#!/usr/bin/env python3
"""Summarize a region-panel paper-quantile PriceFM DESN grid."""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


SCRIPT_DIR = Path(__file__).resolve().parent
SUMMARY_SCRIPT = SCRIPT_DIR / "15_summarize_paper_quantile_runs.py"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--registry-csv", required=True)
    p.add_argument("--grid-config", required=True)
    p.add_argument("--output-root", required=True)
    p.add_argument("--regions", default=None)
    p.add_argument("--folds", default=None)
    p.add_argument("--require-complete", type=parse_bool, default=True)
    p.add_argument("--dry-run", type=parse_bool, default=True)
    p.add_argument("--panel-label", default="local-only DESN/Q-DESN")
    p.add_argument(
        "--panel-description",
        default="local-only DESN/Q-DESN paper-quantile cells",
    )
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
    frame = pd.read_csv(repo_path(registry_csv))
    required = {"region", "fold"}
    missing = required - set(frame.columns)
    if missing:
        raise ValueError("Registry missing required columns: {}".format(sorted(missing)))
    frame = frame[["region", "fold"]].drop_duplicates()
    frame["region"] = frame["region"].astype(str)
    frame["fold"] = frame["fold"].astype(int)
    if regions:
        frame = frame[frame["region"].isin([str(x) for x in regions])]
    if folds:
        frame = frame[frame["fold"].isin([int(x) for x in folds])]
    frame = frame.sort_values(["region", "fold"]).reset_index(drop=True)
    if frame.empty:
        raise ValueError("No region/fold rows remain after filters.")
    return frame


def region_fold_dir(root, region, fold):
    return repo_path(root) / "region={}".format(region) / "fold={}".format(int(fold))


def attach_scope_columns(frame, region, fold, source_path):
    """Attach or validate region/fold columns from the enclosing panel scope."""
    frame = frame.copy()
    expected_region = str(region)
    expected_fold = int(fold)
    source = config_path_value(source_path)

    if "region" in frame.columns:
        actual_regions = set(frame["region"].dropna().astype(str))
        if actual_regions and actual_regions != {expected_region}:
            raise ValueError(
                "{} has region values {}, expected {}".format(
                    source, sorted(actual_regions), expected_region
                )
            )
        frame["region"] = expected_region
    else:
        frame.insert(0, "region", expected_region)

    if "fold" in frame.columns:
        try:
            actual_folds = set(pd.to_numeric(frame["fold"].dropna()).astype(int))
        except Exception as exc:
            raise ValueError("{} has non-numeric fold values".format(source)) from exc
        if actual_folds and actual_folds != {expected_fold}:
            raise ValueError(
                "{} has fold values {}, expected {}".format(
                    source, sorted(actual_folds), expected_fold
                )
            )
        frame["fold"] = expected_fold
    else:
        frame.insert(1, "fold", expected_fold)

    leading = ["region", "fold"]
    return frame[leading + [col for col in frame.columns if col not in leading]]


def command_for_row(grid_config, output_root, region, fold, require_complete):
    return [
        sys.executable,
        str(SUMMARY_SCRIPT),
        "--grid-config",
        str(repo_path(grid_config)),
        "--output-dir",
        str(region_fold_dir(output_root, region, fold)),
        "--region",
        str(region),
        "--fold",
        str(int(fold)),
        "--require-complete",
        str(bool(require_complete)).lower(),
    ]


def run_command(cmd, log_path, dry_run):
    log_path = repo_path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "w") as log:
        log.write("$ {}\n\n".format(" ".join(map(str, cmd))))
        if dry_run:
            log.write("Dry run: command not executed.\n")
            return "planned", 0
        log.flush()
        proc = subprocess.run(
            [str(x) for x in cmd],
            cwd=str(repo_path(".")),
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        )
    return ("completed" if proc.returncode == 0 else "failed"), int(proc.returncode)


def collect_panel_outputs(output_root, scope):
    metric_frames = []
    status_frames = []
    runtime_frames = []
    for row in scope.itertuples(index=False):
        out_dir = region_fold_dir(output_root, row.region, row.fold)
        specs = [
            ("metric", "paper_quantile_metric_summary.csv", metric_frames),
            ("status", "quantile_cell_status.csv", status_frames),
            ("runtime", "quantile_cell_runtime.csv", runtime_frames),
        ]
        for _, filename, frames in specs:
            path = out_dir / filename
            if path.exists() and path.stat().st_size > 0:
                frame = pd.read_csv(path)
                frames.append(attach_scope_columns(frame, row.region, row.fold, path))
    return {
        "metric": pd.concat(metric_frames, ignore_index=True) if metric_frames else pd.DataFrame(),
        "status": pd.concat(status_frames, ignore_index=True) if status_frames else pd.DataFrame(),
        "runtime": pd.concat(runtime_frames, ignore_index=True) if runtime_frames else pd.DataFrame(),
    }


def write_status(path, rows):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = ["region", "fold", "status", "return_code", "output_dir", "log", "command"]
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def write_report(output_root, status_rows, panel, panel_label, panel_description):
    out = repo_path(output_root)
    path = out / "region_panel_quantile_summary_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Region-Panel Paper-Quantile Summary\n\n")
        f.write("This report summarizes {} by region/fold.\n\n".format(panel_description))
        f.write("Panel label: `{}`.\n\n".format(panel_label))
        f.write("## Status\n\n")
        f.write("| status | count |\n|---|---:|\n")
        status_counts = pd.Series([row["status"] for row in status_rows]).value_counts()
        for status, count in status_counts.items():
            f.write("| {} | {} |\n".format(status, int(count)))
        metric = panel["metric"]
        if not metric.empty and {"split", "unit", "method_id", "AQL"}.issubset(metric.columns):
            original = metric[(metric["split"] == "test") & (metric["unit"] == "original")].copy()
            f.write("\n## Best Test AQL By Region/Fold\n\n")
            f.write("| region | fold | method_id | AQL |\n|---|---:|---|---:|\n")
            for _, row in original.sort_values(["region", "fold", "AQL"]).groupby(["region", "fold"]).head(1).iterrows():
                f.write("| {} | {} | {} | {:.6g} |\n".format(
                    row["region"], int(row["fold"]), row["method_id"], float(row["AQL"])
                ))
    return path


def summarize_panel(args):
    scope = registry_scope(
        args.registry_csv,
        regions=parse_csv(args.regions, str),
        folds=parse_csv(args.folds, int),
    )
    output_root = repo_path(args.output_root)
    output_root.mkdir(parents=True, exist_ok=True)
    log_dir = output_root / "logs"
    status_rows = []
    for row in scope.itertuples(index=False):
        out_dir = region_fold_dir(output_root, row.region, row.fold)
        log_path = log_dir / "summarize_region={}_fold={}.log".format(row.region, int(row.fold))
        cmd = command_for_row(args.grid_config, output_root, row.region, row.fold, args.require_complete)
        status, return_code = run_command(cmd, log_path, bool(args.dry_run))
        status_rows.append({
            "region": row.region,
            "fold": int(row.fold),
            "status": status,
            "return_code": return_code,
            "output_dir": config_path_value(out_dir),
            "log": config_path_value(log_path),
            "command": " ".join(map(str, cmd)),
        })
        if status == "failed":
            break
    write_status(output_root / "region_panel_quantile_summary_status.csv", status_rows)
    panel = collect_panel_outputs(output_root, scope)
    for key, frame in panel.items():
        if not frame.empty:
            frame.to_csv(output_root / "panel_{}.csv".format(key), index=False)
    report = write_report(
        output_root,
        status_rows,
        panel,
        getattr(args, "panel_label", "local-only DESN/Q-DESN"),
        getattr(args, "panel_description", "local-only DESN/Q-DESN paper-quantile cells"),
    )
    summary = {
        "status": "planned" if bool(args.dry_run) else ("failed" if any(r["status"] == "failed" for r in status_rows) else "completed"),
        "dry_run": bool(args.dry_run),
        "n_region_folds": int(scope.shape[0]),
        "status_csv": config_path_value(output_root / "region_panel_quantile_summary_status.csv"),
        "report": config_path_value(report),
    }
    write_json(output_root / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = summarize_panel(args)
    print(json.dumps(summary, indent=2, sort_keys=True))
    if summary["status"] == "failed":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
