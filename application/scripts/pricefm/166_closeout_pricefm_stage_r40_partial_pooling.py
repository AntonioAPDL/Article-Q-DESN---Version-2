#!/usr/bin/env python3
"""Close out R39 partial pooling with frozen validation-only gates."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd

from pricefm_common import parse_bool, write_json


DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
DEFAULT_PREP = DATA / "authoritative/pricefm_stage_r39_partial_pooling_launch_prep_20260805"
DEFAULT_GRID = DATA / "experiment_grids/pricefm_stage_r39_partial_pooling_20260805"
DEFAULT_RUNS = DATA / "runs/pricefm_stage_r39_partial_pooling_20260805"
DEFAULT_R37 = DATA / "authoritative/pricefm_stage_r37_nested_horizon_readout_closeout_20260805"
DEFAULT_OUTPUT = DATA / "authoritative/pricefm_stage_r40_partial_pooling_closeout_20260806"
BLOCKS = ["1-24", "25-48", "49-72", "73-96"]
SHARED = "qdesn_al_rhs_ns_exact_chunked"
SEPARATE = SHARED + "_horizon_separate"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--prep-dir", type=Path, default=DEFAULT_PREP)
    p.add_argument("--grid-root", type=Path, default=DEFAULT_GRID)
    p.add_argument("--run-root", type=Path, default=DEFAULT_RUNS)
    p.add_argument("--stage-r37-dir", type=Path, default=DEFAULT_R37)
    p.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    p.add_argument("--expected-cases", type=int, default=11)
    p.add_argument("--harm-margin", type=float, default=0.005)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def boolish(value) -> bool:
    return str(value).strip().lower() in {"true", "1", "yes", "completed"}


def model_dir(root: Path, row) -> Path:
    return root / str(row.id) / "cells" / f"region={row.region}" / f"fold={int(row.fold)}" / "model"


def adapter_dir(root: Path, row) -> Path:
    return root / str(row.id) / "cells" / f"region={row.region}" / f"fold={int(row.fold)}" / "adapter"


def select_block(metrics: pd.DataFrame, convergence: pd.DataFrame, block: str, harm_margin: float) -> dict:
    group = metrics[metrics["horizon_group"].astype(str).eq(block)].copy()
    conv = convergence[convergence["horizon_group"].astype(str).eq(block)]
    shared_ok = bool(group["shared_converged"].map(boolish).all())
    separate_ok = bool(conv["converged"].map(boolish).all())
    stats = group.groupby("separate_weight")["AQL_scaled"].agg(["median", "std", "count"]).reset_index()
    stats["standard_error"] = stats["std"] / np.sqrt(stats["count"])
    stats["eligible"] = shared_ok & ((stats["separate_weight"].eq(0)) | separate_ok)
    eligible = stats[stats["eligible"]]
    if eligible.empty:
        raise RuntimeError(f"No eligible pooling weight for {block}")
    raw = eligible.loc[eligible["median"].idxmin()]
    threshold = float(raw["median"] + raw["standard_error"])
    selected = eligible[eligible["median"].le(threshold + 1e-15)].sort_values("separate_weight").iloc[0]
    weight = float(selected["separate_weight"])
    paired = group[group["separate_weight"].eq(weight)][["inner_fold", "AQL_scaled"]].merge(
        group[group["separate_weight"].eq(0)][["inner_fold", "AQL_scaled"]],
        on="inner_fold", suffixes=("_selected", "_shared"),
    )
    relative = paired["AQL_scaled_selected"] / paired["AQL_scaled_shared"] - 1.0
    return {
        "horizon_group": block,
        "raw_best_weight": float(raw["separate_weight"]),
        "raw_best_median_AQL_scaled": float(raw["median"]),
        "raw_best_standard_error": float(raw["standard_error"]),
        "one_se_threshold": threshold,
        "selected_weight": weight,
        "selected_median_AQL_scaled": float(selected["median"]),
        "shared_all_folds_converged": shared_ok,
        "separate_all_folds_converged": separate_ok,
        "selected_convergence_pass": shared_ok and (weight == 0 or separate_ok),
        "max_relative_harm": float(relative.max()),
        "harm_guard_pass": bool(relative.le(harm_margin + 1e-12).all()),
    }


def pooled_outer(model: Path, adapter: Path, weights: dict[str, float]) -> tuple[float, float, float]:
    predictions = pd.read_csv(model / "model_predictions_scaled.csv")
    observed = pd.read_csv(adapter / "rows_val.csv")[["origin_id", "horizon", "y_scaled"]]
    shared = predictions[predictions["method_id"].eq(SHARED)]
    separate = predictions[predictions["method_id"].eq(SEPARATE)]
    paired = shared.merge(separate, on=["split", "origin_id", "horizon", "tau"], suffixes=("_shared", "_separate")).merge(observed, on=["origin_id", "horizon"])
    paired["horizon_group"] = pd.cut(paired["horizon"], [0, 24, 48, 72, 96], labels=BLOCKS)
    paired["weight"] = paired["horizon_group"].map(weights).astype(float)
    paired["pooled"] = paired["pred_scaled_shared"] * (1 - paired["weight"]) + paired["pred_scaled_separate"] * paired["weight"]
    aql = lambda pred: float(np.mean(0.5 * np.abs(paired["y_scaled"] - pred)))
    return aql(paired["pooled"]), aql(paired["pred_scaled_shared"]), aql(paired["pred_scaled_separate"])


def run(args: argparse.Namespace) -> dict:
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(f"Output exists; use --force true: {output}")
    output.mkdir(parents=True, exist_ok=True)
    manifest_path = args.prep_dir / "pricefm_stage_r39_launch_manifest.csv"
    status_path = args.grid_root / "launch_status.csv"
    r37_path = args.stage_r37_dir / "pricefm_stage_r37_case_closeout.csv"
    manifest, status, r37 = pd.read_csv(manifest_path), pd.read_csv(status_path), pd.read_csv(r37_path)
    complete = status["status"].eq("completed") & status["return_code"].eq(0)
    gates = [
        ("expected_cases", len(manifest) == args.expected_cases, len(manifest)),
        ("unique_cases", manifest["id"].nunique() == args.expected_cases, manifest["id"].nunique()),
        ("completed_zero_exit", len(status) == args.expected_cases and bool(complete.all()), int(complete.sum())),
        ("test_quarantined", bool(manifest["test_metrics_role"].eq("quarantined_not_loaded").all()), "validation only"),
    ]
    completion = pd.DataFrame(gates, columns=["gate", "passed", "observed"])
    completion.to_csv(output / "pricefm_stage_r40_completion_audit.csv", index=False)
    if not completion["passed"].all():
        raise RuntimeError("R39 completion gates failed")
    r37_index = r37.assign(key=r37["experiment_id"].str.replace("r36_", "", regex=False)).set_index("key")
    block_rows, case_rows, sources = [], [], [manifest_path, status_path, r37_path, Path(__file__).resolve()]
    for row in manifest.itertuples(index=False):
        model, adapter = model_dir(args.run_root, row), adapter_dir(args.run_root, row)
        metric_path, conv_path = model / "nested_partial_pooling_metrics.csv", model / "nested_partial_pooling_convergence.csv"
        metrics, convergence = pd.read_csv(metric_path), pd.read_csv(conv_path)
        if set(metrics["likelihood_family"]) != {"al"} or set(metrics["tau"].astype(float)) != {0.5}:
            raise ValueError(f"Unexpected R39 likelihood surface: {row.id}")
        selected = []
        for block in BLOCKS:
            result = select_block(metrics, convergence, block, args.harm_margin)
            block_rows.append({"experiment_id": row.id, "region": row.region, "fold": int(row.fold), **result})
            selected.append(result)
        weights = {item["horizon_group"]: item["selected_weight"] for item in selected}
        pooled_scaled, shared_scaled, separate_scaled = pooled_outer(model, adapter, weights)
        summary = pd.read_csv(model / "metric_summary.csv")
        if set(summary["split"]) != {"val"}:
            raise ValueError(f"Test quarantine violated: {row.id}")
        shared_original = float(summary[(summary["method_id"].eq(SHARED)) & (summary["unit"].eq("original"))]["AQL"].iloc[0])
        scale = shared_original / shared_scaled
        key = str(row.id).replace("r39_", "", 1)
        anchor = r37_index.loc[key]
        pooled_original = pooled_scaled * scale
        convergence_pass = all(item["selected_convergence_pass"] for item in selected)
        harm_pass = all(item["harm_guard_pass"] for item in selected)
        improves_shared = pooled_original < shared_original - 1e-12
        improves_r34 = pooled_original < float(anchor["r34_anchor_val_AQL"]) - 1e-12
        eligible = convergence_pass and harm_pass and improves_shared and improves_r34
        case_rows.append({
            "experiment_id": row.id, "region": row.region, "fold": int(row.fold),
            "source_r34_experiment_id": anchor["source_r34_experiment_id"],
            "source_r34_selected_method": anchor["source_r34_selected_method"],
            **{f"weight_{block.replace('-', '_')}": weights[block] for block in BLOCKS},
            "selected_convergence_pass": convergence_pass, "harm_guard_pass": harm_pass,
            "pooled_outer_val_AQL": pooled_original, "shared_outer_val_AQL": shared_original,
            "separate_outer_val_AQL": separate_scaled * scale,
            "r34_anchor_val_AQL": float(anchor["r34_anchor_val_AQL"]),
            "pooled_minus_shared": pooled_original - shared_original,
            "pooled_minus_r34_anchor": pooled_original - float(anchor["r34_anchor_val_AQL"]),
            "outer_improves_paired_shared": improves_shared, "outer_improves_r34_anchor": improves_r34,
            "full_quantile_confirmation_eligible": eligible,
            "decision": "eligible_for_full_quantile_confirmation" if eligible else "blocked_r39_promotion_gate",
            "test_inspected": False, "registry_mutation_authorized": False,
            "article_mutation_authorized": False, "mcmc_authorized": False,
        })
        sources.extend([metric_path, conv_path, model / "metric_summary.csv", model / "model_predictions_scaled.csv", adapter / "rows_val.csv"])
    blocks, cases = pd.DataFrame(block_rows), pd.DataFrame(case_rows).sort_values(["region", "fold"])
    failures = blocks[~blocks["separate_all_folds_converged"]].copy()
    queue = cases[cases["full_quantile_confirmation_eligible"]].copy()
    blocks.to_csv(output / "pricefm_stage_r40_block_selection.csv", index=False)
    cases.to_csv(output / "pricefm_stage_r40_case_closeout.csv", index=False)
    failures.to_csv(output / "pricefm_stage_r40_convergence_failures.csv", index=False)
    queue.to_csv(output / "pricefm_stage_r40_full_quantile_confirmation_queue.csv", index=False)
    pd.DataFrame([{"path": str(p.resolve()), "sha256": sha256(p), "bytes": p.stat().st_size} for p in dict.fromkeys(sources)]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "completed_read_only_no_confirmation_candidates" if queue.empty else "completed_candidates_queued",
        "cases": len(cases), "experiments_completed": int(complete.sum()), "experiments_remaining": 0,
        "selected_shared_blocks": int(blocks["selected_weight"].eq(0).sum()),
        "selected_partial_blocks": int(blocks["selected_weight"].between(0, 1, inclusive="neither").sum()),
        "selected_separate_blocks": int(blocks["selected_weight"].eq(1).sum()),
        "cases_improving_shared": int(cases["outer_improves_paired_shared"].sum()),
        "cases_improving_r34": int(cases["outer_improves_r34_anchor"].sum()),
        "harm_guard_cases": int(cases["harm_guard_pass"].sum()),
        "full_quantile_candidates": len(queue), "test_inspected": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False, "mcmc_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r40_partial_pooling_closeout_report.md").write_text(
        "# PriceFM Stage-R40 Partial-Pooling Closeout\n\n"
        f"R39 completed {len(cases)}/{len(cases)} cases. The frozen one-standard-error rule selected "
        f"{summary['selected_shared_blocks']} shared and {summary['selected_partial_blocks']} partially pooled blocks. "
        f"{summary['cases_improving_shared']} cases improved over paired shared R36, "
        f"{summary['cases_improving_r34']} improved over R34, and {len(queue)} passed all promotion gates.\n\n"
        "Test, registry, article, full-quantile, and MCMC actions remain blocked.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
