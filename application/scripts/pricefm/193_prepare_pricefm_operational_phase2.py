#!/usr/bin/env python3
"""Materialize the canonical Phase-II PriceFM graph-mask trial manifest."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from pricefm_operational_fullshot import (
    BATCH_SIZE,
    PHASE2_EPOCHS,
    atomic_write_csv,
    atomic_write_json,
    deterministic_seed,
    read_csv_rows,
    read_json,
    sha256_file,
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-root", required=True)
    return p


def prepare_phase2(artifact_root: str | Path) -> dict[str, object]:
    root = Path(artifact_root).resolve()
    protocol = read_json(root / "provenance" / "protocol.json")
    freeze = read_json(root / "phase1" / "freeze.json")
    initializers_path = Path(freeze["selected_manifest"])
    if sha256_file(initializers_path) != freeze["selected_manifest_sha256"]:
        raise RuntimeError("Frozen Phase-I initializer manifest hash mismatch")
    initializers = {int(row["fold"]): row for row in read_csv_rows(initializers_path)}
    masks = read_csv_rows(root / "graph" / "canonical_masks.csv")
    if len(masks) != 349:
        raise RuntimeError(f"Expected 349 canonical masks, observed {len(masks)}")

    rows = []
    for fold in (1, 2, 3):
        initializer = initializers[fold]
        for mask in masks:
            region = mask["region"]
            degree = int(mask["canonical_degree"])
            trial_id = f"p2_f{fold}_{region}_d{degree}_rep1"
            rows.append({
                "task_kind": "fit",
                "phase": "phase2",
                "trial_id": trial_id,
                "fold": fold,
                "region": region,
                "canonical_degree": degree,
                "mask_hash": mask["mask_hash"],
                "mask_json": mask["mask_json"],
                "replicate": 1,
                "seed": deterministic_seed(protocol["run_tag"], "phase2", fold, region, degree, 1),
                "epochs": PHASE2_EPOCHS,
                "batch_size": BATCH_SIZE,
                "initializer_checkpoint": initializer["checkpoint"],
                "initializer_sha256": initializer["checkpoint_sha256"],
                "trial_dir": str(root / "phase2" / "screen" / "trials" / trial_id),
            })
    if len(rows) != 1047:
        raise RuntimeError(f"Expected 1,047 canonical Phase-II trials, observed {len(rows)}")
    manifest = root / "phase2" / "screen" / "trial_manifest.csv"
    atomic_write_csv(manifest, rows)
    summary = {
        "status": "prepared",
        "n_trials": len(rows),
        "manifest": str(manifest),
        "manifest_sha256": sha256_file(manifest),
        "one_seed_per_canonical_mask": True,
        "reads_test_split": False,
    }
    atomic_write_json(root / "phase2" / "screen" / "preparation_summary.json", summary)
    return summary


def main() -> None:
    print(json.dumps(prepare_phase2(parser().parse_args().artifact_root), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
