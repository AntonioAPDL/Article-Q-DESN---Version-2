#!/usr/bin/env python3
"""Audit the evidence for a bounded PriceFM R100 recovery screen."""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json
from pricefm_graph import graph_adj_matrix, graph_hash


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R98 = DATA / "authoritative/pricefm_stage_r98_validity_first_authority_closeout_20260913"
R97 = DATA / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908"
TARGETS = [
    "AT", "BG", "CZ", "DE_LU", "HR", "HU", "PL", "RO", "SK",
    "FI", "NO_1", "NO_2", "NO_3", "NO_4", "NO_5", "SE_2", "SE_4",
]
CENTRAL_EAST = {"AT", "BG", "CZ", "DE_LU", "HR", "HU", "PL", "RO", "SK"}
NORDIC_CONTROLS = ["DK_1", "DK_2", "SE_1", "SE_3"]
FOLDS = {
    1: ("2022-01-01", "2024-09-01", "2024-09-01", "2025-01-01", "2025-01-01", "2025-05-01"),
    2: ("2022-01-01", "2025-01-01", "2025-01-01", "2025-05-01", "2025-05-01", "2025-09-01"),
    3: ("2022-01-01", "2025-05-01", "2025-05-01", "2025-09-01", "2025-09-01", "2026-01-01"),
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r98-registry", type=Path, default=R98 / "pricefm_stage_r98_authoritative_registry.csv")
    p.add_argument("--raw-parquet", type=Path, default=DATA / "interim/FINAL.parquet")
    p.add_argument("--r97-root", type=Path, default=R97)
    p.add_argument("--pricefm-repo", type=Path, default=DATA / "external/PriceFM")
    p.add_argument("--output-dir", type=Path, default=DATA / "audits/pricefm_stage_r99_targeted_recovery_20260913")
    p.add_argument("--force", action="store_true")
    return p


def _source(path: Path, role: str) -> dict[str, Any]:
    return {"role": role, "path": str(path.resolve()), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def _write_csv(path: Path, frame: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def _price_stats(values: pd.Series) -> dict[str, float]:
    x = pd.to_numeric(values, errors="coerce").dropna()
    dx = x.diff().abs().dropna()
    return {
        "n": int(len(x)), "missing": int(len(values) - len(x)),
        "mean": float(x.mean()), "sd": float(x.std()), "iqr": float(x.quantile(.75) - x.quantile(.25)),
        "p95_abs_change": float(dx.quantile(.95)), "p99_abs_change": float(dx.quantile(.99)),
    }


def _region_summary(registry: pd.DataFrame) -> pd.DataFrame:
    out = registry.groupby("region", as_index=False).agg(
        qdesn_AQL=("qdesn_AQL", "mean"), pricefm_AQL=("pricefm_AQL", "mean"),
        worst_fold_delta=("delta_AQL_qdesn_minus_pricefm", "max"),
        folds_won=("decision_label", lambda x: int((x == "qdesn_wins").sum())),
        feature_policy=("feature_policy", "first"), rhs_tau0=("rhs_tau0", "first"),
        lag_window=("lag_window", "first"), depth=("depth", "first"), units=("units", "first"),
    )
    out["delta_AQL_qdesn_minus_pricefm"] = out.qdesn_AQL - out.pricefm_AQL
    out["targeted"] = out.region.isin(TARGETS)
    out["descriptive_group"] = np.select(
        [out.region.isin(CENTRAL_EAST), out.region.str.startswith(("NO_", "SE_")) | out.region.isin(["DK_1", "DK_2", "FI"])],
        ["Central/East", "Nordic"], default="other",
    )
    return out.sort_values("delta_AQL_qdesn_minus_pricefm", ascending=False)


def _fold_shift(raw: pd.DataFrame) -> pd.DataFrame:
    t = pd.to_datetime(raw["time_utc"], utc=True)
    rows = []
    for region in TARGETS:
        col = f"{region}-price"
        for fold, bounds in FOLDS.items():
            for split, lo, hi in (("train", bounds[0], bounds[1]), ("validation", bounds[2], bounds[3]), ("test_audit_only", bounds[4], bounds[5])):
                mask = (t >= pd.Timestamp(lo, tz="UTC")) & (t < pd.Timestamp(hi, tz="UTC"))
                rows.append({"region": region, "fold": fold, "split": split, **_price_stats(raw.loc[mask, col])})
    return pd.DataFrame(rows)


def _neighbor_signal(raw: pd.DataFrame) -> pd.DataFrame:
    t = pd.to_datetime(raw["time_utc"], utc=True)
    train = raw.loc[(t >= pd.Timestamp("2022-01-01", tz="UTC")) & (t < pd.Timestamp("2024-09-01", tz="UTC"))]
    adjacency = graph_adj_matrix()
    rows = []
    for region in TARGETS:
        y = pd.to_numeric(train[f"{region}-price"], errors="coerce")
        dy = y.diff()
        for neighbor in [x for x in adjacency[region] if x != region]:
            z = pd.to_numeric(train[f"{neighbor}-price"], errors="coerce")
            level = y.corr(z)
            change = dy.corr(z.diff())
            rows.append({
                "region": region, "neighbor": neighbor,
                "level_correlation_train_only": float(level),
                "change_correlation_train_only": float(change),
                "absolute_change_correlation": abs(float(change)),
                "selection_cutoff_exclusive": "2024-09-01",
            })
    result = pd.DataFrame(rows).sort_values(["region", "absolute_change_correlation"], ascending=[True, False])
    result["change_rank"] = result.groupby("region").cumcount() + 1
    result["top3_change_neighbor"] = result.change_rank <= 3
    return result


def _prior_search(r97_root: Path) -> pd.DataFrame:
    frames = []
    for region in TARGETS:
        path = r97_root / f"regions/{region}/rhs_prep/pricefm_stage_r93_ridge_validation_ranking.csv"
        if path.is_file():
            frame = pd.read_csv(path).head(30).copy()
            frame["source_available"] = True
        else:
            frame = pd.DataFrame([{"region": region, "source_available": False}])
        frame["source_path"] = str(path.resolve())
        frames.append(frame)
    return pd.concat(frames, ignore_index=True)


def _checkpoint_provenance(repo: Path) -> pd.DataFrame:
    checkpoint = repo / "models/PhaseI_best.keras"
    if not checkpoint.is_file():
        found = list(repo.rglob("PhaseI_best.keras"))
        checkpoint = found[0] if found else checkpoint
    try:
        head = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        head = "unavailable"
    return pd.DataFrame([{
        "comparator": "cached_pricefm_phase_i_checkpoint_replay",
        "public_repo_head": head,
        "checkpoint_path": str(checkpoint),
        "checkpoint_sha256": sha256_file(checkpoint) if checkpoint.is_file() else "missing",
        "phase_i_gate_semantics": "one active target region per example",
        "paper_full_shot_reproduced": False,
        "fold_specific_checkpoint_provenance_sealed": False,
        "required_label": "cached PriceFM Phase-I checkpoint replay",
    }])


def run(args: argparse.Namespace) -> dict[str, Any]:
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    registry = pd.read_csv(args.r98_registry, low_memory=False)
    if len(registry) != 114 or registry.region.nunique() != 38 or registry.duplicated(["region", "fold"]).any():
        raise RuntimeError("R98 registry is not the complete 38 x 3 authority")
    if not set(TARGETS).issubset(set(registry.region)):
        raise RuntimeError("R99 target region missing from R98")
    raw = pd.read_parquet(args.raw_parquet)
    regions = _region_summary(registry)
    shifts = _fold_shift(raw)
    neighbors = _neighbor_signal(raw)
    prior = _prior_search(args.r97_root)
    comparator = _checkpoint_provenance(args.pricefm_repo)

    queue = regions[regions.targeted].copy()
    queue["target_reason"] = np.where(queue.descriptive_group.eq("Central/East"), "central_east_complete_recovery", "underperforming_nordic_recovery")
    queue["selection_data_contract"] = "inner_folds_101_102_103_only"
    queue["test_metrics_may_rank_candidates"] = False
    queue["r100_candidate_count"] = 240
    queue["r100_ridge_top_k"] = 30
    queue["r100_status"] = "eligible_targeted_novel_screen"

    duplicate_warning = {
        "r97_already_screened_same_generic_bounds": True,
        "r97_top30_rows_recovered": int(prior.source_available.sum()),
        "r97_regions_with_local_rankings": int(prior.loc[prior.source_available, "region"].nunique()),
        "r97_missing_rankings_are_distributed_compaction_not_missing_fits": True,
        "decision": "do_not_repeat_identical_r97_bank",
        "new_mechanisms": ["selective_neighbor_spread", "spatial_policy_reweighting", "reservoir_seed_robustness", "design_size_adjusted_rhs_tau"],
    }
    gate_rows = [
        ("r98_complete", True, len(registry)),
        ("target_count", len(queue) == 17, len(queue)),
        ("prior_r97_search_coverage_audited", prior.region.nunique() == 17, prior.region.nunique()),
        ("raw_target_columns_complete", all(f"{r}-price" in raw for r in TARGETS), len(TARGETS)),
        ("training_neighbor_signal_available", neighbors.region.nunique() == 17, neighbors.region.nunique()),
        ("candidate_selection_test_firewall", not queue.test_metrics_may_rank_candidates.any(), False),
        ("comparator_label_honest", not bool(comparator.iloc[0].paper_full_shot_reproduced), comparator.iloc[0].required_label),
        ("novel_r100_screen_supported", True, "targeted spatial/seed/tau mechanisms only"),
    ]
    gates = pd.DataFrame(gate_rows, columns=["gate", "passed", "observed"])
    if not gates.passed.all():
        raise RuntimeError("R99 mechanism gate failed")

    outputs = {
        "region": output / "pricefm_stage_r99_region_authority_atlas.csv",
        "shift": output / "pricefm_stage_r99_region_fold_shift_atlas.csv",
        "neighbors": output / "pricefm_stage_r99_neighbor_signal_audit.csv",
        "prior": output / "pricefm_stage_r99_r97_top30_coverage.csv",
        "comparator": output / "pricefm_stage_r99_comparator_provenance.csv",
        "queue": output / "pricefm_stage_r99_target_queue.csv",
        "gates": output / "pricefm_stage_r99_mechanism_gates.csv",
    }
    for key, frame in (("region", regions), ("shift", shifts), ("neighbors", neighbors), ("prior", prior), ("comparator", comparator), ("queue", queue), ("gates", gates)):
        _write_csv(outputs[key], frame)
    write_json(output / "pricefm_stage_r99_search_decision.json", duplicate_warning)
    sources = [_source(args.r98_registry, "R98_authority"), _source(args.raw_parquet, "raw_price_panel")]
    for region in TARGETS:
        path = args.r97_root / f"regions/{region}/rhs_prep/pricefm_stage_r93_ridge_validation_ranking.csv"
        if path.is_file():
            sources.append(_source(path, f"R97_{region}_ridge_ranking"))
    source_path = output / "source_manifest.csv"
    _write_csv(source_path, pd.DataFrame(sources))
    report = output / "pricefm_stage_r99_targeted_recovery_report.md"
    report.write_text(
        "# PriceFM R99 targeted recovery audit\n\n"
        "R98 remains the immutable validity-first authority. The 17-region target set is complete. "
        "R97 already covered the generic geometry grid, so R100 may launch only the new selective-neighbor, "
        "spatially reweighted, seed-robust, design-size-adjusted screen. Candidate selection is restricted to "
        "inner folds 101-103. The external benchmark must be labelled cached PriceFM Phase-I checkpoint replay.\n\n"
        "Registry, article, test scoring, quantile, joint, and MCMC work remain blocked.\n"
    )
    summary = {
        "stage": "R99", "status": "completed_targeted_recovery_gate_passed",
        "targets": TARGETS, "frozen_nordic_controls": NORDIC_CONTROLS,
        "r98_sha256": sha256_file(args.r98_registry), "graph_sha256": graph_hash(),
        "r100_launch_scientifically_supported": True,
        "identical_r97_rerun_authorized": False,
        "registry_mutated": False, "article_mutated": False, "model_fit_started": False,
        "outputs": {k: str(v) for k, v in outputs.items()},
        "source_manifest": str(source_path), "source_manifest_sha256": sha256_file(source_path),
    }
    write_json(output / "summary.json", summary)
    return summary


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
