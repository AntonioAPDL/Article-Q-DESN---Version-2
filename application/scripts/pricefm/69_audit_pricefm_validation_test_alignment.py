#!/usr/bin/env python3
"""Audit PriceFM median validation/test alignment for current and rescue rows."""

from __future__ import annotations

import argparse
import json

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_MEDIAN_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_l_current_decision_surface_20260624/current_median_registry.csv"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_validation_test_alignment_20260624"
)
DEFAULT_SOURCES = [
    (
        "stage_j_priority0_closeout="
        "application/data_local/pricefm/authoritative/"
        "pricefm_stage_j_information_set_rescue_priority0_closeout_20260623/"
        "rescue_closeout_decisions.csv"
    ),
    (
        "stage_k_regularized_graph="
        "application/data_local/pricefm/authoritative/"
        "pricefm_stage_k_regularized_graph_multiseed_summary_20260623/"
        "multiseed_seed_decisions.csv"
    ),
    (
        "stage_l_si_seed_expansion="
        "application/data_local/pricefm/authoritative/"
        "pricefm_stage_l_si_seed_expansion_summary_20260624/"
        "multiseed_seed_decisions.csv"
    ),
]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--median-registry-csv", default=DEFAULT_MEDIAN_REGISTRY)
    p.add_argument("--diagnostic-source", action="append", default=list(DEFAULT_SOURCES))
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--make-figures", type=parse_bool, default=True)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_csv_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(label, path))
    return pd.read_csv(path)


def parse_source(value):
    if "=" not in str(value):
        raise ValueError("--diagnostic-source must have form label=path")
    label, path = str(value).split("=", 1)
    label = label.strip()
    path = path.strip()
    if not label or not path:
        raise ValueError("--diagnostic-source must have non-empty label and path")
    return label, path


def require_columns(frame, columns, label):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(label, sorted(missing)))


def normalize_keys(frame, label):
    require_columns(frame, ["region", "fold"], label)
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    return out


def numeric(frame, col, label, required=False):
    if col not in frame.columns:
        if required:
            raise ValueError("{} missing required numeric column {}".format(label, col))
        return pd.Series([float("nan")] * len(frame), index=frame.index)
    vals = pd.to_numeric(frame[col], errors="coerce")
    if required and vals.isna().any():
        bad = frame.loc[vals.isna(), ["region", "fold"]].to_dict("records")
        raise ValueError("{} has non-finite {} rows: {}".format(label, col, bad))
    return vals


def bool_series(frame, col, fallback):
    if col in frame.columns:
        text = frame[col].astype(str).str.lower()
        vals = text.isin(["true", "1", "yes", "y"])
        vals = vals.where(~text.isin(["false", "0", "no", "n"]), False)
        return vals.astype(bool)
    return fallback.astype(bool)


def method_family(method_id):
    text = str(method_id)
    if text.startswith("qdesn_exal"):
        return "qdesn_exal"
    if text.startswith("qdesn_al"):
        return "qdesn_al"
    if text.startswith("normal"):
        return "normal_desn"
    return "other"


def current_median_table(median):
    median = normalize_keys(median, "median registry")
    selection = numeric(median, "selection_AQL", "median registry", required=True)
    test = numeric(median, "test_AQL", "median registry", required=True)
    out = pd.DataFrame({
        "region": median["region"],
        "fold": median["fold"],
        "selected_method_id": median["selected_method_id"] if "selected_method_id" in median.columns else "",
        "model_family": [
            method_family(x) for x in (median["selected_method_id"] if "selected_method_id" in median.columns else [""] * len(median))
        ],
        "selection_AQL": selection,
        "test_AQL": test,
        "test_minus_validation_AQL": test - selection,
        "abs_test_minus_validation_AQL": (test - selection).abs(),
    })
    return out.sort_values(["fold", "region"]).reset_index(drop=True)


def diagnostic_rows(label, path):
    frame = normalize_keys(read_csv_required(path, label), label)
    selection = numeric(frame, "selection_AQL", label, required=True)
    test = numeric(frame, "test_AQL", label, required=True)
    current_selection = numeric(frame, "current_selection_AQL", label)
    current_test = numeric(frame, "current_test_AQL", label)
    val_delta = numeric(frame, "val_delta_vs_current", label)
    test_delta = numeric(frame, "test_delta_vs_current", label)
    if val_delta.isna().all() and current_selection.notna().any():
        val_delta = selection - current_selection
    if test_delta.isna().all() and current_test.notna().any():
        test_delta = test - current_test
    validation_improved = bool_series(frame, "validation_improved", val_delta < 0.0)
    test_improved = bool_series(frame, "test_improved", test_delta < 0.0)
    method = frame["method_id"] if "method_id" in frame.columns else frame.get("selected_method_id", "")
    out = pd.DataFrame({
        "source_label": label,
        "source_path": config_path_value(path),
        "region": frame["region"],
        "fold": frame["fold"],
        "experiment_id": frame["experiment_id"] if "experiment_id" in frame.columns else "",
        "method_id": method,
        "model_family": [method_family(x) for x in method],
        "selection_AQL": selection,
        "test_AQL": test,
        "current_selection_AQL": current_selection,
        "current_test_AQL": current_test,
        "val_delta_vs_current": val_delta,
        "test_delta_vs_current": test_delta,
        "validation_improved": validation_improved,
        "test_improved": test_improved,
    })
    out["alignment_label"] = "neither_improved"
    out.loc[out["validation_improved"] & out["test_improved"], "alignment_label"] = "both_improved"
    out.loc[out["validation_improved"] & ~out["test_improved"], "alignment_label"] = "validation_only"
    out.loc[~out["validation_improved"] & out["test_improved"], "alignment_label"] = "test_only"
    out["selection_test_disagree"] = out["validation_improved"] != out["test_improved"]
    return out


def aggregate_alignment(rows):
    if rows.empty:
        return pd.DataFrame()
    grouped = rows.groupby(["source_label", "alignment_label"], dropna=False).size().reset_index(name="n_rows")
    totals = rows.groupby("source_label").size().reset_index(name="source_n_rows")
    out = grouped.merge(totals, on="source_label", how="left")
    out["share"] = out["n_rows"] / out["source_n_rows"].clip(lower=1)
    return out.sort_values(["source_label", "alignment_label"]).reset_index(drop=True)


def source_summary(rows):
    if rows.empty:
        return pd.DataFrame()
    grouped = rows.groupby("source_label")
    out = grouped.agg(
        n_rows=("region", "size"),
        n_region_folds=("region", lambda x: 0),
        n_validation_improved=("validation_improved", "sum"),
        n_test_improved=("test_improved", "sum"),
        n_disagree=("selection_test_disagree", "sum"),
        mean_val_delta=("val_delta_vs_current", "mean"),
        mean_test_delta=("test_delta_vs_current", "mean"),
        max_val_delta=("val_delta_vs_current", "max"),
        max_test_delta=("test_delta_vs_current", "max"),
    ).reset_index()
    key_counts = rows.groupby("source_label")[["region", "fold"]].apply(
        lambda x: x.drop_duplicates().shape[0]
    ).reset_index(name="n_region_folds")
    out = out.drop(columns=["n_region_folds"]).merge(key_counts, on="source_label", how="left")
    out["validation_win_rate"] = out["n_validation_improved"] / out["n_rows"].clip(lower=1)
    out["test_win_rate"] = out["n_test_improved"] / out["n_rows"].clip(lower=1)
    out["disagree_rate"] = out["n_disagree"] / out["n_rows"].clip(lower=1)
    return out.sort_values("source_label").reset_index(drop=True)


def markdown_table(frame, max_rows=25):
    if frame.empty:
        return "_No rows._"
    show = frame.head(max_rows).copy()
    lines = ["| " + " | ".join(show.columns) + " |"]
    lines.append("|" + "|".join(["---"] * len(show.columns)) + "|")
    for _, row in show.iterrows():
        vals = []
        for col in show.columns:
            val = row[col]
            if isinstance(val, float):
                vals.append("{:.6g}".format(val))
            else:
                vals.append(str(val).replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    if len(frame) > max_rows:
        lines.append("| ... | " + " | ".join([""] * (len(show.columns) - 1)) + " |")
    return "\n".join(lines)


def make_figures(out_dir, current, rows):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    paths = []

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.scatter(current["selection_AQL"], current["test_AQL"], s=28, alpha=0.75)
    low = min(current["selection_AQL"].min(), current["test_AQL"].min())
    high = max(current["selection_AQL"].max(), current["test_AQL"].max())
    ax.plot([low, high], [low, high], color="black", linewidth=0.8)
    ax.set_xlabel("Validation AQL")
    ax.set_ylabel("Test AQL")
    ax.set_title("Current Median Registry: Validation vs Test")
    fig.tight_layout()
    path = fig_dir / "stage_m_current_validation_vs_test.png"
    fig.savefig(path, dpi=160)
    plt.close(fig)
    paths.append(path)

    if not rows.empty:
        colors = rows["alignment_label"].map({
            "both_improved": "#2f7d32",
            "test_only": "#c77c02",
            "validation_only": "#3366aa",
            "neither_improved": "#777777",
        }).fillna("#777777")
        fig, ax = plt.subplots(figsize=(7, 5))
        ax.scatter(rows["val_delta_vs_current"], rows["test_delta_vs_current"], c=colors, s=24, alpha=0.75)
        ax.axhline(0.0, color="black", linewidth=0.8)
        ax.axvline(0.0, color="black", linewidth=0.8)
        ax.set_xlabel("Validation delta vs current")
        ax.set_ylabel("Test delta vs current")
        ax.set_title("Rescue Rows: Validation/Test Alignment")
        fig.tight_layout()
        path = fig_dir / "stage_m_rescue_validation_test_deltas.png"
        fig.savefig(path, dpi=160)
        plt.close(fig)
        paths.append(path)

    return [config_path_value(p) for p in paths]


def write_report(out_dir, current, source_summ, align, mismatch, figures):
    report = out_dir / "validation_test_alignment_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Stage-M Validation/Test Alignment Audit\n\n")
        f.write("This report audits whether validation-driven median decisions align ")
        f.write("with held-out test behavior. Test-only improvements are diagnostic ")
        f.write("and are not promotion evidence.\n\n")
        f.write("## Current Median Registry\n\n")
        f.write(markdown_table(current.sort_values("abs_test_minus_validation_AQL", ascending=False).head(15)))
        f.write("\n\n## Diagnostic Source Summary\n\n")
        f.write(markdown_table(source_summ))
        f.write("\n\n## Alignment Labels\n\n")
        f.write(markdown_table(align))
        f.write("\n\n## Largest Disagreements\n\n")
        cols = [
            "source_label", "region", "fold", "experiment_id", "method_id",
            "val_delta_vs_current", "test_delta_vs_current", "alignment_label",
        ]
        f.write(markdown_table(mismatch[cols] if not mismatch.empty else mismatch))
        if figures:
            f.write("\n\n## Figures\n\n")
            for path in figures:
                f.write("- `{}`\n".format(path))
        f.write("\n")
    return report


def summarize(args):
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    current = current_median_table(read_csv_required(args.median_registry_csv, "median registry"))

    frames = []
    source_paths = []
    for value in args.diagnostic_source:
        label, path = parse_source(value)
        frames.append(diagnostic_rows(label, path))
        source_paths.append({"label": label, "path": config_path_value(path)})
    rows = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()
    source_summ = source_summary(rows)
    align = aggregate_alignment(rows)
    mismatch = rows[rows["selection_test_disagree"]].copy() if not rows.empty else pd.DataFrame()
    if not mismatch.empty:
        mismatch["disagreement_magnitude"] = (
            mismatch["val_delta_vs_current"].fillna(0).abs()
            + mismatch["test_delta_vs_current"].fillna(0).abs()
        )
        mismatch = mismatch.sort_values("disagreement_magnitude", ascending=False).reset_index(drop=True)

    current.to_csv(out_dir / "current_median_validation_test.csv", index=False)
    rows.to_csv(out_dir / "diagnostic_validation_test_rows.csv", index=False)
    source_summ.to_csv(out_dir / "diagnostic_source_summary.csv", index=False)
    align.to_csv(out_dir / "alignment_label_summary.csv", index=False)
    mismatch.to_csv(out_dir / "validation_test_mismatch_cases.csv", index=False)
    figures = make_figures(out_dir, current, rows) if bool(args.make_figures) else []
    report = write_report(out_dir, current, source_summ, align, mismatch, figures)

    summary = {
        "n_current_median_rows": int(current.shape[0]),
        "mean_abs_current_test_minus_validation_AQL": float(current["abs_test_minus_validation_AQL"].mean()),
        "n_diagnostic_rows": int(rows.shape[0]),
        "n_mismatch_rows": int(mismatch.shape[0]),
        "diagnostic_sources": source_paths,
        "median_registry_csv": config_path_value(args.median_registry_csv),
        "output_dir": config_path_value(out_dir),
        "report": config_path_value(report),
        "figures": figures,
    }
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    print(json.dumps(summarize(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
