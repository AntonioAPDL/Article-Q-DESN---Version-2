#!/usr/bin/env python3
"""Compare region-panel DESN quantiles with fold-aligned PriceFM Phase-I."""

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
PRICEFM_SCRIPT = SCRIPT_DIR / "17_run_pricefm_phase1_predictions.py"
COMPARE_SCRIPT = SCRIPT_DIR / "18_compare_pricefm_phase1_desn_quantiles.py"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--registry-csv", required=True)
    p.add_argument("--config", default="application/config/pricefm_data_pipeline.yaml")
    p.add_argument("--pricefm-root", required=True)
    p.add_argument("--desn-root", required=True)
    p.add_argument("--output-root", required=True)
    p.add_argument("--regions", default=None)
    p.add_argument("--folds", default=None)
    p.add_argument("--split", default="test")
    p.add_argument("--methods", default="pricefm_phase1_pretraining,qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked,normal_rhs_ns,normal_scaled_ridge")
    p.add_argument("--quantiles", default="0.10,0.25,0.45,0.50,0.55,0.75,0.90")
    p.add_argument("--run-pricefm", type=parse_bool, default=True)
    p.add_argument("--dry-run", type=parse_bool, default=True)
    p.add_argument("--desn-panel-label", default="Local DESN/Q-DESN")
    p.add_argument(
        "--desn-panel-description",
        default="local-only DESN/Q-DESN quantile outputs",
    )
    p.add_argument(
        "--comparison-note",
        default="It is not a PriceFM Phase-II graph-neighbor comparison.",
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


def run_logged(cmd, log_path, dry_run):
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


def pricefm_command(config, pricefm_root, region, fold):
    return [
        sys.executable,
        str(PRICEFM_SCRIPT),
        "--config",
        str(repo_path(config)),
        "--region",
        str(region),
        "--fold",
        str(int(fold)),
        "--output-dir",
        str(region_fold_dir(pricefm_root, region, fold)),
    ]


def compare_command(args, region, fold):
    return [
        sys.executable,
        str(COMPARE_SCRIPT),
        "--config",
        str(repo_path(args.config)),
        "--pricefm-output-dir",
        str(region_fold_dir(args.pricefm_root, region, fold)),
        "--desn-output-dir",
        str(region_fold_dir(args.desn_root, region, fold)),
        "--output-dir",
        str(region_fold_dir(args.output_root, region, fold)),
        "--region",
        str(region),
        "--fold",
        str(int(fold)),
        "--split",
        str(args.split),
        "--methods",
        str(args.methods),
        "--quantiles",
        str(args.quantiles),
    ]


def collect_panel_outputs(output_root, scope):
    frames = {"metric": [], "horizon": [], "horizon_group": [], "row_alignment": []}
    files = {
        "metric": "pricefm_vs_desn_metric_summary.csv",
        "horizon": "pricefm_vs_desn_metric_by_horizon.csv",
        "horizon_group": "pricefm_vs_desn_metric_by_horizon_group.csv",
        "row_alignment": "pricefm_vs_desn_row_alignment_audit.csv",
    }
    for row in scope.itertuples(index=False):
        out_dir = region_fold_dir(output_root, row.region, row.fold)
        for key, filename in files.items():
            path = out_dir / filename
            if path.exists() and path.stat().st_size > 0:
                frame = pd.read_csv(path)
                frames[key].append(attach_scope_columns(frame, row.region, row.fold, path))
    return {
        key: pd.concat(value, ignore_index=True) if value else pd.DataFrame()
        for key, value in frames.items()
    }


def delta_flags(metric, baseline="pricefm_phase1_pretraining"):
    if metric.empty:
        return pd.DataFrame()
    original = metric[(metric["split"] == "test") & (metric["unit"] == "original")].copy()
    base = original[original["method_id"].eq(baseline)][["region", "fold", "AQL"]].rename(
        columns={"AQL": "pricefm_phase1_AQL"}
    )
    candidates = original[~original["method_id"].eq(baseline)].copy()
    if candidates.empty or base.empty:
        return pd.DataFrame()
    best = candidates.sort_values(["region", "fold", "AQL"]).groupby(["region", "fold"], as_index=False).head(1)
    out = best.merge(base, on=["region", "fold"], how="left", validate="one_to_one")
    out["delta_abs"] = out["AQL"] - out["pricefm_phase1_AQL"]
    out["delta_rel"] = out["delta_abs"] / out["pricefm_phase1_AQL"].abs().clip(lower=1.0e-8)
    out["decision_label"] = "local_lags_pricefm"
    out.loc[out["delta_abs"] <= 0.0, "decision_label"] = "local_beats_pricefm"
    out.loc[(out["delta_abs"] > 0.0) & (out["delta_rel"] <= 0.05), "decision_label"] = "local_close_to_pricefm"
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def write_status(path, rows):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = ["region", "fold", "kind", "status", "return_code", "output_dir", "log", "command"]
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def write_report(output_root, status_rows, panel, flags, args):
    out = repo_path(output_root)
    path = out / "pricefm_region_panel_quantile_comparison_report.md"
    label = getattr(args, "desn_panel_label", "Local DESN/Q-DESN")
    description = getattr(args, "desn_panel_description", "local-only DESN/Q-DESN quantile outputs")
    note = getattr(args, "comparison_note", "It is not a PriceFM Phase-II graph-neighbor comparison.")
    with open(path, "w") as f:
        f.write("# PriceFM Phase-I vs {} Region-Panel Comparison\n\n".format(label))
        f.write(
            "This report compares {} with fold-aligned PriceFM Phase-I "
            "target-gated predictions.\n\n".format(description)
        )
        if str(note).strip():
            f.write("{}\n\n".format(note))
        f.write("## Status\n\n")
        f.write("| kind | status | count |\n|---|---|---:|\n")
        status = pd.DataFrame(status_rows)
        if not status.empty:
            for (kind, state), sub in status.groupby(["kind", "status"]):
                f.write("| {} | {} | {} |\n".format(kind, state, int(sub.shape[0])))
        if not flags.empty:
            f.write("\n## Best {} Method Versus PriceFM Phase-I\n\n".format(label))
            f.write("| region | fold | best_selected_method | selected_AQL | pricefm_AQL | delta_abs | delta_rel | decision |\n")
            f.write("|---|---:|---|---:|---:|---:|---:|---|\n")
            for _, row in flags.iterrows():
                f.write("| {} | {} | {} | {:.6g} | {:.6g} | {:.6g} | {:.4g} | {} |\n".format(
                    row["region"],
                    int(row["fold"]),
                    row["method_id"],
                    float(row["AQL"]),
                    float(row["pricefm_phase1_AQL"]),
                    float(row["delta_abs"]),
                    float(row["delta_rel"]),
                    row["decision_label"],
                ))
    return path


def compare_panel(args):
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
        if bool(args.run_pricefm):
            cmd = pricefm_command(args.config, args.pricefm_root, row.region, row.fold)
            log = log_dir / "pricefm_phase1_region={}_fold={}.log".format(row.region, int(row.fold))
            status, code = run_logged(cmd, log, bool(args.dry_run))
            status_rows.append({
                "region": row.region,
                "fold": int(row.fold),
                "kind": "pricefm_phase1",
                "status": status,
                "return_code": code,
                "output_dir": config_path_value(region_fold_dir(args.pricefm_root, row.region, row.fold)),
                "log": config_path_value(log),
                "command": " ".join(map(str, cmd)),
            })
            if status == "failed":
                break
        cmd = compare_command(args, row.region, row.fold)
        log = log_dir / "compare_region={}_fold={}.log".format(row.region, int(row.fold))
        status, code = run_logged(cmd, log, bool(args.dry_run))
        status_rows.append({
            "region": row.region,
            "fold": int(row.fold),
            "kind": "comparison",
            "status": status,
            "return_code": code,
            "output_dir": config_path_value(region_fold_dir(args.output_root, row.region, row.fold)),
            "log": config_path_value(log),
            "command": " ".join(map(str, cmd)),
        })
        if status == "failed":
            break
    write_status(output_root / "region_panel_comparison_status.csv", status_rows)
    panel = collect_panel_outputs(output_root, scope)
    for key, frame in panel.items():
        if not frame.empty:
            frame.to_csv(output_root / "panel_{}.csv".format(key), index=False)
    flags = delta_flags(panel["metric"])
    if not flags.empty:
        flags.to_csv(output_root / "selected_competitiveness_flags.csv", index=False)
        flags.to_csv(output_root / "local_only_competitiveness_flags.csv", index=False)
    report = write_report(output_root, status_rows, panel, flags, args)
    summary = {
        "status": "planned" if bool(args.dry_run) else ("failed" if any(r["status"] == "failed" for r in status_rows) else "completed"),
        "dry_run": bool(args.dry_run),
        "run_pricefm": bool(args.run_pricefm),
        "n_region_folds": int(scope.shape[0]),
        "status_csv": config_path_value(output_root / "region_panel_comparison_status.csv"),
        "report": config_path_value(report),
    }
    write_json(output_root / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = compare_panel(args)
    print(json.dumps(summary, indent=2, sort_keys=True))
    if summary["status"] == "failed":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
