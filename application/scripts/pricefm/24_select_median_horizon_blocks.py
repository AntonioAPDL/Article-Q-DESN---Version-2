#!/usr/bin/env python3
"""Select PriceFM median candidates by validation horizon blocks."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_CANDIDATE_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_median_de_lu_folds23_p2_registry_20260603"
)
DEFAULT_BASELINE_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_median_de_lu_folds23_selection_registry_20260602"
)
DEFAULT_OUTPUT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_de_lu_folds23_horizon_block_selection_20260604"
)
DEFAULT_METHODS = (
    "qdesn_exal_rhs_ns_exact_chunked,"
    "qdesn_al_rhs_ns_exact_chunked"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--candidate-registry-dir", default=DEFAULT_CANDIDATE_REGISTRY)
    p.add_argument("--baseline-registry-dir", default=DEFAULT_BASELINE_REGISTRY)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    p.add_argument("--region", default="DE_LU")
    p.add_argument("--folds", default="2,3")
    p.add_argument("--selection-split", default="val")
    p.add_argument("--audit-split", default="test")
    p.add_argument("--unit", default="original")
    p.add_argument("--metric", default="AQL")
    p.add_argument("--selection-methods", default=DEFAULT_METHODS)
    p.add_argument("--horizon-blocks", default="1-24,25-48,49-72,73-96")
    return p


def parse_csv(value, cast=str):
    if value is None or str(value).strip() == "":
        return []
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def rel_path(path):
    path = repo_path(path)
    try:
        return str(path.relative_to(repo_path(".")))
    except ValueError:
        return str(path)


def read_csv_required(path, context):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(context, path))
    return pd.read_csv(path)


def registry_path(root, name):
    return repo_path(root) / name


def validate_blocks(blocks):
    out = []
    seen = set()
    for block in blocks:
        if "-" not in block:
            raise ValueError("horizon block must be start-end: {}".format(block))
        start, end = [int(x) for x in block.split("-", 1)]
        if start < 1 or end < start:
            raise ValueError("invalid horizon block: {}".format(block))
        label = "{}-{}".format(start, end)
        if label in seen:
            raise ValueError("duplicate horizon block: {}".format(label))
        seen.add(label)
        out.append(label)
    return out


def selected_baseline_rows(registry_dir, region, folds):
    reg = read_csv_required(registry_path(registry_dir, "median_selection_registry.csv"), "baseline registry")
    reg = reg[
        reg["region"].astype(str).eq(str(region))
        & reg["fold"].astype(int).isin(set(folds))
    ].copy()
    if reg.empty:
        raise ValueError("baseline registry has no requested region/fold rows")
    return reg.sort_values(["region", "fold"]).reset_index(drop=True)


def candidate_metric_rows(registry_dir, region, folds, methods):
    metrics = read_csv_required(registry_path(registry_dir, "median_candidate_metrics.csv"), "candidate metrics")
    metrics = metrics[
        metrics["region"].astype(str).eq(str(region))
        & metrics["fold"].astype(int).isin(set(folds))
    ].copy()
    if methods:
        metrics = metrics[metrics["method_id"].astype(str).isin(set(methods))].copy()
    if metrics.empty:
        raise ValueError("candidate registry has no requested metric rows")
    return metrics


def load_metric_by_horizon_group(model_dir, method_id, split, unit, blocks):
    path = repo_path(model_dir) / "metric_by_horizon_group.csv"
    frame = read_csv_required(path, "metric_by_horizon_group")
    frame = frame[
        frame["method_id"].astype(str).eq(str(method_id))
        & frame["split"].astype(str).eq(str(split))
        & frame["unit"].astype(str).eq(str(unit))
        & frame["horizon_group"].astype(str).isin(set(blocks))
    ].copy()
    frame.insert(0, "metric_path", rel_path(path))
    return frame


def collect_candidate_horizon_rows(metrics, selection_split, audit_split, unit, blocks):
    key_cols = [
        "region", "fold", "experiment_id", "method_id", "model_dir",
        "stage", "priority", "lag_window", "feature_map", "feature_dim",
        "depth", "units", "alpha", "rho", "input_scale", "tau0", "seed",
    ]
    rows = []
    unique = metrics.loc[:, [c for c in key_cols if c in metrics.columns]].drop_duplicates()
    for _, row in unique.iterrows():
        for split, role in [(selection_split, "selection"), (audit_split, "audit")]:
            hg = load_metric_by_horizon_group(
                row["model_dir"], row["method_id"], split, unit, blocks
            )
            for key in key_cols:
                if key in row:
                    if key in hg.columns:
                        hg[key] = row[key]
                    else:
                        hg.insert(0, key, row[key])
            hg.insert(0, "metric_role", role)
            rows.append(hg)
    return pd.concat(rows, ignore_index=True) if rows else pd.DataFrame()


def select_horizon_blocks(horizon_rows, metric, blocks):
    select = horizon_rows[horizon_rows["metric_role"].astype(str).eq("selection")].copy()
    if select.empty:
        raise ValueError("no selection horizon rows")
    if metric not in select.columns:
        raise ValueError("metric '{}' absent from horizon rows".format(metric))
    select[metric] = pd.to_numeric(select[metric], errors="coerce")
    select = select[select[metric].notna()].copy()
    winners = []
    for (region, fold, block), sub in select.groupby(["region", "fold", "horizon_group"]):
        if str(block) not in set(blocks):
            continue
        best = sub.sort_values([metric, "method_id", "experiment_id"]).iloc[0].to_dict()
        winners.append(best)
    out = pd.DataFrame(winners)
    if out.empty:
        raise ValueError("no horizon block winners selected")
    return out.sort_values(["region", "fold", "horizon_group"]).reset_index(drop=True)


def audit_selected_blocks(horizon_rows, selection):
    keys = ["region", "fold", "horizon_group", "experiment_id", "method_id"]
    audit = horizon_rows[horizon_rows["metric_role"].astype(str).eq("audit")].copy()
    out = selection.loc[:, keys].merge(audit, on=keys, how="left", suffixes=("_selection", ""))
    return out.sort_values(["region", "fold", "horizon_group"]).reset_index(drop=True)


def baseline_horizon_rows(baseline_registry, selection_split, audit_split, unit, blocks):
    rows = []
    for _, row in baseline_registry.iterrows():
        method = row["selected_method_id"]
        model_dir = row["model_dir"]
        for split, role in [(selection_split, "selection"), (audit_split, "audit")]:
            hg = load_metric_by_horizon_group(model_dir, method, split, unit, blocks)
            for key in [
                "region", "fold", "experiment_id", "selected_method_id",
                "stage", "priority", "lag_window", "feature_map",
                "feature_dim", "depth", "units", "alpha", "rho",
                "input_scale", "tau0", "seed",
            ]:
                if key in row:
                    col = key if key != "selected_method_id" else "method_id"
                    if col in hg.columns:
                        hg[col] = row[key]
                    else:
                        hg.insert(0, col, row[key])
            hg.insert(0, "metric_role", role)
            hg.insert(0, "source", "baseline_global_median")
            rows.append(hg)
    return pd.concat(rows, ignore_index=True) if rows else pd.DataFrame()


def aggregate_composite(frame, source, metric_role):
    sub = frame[frame["metric_role"].astype(str).eq(str(metric_role))].copy()
    if sub.empty:
        return pd.DataFrame()
    rows = []
    for (region, fold), block in sub.groupby(["region", "fold"]):
        out = {
            "source": source,
            "region": region,
            "fold": int(fold),
            "metric_role": metric_role,
            "n_horizon_groups": int(block["horizon_group"].nunique()),
        }
        for metric in ["AQL", "AQCR", "MAE", "RMSE"]:
            if metric in block.columns:
                out[metric] = float(pd.to_numeric(block[metric], errors="coerce").mean())
        rows.append(out)
    return pd.DataFrame(rows)


def composite_delta(baseline_comp, selected_comp):
    base = baseline_comp.rename(columns={c: "baseline_" + c for c in ["AQL", "AQCR", "MAE", "RMSE"] if c in baseline_comp.columns})
    sel = selected_comp.rename(columns={c: "horizon_block_" + c for c in ["AQL", "AQCR", "MAE", "RMSE"] if c in selected_comp.columns})
    base = base.drop(columns=[c for c in ["source", "n_horizon_groups"] if c in base.columns])
    sel = sel.drop(columns=[c for c in ["source", "n_horizon_groups"] if c in sel.columns])
    merged = base.merge(
        sel,
        on=["region", "fold", "metric_role"],
        how="inner",
    )
    for metric in ["AQL", "MAE", "RMSE"]:
        b = "baseline_" + metric
        h = "horizon_block_" + metric
        if b in merged.columns and h in merged.columns:
            merged["delta_" + metric + "_horizon_block_minus_baseline"] = merged[h] - merged[b]
    return merged


def markdown_table(frame, columns=None, float_digits=6):
    if columns is not None:
        frame = frame.loc[:, [c for c in columns if c in frame.columns]].copy()
    if frame.empty:
        return "_No rows._"
    lines = [
        "| " + " | ".join(frame.columns) + " |",
        "| " + " | ".join(["---"] * len(frame.columns)) + " |",
    ]
    for _, row in frame.iterrows():
        vals = []
        for col in frame.columns:
            val = row[col]
            if isinstance(val, float):
                vals.append(("{:." + str(int(float_digits)) + "f}").format(val))
            else:
                vals.append(str(val).replace("\n", " ").replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines)


def make_figures(out_dir, selection, delta):
    figures = []
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:  # pragma: no cover - environment dependent
        return ["figures skipped: matplotlib unavailable ({})".format(exc)]
    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    if not selection.empty:
        fig, ax = plt.subplots(figsize=(12, 5.5))
        for fold, sub in selection.groupby("fold"):
            sub = sub.sort_values("horizon_group")
            ax.plot(
                sub["horizon_group"],
                sub["AQL"],
                marker="o",
                linewidth=1.5,
                label="fold {}".format(int(fold)),
            )
        ax.set_xlabel("Horizon block")
        ax.set_ylabel("Validation AQL")
        ax.set_title("Validation-Selected Horizon-Block AQL")
        ax.grid(alpha=0.22)
        ax.legend()
        fig.tight_layout()
        path = fig_dir / "validation_selected_horizon_block_aql.png"
        fig.savefig(path, dpi=170)
        plt.close(fig)
        figures.append(rel_path(path))
    if not delta.empty:
        fig, ax = plt.subplots(figsize=(10, 5.2))
        sub = delta[delta["metric_role"].astype(str).eq("audit")].copy()
        labels = ["fold {}".format(int(x)) for x in sub["fold"]]
        ax.bar(labels, sub["delta_AQL_horizon_block_minus_baseline"], color="#2563eb")
        ax.axhline(0.0, color="black", linewidth=1.0)
        ax.set_ylabel("Audit AQL delta, horizon-block minus retained")
        ax.set_title("Horizon-Block Composite Test Audit")
        ax.grid(axis="y", alpha=0.22)
        fig.tight_layout()
        path = fig_dir / "audit_composite_aql_delta.png"
        fig.savefig(path, dpi=170)
        plt.close(fig)
        figures.append(rel_path(path))
    return figures


def write_report(out_dir, selection, audit, delta, args, figures):
    report = out_dir / "horizon_block_selection_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Median Horizon-Block Selection\n\n")
        f.write("Region: `{}`  \n".format(args.region))
        f.write("Folds: `{}`  \n".format(args.folds))
        f.write("Selection split: `{}`  \n".format(args.selection_split))
        f.write("Audit split: `{}`  \n".format(args.audit_split))
        f.write("Metric: `{}`  \n".format(args.metric))
        f.write("Horizon blocks: `{}`\n\n".format(args.horizon_blocks))
        f.write("## Validation-Selected Horizon Blocks\n\n")
        f.write(markdown_table(
            selection,
            columns=[
                "region", "fold", "horizon_group", "experiment_id",
                "method_id", "AQL", "MAE", "RMSE", "stage", "lag_window",
                "feature_dim", "rho", "input_scale",
            ],
        ))
        f.write("\n\n## Test Audit For Selected Blocks\n\n")
        f.write(markdown_table(
            audit,
            columns=[
                "region", "fold", "horizon_group", "experiment_id",
                "method_id", "AQL", "MAE", "RMSE",
            ],
        ))
        f.write("\n\n## Composite Delta Versus Retained Global Median\n\n")
        f.write(markdown_table(
            delta,
            columns=[
                "region", "fold", "metric_role",
                "baseline_AQL", "horizon_block_AQL",
                "delta_AQL_horizon_block_minus_baseline",
                "baseline_MAE", "horizon_block_MAE",
                "delta_MAE_horizon_block_minus_baseline",
                "baseline_RMSE", "horizon_block_RMSE",
                "delta_RMSE_horizon_block_minus_baseline",
            ],
        ))
        f.write("\n\n## Interpretation Rules\n\n")
        f.write("- Horizon-block selection uses validation metrics only.\n")
        f.write("- Test rows are audit-only and must not select block winners.\n")
        f.write("- Composite metrics are unweighted horizon-group means; the four default blocks have equal horizon counts.\n")
        f.write("- A horizon-block composite is a workflow selection rule, not a new inference model.\n")
        f.write("\n\n## Figures\n\n")
        for fig in figures:
            f.write("- `{}`\n".format(fig))
    return report


def main():
    args = parser().parse_args()
    folds = parse_csv(args.folds, int)
    blocks = validate_blocks(parse_csv(args.horizon_blocks, str))
    methods = parse_csv(args.selection_methods, str)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    baseline = selected_baseline_rows(args.baseline_registry_dir, args.region, folds)
    metrics = candidate_metric_rows(args.candidate_registry_dir, args.region, folds, methods)
    horizon_rows = collect_candidate_horizon_rows(
        metrics, args.selection_split, args.audit_split, args.unit, blocks
    )
    selection = select_horizon_blocks(horizon_rows, args.metric, blocks)
    audit = audit_selected_blocks(horizon_rows, selection)
    baseline_horizon = baseline_horizon_rows(
        baseline, args.selection_split, args.audit_split, args.unit, blocks
    )
    selected_for_comp = pd.concat([
        selection.assign(metric_role="selection"),
        audit.assign(metric_role="audit"),
    ], ignore_index=True)
    baseline_comp = pd.concat([
        aggregate_composite(baseline_horizon, "baseline_global_median", "selection"),
        aggregate_composite(baseline_horizon, "baseline_global_median", "audit"),
    ], ignore_index=True)
    selected_comp = pd.concat([
        aggregate_composite(selected_for_comp, "horizon_block_selection", "selection"),
        aggregate_composite(selected_for_comp, "horizon_block_selection", "audit"),
    ], ignore_index=True)
    delta = composite_delta(baseline_comp, selected_comp)

    horizon_rows.to_csv(out_dir / "horizon_block_candidate_metrics.csv", index=False)
    baseline_horizon.to_csv(out_dir / "horizon_block_baseline_metrics.csv", index=False)
    selection.to_csv(out_dir / "horizon_block_selection.csv", index=False)
    audit.to_csv(out_dir / "horizon_block_test_audit.csv", index=False)
    selected_comp.to_csv(out_dir / "horizon_block_composite_metrics.csv", index=False)
    delta.to_csv(out_dir / "horizon_block_composite_delta.csv", index=False)
    figures = make_figures(out_dir, selection, delta)
    report = write_report(out_dir, selection, audit, delta, args, figures)
    write_json(out_dir / "summary.json", {
        "candidate_registry_dir": rel_path(args.candidate_registry_dir),
        "baseline_registry_dir": rel_path(args.baseline_registry_dir),
        "region": args.region,
        "folds": folds,
        "horizon_blocks": blocks,
        "selection_split": args.selection_split,
        "audit_split": args.audit_split,
        "unit": args.unit,
        "metric": args.metric,
        "outputs": {
            "horizon_block_candidate_metrics": rel_path(out_dir / "horizon_block_candidate_metrics.csv"),
            "horizon_block_baseline_metrics": rel_path(out_dir / "horizon_block_baseline_metrics.csv"),
            "horizon_block_selection": rel_path(out_dir / "horizon_block_selection.csv"),
            "horizon_block_test_audit": rel_path(out_dir / "horizon_block_test_audit.csv"),
            "horizon_block_composite_metrics": rel_path(out_dir / "horizon_block_composite_metrics.csv"),
            "horizon_block_composite_delta": rel_path(out_dir / "horizon_block_composite_delta.csv"),
            "report": rel_path(report),
            "figures": figures,
        },
    })
    print(json.dumps({"output_dir": rel_path(out_dir), "report": rel_path(report)}, indent=2))


if __name__ == "__main__":
    main()
