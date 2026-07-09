#!/usr/bin/env python3
"""Convert PriceFM FINAL.csv to canonical Parquet with market_time."""

from __future__ import print_function

from pathlib import Path

from pricefm_common import (
    load_config, now_utc, parser, pricefm_block, raw_csv_path, repo_path,
    refuse_incompatible, require_modules, sha256_file, summarize, write_json,
)


def main():
    p = parser(__doc__)
    args = p.parse_args()
    cfg = load_config(args.config)
    require_modules(["pandas", "pyarrow"])

    import pandas as pd

    spec = pricefm_block(cfg)
    raw_csv = raw_csv_path(cfg)
    out_dir = repo_path(spec["interim_dir"])
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / "FINAL.parquet"
    refuse_incompatible(out, args.force)
    refuse_incompatible(out_dir / "parquet_manifest.json", args.force)

    df = pd.read_csv(raw_csv)
    df[spec["time_col"]] = pd.to_datetime(df[spec["time_col"]], utc=True)
    df = df.sort_values(spec["time_col"]).copy()
    raw_schema_column_count = int(df.shape[1])
    df = df.assign(**{spec["split_time_col"]: df[spec["time_col"]] + pd.Timedelta(hours=1)})
    df.to_parquet(out, index=False, compression="zstd")

    manifest = {
        "created_at_utc": now_utc(),
        "source": str(raw_csv),
        "source_sha256": sha256_file(raw_csv),
        "output": str(out),
        "n_rows": int(len(df)),
        "n_raw_columns": raw_schema_column_count,
        "n_interim_columns": int(df.shape[1]),
        "min_time_utc": str(df[spec["time_col"]].min()),
        "max_time_utc": str(df[spec["time_col"]].max()),
        "min_market_time": str(df[spec["split_time_col"]].min()),
        "max_market_time": str(df[spec["split_time_col"]].max()),
        "market_time_definition": spec["market_time_definition"],
        "compression": "zstd",
        "format": "parquet",
    }
    write_json(out_dir / "parquet_manifest.json", manifest)
    summarize(out, {"n_rows": manifest["n_rows"], "n_interim_columns": manifest["n_interim_columns"]})


if __name__ == "__main__":
    main()
