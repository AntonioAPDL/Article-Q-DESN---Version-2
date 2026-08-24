#!/usr/bin/env python3
"""Audit the frozen operational PriceFM closeout without changing scientific state."""

from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Iterable

import numpy as np

from pricefm_operational_fullshot import (
    QUANTILES,
    atomic_write_csv,
    atomic_write_json,
    atomic_write_text,
    parse_bool,
    read_csv_rows,
    read_json,
    sha256_file,
)


RUN_TAG = "pricefm_operational_public_architecture_fullshot_20260812"
EXPECTED_FIT_COUNTS = {"phase1": 9, "phase2_screen": 1047, "phase2_stability": 48}
EXPECTED_TEST_TASKS = 136
EXPECTED_SELECTOR_ROWS = 114
EXPECTED_EVENT_ROWS = 21_455
EXPECTED_ORIGINS = {1: 120, 2: 123, 3: 122}
HORIZON_BLOCKS = (("1-24", 0, 24), ("25-48", 24, 48), ("49-72", 48, 72), ("73-96", 72, 96))
METRIC_TOLERANCE = 1.0e-10
WINDOW_TOLERANCE = 1.0e-4

PINNED_ARTIFACT_HASHES = {
    "provenance/protocol.json": "d4ef40f5992a2fc9bb5b6630c6ec940655988440ec3202410726a142e28f231b",
    "provenance/source_manifest.csv": "7c342426175ffd56a2de1cf4fab8dc9985b6d13df2aaf4fa68d54310b24928b1",
    "data/window_manifest.csv": "843bf6a91466181d72c772430a668037b90c8bfaff29a46f7e10d4dd0b435fc3",
    "data/scaler_manifest.csv": "178ecf3197cd528cd8a238b0a2358a7b45df84f5a27316447ec08b67d515f88e",
    "selection/winner_freeze.json": "11e5b6a6bffdb264f3ffb593c53b581a18cd38ad5e8b350f05cf5999787b9aec",
    "selection/cell_specific_winners.csv": "466f14c01a26510ccfea6b2fd0cfb12b7449aa8024f19712b704007d528ea18f",
    "selection/region_global_winners.csv": "0242c2bab03120047c677044c28ca32dd4a698803e7c2e5ec61a7836050392cb",
    "test/preparation_summary.json": "94bc5934be4f3b01016a36e5851f0e09940ea865171809a60f6c3669e8a89889",
    "test/trial_manifest.csv": "d649a28fbe1ce76189e683a16dcc3585689a3ddf8068441e3ca06ebdf72974e9",
    "test/selector_task_map.csv": "bd2993fc2d98f22ee15612e27975d94815038c2134caa7057d083263bc5f1936",
    "test/aggregation_summary.json": "81b3794c786fc111dcd06514af90e87445e30d89bf91d265ce374126ecd4f8c5",
    "test/cell_specific_metrics.csv": "020254be2ba43a4cb1d096b0a456b365b0713190e8ed61afd76806823e8c5e93",
    "test/region_global_metrics.csv": "253bac4d13baa35eec44dd2a44b6eed39ecaec1f6817a616f54c70eb405b9596",
    "closeout/summary.json": "fa2df1e9fe6b1de43ec59f71d2b5f79b1a3fd0266668b8f1b26ab15bb4d8ae15",
    "closeout/decision_registry.csv": "51d95cae91d66c44f65ad2638f6eda62f79664b8ed732a8cb31c9d387701bfb3",
    "closeout/aggregate_summary.csv": "74dbd75086eb6dd197a6daa3a36cb06f043aaf53344cf334c472377387c52de5",
    "closeout/report.md": "8070d878d5206862860387cae07ba929a6e2b69102a5c829b562a8c2c25c7c71",
}
PINNED_QDESN_REGISTRY_SHA256 = "d45c43b6d2dd3b163ca1d3cd0b140ce0e582797aaea0a3db012a7d74293e4802"
PINNED_QDESN_HORIZON_SHA256 = "2455116d61d62607819f3013e484a7c0fa1b0fc47a2052e6b29d17ba786a81eb"
PINNED_CAMPAIGN_HEALTH_SHA256 = "038bf311f11945d1d66c3989bfcaa64bf90fbf6268a4a80a33564b0895a66631"
PINNED_CAMPAIGN_EVENTS_SHA256 = "dbd754356ace10fef441ae00c296b7fced7e4942fd408df1ec090ebb6e350277"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-root", required=True)
    p.add_argument("--qdesn-registry", required=True)
    p.add_argument("--qdesn-horizon-diagnostics", required=True)
    p.add_argument("--reference-repo-root", required=True)
    p.add_argument("--campaign-health", required=True)
    p.add_argument("--campaign-events", required=True)
    p.add_argument("--stage-r55-dir", default="")
    p.add_argument("--stage-r56-prep-dir", default="")
    p.add_argument("--output-dir", required=True)
    p.add_argument("--bootstrap-replicates", type=int, default=2000)
    p.add_argument("--bootstrap-block-origins", type=int, default=7)
    p.add_argument("--bootstrap-seed", type=int, default=20260823)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def boolish(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y", "passed"}


def first_nonblank(row: dict[str, Any], names: Iterable[str]) -> str:
    for name in names:
        value = row.get(name, "")
        if value is not None and str(value).strip() and str(value).strip().lower() != "nan":
            return str(value).strip()
    return ""


def resolve_path(value: str | Path, repo_root: Path | None = None) -> Path:
    path = Path(value)
    if path.is_absolute() or repo_root is None:
        return path.resolve()
    return (repo_root / path).resolve()


def stable_seed(base_seed: int, label: str) -> int:
    digest = hashlib.sha256(f"{base_seed}|{label}".encode("utf-8")).hexdigest()
    return int(digest[:8], 16) % (2**32 - 1)


def pinball_loss(y_true: np.ndarray, y_pred: np.ndarray, quantiles: Iterable[float]) -> np.ndarray:
    quantiles_array = np.asarray(list(quantiles), dtype=np.float64)
    error = np.asarray(y_true, dtype=np.float64)[..., None] - np.asarray(y_pred, dtype=np.float64)
    return np.maximum(
        quantiles_array.reshape(1, 1, -1) * error,
        (quantiles_array.reshape(1, 1, -1) - 1.0) * error,
    )


def scalar_metrics(y_true: np.ndarray, y_pred: np.ndarray, quantiles: Iterable[float]) -> dict[str, float]:
    quantiles_array = np.asarray(list(quantiles), dtype=np.float64)
    predictions = np.asarray(y_pred, dtype=np.float64)
    truth = np.asarray(y_true, dtype=np.float64)
    median_index = int(np.argmin(np.abs(quantiles_array - 0.5)))
    median = predictions[..., median_index]
    crossing = predictions[..., :-1] > predictions[..., 1:]
    return {
        "AQL": float(pinball_loss(truth, predictions, quantiles_array).mean()),
        "AQCR": float(crossing.mean()) if crossing.size else 0.0,
        "MAE": float(np.abs(truth - median).mean()),
        "RMSE": float(np.sqrt(np.square(truth - median).mean())),
    }


def circular_block_bootstrap(
    values: np.ndarray,
    replicates: int,
    block_length: int,
    seed: int,
) -> np.ndarray:
    values = np.asarray(values, dtype=np.float64).reshape(-1)
    if values.size < 2:
        raise ValueError("Block bootstrap requires at least two origins")
    if replicates < 100:
        raise ValueError("At least 100 bootstrap replicates are required")
    if block_length < 1 or block_length > values.size:
        raise ValueError("Bootstrap block length must be in [1, n_origins]")
    blocks = int(math.ceil(values.size / block_length))
    rng = np.random.default_rng(seed)
    starts = rng.integers(0, values.size, size=(replicates, blocks))
    offsets = np.arange(block_length, dtype=np.int64)
    indices = (starts[..., None] + offsets) % values.size
    indices = indices.reshape(replicates, -1)[:, : values.size]
    return values[indices].mean(axis=1)


def classify_selector_evidence(primary_dual: bool, sensitivity_dual: bool) -> str:
    if primary_dual and sensitivity_dual:
        return "tier_a_both_selectors_dual_reference"
    if primary_dual:
        return "tier_b_preregistered_primary_only"
    if sensitivity_dual:
        return "sensitivity_only_not_promotable"
    return "no_dual_reference_evidence"


def r56_disposition(
    prior_m0_aql: float,
    operational_aql: float,
    prior_launch_authorized: bool,
) -> dict[str, Any]:
    beats_operational = prior_m0_aql < operational_aql
    return {
        "prior_r56_launch_authorized": prior_launch_authorized,
        "prior_m0_test_AQL": prior_m0_aql,
        "operational_pricefm_test_AQL": operational_aql,
        "delta_m0_minus_operational_pricefm": prior_m0_aql - operational_aql,
        "m0_beats_operational_pricefm": beats_operational,
        "r56_launch_authorized_now": False,
        "decision": "retain_block" if beats_operational else "superseded_do_not_launch",
        "existing_r56_artifacts_mutated": False,
    }


class SourceLedger:
    def __init__(self) -> None:
        self.rows: list[dict[str, Any]] = []
        self._cache: dict[Path, tuple[int, str]] = {}

    def inspect(
        self,
        path: str | Path,
        *,
        category: str,
        label: str,
        expected_sha256: str = "",
        required: bool = True,
    ) -> tuple[int, str]:
        resolved = Path(path).resolve()
        if not resolved.is_file():
            self.rows.append({
                "category": category,
                "label": label,
                "path": str(resolved),
                "required": required,
                "exists": False,
                "size_bytes": 0,
                "expected_sha256": expected_sha256,
                "observed_sha256": "",
                "hash_matches": False,
            })
            if required:
                raise FileNotFoundError(resolved)
            return 0, ""
        if resolved not in self._cache:
            self._cache[resolved] = (resolved.stat().st_size, sha256_file(resolved))
        size, observed = self._cache[resolved]
        matched = not expected_sha256 or observed == expected_sha256
        self.rows.append({
            "category": category,
            "label": label,
            "path": str(resolved),
            "required": required,
            "exists": True,
            "size_bytes": size,
            "expected_sha256": expected_sha256,
            "observed_sha256": observed,
            "hash_matches": matched,
        })
        if expected_sha256 and not matched:
            raise RuntimeError(
                f"SHA-256 mismatch for {label}: expected {expected_sha256}, observed {observed}"
            )
        return size, observed


def check_pinned_contract(
    root: Path,
    qdesn_registry: Path,
    qdesn_horizons: Path,
    campaign_health: Path,
    campaign_events: Path,
    ledger: SourceLedger,
) -> dict[str, Any]:
    for relative, expected in PINNED_ARTIFACT_HASHES.items():
        ledger.inspect(root / relative, category="pinned_campaign", label=relative, expected_sha256=expected)
    ledger.inspect(
        qdesn_registry,
        category="pinned_reference",
        label="qdesn_registry",
        expected_sha256=PINNED_QDESN_REGISTRY_SHA256,
    )
    ledger.inspect(
        qdesn_horizons,
        category="pinned_reference",
        label="qdesn_horizon_diagnostics",
        expected_sha256=PINNED_QDESN_HORIZON_SHA256,
    )
    ledger.inspect(
        campaign_health,
        category="pinned_scheduler",
        label="campaign_health",
        expected_sha256=PINNED_CAMPAIGN_HEALTH_SHA256,
    )
    ledger.inspect(
        campaign_events,
        category="pinned_scheduler",
        label="campaign_events",
        expected_sha256=PINNED_CAMPAIGN_EVENTS_SHA256,
    )
    protocol = read_json(root / "provenance" / "protocol.json")
    health = read_json(campaign_health)
    if protocol.get("run_tag") != RUN_TAG or health.get("run_tag") != RUN_TAG:
        raise RuntimeError("Operational run tag mismatch")
    if health.get("status") != "completed" or health.get("stage") != "campaign":
        raise RuntimeError("Campaign health does not record a completed campaign")
    if bool(health.get("registry_mutated")) or bool(health.get("article_mutated")):
        raise RuntimeError("Campaign health records a forbidden mutation")
    event_rows = 0
    event_bad = 0
    final_event: dict[str, Any] = {}
    with campaign_events.open(encoding="utf-8") as handle:
        for line in handle:
            event = json.loads(line)
            event_rows += 1
            final_event = event
            status = str(event.get("status", "")).lower()
            if any(token in status for token in ("fail", "error", "retry")):
                event_bad += 1
    if event_rows != EXPECTED_EVENT_ROWS or event_bad or final_event.get("status") != "completed":
        raise RuntimeError(
            f"Scheduler event audit failed: rows={event_rows}, bad={event_bad}, final={final_event.get('status')}"
        )
    return {
        "pinned_artifacts": len(PINNED_ARTIFACT_HASHES),
        "campaign_event_rows": event_rows,
        "campaign_bad_events": event_bad,
        "campaign_completed": True,
    }


def check_fit_artifacts(root: Path, ledger: SourceLedger) -> list[dict[str, Any]]:
    specs = {
        "phase1": root / "phase1" / "trials",
        "phase2_screen": root / "phase2" / "screen" / "trials",
        "phase2_stability": root / "phase2" / "stability" / "trials",
    }
    summaries = []
    for phase, directory in specs.items():
        statuses = sorted(directory.glob("*/status.json"))
        expected = EXPECTED_FIT_COUNTS[phase]
        if len(statuses) != expected:
            raise RuntimeError(f"Expected {expected} {phase} statuses, observed {len(statuses)}")
        checkpoints = 0
        validation_metrics = 0
        total_bytes = 0
        for status_path in statuses:
            size, _ = ledger.inspect(status_path, category="fit_status", label=f"{phase}:{status_path.parent.name}")
            total_bytes += size
            status = read_json(status_path)
            if status.get("status") != "completed" or bool(status.get("reads_test_split")):
                raise RuntimeError(f"Invalid validation fit status: {status_path}")
            checkpoint = Path(status.get("checkpoint", ""))
            size, _ = ledger.inspect(
                checkpoint,
                category="fit_checkpoint",
                label=f"{phase}:{status_path.parent.name}:checkpoint",
                expected_sha256=str(status.get("checkpoint_sha256", "")),
            )
            total_bytes += size
            checkpoints += 1
            metric_path = Path(status.get("validation_metrics", ""))
            size, _ = ledger.inspect(
                metric_path,
                category="fit_validation_metric",
                label=f"{phase}:{status_path.parent.name}:validation",
                expected_sha256=str(status.get("validation_metrics_sha256", "")),
            )
            total_bytes += size
            validation_metrics += 1
        summaries.append({
            "phase": phase,
            "expected_fits": expected,
            "completed_fits": len(statuses),
            "hash_valid_checkpoints": checkpoints,
            "hash_valid_validation_metrics": validation_metrics,
            "audited_bytes": total_bytes,
            "integrity_pass": True,
        })
    return summaries


def load_and_check_data_manifests(
    root: Path,
    ledger: SourceLedger,
) -> tuple[dict[tuple[int, str, str], dict[str, str]], dict[tuple[int, str], dict[str, str]]]:
    source_rows = read_csv_rows(root / "provenance" / "source_manifest.csv")
    for row in source_rows:
        ledger.inspect(
            row["path"],
            category="campaign_source",
            label=row["label"],
            expected_sha256=row["sha256"],
        )
    windows = read_csv_rows(root / "data" / "window_manifest.csv")
    scalers = read_csv_rows(root / "data" / "scaler_manifest.csv")
    if len(windows) != 342 or len(scalers) != 114:
        raise RuntimeError(f"Data manifest surface mismatch: windows={len(windows)}, scalers={len(scalers)}")
    window_map: dict[tuple[int, str, str], dict[str, str]] = {}
    for row in windows:
        key = (int(row["fold"]), row["region"], row["split"])
        if key in window_map:
            raise RuntimeError(f"Duplicate window manifest key: {key}")
        ledger.inspect(
            row["path"],
            category="data_window",
            label=f"fold={key[0]}:{key[1]}:{key[2]}",
            expected_sha256=row["sha256"],
        )
        window_map[key] = row
    scaler_map: dict[tuple[int, str], dict[str, str]] = {}
    for row in scalers:
        key = (int(row["fold"]), row["region"])
        if key in scaler_map:
            raise RuntimeError(f"Duplicate scaler manifest key: {key}")
        ledger.inspect(
            row["path"],
            category="data_scaler",
            label=f"fold={key[0]}:{key[1]}",
            expected_sha256=row["sha256"],
        )
        scaler_map[key] = row
    return window_map, scaler_map


def prediction_diagnostics(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    *,
    quantiles: Iterable[float] = QUANTILES,
) -> dict[str, Any]:
    quantiles_array = np.asarray(list(quantiles), dtype=np.float64)
    truth = np.asarray(y_true, dtype=np.float64)
    predictions = np.asarray(y_pred, dtype=np.float64)
    if truth.ndim != 2 or predictions.shape != truth.shape + (len(quantiles_array),):
        raise ValueError(f"Prediction shape mismatch: truth={truth.shape}, prediction={predictions.shape}")
    if truth.shape[1] != 96:
        raise ValueError(f"Expected 96 horizons, observed {truth.shape[1]}")
    if not np.isfinite(truth).all() or not np.isfinite(predictions).all():
        raise ValueError("Predictions contain non-finite values")
    losses = pinball_loss(truth, predictions, quantiles_array)
    coverages = (truth[..., None] <= predictions).mean(axis=(0, 1))
    quantile_rows = []
    for index, tau in enumerate(quantiles_array):
        quantile_rows.append({
            "tau": float(tau),
            "AQL": float(losses[..., index].mean()),
            "empirical_cdf_coverage": float(coverages[index]),
            "calibration_error": float(coverages[index] - tau),
            "mean_prediction": float(predictions[..., index].mean()),
        })
    horizon_rows = []
    horizon_quantile_rows = []
    median_index = int(np.argmin(np.abs(quantiles_array - 0.5)))
    for label, start, end in HORIZON_BLOCKS:
        block_truth = truth[:, start:end]
        block_pred = predictions[:, start:end, :]
        block_loss = losses[:, start:end, :]
        horizon_rows.append({
            "horizon_group": label,
            "AQL": float(block_loss.mean()),
            "MAE": float(np.abs(block_truth - block_pred[..., median_index]).mean()),
            "RMSE": float(np.sqrt(np.square(block_truth - block_pred[..., median_index]).mean())),
            "AQCR": float((block_pred[..., :-1] > block_pred[..., 1:]).mean()),
        })
        for index, tau in enumerate(quantiles_array):
            coverage = float((block_truth <= block_pred[..., index]).mean())
            horizon_quantile_rows.append({
                "horizon_group": label,
                "tau": float(tau),
                "AQL": float(block_loss[..., index].mean()),
                "empirical_cdf_coverage": coverage,
                "calibration_error": coverage - float(tau),
            })
    outer_coverage = float(
        ((truth >= predictions[..., 0]) & (truth <= predictions[..., -1])).mean()
    )
    inner_coverage = float(
        ((truth >= predictions[..., 1]) & (truth <= predictions[..., -2])).mean()
    )
    case = scalar_metrics(truth, predictions, quantiles_array)
    case.update({
        "n_origins": int(truth.shape[0]),
        "mean_abs_calibration_error": float(np.abs(coverages - quantiles_array).mean()),
        "max_abs_calibration_error": float(np.abs(coverages - quantiles_array).max()),
        "coverage_q10_q90": outer_coverage,
        "coverage_error_q10_q90": outer_coverage - 0.80,
        "mean_width_q10_q90": float((predictions[..., -1] - predictions[..., 0]).mean()),
        "coverage_q25_q75": inner_coverage,
        "coverage_error_q25_q75": inner_coverage - 0.50,
        "mean_width_q25_q75": float((predictions[..., -2] - predictions[..., 1]).mean()),
        "median_bias": float((predictions[..., median_index] - truth).mean()),
    })
    return {
        "case": case,
        "quantile_rows": quantile_rows,
        "horizon_rows": horizon_rows,
        "horizon_quantile_rows": horizon_quantile_rows,
        "origin_AQL": losses.mean(axis=(1, 2)),
    }


def check_test_tasks(
    root: Path,
    window_map: dict[tuple[int, str, str], dict[str, str]],
    scaler_map: dict[tuple[int, str], dict[str, str]],
    ledger: SourceLedger,
    bootstrap_replicates: int,
    bootstrap_block_origins: int,
    bootstrap_seed: int,
) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    manifest = read_csv_rows(root / "test" / "trial_manifest.csv")
    if len(manifest) != EXPECTED_TEST_TASKS:
        raise RuntimeError(f"Expected {EXPECTED_TEST_TASKS} test tasks, observed {len(manifest)}")
    task_results: dict[str, dict[str, Any]] = {}
    replay_rows = []
    for row in manifest:
        task_id = row["task_id"]
        if task_id in task_results:
            raise RuntimeError(f"Duplicate test task: {task_id}")
        fold = int(row["fold"])
        region = row["region"]
        task_dir = Path(row["task_dir"])
        status_path = task_dir / "status.json"
        ledger.inspect(status_path, category="test_status", label=task_id)
        status = read_json(status_path)
        if status.get("status") != "completed" or status.get("task_id") != task_id:
            raise RuntimeError(f"Incomplete test task: {task_id}")
        metric_path = Path(status.get("metrics", ""))
        prediction_path = Path(status.get("predictions", ""))
        ledger.inspect(
            metric_path,
            category="test_metric",
            label=f"{task_id}:metric",
            expected_sha256=str(status.get("metrics_sha256", "")),
        )
        ledger.inspect(
            prediction_path,
            category="test_prediction",
            label=f"{task_id}:prediction",
            expected_sha256=str(status.get("predictions_sha256", "")),
        )
        metric_rows = read_csv_rows(metric_path)
        if len(metric_rows) != 1:
            raise RuntimeError(f"Expected one metric row for {task_id}")
        metric = metric_rows[0]
        with np.load(prediction_path, allow_pickle=False) as archive:
            required = {"anchors_ns", "y_true", "y_pred"}
            if set(archive.files) != required:
                raise RuntimeError(f"Unexpected prediction payload for {task_id}: {archive.files}")
            anchors = np.asarray(archive["anchors_ns"], dtype=np.int64)
            y_true = np.asarray(archive["y_true"], dtype=np.float64)
            y_pred = np.asarray(archive["y_pred"], dtype=np.float64)
        expected_origins = EXPECTED_ORIGINS[fold]
        if len(anchors) != expected_origins or len(np.unique(anchors)) != expected_origins:
            raise RuntimeError(f"Anchor count mismatch for {task_id}")
        if anchors.size > 1 and not np.all(np.diff(anchors) > 0):
            raise RuntimeError(f"Anchors are not strictly increasing for {task_id}")
        diagnostics = prediction_diagnostics(y_true, y_pred)
        replay = diagnostics["case"]
        metric_errors = {
            name: abs(float(metric[name]) - float(replay[name]))
            for name in ("AQL", "AQCR", "MAE", "RMSE")
        }
        if max(metric_errors.values()) > METRIC_TOLERANCE:
            raise RuntimeError(f"Metric replay mismatch for {task_id}: {metric_errors}")
        window_row = window_map[(fold, region, "test")]
        scaler_row = scaler_map[(fold, region)]
        with np.load(window_row["path"], allow_pickle=False) as window, np.load(
            scaler_row["path"], allow_pickle=False
        ) as scaler:
            expected_anchors = np.asarray(window["anchors_ns"], dtype=np.int64)
            center = float(np.asarray(scaler["y_center"]).reshape(-1)[0])
            scale = float(np.asarray(scaler["y_scale"]).reshape(-1)[0])
            expected_y = np.asarray(window["Y"], dtype=np.float64) * scale + center
        anchor_equal = np.array_equal(anchors, expected_anchors)
        y_max_abs_diff = float(np.max(np.abs(y_true - expected_y)))
        if not anchor_equal or y_max_abs_diff > WINDOW_TOLERANCE:
            raise RuntimeError(
                f"Prediction/window parity failed for {task_id}: anchors={anchor_equal}, y_diff={y_max_abs_diff}"
            )
        samples = circular_block_bootstrap(
            diagnostics["origin_AQL"],
            bootstrap_replicates,
            bootstrap_block_origins,
            stable_seed(bootstrap_seed, task_id),
        )
        ci_low, ci_high = np.quantile(samples, [0.025, 0.975])
        task_results[task_id] = {
            "manifest": row,
            "metric": metric,
            "diagnostics": diagnostics,
            "bootstrap_samples": samples,
            "bootstrap_ci_low": float(ci_low),
            "bootstrap_ci_high": float(ci_high),
            "prediction_path": str(prediction_path),
            "prediction_sha256": str(status["predictions_sha256"]),
        }
        replay_rows.append({
            "task_id": task_id,
            "region": region,
            "fold": fold,
            "candidate_id": row["candidate_id"],
            "phase": row["phase"],
            "canonical_degree": row["canonical_degree"],
            "n_origins": expected_origins,
            **{f"replayed_{name}": replay[name] for name in ("AQL", "AQCR", "MAE", "RMSE")},
            "max_metric_abs_error": max(metric_errors.values()),
            "anchors_match_frozen_window": anchor_equal,
            "y_true_max_abs_diff_from_frozen_window": y_max_abs_diff,
            "prediction_sha256": status["predictions_sha256"],
            "bootstrap_ci_low": float(ci_low),
            "bootstrap_ci_high": float(ci_high),
            "replay_pass": True,
        })
    return task_results, replay_rows


def keyed(rows: list[dict[str, str]], label: str) -> dict[tuple[int, str], dict[str, str]]:
    output: dict[tuple[int, str], dict[str, str]] = {}
    for row in rows:
        key = (int(row["fold"]), row["region"])
        if key in output:
            raise RuntimeError(f"Duplicate {label} key: {key}")
        output[key] = row
    if len(output) != EXPECTED_SELECTOR_ROWS:
        raise RuntimeError(f"Expected {EXPECTED_SELECTOR_ROWS} {label} rows, observed {len(output)}")
    return output


def build_selector_outputs(
    root: Path,
    qdesn_registry: Path,
    task_results: dict[str, dict[str, Any]],
    ledger: SourceLedger,
) -> dict[str, list[dict[str, Any]]]:
    primary_metrics = keyed(read_csv_rows(root / "test" / "cell_specific_metrics.csv"), "primary metric")
    global_metrics = keyed(read_csv_rows(root / "test" / "region_global_metrics.csv"), "global metric")
    primary_winners = keyed(read_csv_rows(root / "selection" / "cell_specific_winners.csv"), "primary winner")
    global_winners = keyed(read_csv_rows(root / "selection" / "region_global_winners.csv"), "global winner")
    references = keyed(read_csv_rows(qdesn_registry), "reference")
    closeout = keyed(read_csv_rows(root / "closeout" / "decision_registry.csv"), "closeout")
    expected_keys = set(primary_metrics)
    if not all(set(mapping) == expected_keys for mapping in (global_metrics, primary_winners, global_winners, references, closeout)):
        raise RuntimeError("Selector/reference key surfaces differ")
    robustness_rows = []
    case_rows = []
    quantile_rows = []
    horizon_rows = []
    horizon_quantile_rows = []
    degree_counter: Counter[str] = Counter()
    for key in sorted(expected_keys):
        fold, region = key
        p_metric = primary_metrics[key]
        g_metric = global_metrics[key]
        p_winner = primary_winners[key]
        g_winner = global_winners[key]
        reference = references[key]
        old_closeout = closeout[key]
        for selector, metric, winner in (
            ("cell_specific", p_metric, p_winner),
            ("region_global", g_metric, g_winner),
        ):
            if winner.get("selected_on_split") != "validation" or boolish(winner.get("selection_reads_test")):
                raise RuntimeError(f"Winner selection contract failed for {selector}, {key}")
            ledger.inspect(
                winner["checkpoint"],
                category="selected_checkpoint",
                label=f"{selector}:fold={fold}:{region}",
                expected_sha256=winner["checkpoint_sha256"],
            )
            task = task_results[metric["task_id"]]
            replayed_aql = float(task["diagnostics"]["case"]["AQL"])
            if abs(float(metric["AQL"]) - replayed_aql) > METRIC_TOLERANCE:
                raise RuntimeError(f"Selector metric does not replay for {selector}, {key}")
            q_aql = float(reference["qdesn_AQL"])
            cached_aql = float(reference["pricefm_AQL"])
            aql = float(metric["AQL"])
            samples = task["bootstrap_samples"]
            base = {
                "selector": selector,
                "region": region,
                "fold": fold,
                "candidate_id": metric["candidate_id"],
                "phase": metric["phase"],
                "canonical_degree": metric["canonical_degree"],
                "validation_AQL": float(winner["validation_AQL"]),
                "task_id": metric["task_id"],
                "prediction_sha256": task["prediction_sha256"],
                **task["diagnostics"]["case"],
                "bootstrap_ci_low": task["bootstrap_ci_low"],
                "bootstrap_ci_high": task["bootstrap_ci_high"],
                "current_qdesn_AQL": q_aql,
                "current_qdesn_method_id": reference["qdesn_method_id"],
                "cached_pricefm_AQL": cached_aql,
                "cached_pricefm_method_id": reference["pricefm_method_id"],
                "delta_operational_minus_qdesn": aql - q_aql,
                "delta_operational_minus_cached_pricefm": aql - cached_aql,
                "beats_current_qdesn": aql < q_aql,
                "beats_cached_pricefm": aql < cached_aql,
                "dual_reference_point_gate": aql < q_aql and aql < cached_aql,
                "comparison_outcome": (
                    "operational_below_both"
                    if aql < q_aql and aql < cached_aql
                    else "current_qdesn_lower_only"
                    if aql >= q_aql and aql < cached_aql
                    else "cached_pricefm_lower_only"
                    if aql < q_aql and aql >= cached_aql
                    else "both_references_lower"
                ),
                "conditional_bootstrap_probability_below_qdesn_scalar": float((samples < q_aql).mean()),
                "conditional_bootstrap_probability_below_cached_pricefm_scalar": float((samples < cached_aql).mean()),
                "conditional_upper_ci_below_qdesn_scalar": task["bootstrap_ci_high"] < q_aql,
                "conditional_upper_ci_below_cached_pricefm_scalar": task["bootstrap_ci_high"] < cached_aql,
                "uncertainty_role": "operational_origin_blocks_only_references_treated_as_fixed_scalars",
                "registry_mutation_authorized": False,
                "article_mutation_authorized": False,
            }
            case_rows.append(base)
            for diagnostic in task["diagnostics"]["quantile_rows"]:
                quantile_rows.append({
                    "selector": selector,
                    "region": region,
                    "fold": fold,
                    "candidate_id": metric["candidate_id"],
                    **diagnostic,
                })
            for diagnostic in task["diagnostics"]["horizon_rows"]:
                horizon_rows.append({
                    "selector": selector,
                    "region": region,
                    "fold": fold,
                    "candidate_id": metric["candidate_id"],
                    **diagnostic,
                })
            for diagnostic in task["diagnostics"]["horizon_quantile_rows"]:
                horizon_quantile_rows.append({
                    "selector": selector,
                    "region": region,
                    "fold": fold,
                    "candidate_id": metric["candidate_id"],
                    **diagnostic,
                })
        p_aql = float(p_metric["AQL"])
        g_aql = float(g_metric["AQL"])
        q_aql = float(reference["qdesn_AQL"])
        cached_aql = float(reference["pricefm_AQL"])
        p_dual = p_aql < q_aql and p_aql < cached_aql
        g_dual = g_aql < q_aql and g_aql < cached_aql
        old_dual = boolish(old_closeout["dual_promotion_gate_pass"])
        if old_dual != p_dual:
            raise RuntimeError(f"Legacy closeout gate does not replay for {key}")
        delta = p_aql - g_aql
        relation = "equal"
        if delta < -METRIC_TOLERANCE:
            relation = "primary_better"
        elif delta > METRIC_TOLERANCE:
            relation = "region_global_better"
        evidence_tier = classify_selector_evidence(p_dual, g_dual)
        robustness_rows.append({
            "region": region,
            "fold": fold,
            "primary_candidate_id": p_metric["candidate_id"],
            "primary_degree": p_metric["canonical_degree"],
            "primary_validation_AQL": float(p_winner["validation_AQL"]),
            "primary_test_AQL": p_aql,
            "primary_dual_reference_point_gate": p_dual,
            "region_global_candidate_id": g_metric["candidate_id"],
            "region_global_degree": g_metric["canonical_degree"],
            "region_global_validation_AQL": float(g_winner["validation_AQL"]),
            "region_global_test_AQL": g_aql,
            "region_global_dual_reference_point_gate": g_dual,
            "primary_minus_region_global_test_AQL": delta,
            "selector_test_relation": relation,
            "same_frozen_task": p_metric["task_id"] == g_metric["task_id"],
            "evidence_tier": evidence_tier,
            "controlling_selector": "cell_specific_preregistered",
            "test_driven_selector_switch_allowed": False,
            "whole_surface_included_in_comparator_proposal": True,
        })
        degree_counter[str(p_metric["canonical_degree"])] += 1
    if not all(row["whole_surface_included_in_comparator_proposal"] for row in robustness_rows):
        raise RuntimeError("Operational comparator proposal must include all 114 cells")
    degree_rows = [
        {"canonical_degree": degree, "n_primary_winners": count}
        for degree, count in sorted(degree_counter.items(), key=lambda item: (item[0] == "phase1", item[0]))
    ]
    return {
        "robustness": robustness_rows,
        "cases": case_rows,
        "quantiles": quantile_rows,
        "horizons": horizon_rows,
        "horizon_quantiles": horizon_quantile_rows,
        "degrees": degree_rows,
    }


def comparator_ledgers(
    selector_rows: list[dict[str, Any]],
    case_rows: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    primary = {
        (int(row["fold"]), row["region"]): row
        for row in case_rows
        if row["selector"] == "cell_specific"
    }
    if len(primary) != EXPECTED_SELECTOR_ROWS or len(selector_rows) != EXPECTED_SELECTOR_ROWS:
        raise RuntimeError("Comparator proposal requires the complete 114-cell primary surface")
    proposals = []
    harm_guards = []
    for selector in selector_rows:
        key = (int(selector["fold"]), selector["region"])
        case = primary[key]
        proposal = {
            "surface_id": RUN_TAG,
            "proposed_comparator_method_id": "pricefm_operational_public_architecture_validation_selected",
            "region": case["region"],
            "fold": case["fold"],
            "candidate_id": case["candidate_id"],
            "phase": case["phase"],
            "canonical_degree": case["canonical_degree"],
            "validation_AQL": case["validation_AQL"],
            "test_AQL": case["AQL"],
            "current_qdesn_method_id": case["current_qdesn_method_id"],
            "current_qdesn_AQL": case["current_qdesn_AQL"],
            "cached_pricefm_method_id": case["cached_pricefm_method_id"],
            "cached_pricefm_AQL": case["cached_pricefm_AQL"],
            "comparison_outcome": case["comparison_outcome"],
            "selector_evidence_tier": selector["evidence_tier"],
            "selected_on_split": "validation",
            "test_role": "one_time_audit_after_winner_freeze",
            "whole_surface_included": True,
            "individual_test_win_required_for_inclusion": False,
            "individual_row_promotion_authorized": False,
            "proposal_status": "frozen_candidate_pending_independent_integration_review",
            "paper_table_ii_equivalence_claimed": False,
            "cached_replay_replacement_claimed": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        }
        proposals.append(proposal)
        if not bool(case["beats_current_qdesn"]):
            harm_guards.append({
                "region": case["region"],
                "fold": case["fold"],
                "current_qdesn_method_id": case["current_qdesn_method_id"],
                "current_qdesn_AQL": case["current_qdesn_AQL"],
                "operational_pricefm_candidate_id": case["candidate_id"],
                "operational_pricefm_AQL": case["AQL"],
                "delta_operational_minus_qdesn": case["delta_operational_minus_qdesn"],
                "future_qdesn_harm_guard": "retain_current_qdesn_or_improve",
                "operational_comparator_row_excluded": False,
                "registry_mutation_authorized": False,
                "article_mutation_authorized": False,
            })
    if len(proposals) != 114 or len(harm_guards) != 11:
        raise RuntimeError(
            f"Unexpected comparator/harm-guard surface: proposals={len(proposals)}, harm_guards={len(harm_guards)}"
        )
    return proposals, harm_guards


def source_row_for(
    source_rows: list[dict[str, str]],
    region: str,
    fold: int,
    authority_method: str,
) -> tuple[dict[str, str], int]:
    matches = [
        row for row in source_rows
        if str(row.get("region", "")) == region and int(float(row.get("fold", -1))) == fold
    ]
    if not matches:
        return {}, 0
    method_fields = ("qdesn_method_id", "best_local_method", "primary_median_method", "selected_method_id")
    aligned = [row for row in matches if authority_method in {first_nonblank(row, [field]) for field in method_fields}]
    return (aligned[0] if aligned else matches[0]), len(matches)


def model_directory(source: dict[str, str], repo_root: Path, region: str, fold: int) -> Path | None:
    direct = first_nonblank(source, ("model_dir", "model_dir_median_registry"))
    if direct:
        return resolve_path(direct, repo_root)
    run_dir = first_nonblank(source, ("run_dir", "run_dir_median_registry"))
    if not run_dir:
        return None
    return resolve_path(run_dir, repo_root) / "cells" / f"region={region}" / f"fold={fold}" / "model"


def retained_metric_match(path: Path | None, method: str, expected_aql: float) -> tuple[bool, bool]:
    if path is None or not path.is_file():
        return False, False
    rows = read_csv_rows(path)
    matches = [
        row for row in rows
        if row.get("method_id") == method and row.get("split") == "test" and row.get("unit") == "original"
    ]
    if not matches:
        return True, False
    return True, abs(float(matches[0]["AQL"]) - expected_aql) <= 1.0e-8


def audit_reference_lineage(
    qdesn_registry: Path,
    horizon_diagnostics: Path,
    reference_repo_root: Path,
    ledger: SourceLedger,
) -> list[dict[str, Any]]:
    registry_rows = read_csv_rows(qdesn_registry)
    horizon_rows = read_csv_rows(horizon_diagnostics)
    horizon_groups: dict[tuple[int, str], set[str]] = {}
    for row in horizon_rows:
        horizon_groups.setdefault((int(row["fold"]), row["region"]), set()).add(row["horizon_group"])
    source_cache: dict[Path, list[dict[str, str]]] = {}
    outputs = []
    for row in registry_rows:
        fold = int(row["fold"])
        region = row["region"]
        authority_method = row["qdesn_method_id"]
        authority_aql = float(row["qdesn_AQL"])
        cached_aql = float(row["pricefm_AQL"])
        source_path = resolve_path(row["registry_source_path"], reference_repo_root)
        ledger.inspect(
            source_path,
            category="reference_registry_source",
            label=f"{row['source_class']}:{source_path.name}",
            expected_sha256=row["registry_source_sha256"],
        )
        if source_path not in source_cache:
            source_cache[source_path] = read_csv_rows(source_path)
        source, source_count = source_row_for(source_cache[source_path], region, fold, authority_method)
        source_reported_method = first_nonblank(
            source, ("qdesn_method_id", "best_local_method", "primary_median_method")
        )
        source_selected_method = first_nonblank(
            source, ("selected_method_id", "selected_method_id_median_registry", "primary_median_method")
        )
        source_scalar_text = first_nonblank(source, ("qdesn_AQL", "local_AQL"))
        source_scalar_matches = bool(source_scalar_text) and abs(float(source_scalar_text) - authority_aql) <= 1.0e-8
        model_dir = model_directory(source, reference_repo_root, region, fold)
        metric_path = model_dir / "metric_summary.csv" if model_dir is not None else None
        prediction_path = model_dir / "model_predictions_scaled.csv" if model_dir is not None else None
        metric_exists, q_metric_matches = retained_metric_match(metric_path, authority_method, authority_aql)
        _, cached_metric_matches = retained_metric_match(metric_path, "pricefm_phase1_pretraining", cached_aql)
        if metric_path is not None and metric_path.is_file():
            ledger.inspect(
                metric_path,
                category="reference_retained_metric",
                label=f"fold={fold}:{region}:metric",
            )
        prediction_exists = bool(prediction_path is not None and prediction_path.is_file())
        if prediction_exists and prediction_path is not None:
            ledger.inspect(
                prediction_path,
                category="reference_retained_prediction",
                label=f"fold={fold}:{region}:prediction",
            )
        groups = horizon_groups.get((fold, region), set())
        outputs.append({
            "region": region,
            "fold": fold,
            "source_class": row["source_class"],
            "authority_qdesn_method_id": authority_method,
            "authority_qdesn_AQL": authority_aql,
            "cached_pricefm_AQL": cached_aql,
            "source_registry_path": str(source_path),
            "source_matching_rows": source_count,
            "source_reported_method_id": source_reported_method,
            "source_validation_selected_method_id": source_selected_method,
            "authority_matches_source_reported_method": authority_method == source_reported_method,
            "authority_matches_source_validation_selected_method": authority_method == source_selected_method,
            "source_scalar_matches_authority": source_scalar_matches,
            "retained_model_dir": str(model_dir) if model_dir is not None else "",
            "retained_metric_summary_exists": metric_exists,
            "retained_metric_matches_authority_qdesn_scalar": q_metric_matches,
            "retained_metric_matches_cached_pricefm_scalar": cached_metric_matches,
            "retained_prediction_file_exists": prediction_exists,
            "qdesn_prediction_level_reference_ready": prediction_exists and q_metric_matches,
            "cached_pricefm_prediction_level_reference_ready": prediction_exists and cached_metric_matches,
            "retained_horizon_delta_groups": len(groups),
            "horizon_delta_evidence_available": groups == {label for label, _, _ in HORIZON_BLOCKS},
            "operational_paired_prediction_comparison_ready": (
                prediction_exists and q_metric_matches and cached_metric_matches
            ),
            "comparison_evidence_level": (
                "scalar_plus_qdesn_minus_cached_horizon_deltas" if groups else "scalar_only"
            ),
            "reference_limitation": (
                "reported_method_differs_from_source_validation_selected_method"
                if authority_method != source_selected_method
                else "matched_scalar_without_retained_prediction_surface"
            ),
        })
    return sorted(outputs, key=lambda item: (item["fold"], item["region"]))


def aggregate_rows(case_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    outputs = []
    for selector in ("cell_specific", "region_global"):
        selected = [row for row in case_rows if row["selector"] == selector]
        for fold in (1, 2, 3, "all"):
            rows = selected if fold == "all" else [row for row in selected if row["fold"] == fold]
            outputs.append({
                "selector": selector,
                "scope": "all" if fold == "all" else f"fold_{fold}",
                "n_rows": len(rows),
                "mean_operational_AQL": float(np.mean([row["AQL"] for row in rows])),
                "mean_current_qdesn_AQL": float(np.mean([row["current_qdesn_AQL"] for row in rows])),
                "mean_cached_pricefm_AQL": float(np.mean([row["cached_pricefm_AQL"] for row in rows])),
                "mean_AQCR": float(np.mean([row["AQCR"] for row in rows])),
                "mean_abs_calibration_error": float(np.mean([row["mean_abs_calibration_error"] for row in rows])),
                "mean_max_abs_calibration_error": float(np.mean([row["max_abs_calibration_error"] for row in rows])),
                "n_beats_current_qdesn": sum(bool(row["beats_current_qdesn"]) for row in rows),
                "n_beats_cached_pricefm": sum(bool(row["beats_cached_pricefm"]) for row in rows),
                "n_dual_reference_point_gate": sum(bool(row["dual_reference_point_gate"]) for row in rows),
                "n_conditional_upper_ci_below_both_fixed_scalars": sum(
                    bool(row["conditional_upper_ci_below_qdesn_scalar"])
                    and bool(row["conditional_upper_ci_below_cached_pricefm_scalar"])
                    for row in rows
                ),
            })
    return outputs


def build_r56_rows(
    stage_r55_dir: Path | None,
    stage_r56_dir: Path | None,
    primary_cases: list[dict[str, Any]],
    ledger: SourceLedger,
) -> list[dict[str, Any]]:
    if stage_r55_dir is None or stage_r56_dir is None:
        return [{
            "target": "EE/fold=1",
            "decision": "not_audited_missing_optional_inputs",
            "r56_launch_authorized_now": False,
            "existing_r56_artifacts_mutated": False,
        }]
    r55_path = stage_r55_dir / "pricefm_stage_r55_case_triage.csv"
    r56_summary_path = stage_r56_dir / "summary.json"
    r56_manifest_path = stage_r56_dir / "pricefm_stage_r56_launch_manifest.csv"
    r56_gates_path = stage_r56_dir / "pricefm_stage_r56_prelaunch_gates.csv"
    for label, path in (
        ("r55_case_triage", r55_path),
        ("r56_summary", r56_summary_path),
        ("r56_manifest", r56_manifest_path),
        ("r56_prelaunch_gates", r56_gates_path),
    ):
        ledger.inspect(path, category="r56_prior_state", label=label)
    old_rows = read_csv_rows(r55_path)
    old = next(row for row in old_rows if row["region"] == "EE" and int(row["fold"]) == 1)
    current = next(row for row in primary_cases if row["region"] == "EE" and int(row["fold"]) == 1)
    prior_summary = read_json(r56_summary_path)
    result = r56_disposition(
        float(old["m0_test_AQL"]),
        float(current["AQL"]),
        bool(prior_summary.get("launch_authorized")),
    )
    return [{
        "target": "EE/fold=1",
        "prior_r55_case_id": old["case_id"],
        "prior_authoritative_qdesn_AQL": float(old["authority_qdesn_AQL"]),
        "prior_cached_pricefm_AQL": float(old["cached_pricefm_AQL"]),
        "operational_candidate_id": current["candidate_id"],
        **result,
        "reason": "R55 candidate no longer beats the completed operational PriceFM comparator",
        "recommended_action": "do_not_launch_r56; redesign only if a new validation-selected candidate beats the operational comparator",
    }]


def gate_rows(
    fit_rows: list[dict[str, Any]],
    replay_rows: list[dict[str, Any]],
    selector_rows: list[dict[str, Any]],
    reference_rows: list[dict[str, Any]],
    r56_rows: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    primary_dual = sum(row["primary_dual_reference_point_gate"] for row in selector_rows)
    both_dual = sum(
        row["primary_dual_reference_point_gate"] and row["region_global_dual_reference_point_gate"]
        for row in selector_rows
    )
    selected_alignment = sum(row["authority_matches_source_validation_selected_method"] for row in reference_rows)
    q_prediction_ready = sum(row["qdesn_prediction_level_reference_ready"] for row in reference_rows)
    cached_prediction_ready = sum(row["cached_pricefm_prediction_level_reference_ready"] for row in reference_rows)
    hard = [
        ("pinned_campaign_contract", True, "all pinned hashes match", "operational_surface_freeze"),
        ("all_validation_fits_complete", sum(row["completed_fits"] for row in fit_rows) == 1104, "1104/1104", "operational_surface_freeze"),
        ("all_test_tasks_replayed", len(replay_rows) == EXPECTED_TEST_TASKS and all(row["replay_pass"] for row in replay_rows), f"{len(replay_rows)}/136", "operational_surface_freeze"),
        ("frozen_window_parity", all(row["anchors_match_frozen_window"] and row["y_true_max_abs_diff_from_frozen_window"] <= WINDOW_TOLERANCE for row in replay_rows), "all anchors exact; y tolerance 1e-4", "operational_surface_freeze"),
        ("validation_only_primary_selection", True, "114/114", "operational_surface_freeze"),
        ("whole_surface_no_test_filter", len(selector_rows) == 114 and all(row["whole_surface_included_in_comparator_proposal"] for row in selector_rows), "114/114 included", "operational_surface_freeze"),
        ("registry_article_remain_blocked", True, "blocked", "operational_surface_freeze"),
    ]
    rows = [
        {
            "gate": gate,
            "scope": scope,
            "required": True,
            "passed": passed,
            "observed": observed,
            "consequence": "block operational surface freeze" if not passed else "none",
        }
        for gate, passed, observed, scope in hard
    ]
    rows.extend([
        {
            "gate": "both_selector_dual_reference_robustness",
            "scope": "descriptive_row_evidence",
            "required": False,
            "passed": both_dual == primary_dual,
            "observed": f"{both_dual} both-selector vs {primary_dual} primary dual rows",
            "consequence": "selector-sensitive rows require separate labeling",
        },
        {
            "gate": "reference_method_matches_validation_selected_method",
            "scope": "paired_superiority_claim",
            "required": True,
            "passed": selected_alignment == 114,
            "observed": f"{selected_alignment}/114",
            "consequence": "block symmetric validation-selected superiority language",
        },
        {
            "gate": "qdesn_prediction_surface_retained",
            "scope": "paired_superiority_claim",
            "required": True,
            "passed": q_prediction_ready == 114,
            "observed": f"{q_prediction_ready}/114",
            "consequence": "block paired horizon/quantile uncertainty claims",
        },
        {
            "gate": "cached_pricefm_prediction_surface_retained",
            "scope": "paired_superiority_claim",
            "required": True,
            "passed": cached_prediction_ready == 114,
            "observed": f"{cached_prediction_ready}/114",
            "consequence": "block paired horizon/quantile uncertainty claims",
        },
        {
            "gate": "r56_still_beats_operational_pricefm",
            "scope": "r56_launch",
            "required": True,
            "passed": bool(r56_rows[0].get("m0_beats_operational_pricefm", False)),
            "observed": r56_rows[0].get("decision", ""),
            "consequence": "R56 must not launch",
        },
    ])
    return rows


def markdown_table(headers: list[str], rows: list[list[Any]]) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join(["---"] * len(headers)) + " |",
    ]
    for row in rows:
        values = []
        for value in row:
            if isinstance(value, float):
                values.append(f"{value:.6f}")
            else:
                values.append(str(value))
        lines.append("| " + " | ".join(values) + " |")
    return "\n".join(lines)


def make_report(
    summary: dict[str, Any],
    aggregates: list[dict[str, Any]],
    selector_rows: list[dict[str, Any]],
    reference_rows: list[dict[str, Any]],
    r56_rows: list[dict[str, Any]],
) -> str:
    primary = next(row for row in aggregates if row["selector"] == "cell_specific" and row["scope"] == "all")
    tier_counts = Counter(row["evidence_tier"] for row in selector_rows)
    horizon_coverage = sum(row["horizon_delta_evidence_available"] for row in reference_rows)
    method_alignment = sum(row["authority_matches_source_validation_selected_method"] for row in reference_rows)
    return f"""# Operational PriceFM post-closeout promotion and robustness audit

## Decision

The completed operational replay is internally reproducible and is ready to be
frozen for independent review as one separate 114-cell comparator. It must not
be assembled from only the 99 cells where its preregistered primary selector
beats both scalar references; doing so would select the comparator on test.
No registry or article mutation is authorized by this audit.

## Primary result

{markdown_table(
    ["Quantity", "Value"],
    [
        ["Cells", primary['n_rows']],
        ["Mean operational PriceFM AQL", primary['mean_operational_AQL']],
        ["Mean current Q-DESN AQL", primary['mean_current_qdesn_AQL']],
        ["Mean cached PriceFM AQL", primary['mean_cached_pricefm_AQL']],
        ["Operational below current Q-DESN", f"{primary['n_beats_current_qdesn']} / 114"],
        ["Operational below cached PriceFM", f"{primary['n_beats_cached_pricefm']} / 114"],
        ["Primary pointwise dual-reference rows", f"{primary['n_dual_reference_point_gate']} / 114"],
        ["Conditional upper CI below both fixed scalars", f"{primary['n_conditional_upper_ci_below_both_fixed_scalars']} / 114"],
    ],
)}

The origin-block intervals quantify uncertainty in the operational replay only.
They treat the two historical references as fixed scalar thresholds and are not
paired model-difference intervals.

## Selector robustness

{markdown_table(
    ["Evidence class", "Rows"],
    [[name, tier_counts.get(name, 0)] for name in [
        "tier_a_both_selectors_dual_reference",
        "tier_b_preregistered_primary_only",
        "sensitivity_only_not_promotable",
        "no_dual_reference_evidence",
    ]],
)}

The cell-specific selector remains controlling because it was preregistered.
The region-global result is sensitivity evidence only; the five global-only
dual-reference rows cannot be substituted after seeing test results.

## Reference limitation

The current Q-DESN/cached PriceFM ledger is preserved exactly, but only
{horizon_coverage}/114 rows retain four horizon-delta summaries and 0/114 rows
retain an exact prediction surface whose scalar metric matches the authority
used here. The authority method agrees with the method named as validation
selected in its immediate source ledger for {method_alignment}/114 rows. This
does not invalidate the declared scalar ledger, but it blocks symmetric paired
horizon, quantile, calibration, and uncertainty claims until a frozen reference
prediction surface is reconstructed.

## Stage-R56

The old EE/fold-1 R55 candidate has AQL
{r56_rows[0].get('prior_m0_test_AQL', float('nan')):.6f}; the completed
operational PriceFM value is
{r56_rows[0].get('operational_pricefm_test_AQL', float('nan')):.6f}.
Stage-R56 is therefore superseded and must not launch. Existing R56 files were
not changed.

## Exact next action

1. Freeze this full operational surface as a candidate named operational
   PriceFM public-architecture replay; keep it distinct from the paper's Table
   II result and from the cached released-checkpoint replay.
2. Obtain independent integration review of protocol terminology and the
   all-or-none comparator rule.
3. Before paired superiority language, reconstruct a validation-selected
   Q-DESN reference prediction manifest on the same anchors and preserve all
   seven quantiles.
4. Rebase future Q-DESN calibration targets against operational PriceFM while
   preserving the 11 cells where current Q-DESN is lower as harm guards.
5. Do not launch R56, mutate the registry, update the article, or clean the 4.8
   GiB campaign until the integration decision is made.
"""


def write_outputs(
    output_dir: Path,
    *,
    fit_rows: list[dict[str, Any]],
    replay_rows: list[dict[str, Any]],
    selector_outputs: dict[str, list[dict[str, Any]]],
    reference_rows: list[dict[str, Any]],
    aggregate: list[dict[str, Any]],
    gates: list[dict[str, Any]],
    r56_rows: list[dict[str, Any]],
    source_rows: list[dict[str, Any]],
    contract: dict[str, Any],
    bootstrap_replicates: int,
    bootstrap_block_origins: int,
    bootstrap_seed: int,
) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    comparator_proposal, harm_guards = comparator_ledgers(
        selector_outputs["robustness"], selector_outputs["cases"]
    )
    payloads = {
        "pricefm_operational_fit_integrity.csv": fit_rows,
        "pricefm_operational_test_replay.csv": replay_rows,
        "pricefm_operational_case_diagnostics.csv": selector_outputs["cases"],
        "pricefm_operational_quantile_diagnostics.csv": selector_outputs["quantiles"],
        "pricefm_operational_horizon_diagnostics.csv": selector_outputs["horizons"],
        "pricefm_operational_horizon_quantile_diagnostics.csv": selector_outputs["horizon_quantiles"],
        "pricefm_operational_selector_robustness.csv": selector_outputs["robustness"],
        "pricefm_operational_graph_degree_summary.csv": selector_outputs["degrees"],
        "pricefm_operational_comparator_proposal.csv": comparator_proposal,
        "pricefm_qdesn_harm_guard_ledger.csv": harm_guards,
        "pricefm_operational_reference_lineage.csv": reference_rows,
        "pricefm_operational_aggregate_summary.csv": aggregate,
        "pricefm_operational_gate_ledger.csv": gates,
        "pricefm_stage_r56_disposition.csv": r56_rows,
        "source_manifest.csv": source_rows,
    }
    for filename, rows in payloads.items():
        atomic_write_csv(output_dir / filename, rows)
    preliminary = {
        "status": "completed_read_only_postcloseout_audit",
        "run_tag": RUN_TAG,
        "primary_selector": "cell_specific",
        "sensitivity_selector": "region_global",
        "bootstrap_replicates": bootstrap_replicates,
        "bootstrap_block_origins": bootstrap_block_origins,
        "bootstrap_seed": bootstrap_seed,
        "whole_surface_all_or_none": True,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "launch_authorized": False,
        "fits_models": False,
        **contract,
    }
    report = make_report(preliminary, aggregate, selector_outputs["robustness"], reference_rows, r56_rows)
    atomic_write_text(output_dir / "report.md", report)
    output_files = sorted(list(payloads) + ["report.md"])
    output_manifest = [
        {
            "filename": filename,
            "size_bytes": (output_dir / filename).stat().st_size,
            "sha256": sha256_file(output_dir / filename),
        }
        for filename in output_files
    ]
    atomic_write_csv(output_dir / "output_manifest.csv", output_manifest)
    primary = next(row for row in aggregate if row["selector"] == "cell_specific" and row["scope"] == "all")
    tier_counts = Counter(row["evidence_tier"] for row in selector_outputs["robustness"])
    hard_gates = [row for row in gates if row["scope"] == "operational_surface_freeze" and row["required"]]
    paired_gates = [row for row in gates if row["scope"] == "paired_superiority_claim" and row["required"]]
    summary = preliminary | {
        "fit_tasks_complete": sum(row["completed_fits"] for row in fit_rows),
        "test_tasks_complete": len(replay_rows),
        "region_fold_rows": 114,
        "mean_operational_pricefm_AQL": primary["mean_operational_AQL"],
        "mean_current_qdesn_AQL": primary["mean_current_qdesn_AQL"],
        "mean_cached_pricefm_AQL": primary["mean_cached_pricefm_AQL"],
        "operational_beats_current_qdesn": primary["n_beats_current_qdesn"],
        "operational_beats_cached_pricefm": primary["n_beats_cached_pricefm"],
        "primary_dual_reference_point_rows": primary["n_dual_reference_point_gate"],
        "both_selector_dual_reference_rows": tier_counts["tier_a_both_selectors_dual_reference"],
        "primary_only_dual_reference_rows": tier_counts["tier_b_preregistered_primary_only"],
        "sensitivity_only_dual_reference_rows": tier_counts["sensitivity_only_not_promotable"],
        "neither_selector_dual_reference_rows": tier_counts["no_dual_reference_evidence"],
        "qdesn_harm_guard_rows": 114 - primary["n_beats_current_qdesn"],
        "reference_rows_with_horizon_deltas": sum(row["horizon_delta_evidence_available"] for row in reference_rows),
        "reference_rows_with_exact_qdesn_predictions": sum(row["qdesn_prediction_level_reference_ready"] for row in reference_rows),
        "reference_rows_with_validation_method_alignment": sum(row["authority_matches_source_validation_selected_method"] for row in reference_rows),
        "operational_surface_freeze_ready_for_independent_review": all(row["passed"] for row in hard_gates),
        "paired_superiority_claim_ready": all(row["passed"] for row in paired_gates),
        "r56_launch_authorized": False,
        "comparator_proposal": "freeze_all_114_as_separate_operational_replay_or_freeze_none",
        "recommended_next_action": "independent comparator integration review, then reconstruct matched validation-selected Q-DESN predictions before paired claims",
        "outputs": {row["filename"]: row["sha256"] for row in output_manifest},
        "output_manifest_sha256": sha256_file(output_dir / "output_manifest.csv"),
    }
    atomic_write_json(output_dir / "summary.json", summary)
    return summary


def run(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.artifact_root).resolve()
    qdesn_registry = Path(args.qdesn_registry).resolve()
    qdesn_horizons = Path(args.qdesn_horizon_diagnostics).resolve()
    reference_repo_root = Path(args.reference_repo_root).resolve()
    campaign_health = Path(args.campaign_health).resolve()
    campaign_events = Path(args.campaign_events).resolve()
    output_dir = Path(args.output_dir).resolve()
    if output_dir.exists() and any(output_dir.iterdir()):
        if not args.force:
            raise FileExistsError(f"Output exists: {output_dir}")
        allowed_root = root.resolve()
        try:
            output_dir.relative_to(allowed_root)
        except ValueError as error:
            raise RuntimeError("Forced replacement is allowed only inside the campaign artifact root") from error
        for path in sorted(output_dir.iterdir()):
            if path.is_dir():
                raise RuntimeError(f"Refusing to replace nested output directory: {path}")
            path.unlink()
    if args.bootstrap_replicates < 100:
        raise ValueError("--bootstrap-replicates must be at least 100")
    ledger = SourceLedger()
    contract = check_pinned_contract(
        root, qdesn_registry, qdesn_horizons, campaign_health, campaign_events, ledger
    )
    code_root = Path(__file__).resolve().parent
    for code_path in [
        Path(__file__).resolve(),
        code_root / "pricefm_operational_fullshot.py",
        *[code_root / f"{number}_{name}.py" for number, name in [
            (190, "prepare_pricefm_operational_fullshot"),
            (191, "run_pricefm_operational_fullshot_trial"),
            (192, "select_pricefm_operational_phase1"),
            (193, "prepare_pricefm_operational_phase2"),
            (194, "select_pricefm_operational_winners"),
            (195, "score_pricefm_operational_test"),
            (196, "closeout_pricefm_operational_fullshot"),
            (197, "launch_pricefm_operational_campaign"),
            (198, "launch_pricefm_operational_elastic_campaign"),
        ]],
        reference_repo_root / "application/scripts/pricefm/105_closeout_pricefm_stage_r3_quantile_promotion.py",
        reference_repo_root / "application/scripts/pricefm/114_closeout_pricefm_full_surface_decision_registry.py",
    ]:
        ledger.inspect(code_path, category="code_provenance", label=code_path.name)
    fit_rows = check_fit_artifacts(root, ledger)
    window_map, scaler_map = load_and_check_data_manifests(root, ledger)
    task_results, replay_rows = check_test_tasks(
        root,
        window_map,
        scaler_map,
        ledger,
        args.bootstrap_replicates,
        args.bootstrap_block_origins,
        args.bootstrap_seed,
    )
    selector_outputs = build_selector_outputs(root, qdesn_registry, task_results, ledger)
    reference_rows = audit_reference_lineage(
        qdesn_registry, qdesn_horizons, reference_repo_root, ledger
    )
    aggregate = aggregate_rows(selector_outputs["cases"])
    stage_r55 = Path(args.stage_r55_dir).resolve() if args.stage_r55_dir else None
    stage_r56 = Path(args.stage_r56_prep_dir).resolve() if args.stage_r56_prep_dir else None
    primary_cases = [row for row in selector_outputs["cases"] if row["selector"] == "cell_specific"]
    r56_rows = build_r56_rows(stage_r55, stage_r56, primary_cases, ledger)
    gates = gate_rows(fit_rows, replay_rows, selector_outputs["robustness"], reference_rows, r56_rows)
    summary = write_outputs(
        output_dir,
        fit_rows=fit_rows,
        replay_rows=replay_rows,
        selector_outputs=selector_outputs,
        reference_rows=reference_rows,
        aggregate=aggregate,
        gates=gates,
        r56_rows=r56_rows,
        source_rows=ledger.rows,
        contract=contract,
        bootstrap_replicates=args.bootstrap_replicates,
        bootstrap_block_origins=args.bootstrap_block_origins,
        bootstrap_seed=args.bootstrap_seed,
    )
    return summary


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
