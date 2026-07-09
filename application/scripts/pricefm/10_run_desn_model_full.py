#!/usr/bin/env python3
"""Run the full PriceFM DESN comparison as resumable region/fold cells."""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from pricefm_common import load_config, parse_bool, repo_path, summarize, write_json
from pricefm_full_run import (
    FULL_BLOCK,
    cell_statuses_have_failures,
    load_full_config,
    resolve_folds,
    resolve_horizons,
    resolve_quantiles,
    resolve_regions,
    run_cells,
    write_status_csv,
)


def parse_csv_or_all(value):
    if value is None:
        return None
    text = str(value).strip()
    if text == "" or text == "all":
        return "all"
    return [x.strip() for x in text.split(",") if x.strip()]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", default="application/config/pricefm_desn_model_full.yaml")
    p.add_argument("--jobs", type=int, default=None)
    p.add_argument("--resume", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    p.add_argument("--dry-run", type=parse_bool, default=False)
    p.add_argument("--regions", default=None, help="Comma-separated region subset or 'all'.")
    p.add_argument("--folds", default=None, help="Comma-separated fold subset or 'all'.")
    p.add_argument("--max-cells", type=int, default=None)
    args = p.parse_args()

    full_cfg = load_full_config(args.config)
    data_cfg = load_config(full_cfg["data_config"])
    run_dir = repo_path(full_cfg["run"]["output_dir"])
    run_dir.mkdir(parents=True, exist_ok=True)

    region_override = parse_csv_or_all(args.regions)
    if region_override == "all":
        region_override = None
    fold_override = parse_csv_or_all(args.folds)
    if fold_override == "all":
        fold_override = None
    if fold_override is not None:
        fold_override = [int(x) for x in fold_override]

    regions = resolve_regions(full_cfg, data_cfg, region_override)
    folds = resolve_folds(full_cfg, data_cfg, fold_override)
    horizons = resolve_horizons(full_cfg, data_cfg)
    quantiles = resolve_quantiles(full_cfg)
    jobs = int(args.jobs or full_cfg["run"].get("default_jobs", 1))

    manifest = {
        "config": str(repo_path(args.config)),
        "block": FULL_BLOCK,
        "regions": regions,
        "folds": folds,
        "n_cells": len(regions) * len(folds),
        "horizons": horizons,
        "quantiles": quantiles,
        "jobs": jobs,
        "resume": bool(args.resume),
        "force": bool(args.force),
        "dry_run": bool(args.dry_run),
        "max_cells": args.max_cells,
    }
    write_json(run_dir / "run_manifest.json", manifest)

    rows = run_cells(
        full_cfg,
        data_cfg,
        regions=regions,
        folds=folds,
        jobs=jobs,
        force=bool(args.force),
        resume=bool(args.resume),
        dry_run=bool(args.dry_run),
        max_cells=args.max_cells,
    )
    status_path = run_dir / "cell_status.csv"
    write_status_csv(status_path, rows)
    counts = Counter(row["status"] for row in rows)
    summarize(run_dir, {
        "status_csv": str(status_path),
        "counts": dict(sorted(counts.items())),
        "n_rows": len(rows),
    })
    if cell_statuses_have_failures(rows):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
