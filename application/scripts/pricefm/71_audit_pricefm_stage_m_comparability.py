#!/usr/bin/env python3
"""Audit Stage-M PriceFM comparability and manuscript claim guardrails."""

from __future__ import annotations

import argparse
import json

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_DECISION_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624"
)
DEFAULT_ARTICLE_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_article_tables_20260624"
)
DEFAULT_QUANTILE_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_l_current_decision_surface_20260624/current_quantile_decision_registry.csv"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_comparability_audit_20260624"
)
PAPER_QUANTILES = "0.10,0.25,0.45,0.50,0.55,0.75,0.90"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--decision-dir", default=DEFAULT_DECISION_DIR)
    p.add_argument("--article-dir", default=DEFAULT_ARTICLE_DIR)
    p.add_argument("--quantile-registry-csv", default=DEFAULT_QUANTILE_REGISTRY)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--expected-region-folds", type=int, default=42)
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


def require_columns(frame, columns, label):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(label, sorted(missing)))


def numeric(frame, col, label):
    if col not in frame.columns:
        raise ValueError("{} missing required numeric column {}".format(label, col))
    vals = pd.to_numeric(frame[col], errors="coerce")
    return vals


def check_row(check_id, severity, passed, detail, observed=""):
    return {
        "check_id": check_id,
        "severity": severity,
        "status": "pass" if bool(passed) else "fail",
        "observed": observed,
        "detail": detail,
    }


def decision_label(delta_abs, delta_rel):
    if delta_abs < 0.0:
        return "local_beats_pricefm"
    if pd.notna(delta_rel) and delta_rel <= 0.05:
        return "local_close_to_pricefm"
    return "pricefm_better"


def claim_guardrails(surface):
    n_rows = int(surface.shape[0])
    n_regions = int(surface["region"].nunique()) if "region" in surface else 0
    n_folds = int(surface["fold"].nunique()) if "fold" in surface else 0
    n_graph = int(surface["information_set"].eq("pricefm_graph_inputs").sum())
    n_target = int(surface["information_set"].eq("target_only").sum())
    return pd.DataFrame([
        {
            "claim_type": "scope",
            "allowed_wording": (
                "Across the selected Stage-M panel of {} region/folds "
                "({} regions, {} folds), the local registry is compared with "
                "fold-aligned PriceFM Phase-I predictions.".format(n_rows, n_regions, n_folds)
            ),
            "forbidden_wording": "Q-DESN outperforms PriceFM overall.",
            "reason": "The panel is selected and does not cover every PriceFM paper region/fold.",
        },
        {
            "claim_type": "metric",
            "allowed_wording": (
                "Lower original-unit AQL is better; deltas are local AQL minus "
                "PriceFM AQL on the aligned test rows."
            ),
            "forbidden_wording": "Validation AQL and paper-grid test AQL are interchangeable.",
            "reason": "Validation is used for selection; test AQL is the comparison audit.",
        },
        {
            "claim_type": "quantiles",
            "allowed_wording": "The paper-grid comparison uses quantiles {}.".format(PAPER_QUANTILES),
            "forbidden_wording": "Median-only screening is a paper-quantile result.",
            "reason": "Median selection and seven-quantile evaluation are separate stages.",
        },
        {
            "claim_type": "information_set",
            "allowed_wording": (
                "Report graph-input rows (n={}) separately from target-only rows "
                "(n={}).".format(n_graph, n_target)
            ),
            "forbidden_wording": "All local wins are purely target-only univariate wins.",
            "reason": "Many of the strongest rows use released PriceFM graph-neighbor inputs.",
        },
        {
            "claim_type": "selection",
            "allowed_wording": (
                "Stage-K and Stage-L candidates that helped test but failed validation "
                "were not promoted."
            ),
            "forbidden_wording": "Test-only rescue improvements define the authoritative registry.",
            "reason": "The staged protocol is validation-first.",
        },
        {
            "claim_type": "paper_context",
            "allowed_wording": (
                "PriceFM paper headline metrics are background context; direct "
                "comparisons use the fold-aligned Phase-I artifacts."
            ),
            "forbidden_wording": "Selected-panel AQL is directly comparable to the paper-wide aggregate AQL.",
            "reason": "The scopes and aggregation sets differ.",
        },
    ])


def scope_table(surface):
    return pd.DataFrame([
        {
            "scope_item": "benchmark",
            "value": "cached fold-aligned PriceFM Phase-I predictions",
            "comparability_status": "direct within selected panel",
        },
        {
            "scope_item": "metric",
            "value": "original-unit average quantile loss (AQL)",
            "comparability_status": "same implementation convention as PriceFM evaluation.py",
        },
        {
            "scope_item": "quantile_grid",
            "value": PAPER_QUANTILES,
            "comparability_status": "paper-grid quantile comparison",
        },
        {
            "scope_item": "region_folds",
            "value": str(int(surface.shape[0])),
            "comparability_status": "selected Stage-M panel, not full paper scope",
        },
        {
            "scope_item": "regions",
            "value": str(int(surface["region"].nunique())),
            "comparability_status": "selected subset of PriceFM regions",
        },
        {
            "scope_item": "folds",
            "value": ",".join(str(x) for x in sorted(surface["fold"].astype(int).unique())),
            "comparability_status": "fold-aligned",
        },
    ])


def audit(args):
    decision_dir = repo_path(args.decision_dir)
    article_dir = repo_path(args.article_dir)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    surface = read_csv_required(decision_dir / "current_decision_surface_table.csv", "decision surface")
    article_decisions = read_csv_required(
        article_dir / "article_table_region_fold_decisions.csv",
        "article region/fold decisions",
    )
    guardrails = read_csv_optional(article_dir / "article_comparability_guardrails.csv")
    quantile = read_csv_required(args.quantile_registry_csv, "quantile registry")

    checks = []
    key_cols = ["region", "fold"]
    require_columns(
        surface,
        key_cols + [
            "local_AQL", "pricefm_AQL", "delta_abs", "delta_rel",
            "decision_label", "information_set", "spatial_information_set",
        ],
        "decision surface",
    )
    require_columns(article_decisions, key_cols, "article region/fold decisions")
    require_columns(quantile, key_cols, "quantile registry")
    checks.append(check_row(
        "decision_surface_row_count",
        "fatal",
        int(surface.shape[0]) == int(args.expected_region_folds),
        "Stage-M decision surface should have the expected selected-panel size.",
        str(int(surface.shape[0])),
    ))
    checks.append(check_row(
        "decision_surface_unique_keys",
        "fatal",
        not surface.duplicated(key_cols).any(),
        "Region/fold keys must be unique.",
        str(int(surface.duplicated(key_cols).sum())),
    ))
    article_keys = article_decisions[key_cols].astype(str).apply(tuple, axis=1)
    surface_keys = surface[key_cols].astype(str).apply(tuple, axis=1)
    checks.append(check_row(
        "article_table_keys_match_surface",
        "fatal",
        set(article_keys) == set(surface_keys),
        "Article-facing decision rows must match the current decision surface.",
        "article={},surface={}".format(len(article_keys), len(surface_keys)),
    ))

    local = numeric(surface, "local_AQL", "decision surface")
    pricefm = numeric(surface, "pricefm_AQL", "decision surface")
    delta = numeric(surface, "delta_abs", "decision surface")
    delta_rel = numeric(surface, "delta_rel", "decision surface")
    finite = local.notna() & pricefm.notna() & delta.notna()
    checks.append(check_row(
        "finite_aql_metrics",
        "fatal",
        bool(finite.all()),
        "Local AQL, PriceFM AQL, and delta_abs must be finite.",
        "nonfinite={}".format(int((~finite).sum())),
    ))
    identity_error = (local - pricefm - delta).abs().max()
    checks.append(check_row(
        "delta_identity",
        "fatal",
        bool(pd.notna(identity_error) and identity_error <= 1.0e-8),
        "delta_abs must equal local_AQL - pricefm_AQL.",
        "{:.6g}".format(float(identity_error)) if pd.notna(identity_error) else "nan",
    ))
    expected_labels = [
        decision_label(float(d), float(r) if pd.notna(r) else float("nan"))
        for d, r in zip(delta, delta_rel)
    ]
    checks.append(check_row(
        "decision_label_consistency",
        "fatal",
        list(surface["decision_label"].astype(str)) == expected_labels,
        "Decision labels must follow the same delta rule used by the comparison scripts.",
        "mismatches={}".format(int((surface["decision_label"].astype(str) != pd.Series(expected_labels)).sum())),
    ))
    info_sets = set(surface["information_set"].astype(str))
    checks.append(check_row(
        "information_sets_are_explicit",
        "fatal",
        info_sets.issubset({"pricefm_graph_inputs", "target_only"}) and len(info_sets) == 2,
        "Rows must be separated into graph-input and target-only information sets.",
        ",".join(sorted(info_sets)),
    ))
    graph = surface[surface["information_set"].eq("pricefm_graph_inputs")]
    target = surface[surface["information_set"].eq("target_only")]
    checks.append(check_row(
        "graph_rows_have_graph_metadata",
        "fatal",
        bool((graph["spatial_information_set"].astype(str).str.contains("graph", case=False, na=False)).all()),
        "Graph-input rows must carry graph information-set metadata.",
        "graph_rows={}".format(int(graph.shape[0])),
    ))
    checks.append(check_row(
        "target_rows_have_local_metadata",
        "fatal",
        bool((target["spatial_information_set"].astype(str).str.contains("local", case=False, na=False)).all()),
        "Target-only rows must carry local information-set metadata.",
        "target_rows={}".format(int(target.shape[0])),
    ))
    checks.append(check_row(
        "quantile_registry_matches_surface_keys",
        "fatal",
        set(quantile[key_cols].astype(str).apply(tuple, axis=1)) == set(surface_keys),
        "The current quantile decision registry must match the decision surface keys.",
        "quantile={},surface={}".format(int(quantile.shape[0]), int(surface.shape[0])),
    ))
    experiment_text = " ".join(surface.get("experiment_id", pd.Series(dtype=str)).astype(str).tolist()).lower()
    checks.append(check_row(
        "no_stage_l_test_only_promotion",
        "fatal",
        "stagel" not in experiment_text and "stage_l" not in experiment_text,
        "Stage-L SI seed expansion should remain diagnostic and not appear as promoted rows.",
        "stage_l_present={}".format("stage_l" in experiment_text or "stagel" in experiment_text),
    ))
    checks.append(check_row(
        "article_guardrails_present",
        "warning",
        not guardrails.empty,
        "The generated article table bundle should include claim guardrails.",
        "rows={}".format(int(guardrails.shape[0])),
    ))

    checks_frame = pd.DataFrame(checks)
    scope = scope_table(surface)
    claims = claim_guardrails(surface)
    checks_frame.to_csv(out_dir / "comparability_checks.csv", index=False)
    scope.to_csv(out_dir / "comparability_scope.csv", index=False)
    claims.to_csv(out_dir / "article_claim_guardrails.csv", index=False)

    fatal_failures = checks_frame[
        checks_frame["severity"].eq("fatal") & checks_frame["status"].eq("fail")
    ]
    warning_failures = checks_frame[
        checks_frame["severity"].eq("warning") & checks_frame["status"].eq("fail")
    ]
    summary = {
        "n_checks": int(checks_frame.shape[0]),
        "n_fatal_failures": int(fatal_failures.shape[0]),
        "n_warning_failures": int(warning_failures.shape[0]),
        "n_region_folds": int(surface.shape[0]),
        "n_regions": int(surface["region"].nunique()),
        "n_folds": int(surface["fold"].nunique()),
        "n_graph_input_rows": int(graph.shape[0]),
        "n_target_only_rows": int(target.shape[0]),
        "n_local_wins": int((delta < 0.0).sum()),
        "mean_delta_abs": float(delta.mean()),
        "paper_quantiles": PAPER_QUANTILES,
        "comparison_scope": "fold_aligned_pricefm_phase1_selected_region_folds",
        "decision_dir": config_path_value(decision_dir),
        "article_dir": config_path_value(article_dir),
        "output_dir": config_path_value(out_dir),
    }
    report = write_report(out_dir, checks_frame, scope, claims, summary)
    summary["report"] = config_path_value(report)
    write_json(out_dir / "summary.json", summary)
    if not fatal_failures.empty:
        raise RuntimeError("Stage-M comparability audit failed fatal checks")
    return summary


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


def write_report(out_dir, checks, scope, claims, summary):
    report = out_dir / "pricefm_stage_m_comparability_audit_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Stage-M Comparability Audit\n\n")
        f.write(
            "This audit checks whether the Stage-M article tables can be used "
            "for a scoped comparison with PriceFM. It does not launch models "
            "or change the authoritative registry.\n\n"
        )
        f.write("## Summary\n\n")
        for key in sorted(summary):
            f.write("- {}: `{}`\n".format(key, summary[key]))
        f.write("\n## Comparability Scope\n\n")
        f.write(markdown_table(scope))
        f.write("\n\n## Checks\n\n")
        f.write(markdown_table(checks))
        f.write("\n\n## Claim Guardrails\n\n")
        f.write(markdown_table(claims, max_rows=20))
        f.write("\n")
    return report


def main():
    args = parser().parse_args()
    print(json.dumps(audit(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
