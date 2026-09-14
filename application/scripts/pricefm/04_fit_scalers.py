#!/usr/bin/env python3
"""Fit train-only PriceFM scalers and write scaled split views."""

from __future__ import print_function

from pricefm_common import (
    configured_split_names, load_config, now_utc, parser, pricefm_block,
    processed_dir, refuse_incompatible, require_modules, summarize, write_json,
)


def fit_transform_scalers_per_region(frames, regions, x_features, y_features):
    from sklearn.preprocessing import RobustScaler

    train = frames["train"]
    scaled = {name: frame.copy() for name, frame in frames.items()}
    scalers = {}

    for region in regions:
        x_cols = ["{}-{}".format(region, f) for f in x_features if "{}-{}".format(region, f) in train.columns]
        y_cols = ["{}-{}".format(region, f) for f in y_features if "{}-{}".format(region, f) in train.columns]
        if not x_cols or not y_cols:
            continue

        x_scaler = RobustScaler()
        y_scaler = RobustScaler()
        x_scaler.fit(train[x_cols])
        y_scaler.fit(train[y_cols])

        for name, frame in frames.items():
            scaled[name][x_cols] = x_scaler.transform(frame[x_cols])
            scaled[name][y_cols] = y_scaler.transform(frame[y_cols])

        scalers[region] = {
            "x_cols": x_cols,
            "y_cols": y_cols,
            "x_scaler": x_scaler,
            "y_scaler": y_scaler,
        }

    return scaled, scalers


def main():
    p = parser(__doc__)
    args = p.parse_args()
    cfg = load_config(args.config)
    require_modules(["pandas", "pyarrow", "sklearn", "joblib"])

    import joblib
    import pandas as pd

    spec = pricefm_block(cfg)
    root = processed_dir(cfg)
    split_root = root / "splits"
    scaled_root = root / "splits_scaled"
    scaler_root = root / "scalers"
    x_features = spec["features"]["lead"]
    y_features = [spec["features"]["label"]]

    fitted_folds = []
    for split_spec in spec["splits"]:
        fold = int(split_spec["fold"])
        split_dir = split_root / "fold_{}".format(fold)
        scaled_dir = scaled_root / "fold_{}".format(fold)
        scaler_dir = scaler_root / "fold_{}".format(fold)
        scaled_dir.mkdir(parents=True, exist_ok=True)
        scaler_dir.mkdir(parents=True, exist_ok=True)
        split_names = configured_split_names(split_spec)
        for name in split_names:
            refuse_incompatible(scaled_dir / "{}_scaled.parquet".format(name), args.force)
        refuse_incompatible(scaler_dir / "per_region_separate_xy_scalers.joblib", args.force)
        refuse_incompatible(scaler_dir / "scaling_manifest.json", args.force)

        frames = {
            name: pd.read_parquet(split_dir / "{}.parquet".format(name))
            for name in split_names
        }
        scaled, scalers = fit_transform_scalers_per_region(
            frames, spec["regions"], x_features, y_features
        )
        for name, frame in scaled.items():
            frame.to_parquet(
                scaled_dir / "{}_scaled.parquet".format(name), compression="zstd"
            )

        scaler_file = scaler_dir / "per_region_separate_xy_scalers.joblib"
        joblib.dump(scalers, scaler_file)
        manifest = {
            "created_at_utc": now_utc(),
            "fold": fold,
            "scaling_mode": spec["scaling"]["mode"],
            "scaler": "sklearn.preprocessing.RobustScaler",
            "fit_on": "training split only",
            "configured_splits": split_names,
            "regions": sorted(scalers.keys()),
            "x_features": x_features,
            "y_features": y_features,
            "raw_split_dir": str(split_dir),
            "scaled_split_dir": str(scaled_dir),
            "scaler_file": str(scaler_file),
        }
        write_json(scaler_dir / "scaling_manifest.json", manifest)
        fitted_folds.append(fold)

    summarize(scaler_root, {"fitted_folds": fitted_folds})


if __name__ == "__main__":
    main()
