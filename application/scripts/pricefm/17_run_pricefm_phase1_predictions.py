#!/usr/bin/env python3
"""Run local PriceFM Phase-I predictions for an article PriceFM fold."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

import joblib
import numpy as np
import pandas as pd

from pricefm_common import (
    fold_spec,
    load_config,
    pricefm_block,
    repo_path,
    sha256_file,
    write_json,
)
from pricefm_metrics import inverse_scale_y, metric_dict, normalize_quantiles


DEFAULT_MODEL = "application/data_local/pricefm/external/PriceFM/Model/PhaseI_best.keras"
DEFAULT_PRICEFM_REPO = "application/data_local/pricefm/external/PriceFM"
DEFAULT_OUTPUT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_de_lu_fold1_apples_to_apples_20260602"
)
DEFAULT_QUANTILES = "0.10,0.25,0.45,0.50,0.55,0.75,0.90"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", default="application/config/pricefm_data_pipeline.yaml")
    p.add_argument("--pricefm-repo", default=DEFAULT_PRICEFM_REPO)
    p.add_argument("--model-path", default=DEFAULT_MODEL)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    p.add_argument("--region", default="DE_LU")
    p.add_argument("--fold", type=int, default=1)
    p.add_argument("--splits", default="test")
    p.add_argument("--quantiles", default=DEFAULT_QUANTILES)
    p.add_argument(
        "--window-mode",
        choices=["operational", "upstream_split_only"],
        default="operational",
        help=(
            "operational uses article windows with lag context and aligns to DESN; "
            "upstream_split_only rebuilds windows inside each split to mimic the "
            "upstream tutorial window semantics."
        ),
    )
    p.add_argument("--batch-size", type=int, default=128)
    p.add_argument("--method-id", default="pricefm_phase1_pretraining")
    return p


def parse_csv_list(value, cast=str):
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def quantile_label(tau):
    return float("{:.12g}".format(float(tau)))


def load_y_scaler(cfg, fold, region):
    spec = pricefm_block(cfg)
    path = repo_path(
        Path(spec["processed_dir"])
        / "scalers"
        / "fold_{}".format(int(fold))
        / "per_region_separate_xy_scalers.joblib"
    )
    scalers = joblib.load(path)
    return scalers[region]["y_scaler"]


def window_npz_path(cfg, fold, region, split):
    spec = pricefm_block(cfg)
    if split == "train":
        mode = spec["windows"]["train_boundary_mode"]
    elif split == "val":
        mode = spec["windows"]["validation_boundary_mode"]
    elif split == "test":
        mode = spec["windows"]["test_boundary_mode"]
    else:
        raise ValueError("Unknown split: {}".format(split))
    return repo_path(
        Path(spec["processed_dir"])
        / "windows"
        / "fold_{}".format(int(fold))
        / "region={}".format(region)
        / "{}_L{}_H{}_{}.npz".format(
            split,
            int(spec["windows"]["lag_window"]),
            int(spec["windows"]["lead_window"]),
            mode,
        )
    )


def load_operational_windows(cfg, fold, split, regions):
    windows = {}
    anchors = None
    for region in regions:
        path = window_npz_path(cfg, fold, region, split)
        if not path.exists():
            raise FileNotFoundError("Missing window file: {}".format(path))
        z = np.load(path, allow_pickle=True)
        local_anchors = np.asarray(z["anchors"]).astype(str)
        if anchors is None:
            anchors = local_anchors
        elif not np.array_equal(anchors, local_anchors):
            raise ValueError("Anchor mismatch for region {} split {}".format(region, split))
        windows[region] = {
            "X_lag": np.asarray(z["X_lag"], dtype=np.float32),
            "X_lead": np.asarray(z["X_lead"], dtype=np.float32),
            "Y": np.asarray(z["Y"], dtype=np.float32),
            "anchors": local_anchors,
            "source": str(path),
        }
    return windows


def ensure_utc_index(df):
    if df.index.name == "market_time":
        out = df.sort_index()
    elif "market_time" in df.columns:
        out = df.copy()
        out["market_time"] = pd.to_datetime(out["market_time"], utc=True)
        out = out.sort_values("market_time").set_index("market_time")
    else:
        raise ValueError("Expected a market_time index or column")
    if out.index.tz is None:
        out.index = out.index.tz_localize("UTC")
    return out


def make_upstream_windows_for_region(df, target_start, target_end, region, cfg):
    spec = pricefm_block(cfg)
    wspec = spec["windows"]
    features = spec["features"]
    df = ensure_utc_index(df)
    target_start_ts = pd.Timestamp(target_start, tz="UTC")
    target_end_ts = pd.Timestamp(target_end, tz="UTC")
    lag_cols = ["{}-{}".format(region, f) for f in features["lag"]]
    lead_cols = ["{}-{}".format(region, f) for f in features["lead"]]
    label_col = "{}-{}".format(region, features["label"])
    missing = [c for c in lag_cols + lead_cols + [label_col] if c not in df.columns]
    if missing:
        raise ValueError("Missing columns for {}: {}".format(region, missing))
    anchors = df.index[
        (df.index >= target_start_ts)
        & (df.index < target_end_ts)
        & (df.index.hour == int(wspec["anchor_hour"]))
        & (df.index.minute == int(wspec["anchor_minute"]))
    ]
    lag_window = int(wspec["lag_window"])
    lead_window = int(wspec["lead_window"])
    idx = df.index
    x_lag = []
    x_lead = []
    y = []
    anchor_list = []
    for anchor in anchors:
        pos = idx.get_loc(anchor)
        if isinstance(pos, slice):
            raise ValueError("Duplicate market_time found: {}".format(anchor))
        lag_start = pos - lag_window
        lead_end = pos + lead_window
        # This intentionally mirrors the upstream tutorial helper, which skips
        # lead_end == len(idx) even though Python slicing could include it.
        if lag_start < 0 or lead_end >= len(idx):
            continue
        x_lag.append(df.iloc[lag_start:pos][lag_cols].to_numpy(dtype=np.float32))
        x_lead.append(df.iloc[pos:lead_end][lead_cols].to_numpy(dtype=np.float32))
        y.append(df.iloc[pos:lead_end][label_col].to_numpy(dtype=np.float32))
        anchor_list.append(anchor.isoformat())
    return {
        "X_lag": np.asarray(x_lag, dtype=np.float32),
        "X_lead": np.asarray(x_lead, dtype=np.float32),
        "Y": np.asarray(y, dtype=np.float32),
        "anchors": np.asarray(anchor_list, dtype=str),
        "source": "rebuilt_from_split_scaled",
    }


def load_upstream_split_only_windows(cfg, fold, split, regions):
    spec = pricefm_block(cfg)
    split_bounds = fold_spec(cfg, fold)[split]
    path = repo_path(
        Path(spec["processed_dir"])
        / "splits_scaled"
        / "fold_{}".format(int(fold))
        / "{}_scaled.parquet".format(split)
    )
    if not path.exists():
        raise FileNotFoundError("Missing scaled split: {}".format(path))
    frame = pd.read_parquet(path)
    windows = {
        region: make_upstream_windows_for_region(frame, split_bounds[0], split_bounds[1], region, cfg)
        for region in regions
    }
    anchors = None
    for region, win in windows.items():
        if anchors is None:
            anchors = win["anchors"]
        elif not np.array_equal(anchors, win["anchors"]):
            raise ValueError("Anchor mismatch for region {} split {}".format(region, split))
    return windows


def stack_model_inputs(windows, regions, target_region):
    x_lag = np.stack([windows[r]["X_lag"] for r in regions], axis=1)
    x_lead = np.stack([windows[r]["X_lead"] for r in regions], axis=1)
    y = windows[target_region]["Y"]
    anchors = windows[target_region]["anchors"]
    gate = graph_gate(regions, [target_region], len(anchors))
    return x_lag, x_lead, gate, y, anchors


def graph_gate(input_regions, active_regions, n_rows):
    active = set(active_regions)
    vec = np.asarray([1.0 if region in active else 0.0 for region in input_regions], dtype=np.float32)
    if vec.sum() <= 0:
        raise ValueError("No active regions are present in input_regions")
    return np.repeat(vec[None, :], repeats=int(n_rows), axis=0)


def response_times(anchors, lead_window):
    anchor_ts = pd.to_datetime(pd.Series(anchors), utc=True)
    offsets = pd.to_timedelta(np.arange(int(lead_window)) * 15, unit="min")
    return [[(a + o).isoformat() for o in offsets] for a in anchor_ts]


def predictions_long(method_id, split, y_scaled, pred_scaled, anchors, quantiles):
    rows = []
    resp = response_times(anchors, pred_scaled.shape[1])
    for i, anchor in enumerate(anchors):
        for h in range(pred_scaled.shape[1]):
            for q_idx, tau in enumerate(quantiles):
                rows.append({
                    "method_id": method_id,
                    "split": split,
                    "origin_id": int(i),
                    "horizon": int(h + 1),
                    "tau": quantile_label(tau),
                    "pred_scaled": float(pred_scaled[i, h, q_idx]),
                    "y_scaled": float(y_scaled[i, h]),
                    "origin_market_time": str(anchor),
                    "response_market_time": resp[i][h],
                })
    return pd.DataFrame(rows)


def add_original_scale(pred, y_scaler):
    out = pred.copy()
    out["pred_original"] = inverse_scale_y(out["pred_scaled"].to_numpy(), y_scaler)
    out["y_original"] = inverse_scale_y(out["y_scaled"].to_numpy(), y_scaler)
    return out


def pivot_metric_arrays(pred, quantiles):
    piv_y = pred.drop_duplicates(["origin_id", "horizon"]).pivot(
        index="origin_id", columns="horizon", values="y_scaled"
    )
    piv_p = pred.pivot_table(
        index="origin_id", columns=["horizon", "tau"], values="pred_scaled", aggfunc="first"
    )
    horizons = sorted(int(h) for h in pred["horizon"].unique())
    y = piv_y.loc[:, horizons].to_numpy()
    blocks = []
    for h in horizons:
        blocks.append(piv_p[h].loc[:, quantiles].to_numpy())
    return y, np.stack(blocks, axis=1), horizons


def metrics_by_split(pred, quantiles, y_scaler):
    rows = []
    horizon_rows = []
    for split, split_df in pred.groupby("split"):
        y_scaled, p_scaled, horizons = pivot_metric_arrays(split_df, quantiles)
        y_orig = inverse_scale_y(y_scaled, y_scaler)
        p_orig = inverse_scale_y(p_scaled, y_scaler)
        for unit, y, p in [
            ("scaled", y_scaled, p_scaled),
            ("original", y_orig, p_orig),
        ]:
            rows.append({
                "method_id": split_df["method_id"].iloc[0],
                "split": split,
                "unit": unit,
                **metric_dict(y, p, quantiles),
            })
            for h_idx, h in enumerate(horizons):
                horizon_rows.append({
                    "method_id": split_df["method_id"].iloc[0],
                    "split": split,
                    "unit": unit,
                    "horizon": int(h),
                    **metric_dict(y[:, [h_idx]], p[:, [h_idx], :], quantiles),
                })
    return pd.DataFrame(rows), pd.DataFrame(horizon_rows)


def load_phase1_model(pricefm_repo, model_path):
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    repo = repo_path(pricefm_repo)
    if str(repo) not in sys.path:
        sys.path.insert(0, str(repo))
    import tensorflow as tf  # noqa: WPS433
    from PriceFM.model import (  # noqa: WPS433
        AbsActivation,
        ExpandDimsLast,
        QuantileLoss,
        ReshapeQuantiles,
        WeightedAvgPool,
    )

    return tf.keras.models.load_model(
        str(repo_path(model_path)),
        custom_objects={
            "AbsActivation": AbsActivation,
            "ExpandDimsLast": ExpandDimsLast,
            "WeightedAvgPool": WeightedAvgPool,
            "ReshapeQuantiles": ReshapeQuantiles,
            "QuantileLoss": QuantileLoss,
        },
        compile=False,
    )


def runtime_environment():
    payload = {
        "python": sys.version,
        "platform": platform.platform(),
    }
    for name in ["numpy", "pandas", "joblib", "sklearn", "tensorflow", "keras", "h5py"]:
        try:
            mod = __import__(name)
            payload[name] = getattr(mod, "__version__", "unknown")
        except Exception as exc:  # pragma: no cover - diagnostic only
            payload[name] = "missing: {}".format(exc)
    return payload


def git_commit_or_none(path):
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(repo_path(path)),
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except Exception:
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def markdown_table(frame):
    if frame.empty:
        return "_No rows._"
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        values = [str(row[col]) for col in cols]
        lines.append("| " + " | ".join(values) + " |")
    return "\n".join(lines)


def main():
    args = parser().parse_args()
    cfg = load_config(args.config)
    spec = pricefm_block(cfg)
    regions = list(spec["regions"])
    if args.region not in regions:
        raise ValueError("region {} is absent from configured regions".format(args.region))
    quantiles = [float(x) for x in normalize_quantiles(parse_csv_list(args.quantiles, float))]
    splits = parse_csv_list(args.splits, str)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    model = load_phase1_model(args.pricefm_repo, args.model_path)
    y_scaler = load_y_scaler(cfg, args.fold, args.region)
    pred_parts = []
    row_audits = []
    for split in splits:
        if args.window_mode == "operational":
            windows = load_operational_windows(cfg, args.fold, split, regions)
        else:
            windows = load_upstream_split_only_windows(cfg, args.fold, split, regions)
        x_lag, x_lead, gate, y, anchors = stack_model_inputs(windows, regions, args.region)
        pred = model.predict(
            {"X_lag_all": x_lag, "X_lead_all": x_lead, "graph_gate": gate},
            batch_size=int(args.batch_size),
            verbose=0,
        )
        pred = np.asarray(pred, dtype=np.float64)
        if pred.shape != (y.shape[0], y.shape[1], len(quantiles)):
            raise ValueError("Unexpected prediction shape {}; expected {}".format(
                pred.shape, (y.shape[0], y.shape[1], len(quantiles))
            ))
        pred_parts.append(predictions_long(args.method_id, split, y, pred, anchors, quantiles))
        row_audits.append({
            "split": split,
            "window_mode": args.window_mode,
            "n_origins": int(y.shape[0]),
            "n_horizons": int(y.shape[1]),
            "first_anchor": str(anchors[0]) if len(anchors) else "",
            "last_anchor": str(anchors[-1]) if len(anchors) else "",
            "x_lag_shape": json.dumps(list(x_lag.shape)),
            "x_lead_shape": json.dumps(list(x_lead.shape)),
            "gate_shape": json.dumps(list(gate.shape)),
            "gate_active_count": int(gate[0].sum()) if len(gate) else 0,
        })

    pred_scaled = pd.concat(pred_parts, ignore_index=True)
    pred_orig = add_original_scale(pred_scaled, y_scaler)
    metric, horizon_metric = metrics_by_split(pred_scaled, quantiles, y_scaler)

    pred_scaled.to_csv(out_dir / "pricefm_phase1_predictions_scaled.csv", index=False)
    pred_orig.to_csv(out_dir / "pricefm_phase1_predictions_original.csv", index=False)
    metric.to_csv(out_dir / "pricefm_phase1_metrics.csv", index=False)
    horizon_metric.to_csv(out_dir / "pricefm_phase1_metric_by_horizon.csv", index=False)
    pd.DataFrame(row_audits).to_csv(out_dir / "pricefm_phase1_row_audit.csv", index=False)
    manifest = {
        "config": str(repo_path(args.config)),
        "pricefm_repo": str(repo_path(args.pricefm_repo)),
        "pricefm_repo_commit": git_commit_or_none(args.pricefm_repo),
        "model_path": str(repo_path(args.model_path)),
        "model_sha256": sha256_file(repo_path(args.model_path)),
        "region": args.region,
        "fold": int(args.fold),
        "splits": splits,
        "quantiles": quantiles,
        "window_mode": args.window_mode,
        "method_id": args.method_id,
        "input_regions": regions,
        "n_input_regions": len(regions),
        "outputs": {
            "predictions_scaled": str(out_dir / "pricefm_phase1_predictions_scaled.csv"),
            "predictions_original": str(out_dir / "pricefm_phase1_predictions_original.csv"),
            "metrics": str(out_dir / "pricefm_phase1_metrics.csv"),
            "horizon_metrics": str(out_dir / "pricefm_phase1_metric_by_horizon.csv"),
            "row_audit": str(out_dir / "pricefm_phase1_row_audit.csv"),
        },
        "environment": runtime_environment(),
    }
    write_json(out_dir / "summary.json", manifest)
    with open(out_dir / "pricefm_phase1_report.md", "w") as f:
        f.write("# PriceFM Phase-I Local Prediction Report\n\n")
        f.write("Region: `{}`  \n".format(args.region))
        f.write("Fold: `{}`  \n".format(args.fold))
        f.write("Window mode: `{}`  \n".format(args.window_mode))
        f.write("Quantiles: `{}`  \n\n".format(quantiles))
        f.write("## Metrics\n\n")
        f.write(markdown_table(metric))
        f.write("\n\n## Row Audit\n\n")
        f.write(markdown_table(pd.DataFrame(row_audits)))
        f.write("\n")
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
