#!/usr/bin/env python3
"""Export tracked manuscript assets for the PriceFM Stage-M application."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path


DEFAULT_ARTICLE_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_article_tables_20260624"
)
DEFAULT_AUDIT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_comparability_audit_20260624"
)
DEFAULT_TABLE_DIR = "tables"
DEFAULT_FIGURE_DIR = "figures/pricefm_application"
PAPER_QUANTILES = "0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--article-dir", default=DEFAULT_ARTICLE_DIR)
    p.add_argument("--audit-dir", default=DEFAULT_AUDIT_DIR)
    p.add_argument("--table-dir", default=DEFAULT_TABLE_DIR)
    p.add_argument("--figure-dir", default=DEFAULT_FIGURE_DIR)
    return p


def read_csv_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(label, path))
    return pd.read_csv(path)


def read_json_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required JSON: {}".format(label, path))
    with open(path) as f:
        return json.load(f)


def repo_relative(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def latex_escape(value):
    text = "" if pd.isna(value) else str(value)
    replacements = {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
        "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    return "".join(replacements.get(ch, ch) for ch in text)


def method_label(value):
    labels = {
        "qdesn_exal": r"exQDESN",
        "qdesn_al": r"QDESN",
        "qdesn_exal_rhs_ns_exact_chunked": r"exQDESN RHS\_NS",
        "qdesn_al_rhs_ns_exact_chunked": r"QDESN RHS\_NS",
    }
    return labels.get(str(value), latex_escape(value))


def group_label(summary_type, value):
    if str(summary_type) == "method_family":
        return method_label(value)
    labels = {
        "pricefm_graph_inputs": "PriceFM graph inputs",
        "target_only": "Target-only inputs",
    }
    return labels.get(str(value), latex_escape(value))


def info_label(value):
    labels = {
        "pricefm_graph_inputs": "Graph",
        "target_only": "Target-only",
    }
    return labels.get(str(value), latex_escape(value))


def fmt_num(value, digits=3):
    if pd.isna(value):
        return "--"
    return ("{:.%df}" % digits).format(float(value))


def fmt_int(value):
    if pd.isna(value):
        return "--"
    return str(int(value))


def fmt_pct(value, digits=1):
    if pd.isna(value):
        return "--"
    return ("{:.%df}\\%%" % digits).format(100.0 * float(value))


def write_text(path, text):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


def validate_audit(audit_dir):
    audit_summary = read_json_required(audit_dir / "summary.json", "Stage-M audit summary")
    checks = read_csv_required(audit_dir / "comparability_checks.csv", "Stage-M comparability checks")
    fatal_failed = checks[(checks["severity"] == "fatal") & (checks["status"] != "pass")]
    if int(audit_summary.get("n_fatal_failures", 0)) != 0 or not fatal_failed.empty:
        raise ValueError("Stage-M comparability audit has fatal failures")
    return audit_summary, checks


def tabular(headers, rows, align):
    lines = []
    lines.append(r"\begin{tabular}{" + align + "}")
    lines.append(r"\toprule")
    lines.append(" & ".join(headers) + r" \\")
    lines.append(r"\midrule")
    for row in rows:
        lines.append(" & ".join(row) + r" \\")
    lines.append(r"\bottomrule")
    lines.append(r"\end{tabular}")
    return "\n".join(lines) + "\n"


def write_fold_table(path, fold):
    rows = []
    for _, row in fold.sort_values("fold").iterrows():
        rows.append([
            fmt_int(row["fold"]),
            fmt_int(row["n_region_folds"]),
            fmt_int(row["n_local_wins"]),
            fmt_pct(row["win_rate"]),
            fmt_num(row["mean_local_AQL"]),
            fmt_num(row["mean_pricefm_AQL"]),
            fmt_num(row["mean_delta_abs"]),
        ])
    return write_text(path, tabular(
        [
            "Fold", "Rows", "Local wins", "Win rate",
            "Local AQL", "PriceFM AQL", "$\\Delta$ AQL",
        ],
        rows,
        "rrrrrrr",
    ))


def write_info_table(path, info):
    rows = []
    for _, row in info.iterrows():
        rows.append([
            group_label(row["summary_type"], row["group"]),
            fmt_int(row["n_region_folds"]),
            fmt_int(row["n_local_wins"]),
            fmt_pct(row["win_rate"]),
            fmt_num(row["mean_delta_abs"]),
            fmt_num(row["median_delta_abs"]),
        ])
    return write_text(path, tabular(
        ["Group", "Rows", "Local wins", "Win rate", "Mean $\\Delta$", "Median $\\Delta$"],
        rows,
        "lrrrrr",
    ))


def write_top_table(path, decisions):
    wins = decisions.sort_values("delta_abs", ascending=True).head(5).copy()
    losses = decisions.sort_values("delta_abs", ascending=False).head(5).copy()
    wins.insert(0, "side", "Largest local wins")
    losses.insert(0, "side", "Largest PriceFM wins")
    show = pd.concat([wins, losses], ignore_index=True)
    rows = []
    for _, row in show.iterrows():
        rows.append([
            latex_escape(row["side"]),
            latex_escape("{} / {}".format(row["region"], int(row["fold"]))),
            info_label(row["information_set"]),
            method_label(row["best_local_method"]),
            fmt_num(row["local_AQL"]),
            fmt_num(row["pricefm_AQL"]),
            fmt_num(row["delta_abs"]),
        ])
    return write_text(path, tabular(
        ["Side", "Region/fold", "Info", "Local method", "Local AQL", "PriceFM AQL", "$\\Delta$"],
        rows,
        "llllrrr",
    ))


def write_alignment_table(path, alignment):
    rows = []
    for _, row in alignment.sort_values("source_label").iterrows():
        rows.append([
            latex_escape(row["source_label"].replace("_", " ")),
            fmt_int(row["n_rows"]),
            fmt_int(row["n_region_folds"]),
            fmt_pct(row["validation_win_rate"]),
            fmt_pct(row["test_win_rate"]),
            fmt_pct(row["disagree_rate"]),
            fmt_num(row["mean_val_delta"]),
            fmt_num(row["mean_test_delta"]),
        ])
    return write_text(path, tabular(
        [
            "Diagnostic source", "Rows", "Region/folds", "Validation wins",
            "Test wins", "Disagree", "Mean val $\\Delta$", "Mean test $\\Delta$",
        ],
        rows,
        "lrrrrrrr",
    ))


def copy_figures(figure_index, figure_dir):
    figure_dir = repo_path(figure_dir)
    figure_dir.mkdir(parents=True, exist_ok=True)
    copied = {}
    for _, row in figure_index.iterrows():
        src = repo_path(row["figure_path"])
        if not src.exists() or src.stat().st_size == 0:
            raise FileNotFoundError("missing Stage-M figure: {}".format(src))
        dst_name = "pricefm_stage_m_{}".format(src.name.replace("stage_m_", ""))
        dst = figure_dir / dst_name
        shutil.copyfile(src, dst)
        copied[src.name] = dst
    return copied


def write_current_outputs(path, macros):
    lines = [
        "% Generated by application/scripts/pricefm/72_build_pricefm_manuscript_assets.py",
        "% Stable current-output aliases for the PriceFM application section.",
    ]
    for name, value in macros.items():
        lines.append(r"\newcommand{\%s}{%s}" % (name, value))
    return write_text(path, "\n".join(lines) + "\n")


def write_manifest(path, files, summary):
    payload = {
        "summary": summary,
        "files": [
            {
                "path": repo_relative(path),
                "sha256": sha256_file(path),
                "bytes": repo_path(path).stat().st_size,
            }
            for path in files
        ],
    }
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return path


def build(args):
    article_dir = repo_path(args.article_dir)
    audit_dir = repo_path(args.audit_dir)
    table_dir = repo_path(args.table_dir)
    figure_dir = repo_path(args.figure_dir)
    table_dir.mkdir(parents=True, exist_ok=True)
    figure_dir.mkdir(parents=True, exist_ok=True)

    article_summary = read_json_required(article_dir / "summary.json", "Stage-M article summary")
    audit_summary, _ = validate_audit(audit_dir)
    decisions = read_csv_required(article_dir / "article_table_region_fold_decisions.csv", "Stage-M decisions")
    fold = read_csv_required(article_dir / "article_table_fold_summary.csv", "Stage-M fold summary")
    info = read_csv_required(
        article_dir / "article_table_method_information_set_summary.csv",
        "Stage-M method/information-set summary",
    )
    alignment = read_csv_required(
        article_dir / "article_table_validation_test_alignment.csv",
        "Stage-M validation/test alignment",
    )
    figure_index = read_csv_required(article_dir / "article_figure_index.csv", "Stage-M figure index")

    copied_figures = copy_figures(figure_index, figure_dir)
    fold_table = write_fold_table(table_dir / "pricefm_stage_m_fold_summary.tex", fold)
    info_table = write_info_table(table_dir / "pricefm_stage_m_information_set_summary.tex", info)
    top_table = write_top_table(table_dir / "pricefm_stage_m_top_wins_losses.tex", decisions)
    alignment_table = write_alignment_table(table_dir / "pricefm_stage_m_validation_alignment.tex", alignment)

    local_wins = int(article_summary["n_local_wins"])
    n_rows = int(article_summary["n_region_folds"])
    mean_local = float(pd.to_numeric(decisions["local_AQL"], errors="coerce").mean())
    mean_pricefm = float(pd.to_numeric(decisions["pricefm_AQL"], errors="coerce").mean())
    mean_delta = float(article_summary["mean_delta_abs"])
    n_regions = int(audit_summary["n_regions"])
    n_folds = int(audit_summary["n_folds"])
    n_graph = int(audit_summary["n_graph_input_rows"])
    n_target = int(audit_summary["n_target_only_rows"])
    n_pricefm = int(article_summary["n_pricefm_wins"])

    macros = {
        "PricefmStageMRegionFolds": str(n_rows),
        "PricefmStageMRegions": str(n_regions),
        "PricefmStageMFolds": str(n_folds),
        "PricefmStageMLocalWins": str(local_wins),
        "PricefmStageMPricefmWins": str(n_pricefm),
        "PricefmStageMWinRate": fmt_pct(local_wins / n_rows),
        "PricefmStageMGraphRows": str(n_graph),
        "PricefmStageMTargetOnlyRows": str(n_target),
        "PricefmStageMMeanLocalAql": fmt_num(mean_local),
        "PricefmStageMMeanPricefmAql": fmt_num(mean_pricefm),
        "PricefmStageMMeanDeltaAql": fmt_num(mean_delta),
        "PricefmStageMPaperQuantiles": PAPER_QUANTILES,
        "PricefmStageMFoldSummaryTable": repo_relative(fold_table),
        "PricefmStageMInformationSetSummaryTable": repo_relative(info_table),
        "PricefmStageMTopWinsLossesTable": repo_relative(top_table),
        "PricefmStageMValidationAlignmentTable": repo_relative(alignment_table),
        "PricefmStageMDecisionSurfaceFigure": repo_relative(copied_figures["stage_m_aql_delta_by_region_fold.png"]),
        "PricefmStageMLocalWinsFigure": repo_relative(copied_figures["stage_m_local_wins_by_fold.png"]),
        "PricefmStageMValidationTestFigure": repo_relative(copied_figures["stage_m_current_validation_vs_test.png"]),
        "PricefmStageMRescueDeltasFigure": repo_relative(copied_figures["stage_m_rescue_validation_test_deltas.png"]),
    }
    current_outputs = write_current_outputs(table_dir / "pricefm_stage_m_current_outputs.tex", macros)
    manifest = write_manifest(
        table_dir / "pricefm_stage_m_article_asset_manifest.json",
        [
            current_outputs,
            fold_table,
            info_table,
            top_table,
            alignment_table,
            *copied_figures.values(),
        ],
        {
            "article_dir": repo_relative(article_dir),
            "audit_dir": repo_relative(audit_dir),
            "comparison_scope": article_summary["comparison_scope"],
            "paper_quantiles": PAPER_QUANTILES,
            "n_region_folds": n_rows,
            "n_local_wins": local_wins,
            "n_pricefm_wins": n_pricefm,
            "mean_delta_aql": mean_delta,
        },
    )
    return {
        "current_outputs": repo_relative(current_outputs),
        "manifest": repo_relative(manifest),
        "n_region_folds": n_rows,
        "n_local_wins": local_wins,
        "mean_delta_aql": mean_delta,
        "figures": [repo_relative(path) for path in copied_figures.values()],
    }


def main():
    args = parser().parse_args()
    print(json.dumps(build(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
