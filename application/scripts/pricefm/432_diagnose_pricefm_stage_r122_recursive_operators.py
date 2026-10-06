#!/usr/bin/env python3
"""Bounded, no-refit replay of R122 operators on internal validation only."""

from __future__ import annotations

import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
from statistics import NormalDist
import sys
import tempfile
import time
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import now_utc, sha256_file, write_json
from pricefm_metrics import average_quantile_loss
import pricefm_r122_runtime as RT


SCRIPTS = Path(__file__).resolve().parent


def load_module(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec); sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


AUDIT = load_module("pricefm_r122_frozen_internal_audit", SCRIPTS / "431_closeout_pricefm_stage_r122_internal.py")
RUNNER = load_module("pricefm_r122_frozen_internal_runner", SCRIPTS / "429_run_pricefm_stage_r122_long_memory.py")


def diagnostic_indices(indices: np.ndarray, count: int, maximum: int = 16) -> np.ndarray:
    values = np.asarray(indices, dtype=int)
    AUDIT.require(0 < count <= maximum and len(values) > 0, "invalid bounded diagnostic origin count")
    AUDIT.require(np.all(np.diff(values) > 0), "diagnostic origins must be unique and ordered")
    positions = np.unique(np.linspace(0, len(values) - 1, min(count, len(values))).round().astype(int))
    return values[positions]


def mixture_counterexample() -> dict[str, float]:
    # Quantiles do not commute with mixing, even when the readout is linear.
    q = .9; offset = NormalDist().inv_cdf(q)
    average_conditional_quantile = .5 * ((-5 + offset) + (5 + offset))
    mixed_cdf = .5 * (NormalDist(-5, 1).cdf(average_conditional_quantile)
                      + NormalDist(5, 1).cdf(average_conditional_quantile))
    return {"nominal_quantile": q, "average_conditional_quantile": average_conditional_quantile,
            "mixture_cdf_at_average_conditional_quantile": mixed_cdf}


def cpu_identity(cpu: int) -> tuple[str, str]:
    root = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
    return ((root / "physical_package_id").read_text().strip(), (root / "core_id").read_text().strip())


def cpu_snapshot() -> dict[int, tuple[int, int]]:
    result = {}
    for line in Path("/proc/stat").read_text().splitlines():
        fields = line.split()
        if fields and fields[0].startswith("cpu") and fields[0][3:].isdigit():
            values = [int(x) for x in fields[1:9]]
            result[int(fields[0][3:])] = (sum(values), values[3] + values[4])
    return result


def preflight(cpus: list[int], output_parent: Path, protocol: dict[str, Any]) -> dict[str, Any]:
    for name in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
        AUDIT.require(os.environ.get(name) == "1", f"diagnostic numerical thread cap must be explicit: {name}")
    AUDIT.require(0 < len(cpus) <= protocol["maximum_workers"] and len(set(cpus)) == len(cpus),
                  "invalid diagnostic worker allocation")
    AUDIT.require(set(cpus).issubset(os.sched_getaffinity(0)), "diagnostic CPU outside available affinity")
    identities = [cpu_identity(cpu) for cpu in cpus]
    AUDIT.require(len(set(identities)) == len(cpus), "workers must use distinct physical cores")
    before = cpu_snapshot(); time.sleep(5); after = cpu_snapshot()
    usage = {cpu: 100 * (1 - (after[cpu][1] - before[cpu][1]) / max(1, after[cpu][0] - before[cpu][0]))
             for cpu in before}
    peak = {cpu: max(usage[x] for x in usage if cpu_identity(x) == cpu_identity(cpu)) for cpu in cpus}
    available = next(int(x.split()[1]) / 2**20 for x in Path("/proc/meminfo").read_text().splitlines()
                     if x.startswith("MemAvailable:"))
    free = shutil.disk_usage(output_parent).free / 2**30
    AUDIT.require(max(peak.values()) <= protocol["maximum_selected_core_peak_percent"], "selected physical core is busy")
    AUDIT.require(available >= protocol["minimum_memory_gib"] and free >= protocol["minimum_free_gib"],
                  "diagnostic memory or disk floor failed")
    return {"cpu_list": cpus, "physical_core_peak_percent": peak, "memory_available_gib": available,
            "free_disk_gib": free, "sample_seconds": 5, "numerical_threads_per_worker": 1}


def score_operators(truth: np.ndarray, values: dict[str, np.ndarray]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    rows, horizons = [], []
    for name in ("mean_feature", "path_specific", "normal_driver", "oracle_teacher_forced_history"):
        prediction = values[name]
        AUDIT.require(prediction.shape == (*truth.shape, 7) and np.isfinite(prediction).all(),
                      "invalid diagnostic prediction array")
        rows.append({"operator": name, **RT.prediction_metrics(truth, prediction)})
        for label, selection in (("first_6_hours", slice(0, 24)), ("middle_12_hours", slice(24, 72)),
                                 ("last_6_hours", slice(72, 96))):
            actual, forecast = truth[:, selection], prediction[:, selection]
            horizons.append({
                "operator": name, "horizon_block": label,
                "AQL": average_quantile_loss(actual, forecast, RT.QUANTILES),
                "median_MAE": float(np.mean(np.abs(actual - forecast[:, :, 3]))),
                "interval_80_coverage": float(np.mean((actual >= forecast[:, :, 0]) & (actual <= forecast[:, :, -1]))),
                "interval_80_width": float(np.mean(forecast[:, :, -1] - forecast[:, :, 0])),
                "crossing_rate": float(np.mean(forecast[:, :, :-1] > forecast[:, :, 1:])),
            })
    return rows, horizons


def teacher_forced_quantile_readouts(design: np.ndarray, fits: dict[float, Any], origins: int) -> np.ndarray:
    AUDIT.require(design.ndim == 2 and origins > 0 and design.shape[0] == 96 * origins,
                  "invalid time-major oracle design")
    rows = np.stack([design @ fits[tau]["beta_mean"] for tau in RT.QUANTILES], axis=-1)
    # teacher_forced_design stacks all origins within each horizon, whereas
    # recursive_quantile_forecast returns all horizons within each origin.
    return rows.reshape(96, origins, 7).transpose(1, 0, 2)


def case_job(job: dict[str, Any]) -> dict[str, Any]:
    os.sched_setaffinity(0, {job["cpu"]})
    control = AUDIT.read_json(Path(job["prep"]) / "launch_control.json")
    campaign = Path(job["campaign"]); root = Path(job["output"])
    candidate, split = job["candidate_id"], int(job["split"])
    contract = {k: v for k, v in job.items() if k != "cpu"}
    if root.exists():
        saved = AUDIT.read_json(root / "terminal.json")
        AUDIT.require(saved["contract"] == contract, "existing diagnostic case contract changed")
        for name, expected in saved["output_sha256"].items():
            AUDIT.contract_hash(root / name, expected)
        return saved
    spec = dict(job["spec"]); spec["seed"] = int(RUNNER.RESERVOIR_SEEDS[0])
    arrays = RUNNER._selection_arrays(control, RT.normalize_spec(spec))
    item = RT.internal_splits(len(arrays.response))[split - 1]
    selected = diagnostic_indices(item["validation"], int(job["origin_count"]))
    AUDIT.require(set(selected).isdisjoint(set(item["train"])), "diagnostic origins overlap fit origins")
    scaled, scaler = RT.standardize_from_training_origins(arrays, item["train"])
    ladder = campaign / f"al_internal/{candidate}/split={split}"
    median = AUDIT.read_json(ladder / "contracts/final/tau=0.50.json")
    normal = RT.load_normal_fit(Path(median["parent_dir"]))
    quantile = {tau: RT.load_quantile_fit(ladder / f"quantiles/al/tau={tau:.2f}") for tau in RT.QUANTILES}
    started = time.monotonic()
    forecasts = RT.recursive_quantile_forecast(RT.subset_arrays(scaled, selected), spec, normal, quantile,
                                             int(job["posterior_paths"]), int(RUNNER.RESERVOIR_SEEDS[0]) + split)
    truth = forecasts["truth"] * scaler["price_scale"] + scaler["price_mean"]
    predictions = {name: forecasts[name] * scaler["price_scale"] + scaler["price_mean"]
                   for name in ("mean_feature", "path_specific", "normal_driver")}
    # This control deliberately uses observed preceding target values within
    # the internal validation path. It is never an operational forecast.
    oracle_design, _, _ = RT.teacher_forced_design(RT.subset_arrays(scaled, selected), spec)
    predictions["oracle_teacher_forced_history"] = teacher_forced_quantile_readouts(
        oracle_design, quantile, len(selected),
    ) * scaler["price_scale"] + scaler["price_mean"]
    rows, horizon_rows = score_operators(truth, predictions)
    deterministic = RT.recursive_normal_score(scaled, spec, normal, selected, maximum_origins=None)
    for metric in ("AQL", "late_AQL", "median_MAE", "interval_80_width"):
        deterministic[metric] *= float(scaler["price_scale"])
    rows.append({"operator": "normal_deterministic_mean_recursion", **deterministic})
    difference = predictions["path_specific"] - predictions["mean_feature"]
    root.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=root.name + ".tmp.", dir=root.parent) as temp:
        path = Path(temp)
        np.savez_compressed(path / "matched_predictions.npz", truth=truth, anchors=arrays.anchors[selected],
                            selected_origin_indices=selected, quantiles=np.asarray(RT.QUANTILES), **predictions)
        pd.DataFrame(rows).to_csv(path / "operator_metrics.csv", index=False)
        pd.DataFrame(horizon_rows).to_csv(path / "horizon_metrics.csv", index=False)
        result = {"status": "completed_r122_no_refit_operator_case", "contract": contract,
                  "candidate_id": candidate, "split": split, "origin_count": len(selected),
                  "anchors": arrays.anchors[selected].tolist(), "posterior_paths": job["posterior_paths"],
                  "selected_origin_indices": selected.tolist(), "forecast_seconds": time.monotonic() - started,
                  "path_vs_mean_max_absolute_difference": float(np.max(np.abs(difference))),
                  "path_vs_mean_rms_difference": float(np.sqrt(np.mean(difference**2))),
                  "cpu_affinity": sorted(os.sched_getaffinity(0)), "model_fitted": False,
                  "test_opened": False, "article_mutated": False, "registry_mutated": False,
                  "statistical_interpretation": "averaged_conditional_quantile_readouts_not_marginal_predictive_quantiles",
                  "oracle_history_control_is_not_deployable": True,
                  "oracle_design_order": "horizon_origin_to_origin_horizon",
                  "scaler": scaler, "processed_source_manifest": list(arrays.source_manifest),
                  "output_sha256": {x.name: sha256_file(x) for x in path.iterdir()}}
        write_json(path / "terminal.json", result)
        # Rename, never merge into or overwrite an existing case directory.
        path.rename(root)
    return result


def render_pdf(path: Path, records: list[dict[str, Any]], metrics: pd.DataFrame,
               horizon: pd.DataFrame, winner: str) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    colors = {"mean_feature": "#167d8d", "path_specific": "#98555f", "normal_driver": "#6c8b45",
              "oracle_teacher_forced_history": "#76659e"}
    plt.rcParams.update({"font.size": 9, "axes.spines.top": False, "axes.spines.right": False,
                         "axes.grid": True, "grid.alpha": .18, "pdf.fonttype": 42})
    with PdfPages(path) as pdf:
        fig, axes = plt.subplots(1, 2, figsize=(11.7, 8.3))
        summary = metrics.groupby("operator").agg(AQL=("AQL", "mean"), coverage=("interval_80_coverage", "mean"))
        labels = [str(x).replace("_", "\n") for x in summary.index]
        axes[0].bar(labels, summary.AQL, color="#167d8d"); axes[0].set_ylabel("AQL (processed price units)")
        axes[1].bar(labels, 100 * summary.coverage, color="#6c8b45")
        axes[1].axhline(80, color="#333333", linestyle="--"); axes[1].set_ylim(0, 100)
        axes[1].set_ylabel("Nominal 80% interval coverage (%)")
        fig.suptitle("BG R122: Matched Recursive Operator Diagnostics", fontsize=14)
        fig.text(.06, .09, "Diagnostic subset only: 12 predeclared origins per internal split, 500 paths.\n"
                 "No refits, no new selection, no official validation or test scores.\n"
                 "Oracle history uses future observed prices and is NOT deployable.\n"
                 "Averaged conditional quantiles are not generally marginal predictive quantiles.", fontsize=10)
        fig.tight_layout(rect=(.02, .24, .98, .92)); pdf.savefig(fig); plt.close(fig)
        subset = horizon[horizon.candidate_id.eq(winner)]
        fig, axes = plt.subplots(1, 2, figsize=(11.7, 8.3))
        blocks = ["first_6_hours", "middle_12_hours", "last_6_hours"]
        for name, color in colors.items():
            rows = subset[subset.operator.eq(name)].groupby("horizon_block").mean(numeric_only=True).reindex(blocks)
            axes[0].plot(range(3), rows.AQL, marker="o", color=color, label=name.replace("_", " "))
            axes[1].plot(range(3), 100 * rows.interval_80_coverage, marker="o", color=color)
        for ax in axes: ax.set_xticks(range(3), ["First 6h", "Middle 12h", "Last 6h"])
        axes[0].set_ylabel("AQL"); axes[1].set_ylabel("80% interval coverage (%)")
        axes[1].axhline(80, color="#333333", linestyle="--"); axes[1].set_ylim(0, 100)
        axes[0].legend(fontsize=9)
        fig.suptitle(f"Frozen Winner {winner}: Horizon Profiles on Matched Origins", fontsize=13)
        fig.tight_layout(rect=(.02, .04, .98, .92)); pdf.savefig(fig); plt.close(fig)
        for record in sorted(records, key=lambda x: (x["candidate_id"], x["split"])):
            case = Path(record["contract"]["output"])
            with np.load(case / "matched_predictions.npz") as data:
                fig, axes = plt.subplots(2, 4, figsize=(13.7, 8.3))
                hours = np.arange(1, 97) / 4
                for row, origin in enumerate((0, len(data["anchors"]) - 1)):
                    for column, (name, color) in enumerate(colors.items()):
                        ax = axes[row, column]; values = data[name][origin]
                        ax.fill_between(hours, values[:, 0], values[:, -1], color=color, alpha=.18)
                        ax.plot(hours, values[:, 3], color=color, linewidth=1.2, label="Median")
                        ax.plot(hours, data["truth"][origin], color="#303030", linewidth=1, label="Observed")
                        ax.set_title(f"{name.replace('_', ' ')}\n{str(data['anchors'][origin])[:16]}", fontsize=9)
                        ax.set_xlabel("Hours after daily origin"); ax.set_ylabel("Processed price")
                lo = min(ax.get_ylim()[0] for ax in axes.flat); hi = max(ax.get_ylim()[1] for ax in axes.flat)
                for ax in axes.flat: ax.set_ylim(lo, hi)
                axes[0, 0].legend(fontsize=8)
                fig.suptitle(f"{record['candidate_id']} | Internal Split {record['split']} | First and Last Selected Origins", fontsize=12)
                fig.tight_layout(rect=(.02, .03, .98, .90)); pdf.savefig(fig); plt.close(fig)


def run(args: argparse.Namespace) -> dict[str, Any]:
    campaign, prep, output = args.campaign.resolve(), args.prep.resolve(), args.output.resolve()
    AUDIT.validate_output_root(output, campaign, prep)
    protocol = AUDIT.read_json(args.protocol)
    audit = AUDIT.audit_campaign(campaign, prep, protocol)
    cpus = [int(x) for x in args.cpu_list.split(",")]
    origin_count = int(protocol["diagnostic_origins_per_split"])
    AUDIT.require(protocol["posterior_paths"] == 500 and origin_count <= protocol["maximum_diagnostic_origins_per_split"]
                  and protocol["include_oracle_history_negative_control"] is True,
                  "diagnostic simulation budget changed")
    identity = {"protocol_sha256": sha256_file(args.protocol), "preparation_sha256": sha256_file(prep / "summary.json"),
                "campaign_terminal_sha256": sha256_file(campaign / "terminal.json"),
                "source_sha256": {str(x): sha256_file(x) for x in (Path(__file__), Path(AUDIT.__file__))}}
    if (output / "terminal.json").exists():
        saved = AUDIT.read_json(output / "terminal.json")
        AUDIT.require(saved["identity"] == identity, "completed diagnostic identity changed")
        for name, expected in saved["output_sha256"].items(): AUDIT.contract_hash(output / name, expected)
        AUDIT.verify_ledger(audit["ledger"])
        return saved
    resource = preflight(cpus, output.parent, protocol)
    output.mkdir(parents=True, exist_ok=True)
    with (output / "diagnostic.lock").open("a+") as handle:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("another R122 diagnostic controller owns this output") from error
        if (output / "identity.json").exists():
            AUDIT.require(AUDIT.read_json(output / "identity.json") == identity, "resume identity changed")
        else: write_json(output / "identity.json", identity)
        write_json(output / "preflight.json", resource)
        write_json(output / "running.json", {"pid": os.getpid(), "started_at_utc": now_utc(), "model_fitted": False})
        manifest = AUDIT.read_csv(prep / "candidate_manifest.csv").set_index("candidate_id")
        jobs = []
        for candidate in audit["ranking"].candidate_id:
            spec = json.loads(manifest.loc[candidate, "spec_json"])
            for split in (1, 2, 3):
                jobs.append({"candidate_id": candidate, "split": split, "spec": spec, "campaign": str(campaign),
                             "prep": str(prep), "output": str(output / f"cases/{candidate}/split={split}"),
                             "cpu": cpus[len(jobs) % len(cpus)], "origin_count": origin_count,
                             "posterior_paths": int(protocol["posterior_paths"]), "identity": identity})
        # A process per CPU runs a sequential queue, avoiding simultaneous cases
        # sharing an affinity when resuming or using fewer than nine workers.
        groups = [[job for job in jobs if job["cpu"] == cpu] for cpu in cpus]
        records = []
        with ProcessPoolExecutor(max_workers=len(cpus)) as pool:
            futures = [pool.submit(case_group, group) for group in groups if group]
            for future in as_completed(futures):
                records.extend(future.result())
                write_json(output / "progress.json", {"completed_cases": len(records), "total_cases": len(jobs),
                                                       "updated_at_utc": now_utc(), "model_fitted": False})
        metrics, horizons = [], []
        for record in records:
            case = Path(record["contract"]["output"])
            for destination, name in ((metrics, "operator_metrics.csv"), (horizons, "horizon_metrics.csv")):
                frame = AUDIT.read_csv(case / name)
                frame["candidate_id"] = record["candidate_id"]; frame["split"] = record["split"]
                destination.append(frame)
        metrics_frame = pd.concat(metrics, ignore_index=True); horizon_frame = pd.concat(horizons, ignore_index=True)
        metrics_frame.to_csv(output / "matched_operator_metrics.csv", index=False)
        horizon_frame.to_csv(output / "matched_horizon_metrics.csv", index=False)
        pd.DataFrame([{k: v for k, v in x.items() if k in ("candidate_id", "split", "origin_count", "forecast_seconds",
                          "path_vs_mean_max_absolute_difference", "path_vs_mean_rms_difference")} for x in records]).to_csv(
            output / "operator_difference_audit.csv", index=False)
        write_json(output / "mixture_counterexample.json", mixture_counterexample())
        render_pdf(output / "pricefm_r122_matched_recursive_operator_diagnostics.pdf", records, metrics_frame,
                   horizon_frame, audit["ranking"].iloc[0].candidate_id)
        AUDIT.verify_ledger(audit["ledger"])
        result = {"status": "R122_INTERNAL_OPERATOR_DIAGNOSIS_COMPLETE_NOT_PROMOTED", "identity": identity,
                  "finished_at_utc": now_utc(), "case_count": len(records), "posterior_paths": 500,
                  "origins_per_case": origin_count, "metric_units": protocol["metric_units"],
                  "source_preservation_verified": True, "model_fitted": False, "test_opened": False,
                  "official_validation_opened": False, "article_mutated": False, "registry_mutated": False,
                  "frozen_winner_changed": False, "ready_for_article_promotion": False,
                  "oracle_history_control_is_not_deployable": True,
                  "integration_status": "NOT_READY_FOR_INTEGRATION",
                  "diagnostic_subset_cannot_select_or_reject_a_model": True,
                  "output_sha256": {x.name: sha256_file(x) for x in output.iterdir() if x.is_file() and x.name not in
                                    ("terminal.json", "diagnostic.lock", "running.json")}}
        write_json(output / "terminal.json", result)
        return result


def case_group(jobs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [case_job(job) for job in jobs]


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--campaign", type=Path, required=True)
    value.add_argument("--prep", type=Path, required=True)
    value.add_argument("--output", type=Path, required=True)
    value.add_argument("--protocol", type=Path, default=AUDIT.DEFAULT_PROTOCOL)
    value.add_argument("--cpu-list", required=True)
    return value


if __name__ == "__main__":
    try:
        print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    except Exception as error:
        print(json.dumps({"status": "R122_OPERATOR_DIAGNOSIS_FAILED", "error_type": type(error).__name__,
                          "error": str(error), "model_fitted": False, "test_opened": False}), file=sys.stderr)
        raise
