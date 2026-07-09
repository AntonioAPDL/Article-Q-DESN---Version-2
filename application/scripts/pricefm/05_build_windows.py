#!/usr/bin/env python3
"""Build PriceFM rolling-window arrays for the configured pilot or all regions."""

from __future__ import print_function

import argparse
from pathlib import Path

from pricefm_common import (
    load_config, now_utc, parse_bool, parser, pricefm_block, processed_dir,
    refuse_incompatible, require_modules, summarize, write_json,
)


def parse_csv(value, cast=str):
    if value is None or str(value).strip() == "":
        return None
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def ensure_market_index(df, split_time_col, time_col):
    import pandas as pd

    if hasattr(df.index, "tz") and df.index.name == split_time_col:
        return df.sort_index()
    if split_time_col in df.columns:
        df[split_time_col] = pd.to_datetime(df[split_time_col], utc=True)
        return df.sort_values(split_time_col).set_index(split_time_col)
    if time_col in df.columns:
        df[split_time_col] = pd.to_datetime(df[time_col], utc=True) + pd.Timedelta(hours=1)
        return df.sort_values(split_time_col).set_index(split_time_col)
    raise ValueError("Window context must include {} or {}.".format(split_time_col, time_col))


def make_windows_for_region(df_context, target_start, target_end, region, spec):
    import numpy as np
    import pandas as pd

    wspec = spec["windows"]
    features = spec["features"]
    df = df_context.sort_index()
    target_start_ts = pd.Timestamp(target_start, tz="UTC")
    target_end_ts = pd.Timestamp(target_end, tz="UTC")
    lag_cols = ["{}-{}".format(region, f) for f in features["lag"] if "{}-{}".format(region, f) in df.columns]
    lead_cols = ["{}-{}".format(region, f) for f in features["lead"] if "{}-{}".format(region, f) in df.columns]
    label_col = "{}-{}".format(region, features["label"])
    if label_col not in df.columns:
        raise ValueError("Missing label column: {}".format(label_col))
    if not lag_cols or not lead_cols:
        raise ValueError("Missing lag or lead columns for region {}".format(region))

    anchors = df.index[
        (df.index >= target_start_ts)
        & (df.index < target_end_ts)
        & (df.index.hour == int(wspec["anchor_hour"]))
        & (df.index.minute == int(wspec["anchor_minute"]))
    ]
    lag_window = int(wspec["lag_window"])
    lead_window = int(wspec["lead_window"])
    dtype = str(wspec["dtype"])
    idx = df.index
    x_lag = []
    x_lead = []
    y = []
    anchor_list = []

    for anchor in anchors:
        pos = idx.get_loc(anchor)
        if isinstance(pos, slice):
            raise ValueError("Duplicate timestamp found: {}".format(anchor))
        lag_start = pos - lag_window
        lead_end = pos + lead_window
        if lag_start < 0 or lead_end > len(df):
            continue
        lag_df = df.iloc[lag_start:pos][lag_cols]
        lead_df = df.iloc[pos:lead_end][lead_cols]
        label = df.iloc[pos:lead_end][label_col]
        if len(lag_df) != lag_window or len(lead_df) != lead_window or len(label) != lead_window:
            continue
        x_lag.append(lag_df.to_numpy(dtype=dtype))
        x_lead.append(lead_df.to_numpy(dtype=dtype))
        y.append(label.to_numpy(dtype=dtype))
        anchor_list.append(anchor.isoformat())

    return {
        "X_lag": np.asarray(x_lag, dtype=dtype),
        "X_lead": np.asarray(x_lead, dtype=dtype),
        "Y": np.asarray(y, dtype=dtype),
        "anchors": np.asarray(anchor_list, dtype=object),
        "lag_cols": lag_cols,
        "lead_cols": lead_cols,
        "label_col": label_col,
    }


def save_windows_npz(windows, out_path, manifest):
    import numpy as np

    out_path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        out_path,
        X_lag=windows["X_lag"],
        X_lead=windows["X_lead"],
        Y=windows["Y"],
        anchors=windows["anchors"],
        lag_cols=np.asarray(windows["lag_cols"], dtype=object),
        lead_cols=np.asarray(windows["lead_cols"], dtype=object),
        label_col=np.asarray([windows["label_col"]], dtype=object),
    )
    write_json(out_path.with_suffix(".manifest.json"), manifest)


def build_context(split_frames, split_name):
    import pandas as pd

    if split_name == "train":
        return split_frames["train"], "train"
    if split_name == "val":
        return pd.concat([split_frames["train"], split_frames["val"]]), "train+val"
    if split_name == "test":
        return pd.concat([split_frames["train"], split_frames["val"], split_frames["test"]]), "train+val+test"
    raise ValueError("Unknown split: {}".format(split_name))


def main():
    p = parser(__doc__)
    p.add_argument("--pilot-only", type=parse_bool, default=True)
    p.add_argument("--regions", default=None, help="Optional comma-separated region override.")
    p.add_argument("--folds", default=None, help="Optional comma-separated fold override.")
    p.add_argument("--resume", type=parse_bool, default=False)
    args = p.parse_args()
    cfg = load_config(args.config)
    require_modules(["numpy", "pandas", "pyarrow"])

    import pandas as pd

    spec = pricefm_block(cfg)
    root = processed_dir(cfg)
    scaled_root = root / "splits_scaled"
    window_root = root / "windows"
    pilot = spec["pilot"]
    region_override = parse_csv(args.regions, str)
    fold_override = parse_csv(args.folds, int)
    regions = (
        region_override
        if region_override is not None
        else [pilot["region"]]
        if args.pilot_only
        else spec["regions"]
    )
    folds = (
        fold_override
        if fold_override is not None
        else [int(pilot["fold"])]
        if args.pilot_only
        else [int(s["fold"]) for s in spec["splits"]]
    )
    bad_regions = [region for region in regions if region not in spec["regions"]]
    if bad_regions:
        raise ValueError("Unknown PriceFM regions: {}".format(", ".join(bad_regions)))
    known_folds = {int(s["fold"]) for s in spec["splits"]}
    bad_folds = [fold for fold in folds if int(fold) not in known_folds]
    if bad_folds:
        raise ValueError("Unknown PriceFM folds: {}".format(", ".join(map(str, bad_folds))))
    built = []

    for fold in folds:
        split_spec = None
        for candidate in spec["splits"]:
            if int(candidate["fold"]) == fold:
                split_spec = candidate
                break
        if split_spec is None:
            raise ValueError("No split specification for fold {}".format(fold))

        split_dir = scaled_root / "fold_{}".format(fold)
        frames = {}
        for split_name in ("train", "val", "test"):
            frame = pd.read_parquet(split_dir / "{}_scaled.parquet".format(split_name))
            frames[split_name] = ensure_market_index(frame, spec["split_time_col"], spec["time_col"])

        for region in regions:
            for split_name in ("train", "val", "test"):
                context, context_name = build_context(frames, split_name)
                target_start, target_end = split_spec[split_name]
                boundary_mode = (
                    spec["windows"]["train_boundary_mode"]
                    if split_name == "train"
                    else spec["windows"]["validation_boundary_mode"]
                    if split_name == "val"
                    else spec["windows"]["test_boundary_mode"]
                )
                windows = make_windows_for_region(context, target_start, target_end, region, spec)
                out_dir = window_root / "fold_{}".format(fold) / "region={}".format(region)
                out_name = "{}_L{}_H{}_{}.npz".format(
                    split_name,
                    int(spec["windows"]["lag_window"]),
                    int(spec["windows"]["lead_window"]),
                    boundary_mode,
                )
                out_path = out_dir / out_name
                manifest_path = out_path.with_suffix(".manifest.json")
                if args.resume and out_path.exists() and manifest_path.exists():
                    built.append(str(out_path))
                    continue
                refuse_incompatible(out_path, args.force)
                refuse_incompatible(manifest_path, args.force)
                manifest = {
                    "created_at_utc": now_utc(),
                    "fold": fold,
                    "region": region,
                    "split": split_name,
                    "boundary_mode": boundary_mode,
                    "context": context_name,
                    "context_start": str(context.index.min()),
                    "context_end": str(context.index.max()),
                    "target_start": target_start,
                    "target_end": target_end,
                    "time_index": spec["split_time_col"],
                    "market_time_definition": spec["market_time_definition"],
                    "lag_window": int(spec["windows"]["lag_window"]),
                    "lead_window": int(spec["windows"]["lead_window"]),
                    "lag_features": spec["features"]["lag"],
                    "lead_features": spec["features"]["lead"],
                    "label_column": spec["features"]["label"],
                    "n_origins": int(windows["Y"].shape[0]),
                    "X_lag_shape": list(windows["X_lag"].shape),
                    "X_lead_shape": list(windows["X_lead"].shape),
                    "Y_shape": list(windows["Y"].shape),
                    "dtype": str(windows["Y"].dtype),
                    "source_view": str(split_dir),
                }
                save_windows_npz(windows, out_path, manifest)
                built.append(str(out_path))

    summarize(window_root, {"n_window_files": len(built), "files": built})


if __name__ == "__main__":
    main()
