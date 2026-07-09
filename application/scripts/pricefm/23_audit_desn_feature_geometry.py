#!/usr/bin/env python3
"""Audit PriceFM DESN feature geometry without fitting models."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

from pricefm_common import repo_path, write_json
from pricefm_desn_adapter import (
    load_config,
    load_smoke_config,
    load_window,
    make_design_chunked,
    normalize_reservoir_config,
    subset_train_origins,
)


DEFAULT_OUTPUT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_de_lu_folds23_feature_geometry_audit_20260604"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--adapter",
        action="append",
        default=[],
        help="Adapter spec as label=path. May be repeated.",
    )
    p.add_argument(
        "--adapter-table",
        default=None,
        help="Optional CSV with label and adapter_dir columns.",
    )
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    p.add_argument("--splits", default="train,val,test")
    p.add_argument("--max-rows-per-split", type=int, default=5000)
    p.add_argument("--compute-rank", default="true")
    return p


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def parse_csv(value, cast=str):
    if value is None or str(value).strip() == "":
        return []
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def rel_path(path):
    path = repo_path(path)
    try:
        return str(path.relative_to(repo_path(".")))
    except ValueError:
        return str(path)


def parse_adapter_spec(value):
    if "=" not in str(value):
        path = str(value)
        label = Path(path).parent.parent.parent.name
    else:
        label, path = str(value).split("=", 1)
    label = label.strip()
    path = path.strip()
    if not label or not path:
        raise ValueError("adapter specs must be label=path")
    return {"label": label, "adapter_dir": path}


def load_adapter_specs(adapter_args, adapter_table=None):
    rows = [parse_adapter_spec(x) for x in adapter_args]
    if adapter_table:
        frame = pd.read_csv(repo_path(adapter_table))
        required = {"label", "adapter_dir"}
        missing = required - set(frame.columns)
        if missing:
            raise ValueError("adapter table missing columns: {}".format(sorted(missing)))
        rows.extend(frame.loc[:, ["label", "adapter_dir"]].to_dict("records"))
    if not rows:
        raise ValueError("At least one --adapter or --adapter-table row is required.")
    seen = set()
    out = []
    for row in rows:
        label = str(row["label"])
        if label in seen:
            raise ValueError("Duplicate adapter label: {}".format(label))
        seen.add(label)
        out.append({"label": label, "adapter_dir": rel_path(row["adapter_dir"])})
    return out


def read_json(path):
    with open(repo_path(path), "r") as f:
        return json.load(f)


def horizon_group_label(horizon):
    horizon = int(horizon)
    start = ((horizon - 1) // 24) * 24 + 1
    end = start + 23
    return "{}-{}".format(start, end)


def sample_indices(n_rows, max_rows, seed=8675309):
    n_rows = int(n_rows)
    if max_rows is None or int(max_rows) <= 0 or n_rows <= int(max_rows):
        return np.arange(n_rows)
    rng = np.random.default_rng(int(seed))
    return np.sort(rng.choice(n_rows, size=int(max_rows), replace=False))


def safe_numeric_matrix(X):
    X = np.asarray(X, dtype=float)
    if X.ndim != 2:
        raise ValueError("matrix must be two-dimensional")
    if not np.all(np.isfinite(X)):
        raise ValueError("matrix contains non-finite values")
    return X


def matrix_geometry(X, include_intercept=True):
    X = safe_numeric_matrix(X)
    if include_intercept and X.shape[1] > 1:
        core = X[:, 1:]
    else:
        core = X
    if core.size == 0:
        return {
            "n_rows_sampled": int(X.shape[0]),
            "n_features": int(X.shape[1]),
            "n_core_features": 0,
            "near_zero_var_count": 0,
            "high_corr_pair_count": 0,
            "effective_rank": 0.0,
            "condition_number": np.nan,
            "min_singular": np.nan,
            "max_singular": np.nan,
        }
    sd = np.std(core, axis=0)
    near_zero = sd <= 1.0e-10
    keep = ~near_zero
    scaled = core[:, keep]
    if scaled.shape[1] == 0:
        return {
            "n_rows_sampled": int(X.shape[0]),
            "n_features": int(X.shape[1]),
            "n_core_features": int(core.shape[1]),
            "near_zero_var_count": int(np.sum(near_zero)),
            "high_corr_pair_count": 0,
            "effective_rank": 0.0,
            "condition_number": np.nan,
            "min_singular": np.nan,
            "max_singular": np.nan,
        }
    scaled = scaled - np.mean(scaled, axis=0)
    scaled = scaled / np.std(scaled, axis=0)
    singular = np.linalg.svd(scaled, full_matrices=False, compute_uv=False)
    singular = singular[np.isfinite(singular) & (singular > 0.0)]
    if singular.size:
        p = singular / np.sum(singular)
        effective_rank = float(np.exp(-np.sum(p * np.log(p))))
        condition = float(np.max(singular) / np.min(singular))
        min_s = float(np.min(singular))
        max_s = float(np.max(singular))
    else:
        effective_rank = 0.0
        condition = np.nan
        min_s = np.nan
        max_s = np.nan
    high_corr = 0
    if scaled.shape[1] > 1:
        corr = np.corrcoef(scaled, rowvar=False)
        upper = corr[np.triu_indices_from(corr, k=1)]
        high_corr = int(np.sum(np.abs(upper) >= 0.99))
    return {
        "n_rows_sampled": int(X.shape[0]),
        "n_features": int(X.shape[1]),
        "n_core_features": int(core.shape[1]),
        "near_zero_var_count": int(np.sum(near_zero)),
        "high_corr_pair_count": high_corr,
        "effective_rank": effective_rank,
        "condition_number": condition,
        "min_singular": min_s,
        "max_singular": max_s,
    }


def split_stats(X, include_intercept=True):
    X = safe_numeric_matrix(X)
    core = X[:, 1:] if include_intercept and X.shape[1] > 1 else X
    return {
        "mean": np.mean(core, axis=0),
        "sd": np.std(core, axis=0),
    }


def split_drift(train_stats, other_stats):
    denom = np.maximum(train_stats["sd"], 1.0e-8)
    mean_shift = np.abs(other_stats["mean"] - train_stats["mean"]) / denom
    scale_ratio = other_stats["sd"] / denom
    return {
        "mean_abs_standardized_shift": float(np.mean(mean_shift)),
        "max_abs_standardized_shift": float(np.max(mean_shift)),
        "median_scale_ratio": float(np.median(scale_ratio)),
        "max_scale_ratio": float(np.max(scale_ratio)),
    }


def feature_response_alignment(X, y, rows, include_intercept=True):
    X = safe_numeric_matrix(X)
    y = np.asarray(y, dtype=float)
    core = X[:, 1:] if include_intercept and X.shape[1] > 1 else X
    meta = pd.DataFrame(rows).copy()
    if "horizon" not in meta.columns:
        return pd.DataFrame()
    meta["horizon_group"] = meta["horizon"].map(horizon_group_label)
    out = []
    for group, idx in meta.groupby("horizon_group").groups.items():
        pos = np.asarray(list(idx), dtype=int)
        yy = y[pos]
        yy_sd = float(np.std(yy))
        if yy_sd <= 1.0e-12 or core.shape[1] == 0:
            max_abs = np.nan
            mean_top10 = np.nan
        else:
            sub = core[pos, :]
            x_sd = np.std(sub, axis=0)
            keep = x_sd > 1.0e-12
            if not np.any(keep):
                max_abs = np.nan
                mean_top10 = np.nan
            else:
                xs = (sub[:, keep] - np.mean(sub[:, keep], axis=0)) / x_sd[keep]
                ys = (yy - np.mean(yy)) / yy_sd
                corr = np.abs(np.mean(xs * ys[:, None], axis=0))
                corr = corr[np.isfinite(corr)]
                if corr.size == 0:
                    max_abs = np.nan
                    mean_top10 = np.nan
                else:
                    max_abs = float(np.max(corr))
                    mean_top10 = float(np.mean(np.sort(corr)[-min(10, corr.size):]))
        out.append({
            "horizon_group": group,
            "n_rows": int(len(pos)),
            "max_abs_feature_response_corr": max_abs,
            "mean_top10_abs_feature_response_corr": mean_top10,
        })
    return pd.DataFrame(out)


def rebuild_split_design(adapter_manifest, split, max_rows):
    smoke = load_smoke_config(adapter_manifest["smoke_config_path"])
    data_cfg = load_config(smoke["data_config"])
    feature_map = smoke["adapter"]["feature_map"]
    feature_dim = int(smoke["adapter"]["feature_dim"])
    seed = int(smoke["adapter"]["seed"])
    include_intercept = bool(smoke["adapter"].get("include_intercept", True))
    row_chunk_size = int(smoke["adapter"].get("row_chunk_size", 2048))
    projection_scale = float(smoke["adapter"].get("projection_scale", 1.0))
    reservoir_config = (
        normalize_reservoir_config(smoke["adapter"], feature_dim)
        if str(feature_map) == "window_reservoir_v1"
        else None
    )
    window = load_window(data_cfg, int(smoke["fold"]), smoke["region"], split)
    training_cfg = smoke.get("training", {})
    if split == "train" and training_cfg.get("train_origin_limit") is not None:
        window, _ = subset_train_origins(
            window,
            training_cfg.get("train_origin_limit"),
            training_cfg.get("train_origin_selection", "tail"),
        )
    X, y, rows, _mapping, _activation = make_design_chunked(
        window,
        split,
        [int(h) for h in smoke["horizons"]],
        [int(h) for h in smoke["horizons"]],
        feature_map,
        feature_dim,
        seed,
        include_intercept=include_intercept,
        row_chunk_size=row_chunk_size,
        mapping=None,
        projection_scale=projection_scale,
        reservoir_config=reservoir_config,
    )
    idx = sample_indices(X.shape[0], max_rows, seed=seed + len(split))
    if idx.size != X.shape[0]:
        rows = [rows[int(i)] for i in idx]
        X = X[idx, :]
        y = y[idx]
    return X, y, rows


def adapter_metadata(label, adapter_dir, manifest):
    feature = manifest["feature_manifest"]
    reservoir = feature.get("reservoir") or {}
    return {
        "label": label,
        "adapter_dir": rel_path(adapter_dir),
        "region": manifest.get("region"),
        "fold": int(manifest.get("fold")),
        "feature_map": feature.get("feature_map"),
        "feature_dim": int(feature.get("feature_dim", 0)),
        "projection_scale": float(feature.get("projection_scale", 1.0)),
        "seed": int(feature.get("seed", 0)),
        "include_intercept": bool(feature.get("include_intercept", True)),
        "reservoir_depth": reservoir.get("depth", ""),
        "reservoir_units": json.dumps(reservoir.get("units", "")),
        "reservoir_alpha": json.dumps(reservoir.get("alpha", "")),
        "reservoir_rho": json.dumps(reservoir.get("rho", "")),
        "reservoir_input_scale": json.dumps(reservoir.get("input_scale", "")),
        "reservoir_state_output": reservoir.get("state_output", ""),
    }


def audit_adapters(specs, splits, max_rows_per_split, compute_rank):
    geometry_rows = []
    activation_rows = []
    rank_rows = []
    drift_rows = []
    alignment_rows = []
    for spec in specs:
        adapter_dir = repo_path(spec["adapter_dir"])
        manifest_path = adapter_dir / "adapter_manifest.json"
        if not manifest_path.exists():
            raise FileNotFoundError("missing adapter manifest: {}".format(manifest_path))
        manifest = read_json(manifest_path)
        meta = adapter_metadata(spec["label"], adapter_dir, manifest)
        geometry_rows.append({
            **meta,
            "horizons": json.dumps(manifest.get("horizons", [])),
            "quantiles": json.dumps(manifest.get("quantiles", [])),
            "train_origin_subset": json.dumps(manifest.get("train_origin_subset", {}), sort_keys=True),
        })
        for split, payload in manifest.get("splits", {}).items():
            if split not in splits:
                continue
            act = payload.get("activation_summary") or {}
            activation_rows.append({
                **meta,
                "split": split,
                "n_rows": int(payload.get("n_rows", 0)),
                "n_origins": int(payload.get("n_origins", 0)),
                "n_features": int(payload.get("n_features", 0)),
                "activation_count": act.get("count", np.nan),
                "activation_mean": act.get("mean", np.nan),
                "activation_sd": act.get("sd", np.nan),
                "activation_min": act.get("min", np.nan),
                "activation_max": act.get("max", np.nan),
                "activation_frac_abs_gt_2": act.get("frac_abs_gt_2", np.nan),
                "activation_frac_abs_gt_4": act.get("frac_abs_gt_4", np.nan),
            })
        if not compute_rank:
            continue
        split_designs = {}
        split_stat_map = {}
        for split in splits:
            if split not in manifest.get("splits", {}):
                continue
            X, y, rows = rebuild_split_design(manifest, split, max_rows_per_split)
            split_designs[split] = (X, y, rows)
            split_stat_map[split] = split_stats(X, include_intercept=meta["include_intercept"])
            rank_rows.append({
                **meta,
                "split": split,
                **matrix_geometry(X, include_intercept=meta["include_intercept"]),
            })
            align = feature_response_alignment(
                X, y, rows, include_intercept=meta["include_intercept"]
            )
            if not align.empty:
                for _, row in align.iterrows():
                    alignment_rows.append({**meta, "split": split, **row.to_dict()})
        if "train" in split_stat_map:
            for split, stats in split_stat_map.items():
                if split == "train":
                    continue
                drift_rows.append({
                    **meta,
                    "reference_split": "train",
                    "comparison_split": split,
                    **split_drift(split_stat_map["train"], stats),
                })
    return {
        "feature_geometry_summary": pd.DataFrame(geometry_rows),
        "activation_summary": pd.DataFrame(activation_rows),
        "feature_rank_condition_summary": pd.DataFrame(rank_rows),
        "feature_split_drift": pd.DataFrame(drift_rows),
        "feature_response_alignment": pd.DataFrame(alignment_rows),
    }


def markdown_table(frame, columns=None, float_digits=6):
    if columns is not None:
        frame = frame.loc[:, [c for c in columns if c in frame.columns]].copy()
    if frame.empty:
        return "_No rows._"
    lines = [
        "| " + " | ".join(frame.columns) + " |",
        "| " + " | ".join(["---"] * len(frame.columns)) + " |",
    ]
    for _, row in frame.iterrows():
        values = []
        for col in frame.columns:
            val = row[col]
            if isinstance(val, float):
                values.append(("{:." + str(float_digits) + "f}").format(val))
            else:
                values.append(str(val).replace("\n", " ").replace("|", "\\|"))
        lines.append("| " + " | ".join(values) + " |")
    return "\n".join(lines)


def make_figures(out_dir, outputs):
    figures = []
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:  # pragma: no cover - environment dependent
        return ["figures skipped: matplotlib unavailable ({})".format(exc)]
    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    rank = outputs["feature_rank_condition_summary"]
    if not rank.empty:
        fig, ax = plt.subplots(figsize=(12, 5.5))
        sub = rank[rank["split"].astype(str).eq("val")].copy()
        sub = sub.sort_values("effective_rank", ascending=False)
        ax.bar(sub["label"], sub["effective_rank"], color="#2563eb")
        ax.set_ylabel("Effective rank, validation sample")
        ax.set_title("Feature Effective Rank By Candidate")
        ax.tick_params(axis="x", labelrotation=35)
        ax.grid(axis="y", alpha=0.22)
        fig.tight_layout()
        path = fig_dir / "validation_effective_rank.png"
        fig.savefig(path, dpi=170)
        plt.close(fig)
        figures.append(rel_path(path))
    drift = outputs["feature_split_drift"]
    if not drift.empty:
        fig, ax = plt.subplots(figsize=(12, 5.5))
        sub = drift[drift["comparison_split"].astype(str).eq("test")].copy()
        sub = sub.sort_values("mean_abs_standardized_shift", ascending=False)
        ax.bar(sub["label"], sub["mean_abs_standardized_shift"], color="#b45309")
        ax.set_ylabel("Mean absolute standardized train-to-test shift")
        ax.set_title("Feature Drift By Candidate")
        ax.tick_params(axis="x", labelrotation=35)
        ax.grid(axis="y", alpha=0.22)
        fig.tight_layout()
        path = fig_dir / "test_feature_drift.png"
        fig.savefig(path, dpi=170)
        plt.close(fig)
        figures.append(rel_path(path))
    return figures


def write_report(out_dir, outputs, args, figures):
    report = out_dir / "feature_geometry_report.md"
    rank = outputs["feature_rank_condition_summary"]
    activation = outputs["activation_summary"]
    drift = outputs["feature_split_drift"]
    align = outputs["feature_response_alignment"]
    with open(report, "w") as f:
        f.write("# PriceFM DESN Feature-Geometry Audit\n\n")
        f.write("Splits: `{}`  \n".format(args.splits))
        f.write("Max rows per split: `{}`  \n".format(args.max_rows_per_split))
        f.write("Computed rank diagnostics: `{}`\n\n".format(parse_bool(args.compute_rank)))
        f.write("## Feature Maps\n\n")
        f.write(markdown_table(
            outputs["feature_geometry_summary"],
            columns=[
                "label", "region", "fold", "feature_map", "feature_dim",
                "projection_scale", "reservoir_units", "reservoir_alpha",
                "reservoir_rho", "reservoir_input_scale",
            ],
        ))
        f.write("\n\n## Rank And Conditioning\n\n")
        f.write(markdown_table(
            rank,
            columns=[
                "label", "split", "n_rows_sampled", "n_features",
                "near_zero_var_count", "high_corr_pair_count",
                "effective_rank", "condition_number",
            ],
        ))
        f.write("\n\n## Activation Summary\n\n")
        f.write(markdown_table(
            activation,
            columns=[
                "label", "split", "activation_sd",
                "activation_frac_abs_gt_2", "activation_frac_abs_gt_4",
                "activation_min", "activation_max",
            ],
        ))
        f.write("\n\n## Train-To-Holdout Feature Drift\n\n")
        f.write(markdown_table(
            drift,
            columns=[
                "label", "comparison_split", "mean_abs_standardized_shift",
                "max_abs_standardized_shift", "median_scale_ratio",
                "max_scale_ratio",
            ],
        ))
        f.write("\n\n## Train-Only / Split Feature-Response Alignment\n\n")
        f.write(markdown_table(
            align,
            columns=[
                "label", "split", "horizon_group", "n_rows",
                "max_abs_feature_response_corr",
                "mean_top10_abs_feature_response_corr",
            ],
        ))
        f.write("\n\n## Interpretation Rules\n\n")
        f.write("- Test split diagnostics are audit-only and must not select models.\n")
        f.write("- Low effective rank, many near-zero columns, high condition numbers, or large drift support feature-map redesign before another grid.\n")
        f.write("- Activation summaries are pre-tanh for `window_desn_v1` and reservoir pre-activation summaries for `window_reservoir_v1`.\n")
        f.write("\n\n## Figures\n\n")
        for fig in figures:
            f.write("- `{}`\n".format(fig))
    return report


def main():
    args = parser().parse_args()
    specs = load_adapter_specs(args.adapter, args.adapter_table)
    splits = parse_csv(args.splits, str)
    if not splits:
        raise ValueError("At least one split is required.")
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    outputs = audit_adapters(
        specs,
        splits,
        args.max_rows_per_split,
        parse_bool(args.compute_rank),
    )
    for name, frame in outputs.items():
        frame.to_csv(out_dir / "{}.csv".format(name), index=False)
    figures = make_figures(out_dir, outputs)
    report = write_report(out_dir, outputs, args, figures)
    write_json(out_dir / "summary.json", {
        "adapter_specs": specs,
        "splits": splits,
        "max_rows_per_split": int(args.max_rows_per_split),
        "compute_rank": parse_bool(args.compute_rank),
        "outputs": {
            **{name: rel_path(out_dir / "{}.csv".format(name)) for name in outputs},
            "report": rel_path(report),
            "figures": figures,
        },
    })
    print(json.dumps({"output_dir": rel_path(out_dir), "report": rel_path(report)}, indent=2))


if __name__ == "__main__":
    main()
