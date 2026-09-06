#!/usr/bin/env python3
"""Close out the completed R69B/R72 PriceFM AL validation surface.

R73 reconstructs the seven-quantile AL candidate for every case from immutable,
hash-checked R69B atoms and their exact R72 missing-atom replacements.  It reads
validation data only and cannot launch work or mutate article/registry state.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
from typing import Any

import joblib
import numpy as np
import pandas as pd
import yaml


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R69B_TAG = "pricefm_stage_r69b_bounded_cran111_independent_vb_20260831"
R72_TAG = "pricefm_stage_r72_missing_al_repair_20260901"
R69B_GRID = DATA / "experiment_grids" / R69B_TAG
R71_DIR = DATA / "authoritative/pricefm_stage_r71_r70_closeout_20260901"
R72_GRID = DATA / "experiment_grids" / R72_TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r73_completed_al_surface_20260902"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r69b-manifest", type=Path, default=R69B_GRID / "case_manifest.csv")
    p.add_argument("--r71-dir", type=Path, default=R71_DIR)
    p.add_argument("--r72-manifest", type=Path, default=R72_GRID / "task_manifest.csv")
    p.add_argument("--r72-status", type=Path, default=R72_GRID / "launch_status.csv")
    p.add_argument("--r72-launch-summary", type=Path, default=R72_GRID / "launch_summary.json")
    p.add_argument("--r72-monitor", type=Path, default=R72_GRID / "monitor_latest.json")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cases", type=int, default=56)
    p.add_argument("--expected-atoms", type=int, default=392)
    p.add_argument("--expected-r69b-atoms", type=int, default=250)
    p.add_argument("--expected-r72-atoms", type=int, default=142)
    p.add_argument("--force", action="store_true")
    return p


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def tau_slug(tau: float) -> str:
    return f"{tau:.12f}".rstrip("0").rstrip(".").replace(".", "p")


def require_file(path: Path, label: str) -> Path:
    if not path.is_file():
        raise FileNotFoundError(f"Missing {label}: {path}")
    return path


def one_row(path: Path) -> dict[str, Any]:
    frame = pd.read_csv(path)
    if len(frame) != 1:
        raise RuntimeError(f"Expected one row in {path}, observed {len(frame)}")
    return frame.iloc[0].to_dict()


def load_scale(data_config: Path, fold: int, region: str) -> tuple[float, float, Path]:
    config = yaml.safe_load(require_file(data_config, "data config").read_text())
    processed = Path(config["pricefm"]["processed_dir"])
    scaler_path = processed / "scalers" / f"fold_{fold}" / "per_region_separate_xy_scalers.joblib"
    scalers = joblib.load(require_file(scaler_path, "target scaler"))
    scaler = scalers[region]["y_scaler"]
    center = float(np.asarray(scaler.center_).reshape(-1)[0])
    scale = float(np.asarray(scaler.scale_).reshape(-1)[0])
    if not np.isfinite(center) or not np.isfinite(scale) or scale <= 0:
        raise RuntimeError(f"Invalid target scaler for {region} fold {fold}")
    return center, scale, scaler_path


def check_prediction(path: Path, tau: float) -> pd.DataFrame:
    pred = pd.read_csv(require_file(path, "prediction artifact"))
    required = {"split", "origin_id", "horizon", "tau", "pred_scaled"}
    if not required.issubset(pred.columns):
        raise RuntimeError(f"Prediction schema is incomplete: {path}")
    if set(pred["split"].astype(str)) != {"val"}:
        raise RuntimeError(f"Non-validation prediction found: {path}")
    observed_tau = pd.to_numeric(pred["tau"], errors="coerce")
    values = pd.to_numeric(pred["pred_scaled"], errors="coerce")
    if not np.allclose(observed_tau, tau) or not np.isfinite(values).all():
        raise RuntimeError(f"Invalid tau or prediction values: {path}")
    if pred.duplicated(["origin_id", "horizon"]).any():
        raise RuntimeError(f"Duplicate prediction keys: {path}")
    return pred[["origin_id", "horizon", "tau", "pred_scaled"]].copy()


def resolve_r69b_atom(atom: Any) -> dict[str, Any]:
    component = Path(atom.component_dir)
    prediction = require_file(component / "al_predictions_scaled.csv", "R69B AL prediction")
    method = require_file(component / "al_method_summary.csv", "R69B AL method summary")
    parameter = require_file(component / "al_parameter_summary.csv", "R69B AL parameter summary")
    terminal_path = require_file(component / "component_terminal.json", "R69B terminal")
    terminal = json.loads(terminal_path.read_text())
    expected_hash = str(terminal.get("al_prediction_sha256", ""))
    if not expected_hash or sha256(prediction) != expected_hash:
        raise RuntimeError(f"R69B prediction hash mismatch: {prediction}")
    return {
        "source_stage": "R69B", "prediction": prediction, "method": method,
        "parameter": parameter, "terminal": terminal_path,
    }


def resolve_r72_atom(task: Any, status: dict[str, Any]) -> dict[str, Any]:
    if status.get("status") != "completed" or int(status.get("returncode", -1)) != 0:
        raise RuntimeError(f"R72 task is not completed: {task.task_id}")
    output = Path(task.output_dir)
    paths = {
        "prediction": require_file(output / "predictions_scaled.csv", "R72 AL prediction"),
        "method": require_file(output / "method_summary.csv", "R72 AL method summary"),
        "parameter": require_file(output / "parameter_summary.csv", "R72 AL parameter summary"),
        "terminal": require_file(output / "terminal.json", "R72 terminal"),
    }
    terminal = json.loads(paths["terminal"].read_text())
    if terminal.get("status") != "completed" or bool(terminal.get("test_loaded")):
        raise RuntimeError(f"Invalid R72 terminal: {paths['terminal']}")
    hashes = terminal.get("artifact_sha256") or {}
    for name in ("predictions_scaled.csv", "method_summary.csv", "parameter_summary.csv"):
        path = output / name
        if hashes.get(name) != sha256(path):
            raise RuntimeError(f"R72 artifact hash mismatch: {path}")
    return {"source_stage": "R72", **paths}


def atom_inventory(
    cases: pd.DataFrame, salvage: pd.DataFrame, r72: pd.DataFrame, statuses: pd.DataFrame,
) -> tuple[pd.DataFrame, dict[tuple[str, float], dict[str, Any]]]:
    al = salvage[salvage["likelihood_family"].eq("al")].copy()
    al["tau_key"] = al["tau"].astype(float).round(12)
    r72 = r72.copy()
    r72["tau_key"] = r72["tau"].astype(float).round(12)
    if al.duplicated(["case_id", "tau_key"]).any() or r72.duplicated(["case_id", "tau_key"]).any():
        raise RuntimeError("Duplicate AL atom identifiers")
    status_by_task = statuses.set_index("task_id").to_dict("index")
    salvage_by_key = al.set_index(["case_id", "tau_key"])
    r72_by_key = r72.set_index(["case_id", "tau_key"])
    resolved: dict[tuple[str, float], dict[str, Any]] = {}
    rows: list[dict[str, Any]] = []
    for case in cases.itertuples(index=False):
        for tau in TAUS:
            key = (case.case_id, round(tau, 12))
            if key not in salvage_by_key.index:
                raise RuntimeError(f"R71 is missing AL atom {key}")
            atom = salvage_by_key.loc[key]
            disposition = str(atom.disposition)
            if disposition == "reuse_r70_al_validation_artifact":
                source = resolve_r69b_atom(atom)
            elif disposition in {"missing_requires_r72_refit", "invalid_requires_r72_refit"}:
                if key not in r72_by_key.index:
                    raise RuntimeError(f"R72 is missing replacement atom {key}")
                task = r72_by_key.loc[key]
                source = resolve_r72_atom(task, status_by_task[str(task.task_id)])
            else:
                raise RuntimeError(f"Unsupported AL disposition for {key}: {disposition}")
            method = one_row(source["method"])
            parameter = one_row(source["parameter"])
            prediction = check_prediction(source["prediction"], tau)
            resolved[key] = {**source, "predictions": prediction}
            rows.append({
                "case_id": case.case_id, "region": case.region, "fold": int(case.fold),
                "tau": tau, "source_stage": source["source_stage"],
                "source_disposition": disposition,
                "method_id": str(method.get("method_id", "")),
                "converged": boolish(method.get("converged")),
                "iter": int(float(method.get("iter", 0))),
                "train_seconds": float(method.get("train_seconds", np.nan)),
                "sigma": float(parameter.get("sigma", np.nan)),
                "prediction_rows": int(len(prediction)),
                "prediction_path": str(source["prediction"]),
                "prediction_sha256": sha256(source["prediction"]),
                "method_path": str(source["method"]),
                "method_sha256": sha256(source["method"]),
                "parameter_path": str(source["parameter"]),
                "parameter_sha256": sha256(source["parameter"]),
                "terminal_path": str(source["terminal"]),
                "terminal_sha256": sha256(source["terminal"]),
                "test_opened": False,
            })
    return pd.DataFrame(rows).sort_values(["region", "fold", "tau"]), resolved


def pinball(y: np.ndarray, pred: np.ndarray, tau: float) -> np.ndarray:
    error = y - pred
    return np.maximum(tau * error, (tau - 1.0) * error)


def evaluate_case(case: Any, sources: dict[tuple[str, float], dict[str, Any]]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    adapter = Path(case.adapter_dir)
    if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
        raise RuntimeError(f"Test artifact is present in validation adapter: {adapter}")
    truth = pd.read_csv(require_file(adapter / "rows_val.csv", "validation row ledger"))
    required_truth = {"origin_id", "horizon", "y_scaled"}
    if not required_truth.issubset(truth.columns) or truth.duplicated(["origin_id", "horizon"]).any():
        raise RuntimeError(f"Invalid validation truth ledger: {adapter}")
    truth = truth[["origin_id", "horizon", "y_scaled"]].copy()
    truth["y_scaled"] = pd.to_numeric(truth["y_scaled"], errors="coerce")
    if not np.isfinite(truth["y_scaled"]).all():
        raise RuntimeError(f"Non-finite validation truth: {adapter}")
    wide = truth.copy()
    for tau in TAUS:
        pred = sources[(case.case_id, round(tau, 12))]["predictions"].drop(columns="tau")
        pred = pred.rename(columns={"pred_scaled": f"q_{tau:g}"})
        wide = wide.merge(pred, on=["origin_id", "horizon"], how="left", validate="one_to_one")
    pred_matrix = wide[[f"q_{tau:g}" for tau in TAUS]].to_numpy(float)
    if pred_matrix.shape != (len(truth), len(TAUS)) or not np.isfinite(pred_matrix).all():
        raise RuntimeError(f"Incomplete seven-quantile surface: {case.case_id}")
    y = wide["y_scaled"].to_numpy(float)
    _, scale, scaler_path = load_scale(Path(case.data_config), int(case.fold), str(case.region))
    losses = np.column_stack([pinball(y, pred_matrix[:, i], tau) for i, tau in enumerate(TAUS)])
    crossings = pred_matrix[:, :-1] > pred_matrix[:, 1:]
    crossing_size = np.maximum(pred_matrix[:, :-1] - pred_matrix[:, 1:], 0.0)
    quantile_rows = []
    for index, tau in enumerate(TAUS):
        quantile_rows.append({
            "case_id": case.case_id, "region": case.region, "fold": int(case.fold),
            "tau": tau, "n_validation_rows": int(len(y)),
            "empirical_coverage": float(np.mean(y <= pred_matrix[:, index])),
            "coverage_error": float(np.mean(y <= pred_matrix[:, index]) - tau),
            "validation_quantile_loss_scaled": float(losses[:, index].mean()),
            "validation_quantile_loss_original": float(losses[:, index].mean() * scale),
            "test_opened": False,
        })
    candidate = float(losses.mean() * scale)
    prior = float(case.r69a_validation_AQL_recomputed)
    operational = prior - float(case.qdesn_minus_operational_pricefm_AQL)
    cached = prior - float(case.qdesn_minus_cached_pricefm_AQL)
    all_converged = all(
        boolish(one_row(sources[(case.case_id, round(tau, 12))]["method"]).get("converged"))
        for tau in TAUS
    )
    performance_gate = candidate < prior and candidate < operational
    promotion = performance_gate and all_converged
    return {
        "case_id": case.case_id, "region": case.region, "fold": int(case.fold),
        "selected_family_anchor": case.selected_family_anchor,
        "validation_rows": int(len(y)), "validation_AQL": candidate,
        "prior_authoritative_qdesn_validation_AQL": prior,
        "operational_pricefm_validation_AQL": operational,
        "cached_pricefm_validation_AQL": cached,
        "delta_vs_prior_authoritative_qdesn": candidate - prior,
        "delta_vs_operational_pricefm": candidate - operational,
        "delta_vs_cached_pricefm": candidate - cached,
        "beats_prior_authoritative_qdesn": candidate < prior,
        "beats_operational_pricefm": candidate < operational,
        "beats_cached_pricefm": candidate < cached,
        "all_seven_quantiles_converged": all_converged,
        "adjacent_crossing_rate": float(crossings.mean()),
        "row_any_crossing_rate": float(crossings.any(axis=1).mean()),
        "max_crossing_original": float(crossing_size.max(initial=0.0) * scale),
        "performance_gate_passed": performance_gate,
        "passes_validation_promotion_gate": promotion,
        "decision": "promotion_queue" if promotion else "blocked_validation_or_integrity_gate",
        "scaler_path": str(scaler_path), "scaler_sha256": sha256(scaler_path),
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    }, quantile_rows


def run(args: argparse.Namespace) -> dict[str, Any]:
    cases = pd.read_csv(args.r69b_manifest)
    salvage = pd.read_csv(args.r71_dir / "pricefm_stage_r71_atomic_fit_salvage_ledger.csv")
    r71_summary = json.loads((args.r71_dir / "pricefm_stage_r71_closeout_summary.json").read_text())
    r72 = pd.read_csv(args.r72_manifest)
    statuses = pd.read_csv(args.r72_status)
    launch_summary = json.loads(args.r72_launch_summary.read_text())
    monitor = json.loads(args.r72_monitor.read_text()) if args.r72_monitor.is_file() else {}
    if len(cases) != args.expected_cases or cases["case_id"].duplicated().any():
        raise RuntimeError("Unexpected or duplicate R69B case surface")
    if any(cases[name].map(boolish).any() for name in BLOCKED):
        raise RuntimeError("R69B firewall declarations are not all false")
    if r71_summary.get("status") != "r70_frozen_closed_out_no_promotion":
        raise RuntimeError("R71 is not a frozen closeout")
    if launch_summary.get("status") != "completed" or int(launch_summary.get("failed", -1)) != 0:
        raise RuntimeError("R72 launch did not complete cleanly")
    if len(r72) != args.expected_r72_atoms or len(statuses) != args.expected_r72_atoms:
        raise RuntimeError("Unexpected R72 task/status count")

    atoms, sources = atom_inventory(cases, salvage, r72, statuses)
    if len(atoms) != args.expected_atoms:
        raise RuntimeError(f"Expected {args.expected_atoms} AL atoms, observed {len(atoms)}")
    source_counts = atoms["source_stage"].value_counts().to_dict()
    if source_counts.get("R69B", 0) != args.expected_r69b_atoms or source_counts.get("R72", 0) != args.expected_r72_atoms:
        raise RuntimeError(f"Unexpected source partition: {source_counts}")

    case_rows: list[dict[str, Any]] = []
    quantile_rows: list[dict[str, Any]] = []
    for case in cases.sort_values(["region", "fold"]).itertuples(index=False):
        case_result, quantile_result = evaluate_case(case, sources)
        case_rows.append(case_result)
        quantile_rows.extend(quantile_result)
    metrics = pd.DataFrame(case_rows).sort_values(["region", "fold"])
    calibration = pd.DataFrame(quantile_rows).sort_values(["region", "fold", "tau"])
    aggregate = calibration.groupby("tau", as_index=False).agg(
        validation_rows=("n_validation_rows", "sum"),
        mean_case_empirical_coverage=("empirical_coverage", "mean"),
        mean_case_coverage_error=("coverage_error", "mean"),
        mean_case_quantile_loss_original=("validation_quantile_loss_original", "mean"),
    )
    aggregate["target_coverage"] = aggregate["tau"]
    aggregate["test_opened"] = False
    queue = metrics[metrics["passes_validation_promotion_gate"]].copy()
    gates = pd.DataFrame([
        {"gate": "exact_case_count", "passed": len(metrics) == args.expected_cases, "observed": len(metrics)},
        {"gate": "exact_case_quantile_atoms", "passed": len(atoms) == args.expected_atoms, "observed": len(atoms)},
        {"gate": "r69b_r72_partition", "passed": source_counts == {"R69B": args.expected_r69b_atoms, "R72": args.expected_r72_atoms}, "observed": json.dumps(source_counts, sort_keys=True)},
        {"gate": "all_artifacts_hash_verified", "passed": True, "observed": len(atoms)},
        {"gate": "r72_terminal_clean", "passed": True, "observed": f"{len(statuses)} completed; 0 failed"},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
        {"gate": "no_automatic_launch", "passed": True, "observed": "R73 has no launcher"},
    ])
    if not gates["passed"].all():
        raise RuntimeError("R73 closeout gates failed")

    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    atoms.to_csv(output / "pricefm_stage_r73_al_atom_ledger.csv", index=False)
    metrics.to_csv(output / "pricefm_stage_r73_case_validation_metrics.csv", index=False)
    calibration.to_csv(output / "pricefm_stage_r73_case_quantile_calibration.csv", index=False)
    aggregate.to_csv(output / "pricefm_stage_r73_aggregate_quantile_calibration.csv", index=False)
    queue.to_csv(output / "pricefm_stage_r73_validation_promotion_queue.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r73_closeout_gates.csv", index=False)

    fixed_sources = [
        Path(__file__).resolve(), args.r69b_manifest.resolve(),
        (args.r71_dir / "pricefm_stage_r71_atomic_fit_salvage_ledger.csv").resolve(),
        (args.r71_dir / "pricefm_stage_r71_closeout_summary.json").resolve(),
        args.r72_manifest.resolve(), args.r72_status.resolve(),
        args.r72_launch_summary.resolve(),
    ]
    if args.r72_monitor.is_file():
        fixed_sources.append(args.r72_monitor.resolve())
    artifact_sources = []
    for row in atoms.itertuples(index=False):
        artifact_sources.extend(map(Path, (
            row.prediction_path, row.method_path, row.parameter_path, row.terminal_path,
        )))
    for row in metrics.itertuples(index=False):
        artifact_sources.extend((Path(row.scaler_path), Path(cases.set_index("case_id").loc[row.case_id, "adapter_dir"]) / "rows_val.csv"))
    unique_sources = list(dict.fromkeys(path.resolve() for path in fixed_sources + artifact_sources))
    pd.DataFrame([
        {"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in unique_sources
    ]).to_csv(output / "source_manifest.csv", index=False)

    summary = {
        "status": "completed_al_surface_closed_out_no_automatic_promotion",
        "cases": int(len(metrics)), "al_atoms": int(len(atoms)),
        "r69b_atoms_reused": int(source_counts.get("R69B", 0)),
        "r72_atoms_repaired": int(source_counts.get("R72", 0)),
        "r72_tasks_completed": int(len(statuses)), "r72_tasks_failed": 0,
        "r72_stale_monitor_detected": bool(monitor.get("state") == "running"),
        "converged_atoms": int(atoms["converged"].sum()),
        "all_seven_converged_cases": int(metrics["all_seven_quantiles_converged"].sum()),
        "mean_validation_AQL": float(metrics["validation_AQL"].mean()),
        "mean_prior_authoritative_qdesn_AQL": float(metrics["prior_authoritative_qdesn_validation_AQL"].mean()),
        "mean_operational_pricefm_AQL": float(metrics["operational_pricefm_validation_AQL"].mean()),
        "mean_cached_pricefm_AQL": float(metrics["cached_pricefm_validation_AQL"].mean()),
        "beats_prior_authoritative_qdesn_cases": int(metrics["beats_prior_authoritative_qdesn"].sum()),
        "beats_operational_pricefm_cases": int(metrics["beats_operational_pricefm"].sum()),
        "beats_cached_pricefm_cases": int(metrics["beats_cached_pricefm"].sum()),
        "validation_promotion_candidates": int(len(queue)),
        "mean_row_any_crossing_rate": float(metrics["row_any_crossing_rate"].mean()),
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
        "launch_yaml_written": False, "launch_authorized": False,
        "recommended_next_action": "run_r74_no_refit_feasibility_and_repair_large_n_structured_exal_before_any_broad_refit",
    }
    write_json(output / "summary.json", summary)
    report = f"""# PriceFM Stage-R73 Completed AL Surface Closeout

R73 reconstructs all {len(atoms)} validation-only AL atoms for {len(metrics)}
region/fold cases: {source_counts.get('R69B', 0)} immutable R69B atoms and
{source_counts.get('R72', 0)} hash-verified R72 replacements. The R72 launch is
terminal ({len(statuses)} completed, zero failed). Its older monitor snapshot is
stale and is not used as completion authority.

Mean validation AQL is {summary['mean_validation_AQL']:.6f}, versus
{summary['mean_prior_authoritative_qdesn_AQL']:.6f} for the current Q-DESN
authority and {summary['mean_operational_pricefm_AQL']:.6f} for operational
PriceFM. The candidate beats current Q-DESN in
{summary['beats_prior_authoritative_qdesn_cases']}/{len(metrics)} cases and
operational PriceFM in {summary['beats_operational_pricefm_cases']}/{len(metrics)}.
Only {summary['all_seven_converged_cases']} cases converged at all seven quantiles.

The full validation-and-integrity gate admits {len(queue)} promotion candidates.
No test data were opened, and no launch, registry, article, joint-model, or MCMC
action is authorized by this closeout.
"""
    (output / "pricefm_stage_r73_closeout_report.md").write_text(report)
    if list(output.rglob("*.yaml")) or list(output.rglob("*.yml")):
        raise RuntimeError("R73 must not produce launch YAML")
    if any(path.suffix in BINARY_SUFFIXES for path in output.rglob("*") if path.is_file()):
        raise RuntimeError("R73 must not produce binary model artifacts")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
