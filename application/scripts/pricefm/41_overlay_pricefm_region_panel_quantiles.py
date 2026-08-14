#!/usr/bin/env python3
"""Overlay patched PriceFM DESN region/fold summaries onto a base panel root."""

from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--base-root", required=True)
    p.add_argument("--patch-root", action="append", required=True)
    p.add_argument("--output-root", required=True)
    p.add_argument("--registry-csv", required=True)
    p.add_argument("--link-mode", choices=["symlink", "copy"], default="symlink")
    p.add_argument("--force", type=parse_bool, default=False)
    p.add_argument("--dry-run", type=parse_bool, default=True)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def region_fold_dir(root, region, fold):
    return repo_path(root) / "region={}".format(region) / "fold={}".format(int(fold))


def registry_scope(registry_csv):
    frame = pd.read_csv(repo_path(registry_csv))
    required = {"region", "fold"}
    missing = required - set(frame.columns)
    if missing:
        raise ValueError("Registry missing required columns: {}".format(sorted(missing)))
    frame = frame[["region", "fold"]].drop_duplicates()
    frame["region"] = frame["region"].astype(str)
    frame["fold"] = frame["fold"].astype(int)
    return frame.sort_values(["region", "fold"]).reset_index(drop=True)


def patch_source_for(row, patch_roots, base_root):
    for root in patch_roots:
        candidate = region_fold_dir(root, row.region, row.fold)
        if (candidate / "summary.json").exists():
            return candidate, "patch"
    base = region_fold_dir(base_root, row.region, row.fold)
    if not (base / "summary.json").exists():
        raise FileNotFoundError(
            "No base or patch summary for region={}, fold={}".format(row.region, int(row.fold))
        )
    return base, "base"


def ensure_clean_target(target, force):
    if target.exists() or target.is_symlink():
        if not bool(force):
            raise FileExistsError("{} already exists; pass --force true to replace overlay links".format(target))
        if target.is_symlink() or target.is_file():
            target.unlink()
        else:
            shutil.rmtree(target)


def materialize_source(source, target, link_mode, force, dry_run):
    if bool(dry_run):
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    ensure_clean_target(target, force)
    if link_mode == "copy":
        shutil.copytree(source, target)
        return
    rel_source = os.path.relpath(source, start=target.parent)
    os.symlink(rel_source, target)


def attach_scope_columns(frame, region, fold, source_path):
    frame = frame.copy()
    expected_region = str(region)
    expected_fold = int(fold)
    if "region" in frame.columns:
        actual = set(frame["region"].dropna().astype(str))
        if actual and actual != {expected_region}:
            raise ValueError("{} has unexpected region values {}".format(source_path, sorted(actual)))
        frame["region"] = expected_region
    else:
        frame.insert(0, "region", expected_region)
    if "fold" in frame.columns:
        actual = set(pd.to_numeric(frame["fold"].dropna()).astype(int))
        if actual and actual != {expected_fold}:
            raise ValueError("{} has unexpected fold values {}".format(source_path, sorted(actual)))
        frame["fold"] = expected_fold
    else:
        frame.insert(1, "fold", expected_fold)
    leading = ["region", "fold"]
    return frame[leading + [col for col in frame.columns if col not in leading]]


def collect_panel_outputs(output_root, scope):
    specs = {
        "metric": "paper_quantile_metric_summary.csv",
        "status": "quantile_cell_status.csv",
        "runtime": "quantile_cell_runtime.csv",
    }
    frames = {key: [] for key in specs}
    for row in scope.itertuples(index=False):
        out_dir = region_fold_dir(output_root, row.region, row.fold)
        for key, filename in specs.items():
            path = out_dir / filename
            if path.exists() and path.stat().st_size > 0:
                frame = pd.read_csv(path)
                frames[key].append(attach_scope_columns(frame, row.region, row.fold, path))
    return {
        key: pd.concat(value, ignore_index=True) if value else pd.DataFrame()
        for key, value in frames.items()
    }


def write_report(output_root, manifest, panel):
    path = repo_path(output_root) / "overlay_panel_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Region-Panel Quantile Overlay\n\n")
        f.write("This overlay keeps base region/fold summaries unless a patch root provides a replacement.\n\n")
        f.write("## Source Counts\n\n")
        f.write("| source_kind | count |\n|---|---:|\n")
        for label, count in manifest["source_kind"].value_counts().items():
            f.write("| {} | {} |\n".format(label, int(count)))
        metric = panel.get("metric", pd.DataFrame())
        if not metric.empty and {"split", "unit", "method_id", "AQL"}.issubset(metric.columns):
            original = metric[(metric["split"] == "test") & (metric["unit"] == "original")]
            f.write("\n## Best Test AQL By Region/Fold\n\n")
            f.write("| region | fold | method_id | AQL |\n|---|---:|---|---:|\n")
            for _, row in original.sort_values(["region", "fold", "AQL"]).groupby(["region", "fold"]).head(1).iterrows():
                f.write("| {} | {} | {} | {:.6g} |\n".format(
                    row["region"], int(row["fold"]), row["method_id"], float(row["AQL"])
                ))
    return path


def build_overlay(args):
    scope = registry_scope(args.registry_csv)
    output_root = repo_path(args.output_root)
    patch_roots = [repo_path(root) for root in args.patch_root]
    rows = []
    if output_root.exists() and any(output_root.iterdir()) and not bool(args.force) and not bool(args.dry_run):
        raise FileExistsError("{} already exists and is not empty; pass --force true".format(output_root))
    if not bool(args.dry_run):
        output_root.mkdir(parents=True, exist_ok=True)
    for row in scope.itertuples(index=False):
        source, source_kind = patch_source_for(row, patch_roots, args.base_root)
        target = region_fold_dir(output_root, row.region, row.fold)
        materialize_source(source, target, args.link_mode, args.force, args.dry_run)
        rows.append({
            "region": row.region,
            "fold": int(row.fold),
            "source_kind": source_kind,
            "source_dir": config_path_value(source),
            "target_dir": config_path_value(target),
            "link_mode": str(args.link_mode),
        })
    manifest = pd.DataFrame(rows).sort_values(["region", "fold"]).reset_index(drop=True)
    panel = {"metric": pd.DataFrame(), "status": pd.DataFrame(), "runtime": pd.DataFrame()}
    report = output_root / "overlay_panel_report.md"
    if not bool(args.dry_run):
        manifest.to_csv(output_root / "overlay_manifest.csv", index=False)
        panel = collect_panel_outputs(output_root, scope)
        for key, frame in panel.items():
            if not frame.empty:
                frame.to_csv(output_root / "panel_{}.csv".format(key), index=False)
        report = write_report(output_root, manifest, panel)
        write_json(output_root / "summary.json", {
            "status": "completed",
            "dry_run": False,
            "base_root": config_path_value(args.base_root),
            "patch_roots": [config_path_value(x) for x in patch_roots],
            "n_region_folds": int(scope.shape[0]),
            "n_patch_folds": int((manifest["source_kind"] == "patch").sum()),
            "overlay_manifest": config_path_value(output_root / "overlay_manifest.csv"),
            "report": config_path_value(report),
        })
    return {
        "status": "planned" if bool(args.dry_run) else "completed",
        "dry_run": bool(args.dry_run),
        "output_root": config_path_value(output_root),
        "n_region_folds": int(scope.shape[0]),
        "n_patch_folds": int((manifest["source_kind"] == "patch").sum()),
        "report": config_path_value(report),
    }


def main():
    args = parser().parse_args()
    summary = build_overlay(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
