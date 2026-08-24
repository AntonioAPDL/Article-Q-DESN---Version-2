#!/usr/bin/env python3
"""Plan bounded stability repeats and freeze validation-selected PriceFM winners."""

from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path
import statistics

from pricefm_operational_fullshot import (
    BATCH_SIZE,
    PHASE2_EPOCHS,
    atomic_write_csv,
    atomic_write_json,
    deterministic_seed,
    read_csv_rows,
    read_json,
    sha256_file,
    sha256_payload,
    status_is_complete,
)


WINNER_FIELDS = [
    "selector", "fold", "region", "candidate_id", "phase", "canonical_degree",
    "validation_AQL", "n_validation_replicates", "trial_id", "replicate", "seed",
    "checkpoint", "checkpoint_sha256", "mask_json", "mask_hash",
    "selected_on_split", "selection_reads_test",
]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("mode", choices=("plan-stability", "freeze"))
    p.add_argument("--artifact-root", required=True)
    p.add_argument("--relative-near-tie", type=float, default=0.01)
    return p


def completed_phase2_rows(manifest_path: Path) -> list[dict[str, object]]:
    if not manifest_path.is_file():
        return []
    completed = []
    for row in read_csv_rows(manifest_path):
        trial_dir = Path(row["trial_dir"])
        if not status_is_complete(trial_dir):
            raise RuntimeError(f"Incomplete validation trial: {row['trial_id']}")
        metric_rows = read_csv_rows(trial_dir / "validation_metrics.csv")
        if len(metric_rows) != 1:
            raise RuntimeError(f"Expected one validation metric row for {row['trial_id']}")
        status = read_json(trial_dir / "status.json")
        completed.append({
            **row,
            "candidate_id": f"graph_degree_{int(row['canonical_degree'])}",
            "validation_AQL": float(metric_rows[0]["AQL"]),
            "checkpoint": status["checkpoint"],
            "checkpoint_sha256": status["checkpoint_sha256"],
        })
    return completed


def phase1_candidates(root: Path) -> list[dict[str, object]]:
    freeze = read_json(root / "phase1" / "freeze.json")
    selected_path = Path(freeze["selected_manifest"])
    if sha256_file(selected_path) != freeze["selected_manifest_sha256"]:
        raise RuntimeError("Frozen Phase-I manifest hash mismatch")
    protocol = read_json(root / "provenance" / "protocol.json")
    regions = list(protocol["regions"])
    candidates = []
    for row in read_csv_rows(selected_path):
        metric_by_region = {
            metric["region"]: metric for metric in read_csv_rows(row["validation_metrics"])
        }
        fold = int(row["fold"])
        for region in regions:
            mask = [1 if item == region else 0 for item in regions]
            candidates.append({
                "phase": "phase1",
                "fold": fold,
                "region": region,
                "canonical_degree": "phase1",
                "candidate_id": "phase1_shared",
                "replicate": int(row["replicate"]),
                "seed": int(row["seed"]),
                "trial_id": row["trial_id"],
                "validation_AQL": float(metric_by_region[region]["AQL"]),
                "checkpoint": row["checkpoint"],
                "checkpoint_sha256": row["checkpoint_sha256"],
                "mask_json": json.dumps(mask, separators=(",", ":")),
                "mask_hash": sha256_payload(mask),
            })
    return candidates


def plan_stability(root: Path, relative_near_tie: float) -> dict[str, object]:
    screen_manifest = root / "phase2" / "screen" / "trial_manifest.csv"
    phase2 = completed_phase2_rows(screen_manifest)
    if len(phase2) != 1047:
        raise RuntimeError(f"Expected 1,047 completed Phase-II screen trials, observed {len(phase2)}")
    all_candidates = phase1_candidates(root) + phase2
    by_cell: dict[tuple[int, str], list[dict[str, object]]] = defaultdict(list)
    for row in all_candidates:
        by_cell[(int(row["fold"]), str(row["region"]))].append(row)
    if len(by_cell) != 114:
        raise RuntimeError(f"Expected 114 region-fold cells, observed {len(by_cell)}")

    ranking_rows = []
    stability_sources = []
    for (fold, region), candidates in sorted(by_cell.items()):
        ranked = sorted(candidates, key=lambda item: (float(item["validation_AQL"]), str(item["candidate_id"])))
        gap = (float(ranked[1]["validation_AQL"]) - float(ranked[0]["validation_AQL"])) / max(
            abs(float(ranked[0]["validation_AQL"])), 1e-12
        )
        near_tie = gap <= relative_near_tie
        for rank, candidate in enumerate(ranked, start=1):
            ranking_rows.append({
                "fold": fold,
                "region": region,
                "rank": rank,
                "candidate_id": candidate["candidate_id"],
                "phase": candidate["phase"],
                "canonical_degree": candidate["canonical_degree"],
                "validation_AQL": candidate["validation_AQL"],
                "top_two_relative_gap": gap if rank <= 2 else "",
                "stability_triggered": near_tie and rank <= 2,
            })
        if near_tie:
            stability_sources.extend(candidate for candidate in ranked[:2] if candidate["phase"] == "phase2")

    atomic_write_csv(root / "selection" / "validation_screen_ranking.csv", ranking_rows)
    protocol = read_json(root / "provenance" / "protocol.json")
    initializers = {
        int(row["fold"]): row for row in read_csv_rows(root / "phase1" / "frozen_initializers.csv")
    }
    rows = []
    for source in stability_sources:
        fold = int(source["fold"])
        initializer = initializers[fold]
        for replicate in (2, 3):
            degree = int(source["canonical_degree"])
            region = str(source["region"])
            trial_id = f"p2stab_f{fold}_{region}_d{degree}_rep{replicate}"
            rows.append({
                "task_kind": "fit",
                "phase": "phase2",
                "trial_id": trial_id,
                "fold": fold,
                "region": region,
                "canonical_degree": degree,
                "mask_hash": source["mask_hash"],
                "mask_json": source["mask_json"],
                "replicate": replicate,
                "seed": deterministic_seed(
                    protocol["run_tag"], "phase2_stability", fold, region, degree, replicate
                ),
                "epochs": PHASE2_EPOCHS,
                "batch_size": BATCH_SIZE,
                "initializer_checkpoint": initializer["checkpoint"],
                "initializer_sha256": initializer["checkpoint_sha256"],
                "trial_dir": str(root / "phase2" / "stability" / "trials" / trial_id),
            })
    if len(rows) > 456:
        raise RuntimeError(f"Stability cap violated: {len(rows)} > 456")
    manifest = root / "phase2" / "stability" / "trial_manifest.csv"
    fields = [
        "task_kind", "phase", "trial_id", "fold", "region", "canonical_degree",
        "mask_hash", "mask_json", "replicate", "seed", "epochs", "batch_size",
        "initializer_checkpoint", "initializer_sha256", "trial_dir",
    ]
    atomic_write_csv(manifest, rows, fields)
    summary = {
        "status": "prepared",
        "relative_near_tie_threshold": relative_near_tie,
        "n_stability_trials": len(rows),
        "maximum_allowed_stability_trials": 456,
        "manifest": str(manifest),
        "manifest_sha256": sha256_file(manifest),
        "selection_reads_test": False,
    }
    atomic_write_json(root / "phase2" / "stability" / "preparation_summary.json", summary)
    return summary


def aggregate_candidates(root: Path) -> list[dict[str, object]]:
    phase1 = phase1_candidates(root)
    phase2 = completed_phase2_rows(root / "phase2" / "screen" / "trial_manifest.csv")
    stability_path = root / "phase2" / "stability" / "trial_manifest.csv"
    phase2 += completed_phase2_rows(stability_path)
    groups: dict[tuple[int, str, str], list[dict[str, object]]] = defaultdict(list)
    for row in phase1 + phase2:
        groups[(int(row["fold"]), str(row["region"]), str(row["candidate_id"]))].append(row)

    summaries = []
    for (fold, region, candidate_id), rows in sorted(groups.items()):
        values = [float(row["validation_AQL"]) for row in rows]
        median_aql = statistics.median(values)
        representative = min(
            rows,
            key=lambda row: (abs(float(row["validation_AQL"]) - median_aql), str(row["trial_id"])),
        )
        summaries.append({
            "fold": fold,
            "region": region,
            "candidate_id": candidate_id,
            "phase": representative["phase"],
            "canonical_degree": representative["canonical_degree"],
            "validation_AQL": median_aql,
            "n_validation_replicates": len(rows),
            "min_validation_AQL": min(values),
            "max_validation_AQL": max(values),
            "trial_id": representative["trial_id"],
            "replicate": representative["replicate"],
            "seed": representative["seed"],
            "checkpoint": representative["checkpoint"],
            "checkpoint_sha256": representative["checkpoint_sha256"],
            "mask_json": representative["mask_json"],
            "mask_hash": representative["mask_hash"],
        })
    return summaries


def winner_row(selector: str, row: dict[str, object]) -> dict[str, object]:
    return {
        "selector": selector,
        **{field: row[field] for field in WINNER_FIELDS if field in row and field != "selector"},
        "selected_on_split": "validation",
        "selection_reads_test": False,
    }


def freeze_winners(root: Path) -> dict[str, object]:
    summaries = aggregate_candidates(root)
    summary_path = root / "selection" / "candidate_validation_summary.csv"
    atomic_write_csv(summary_path, summaries)
    by_cell: dict[tuple[int, str], list[dict[str, object]]] = defaultdict(list)
    for row in summaries:
        by_cell[(int(row["fold"]), str(row["region"]))].append(row)
    if len(by_cell) != 114:
        raise RuntimeError(f"Expected 114 candidate cells, observed {len(by_cell)}")

    cell_winners = [
        winner_row("cell_specific", min(rows, key=lambda row: (float(row["validation_AQL"]), str(row["candidate_id"]))))
        for _, rows in sorted(by_cell.items())
    ]
    by_region_candidate: dict[tuple[str, str], list[dict[str, object]]] = defaultdict(list)
    for row in summaries:
        by_region_candidate[(str(row["region"]), str(row["candidate_id"]))].append(row)
    region_choice: dict[str, str] = {}
    for region in sorted({str(row["region"]) for row in summaries}):
        candidates = []
        for (candidate_region, candidate_id), rows in by_region_candidate.items():
            if candidate_region == region and {int(row["fold"]) for row in rows} == {1, 2, 3}:
                candidates.append((sum(float(row["validation_AQL"]) for row in rows) / 3, candidate_id))
        if not candidates:
            raise RuntimeError(f"No fold-complete region-global candidate for {region}")
        region_choice[region] = min(candidates)[1]
    global_winners = []
    summary_index = {
        (int(row["fold"]), str(row["region"]), str(row["candidate_id"])): row for row in summaries
    }
    for fold, region in sorted(by_cell):
        global_winners.append(winner_row(
            "region_global", summary_index[(fold, region, region_choice[region])]
        ))

    cell_path = root / "selection" / "cell_specific_winners.csv"
    global_path = root / "selection" / "region_global_winners.csv"
    atomic_write_csv(cell_path, cell_winners, WINNER_FIELDS)
    atomic_write_csv(global_path, global_winners, WINNER_FIELDS)
    freeze = {
        "status": "frozen_before_test",
        "primary_selector": "cell_specific",
        "sensitivity_selector": "region_global",
        "n_primary_winners": len(cell_winners),
        "n_sensitivity_winners": len(global_winners),
        "candidate_summary": str(summary_path),
        "candidate_summary_sha256": sha256_file(summary_path),
        "cell_specific_winners": str(cell_path),
        "cell_specific_winners_sha256": sha256_file(cell_path),
        "region_global_winners": str(global_path),
        "region_global_winners_sha256": sha256_file(global_path),
        "selection_metric": "median_original_scale_validation_AQL",
        "selection_reads_test": False,
    }
    atomic_write_json(root / "selection" / "winner_freeze.json", freeze)
    return freeze


def main() -> None:
    args = parser().parse_args()
    root = Path(args.artifact_root).resolve()
    result = (
        plan_stability(root, args.relative_near_tie)
        if args.mode == "plan-stability"
        else freeze_winners(root)
    )
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
