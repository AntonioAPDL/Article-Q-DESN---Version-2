#!/usr/bin/env python3
"""Build the validation-only BG recursive-versus-authority comparison book."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any, Iterable

import joblib
import numpy as np
import pandas as pd


STAGE = "R111D"
TAG = "pricefm_stage_r111d_bg_recursive_authority_comparison_20260923"
DEFAULT_DATA_ROOT = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm"
)
DEFAULT_OUTPUT = DEFAULT_DATA_ROOT / "figures" / TAG
R108_RELATIVE = Path(
    "authoritative/pricefm_stage_r108_recursive_driver_decomposition_20260920"
)
R111B_RELATIVE = Path(
    "campaigns/pricefm_stage_r111b_bg_exposure_readout_20260922"
)
R111C_RELATIVE = Path(
    "authoritative/pricefm_stage_r111c_bg_residual_decomposition_20260922"
)
FOLDS = (1, 2, 3)
QUANTILES = np.asarray((0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90))
METHODS = ("r111b", "r97", "pricefm")
METHOD_LABELS = {
    "r111b": "R111B recursive Q-DESN",
    "r97": "R97 direct Q-DESN authority",
    "pricefm": "Cached PriceFM",
}
METHOD_SHORT = {
    "r111b": "R111B recursive",
    "r97": "R97 authority",
    "pricefm": "PriceFM",
}
COLORS = {
    "r111b": "#007C78",
    "r97": "#C63C4E",
    "pricefm": "#C58A00",
}
TRUTH_COLOR = "#202428"
GRID_COLOR = "#D8DDDF"
BACKGROUND = "#FBFBF9"
BLOCKS = (
    (1, 24, "0-6 h"),
    (25, 48, "6-12 h"),
    (49, 72, "12-18 h"),
    (73, 96, "18-24 h"),
)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    result.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    result.add_argument("--force", action="store_true")
    return result


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True, default=str) + "\n")


def source_record(role: str, path: Path, **extra: Any) -> dict[str, Any]:
    path = path.resolve()
    if not path.is_file():
        raise FileNotFoundError(path)
    return {
        "role": role,
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        **extra,
    }


def verify_frozen_summary(path: Path, stage: str, status: str) -> dict[str, Any]:
    value = json.loads(path.read_text())
    if (
        value.get("stage") != stage
        or value.get("status") != status
        or value.get("test_opened") is not False
        or value.get("registry_mutated") is not False
        or value.get("article_mutated") is not False
    ):
        raise RuntimeError(f"invalid frozen {stage} summary: {path}")
    return value


def verify_manifest_artifact(manifest: pd.DataFrame, path: Path) -> None:
    resolved = str(path.resolve())
    rows = manifest.loc[manifest.path.eq(resolved)]
    if rows.empty:
        raise RuntimeError(f"source is absent from frozen R111C manifest: {resolved}")
    digest = sha256_file(path)
    if digest not in set(rows.sha256.astype(str)):
        raise RuntimeError(f"source hash changed since R111C closeout: {resolved}")


def validate_surface(truth: np.ndarray, prediction: np.ndarray, anchors: np.ndarray) -> None:
    expected = (len(QUANTILES), truth.shape[0], 96)
    if truth.ndim != 2 or truth.shape[1] != 96:
        raise RuntimeError("truth must be an origin-by-96 surface")
    if prediction.shape != expected:
        raise RuntimeError(f"prediction geometry {prediction.shape} != {expected}")
    if len(anchors) != truth.shape[0]:
        raise RuntimeError("anchor count does not match origins")
    if not np.isfinite(truth).all() or not np.isfinite(prediction).all():
        raise RuntimeError("nonfinite forecast evidence")


def pinball_loss(truth: np.ndarray, prediction: np.ndarray) -> np.ndarray:
    error = truth[None, :, :] - prediction
    tau = QUANTILES[:, None, None]
    return np.maximum(tau * error, (tau - 1.0) * error)


def score_surface(truth: np.ndarray, prediction: np.ndarray) -> dict[str, float | int]:
    loss = pinball_loss(truth, prediction)
    median = prediction[3]
    return {
        "AQL": float(loss.mean()),
        "AQCR": float(np.mean(prediction[:-1] > prediction[1:])),
        "coverage_10_90": float(
            np.mean((truth >= prediction[0]) & (truth <= prediction[-1]))
        ),
        "mean_width_10_90": float(np.mean(prediction[-1] - prediction[0])),
        "mean_width_25_75": float(np.mean(prediction[5] - prediction[1])),
        "median_MAE": float(np.mean(np.abs(truth - median))),
        "median_RMSE": float(np.sqrt(np.mean((truth - median) ** 2))),
        "n_origins": int(truth.shape[0]),
        "n_loss_atoms": int(loss.size),
    }


def representative_origin(case: dict[str, Any]) -> int:
    losses = pinball_loss(case["truth"], case["predictions"]["r111b"])
    values = losses.mean(axis=(0, 2))
    return int(np.argmin(np.abs(values - np.median(values))))


def load_cases(data_root: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    r108 = data_root / R108_RELATIVE
    r111b = data_root / R111B_RELATIVE
    r111c = data_root / R111C_RELATIVE
    summary_111b = verify_frozen_summary(
        r111b / "summary.json", "R111B", "completed_bg_exposure_readout_closeout"
    )
    summary_111c = verify_frozen_summary(
        r111c / "summary.json", "R111C", "completed_bg_residual_decomposition"
    )
    if (
        summary_111b.get("selected_arm") != "mixed_equal"
        or summary_111c.get("recommended_action") != "stop_recursive_redesign_retain_R97"
        or summary_111c.get("folds_complete") != 3
    ):
        raise RuntimeError("frozen R111B/R111C decision contract changed")
    manifest_path = r111c / "source_manifest.csv"
    manifest = pd.read_csv(manifest_path)
    records = [
        source_record("r111b_summary", r111b / "summary.json"),
        source_record("r111c_summary", r111c / "summary.json"),
        source_record("r111c_source_manifest", manifest_path),
    ]
    cases: list[dict[str, Any]] = []
    for fold in FOLDS:
        r108_path = r108 / f"cases/region=BG/fold={fold}/validation_predictions.npz"
        r111b_path = r111b / f"replay/fold={fold}/validation_predictions.npz"
        r111b_manifest_path = r111b / f"replay/fold={fold}/source_manifest.csv"
        verify_manifest_artifact(manifest, r108_path)
        verify_manifest_artifact(manifest, r111b_path)
        verify_manifest_artifact(manifest, r111b_manifest_path)
        fold_manifest = pd.read_csv(r111b_manifest_path)
        scaler_rows = fold_manifest.loc[fold_manifest.role.eq("r103_bg_scaler")]
        if len(scaler_rows) != 1:
            raise RuntimeError(f"fold {fold} response scaler is ambiguous")
        scaler_path = Path(scaler_rows.iloc[0].path)
        if sha256_file(scaler_path) != str(scaler_rows.iloc[0].sha256):
            raise RuntimeError(f"fold {fold} response scaler changed")
        scaler = joblib.load(scaler_path)["BG"]["y_scaler"]
        center = float(np.asarray(scaler.center_).reshape(-1)[0])
        scale = float(np.asarray(scaler.scale_).reshape(-1)[0])
        with np.load(r108_path, allow_pickle=False) as archive:
            truth_108 = np.asarray(archive["truth_scaled"], dtype=float)
            anchors_108 = np.asarray(archive["anchors"], dtype=str)
            quantiles_108 = np.asarray(archive["quantiles"], dtype=float)
            names = [str(value) for value in archive["policies"].tolist()]
            surfaces = np.asarray(archive["predictions_scaled"], dtype=float)
            r97 = surfaces[names.index("r97_direct_reference")]
            pricefm = surfaces[names.index("pricefm_quantile_paths_all_active")]
        with np.load(r111b_path, allow_pickle=False) as archive:
            truth_111b = np.asarray(archive["truth_scaled"], dtype=float)
            anchors_111b = np.asarray(archive["anchors"], dtype=str)
            quantiles_111b = np.asarray(archive["quantiles"], dtype=float)
            candidate = np.asarray(archive["prediction_scaled"], dtype=float)
        if (
            not np.array_equal(anchors_108, anchors_111b)
            or not np.allclose(truth_108, truth_111b, rtol=0, atol=1e-6)
            or not np.allclose(quantiles_108, QUANTILES)
            or not np.allclose(quantiles_111b, QUANTILES)
        ):
            raise RuntimeError(f"fold {fold} evidence is not exactly aligned")
        truth = truth_108 * scale + center
        predictions = {
            "r111b": candidate * scale + center,
            "r97": r97 * scale + center,
            "pricefm": pricefm * scale + center,
        }
        for prediction in predictions.values():
            validate_surface(truth, prediction, anchors_108)
        cases.append({
            "fold": fold,
            "truth": truth,
            "predictions": predictions,
            "anchors": anchors_108,
        })
        records.extend([
            source_record("r108_aligned_prediction_surface", r108_path, fold=fold),
            source_record("r111b_recursive_prediction_surface", r111b_path, fold=fold),
            source_record("r111b_case_manifest", r111b_manifest_path, fold=fold),
            source_record("response_scaler", scaler_path, fold=fold),
        ])
    return cases, records


def metric_tables(cases: list[dict[str, Any]]) -> dict[str, pd.DataFrame]:
    metric_rows: list[dict[str, Any]] = []
    horizon_rows: list[dict[str, Any]] = []
    block_rows: list[dict[str, Any]] = []
    quantile_rows: list[dict[str, Any]] = []
    origin_rows: list[dict[str, Any]] = []
    for case in cases:
        fold = int(case["fold"])
        for method in METHODS:
            prediction = case["predictions"][method]
            loss = pinball_loss(case["truth"], prediction)
            metric_rows.append({"fold": fold, "method": method, **score_surface(case["truth"], prediction)})
            for horizon in range(96):
                horizon_rows.append({
                    "fold": fold,
                    "method": method,
                    "horizon": horizon + 1,
                    "hours_ahead": (horizon + 1) / 4.0,
                    "AQL": float(loss[:, :, horizon].mean()),
                    "n_loss_atoms": int(loss[:, :, horizon].size),
                })
            for start, end, label in BLOCKS:
                subset = loss[:, :, start - 1 : end]
                block_rows.append({
                    "fold": fold,
                    "method": method,
                    "horizon_block": label,
                    "AQL": float(subset.mean()),
                    "n_loss_atoms": int(subset.size),
                })
            for index, tau in enumerate(QUANTILES):
                subset = loss[index]
                quantile_rows.append({
                    "fold": fold,
                    "method": method,
                    "tau": float(tau),
                    "AQL": float(subset.mean()),
                    "n_loss_atoms": int(subset.size),
                })
            for index, anchor in enumerate(case["anchors"]):
                origin_rows.append({
                    "fold": fold,
                    "method": method,
                    "origin_index": index,
                    "anchor": str(anchor),
                    "AQL": float(loss[:, index].mean()),
                    "n_loss_atoms": int(loss[:, index].size),
                })
    metrics = pd.DataFrame(metric_rows)
    horizons = pd.DataFrame(horizon_rows)
    blocks = pd.DataFrame(block_rows)
    quantiles = pd.DataFrame(quantile_rows)
    origins = pd.DataFrame(origin_rows)
    pooled_metrics = []
    for method in METHODS:
        truth = np.concatenate([case["truth"] for case in cases], axis=0)
        prediction = np.concatenate([case["predictions"][method] for case in cases], axis=1)
        pooled_metrics.append({"fold": 0, "method": method, **score_surface(truth, prediction)})
    metrics = pd.concat([metrics, pd.DataFrame(pooled_metrics)], ignore_index=True)
    for name, frame, keys in (
        ("horizons", horizons, ["method", "horizon", "hours_ahead"]),
        ("blocks", blocks, ["method", "horizon_block"]),
        ("quantiles", quantiles, ["method", "tau"]),
    ):
        pooled = (
            frame.groupby(keys, sort=False)
            .apply(
                lambda x: pd.Series({
                    "AQL": float(np.average(x.AQL, weights=x.n_loss_atoms)),
                    "n_loss_atoms": int(x.n_loss_atoms.sum()),
                }),
                include_groups=False,
            )
            .reset_index()
        )
        pooled.insert(0, "fold", 0)
        if name == "horizons":
            horizons = pd.concat([horizons, pooled], ignore_index=True)
        elif name == "blocks":
            blocks = pd.concat([blocks, pooled], ignore_index=True)
        else:
            quantiles = pd.concat([quantiles, pooled], ignore_index=True)
    return {
        "metrics": metrics.sort_values(["fold", "method"]),
        "horizons": horizons.sort_values(["fold", "horizon", "method"]),
        "blocks": blocks.sort_values(["fold", "horizon_block", "method"]),
        "quantiles": quantiles.sort_values(["fold", "tau", "method"]),
        "origins": origins.sort_values(["fold", "origin_index", "method"]),
    }


def validate_against_closeout(data_root: Path, tables: dict[str, pd.DataFrame]) -> None:
    summary = json.loads((data_root / R111C_RELATIVE / "summary.json").read_text())
    expected = {
        "r111b": float(summary["r111b_AQL"]),
        "r97": float(summary["r97_AQL"]),
        "pricefm": float(summary["pricefm_AQL"]),
    }
    pooled = tables["metrics"].loc[tables["metrics"].fold.eq(0)].set_index("method")
    for method, value in expected.items():
        if not np.isclose(float(pooled.loc[method, "AQL"]), value, rtol=0, atol=1e-10):
            raise RuntimeError(f"{method} AQL does not reproduce frozen R111C closeout")


def configure_plotting() -> None:
    import matplotlib as mpl

    mpl.rcParams.update({
        "figure.facecolor": BACKGROUND,
        "axes.facecolor": BACKGROUND,
        "savefig.facecolor": BACKGROUND,
        "font.family": "DejaVu Sans",
        "font.size": 9.0,
        "axes.titlesize": 11.0,
        "axes.labelsize": 9.5,
        "axes.edgecolor": "#AEB5B8",
        "axes.linewidth": 0.7,
        "axes.grid": True,
        "grid.color": GRID_COLOR,
        "grid.linewidth": 0.55,
        "grid.alpha": 0.8,
        "legend.frameon": False,
        "xtick.color": "#4A5257",
        "ytick.color": "#4A5257",
        "text.color": TRUTH_COLOR,
        "axes.titlecolor": TRUTH_COLOR,
        "axes.labelcolor": TRUTH_COLOR,
        "pdf.fonttype": 42,
    })


def add_page_header(fig: Any, title: str, subtitle: str) -> None:
    fig.text(0.045, 0.955, title, fontsize=17, fontweight="bold", va="top")
    fig.text(0.045, 0.914, subtitle, fontsize=9.7, color="#556066", va="top")
    fig.add_artist(
        __import__("matplotlib").lines.Line2D(
            [0.045, 0.955], [0.892, 0.892], transform=fig.transFigure, color="#C9CED0", lw=0.8
        )
    )


def style_table(table: Any, final_row: int | None = None) -> None:
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    for (row, _column), cell in table.get_celld().items():
        cell.set_edgecolor("#D2D7D9")
        cell.set_linewidth(0.6)
        if row == 0:
            cell.set_facecolor("#E8ECEC")
            cell.set_text_props(weight="bold")
        elif final_row is not None and row == final_row:
            cell.set_facecolor("#EEF2F1")
            cell.set_text_props(weight="bold")
        else:
            cell.set_facecolor(BACKGROUND)


def cover_figure(tables: dict[str, pd.DataFrame]) -> Any:
    import matplotlib.pyplot as plt

    metrics = tables["metrics"]
    pivot = metrics.pivot(index="fold", columns="method", values="AQL").loc[[1, 2, 3, 0], list(METHODS)]
    display = pd.DataFrame({
        "Fold": ["1", "2", "3", "Pooled"],
        METHOD_SHORT["r111b"]: [f"{value:.3f}" for value in pivot.r111b],
        METHOD_SHORT["r97"]: [f"{value:.3f}" for value in pivot.r97],
        METHOD_SHORT["pricefm"]: [f"{value:.3f}" for value in pivot.pricefm],
    })
    pooled = metrics.loc[metrics.fold.eq(0)].set_index("method")
    candidate = float(pooled.loc["r111b", "AQL"])
    authority = float(pooled.loc["r97", "AQL"])
    pricefm = float(pooled.loc["pricefm", "AQL"])
    fig = plt.figure(figsize=(13.33, 7.5))
    ax = fig.add_axes([0.055, 0.08, 0.89, 0.80])
    ax.axis("off")
    add_page_header(
        fig,
        "BG forecast comparison: recursion, authority, and PriceFM",
        "Aligned outer-validation evidence | 7 quantiles | 96 quarter-hour horizons | lower AQL is better",
    )
    table = ax.table(
        cellText=display.values,
        colLabels=display.columns,
        cellLoc="center",
        colLoc="center",
        bbox=[0.0, 0.51, 1.0, 0.31],
    )
    style_table(table, final_row=len(display))
    findings = [
        (
            "Best completed recursive model",
            "R111B: Normal-RHS recursive driver + exposure-aligned AL readout (mixed_equal).",
            COLORS["r111b"],
        ),
        (
            "Pooled comparison",
            f"R111B {candidate:.3f}; R97 {authority:.3f}; PriceFM {pricefm:.3f}. "
            f"R111B is {100 * (candidate / authority - 1):.2f}% above R97 and "
            f"{100 * (1 - candidate / pricefm):.2f}% below PriceFM.",
            TRUTH_COLOR,
        ),
        (
            "Decision boundary",
            "R97 remains the valid authority. R111B is strong diagnostic evidence, not a promoted replacement.",
            COLORS["r97"],
        ),
        (
            "Evidence guard",
            "Validation only: no outer test, refit, selection, registry mutation, or article mutation occurs here.",
            "#5B6469",
        ),
    ]
    for index, (heading, body, color) in enumerate(findings):
        y = 0.42 - index * 0.102
        ax.text(0.0, y, heading, fontsize=10.4, fontweight="bold", color=color, va="top")
        ax.text(0.23, y, body, fontsize=9.8, color="#414A4F", va="top", wrap=True)
    return fig


def fold_metrics_figure(tables: dict[str, pd.DataFrame]) -> Any:
    import matplotlib.pyplot as plt

    metrics = tables["metrics"]
    fig, axes = plt.subplots(1, 3, figsize=(13.33, 7.5))
    fig.subplots_adjust(left=0.07, right=0.98, top=0.84, bottom=0.13, wspace=0.28)
    add_page_header(
        fig,
        "Fold-level accuracy and calibration",
        "Each panel uses the same aligned validation origins; pooled values weight every quantile-horizon loss atom equally.",
    )
    folds = (1, 2, 3, 0)
    labels = ("Fold 1", "Fold 2", "Fold 3", "Pooled")
    x = np.arange(len(folds))
    width = 0.24
    panels = (
        ("AQL", "Average quantile loss", None),
        ("coverage_10_90", "10-90% interval coverage", 0.80),
        ("mean_width_10_90", "10-90% interval width", None),
    )
    for ax, (column, title, reference) in zip(axes, panels):
        for offset, method in enumerate(METHODS):
            frame = metrics.loc[metrics.method.eq(method)].set_index("fold")
            values = [float(frame.loc[fold, column]) for fold in folds]
            bars = ax.bar(
                x + (offset - 1) * width,
                values,
                width,
                color=COLORS[method],
                alpha=0.90,
                label=METHOD_SHORT[method],
            )
            for bar, value in zip(bars, values):
                label = f"{value:.2f}" if column != "coverage_10_90" else f"{value:.2f}"
                ax.text(bar.get_x() + bar.get_width() / 2, value, label, ha="center", va="bottom", fontsize=7.1)
        if reference is not None:
            ax.axhline(reference, color="#6C7478", ls="--", lw=1.0, label="Nominal 0.80")
        ax.set_title(title, fontweight="bold")
        ax.set_xticks(x, labels, rotation=18, ha="right")
        ax.set_axisbelow(True)
        ax.spines[["top", "right"]].set_visible(False)
    handles, labels_legend = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels_legend, loc="lower center", bbox_to_anchor=(0.5, 0.025), ncol=3)
    return fig


def horizon_figure(tables: dict[str, pd.DataFrame]) -> Any:
    import matplotlib.pyplot as plt

    horizons = tables["horizons"]
    fig, axes = plt.subplots(2, 2, figsize=(13.33, 7.5), sharex=True, sharey=True)
    fig.subplots_adjust(left=0.07, right=0.98, top=0.84, bottom=0.10, hspace=0.30, wspace=0.18)
    add_page_header(
        fig,
        "Where forecast error accumulates across the day",
        "Lines are one-hour centered moving averages of exact quarter-hour AQL; raw metrics are preserved in the companion CSV.",
    )
    for ax, fold, title in zip(axes.flat, (1, 2, 3, 0), ("Fold 1", "Fold 2", "Fold 3", "Pooled")):
        for method in METHODS:
            frame = horizons.loc[(horizons.fold.eq(fold)) & (horizons.method.eq(method))].sort_values("horizon")
            smooth = frame.AQL.rolling(4, center=True, min_periods=1).mean()
            ax.plot(frame.hours_ahead, smooth, color=COLORS[method], lw=1.8, label=METHOD_SHORT[method])
        for hour in (6, 12, 18):
            ax.axvline(hour, color="#C7CCCE", lw=0.7, ls=":")
        ax.set_title(title, loc="left", fontweight="bold")
        ax.set_xlim(0.25, 24)
        ax.set_xticks((0.25, 6, 12, 18, 24), ("0", "6", "12", "18", "24"))
        ax.spines[["top", "right"]].set_visible(False)
    axes[1, 0].set_xlabel("Hours ahead")
    axes[1, 1].set_xlabel("Hours ahead")
    axes[0, 0].set_ylabel("AQL")
    axes[1, 0].set_ylabel("AQL")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", bbox_to_anchor=(0.5, 0.015), ncol=3)
    return fig


def block_figure(tables: dict[str, pd.DataFrame]) -> Any:
    import matplotlib.pyplot as plt

    blocks = tables["blocks"].loc[tables["blocks"].fold.eq(0)]
    pivot = blocks.pivot(index="horizon_block", columns="method", values="AQL").loc[
        [label for _, _, label in BLOCKS], list(METHODS)
    ]
    fig, axes = plt.subplots(1, 2, figsize=(13.33, 7.5))
    fig.subplots_adjust(left=0.07, right=0.98, top=0.83, bottom=0.15, wspace=0.28)
    add_page_header(
        fig,
        "Six-hour error blocks isolate the recursive pattern",
        "R111B leads early, then gives back the advantage as recursively generated endogenous inputs propagate.",
    )
    x = np.arange(len(pivot))
    width = 0.24
    for offset, method in enumerate(METHODS):
        axes[0].bar(
            x + (offset - 1) * width,
            pivot[method],
            width,
            color=COLORS[method],
            label=METHOD_SHORT[method],
        )
    axes[0].set_xticks(x, pivot.index)
    axes[0].set_ylabel("Pooled AQL")
    axes[0].set_title("AQL by forecast block", fontweight="bold")
    axes[0].spines[["top", "right"]].set_visible(False)
    gaps = pd.DataFrame({
        "vs R97 authority": pivot.r111b - pivot.r97,
        "vs PriceFM": pivot.r111b - pivot.pricefm,
    })
    colors = (COLORS["r97"], COLORS["pricefm"])
    for offset, (column, color) in enumerate(zip(gaps.columns, colors)):
        values = gaps[column]
        bars = axes[1].bar(x + (offset - 0.5) * 0.34, values, 0.34, color=color, label=column)
        for bar, value in zip(bars, values):
            axes[1].text(
                bar.get_x() + bar.get_width() / 2,
                value + (0.08 if value >= 0 else -0.08),
                f"{value:+.2f}",
                ha="center",
                va="bottom" if value >= 0 else "top",
                fontsize=8,
            )
    axes[1].axhline(0, color=TRUTH_COLOR, lw=0.9)
    axes[1].set_xticks(x, gaps.index)
    axes[1].set_ylabel("R111B AQL minus comparator")
    axes[1].set_title("Recursive-model gap", fontweight="bold")
    axes[1].text(
        0.98,
        0.035,
        "Below zero favors R111B",
        transform=axes[1].transAxes,
        ha="right",
        va="bottom",
        color="#596267",
    )
    axes[1].spines[["top", "right"]].set_visible(False)
    axes[0].legend(loc="upper left")
    axes[1].legend(loc="upper left")
    return fig


def quantile_figure(tables: dict[str, pd.DataFrame]) -> Any:
    import matplotlib.pyplot as plt

    quantiles = tables["quantiles"].loc[tables["quantiles"].fold.eq(0)]
    pivot = quantiles.pivot(index="tau", columns="method", values="AQL").loc[QUANTILES, list(METHODS)]
    metrics = tables["metrics"].loc[tables["metrics"].fold.eq(0)].set_index("method")
    fig, axes = plt.subplots(1, 2, figsize=(13.33, 7.5))
    fig.subplots_adjust(left=0.07, right=0.98, top=0.83, bottom=0.14, wspace=0.28)
    add_page_header(
        fig,
        "Quantile accuracy and interval behavior",
        "The remaining R111B-versus-R97 gap is broad across quantiles rather than confined to one tail.",
    )
    for method in METHODS:
        axes[0].plot(
            pivot.index,
            pivot[method],
            marker="o",
            markersize=4.5,
            lw=1.9,
            color=COLORS[method],
            label=METHOD_SHORT[method],
        )
    axes[0].set_xlabel("Quantile level")
    axes[0].set_ylabel("Pooled AQL")
    axes[0].set_title("Loss by quantile", fontweight="bold")
    axes[0].spines[["top", "right"]].set_visible(False)
    axes[0].legend()
    x = np.arange(len(METHODS))
    coverage = [metrics.loc[method, "coverage_10_90"] for method in METHODS]
    width = [metrics.loc[method, "mean_width_10_90"] for method in METHODS]
    bars = axes[1].bar(x - 0.18, coverage, 0.36, color=[COLORS[m] for m in METHODS], alpha=0.9)
    axes[1].axhline(0.80, color="#6C7478", ls="--", lw=1.0)
    axes[1].set_ylabel("Empirical 10-90% coverage")
    axes[1].set_ylim(0, 0.9)
    axes[1].set_xticks(x, ("R111B", "R97", "PriceFM"))
    axes[1].set_title("Coverage and interval width", fontweight="bold")
    second = axes[1].twinx()
    second.plot(x + 0.18, width, color="#263238", marker="D", lw=1.5, label="10-90% width")
    second.set_ylabel("Mean interval width (EUR/MWh)")
    second.set_ylim(50, 90)
    for bar, value in zip(bars, coverage):
        axes[1].text(bar.get_x() + bar.get_width() / 2, value + 0.015, f"{value:.2f}", ha="center", fontsize=8)
    for xx, value in zip(x + 0.18, width):
        second.text(xx, value + 1.5, f"{value:.1f}", ha="center", fontsize=8, color="#263238")
    axes[1].spines["top"].set_visible(False)
    second.spines["top"].set_visible(False)
    return fig


def draw_origin_panel(ax: Any, case: dict[str, Any], method: str, origin: int) -> None:
    prediction = case["predictions"][method][:, origin, :]
    truth = case["truth"][origin]
    x = np.arange(1, 97) / 4.0
    color = COLORS[method]
    ax.fill_between(x, prediction[0], prediction[6], color=color, alpha=0.13, linewidth=0, label="10-90%")
    ax.fill_between(x, prediction[1], prediction[5], color=color, alpha=0.24, linewidth=0, label="25-75%")
    ax.plot(x, prediction[3], color=color, lw=1.55, label="Median forecast")
    ax.plot(x, truth, color=TRUTH_COLOR, lw=1.25, label="Observed price", zorder=4)
    aql = float(pinball_loss(case["truth"][origin : origin + 1], case["predictions"][method][:, origin : origin + 1]).mean())
    ax.set_title(f"{METHOD_LABELS[method]} | origin AQL {aql:.2f}", loc="left", fontweight="bold")
    ax.set_xlim(0.25, 24)
    ax.set_xticks((0.25, 6, 12, 18, 24), ("0", "6", "12", "18", "24"))
    ax.set_ylabel("EUR/MWh")
    ax.spines[["top", "right"]].set_visible(False)


def representative_figure(case: dict[str, Any]) -> Any:
    import matplotlib.pyplot as plt

    fold = int(case["fold"])
    origin = representative_origin(case)
    anchor = pd.Timestamp(str(case["anchors"][origin])).strftime("%Y-%m-%d")
    fig, axes = plt.subplots(3, 1, figsize=(13.33, 7.5), sharex=True)
    fig.subplots_adjust(left=0.075, right=0.98, top=0.82, bottom=0.09, hspace=0.35)
    add_page_header(
        fig,
        f"Fold {fold}: representative 24-hour forecast",
        f"Origin {anchor} UTC | selected deterministically as the median-R111B-loss validation origin, not by visual appeal.",
    )
    all_values = [case["truth"][origin]]
    for method in METHODS:
        all_values.extend([
            case["predictions"][method][0, origin],
            case["predictions"][method][6, origin],
        ])
    low, high = np.nanpercentile(np.concatenate(all_values), (0.5, 99.5))
    margin = max(5.0, 0.08 * (high - low))
    for ax, method in zip(axes, METHODS):
        draw_origin_panel(ax, case, method, origin)
        ax.set_ylim(low - margin, high + margin)
    axes[-1].set_xlabel("Hours ahead")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", bbox_to_anchor=(0.5, 0.008), ncol=4)
    return fig


def origin_figure(tables: dict[str, pd.DataFrame]) -> Any:
    import matplotlib.pyplot as plt

    origins = tables["origins"].pivot(
        index=["fold", "origin_index", "anchor"], columns="method", values="AQL"
    ).reset_index()
    fig, axes = plt.subplots(1, 2, figsize=(13.33, 7.5))
    fig.subplots_adjust(left=0.07, right=0.98, top=0.83, bottom=0.14, wspace=0.28)
    add_page_header(
        fig,
        "Daily-origin behavior: gains are not uniform",
        "Each point is one complete 24-hour validation forecast; the diagonal indicates equal AQL.",
    )
    fold_colors = {1: "#3E6E9E", 2: "#7A5E9A", 3: "#567D46"}
    for fold in FOLDS:
        frame = origins.loc[origins.fold.eq(fold)]
        axes[0].scatter(frame.r97, frame.r111b, s=18, alpha=0.58, color=fold_colors[fold], label=f"Fold {fold}")
    limit = max(float(origins.r97.max()), float(origins.r111b.max()))
    axes[0].plot((0, limit), (0, limit), color="#596267", ls="--", lw=1)
    axes[0].set_xlim(left=0)
    axes[0].set_ylim(bottom=0)
    axes[0].set_xlabel("R97 authority origin AQL")
    axes[0].set_ylabel("R111B recursive origin AQL")
    axes[0].set_title("R111B versus R97", fontweight="bold")
    axes[0].legend()
    gap_data = []
    positions = []
    labels = []
    pos = 1
    for comparator, label in (("r97", "vs R97"), ("pricefm", "vs PriceFM")):
        for fold in FOLDS:
            frame = origins.loc[origins.fold.eq(fold)]
            gap_data.append((frame.r111b - frame[comparator]).to_numpy())
            positions.append(pos)
            labels.append(f"{label}\nF{fold}")
            pos += 1
        pos += 0.5
    box = axes[1].boxplot(gap_data, positions=positions, widths=0.62, patch_artist=True, showfliers=False)
    for index, patch in enumerate(box["boxes"]):
        patch.set_facecolor(COLORS["r97"] if index < 3 else COLORS["pricefm"])
        patch.set_alpha(0.70)
    axes[1].axhline(0, color=TRUTH_COLOR, lw=0.9)
    axes[1].set_xticks(positions, labels)
    axes[1].set_ylabel("R111B origin AQL minus comparator")
    axes[1].set_title("Distribution of daily-origin gaps", fontweight="bold")
    axes[1].text(0.02, 0.97, "Below zero favors R111B", transform=axes[1].transAxes, va="top", color="#596267")
    for ax in axes:
        ax.spines[["top", "right"]].set_visible(False)
    return fig


def conclusion_figure(tables: dict[str, pd.DataFrame]) -> Any:
    import matplotlib.pyplot as plt

    metrics = tables["metrics"].loc[tables["metrics"].fold.eq(0)].set_index("method")
    blocks = tables["blocks"].loc[tables["blocks"].fold.eq(0)].pivot(
        index="horizon_block", columns="method", values="AQL"
    )
    fig = plt.figure(figsize=(13.33, 7.5))
    ax = fig.add_axes([0.06, 0.08, 0.88, 0.80])
    ax.axis("off")
    add_page_header(
        fig,
        "What this comparison establishes",
        "A compact decision page for the completed BG recursive branch.",
    )
    sections = [
        (
            "1  R111B is the best completed recursive forecast",
            "Its repaired readout uses the Normal-RHS recursive price driver while exposing the AL readout to a balanced mixture of teacher-forced and recursive training states.",
            COLORS["r111b"],
        ),
        (
            "2  The repair is meaningful, but not enough to replace R97",
            f"Pooled AQL is {metrics.loc['r111b', 'AQL']:.3f} versus {metrics.loc['r97', 'AQL']:.3f}. "
            "R111B wins fold 1, then trails R97 in folds 2 and 3.",
            COLORS["r97"],
        ),
        (
            "3  R111B does beat cached PriceFM on this aligned validation surface",
            f"Pooled PriceFM AQL is {metrics.loc['pricefm', 'AQL']:.3f}; R111B is lower in all three folds. "
            "This is validation evidence, not an article-test promotion claim.",
            COLORS["pricefm"],
        ),
        (
            "4  The residual problem is late-horizon transfer",
            f"R111B improves on R97 by {blocks.loc['0-6 h', 'r97'] - blocks.loc['0-6 h', 'r111b']:.3f} AQL points over 0-6 h, "
            "but is worse in each later six-hour block. Recursive driver errors accumulate after the early horizon.",
            "#4E5960",
        ),
        (
            "5  Scientific action",
            "Retain R97 as authority. Preserve R111B as the recursive benchmark and use it to judge future driver/readout mechanisms. Do not reinterpret this book as a registry or manuscript update.",
            TRUTH_COLOR,
        ),
    ]
    for index, (heading, body, color) in enumerate(sections):
        y = 0.80 - index * 0.145
        ax.text(0.0, y, heading, fontsize=12.2, fontweight="bold", color=color, va="top")
        ax.text(0.035, y - 0.047, body, fontsize=10.2, color="#3F484D", va="top", wrap=True)
    ax.text(
        0.0,
        0.03,
        "Scope: BG outer validation only | no new fit | no test access | no authority mutation",
        fontsize=9.2,
        color="#687177",
    )
    return fig


def write_pdf(path: Path, cases: list[dict[str, Any]], tables: dict[str, pd.DataFrame]) -> int:
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    configure_plotting()
    metadata = {
        "Title": "PriceFM R111D BG recursive-authority comparison",
        "Author": "Article Q-DESN reproducibility pipeline",
        "Subject": "Validation-only BG forecast diagnostics",
        "CreationDate": None,
        "ModDate": None,
    }
    figures: list[Any] = [
        cover_figure(tables),
        fold_metrics_figure(tables),
        horizon_figure(tables),
        block_figure(tables),
        quantile_figure(tables),
    ]
    figures.extend(representative_figure(case) for case in cases)
    figures.extend((origin_figure(tables), conclusion_figure(tables)))
    with PdfPages(path, metadata=metadata) as pdf:
        for figure in figures:
            pdf.savefig(figure)
            plt.close(figure)
    return len(figures)


def report_text(tables: dict[str, pd.DataFrame], pdf_name: str) -> str:
    pooled = tables["metrics"].loc[tables["metrics"].fold.eq(0)].set_index("method")
    candidate = float(pooled.loc["r111b", "AQL"])
    authority = float(pooled.loc["r97", "AQL"])
    pricefm = float(pooled.loc["pricefm", "AQL"])
    return "\n".join([
        "# PriceFM R111D BG recursive-authority comparison",
        "",
        "This package combines the most informative elements of the R103 forecast book and",
        "the R104 forecast-operator diagnostics. It compares exactly aligned outer-validation",
        "surfaces for BG; it performs no fitting and opens no outer test data.",
        "",
        "## Models",
        "",
        "- **R111B recursive Q-DESN:** Normal-RHS recursive endogenous driver plus the",
        "  exposure-aligned `mixed_equal` AL readout. This is the best completed recursive model.",
        "- **R97 direct Q-DESN:** current valid direct-horizon authority.",
        "- **Cached PriceFM:** validation-only PriceFM quantile paths already frozen in R108.",
        "",
        "## Pooled result",
        "",
        f"- R111B: `{candidate:.6f}` AQL.",
        f"- R97: `{authority:.6f}` AQL.",
        f"- PriceFM: `{pricefm:.6f}` AQL.",
        f"- R111B is `{100 * (candidate / authority - 1):.2f}%` worse than R97 and",
        f"  `{100 * (1 - candidate / pricefm):.2f}%` better than PriceFM.",
        "",
        "R97 remains authoritative. R111B is retained as the best recursive diagnostic",
        "benchmark because its advantage is concentrated in the first six forecast hours and",
        "it trails R97 in each later six-hour block.",
        "",
        "## Output",
        "",
        f"- `{pdf_name}`",
        "- `metrics.csv`, `horizon_metrics.csv`, `horizon_block_metrics.csv`,",
        "  `quantile_metrics.csv`, and `origin_metrics.csv`",
        "- `source_manifest.csv` and `summary.json`",
        "",
        "## Guard",
        "",
        "No result in this package changes the registry, article, R97 authority, or current",
        "running campaign. All displayed comparisons are validation-only.",
        "",
    ])


def materialize(data_root: Path, output: Path, force: bool = False) -> dict[str, Any]:
    data_root = data_root.resolve()
    output = output.resolve()
    if output.exists() and any(output.iterdir()) and not force:
        raise FileExistsError(output)
    cases, sources = load_cases(data_root)
    tables = metric_tables(cases)
    validate_against_closeout(data_root, tables)
    script_path = Path(__file__).resolve()
    sources.append(source_record("executed_source", script_path))
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        table_names = {
            "metrics": "metrics.csv",
            "horizons": "horizon_metrics.csv",
            "blocks": "horizon_block_metrics.csv",
            "quantiles": "quantile_metrics.csv",
            "origins": "origin_metrics.csv",
        }
        for key, name in table_names.items():
            tables[key].to_csv(temporary / name, index=False)
        manifest = (
            pd.DataFrame(sources)
            .drop_duplicates(subset=["path", "sha256"])
            .sort_values(["role", "path"])
        )
        manifest.to_csv(temporary / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        pdf_name = "pricefm_stage_r111d_bg_recursive_authority_comparison.pdf"
        page_count = write_pdf(temporary / pdf_name, cases, tables)
        (temporary / "README.md").write_text(report_text(tables, pdf_name))
        pooled = tables["metrics"].loc[tables["metrics"].fold.eq(0)].set_index("method")
        outputs = []
        for path in sorted(temporary.iterdir()):
            if path.is_file() and path.name != "summary.json":
                record = source_record("output", path)
                record["path"] = str((output / path.name).resolve())
                outputs.append(record)
        summary = {
            "stage": STAGE,
            "tag": TAG,
            "status": "completed_validation_only_bg_recursive_authority_book",
            "region": "BG",
            "folds": list(FOLDS),
            "quantiles": QUANTILES.tolist(),
            "horizons": 96,
            "horizon_frequency": "15min",
            "page_count": page_count,
            "best_completed_recursive_model": "R111B_Normal_RHS_driver_mixed_equal_AL_readout",
            "current_authority": "R97_direct_QDESN",
            "r111b_AQL": float(pooled.loc["r111b", "AQL"]),
            "r97_AQL": float(pooled.loc["r97", "AQL"]),
            "pricefm_AQL": float(pooled.loc["pricefm", "AQL"]),
            "recommended_action": "retain_R97_preserve_R111B_as_recursive_diagnostic",
            "fit_performed": False,
            "test_opened": False,
            "registry_mutated": False,
            "article_mutated": False,
            "outputs": outputs,
        }
        write_json(temporary / "summary.json", summary)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return summary
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> int:
    args = parser().parse_args()
    summary = materialize(args.data_root, args.output_dir, args.force)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
