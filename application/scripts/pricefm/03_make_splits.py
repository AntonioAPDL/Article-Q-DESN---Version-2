#!/usr/bin/env python3
"""Build half-open market_time PriceFM train/validation/test splits."""

from __future__ import print_function

from pathlib import Path

from pricefm_common import (
    interim_parquet_path, load_config, now_utc, parser, pricefm_block, processed_dir,
    refuse_incompatible, require_modules, summarize, write_json,
)


def subset_half_open(df, start, end):
    import pandas as pd

    start_ts = pd.Timestamp(start, tz="UTC")
    end_ts = pd.Timestamp(end, tz="UTC")
    return df.loc[(df.index >= start_ts) & (df.index < end_ts)].copy()


def main():
    p = parser(__doc__)
    args = p.parse_args()
    cfg = load_config(args.config)
    require_modules(["pandas", "pyarrow"])

    import pandas as pd

    spec = pricefm_block(cfg)
    split_dir = processed_dir(cfg) / "splits"
    split_dir.mkdir(parents=True, exist_ok=True)
    refuse_incompatible(split_dir / "split_registry.csv", args.force)
    refuse_incompatible(split_dir / "split_manifest.json", args.force)

    df = pd.read_parquet(interim_parquet_path(cfg))
    df[spec["time_col"]] = pd.to_datetime(df[spec["time_col"]], utc=True)
    if spec["split_time_col"] not in df.columns:
        df[spec["split_time_col"]] = df[spec["time_col"]] + pd.Timedelta(hours=1)
    df[spec["split_time_col"]] = pd.to_datetime(df[spec["split_time_col"]], utc=True)
    df = df.sort_values(spec["split_time_col"]).set_index(spec["split_time_col"])

    rows = []
    for split_spec in spec["splits"]:
        fold = int(split_spec["fold"])
        out_dir = split_dir / "fold_{}".format(fold)
        out_dir.mkdir(parents=True, exist_ok=True)
        parts = {
            "train": subset_half_open(df, split_spec["train"][0], split_spec["train"][1]),
            "val": subset_half_open(df, split_spec["val"][0], split_spec["val"][1]),
            "test": subset_half_open(df, split_spec["test"][0], split_spec["test"][1]),
        }
        for name, part in parts.items():
            out_file = out_dir / "{}.parquet".format(name)
            refuse_incompatible(out_file, args.force)
            part.to_parquet(out_file, compression="zstd")
            start, end = split_spec[name]
            rows.append({
                "fold": fold,
                "split": name,
                "mode": "half_open",
                "time_index": spec["split_time_col"],
                "market_time_definition": spec["market_time_definition"],
                "start": start,
                "end": end,
                "n_rows": int(len(part)),
                "min_market_time": str(part.index.min()) if len(part) else "",
                "max_market_time": str(part.index.max()) if len(part) else "",
                "min_time_utc": str(part[spec["time_col"]].min()) if len(part) else "",
                "max_time_utc": str(part[spec["time_col"]].max()) if len(part) else "",
            })

    registry = pd.DataFrame(rows)
    registry.to_csv(split_dir / "split_registry.csv", index=False)
    manifest = {
        "created_at_utc": now_utc(),
        "time_index": spec["split_time_col"],
        "market_time_definition": spec["market_time_definition"],
        "mode": "half_open",
        "registry_file": str(split_dir / "split_registry.csv"),
        "n_rows": int(len(registry)),
    }
    write_json(split_dir / "split_manifest.json", manifest)
    summarize(split_dir / "split_registry.csv", {"n_registry_rows": int(len(registry))})


if __name__ == "__main__":
    main()
