#!/usr/bin/env python3
"""Build article-facing PriceFM tables from Stage-M diagnostics."""

from __future__ import annotations

import argparse
import json

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_DECISION_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624"
)
DEFAULT_ALIGNMENT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_validation_test_alignment_20260624"
)
DEFAULT_SPLIT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_split_diagnostics_20260624"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_article_tables_20260624"
)
PAPER_QUANTILES = "0.10,0.25,0.45,0.50,0.55,0.75,0.90"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--decision-dir", default=DEFAULT_DECISION_DIR)
    p.add_argument("--alignment-dir", default=DEFAULT_ALIGNMENT_DIR)
    p.add_argument("--split-diagnostics-dir", default=DEFAULT_SPLIT_DIR)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
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


def read_csv_optional(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return pd.DataFrame()
    return pd.read_csv(path)


def numeric(frame, col):
    return pd.to_numeric(frame[col], errors="coerce")


def compact_decision_table(surface):
    cols = [
        "region", "fold", "best_local_method", "information_set",
        "local_AQL", "pricefm_AQL", "delta_abs", "delta_rel", "decision_label",
    ]
    out = surface[cols].copy()
    out = out.sort_values(["fold", "region"]).reset_index(drop=True)
    return out


def fold_table(by_fold):
    cols = [
        "fold", "n_region_folds", "n_local_wins", "win_rate",
        "mean_local_AQL", "mean_pricefm_AQL", "mean_delta_abs",
    ]
    return by_fold[cols].sort_values("fold").reset_index(drop=True)


def method_information_table(by_method, by_info):
    method = by_method.copy()
    method.insert(0, "summary_type", "method_family")
    method = method.rename(columns={"model_family": "group"})
    info = by_info.copy()
    info.insert(0, "summary_type", "information_set")
    info = info.rename(columns={"information_set": "group"})
    cols = [
        "summary_type", "group", "n_region_folds", "n_local_wins",
        "win_rate", "mean_delta_abs", "median_delta_abs",
    ]
    return pd.concat([method[cols], info[cols]], ignore_index=True)


def alignment_table(source_summary):
    if source_summary.empty:
        return pd.DataFrame()
    cols = [
        "source_label", "n_rows", "n_region_folds", "n_validation_improved",
        "n_test_improved", "n_disagree", "validation_win_rate",
        "test_win_rate", "disagree_rate", "mean_val_delta", "mean_test_delta",
    ]
    return source_summary[cols].sort_values("source_label").reset_index(drop=True)


def split_shift_table(split_contrasts):
    if split_contrasts.empty:
        return pd.DataFrame()
    keep = split_contrasts[split_contrasts["contrast"].isin(["val_minus_train", "test_minus_val"])].copy()
    return keep.sort_values(["region", "fold", "contrast"]).reset_index(drop=True)


def figure_index(decision_dir, alignment_dir):
    rows = []
    for label, root in [("decision_surface", decision_dir), ("validation_alignment", alignment_dir)]:
        fig_dir = repo_path(root) / "figures"
        if not fig_dir.exists():
            continue
        for path in sorted(fig_dir.glob("*.png")):
            rows.append({
                "figure_group": label,
                "figure_path": config_path_value(path),
                "filename": path.name,
            })
    return pd.DataFrame(rows)


def comparability_guardrails(decision):
    n_regions = int(decision["region"].nunique()) if "region" in decision else 0
    n_folds = int(decision["fold"].nunique()) if "fold" in decision else 0
    n_rows = int(decision.shape[0])
    n_graph = int(decision["information_set"].eq("pricefm_graph_inputs").sum())
    n_target = int(decision["information_set"].eq("target_only").sum())
    return pd.DataFrame([
        {
            "topic": "benchmark",
            "status": "comparable_with_scope_limits",
            "article_language": (
                "Compare against cached fold-aligned PriceFM Phase-I predictions "
                "on the same selected region/fold test rows."
            ),
            "avoid_language": "Do not describe this as a full PriceFM paper-wide benchmark.",
        },
        {
            "topic": "metric",
            "status": "comparable",
            "article_language": (
                "Use original-unit AQL; negative local-minus-PriceFM AQL means "
                "the DESN/Q-DESN registry has lower average quantile loss."
            ),
            "avoid_language": "Do not mix validation AQL, median-only AQL, and paper-grid test AQL.",
        },
        {
            "topic": "quantile_grid",
            "status": "comparable",
            "article_language": (
                "The paper-grid comparison uses quantiles {}.".format(PAPER_QUANTILES)
            ),
            "avoid_language": "Do not call median-only screening a paper-grid result.",
        },
        {
            "topic": "scope",
            "status": "selected_panel",
            "article_language": (
                "Report the Stage-M panel as {} selected region/folds, spanning {} "
                "regions and {} folds.".format(n_rows, n_regions, n_folds)
            ),
            "avoid_language": "Do not imply coverage of all 38 PriceFM regions unless that table is built.",
        },
        {
            "topic": "information_set",
            "status": "mixed_information_sets",
            "article_language": (
                "Separate PriceFM graph-input rows (n={}) from target-only rows "
                "(n={}).".format(n_graph, n_target)
            ),
            "avoid_language": "Do not present graph-input wins as purely local univariate wins.",
        },
        {
            "topic": "selection_protocol",
            "status": "validation_first",
            "article_language": (
                "State that Stage-K and Stage-L test-helpful rows were not promoted "
                "when validation gates failed."
            ),
            "avoid_language": "Do not promote candidates based only on test improvements.",
        },
        {
            "topic": "paper_headline_metrics",
            "status": "context_only",
            "article_language": (
                "Use PriceFM paper headline metrics only as broad context; the "
                "article table should use the fold-aligned Phase-I rows."
            ),
            "avoid_language": "Do not compare selected-panel AQL directly to the paper-wide aggregate AQL.",
        },
    ])


def markdown_table(frame, max_rows=30):
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


def write_report(out_dir, decision, fold, method_info, alignment, split, figures, guardrails, summary):
    report = out_dir / "pricefm_stage_m_article_tables_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Stage-M Article Tables\n\n")
        f.write("These tables package the current PriceFM local DESN/Q-DESN ")
        f.write("decision surface for article drafting. They do not promote new ")
        f.write("models or alter the authoritative registry.\n\n")
        f.write("## Comparability Contract\n\n")
        f.write(
            "The comparison is fold-aligned to cached PriceFM Phase-I predictions "
            "on the same selected region/fold test rows and uses original-unit "
            "AQL on the PriceFM paper quantile grid "
            "`{}`. It is not a full paper-wide benchmark and it must be "
            "reported separately for PriceFM graph-input rows and target-only "
            "rows.\n\n".format(PAPER_QUANTILES)
        )
        f.write(markdown_table(guardrails, max_rows=20))
        f.write("\n\n")
        f.write("## Summary\n\n")
        for key in sorted(summary):
            if key.endswith("_path") or key.endswith("_dir"):
                continue
            f.write("- {}: `{}`\n".format(key, summary[key]))
        f.write("\n## Fold Summary\n\n")
        f.write(markdown_table(fold))
        f.write("\n\n## Method And Information-Set Summary\n\n")
        f.write(markdown_table(method_info))
        f.write("\n\n## Validation/Test Alignment\n\n")
        f.write(markdown_table(alignment))
        f.write("\n\n## Split Shift Diagnostics\n\n")
        f.write(markdown_table(split))
        f.write("\n\n## Largest Decision-Surface Losses\n\n")
        f.write(markdown_table(decision.sort_values("delta_abs", ascending=False).head(10)))
        f.write("\n\n## Largest Decision-Surface Wins\n\n")
        f.write(markdown_table(decision.sort_values("delta_abs").head(10)))
        if not figures.empty:
            f.write("\n\n## Figure Index\n\n")
            f.write(markdown_table(figures))
        f.write("\n")
    return report


def build(args):
    decision_dir = repo_path(args.decision_dir)
    alignment_dir = repo_path(args.alignment_dir)
    split_dir = repo_path(args.split_diagnostics_dir)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    surface = read_csv_required(decision_dir / "current_decision_surface_table.csv", "decision surface")
    by_fold = read_csv_required(decision_dir / "aggregate_by_fold.csv", "fold aggregate")
    by_method = read_csv_required(decision_dir / "aggregate_by_method_family.csv", "method aggregate")
    by_info = read_csv_required(decision_dir / "aggregate_by_information_set.csv", "information-set aggregate")
    source_summary = read_csv_required(alignment_dir / "diagnostic_source_summary.csv", "alignment source summary")
    split_contrasts = read_csv_optional(split_dir / "split_response_contrasts.csv")

    decision = compact_decision_table(surface)
    fold = fold_table(by_fold)
    method_info = method_information_table(by_method, by_info)
    alignment = alignment_table(source_summary)
    split = split_shift_table(split_contrasts)
    figures = figure_index(decision_dir, alignment_dir)

    decision.to_csv(out_dir / "article_table_region_fold_decisions.csv", index=False)
    fold.to_csv(out_dir / "article_table_fold_summary.csv", index=False)
    method_info.to_csv(out_dir / "article_table_method_information_set_summary.csv", index=False)
    alignment.to_csv(out_dir / "article_table_validation_test_alignment.csv", index=False)
    split.to_csv(out_dir / "article_table_split_shift_diagnostics.csv", index=False)
    figures.to_csv(out_dir / "article_figure_index.csv", index=False)
    guardrails = comparability_guardrails(decision)
    guardrails.to_csv(out_dir / "article_comparability_guardrails.csv", index=False)

    summary = {
        "n_region_folds": int(decision.shape[0]),
        "n_local_wins": int((numeric(decision, "delta_abs") < 0.0).sum()),
        "n_pricefm_wins": int((numeric(decision, "delta_abs") >= 0.0).sum()),
        "mean_delta_abs": float(numeric(decision, "delta_abs").mean()),
        "paper_quantiles": PAPER_QUANTILES,
        "comparison_scope": "fold_aligned_pricefm_phase1_selected_region_folds",
        "article_guardrails_path": config_path_value(out_dir / "article_comparability_guardrails.csv"),
        "decision_dir": config_path_value(decision_dir),
        "alignment_dir": config_path_value(alignment_dir),
        "split_diagnostics_dir": config_path_value(split_dir),
        "output_dir": config_path_value(out_dir),
    }
    report = write_report(out_dir, decision, fold, method_info, alignment, split, figures, guardrails, summary)
    summary["report"] = config_path_value(report)
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    print(json.dumps(build(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
