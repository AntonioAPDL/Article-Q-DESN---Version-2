#!/usr/bin/env python3
"""Create one exploratory all-feature PriceFM figure per region."""

from __future__ import print_function

import csv
from pathlib import Path

from pricefm_common import (
    interim_parquet_path, load_config, now_utc, parser, pricefm_block,
    refuse_incompatible, repo_path, require_modules, summarize, write_json,
)


FEATURE_STYLES = {
    "generation": {"color": "#4B5563", "label": "Generation"},
    "load": {"color": "#2563EB", "label": "Load"},
    "price": {"color": "#B91C1C", "label": "Price"},
    "solar": {"color": "#D97706", "label": "Solar"},
    "wind": {"color": "#059669", "label": "Wind"},
}


def parse_regions(value, configured_regions):
    if value.strip().lower() == "all":
        return list(configured_regions)
    regions = [x.strip() for x in value.split(",") if x.strip()]
    unknown = sorted(set(regions).difference(configured_regions))
    if unknown:
        raise ValueError("Unknown PriceFM regions: {}".format(", ".join(unknown)))
    return regions


def make_daily_summaries(df, time_col, value_cols, q_low, q_high):
    value_df = df.set_index(time_col)[value_cols].sort_index()
    grouped = value_df.resample("1D")
    return {
        "mean": grouped.mean().reset_index(),
        "median": grouped.median().reset_index(),
        "q_low": grouped.quantile(q_low).reset_index(),
        "q_high": grouped.quantile(q_high).reset_index(),
        "missing": value_df.isna().sum().to_dict(),
    }


def make_region_figure(region, daily, spec, out_path):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.dates as mdates
    import matplotlib.pyplot as plt

    eda = spec["eda"]["region_feature_overview"]
    features = spec["features"]["raw"]
    q_low, q_high = [float(x) for x in eda["ribbon"]]
    summary_line = eda["summary_line"]
    time_col = eda["time_index"]

    fig, axes = plt.subplots(
        nrows=len(features),
        ncols=1,
        sharex=True,
        figsize=(float(eda["width"]), float(eda["height"])),
        constrained_layout=False,
    )
    if len(features) == 1:
        axes = [axes]

    missing = {}
    x = daily["median"][time_col]
    for ax, feature in zip(axes, features):
        col = "{}-{}".format(region, feature)
        style = FEATURE_STYLES.get(feature, {"color": "#111827", "label": feature})
        if col not in daily["median"].columns:
            ax.text(0.5, 0.5, "Missing column: {}".format(col), transform=ax.transAxes, ha="center", va="center")
            ax.set_ylabel(style["label"])
            missing[feature] = None
            continue

        ax.fill_between(
            x,
            daily["q_low"][col],
            daily["q_high"][col],
            color=style["color"],
            alpha=0.16,
            linewidth=0,
            label="{:.0f}-{:.0f}% daily band".format(q_low * 100, q_high * 100),
        )
        ax.plot(
            x,
            daily[summary_line][col],
            color=style["color"],
            linewidth=1.15,
            label="daily {}".format(summary_line),
        )
        ax.axhline(0, color="#9CA3AF", linewidth=0.65, alpha=0.7)
        ax.set_ylabel(style["label"])
        ax.grid(True, axis="y", color="#E5E7EB", linewidth=0.7)
        ax.grid(False, axis="x")
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)
        missing[feature] = int(daily["missing"].get(col, 0))

    axes[0].legend(loc="upper right", frameon=False, fontsize=8)
    axes[-1].xaxis.set_major_locator(mdates.MonthLocator(interval=4))
    axes[-1].xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m"))
    for label in axes[-1].get_xticklabels():
        label.set_rotation(0)
        label.set_ha("center")

    start = str(x.min())
    end = str(x.max())
    fig.suptitle(
        "PriceFM Region Overview: {}".format(region),
        fontsize=16,
        fontweight="bold",
        x=0.01,
        y=0.988,
        ha="left",
    )
    fig.text(
        0.01,
        0.952,
        "Daily {} with {:.0f}-{:.0f}% daily band; market_time window {} to {}".format(
            summary_line, q_low * 100, q_high * 100, start[:10], end[:10]
        ),
        fontsize=9,
        color="#374151",
        ha="left",
        va="top",
    )
    fig.text(
        0.99,
        0.025,
        "Source: RunyaoYu/PriceFM FINAL.csv; raw 15-minute data summarized daily",
        fontsize=8,
        color="#6B7280",
        ha="right",
    )
    fig.subplots_adjust(left=0.06, right=0.99, top=0.91, bottom=0.085, hspace=0.08)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=int(eda["dpi"]))
    plt.close(fig)
    return missing


def main():
    p = parser(__doc__)
    p.add_argument("--regions", default="all", help="Comma-separated region list, or 'all'.")
    args = p.parse_args()
    cfg = load_config(args.config)
    require_modules(["pandas", "pyarrow", "matplotlib"])

    import pandas as pd

    spec = pricefm_block(cfg)
    eda = spec["eda"]["region_feature_overview"]
    regions = parse_regions(args.regions, spec["regions"])
    out_dir = repo_path(eda["output_dir"])
    manifest_path = out_dir / "region_feature_overview_manifest.json"
    index_path = out_dir / "region_feature_overview_index.csv"
    refuse_incompatible(manifest_path, args.force)
    refuse_incompatible(index_path, args.force)

    time_col = eda["time_index"]
    cols = [time_col]
    if spec["time_col"] != time_col:
        cols.append(spec["time_col"])
    for region in regions:
        cols.extend(["{}-{}".format(region, f) for f in spec["features"]["raw"]])
    cols = list(dict.fromkeys(cols))
    df = pd.read_parquet(interim_parquet_path(cfg), columns=cols)
    df[time_col] = pd.to_datetime(df[time_col], utc=True)
    start = pd.Timestamp(eda["start"], tz="UTC")
    end = pd.Timestamp(eda["end"], tz="UTC")
    df = df.loc[(df[time_col] >= start) & (df[time_col] < end)].copy()
    value_cols = [c for c in cols if c not in [time_col, spec["time_col"]]]
    daily = make_daily_summaries(df[[time_col] + value_cols], time_col, value_cols, eda["ribbon"][0], eda["ribbon"][1])

    rows = []
    figure_format = eda["figure_format"].lstrip(".")
    for region in regions:
        out_path = out_dir / "region_feature_overview_{}.{}".format(region, figure_format)
        refuse_incompatible(out_path, args.force)
        missing = make_region_figure(region, daily, spec, out_path)
        rows.append({
            "region": region,
            "figure": str(out_path),
            "format": figure_format,
            "time_index": time_col,
            "start": eda["start"],
            "end": eda["end"],
            "aggregation": eda["aggregation"],
            "summary_line": eda["summary_line"],
            "ribbon_low": eda["ribbon"][0],
            "ribbon_high": eda["ribbon"][1],
            "n_rows": int(len(df)),
            "missing_generation": missing.get("generation"),
            "missing_load": missing.get("load"),
            "missing_price": missing.get("price"),
            "missing_solar": missing.get("solar"),
            "missing_wind": missing.get("wind"),
        })

    out_dir.mkdir(parents=True, exist_ok=True)
    with open(index_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    manifest = {
        "created_at_utc": now_utc(),
        "description": "One all-feature exploratory PriceFM figure per region.",
        "source_file": str(interim_parquet_path(cfg)),
        "output_dir": str(out_dir),
        "index_file": str(index_path),
        "n_regions": len(regions),
        "regions": regions,
        "features": spec["features"]["raw"],
        "time_index": time_col,
        "market_time_definition": spec["market_time_definition"],
        "start": eda["start"],
        "end": eda["end"],
        "aggregation": eda["aggregation"],
        "summary_line": eda["summary_line"],
        "ribbon": eda["ribbon"],
        "figure_format": figure_format,
        "dpi": int(eda["dpi"]),
    }
    write_json(manifest_path, manifest)
    summarize(out_dir, {"n_regions": len(regions), "index_file": str(index_path)})


if __name__ == "__main__":
    main()
