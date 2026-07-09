#!/usr/bin/env python3
"""Audit PriceFM schema, timestamps, missingness, zeros, and ranges."""

from __future__ import print_function

from pricefm_common import (
    expected_region_columns, interim_parquet_path, load_config, now_utc, parser,
    pricefm_block, refuse_incompatible, repo_path, require_modules, summarize,
    write_json,
)


def main():
    p = parser(__doc__)
    args = p.parse_args()
    cfg = load_config(args.config)
    require_modules(["numpy", "pandas", "pyarrow"])

    import numpy as np
    import pandas as pd

    spec = pricefm_block(cfg)
    interim_dir = repo_path(spec["interim_dir"])
    for name in [
        "audit_time.json",
        "audit_columns.csv",
        "audit_missingness_ranges.csv",
        "schema_manifest.json",
    ]:
        refuse_incompatible(interim_dir / name, args.force)
    df = pd.read_parquet(interim_parquet_path(cfg))
    time_col = spec["time_col"]
    split_col = spec["split_time_col"]
    df[time_col] = pd.to_datetime(df[time_col], utc=True)
    if split_col not in df.columns:
        df[split_col] = df[time_col] + pd.Timedelta(hours=1)
    df[split_col] = pd.to_datetime(df[split_col], utc=True)
    raw_column_count = int(df.drop(columns=[split_col], errors="ignore").shape[1])
    time_index = pd.date_range(
        start=spec["observed_start_utc"],
        end=spec["observed_end_utc"],
        freq=spec["frequency"],
        tz=spec["timezone"],
    )
    df_time = df.sort_values(time_col).set_index(time_col)

    audit_time = {
        "created_at_utc": now_utc(),
        "n_rows": int(len(df)),
        "n_columns": raw_column_count,
        "expected_rows": int(len(time_index)),
        "expected_columns": int(spec["expected_columns"]),
        "min_time": str(df_time.index.min()),
        "max_time": str(df_time.index.max()),
        "min_market_time": str(df[split_col].min()),
        "max_market_time": str(df[split_col].max()),
        "market_time_definition": spec["market_time_definition"],
        "index_is_unique": bool(df_time.index.is_unique),
        "index_is_monotone": bool(df_time.index.is_monotonic_increasing),
        "n_duplicate_timestamps": int(df_time.index.duplicated().sum()),
        "n_missing_expected_timestamps": int(len(time_index.difference(df_time.index))),
        "n_extra_timestamps": int(len(df_time.index.difference(time_index))),
    }
    write_json(interim_dir / "audit_time.json", audit_time)

    column_rows = []
    for region in spec["regions"]:
        for feature in spec["features"]["raw"]:
            col = "{}-{}".format(region, feature)
            column_rows.append({"region": region, "feature": feature, "column": col, "present": col in df.columns})
    pd.DataFrame(column_rows).to_csv(interim_dir / "audit_columns.csv", index=False)

    records = []
    for region in spec["regions"]:
        for feature in spec["features"]["raw"]:
            col = "{}-{}".format(region, feature)
            if col not in df.columns:
                records.append({
                    "region": region, "feature": feature, "column": col, "present": False,
                    "nan_rate": np.nan, "zero_rate": np.nan, "constant": np.nan,
                    "min": np.nan, "p01": np.nan, "median": np.nan, "p99": np.nan,
                    "max": np.nan, "negative_rate": np.nan,
                })
                continue
            s = pd.to_numeric(df[col], errors="coerce")
            records.append({
                "region": region,
                "feature": feature,
                "column": col,
                "present": True,
                "nan_rate": float(s.isna().mean()),
                "zero_rate": float((s == 0).mean()),
                "constant": bool(s.nunique(dropna=True) <= 1),
                "min": float(s.min(skipna=True)),
                "p01": float(s.quantile(0.01)),
                "median": float(s.quantile(0.50)),
                "p99": float(s.quantile(0.99)),
                "max": float(s.max(skipna=True)),
                "negative_rate": float((s < 0).mean()),
            })
    pd.DataFrame(records).to_csv(interim_dir / "audit_missingness_ranges.csv", index=False)

    missing_cols = sorted(set(expected_region_columns(cfg)).difference(df.columns))
    manifest = {
        "created_at_utc": now_utc(),
        "dataset": spec["repo_id"],
        "source_file": str(repo_path(spec["raw_dir"]) / spec["filename"]),
        "interim_file": str(interim_parquet_path(cfg)),
        "observed_start_utc": spec["observed_start_utc"],
        "observed_end_utc": spec["observed_end_utc"],
        "market_time_definition": spec["market_time_definition"],
        "market_time_start": str(df[split_col].min()),
        "market_time_end": str(df[split_col].max()),
        "expected_frequency": spec["frequency"],
        "expected_timestamp_rows": int(spec["expected_rows"]),
        "expected_columns": int(spec["expected_columns"]),
        "expected_regions": len(spec["regions"]),
        "raw_features": spec["features"]["raw"],
        "default_model_lag_features": spec["features"]["lag"],
        "default_model_lead_features": spec["features"]["lead"],
        "missing_expected_columns": missing_cols,
        "audit_files": ["audit_time.json", "audit_columns.csv", "audit_missingness_ranges.csv"],
    }
    write_json(interim_dir / "schema_manifest.json", manifest)
    summarize(interim_dir / "schema_manifest.json", {"missing_expected_columns": len(missing_cols)})


if __name__ == "__main__":
    main()
