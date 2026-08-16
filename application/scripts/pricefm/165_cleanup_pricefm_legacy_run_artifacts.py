#!/usr/bin/env python3
"""Safely prune reconstructible heavy artifacts from closed PriceFM runs."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_DATA_ROOT = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm"
)
DEFAULT_SELECTED = DEFAULT_DATA_ROOT / (
    "authoritative/pricefm_stage_r34_lean_capacity_history_closeout_20260728/"
    "pricefm_stage_r34_validation_selected_cases.csv"
)
DEFAULT_OUTPUT = DEFAULT_DATA_ROOT / (
    "authoritative/pricefm_legacy_cleanup_20260805"
)
RUN_POLICIES = {
    "pricefm_stage_r25_post_r24_broad_horizon_weighted_20260709": "all_closed_negative",
    "pricefm_stage_r30_horizon_block_readout_main_20260711": "all_closed_negative",
    "pricefm_stage_r32_large_capacity_history_20260714": "all_closed_negative",
    "pricefm_stage_r33_lean_capacity_history_20260722": "preserve_r34_selected",
}
PRUNABLE_NAMES = {
    "rows_all.csv",
    "rows_train.csv",
    "rows_val.csv",
    "rows_test.csv",
    "y_train.csv",
    "y_val.csv",
    "y_test.csv",
    "model_predictions_scaled.csv",
    "predictions_with_naive_scaled.csv",
    "feature_map_matrix.npz",
}
PRUNABLE_SUFFIXES = (".png",)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def selected_experiments(path: Path) -> set[str]:
    with path.open(newline="", encoding="utf-8") as handle:
        return {row["experiment_id"] for row in csv.DictReader(handle)}


def active_pricefm_processes() -> list[str]:
    result = subprocess.run(
        ["ps", "-eo", "pid=,args="], check=True, text=True, capture_output=True
    )
    own_pid = os.getpid()
    return [
        line.strip()
        for line in result.stdout.splitlines()
        if "pricefm_stage_r" in line.lower()
        and not line.lstrip().startswith(str(own_pid) + " ")
        and "165_cleanup_pricefm_legacy_run_artifacts.py" not in line
    ]


def experiment_id(path: Path, run_root: Path) -> str:
    relative = path.relative_to(run_root)
    return relative.parts[0] if relative.parts else ""


def build_ledger(data_root: Path, selected: set[str]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    runs_root = data_root / "runs"
    for run_tag, policy in RUN_POLICIES.items():
        run_root = (runs_root / run_tag).resolve()
        if not run_root.is_dir() or runs_root.resolve() not in run_root.parents:
            continue
        for path in sorted(item for item in run_root.rglob("*") if item.is_file()):
            exp_id = experiment_id(path, run_root)
            selected_by_r34 = run_tag.endswith("20260722") and exp_id in selected
            is_prunable = path.name in PRUNABLE_NAMES or path.suffix.lower() in PRUNABLE_SUFFIXES
            if not is_prunable or selected_by_r34:
                continue
            rows.append(
                {
                    "run_tag": run_tag,
                    "policy": policy,
                    "experiment_id": exp_id,
                    "selected_by_r34": selected_by_r34,
                    "path": str(path),
                    "size_bytes": path.stat().st_size,
                    "sha256": sha256(path),
                    "action": "delete_reconstructible_artifact",
                }
            )
    return rows


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    fields = [
        "run_tag", "policy", "experiment_id", "selected_by_r34", "path",
        "size_bytes", "sha256", "action", "applied",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def load_ledger(path: Path, data_root: Path) -> list[dict[str, object]]:
    runs_root = (data_root / "runs").resolve()
    allowed_roots = {(runs_root / tag).resolve() for tag in RUN_POLICIES}
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    for row in rows:
        artifact = Path(row["path"]).resolve()
        if not any(root in artifact.parents for root in allowed_roots):
            raise RuntimeError(f"Ledger path escapes allowed run roots: {artifact}")
        if artifact.name not in PRUNABLE_NAMES and artifact.suffix.lower() not in PRUNABLE_SUFFIXES:
            raise RuntimeError(f"Ledger contains a non-allowlisted artifact: {artifact}")
        if row["selected_by_r34"].lower() == "true":
            raise RuntimeError(f"Ledger contains an R34-selected artifact: {artifact}")
        if artifact.exists() and artifact.stat().st_size != int(row["size_bytes"]):
            raise RuntimeError(f"Artifact size changed since dry run: {artifact}")
    return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    parser.add_argument("--selected-csv", type=Path, default=DEFAULT_SELECTED)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    selected = selected_experiments(args.selected_csv)
    if len(selected) != 20:
        raise RuntimeError(f"Expected 20 frozen R34 selections, found {len(selected)}")
    active = active_pricefm_processes()
    if active:
        raise RuntimeError("Refusing cleanup while PriceFM processes are active: " + " | ".join(active))
    ledger_path = args.output_dir / "pricefm_legacy_cleanup_ledger.csv"
    if args.apply and ledger_path.exists():
        rows = load_ledger(ledger_path, args.data_root.resolve())
    else:
        rows = build_ledger(args.data_root.resolve(), selected)
    bytes_planned = sum(int(row["size_bytes"]) for row in rows)
    if args.apply:
        if not args.force:
            raise RuntimeError("Apply mode requires --force")
        for row in rows:
            path = Path(str(row["path"]))
            if path.exists():
                path.unlink()
            row["applied"] = True
    else:
        for row in rows:
            row["applied"] = False
    write_csv(ledger_path, rows)
    summary = {
        "status": "applied" if args.apply else "dry_run",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "data_root": str(args.data_root.resolve()),
        "selected_manifest": str(args.selected_csv.resolve()),
        "selected_experiments_preserved_in_full": len(selected),
        "run_policies": RUN_POLICIES,
        "files_planned": len(rows),
        "bytes_planned": bytes_planned,
        "gib_planned": round(bytes_planned / (1024 ** 3), 3),
        "active_pricefm_processes": active,
        "preserved_classes": [
            "all R34-selected R33 experiment artifacts",
            "metrics, manifests, logs, reports, parameter summaries, and provenance",
            "all R36/R37/R38/R39 artifacts",
        ],
    }
    (args.output_dir / "pricefm_legacy_cleanup_summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
