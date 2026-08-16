#!/usr/bin/env python3
"""Summarize PriceFM train/validation/test response windows for Stage L."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_MANIFEST = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_k_regularized_graph_20260623/manifest.csv"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_l_split_diagnostics_20260624"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest-csv", default=DEFAULT_MANIFEST)
    p.add_argument("--registry-csv", default=None)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--regions", default="LV,SI")
    p.add_argument("--folds", default="1")
    p.add_argument("--splits", default="train,val,test")
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def parse_csv(text, cast=str):
    out = []
    for raw in str(text).split(","):
        raw = raw.strip()
        if raw:
            out.append(cast(raw))
    return out


def parse_jsonish(value):
    if isinstance(value, str):
        text = value.strip()
        if text.startswith("[") or text.startswith("{") or text.startswith('"'):
            return json.loads(text)
    return value


def first_scalar(value):
    value = parse_jsonish(value)
    if isinstance(value, (list, tuple)):
        return value[0] if value else None
    return value


def read_manifest(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("missing manifest: {}".format(path))
    return pd.read_csv(path)


def read_registry(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("missing registry: {}".format(path))
    frame = pd.read_csv(path)
    missing = {"region", "fold"} - set(frame.columns)
    if missing:
        raise ValueError("registry missing columns: {}".format(sorted(missing)))
    frame = frame.copy()
    frame["region"] = frame["region"].astype(str)
    frame["fold"] = pd.to_numeric(frame["fold"], errors="raise").astype(int)
    dup = frame[frame.duplicated(["region", "fold"], keep=False)]
    if not dup.empty:
        keys = dup[["region", "fold"]].drop_duplicates().sort_values(["region", "fold"]).to_dict("records")
        raise ValueError("registry has duplicate region/fold keys: {}".format(keys))
    return frame


def row_region_fold(row):
    region = str(first_scalar(row["regions"] if "regions" in row else row["region"]))
    fold = int(first_scalar(row["folds"] if "folds" in row else row["fold"]))
    return region, fold


def row_value(row, name, default=""):
    if name in row.index and pd.notna(row[name]) and str(row[name]) != "":
        return row[name]
    return default


def choose_source_row(manifest, region, fold):
    rows = []
    for _, row in manifest.iterrows():
        rr, ff = row_region_fold(row)
        if rr == str(region) and int(ff) == int(fold):
            rows.append(row)
    if not rows:
        raise ValueError("No manifest row for region={} fold={}".format(region, fold))
    # Prefer the Stage-K near-miss geometry when available; otherwise use the
    # first row with materialized response files.
    preferred = [
        row for row in rows
        if str(row.get("feature_policy", "")) == "graph_summary_mean"
        and str(row.get("graph_degree", "")) in {"2", "2.0"}
    ]
    for row in preferred + rows:
        cell = cell_dir(row, region, fold)
        if (cell / "adapter" / "y_val.csv").exists():
            return row
    raise FileNotFoundError("No materialized adapter response files for region={} fold={}".format(region, fold))


def choose_registry_row(registry, region, fold):
    rows = registry[
        registry["region"].astype(str).eq(str(region))
        & registry["fold"].astype(int).eq(int(fold))
    ]
    if rows.empty:
        raise ValueError("No registry row for region={} fold={}".format(region, fold))
    row = rows.iloc[0]
    adapter = registry_adapter_dir(row, region, fold)
    if (adapter / "y_val.csv").exists():
        return row
    raise FileNotFoundError("No materialized adapter response files for region={} fold={}".format(region, fold))


def cell_dir(row, region, fold):
    return (
        repo_path(row["run_dir"])
        / "cells" / "region={}".format(region) / "fold={}".format(int(fold))
    )


def registry_adapter_dir(row, region, fold):
    adapter_dir = row_value(row, "adapter_dir", "")
    if adapter_dir:
        return repo_path(adapter_dir)
    model_dir = row_value(row, "model_dir", "")
    if model_dir:
        model_path = repo_path(model_dir)
        candidate = model_path.parent / "adapter"
        if candidate.exists():
            return candidate
    run_dir = row_value(row, "run_dir", "")
    if run_dir:
        return repo_path(run_dir) / "cells" / "region={}".format(region) / "fold={}".format(int(fold)) / "adapter"
    raise ValueError("registry row lacks adapter_dir, model_dir, and run_dir")


def source_adapter_dir(row, region, fold):
    if "adapter_dir" in row.index or "model_dir" in row.index:
        return registry_adapter_dir(row, region, fold)
    return cell_dir(row, region, fold) / "adapter"


def read_y(path):
    vals = pd.read_csv(path, header=None).iloc[:, 0]
    return pd.to_numeric(vals, errors="coerce").dropna()


def split_summary(row, region, fold, split):
    adapter = source_adapter_dir(row, region, fold)
    y_path = adapter / "y_{}.csv".format(split)
    rows_path = adapter / "rows_{}.csv".format(split)
    y = read_y(y_path)
    meta = pd.read_csv(rows_path) if rows_path.exists() else pd.DataFrame()
    q = y.quantile([0.1, 0.25, 0.5, 0.75, 0.9]) if not y.empty else pd.Series(dtype=float)
    out = {
        "region": region,
        "fold": int(fold),
        "split": split,
        "experiment_id": str(row_value(row, "id", row_value(row, "experiment_id", ""))),
        "feature_policy": str(row_value(row, "feature_policy", "")),
        "graph_degree": row_value(row, "graph_degree", ""),
        "n": int(y.shape[0]),
        "mean_y_scaled": float(y.mean()) if not y.empty else float("nan"),
        "sd_y_scaled": float(y.std(ddof=0)) if not y.empty else float("nan"),
        "min_y_scaled": float(y.min()) if not y.empty else float("nan"),
        "q10_y_scaled": float(q.loc[0.1]) if 0.1 in q.index else float("nan"),
        "q25_y_scaled": float(q.loc[0.25]) if 0.25 in q.index else float("nan"),
        "median_y_scaled": float(q.loc[0.5]) if 0.5 in q.index else float("nan"),
        "q75_y_scaled": float(q.loc[0.75]) if 0.75 in q.index else float("nan"),
        "q90_y_scaled": float(q.loc[0.9]) if 0.9 in q.index else float("nan"),
        "max_y_scaled": float(y.max()) if not y.empty else float("nan"),
    }
    if not meta.empty and "response_market_time" in meta.columns:
        out["first_response_market_time"] = str(meta["response_market_time"].iloc[0])
        out["last_response_market_time"] = str(meta["response_market_time"].iloc[-1])
        out["n_origins"] = int(meta["origin_id"].nunique()) if "origin_id" in meta.columns else None
        out["n_horizons"] = int(meta["horizon"].nunique()) if "horizon" in meta.columns else None
    return out


def contrast_rows(summary):
    rows = []
    for (region, fold), sub in summary.groupby(["region", "fold"]):
        splits = {r["split"]: r for _, r in sub.iterrows()}
        for left, right in [("val", "train"), ("test", "val"), ("test", "train")]:
            if left not in splits or right not in splits:
                continue
            lrow, rrow = splits[left], splits[right]
            rows.append({
                "region": region,
                "fold": int(fold),
                "contrast": "{}_minus_{}".format(left, right),
                "mean_delta": float(lrow["mean_y_scaled"] - rrow["mean_y_scaled"]),
                "sd_ratio": float(lrow["sd_y_scaled"] / rrow["sd_y_scaled"]) if float(rrow["sd_y_scaled"]) != 0 else float("nan"),
                "median_delta": float(lrow["median_y_scaled"] - rrow["median_y_scaled"]),
                "q90_delta": float(lrow["q90_y_scaled"] - rrow["q90_y_scaled"]),
                "q10_delta": float(lrow["q10_y_scaled"] - rrow["q10_y_scaled"]),
            })
    return pd.DataFrame(rows)


def markdown_table(frame):
    if frame.empty:
        return "_No rows._"
    text_frame = frame.copy()
    for col in text_frame.columns:
        text_frame[col] = text_frame[col].map(lambda x: "" if pd.isna(x) else str(x))
    lines = []
    cols = list(text_frame.columns)
    lines.append("| " + " | ".join(cols) + " |")
    lines.append("|" + "|".join(["---"] * len(cols)) + "|")
    for _, row in text_frame.iterrows():
        vals = [str(row[col]).replace("|", "\\|") for col in cols]
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines)


def write_report(out_dir, summary, contrasts):
    report = out_dir / "stage_l_split_diagnostics_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Stage-L Split Diagnostics\n\n")
        f.write("This diagnostic summarizes scaled response distributions across ")
        f.write("train, validation, and test windows for Stage-L candidate rows.\n\n")
        f.write("## Split Summary\n\n")
        f.write(markdown_table(summary))
        f.write("\n\n## Split Contrasts\n\n")
        f.write(markdown_table(contrasts) if not contrasts.empty else "_No contrasts._")
        f.write("\n")
    return report


def summarize(args):
    registry_csv = getattr(args, "registry_csv", None)
    registry = read_registry(registry_csv) if registry_csv else None
    manifest = None if registry is not None else read_manifest(args.manifest_csv)
    regions = parse_csv(args.regions, str)
    folds = parse_csv(args.folds, int)
    splits = parse_csv(args.splits, str)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    source_rows = []
    if registry is not None:
        key_frame = registry[["region", "fold"]].drop_duplicates().copy()
        if regions:
            key_frame = key_frame[key_frame["region"].astype(str).isin(regions)]
        if folds:
            key_frame = key_frame[key_frame["fold"].astype(int).isin(folds)]
        key_pairs = list(key_frame.sort_values(["region", "fold"]).itertuples(index=False, name=None))
    else:
        key_pairs = [(region, fold) for region in regions for fold in folds]

    for region, fold in key_pairs:
        row = choose_registry_row(registry, region, fold) if registry is not None else choose_source_row(manifest, region, fold)
        source_rows.append({
            "region": region,
            "fold": int(fold),
            "experiment_id": str(row_value(row, "id", row_value(row, "experiment_id", ""))),
            "run_dir": config_path_value(row_value(row, "run_dir", "")),
            "adapter_dir": config_path_value(source_adapter_dir(row, region, fold)),
            "feature_policy": str(row_value(row, "feature_policy", "")),
            "graph_degree": row_value(row, "graph_degree", ""),
        })
        for split in splits:
            rows.append(split_summary(row, region, fold, split))
    summary = pd.DataFrame(rows).sort_values(["region", "fold", "split"]).reset_index(drop=True)
    contrasts = contrast_rows(summary)
    source = pd.DataFrame(source_rows).sort_values(["region", "fold"]).reset_index(drop=True)
    summary.to_csv(out_dir / "split_response_summary.csv", index=False)
    contrasts.to_csv(out_dir / "split_response_contrasts.csv", index=False)
    source.to_csv(out_dir / "source_cells.csv", index=False)
    report = write_report(out_dir, summary, contrasts)
    payload = {
        "n_regions": int(source["region"].nunique()) if not source.empty else 0,
        "n_folds": int(source["fold"].nunique()) if not source.empty else 0,
        "n_region_folds": int(source.shape[0]),
        "n_split_rows": int(summary.shape[0]),
        "n_contrast_rows": int(contrasts.shape[0]),
        "registry_csv": config_path_value(registry_csv) if registry_csv else "",
        "manifest_csv": config_path_value(args.manifest_csv) if not registry_csv else "",
        "output_dir": config_path_value(out_dir),
        "report": config_path_value(report),
    }
    write_json(out_dir / "summary.json", payload)
    return payload


def main():
    args = parser().parse_args()
    payload = summarize(args)
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
