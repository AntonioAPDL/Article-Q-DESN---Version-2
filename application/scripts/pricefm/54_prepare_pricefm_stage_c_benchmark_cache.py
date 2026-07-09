#!/usr/bin/env python3
"""Prepare fold-aligned PriceFM Phase-I benchmark caches for Stage-C rows.

This script is a small orchestration layer around
``17_run_pricefm_phase1_predictions.py``. It exists so Stage-C expansion rows
can verify the PriceFM benchmark cache before launching local DESN/Q-DESN
paper-quantile fits.

It does not fit local models and it does not compare methods. It only creates
or verifies the cached PriceFM Phase-I artifacts required by the comparison
gate.
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


SCRIPT_DIR = Path(__file__).resolve().parent
PRICEFM_SCRIPT = SCRIPT_DIR / "17_run_pricefm_phase1_predictions.py"
DEFAULT_QUANTILES = "0.10,0.25,0.45,0.50,0.55,0.75,0.90"
DEFAULT_PRICEFM_PYTHON = "application/data_local/pricefm/venv_pricefm_tf/bin/python"
REQUIRED_CACHE_FILES = [
    "pricefm_phase1_metrics.csv",
    "pricefm_phase1_predictions_original.csv",
    "pricefm_phase1_predictions_scaled.csv",
    "pricefm_phase1_row_audit.csv",
    "pricefm_phase1_metric_by_horizon.csv",
]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--registry-csv", required=True)
    p.add_argument("--output-root", required=True)
    p.add_argument("--config", default="application/config/pricefm_data_pipeline.yaml")
    p.add_argument("--pricefm-python", default=DEFAULT_PRICEFM_PYTHON)
    p.add_argument("--regions", default=None)
    p.add_argument("--folds", default=None)
    p.add_argument("--quantiles", default=DEFAULT_QUANTILES)
    p.add_argument("--splits", default="test")
    p.add_argument("--window-mode", default="operational")
    p.add_argument("--batch-size", type=int, default=128)
    p.add_argument("--jobs", type=int, default=1)
    p.add_argument("--resume", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    p.add_argument("--dry-run", type=parse_bool, default=True)
    p.add_argument("--grid-id", default="pricefm_stage_c_benchmark_cache_20260618")
    return p


def parse_csv(value, cast=str):
    if value is None or str(value).strip() == "":
        return None
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def registry_scope(registry_csv, regions=None, folds=None):
    path = repo_path(registry_csv)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("Missing registry CSV: {}".format(path))
    frame = pd.read_csv(path)
    missing = {"region", "fold"} - set(frame.columns)
    if missing:
        raise ValueError("Registry missing required columns: {}".format(sorted(missing)))
    frame = frame.copy()
    frame["region"] = frame["region"].astype(str)
    frame["fold"] = pd.to_numeric(frame["fold"], errors="raise").astype(int)
    if regions:
        frame = frame[frame["region"].isin([str(x) for x in regions])]
    if folds:
        frame = frame[frame["fold"].isin([int(x) for x in folds])]
    dup = frame[frame.duplicated(["region", "fold"], keep=False)]
    if not dup.empty:
        raise ValueError(
            "Registry has duplicate region/fold rows:\n{}".format(
                dup[["region", "fold"]].to_string(index=False)
            )
        )
    frame = frame.sort_values(["region", "fold"]).reset_index(drop=True)
    if frame.empty:
        raise ValueError("No region/fold rows remain after filters.")
    return frame


def region_fold_dir(output_root, region, fold):
    return repo_path(output_root) / "region={}".format(region) / "fold={}".format(int(fold))


def cache_missing_files(output_dir):
    output_dir = repo_path(output_dir)
    missing = []
    for name in REQUIRED_CACHE_FILES:
        path = output_dir / name
        if not path.exists() or path.stat().st_size == 0:
            missing.append(name)
    return missing


def cache_complete(output_dir):
    return len(cache_missing_files(output_dir)) == 0


def pricefm_command(args, region, fold, output_dir):
    return [
        str(repo_path(args.pricefm_python)),
        str(PRICEFM_SCRIPT),
        "--config",
        str(repo_path(args.config)),
        "--region",
        str(region),
        "--fold",
        str(int(fold)),
        "--output-dir",
        str(repo_path(output_dir)),
        "--splits",
        str(args.splits),
        "--quantiles",
        str(args.quantiles),
        "--window-mode",
        str(args.window_mode),
        "--batch-size",
        str(int(args.batch_size)),
    ]


def run_one(args, row):
    region = str(row.region)
    fold = int(row.fold)
    output_dir = region_fold_dir(args.output_root, region, fold)
    log_path = repo_path(args.output_root) / "logs" / "pricefm_region={}_fold={}.log".format(region, fold)
    cmd = pricefm_command(args, region, fold, output_dir)
    before_missing = cache_missing_files(output_dir)
    before_complete = not before_missing

    if args.dry_run:
        status = "planned_cached" if before_complete else "planned_run"
        return {
            "region": region,
            "fold": fold,
            "status": status,
            "return_code": 0,
            "cache_complete_before": before_complete,
            "cache_complete_after": before_complete,
            "missing_files_after": ",".join(before_missing),
            "output_dir": config_path_value(output_dir),
            "log": config_path_value(log_path),
            "command": " ".join(map(str, cmd)),
        }

    if before_complete and args.resume and not args.force:
        return {
            "region": region,
            "fold": fold,
            "status": "cached",
            "return_code": 0,
            "cache_complete_before": True,
            "cache_complete_after": True,
            "missing_files_after": "",
            "output_dir": config_path_value(output_dir),
            "log": config_path_value(log_path),
            "command": " ".join(map(str, cmd)),
        }

    log_path.parent.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    with open(log_path, "w") as log:
        log.write("$ {}\n\n".format(" ".join(map(str, cmd))))
        log.flush()
        proc = subprocess.run(
            [str(x) for x in cmd],
            cwd=str(repo_path(".")),
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        )

    after_missing = cache_missing_files(output_dir)
    after_complete = not after_missing
    if proc.returncode == 0 and after_complete:
        status = "completed"
    elif proc.returncode == 0:
        status = "incomplete"
    else:
        status = "failed"
    return {
        "region": region,
        "fold": fold,
        "status": status,
        "return_code": int(proc.returncode),
        "cache_complete_before": before_complete,
        "cache_complete_after": after_complete,
        "missing_files_after": ",".join(after_missing),
        "output_dir": config_path_value(output_dir),
        "log": config_path_value(log_path),
        "command": " ".join(map(str, cmd)),
    }


def write_status(path, rows):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "region", "fold", "status", "return_code",
        "cache_complete_before", "cache_complete_after",
        "missing_files_after", "output_dir", "log", "command",
    ]
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def write_report(output_root, args, rows):
    path = repo_path(output_root) / "pricefm_stage_c_benchmark_cache_report.md"
    frame = pd.DataFrame(rows)
    counts = frame["status"].value_counts().sort_index()
    with open(path, "w") as f:
        f.write("# PriceFM Stage-C Benchmark Cache\n\n")
        f.write("Grid: `{}`\n\n".format(args.grid_id))
        f.write("This report records PriceFM Phase-I benchmark cache preparation ")
        f.write("for Stage-C region/fold candidates. It does not fit local models ")
        f.write("and it does not compare methods.\n\n")
        f.write("## Status Counts\n\n")
        f.write("| status | count |\n|---|---:|\n")
        for status, count in counts.items():
            f.write("| `{}` | {} |\n".format(status, int(count)))
        f.write("\n## Region/Fold Rows\n\n")
        f.write("| region | fold | status | cache_complete_after | missing_files_after |\n")
        f.write("|---|---:|---|---|---|\n")
        for row in rows:
            f.write(
                "| {region} | {fold} | `{status}` | {complete} | {missing} |\n".format(
                    region=row["region"],
                    fold=int(row["fold"]),
                    status=row["status"],
                    complete=row["cache_complete_after"],
                    missing=row["missing_files_after"] or "",
                )
            )
    return path


def prepare_cache(args):
    if int(args.jobs) < 1:
        raise ValueError("--jobs must be >= 1")
    if int(args.batch_size) < 1:
        raise ValueError("--batch-size must be >= 1")
    if args.force and args.dry_run:
        raise ValueError("--force true is not meaningful with --dry-run true")

    regions = parse_csv(args.regions, str)
    folds = parse_csv(args.folds, int)
    scope = registry_scope(args.registry_csv, regions=regions, folds=folds)
    out_root = repo_path(args.output_root)
    out_root.mkdir(parents=True, exist_ok=True)

    rows = []
    with ThreadPoolExecutor(max_workers=int(args.jobs)) as pool:
        futures = [pool.submit(run_one, args, row) for row in scope.itertuples(index=False)]
        for future in as_completed(futures):
            rows.append(future.result())
    rows = sorted(rows, key=lambda x: (str(x["region"]), int(x["fold"])))

    status_csv = out_root / "pricefm_stage_c_benchmark_cache_status.csv"
    write_status(status_csv, rows)
    report = write_report(out_root, args, rows)

    frame = pd.DataFrame(rows)
    failed = frame[~frame["status"].isin(["completed", "cached", "planned_cached", "planned_run"])]
    complete_after = frame["cache_complete_after"].astype(bool)
    summary_status = "planned" if args.dry_run else ("completed" if complete_after.all() and failed.empty else "failed")
    summary = {
        "grid_id": args.grid_id,
        "status": summary_status,
        "dry_run": bool(args.dry_run),
        "registry_csv": config_path_value(args.registry_csv),
        "output_root": config_path_value(out_root),
        "config": config_path_value(args.config),
        "pricefm_python": config_path_value(args.pricefm_python),
        "quantiles": args.quantiles,
        "splits": args.splits,
        "window_mode": args.window_mode,
        "batch_size": int(args.batch_size),
        "jobs": int(args.jobs),
        "resume": bool(args.resume),
        "force": bool(args.force),
        "n_region_folds": int(frame.shape[0]),
        "n_cache_complete_after": int(complete_after.sum()),
        "n_missing_after": int((~complete_after).sum()),
        "status_counts": {str(k): int(v) for k, v in frame["status"].value_counts().sort_index().items()},
        "outputs": {
            "status_csv": config_path_value(status_csv),
            "report": config_path_value(report),
        },
    }
    write_json(out_root / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = prepare_cache(args)
    print(json.dumps(summary, indent=2, sort_keys=True))
    if not args.dry_run and summary["status"] != "completed":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
