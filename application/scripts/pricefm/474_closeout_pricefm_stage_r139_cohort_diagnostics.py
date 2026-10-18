#!/usr/bin/env python3
"""Build the frozen R139 PriceFM cohort diagnosis from sealed R137/R138 output."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import subprocess
from typing import Any, Mapping, Sequence

import numpy as np


NS_PER_HOUR = 3_600_000_000_000
EPS = 1e-12


class EvidenceError(RuntimeError):
    """Raised when frozen evidence fails its reproducibility contract."""


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: Sequence[Mapping[str, Any]], fields: Sequence[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(fields), extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fields})


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_artifact_manifest(base: Path, evidence_path: Path) -> dict[str, Any]:
    if not evidence_path.is_file():
        raise EvidenceError(f"missing evidence manifest: {evidence_path}")
    evidence = read_json(evidence_path)
    artifacts = evidence.get("artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        raise EvidenceError(f"empty artifact manifest: {evidence_path}")
    for relative, expected in artifacts.items():
        artifact = base / relative
        if not artifact.is_file():
            raise EvidenceError(f"missing sealed artifact: {artifact}")
        actual = sha256_file(artifact)
        if actual != expected:
            raise EvidenceError(
                f"SHA-256 mismatch for {artifact}: expected {expected}, got {actual}"
            )
    return evidence


def pinball_loss(truth: np.ndarray, prediction: np.ndarray, quantiles: np.ndarray) -> np.ndarray:
    residual = truth[..., None] - prediction
    return np.where(residual >= 0.0, quantiles * residual, (quantiles - 1.0) * residual)


def metric_record(truth: np.ndarray, prediction: np.ndarray, quantiles: np.ndarray) -> dict[str, Any]:
    if prediction.shape != truth.shape + (quantiles.size,):
        raise EvidenceError(
            f"prediction shape {prediction.shape} does not match truth {truth.shape} and quantiles"
        )
    median_index = int(np.flatnonzero(np.isclose(quantiles, 0.5))[0])
    lower_index = int(np.flatnonzero(np.isclose(quantiles, 0.1))[0])
    upper_index = int(np.flatnonzero(np.isclose(quantiles, 0.9))[0])
    exceedance = np.mean(truth[..., None] > prediction, axis=tuple(range(truth.ndim)))
    crossing = np.mean(prediction[..., :-1] > prediction[..., 1:])
    return {
        "AQL": float(np.mean(pinball_loss(truth, prediction, quantiles))),
        "median_MAE": float(np.mean(np.abs(truth - prediction[..., median_index]))),
        "coverage_80": float(
            np.mean(
                (truth >= prediction[..., lower_index])
                & (truth <= prediction[..., upper_index])
            )
        ),
        "width_80": float(
            np.mean(prediction[..., upper_index] - prediction[..., lower_index])
        ),
        "calibration_rmse": float(
            np.sqrt(np.mean((exceedance - (1.0 - quantiles)) ** 2))
        ),
        "crossing_rate": float(crossing),
        "exceedance": [float(value) for value in exceedance],
        "n_predictions": int(truth.size),
    }


def numeric_summary(values: np.ndarray, prefix: str) -> dict[str, float]:
    probs = np.array([0.1, 0.25, 0.5, 0.75, 0.9])
    qs = np.quantile(values, probs)
    result = {
        f"{prefix}_mean": float(np.mean(values)),
        f"{prefix}_sd": float(np.std(values)),
    }
    result.update({f"{prefix}_q{int(p * 100):02d}": float(q) for p, q in zip(probs, qs)})
    return result


def require_source_state(
    campaign_root: Path,
    expected: Mapping[str, Any],
    expected_region: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    terminal_path = campaign_root / "terminal.json"
    progress_path = campaign_root / "progress.json"
    if not terminal_path.is_file() or not progress_path.is_file():
        raise EvidenceError(f"campaign lacks terminal/progress state: {campaign_root}")
    terminal = read_json(terminal_path)
    progress = read_json(progress_path)
    if terminal.get("status") != expected["terminal_status"]:
        raise EvidenceError(f"unexpected terminal status for {expected_region}: {terminal.get('status')}")
    source = terminal.get("source", {})
    if source.get("branch") != expected["source_branch"] or source.get("head") != expected["source_head"]:
        raise EvidenceError(f"source identity mismatch for {expected_region}: {source}")
    if int(progress.get("completed", -1)) != int(expected["expected_completed_tasks"]):
        raise EvidenceError(f"completed-task count mismatch for {expected_region}")
    if "expected_task_directories" in expected:
        task_count = sum(1 for path in (campaign_root / "tasks_done").iterdir() if path.is_dir())
        if task_count != int(expected["expected_task_directories"]):
            raise EvidenceError(
                f"task-directory count mismatch for {expected_region}: "
                f"got {task_count}, expected {expected['expected_task_directories']}"
            )
    if int(progress.get("active", -1)) != 0 or int(progress.get("pending", -1)) != 0:
        raise EvidenceError(f"campaign is not quiescent for {expected_region}")
    if progress.get("failures"):
        raise EvidenceError(f"campaign reports failures for {expected_region}")
    verify_artifact_manifest(campaign_root / "closeout", campaign_root / "closeout/completed_evidence.json")
    closeout_source = read_json(campaign_root / "closeout/completed_evidence.json").get("metadata", {}).get("source", {})
    if closeout_source.get("head") != expected["source_head"]:
        raise EvidenceError(f"closeout source HEAD mismatch for {expected_region}")
    return terminal, progress


def load_prediction_packet(task_dir: Path, expected_head: str) -> dict[str, np.ndarray]:
    evidence = verify_artifact_manifest(task_dir, task_dir / "completed_evidence.json")
    metadata = evidence.get("metadata", {})
    if metadata.get("source_head") != expected_head or metadata.get("certified") is not True:
        raise EvidenceError(f"uncertified or wrong-source forecast packet: {task_dir}")
    result = read_json(task_dir / "result.json")
    if result.get("certified") is not True:
        raise EvidenceError(f"forecast result is not certified: {task_dir}")
    with np.load(task_dir / "predictions.npz", allow_pickle=False) as packet:
        return {key: np.asarray(packet[key]) for key in packet.files}


def reconstruct_fold(
    campaign_root: Path,
    region: str,
    fold: int,
    operators: Sequence[str],
    expected_head: str,
    expected_origins: int,
    horizon: int,
    quantile_count: int,
) -> dict[str, np.ndarray]:
    task_dirs = sorted((campaign_root / "tasks_done").glob(f"{region}_fold{fold}_forecast*"))
    if not task_dirs:
        raise EvidenceError(f"no forecast packets for {region} fold {fold}")
    chunks = [load_prediction_packet(path, expected_head) for path in task_dirs]
    required = set(operators) | {"truth", "anchors_ns", "positions"}
    for task_dir, chunk in zip(task_dirs, chunks):
        missing = required - set(chunk)
        if missing:
            raise EvidenceError(f"{task_dir} is missing arrays: {sorted(missing)}")
        n = chunk["truth"].shape[0]
        if chunk["truth"].shape != (n, horizon):
            raise EvidenceError(f"wrong truth shape in {task_dir}: {chunk['truth'].shape}")
        for operator in operators:
            if chunk[operator].shape != (n, horizon, quantile_count):
                raise EvidenceError(f"wrong {operator} shape in {task_dir}: {chunk[operator].shape}")
    combined = {
        key: np.concatenate([chunk[key] for chunk in chunks], axis=0)
        for key in required
    }
    order = np.argsort(combined["positions"])
    combined = {key: value[order] for key, value in combined.items()}
    positions = combined["positions"].astype(int)
    if positions.tolist() != list(range(expected_origins)):
        raise EvidenceError(
            f"origin positions are not contiguous for {region} fold {fold}: "
            f"got {positions.size}, expected {expected_origins}"
        )
    anchors = combined["anchors_ns"].astype(np.int64)
    if anchors.size > 1 and not np.all(np.diff(anchors) > 0):
        raise EvidenceError(f"anchors are not strictly increasing for {region} fold {fold}")
    if not all(np.isfinite(combined[key]).all() for key in set(operators) | {"truth"}):
        raise EvidenceError(f"non-finite predictions for {region} fold {fold}")
    return combined


def fold_reference_map(path: Path) -> dict[tuple[int, str], dict[str, str]]:
    rows = read_csv(path)
    return {(int(row["fold"]), row["operator"]): row for row in rows}


def assert_frozen_metric_match(
    observed: Mapping[str, Any],
    reference: Mapping[str, str],
    region: str,
    fold: int,
    operator: str,
    tolerance: float = 1e-9,
) -> None:
    for metric in ("AQL", "median_MAE", "coverage_80", "width_80"):
        delta = abs(float(observed[metric]) - float(reference[metric]))
        if delta > tolerance:
            raise EvidenceError(
                f"frozen metric mismatch for {region} fold {fold} {operator} {metric}: "
                f"delta={delta:.3g}"
            )


def load_training_response(
    campaign_root: Path,
    region: str,
    fold: int,
    expected_head: str,
    design_task_suffix: str = "design",
) -> np.ndarray:
    task_dir = campaign_root / "tasks_done" / f"{region}_fold{fold}_{design_task_suffix}"
    evidence = verify_artifact_manifest(task_dir, task_dir / "completed_evidence.json")
    metadata = evidence.get("metadata", {})
    if metadata.get("source_head") != expected_head or metadata.get("certified") is not True:
        raise EvidenceError(f"uncertified or wrong-source design packet: {task_dir}")
    scaler = read_json(task_dir / "design/scaler.json")
    standardized = np.fromfile(task_dir / "design/y.bin", dtype="<f8")
    expected_n = int(scaler["training_origin_count"]) * 96
    if standardized.size != expected_n or not np.isfinite(standardized).all():
        raise EvidenceError(f"invalid design response for {region} fold {fold}")
    return standardized * float(scaler["price_scale"]) + float(scaler["price_mean"])


def verify_region_packet(packet_dir: Path) -> dict[str, Any]:
    evidence = verify_artifact_manifest(packet_dir, packet_dir / "completed_evidence.json")
    terminal = read_json(packet_dir / "terminal.json")
    if terminal.get("status") != "R139_REGION_PACKET_COMPLETE":
        raise EvidenceError(f"incomplete R139 regional packet: {packet_dir}")
    return evidence


def flatten_exceedance(row: dict[str, Any]) -> dict[str, Any]:
    result = dict(row)
    exceedance = result.pop("exceedance", [])
    for index, value in enumerate(exceedance):
        result[f"exceedance_q{index + 1}"] = value
    return result


def run_region(config_path: Path, stage: str, region: str, campaign_root: Path, output: Path) -> None:
    config = read_json(config_path)
    if stage == "r137":
        expected = config["r137"]
        if region not in expected["regions"]:
            raise EvidenceError(f"{region} is not in the configured R137 cohort")
        role = "cohort"
    elif stage == "r138":
        expected = config["r138_negative_control"]
        if region != expected["region"]:
            raise EvidenceError(f"{region} is not the configured R138 negative control")
        role = "negative_control"
    else:
        raise EvidenceError(f"unknown stage: {stage}")

    if output.exists() and any(output.iterdir()):
        raise EvidenceError(f"refusing to overwrite non-empty output directory: {output}")
    output.mkdir(parents=True, exist_ok=True)
    terminal, progress = require_source_state(campaign_root, expected, region)
    quantiles = np.asarray(config["quantiles"], dtype=float)
    operators = list(config["operators"])
    horizon = int(config["forecast_horizon"])
    reference = fold_reference_map(campaign_root / "closeout/fold_comparison.csv")

    fold_rows: list[dict[str, Any]] = []
    horizon_rows: list[dict[str, Any]] = []
    block_rows: list[dict[str, Any]] = []
    shift_rows: list[dict[str, Any]] = []
    reconstructed: dict[int, dict[str, np.ndarray]] = {}

    for fold in (1, 2, 3):
        expected_origins = int(expected["expected_origins_by_fold"][str(fold)])
        arrays = reconstruct_fold(
            campaign_root,
            region,
            fold,
            operators,
            expected["source_head"],
            expected_origins,
            horizon,
            quantiles.size,
        )
        reconstructed[fold] = arrays
        truth = arrays["truth"]
        for operator in operators:
            metrics = metric_record(truth, arrays[operator], quantiles)
            if (fold, operator) in reference:
                assert_frozen_metric_match(metrics, reference[(fold, operator)], region, fold, operator)
            fold_rows.append(flatten_exceedance({
                "stage": stage,
                "role": role,
                "region": region,
                "fold": fold,
                "operator": operator,
                **metrics,
                "qdesn_AQL": float(reference[(fold, "cdf_pool_clipped")]["qdesn_AQL"]),
                "pricefm_AQL": float(reference[(fold, "cdf_pool_clipped")]["pricefm_AQL"]),
                "operational_pricefm_AQL": float(
                    reference[(fold, "cdf_pool_clipped")]["operational_pricefm_AQL"]
                ),
            }))
            for lead in range(horizon):
                lead_metrics = metric_record(truth[:, lead], arrays[operator][:, lead, :], quantiles)
                horizon_rows.append(flatten_exceedance({
                    "stage": stage,
                    "role": role,
                    "region": region,
                    "fold": fold,
                    "operator": operator,
                    "horizon": lead + 1,
                    **lead_metrics,
                }))
            for block in config["horizon_blocks"]:
                start = int(block["start"]) - 1
                end = int(block["end"])
                block_metrics = metric_record(
                    truth[:, start:end], arrays[operator][:, start:end, :], quantiles
                )
                block_rows.append(flatten_exceedance({
                    "stage": stage,
                    "role": role,
                    "region": region,
                    "fold": fold,
                    "operator": operator,
                    "horizon_block": block["label"],
                    "horizon_start": start + 1,
                    "horizon_end": end,
                    **block_metrics,
                }))

        train = load_training_response(
            campaign_root,
            region,
            fold,
            expected["source_head"],
            expected.get("design_task_suffix", "design"),
        )
        test = truth.reshape(-1)
        row = {"stage": stage, "role": role, "region": region, "fold": fold}
        row.update(numeric_summary(train, "train"))
        row.update(numeric_summary(test, "test"))
        row["mean_shift_in_train_sd"] = float(
            (np.mean(test) - np.mean(train)) / max(np.std(train), EPS)
        )
        probs = np.linspace(0.01, 0.99, 99)
        row["quantile_distance_in_train_sd"] = float(
            np.mean(np.abs(np.quantile(test, probs) - np.quantile(train, probs)))
            / max(np.std(train), EPS)
        )
        row["train_rows"] = int(train.size)
        row["test_rows"] = int(test.size)
        row["weighting_note"] = "design-row and forecast-row weighted; overlapping horizons retained"
        shift_rows.append(row)

    numeric_metric_fields = [
        "AQL", "median_MAE", "coverage_80", "width_80", "calibration_rmse", "crossing_rate"
    ]
    region_rows: list[dict[str, Any]] = []
    for operator in operators:
        selected = [row for row in fold_rows if row["operator"] == operator]
        aggregate = {field: float(np.mean([float(row[field]) for row in selected])) for field in numeric_metric_fields}
        aggregate.update({
            "stage": stage,
            "role": role,
            "region": region,
            "operator": operator,
            "folds": 3,
            "qdesn_AQL": float(np.mean([float(row["qdesn_AQL"]) for row in selected])),
            "pricefm_AQL": float(np.mean([float(row["pricefm_AQL"]) for row in selected])),
            "operational_pricefm_AQL": float(
                np.mean([float(row["operational_pricefm_AQL"]) for row in selected])
            ),
        })
        region_rows.append(aggregate)

    metric_fields = [
        "stage", "role", "region", "fold", "operator", *numeric_metric_fields,
        "n_predictions", "qdesn_AQL", "pricefm_AQL", "operational_pricefm_AQL",
        *[f"exceedance_q{i}" for i in range(1, quantiles.size + 1)],
    ]
    horizon_fields = [
        "stage", "role", "region", "fold", "operator", "horizon", *numeric_metric_fields,
        "n_predictions", *[f"exceedance_q{i}" for i in range(1, quantiles.size + 1)],
    ]
    block_fields = [
        "stage", "role", "region", "fold", "operator", "horizon_block",
        "horizon_start", "horizon_end", *numeric_metric_fields, "n_predictions",
        *[f"exceedance_q{i}" for i in range(1, quantiles.size + 1)],
    ]
    region_fields = [
        "stage", "role", "region", "operator", "folds", *numeric_metric_fields,
        "qdesn_AQL", "pricefm_AQL", "operational_pricefm_AQL",
    ]
    shift_fields = list(shift_rows[0].keys())
    write_csv(output / "fold_metrics.csv", fold_rows, metric_fields)
    write_csv(output / "horizon_metrics.csv", horizon_rows, horizon_fields)
    write_csv(output / "horizon_block_metrics.csv", block_rows, block_fields)
    write_csv(output / "region_metrics.csv", region_rows, region_fields)
    write_csv(output / "distribution_shift.csv", shift_rows, shift_fields)
    write_json(output / "source_manifest.json", {
        "schema_version": config["schema_version"],
        "run_tag": config["run_tag"],
        "stage": stage,
        "role": role,
        "region": region,
        "campaign_root": str(campaign_root.resolve()),
        "source_branch": expected["source_branch"],
        "source_head": expected["source_head"],
        "source_terminal": terminal,
        "source_progress": progress,
        "source_closeout_sha256": sha256_file(campaign_root / "closeout/completed_evidence.json"),
        "forecast_packets": sum(
            len(list((campaign_root / "tasks_done").glob(f"{region}_fold{fold}_forecast*")))
            for fold in (1, 2, 3)
        ),
        "origin_counts": {str(fold): int(reconstructed[fold]["truth"].shape[0]) for fold in (1, 2, 3)},
        "read_only_source": True,
        "fit_or_forecast_executed": False,
    })
    write_json(output / "terminal.json", {
        "status": "R139_REGION_PACKET_COMPLETE",
        "stage": stage,
        "role": role,
        "region": region,
        "source_head": expected["source_head"],
        "integrity_verified": True,
        "frozen_metrics_reproduced": True,
    })
    artifacts = {
        name: sha256_file(output / name)
        for name in (
            "distribution_shift.csv", "fold_metrics.csv", "horizon_block_metrics.csv",
            "horizon_metrics.csv", "region_metrics.csv", "source_manifest.json", "terminal.json"
        )
    }
    write_json(output / "completed_evidence.json", {
        "artifacts": artifacts,
        "metadata": {
            "schema_version": config["schema_version"],
            "region": region,
            "role": role,
            "source_head": expected["source_head"],
        },
    })


def percent_delta(value: float, reference: float) -> float:
    return 100.0 * (value - reference) / reference


def aggregate_rows(rows: Sequence[Mapping[str, str]], keys: Sequence[str], metrics: Sequence[str]) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, ...], list[Mapping[str, str]]] = {}
    for row in rows:
        grouped.setdefault(tuple(row[key] for key in keys), []).append(row)
    result: list[dict[str, Any]] = []
    for group_key, group_rows in sorted(grouped.items()):
        row: dict[str, Any] = dict(zip(keys, group_key))
        row.update({metric: float(np.mean([float(item[metric]) for item in group_rows])) for metric in metrics})
        row["regions"] = len({item["region"] for item in group_rows})
        row["fold_rows"] = len(group_rows)
        result.append(row)
    return result


def render_pdf(
    output: Path,
    comparison_rows: Sequence[Mapping[str, Any]],
    fold_rows: Sequence[Mapping[str, str]],
    horizon_rows: Sequence[Mapping[str, str]],
    block_rows: Sequence[Mapping[str, str]],
    shift_rows: Sequence[Mapping[str, str]],
    decision: Mapping[str, Any],
    primary_operator: str,
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    colors = {
        "R137 primary": "#2364AA",
        "Authoritative QDESN": "#D1495B",
        "Local PriceFM": "#2A9D8F",
        "Operational PriceFM": "#6C757D",
    }
    regions = [row["region"] for row in comparison_rows]
    x = np.arange(len(regions))
    series = [
        ("R137 primary", [float(row["r137_AQL"]) for row in comparison_rows]),
        ("Authoritative QDESN", [float(row["qdesn_AQL"]) for row in comparison_rows]),
        ("Local PriceFM", [float(row["pricefm_AQL"]) for row in comparison_rows]),
        ("Operational PriceFM", [float(row["operational_pricefm_AQL"]) for row in comparison_rows]),
    ]
    pdf_path = output / "pricefm_stage_r139_cohort_diagnostics.pdf"
    with PdfPages(pdf_path) as pdf:
        fig = plt.figure(figsize=(11, 8.5), constrained_layout=True)
        grid = fig.add_gridspec(2, 1, height_ratios=[2.0, 1.25])
        ax = fig.add_subplot(grid[0])
        width = 0.19
        for index, (label, values) in enumerate(series):
            bars = ax.bar(x + (index - 1.5) * width, values, width, label=label, color=colors[label])
            ax.bar_label(bars, fmt="%.2f", padding=2, fontsize=7)
        ax.set_xticks(x, regions)
        ax.set_ylabel("Average quantile loss (lower is better)")
        ax.set_title("R137 four-region pilot: matched three-fold comparison", loc="left", weight="bold")
        ax.grid(axis="y", alpha=0.2)
        ax.legend(ncol=2, frameon=False)
        ax2 = fig.add_subplot(grid[1])
        ax2.axis("off")
        table_data = []
        for row in comparison_rows:
            table_data.append([
                row["region"], f"{float(row['r137_AQL']):.3f}",
                f"{float(row['delta_vs_qdesn_pct']):+.1f}%",
                f"{float(row['delta_vs_local_pricefm_pct']):+.1f}%",
                f"{float(row['delta_vs_operational_pricefm_pct']):+.1f}%",
            ])
        table_data.append([
            "Equal-region mean", f"{decision['cohort_AQL']:.3f}",
            f"{decision['delta_vs_qdesn_pct']:+.1f}%",
            f"{decision['delta_vs_local_pricefm_pct']:+.1f}%",
            f"{decision['delta_vs_operational_pricefm_pct']:+.1f}%",
        ])
        table = ax2.table(
            cellText=table_data,
            colLabels=["Region", "R137", "vs QDESN", "vs local PriceFM", "vs operational PriceFM"],
            cellLoc="center", loc="center", colWidths=[0.2, 0.14, 0.18, 0.22, 0.24]
        )
        table.auto_set_font_size(False)
        table.set_fontsize(9)
        table.scale(1, 1.5)
        for (row, col), cell in table.get_celld().items():
            cell.set_edgecolor("#D8DEE4")
            if row == 0:
                cell.set_facecolor("#EAF2F8")
                cell.set_text_props(weight="bold")
        fig.suptitle(
            f"Decision: {decision['decision']}\n"
            "Negative percentages indicate lower AQL than the comparator.",
            x=0.06, y=1.02, ha="left", fontsize=11,
        )
        pdf.savefig(fig, bbox_inches="tight")
        plt.close(fig)

        fig, axes = plt.subplots(2, 2, figsize=(11, 8.5), sharex=True, constrained_layout=True)
        for ax, region in zip(axes.flat, regions):
            selected = [
                row for row in horizon_rows
                if row["region"] == region and row["operator"] == primary_operator
            ]
            by_horizon: dict[int, list[float]] = {}
            for row in selected:
                by_horizon.setdefault(int(row["horizon"]), []).append(float(row["AQL"]))
            horizon_values = sorted(by_horizon)
            means = np.array([np.mean(by_horizon[h]) for h in horizon_values])
            smooth = np.convolve(means, np.ones(6) / 6.0, mode="same")
            ax.plot(horizon_values, means, color="#90B8D8", linewidth=0.8, alpha=0.8)
            ax.plot(horizon_values[3:-3], smooth[3:-3], color="#2364AA", linewidth=2.0)
            ax.set_title(region, loc="left", weight="bold")
            ax.grid(alpha=0.2)
            ax.set_ylabel("AQL")
        for ax in axes[-1, :]:
            ax.set_xlabel("Forecast horizon (hours)")
        fig.suptitle(
            "Where forecast loss grows across the 96-hour horizon\n"
            "Thin line: hourly; dark line: six-hour moving mean; folds averaged equally",
            x=0.07, ha="left", weight="bold",
        )
        pdf.savefig(fig, bbox_inches="tight")
        plt.close(fig)

        fig, axes = plt.subplots(1, 2, figsize=(11, 8.5), constrained_layout=True)
        blocks = ["h01_24", "h25_48", "h49_72", "h73_96"]
        matrix_aql = np.zeros((len(regions), len(blocks)))
        matrix_cov = np.zeros_like(matrix_aql)
        for i, region in enumerate(regions):
            for j, block in enumerate(blocks):
                selected = [
                    row for row in block_rows
                    if row["region"] == region
                    and row["operator"] == primary_operator
                    and row["horizon_block"] == block
                ]
                matrix_aql[i, j] = np.mean([float(row["AQL"]) for row in selected])
                matrix_cov[i, j] = np.mean([float(row["coverage_80"]) for row in selected])
        for ax, matrix, title, fmt, cmap, vmin, vmax in (
            (axes[0], matrix_aql, "AQL by 24-hour block", ".2f", "Blues", None, None),
            (axes[1], matrix_cov, "80% interval coverage", ".0%", "RdYlGn", 0.0, 1.0),
        ):
            image = ax.imshow(matrix, aspect="auto", cmap=cmap, vmin=vmin, vmax=vmax)
            ax.set_xticks(range(len(blocks)), ["1-24", "25-48", "49-72", "73-96"])
            ax.set_yticks(range(len(regions)), regions)
            ax.set_title(title, loc="left", weight="bold")
            for i in range(matrix.shape[0]):
                for j in range(matrix.shape[1]):
                    ax.text(j, i, format(matrix[i, j], fmt), ha="center", va="center", fontsize=9)
            fig.colorbar(image, ax=ax, shrink=0.72)
        fig.suptitle(
            "Horizon degradation and calibration of the primary R137 operator",
            x=0.05, ha="left", weight="bold",
        )
        pdf.savefig(fig, bbox_inches="tight")
        plt.close(fig)

        fig, ax = plt.subplots(figsize=(11, 8.5), constrained_layout=True)
        ax.axis("off")
        lines = [
            "Interpretation",
            "",
            f"Primary result: equal-region AQL {decision['cohort_AQL']:.3f}; "
            f"authoritative QDESN {decision['qdesn_AQL']:.3f} "
            f"({decision['delta_vs_qdesn_pct']:+.1f}%).",
            f"Regional wins against authority: {decision['region_wins_vs_qdesn']}/4; "
            f"fold wins: {decision['fold_wins_vs_qdesn']}/{decision['fold_count']}.",
            "",
            "What this supports",
            "The family is promising enough to freeze and evaluate prospectively across remaining regions "
            "if the objective is to improve on the current QDESN authority.",
            "",
            "What this does not support",
            "These four folds have been inspected during development. They do not establish a confirmatory "
            "all-region result, and R139 does not promote or modify any authority.",
            "",
            "R138/DK_1 context",
            f"The separate targeted DK_1 follow-up obtained AQL {decision['negative_control']['AQL']:.3f} "
            f"versus its authority {decision['negative_control']['qdesn_AQL']:.3f}. It is excluded from the "
            "R137 cohort mean and argues against more test-guided DK_1 tuning.",
            "",
            "Remaining limitation",
            "The frozen packets contain operator forecasts but not raw Normal-RHS driver paths. Horizon loss "
            "is diagnosed exactly; raw driver-path error cannot be reconstructed without a later scoring-only replay.",
        ]
        y = 0.97
        for index, line in enumerate(lines):
            if line in {"Interpretation", "What this supports", "What this does not support", "R138/DK_1 context", "Remaining limitation"}:
                ax.text(0.04, y, line, fontsize=14 if index == 0 else 12, weight="bold", va="top")
            else:
                ax.text(0.04, y, line, fontsize=10.5, va="top", wrap=True)
            y -= 0.054 if line else 0.035
        pdf.savefig(fig, bbox_inches="tight")
        plt.close(fig)


def run_aggregate(
    config_path: Path,
    packets: Sequence[str],
    negative_control: Path,
    output: Path,
) -> None:
    config = read_json(config_path)
    expected_regions = list(config["r137"]["regions"])
    packet_map: dict[str, Path] = {}
    for packet in packets:
        if "=" not in packet:
            raise EvidenceError(f"packet must use REGION=PATH syntax: {packet}")
        region, path = packet.split("=", 1)
        if region in packet_map:
            raise EvidenceError(f"duplicate packet for {region}")
        packet_map[region] = Path(path)
    if set(packet_map) != set(expected_regions):
        raise EvidenceError(f"aggregate requires exactly {expected_regions}; got {sorted(packet_map)}")
    if output.exists() and any(output.iterdir()):
        raise EvidenceError(f"refusing to overwrite non-empty output directory: {output}")
    output.mkdir(parents=True, exist_ok=True)

    all_fold_rows: list[dict[str, str]] = []
    all_horizon_rows: list[dict[str, str]] = []
    all_block_rows: list[dict[str, str]] = []
    all_shift_rows: list[dict[str, str]] = []
    region_rows: list[dict[str, str]] = []
    packet_hashes: dict[str, str] = {}
    for region in expected_regions:
        packet_dir = packet_map[region]
        evidence = verify_region_packet(packet_dir)
        metadata = evidence.get("metadata", {})
        if metadata.get("region") != region or metadata.get("role") != "cohort":
            raise EvidenceError(f"wrong regional packet identity for {region}")
        if metadata.get("source_head") != config["r137"]["source_head"]:
            raise EvidenceError(f"wrong R137 source HEAD for {region}")
        packet_hashes[region] = sha256_file(packet_dir / "completed_evidence.json")
        all_fold_rows.extend(read_csv(packet_dir / "fold_metrics.csv"))
        all_horizon_rows.extend(read_csv(packet_dir / "horizon_metrics.csv"))
        all_block_rows.extend(read_csv(packet_dir / "horizon_block_metrics.csv"))
        all_shift_rows.extend(read_csv(packet_dir / "distribution_shift.csv"))
        region_rows.extend(read_csv(packet_dir / "region_metrics.csv"))

    negative_evidence = verify_region_packet(negative_control)
    negative_metadata = negative_evidence.get("metadata", {})
    if negative_metadata.get("region") != config["r138_negative_control"]["region"]:
        raise EvidenceError("wrong negative-control region")
    if negative_metadata.get("role") != "negative_control":
        raise EvidenceError("R138 packet is not marked as a negative control")
    negative_rows = read_csv(negative_control / "region_metrics.csv")

    primary = config["primary_operator"]
    comparisons: list[dict[str, Any]] = []
    for region in expected_regions:
        candidates = [row for row in region_rows if row["region"] == region and row["operator"] == primary]
        if len(candidates) != 1:
            raise EvidenceError(f"expected one primary regional row for {region}")
        source = candidates[0]
        value = float(source["AQL"])
        qdesn = float(source["qdesn_AQL"])
        local = float(source["pricefm_AQL"])
        operational = float(source["operational_pricefm_AQL"])
        comparisons.append({
            "region": region,
            "r137_AQL": value,
            "qdesn_AQL": qdesn,
            "pricefm_AQL": local,
            "operational_pricefm_AQL": operational,
            "delta_vs_qdesn": value - qdesn,
            "delta_vs_qdesn_pct": percent_delta(value, qdesn),
            "delta_vs_local_pricefm": value - local,
            "delta_vs_local_pricefm_pct": percent_delta(value, local),
            "delta_vs_operational_pricefm": value - operational,
            "delta_vs_operational_pricefm_pct": percent_delta(value, operational),
            "wins_vs_qdesn": value < qdesn,
            "wins_vs_local_pricefm": value < local,
            "wins_vs_operational_pricefm": value < operational,
        })

    cohort = float(np.mean([row["r137_AQL"] for row in comparisons]))
    qdesn = float(np.mean([row["qdesn_AQL"] for row in comparisons]))
    local = float(np.mean([row["pricefm_AQL"] for row in comparisons]))
    operational = float(np.mean([row["operational_pricefm_AQL"] for row in comparisons]))
    primary_folds = [row for row in all_fold_rows if row["operator"] == primary]
    negative_primary = [row for row in negative_rows if row["operator"] == primary]
    if len(negative_primary) != 1:
        raise EvidenceError("expected one primary negative-control row")
    negative = negative_primary[0]
    promising = cohort < qdesn
    decision = {
        "decision": "PROMISING_FOR_FROZEN_PROSPECTIVE_ROLLOUT" if promising else "STOP_BEFORE_WIDER_ROLLOUT",
        "primary_goal": config["decision_contract"]["primary_goal"],
        "primary_operator": primary,
        "regions": expected_regions,
        "region_count": len(expected_regions),
        "fold_count": len(primary_folds),
        "cohort_AQL": cohort,
        "qdesn_AQL": qdesn,
        "local_pricefm_AQL": local,
        "operational_pricefm_AQL": operational,
        "delta_vs_qdesn_pct": percent_delta(cohort, qdesn),
        "delta_vs_local_pricefm_pct": percent_delta(cohort, local),
        "delta_vs_operational_pricefm_pct": percent_delta(cohort, operational),
        "region_wins_vs_qdesn": sum(bool(row["wins_vs_qdesn"]) for row in comparisons),
        "region_wins_vs_local_pricefm": sum(bool(row["wins_vs_local_pricefm"]) for row in comparisons),
        "region_wins_vs_operational_pricefm": sum(bool(row["wins_vs_operational_pricefm"]) for row in comparisons),
        "fold_wins_vs_qdesn": sum(float(row["AQL"]) < float(row["qdesn_AQL"]) for row in primary_folds),
        "negative_control": {
            "region": negative["region"],
            "AQL": float(negative["AQL"]),
            "qdesn_AQL": float(negative["qdesn_AQL"]),
            "excluded_from_cohort": True,
        },
        "authority_replaced": False,
        "article_updated": False,
        "confirmatory_claim": False,
        "recommended_next_action": (
            "Freeze the R137 workflow before a prospective remaining-region run; do not tune further on these folds."
            if promising
            else "Do not launch the family broadly; return to a separately declared development study."
        ),
        "limitations": [
            "R137 folds were inspected during model development and are not untouched confirmation data.",
            "Only four regions are in the cohort.",
            "Raw Normal-RHS driver paths are absent from the frozen packets; driver-path error is unresolved.",
            "R138 DK_1 is post-selection follow-up evidence and is excluded from the R137 cohort estimate."
        ],
    }

    comparison_fields = list(comparisons[0].keys())
    write_csv(output / "region_comparison.csv", comparisons, comparison_fields)
    write_csv(output / "fold_metrics.csv", all_fold_rows, list(all_fold_rows[0].keys()))
    write_csv(output / "horizon_metrics.csv", all_horizon_rows, list(all_horizon_rows[0].keys()))
    write_csv(output / "horizon_block_metrics.csv", all_block_rows, list(all_block_rows[0].keys()))
    write_csv(output / "distribution_shift.csv", all_shift_rows, list(all_shift_rows[0].keys()))
    aggregate_block = aggregate_rows(
        all_block_rows,
        ["operator", "horizon_block"],
        ["AQL", "median_MAE", "coverage_80", "width_80", "calibration_rmse", "crossing_rate"],
    )
    write_csv(output / "cohort_horizon_block_metrics.csv", aggregate_block, list(aggregate_block[0].keys()))
    write_json(output / "decision.json", decision)
    write_csv(output / "report_summary.csv", [{
        "decision": decision["decision"],
        "cohort_AQL": decision["cohort_AQL"],
        "qdesn_AQL": decision["qdesn_AQL"],
        "local_pricefm_AQL": decision["local_pricefm_AQL"],
        "operational_pricefm_AQL": decision["operational_pricefm_AQL"],
        "delta_vs_qdesn_pct": decision["delta_vs_qdesn_pct"],
        "delta_vs_local_pricefm_pct": decision["delta_vs_local_pricefm_pct"],
        "delta_vs_operational_pricefm_pct": decision["delta_vs_operational_pricefm_pct"],
        "region_wins_vs_qdesn": decision["region_wins_vs_qdesn"],
        "fold_wins_vs_qdesn": decision["fold_wins_vs_qdesn"],
        "fold_count": decision["fold_count"],
        "negative_control_region": decision["negative_control"]["region"],
        "negative_control_AQL": decision["negative_control"]["AQL"],
        "negative_control_qdesn_AQL": decision["negative_control"]["qdesn_AQL"],
    }], [
        "decision", "cohort_AQL", "qdesn_AQL", "local_pricefm_AQL",
        "operational_pricefm_AQL", "delta_vs_qdesn_pct",
        "delta_vs_local_pricefm_pct", "delta_vs_operational_pricefm_pct",
        "region_wins_vs_qdesn", "fold_wins_vs_qdesn", "fold_count",
        "negative_control_region", "negative_control_AQL", "negative_control_qdesn_AQL",
    ])
    write_json(output / "source_manifest.json", {
        "schema_version": config["schema_version"],
        "run_tag": config["run_tag"],
        "r137_packet_evidence_sha256": packet_hashes,
        "r138_negative_control_evidence_sha256": sha256_file(negative_control / "completed_evidence.json"),
        "r138_excluded_from_r137_aggregate": True,
        "fit_or_forecast_executed": False,
        "authority_or_article_mutated": False,
    })
    renderer = Path(__file__).with_name("475_render_pricefm_stage_r139_cohort_diagnostics.R")
    subprocess.run(["Rscript", str(renderer), str(output), primary], check=True)
    write_json(output / "terminal.json", {
        "status": "R139_COHORT_DIAGNOSTICS_COMPLETE_NOT_PROMOTED",
        "decision": decision["decision"],
        "integrity_verified": True,
        "region_packets": len(packet_map),
        "negative_controls": 1,
        "authority_replaced": False,
    })
    artifact_names = [
        "cohort_horizon_block_metrics.csv", "decision.json", "distribution_shift.csv",
        "fold_metrics.csv", "horizon_block_metrics.csv", "horizon_metrics.csv",
        "pricefm_stage_r139_cohort_diagnostics.pdf", "region_comparison.csv",
        "report_summary.csv", "source_manifest.json", "terminal.json",
    ]
    write_json(output / "completed_evidence.json", {
        "artifacts": {name: sha256_file(output / name) for name in artifact_names},
        "metadata": {
            "schema_version": config["schema_version"],
            "run_tag": config["run_tag"],
            "status": "R139_COHORT_DIAGNOSTICS_COMPLETE_NOT_PROMOTED",
        },
    })


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    region = subparsers.add_parser("region", help="build one sealed regional diagnostic packet")
    region.add_argument("--config", required=True, type=Path)
    region.add_argument("--stage", required=True, choices=("r137", "r138"))
    region.add_argument("--region", required=True)
    region.add_argument("--campaign-root", required=True, type=Path)
    region.add_argument("--output", required=True, type=Path)
    aggregate = subparsers.add_parser("aggregate", help="aggregate the four R137 packets")
    aggregate.add_argument("--config", required=True, type=Path)
    aggregate.add_argument("--packet", action="append", required=True)
    aggregate.add_argument("--negative-control", required=True, type=Path)
    aggregate.add_argument("--output", required=True, type=Path)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    if args.action == "region":
        run_region(args.config, args.stage, args.region, args.campaign_root, args.output)
    else:
        run_aggregate(args.config, args.packet, args.negative_control, args.output)


if __name__ == "__main__":
    main()
