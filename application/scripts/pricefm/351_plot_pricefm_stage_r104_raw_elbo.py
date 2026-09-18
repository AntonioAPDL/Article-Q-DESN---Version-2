#!/usr/bin/env python3
"""Materialize raw-ELBO diagnostics for the frozen R104 focus atoms."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any

import numpy as np
import pandas as pd


DEFAULT_R104_ROOT = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/"
    "pricefm_stage_r104_forecast_operator_diagnosis_20260918"
)
DEFAULT_OUTPUT = DEFAULT_R104_ROOT.parent / "pricefm_stage_r104_raw_elbo_diagnostics_20260918"
FOCUS_REGIONS = ("BG", "BE")
FAMILIES = ("al", "exal")
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
COLORS = ("#2563A6", "#D97706", "#2E8B57", "#C44747", "#8561A8", "#795548", "#D65AA5")


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--r104-root", type=Path, default=DEFAULT_R104_ROOT)
    value.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    value.add_argument("--force", action="store_true")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def summarize_trace(trace: pd.DataFrame) -> dict[str, Any]:
    required = {"iter", "elbo", "delta_elbo"}
    missing = required.difference(trace.columns)
    if missing:
        raise ValueError(f"trace is missing columns: {sorted(missing)}")
    iteration = trace["iter"].to_numpy(dtype=int)
    elbo = trace["elbo"].to_numpy(dtype=float)
    if len(elbo) < 2 or not np.isfinite(elbo).all():
        raise ValueError("raw ELBO trace is incomplete or non-finite")

    def tail_change(window: int) -> float:
        start = max(0, len(elbo) - window - 1)
        return float(elbo[-1] - elbo[start])

    def tail_slope(window: int) -> float:
        start = max(0, len(elbo) - window)
        x = iteration[start:].astype(float)
        y = elbo[start:]
        return float(np.polyfit(x, y, 1)[0]) if len(y) >= 2 else np.nan

    differences = np.diff(elbo)
    return {
        "iterations": int(len(elbo)),
        "initial_elbo": float(elbo[0]),
        "final_elbo": float(elbo[-1]),
        "total_change": float(elbo[-1] - elbo[0]),
        "last_10_change": tail_change(10),
        "last_25_change": tail_change(25),
        "last_50_change": tail_change(50),
        "last_10_slope": tail_slope(10),
        "last_25_slope": tail_slope(25),
        "final_delta_elbo": float(trace["delta_elbo"].iloc[-1]),
        "maximum_elbo": float(np.max(elbo)),
        "final_minus_maximum": float(elbo[-1] - np.max(elbo)),
        "decrease_count": int(np.sum(differences < -1e-10)),
        "largest_decrease": float(np.min(differences)) if len(differences) else np.nan,
    }


def load_focus_traces(r104_root: Path) -> tuple[pd.DataFrame, dict[tuple[str, int, str, float], pd.DataFrame]]:
    ledger_path = r104_root / "pricefm_stage_r104_partial_atom_ledger.csv"
    ledger = pd.read_csv(ledger_path)
    focus = ledger[ledger.region.isin(FOCUS_REGIONS)].copy()
    expected = len(FOCUS_REGIONS) * 3 * len(FAMILIES) * len(QUANTILES)
    if len(focus) != expected:
        raise RuntimeError(f"expected {expected} focus atoms, found {len(focus)}")
    rows = []
    traces = {}
    for row in focus.itertuples(index=False):
        trace_path = Path(row.trace_path)
        if sha256_file(trace_path) != row.trace_sha256:
            raise RuntimeError(f"changed trace artifact: {trace_path}")
        trace = pd.read_csv(trace_path)
        key = (str(row.region), int(row.fold), str(row.family), float(row.tau))
        traces[key] = trace
        rows.append({
            "region": key[0],
            "fold": key[1],
            "family": key[2],
            "tau": key[3],
            "formal_converged": bool(row.formal_converged),
            "numerical_gate_passed": bool(row.numerical_gate_passed),
            "trace_path": str(trace_path.resolve()),
            "trace_sha256": str(row.trace_sha256),
            **summarize_trace(trace),
        })
    return pd.DataFrame(rows).sort_values(["region", "fold", "family", "tau"]), traces


def plain_y_axis(axis: Any) -> None:
    axis.ticklabel_format(axis="y", style="plain", useOffset=False)
    axis.grid(alpha=0.22)


def write_raw_elbo_book(
    path: Path,
    summary: pd.DataFrame,
    traces: dict[tuple[str, int, str, float], pd.DataFrame],
) -> None:
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    with PdfPages(path) as pdf:
        for region in FOCUS_REGIONS:
            for fold in (1, 2, 3):
                for family in FAMILIES:
                    fig, axes = plt.subplots(len(QUANTILES), 2, figsize=(13, 18), squeeze=False)
                    for index, (tau, color) in enumerate(zip(QUANTILES, COLORS)):
                        trace = traces[(region, fold, family, tau)]
                        row = summary[
                            summary.region.eq(region)
                            & summary.fold.eq(fold)
                            & summary.family.eq(family)
                            & summary.tau.eq(tau)
                        ].iloc[0]
                        iteration = trace["iter"].to_numpy(dtype=int)
                        elbo = trace["elbo"].to_numpy(dtype=float)
                        axes[index, 0].plot(iteration, elbo, color=color, linewidth=1.5)
                        axes[index, 0].set_ylabel(f"q={tau:g}")
                        plain_y_axis(axes[index, 0])
                        start = max(0, len(trace) - 30)
                        axes[index, 1].plot(iteration[start:], elbo[start:], color=color, linewidth=1.7)
                        plain_y_axis(axes[index, 1])
                        axes[index, 1].text(
                            0.02,
                            0.96,
                            (
                                f"final={row.final_elbo:.8g}\n"
                                f"last 10={row.last_10_change:.3g}; last 25={row.last_25_change:.3g}\n"
                                f"final delta={row.final_delta_elbo:.3g}; decreases={int(row.decrease_count)}"
                            ),
                            transform=axes[index, 1].transAxes,
                            va="top",
                            fontsize=8,
                        )
                    axes[0, 0].set_title("Raw total ELBO: complete trace")
                    axes[0, 1].set_title("Raw total ELBO: final 30 iterations")
                    axes[-1, 0].set_xlabel("Iteration")
                    axes[-1, 1].set_xlabel("Iteration")
                    fig.suptitle(f"{region}, Fold {fold}, {family.upper()}: raw total ELBO", fontsize=15)
                    fig.tight_layout(rect=(0, 0, 1, 0.975))
                    pdf.savefig(fig)
                    plt.close(fig)


def write_worst_tail_png(
    path: Path,
    summary: pd.DataFrame,
    traces: dict[tuple[str, int, str, float], pd.DataFrame],
) -> None:
    import matplotlib.pyplot as plt

    worst = summary.assign(abs_last_25=summary.last_25_change.abs()).nlargest(8, "abs_last_25")
    fig, axes = plt.subplots(4, 2, figsize=(14, 13), squeeze=False)
    for axis, row in zip(axes.ravel(), worst.itertuples(index=False)):
        trace = traces[(row.region, int(row.fold), row.family, float(row.tau))]
        tail = trace.tail(30)
        axis.plot(tail["iter"], tail["elbo"], color="#2563A6", linewidth=1.8)
        plain_y_axis(axis)
        axis.set_title(
            f"{row.region} F{row.fold} {row.family.upper()} q={row.tau:g} | last 25={row.last_25_change:.4g}",
            fontsize=10,
        )
        axis.set_xlabel("Iteration")
        axis.set_ylabel("Raw total ELBO")
    fig.suptitle("Largest final-window raw ELBO changes among BG/BE atoms", fontsize=15)
    fig.tight_layout(rect=(0, 0, 1, 0.97))
    fig.savefig(path, dpi=180, bbox_inches="tight")
    plt.close(fig)


def write_report(path: Path, summary: pd.DataFrame) -> None:
    worst = summary.assign(abs_last_25=summary.last_25_change.abs()).nlargest(20, "abs_last_25")
    lines = [
        "# PriceFM Stage-R104 raw total ELBO diagnostics",
        "",
        "This is a read-only visualization of the 84 frozen BG/BE AL/exAL atoms. "
        "It does not refit a model or infer convergence from a terminal-distance transformation.",
        "",
        "## Mechanical checks",
        "",
        f"- finite traces: {int(np.isfinite(summary.final_elbo).sum())}/{len(summary)}",
        f"- formal convergence flags: {int(summary.formal_converged.sum())}/{len(summary)}",
        f"- numerical gates: {int(summary.numerical_gate_passed.sum())}/{len(summary)}",
        f"- traces with a raw ELBO decrease larger than 1e-10: {int((summary.decrease_count > 0).sum())}",
        f"- traces ending below their earlier maximum: {int((summary.final_minus_maximum < -1e-10).sum())}",
        "",
        "## Largest final-window changes",
        "",
        worst[[
            "region", "fold", "family", "tau", "iterations", "initial_elbo", "final_elbo",
            "last_10_change", "last_25_change", "last_25_slope", "final_delta_elbo",
            "decrease_count",
        ]].to_markdown(index=False, floatfmt=".8g"),
        "",
        "## Decision boundary",
        "",
        "The full raw traces and final-window zooms require visual review. Formal flags and small "
        "terminal deltas are supporting evidence, not substitutes for that review. No broad "
        "campaign is authorized by this packet.",
        "",
    ]
    path.write_text("\n".join(lines))


def run(args: argparse.Namespace) -> dict[str, Any]:
    r104_root = args.r104_root.resolve()
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    summary, traces = load_focus_traces(r104_root)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        summary.to_csv(temporary / "pricefm_stage_r104_raw_elbo_summary.csv", index=False)
        write_raw_elbo_book(temporary / "pricefm_stage_r104_raw_total_elbo_book.pdf", summary, traces)
        write_worst_tail_png(temporary / "pricefm_stage_r104_raw_elbo_worst_tail.png", summary, traces)
        write_report(temporary / "pricefm_stage_r104_raw_elbo_report.md", summary)
        artifacts = []
        for artifact in sorted(temporary.iterdir()):
            if artifact.is_file() and artifact.name != "summary.json":
                artifacts.append({
                    "path": str((output / artifact.name).resolve()),
                    "bytes": artifact.stat().st_size,
                    "sha256": sha256_file(artifact),
                })
        result = {
            "status": "completed_raw_total_elbo_diagnostics",
            "source_stage": "R104",
            "focus_atoms": int(len(summary)),
            "raw_elbo_decrease_atoms": int((summary.decrease_count > 0).sum()),
            "atoms_ending_below_prior_maximum": int((summary.final_minus_maximum < -1e-10).sum()),
            "maximum_absolute_last_10_change": float(summary.last_10_change.abs().max()),
            "maximum_absolute_last_25_change": float(summary.last_25_change.abs().max()),
            "elbo_convergence_conclusion": "pending_user_visual_review",
            "broad_relaunch_authorized": False,
            "models_refitted": False,
            "test_opened": False,
            "artifacts": artifacts,
        }
        (temporary / "summary.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        print(json.dumps(result, indent=2, sort_keys=True))
        return result
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
