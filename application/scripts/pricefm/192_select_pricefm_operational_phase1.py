#!/usr/bin/env python3
"""Freeze one validation-selected shared PriceFM initializer per fold."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from pricefm_operational_fullshot import (
    atomic_write_csv,
    atomic_write_json,
    read_csv_rows,
    read_json,
    sha256_file,
    status_is_complete,
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-root", required=True)
    return p


def select_phase1(artifact_root: str | Path) -> dict[str, object]:
    root = Path(artifact_root).resolve()
    manifest_path = root / "phase1" / "trial_manifest.csv"
    rows = read_csv_rows(manifest_path)
    expected = 9
    if len(rows) != expected:
        raise RuntimeError(f"Expected {expected} Phase-I trials, observed {len(rows)}")

    scored = []
    for row in rows:
        trial_dir = Path(row["trial_dir"])
        if not status_is_complete(trial_dir):
            raise RuntimeError(f"Phase-I trial is incomplete: {row['trial_id']}")
        status = read_json(trial_dir / "status.json")
        metrics = read_csv_rows(trial_dir / "validation_metrics.csv")
        if len(metrics) != 38:
            raise RuntimeError(f"Expected 38 validation rows for {row['trial_id']}")
        mean_aql = sum(float(metric["AQL"]) for metric in metrics) / len(metrics)
        scored.append({
            **row,
            "equal_region_mean_validation_AQL": mean_aql,
            "checkpoint": status["checkpoint"],
            "checkpoint_sha256": status["checkpoint_sha256"],
            "validation_metrics": status["validation_metrics"],
            "validation_metrics_sha256": status["validation_metrics_sha256"],
        })
    atomic_write_csv(root / "phase1" / "validation_ranking.csv", sorted(
        scored, key=lambda item: (int(item["fold"]), float(item["equal_region_mean_validation_AQL"]), item["trial_id"])
    ))

    selected = []
    for fold in (1, 2, 3):
        candidates = [row for row in scored if int(row["fold"]) == fold]
        winner = min(candidates, key=lambda item: (float(item["equal_region_mean_validation_AQL"]), item["trial_id"]))
        selected.append({
            "fold": fold,
            "trial_id": winner["trial_id"],
            "replicate": int(winner["replicate"]),
            "seed": int(winner["seed"]),
            "equal_region_mean_validation_AQL": winner["equal_region_mean_validation_AQL"],
            "checkpoint": winner["checkpoint"],
            "checkpoint_sha256": winner["checkpoint_sha256"],
            "validation_metrics": winner["validation_metrics"],
            "validation_metrics_sha256": winner["validation_metrics_sha256"],
            "selected_on_split": "validation",
            "selection_reads_test": False,
        })
    selected_path = root / "phase1" / "frozen_initializers.csv"
    atomic_write_csv(selected_path, selected)
    freeze = {
        "status": "frozen",
        "n_selected": len(selected),
        "selected_manifest": str(selected_path),
        "selected_manifest_sha256": sha256_file(selected_path),
        "selection_rule": "minimum_equal_region_mean_validation_AQL_with_trial_id_tiebreak",
        "reads_test_split": False,
    }
    atomic_write_json(root / "phase1" / "freeze.json", freeze)
    return freeze


def main() -> None:
    print(json.dumps(select_phase1(parser().parse_args().artifact_root), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
