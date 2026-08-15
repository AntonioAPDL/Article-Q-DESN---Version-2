#!/usr/bin/env python3
"""Fit train-only PriceFM scalers and write scaled split views."""

from __future__ import print_function

from pricefm_common import (
    load_config, now_utc, parser, pricefm_block, processed_dir,
    refuse_incompatible, require_modules, summarize, write_json,
)


def fit_transform_scalers_per_region(train, val, test, regions, x_features, y_features):
    from sklearn.preprocessing import RobustScaler

    train_s = train.copy()
    val_s = val.copy()
    test_s = test.copy()
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

        train_s[x_cols] = x_scaler.transform(train[x_cols])
        val_s[x_cols] = x_scaler.transform(val[x_cols])
        test_s[x_cols] = x_scaler.transform(test[x_cols])
        train_s[y_cols] = y_scaler.transform(train[y_cols])
        val_s[y_cols] = y_scaler.transform(val[y_cols])
        test_s[y_cols] = y_scaler.transform(test[y_cols])

        scalers[region] = {
            "x_cols": x_cols,
            "y_cols": y_cols,
            "x_scaler": x_scaler,
            "y_scaler": y_scaler,
        }

    return train_s, val_s, test_s, scalers


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
        for name in ["train_scaled.parquet", "val_scaled.parquet", "test_scaled.parquet"]:
            refuse_incompatible(scaled_dir / name, args.force)
        refuse_incompatible(scaler_dir / "per_region_separate_xy_scalers.joblib", args.force)
        refuse_incompatible(scaler_dir / "scaling_manifest.json", args.force)

        train = pd.read_parquet(split_dir / "train.parquet")
        val = pd.read_parquet(split_dir / "val.parquet")
        test = pd.read_parquet(split_dir / "test.parquet")

        train_s, val_s, test_s, scalers = fit_transform_scalers_per_region(
            train, val, test, spec["regions"], x_features, y_features
        )
        train_s.to_parquet(scaled_dir / "train_scaled.parquet", compression="zstd")
        val_s.to_parquet(scaled_dir / "val_scaled.parquet", compression="zstd")
        test_s.to_parquet(scaled_dir / "test_scaled.parquet", compression="zstd")

        scaler_file = scaler_dir / "per_region_separate_xy_scalers.joblib"
        joblib.dump(scalers, scaler_file)
        manifest = {
            "created_at_utc": now_utc(),
            "fold": fold,
            "scaling_mode": spec["scaling"]["mode"],
            "scaler": "sklearn.preprocessing.RobustScaler",
            "fit_on": "training split only",
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
