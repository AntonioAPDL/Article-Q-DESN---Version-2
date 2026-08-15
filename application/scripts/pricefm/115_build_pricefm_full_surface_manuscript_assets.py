#!/usr/bin/env python3
"""Export manuscript assets from the PriceFM full-surface closeout."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[3]
PAPER_QUANTILES = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]
DEFAULT_OUTPUT_CLOSEOUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_full_surface_decision_closeout_20260704"
)


DEFAULT_TABLE_DIR = "tables"
DEFAULT_FIGURE_DIR = "figures/pricefm_application"


def repo_path(path: str | Path) -> Path:
    path = Path(path)
    return path if path.is_absolute() else REPO_ROOT / path


def repo_relative(path: str | Path) -> str:
    full = repo_path(path)
    try:
        return str(full.relative_to(REPO_ROOT))
    except ValueError:
        return str(full)


def read_csv_required(path: str | Path, label: str) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required CSV: {full}")
    return pd.read_csv(full)


def read_json_required(path: str | Path, label: str) -> dict[str, Any]:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required JSON: {full}")
    with open(full, "r") as f:
        return json.load(f)


def sha256_file_or_blank(path: str | Path) -> str:
    full = repo_path(path)
    if not full.exists() or not full.is_file():
        return ""
    h = hashlib.sha256()
    with open(full, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path: str | Path, payload: dict[str, Any]) -> Path:
    full = repo_path(path)
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return full


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--closeout-dir", default=DEFAULT_OUTPUT_CLOSEOUT_DIR)
    p.add_argument("--table-dir", default=DEFAULT_TABLE_DIR)
    p.add_argument("--figure-dir", default=DEFAULT_FIGURE_DIR)
    return p


def latex_escape(value: Any) -> str:
    text = "" if pd.isna(value) else str(value)
    repl = {
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
    return "".join(repl.get(ch, ch) for ch in text)


def method_label(value: Any) -> str:
    labels = {
        "pricefm_phase1_pretraining": "PriceFM",
        "qdesn_selected": r"Selected Q--DESN",
        "qdesn_exal_rhs_ns_exact_chunked": r"exQDESN",
        "qdesn_al_rhs_ns_exact_chunked": r"QDESN",
    }
    return labels.get(str(value), latex_escape(value))


def decision_label(value: Any) -> str:
    labels = {
        "qdesn_wins": "Q--DESN wins",
        "qdesn_close": "Q--DESN close",
        "pricefm_wins": "PriceFM wins",
    }
    return labels.get(str(value), latex_escape(value))


def feature_label(value: Any) -> str:
    labels = {
        "target_only": "Target-only",
        "graph_khop": "Graph k-hop",
        "graph_summary_mean": "Graph summary",
        "graph_neighbor_spread_summary": "Graph spread",
    }
    return labels.get(str(value), latex_escape(value))


def source_label(value: Any) -> str:
    labels = {
        "current_r3q": "Current validation-selected rows",
        "stage_m": "Earlier selected-panel rows",
        "provenance_bridge_30": "Previously audited bridge rows",
    }
    return labels.get(str(value), latex_escape(value))


def fmt_num(value: Any, digits: int = 3) -> str:
    if pd.isna(value):
        return "--"
    return f"{float(value):.{digits}f}"


def fmt_pct(value: Any, digits: int = 1) -> str:
    if pd.isna(value):
        return "--"
    return f"{100.0 * float(value):.{digits}f}\\%"


def tabular(headers: list[str], rows: list[list[str]], align: str) -> str:
    lines = [r"\begin{tabular}{" + align + "}", r"\toprule"]
    lines.append(" & ".join(headers) + r" \\")
    lines.append(r"\midrule")
    for row in rows:
        lines.append(" & ".join(row) + r" \\")
    lines.extend([r"\bottomrule", r"\end{tabular}"])
    return "\n".join(lines) + "\n"


def write_text(path: Path, text: str) -> Path:
    full = repo_path(path)
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(text)
    return full


def fold_summary(registry: pd.DataFrame) -> pd.DataFrame:
    return (
        registry.groupby("fold", as_index=False)
        .agg(
            rows=("region", "size"),
            qdesn_wins=("decision_label", lambda x: int((x == "qdesn_wins").sum())),
            qdesn_close=("decision_label", lambda x: int((x == "qdesn_close").sum())),
            pricefm_wins=("decision_label", lambda x: int((x == "pricefm_wins").sum())),
            mean_qdesn_AQL=("qdesn_AQL", "mean"),
            mean_pricefm_AQL=("pricefm_AQL", "mean"),
            mean_delta_AQL=("delta_AQL_qdesn_minus_pricefm", "mean"),
        )
        .sort_values("fold")
    )


def decision_summary(registry: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for label in ["qdesn_wins", "qdesn_close", "pricefm_wins"]:
        sub = registry[registry["decision_label"].eq(label)]
        rows.append({
            "decision": label,
            "rows": int(len(sub)),
            "mean_delta_AQL": sub["delta_AQL_qdesn_minus_pricefm"].mean(),
            "median_delta_AQL": sub["delta_AQL_qdesn_minus_pricefm"].median(),
        })
    return pd.DataFrame(rows)


def source_summary(registry: pd.DataFrame) -> pd.DataFrame:
    return (
        registry.groupby("source_class", as_index=False)
        .agg(
            rows=("region", "size"),
            qdesn_wins=("decision_label", lambda x: int((x == "qdesn_wins").sum())),
            pricefm_wins=("decision_label", lambda x: int((x == "pricefm_wins").sum())),
            mean_delta_AQL=("delta_AQL_qdesn_minus_pricefm", "mean"),
        )
        .sort_values("source_class")
    )


def feature_summary(registry: pd.DataFrame) -> pd.DataFrame:
    return (
        registry.groupby("feature_policy", as_index=False)
        .agg(
            rows=("region", "size"),
            qdesn_wins=("decision_label", lambda x: int((x == "qdesn_wins").sum())),
            qdesn_close=("decision_label", lambda x: int((x == "qdesn_close").sum())),
            pricefm_wins=("decision_label", lambda x: int((x == "pricefm_wins").sum())),
            mean_delta_AQL=("delta_AQL_qdesn_minus_pricefm", "mean"),
        )
        .sort_values("feature_policy")
    )


def benchmark_summary(registry: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []

    def summarize(scope: str, frame: pd.DataFrame) -> dict[str, Any]:
        return {
            "scope": scope,
            "rows": int(frame.shape[0]),
            "qdesn_wins": int(frame["decision_label"].eq("qdesn_wins").sum()),
            "qdesn_close": int(frame["decision_label"].eq("qdesn_close").sum()),
            "pricefm_wins": int(frame["decision_label"].eq("pricefm_wins").sum()),
            "mean_qdesn_AQL": frame["qdesn_AQL"].mean(),
            "mean_pricefm_AQL": frame["pricefm_AQL"].mean(),
            "mean_delta_AQL": frame["delta_AQL_qdesn_minus_pricefm"].mean(),
            "median_delta_AQL": frame["delta_AQL_qdesn_minus_pricefm"].median(),
        }

    rows.append(summarize("Overall", registry))
    for fold, frame in registry.groupby("fold", sort=True):
        rows.append(summarize(f"Fold {int(fold)}", frame))
    return pd.DataFrame(rows)


def input_set_summary(registry: pd.DataFrame) -> pd.DataFrame:
    frame = registry.copy()
    is_graph = frame["feature_policy"].astype(str).str.contains("graph", na=False)
    frame["input_set"] = is_graph.map({True: "Graph-derived inputs", False: "Target-only inputs"})
    return (
        frame.groupby("input_set", as_index=False)
        .agg(
            rows=("region", "size"),
            qdesn_wins=("decision_label", lambda x: int((x == "qdesn_wins").sum())),
            qdesn_close=("decision_label", lambda x: int((x == "qdesn_close").sum())),
            pricefm_wins=("decision_label", lambda x: int((x == "pricefm_wins").sum())),
            mean_delta_AQL=("delta_AQL_qdesn_minus_pricefm", "mean"),
            median_delta_AQL=("delta_AQL_qdesn_minus_pricefm", "median"),
        )
        .sort_values("input_set")
    )


def write_benchmark_table(path: Path, frame: pd.DataFrame) -> Path:
    rows = [[
        latex_escape(r["scope"]),
        str(int(r["rows"])),
        str(int(r["qdesn_wins"])),
        str(int(r["qdesn_close"])),
        str(int(r["pricefm_wins"])),
        fmt_num(r["mean_qdesn_AQL"]),
        fmt_num(r["mean_pricefm_AQL"]),
        fmt_num(r["mean_delta_AQL"]),
        fmt_num(r["median_delta_AQL"]),
    ] for _, r in frame.iterrows()]
    return write_text(path, tabular(
        [
            "Scope", "Rows", "Q--DESN wins", "Near ties", "PriceFM wins",
            "Q--DESN AQL", "PriceFM AQL", "Mean $\\Delta$", "Median $\\Delta$",
        ],
        rows,
        "lrrrrrrrr",
    ))


def write_input_set_table(path: Path, frame: pd.DataFrame) -> Path:
    rows = [[
        latex_escape(r["input_set"]),
        str(int(r["rows"])),
        str(int(r["qdesn_wins"])),
        str(int(r["qdesn_close"])),
        str(int(r["pricefm_wins"])),
        fmt_num(r["mean_delta_AQL"]),
        fmt_num(r["median_delta_AQL"]),
    ] for _, r in frame.iterrows()]
    return write_text(path, tabular(
        [
            "Input set", "Rows", "Q--DESN wins", "Near ties",
            "PriceFM wins", "Mean $\\Delta$", "Median $\\Delta$",
        ],
        rows,
        "lrrrrrr",
    ))


def write_fold_table(path: Path, frame: pd.DataFrame) -> Path:
    rows = [[
        str(int(r["fold"])), str(int(r["rows"])), str(int(r["qdesn_wins"])),
        str(int(r["qdesn_close"])), str(int(r["pricefm_wins"])),
        fmt_num(r["mean_qdesn_AQL"]), fmt_num(r["mean_pricefm_AQL"]),
        fmt_num(r["mean_delta_AQL"]),
    ] for _, r in frame.iterrows()]
    return write_text(path, tabular(
        ["Fold", "Rows", "Q--DESN wins", "Close", "PriceFM wins", "Q--DESN AQL", "PriceFM AQL", "$\\Delta$"],
        rows,
        "rrrrrrrr",
    ))


def write_method_table(path: Path, frame: pd.DataFrame) -> Path:
    rows = [[
        method_label(r["method_id"]), str(int(r["n"])), fmt_num(r["mean_AQL"]),
        fmt_num(r["median_AQL"]), fmt_num(r["min_AQL"]), fmt_num(r["max_AQL"]),
    ] for _, r in frame.sort_values("mean_AQL").iterrows()]
    return write_text(path, tabular(
        ["Method", "Rows", "Mean AQL", "Median AQL", "Min AQL", "Max AQL"],
        rows,
        "lrrrrr",
    ))


def write_decision_table(path: Path, frame: pd.DataFrame) -> Path:
    rows = [[
        decision_label(r["decision"]), str(int(r["rows"])),
        fmt_num(r["mean_delta_AQL"]), fmt_num(r["median_delta_AQL"]),
    ] for _, r in frame.iterrows()]
    return write_text(path, tabular(
        ["Decision", "Rows", "Mean $\\Delta$", "Median $\\Delta$"],
        rows,
        "lrrr",
    ))


def write_source_table(path: Path, frame: pd.DataFrame) -> Path:
    rows = [[
        source_label(r["source_class"]), str(int(r["rows"])),
        str(int(r["qdesn_wins"])), str(int(r["pricefm_wins"])),
        fmt_num(r["mean_delta_AQL"]),
    ] for _, r in frame.iterrows()]
    return write_text(path, tabular(
        ["Evidence source", "Rows", "Q--DESN wins", "PriceFM wins", "Mean $\\Delta$"],
        rows,
        "lrrrr",
    ))


def write_feature_table(path: Path, frame: pd.DataFrame) -> Path:
    rows = [[
        feature_label(r["feature_policy"]), str(int(r["rows"])),
        str(int(r["qdesn_wins"])), str(int(r["qdesn_close"])),
        str(int(r["pricefm_wins"])), fmt_num(r["mean_delta_AQL"]),
    ] for _, r in frame.iterrows()]
    return write_text(path, tabular(
        ["Feature policy", "Rows", "Q--DESN wins", "Close", "PriceFM wins", "Mean $\\Delta$"],
        rows,
        "lrrrrr",
    ))


def write_horizon_table(path: Path, frame: pd.DataFrame) -> Path:
    rows = [[
        latex_escape(r["horizon_group"]), str(int(r["n"])), str(int(r["qdesn_wins"])),
        fmt_num(r["mean_delta_AQL"]), fmt_num(r["median_delta_AQL"]),
    ] for _, r in frame.iterrows()]
    return write_text(path, tabular(
        ["Horizon block", "Rows", "Q--DESN wins", "Mean $\\Delta$", "Median $\\Delta$"],
        rows,
        "lrrrr",
    ))


def write_top_table(path: Path, registry: pd.DataFrame) -> Path:
    wins = registry.sort_values("delta_AQL_qdesn_minus_pricefm").head(6).copy()
    losses = registry.sort_values("delta_AQL_qdesn_minus_pricefm", ascending=False).head(6).copy()
    wins.insert(0, "side", "Largest Q--DESN gains")
    losses.insert(0, "side", "Largest PriceFM gains")
    show = pd.concat([wins, losses], ignore_index=True)
    rows = [[
        latex_escape(r["side"]),
        latex_escape(f"{r['region']}/{int(r['fold'])}"),
        method_label(r["qdesn_method_id"]),
        feature_label(r["feature_policy"]),
        fmt_num(r["qdesn_AQL"]),
        fmt_num(r["pricefm_AQL"]),
        fmt_num(r["delta_AQL_qdesn_minus_pricefm"]),
    ] for _, r in show.iterrows()]
    return write_text(path, tabular(
        ["Side", "Region/fold", "Q--DESN", "Features", "Q--DESN AQL", "PriceFM AQL", "$\\Delta$"],
        rows,
        "llllrrr",
    ))


def write_priority_table(path: Path, registry: pd.DataFrame) -> Path:
    priority = registry[registry["rescue_tier"].eq("priority0")].sort_values(
        "delta_AQL_qdesn_minus_pricefm", ascending=False,
    ).head(12)
    rows = [[
        latex_escape(f"{r['region']}/{int(r['fold'])}"),
        method_label(r["qdesn_method_id"]),
        feature_label(r["feature_policy"]),
        fmt_num(r["qdesn_AQL"]),
        fmt_num(r["pricefm_AQL"]),
        fmt_num(r["delta_AQL_qdesn_minus_pricefm"]),
        source_label(r["source_class"]),
    ] for _, r in priority.iterrows()]
    return write_text(path, tabular(
        ["Region/fold", "Q--DESN", "Features", "Q--DESN AQL", "PriceFM AQL", "$\\Delta$", "Source"],
        rows,
        "lllrrrl",
    ))


def plot_assets(figure_dir: Path, registry: pd.DataFrame, horizons: pd.DataFrame) -> dict[str, Path]:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    out = repo_path(figure_dir)
    out.mkdir(parents=True, exist_ok=True)
    paths: dict[str, Path] = {}

    ordered = registry.sort_values("delta_AQL_qdesn_minus_pricefm").reset_index(drop=True).copy()
    positions = list(range(len(ordered)))
    labels = (ordered["region"] + " f" + ordered["fold"].astype(str)).tolist()
    colors = ordered["decision_label"].map({
        "qdesn_wins": "#287a45",
        "qdesn_close": "#d49423",
        "pricefm_wins": "#b44646",
    }).fillna("#666666")
    fig, ax = plt.subplots(figsize=(10.5, 7.0))
    ax.barh(positions, ordered["delta_AQL_qdesn_minus_pricefm"], color=colors, height=0.82)
    tick_count = min(14, len(ordered))
    tick_idx = sorted({
        int(round(i * (len(ordered) - 1) / max(1, tick_count - 1)))
        for i in range(tick_count)
    })
    ax.set_yticks(tick_idx)
    ax.set_yticklabels([labels[i] for i in tick_idx], fontsize=7)
    ax.axvline(0.0, color="#222222", linewidth=1)
    ax.set_xlabel("AQL difference: Q-DESN minus PriceFM")
    ax.set_ylabel("Region/fold rank by AQL difference")
    ax.set_title("Full configured PriceFM comparison")
    fig.tight_layout()
    path = out / "pricefm_full_qdesn_pricefm_delta.png"
    fig.savefig(path, dpi=180)
    plt.close(fig)
    paths["delta_figure"] = path

    if not horizons.empty:
        pivot = horizons.pivot_table(
            index=["region", "fold"],
            columns="horizon_group",
            values="horizon_delta_AQL_qdesn_minus_pricefm",
            aggfunc="first",
        )
        fig, ax = plt.subplots(figsize=(8.5, 7.0))
        im = ax.imshow(pivot.to_numpy(), aspect="auto", cmap="coolwarm", vmin=-2.0, vmax=2.0)
        ax.set_xticks(range(len(pivot.columns)))
        ax.set_xticklabels([str(x) for x in pivot.columns])
        tick_count = min(16, len(pivot.index))
        tick_idx = sorted({
            int(round(i * (len(pivot.index) - 1) / max(1, tick_count - 1)))
            for i in range(tick_count)
        })
        ax.set_yticks(tick_idx)
        ax.set_yticklabels([f"{pivot.index[i][0]} f{pivot.index[i][1]}" for i in tick_idx], fontsize=7)
        ax.set_xlabel("Forecast horizon block")
        ax.set_title("Available horizon-block diagnostics")
        cbar = fig.colorbar(im, ax=ax)
        cbar.set_label("Q-DESN minus PriceFM AQL")
        fig.tight_layout()
        path = out / "pricefm_full_horizon_delta_heatmap.png"
        fig.savefig(path, dpi=180)
        plt.close(fig)
        paths["horizon_figure"] = path
    return paths


def write_current_outputs(path: Path, macros: dict[str, str]) -> Path:
    lines = [
        "% Generated by application/scripts/pricefm/115_build_pricefm_full_surface_manuscript_assets.py",
        "% Stable current-output aliases for the full PriceFM benchmark section.",
    ]
    for key, value in macros.items():
        lines.append(r"\newcommand{\%s}{%s}" % (key, value))
    return write_text(path, "\n".join(lines) + "\n")


def validate_closeout(summary: dict[str, Any], registry: pd.DataFrame) -> None:
    if summary.get("status") != "completed":
        raise ValueError("full-surface closeout status is not completed")
    if int(summary.get("n_region_folds", -1)) != int(registry.shape[0]):
        raise ValueError("full-surface closeout row count disagrees with registry")
    if int(summary.get("n_region_folds", -1)) != 114:
        raise ValueError("full-surface closeout is not the configured 114-cell benchmark")


def build(args: argparse.Namespace) -> dict[str, Any]:
    closeout = repo_path(args.closeout_dir)
    table_dir = Path(args.table_dir)
    figure_dir = Path(args.figure_dir)
    summary = read_json_required(closeout / "summary.json", "full-surface summary")
    registry = read_csv_required(closeout / "pricefm_full_surface_decision_registry.csv", "full-surface registry")
    methods = read_csv_required(closeout / "pricefm_full_surface_method_summary.csv", "full-surface method summary")
    horizons = read_csv_required(closeout / "pricefm_full_surface_horizon_diagnostics.csv", "full-surface horizon diagnostics")
    horizon_summary = read_csv_required(closeout / "pricefm_full_surface_horizon_summary.csv", "full-surface horizon summary")
    validate_closeout(summary, registry)

    benchmark = benchmark_summary(registry)
    input_sets = input_set_summary(registry)
    folds = fold_summary(registry)
    decisions = decision_summary(registry)
    sources = source_summary(registry)
    features = feature_summary(registry)
    figures = plot_assets(figure_dir, registry, horizons)

    files = []
    benchmark_table = write_benchmark_table(table_dir / "pricefm_full_main_summary.tex", benchmark)
    input_set_table = write_input_set_table(table_dir / "pricefm_full_input_set_summary.tex", input_sets)
    horizon_table = write_horizon_table(
        table_dir / "pricefm_full_horizon_diagnostic_summary.tex",
        horizon_summary,
    )
    files.extend([benchmark_table, input_set_table, horizon_table])

    # Retain the detailed audit displays as tracked artifacts, but do not use
    # them as the default manuscript-facing display set.
    fold_table = write_fold_table(table_dir / "pricefm_full_fold_summary.tex", folds)
    method_table = write_method_table(table_dir / "pricefm_full_method_summary.tex", methods)
    decision_table = write_decision_table(table_dir / "pricefm_full_decision_summary.tex", decisions)
    source_table = write_source_table(table_dir / "pricefm_full_source_summary.tex", sources)
    feature_table = write_feature_table(table_dir / "pricefm_full_feature_summary.tex", features)
    old_horizon_table = write_horizon_table(table_dir / "pricefm_full_horizon_summary.tex", horizon_summary)
    top_table = write_top_table(table_dir / "pricefm_full_top_wins_losses.tex", registry)
    priority_table = write_priority_table(table_dir / "pricefm_full_priority_rescue.tex", registry)
    files.extend([
        fold_table, method_table, decision_table, source_table, feature_table,
        old_horizon_table, top_table, priority_table,
    ])

    n_rows = int(registry.shape[0])
    n_qwins = int(registry["decision_label"].eq("qdesn_wins").sum())
    n_close = int(registry["decision_label"].eq("qdesn_close").sum())
    n_pfwins = int(registry["decision_label"].eq("pricefm_wins").sum())
    horizon_cells = int(summary.get("n_horizon_diagnostic_region_folds", 0))
    macros = {
        "PricefmFullRegionFolds": str(n_rows),
        "PricefmFullRegions": str(int(registry["region"].nunique())),
        "PricefmFullFolds": str(int(registry["fold"].nunique())),
        "PricefmFullQdesnWins": str(n_qwins),
        "PricefmFullQdesnClose": str(n_close),
        "PricefmFullPricefmWins": str(n_pfwins),
        "PricefmFullQdesnWinRate": fmt_pct(n_qwins / n_rows),
        "PricefmFullMeanQdesnAql": fmt_num(registry["qdesn_AQL"].mean()),
        "PricefmFullMeanPricefmAql": fmt_num(registry["pricefm_AQL"].mean()),
        "PricefmFullMeanDeltaAql": fmt_num(registry["delta_AQL_qdesn_minus_pricefm"].mean()),
        "PricefmFullMedianDeltaAql": fmt_num(registry["delta_AQL_qdesn_minus_pricefm"].median()),
        "PricefmFullGraphRows": str(int(registry["feature_policy"].astype(str).str.contains("graph").sum())),
        "PricefmFullTargetOnlyRows": str(int(registry["feature_policy"].astype(str).eq("target_only").sum())),
        "PricefmFullBridgeRows": str(int(registry["source_class"].eq("provenance_bridge_30").sum())),
        "PricefmFullStageMRows": str(int(registry["source_class"].eq("stage_m").sum())),
        "PricefmFullRthreeqRows": str(int(registry["source_class"].eq("current_r3q").sum())),
        "PricefmFullHorizonRows": str(horizon_cells),
        "PricefmFullPaperQuantiles": ", ".join(f"{x:.2f}" for x in PAPER_QUANTILES),
        "PricefmFullMainSummaryTable": repo_relative(benchmark_table),
        "PricefmFullInputSetSummaryTable": repo_relative(input_set_table),
        "PricefmFullHorizonDiagnosticSummaryTable": repo_relative(horizon_table),
        "PricefmFullFoldSummaryTable": repo_relative(fold_table),
        "PricefmFullMethodSummaryTable": repo_relative(method_table),
        "PricefmFullDecisionSummaryTable": repo_relative(decision_table),
        "PricefmFullSourceSummaryTable": repo_relative(source_table),
        "PricefmFullFeatureSummaryTable": repo_relative(feature_table),
        "PricefmFullHorizonSummaryTable": repo_relative(old_horizon_table),
        "PricefmFullTopWinsLossesTable": repo_relative(top_table),
        "PricefmFullPriorityRescueTable": repo_relative(priority_table),
        "PricefmFullDeltaFigure": repo_relative(figures["delta_figure"]),
        "PricefmFullHorizonFigure": repo_relative(figures.get("horizon_figure", "")),
    }
    outputs = write_current_outputs(table_dir / "pricefm_full_current_outputs.tex", macros)
    files.append(outputs)
    files.extend(figures.values())

    manifest = {
        "summary": summary,
        "files": [
            {
                "path": repo_relative(path),
                "sha256": sha256_file_or_blank(path),
                "bytes": repo_path(path).stat().st_size,
            }
            for path in files
        ],
    }
    manifest_path = write_text(
        table_dir / "pricefm_full_article_asset_manifest.json",
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    )
    files.append(manifest_path)
    asset_summary = {
        "status": "completed",
        "n_region_folds": n_rows,
        "n_qdesn_wins": n_qwins,
        "n_qdesn_close": n_close,
        "n_pricefm_wins": n_pfwins,
        "mean_delta_AQL_qdesn_minus_pricefm": float(registry["delta_AQL_qdesn_minus_pricefm"].mean()),
        "current_outputs": repo_relative(outputs),
        "manifest": repo_relative(manifest_path),
    }
    write_json(table_dir / "pricefm_full_article_asset_summary.json", asset_summary)
    print(json.dumps(asset_summary, indent=2, sort_keys=True))
    return asset_summary


def main() -> None:
    build(parser().parse_args())


if __name__ == "__main__":
    main()
