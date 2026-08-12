#!/usr/bin/env python3
"""Freeze data, graph, provenance, and Phase-I plans for the operational PriceFM benchmark."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
from typing import Any

import numpy as np
import pandas as pd
from sklearn.preprocessing import RobustScaler
import yaml

from pricefm_operational_fullshot import (
    BATCH_SIZE,
    MODEL_PARAMETER_COUNT,
    PHASE1_EPOCHS,
    PHASE1_REPLICATES,
    QUANTILES,
    RAW_SHA256,
    UPSTREAM_COMMIT,
    atomic_save_npz,
    atomic_write_csv,
    atomic_write_json,
    deterministic_seed,
    extract_public_adjacency,
    graph_mask_rows,
    parse_bool,
    sha256_file,
    source_manifest_rows,
)


EXPECTED_ORIGINS = {
    (1, "train"): 973,
    (1, "val"): 122,
    (1, "test"): 120,
    (2, "train"): 1095,
    (2, "val"): 120,
    (2, "test"): 123,
    (3, "train"): 1215,
    (3, "val"): 123,
    (3, "test"): 122,
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", required=True)
    p.add_argument("--raw-csv", required=True)
    p.add_argument("--upstream-root", required=True)
    p.add_argument("--artifact-root", required=True)
    p.add_argument("--reference-window-root", default="")
    p.add_argument("--strict-source", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def subset(frame: pd.DataFrame, start: str, end: str) -> pd.DataFrame:
    start_timestamp = pd.Timestamp(start, tz="UTC")
    end_timestamp = pd.Timestamp(end, tz="UTC")
    return frame.loc[(frame.index >= start_timestamp) & (frame.index < end_timestamp)].copy()


def make_windows(
    context: pd.DataFrame,
    target_start: str,
    target_end: str,
    lag_window: int,
    lead_window: int,
) -> dict[str, np.ndarray]:
    start = pd.Timestamp(target_start, tz="UTC")
    end = pd.Timestamp(target_end, tz="UTC")
    anchors = context.index[
        (context.index >= start)
        & (context.index < end)
        & (context.index.hour == 0)
        & (context.index.minute == 0)
    ]
    index = context.index
    x_lag, x_lead, y, retained = [], [], [], []
    for anchor in anchors:
        position = index.get_loc(anchor)
        if isinstance(position, slice):
            raise RuntimeError(f"Duplicate market timestamp: {anchor}")
        lag_start = position - lag_window
        lead_end = position + lead_window
        if lag_start < 0 or lead_end > len(context):
            continue
        lag = context.iloc[lag_start:position][["price", "load", "solar", "wind"]]
        lead = context.iloc[position:lead_end][["load", "solar", "wind"]]
        target = context.iloc[position:lead_end]["price"]
        if len(lag) != lag_window or len(lead) != lead_window or len(target) != lead_window:
            continue
        x_lag.append(lag.to_numpy(dtype=np.float32))
        x_lead.append(lead.to_numpy(dtype=np.float32))
        y.append(target.to_numpy(dtype=np.float32))
        retained.append(anchor.value)
    return {
        "X_lag": np.asarray(x_lag, dtype=np.float32),
        "X_lead": np.asarray(x_lead, dtype=np.float32),
        "Y": np.asarray(y, dtype=np.float32),
        "anchors_ns": np.asarray(retained, dtype=np.int64),
    }


def reference_path(root: Path, fold: int, region: str, split: str) -> Path:
    mode = "contained_half_open" if split == "train" else "operational_half_open"
    return root / f"fold_{fold}" / f"region={region}" / f"{split}_L96_H96_{mode}.npz"


def compare_reference(path: Path, windows: dict[str, np.ndarray]) -> dict[str, Any]:
    if not path.is_file():
        return {"reference_exists": False, "reference_max_abs_diff": ""}
    maxima = []
    with np.load(path, allow_pickle=True) as archive:
        for name in ("X_lag", "X_lead", "Y"):
            if archive[name].shape != windows[name].shape:
                raise RuntimeError(f"Reference shape mismatch for {path}, array {name}")
            maxima.append(float(np.max(np.abs(archive[name] - windows[name]))) if archive[name].size else 0.0)
    return {"reference_exists": True, "reference_max_abs_diff": max(maxima)}


def git_revision(path: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=path, text=True, capture_output=True, check=True
    )
    return result.stdout.strip()


def pip_freeze() -> str:
    result = subprocess.run(
        [sys.executable, "-m", "pip", "freeze"], text=True, capture_output=True, check=True
    )
    return "\n".join(sorted(line for line in result.stdout.splitlines() if line.strip())) + "\n"


def prepare(args: argparse.Namespace) -> dict[str, Any]:
    artifact_root = Path(args.artifact_root).resolve()
    if artifact_root.exists() and any(artifact_root.iterdir()) and not args.force:
        completed = artifact_root / "provenance" / "preparation_summary.json"
        if completed.exists():
            return json.loads(completed.read_text())
        raise FileExistsError(f"Nonempty incomplete artifact root: {artifact_root}")
    artifact_root.mkdir(parents=True, exist_ok=True)

    config_path = Path(args.config).resolve()
    raw_csv = Path(args.raw_csv).resolve()
    upstream_root = Path(args.upstream_root).resolve()
    config = yaml.safe_load(config_path.read_text())
    spec = config["pricefm"]
    regions = [str(region) for region in spec["regions"]]
    folds = [dict(item) for item in spec["splits"]]
    if args.strict_source:
        if sha256_file(raw_csv) != RAW_SHA256:
            raise RuntimeError("Pinned PriceFM raw CSV hash mismatch")
        if git_revision(upstream_root) != UPSTREAM_COMMIT:
            raise RuntimeError("Pinned upstream PriceFM commit mismatch")
        if len(regions) != 38 or len(folds) != 3:
            raise RuntimeError("Strict benchmark requires 38 regions and three folds")

    provenance = artifact_root / "provenance"
    provenance.mkdir(parents=True, exist_ok=True)
    freeze = pip_freeze()
    (provenance / "environment_freeze.txt").write_text(freeze)
    atomic_write_json(provenance / "environment.json", {
        "python": sys.version,
        "executable": sys.executable,
        "freeze_sha256": sha256_file(provenance / "environment_freeze.txt"),
    })

    source_paths = {
        "config": config_path,
        "raw_csv": raw_csv,
        "upstream_data": upstream_root / "PriceFM" / "data.py",
        "upstream_model": upstream_root / "PriceFM" / "model.py",
        "upstream_pipeline": upstream_root / "PriceFM" / "pipeline.py",
        "upstream_tutorial": upstream_root / "FM_Tutorials.ipynb",
    }
    atomic_write_csv(provenance / "source_manifest.csv", source_manifest_rows(source_paths))

    frame = pd.read_csv(raw_csv)
    time_col = spec["time_col"]
    frame[time_col] = pd.to_datetime(frame[time_col], utc=True)
    if frame[time_col].duplicated().any():
        raise RuntimeError("Raw PriceFM timestamps are duplicated")
    frame = frame.sort_values(time_col)
    if args.strict_source:
        if frame.shape != (int(spec["expected_rows"]), int(spec["expected_columns"])):
            raise RuntimeError(f"Unexpected raw shape: {frame.shape}")
        deltas = frame[time_col].diff().dropna()
        if not (deltas == pd.Timedelta(minutes=15)).all():
            raise RuntimeError("Raw PriceFM timestamps are not continuously spaced at 15 minutes")
    frame["market_time"] = frame[time_col] + pd.Timedelta(hours=1)
    frame = frame.set_index("market_time", drop=False)

    window_rows: list[dict[str, Any]] = []
    scaler_rows: list[dict[str, Any]] = []
    reference_root = Path(args.reference_window_root).resolve() if args.reference_window_root else None
    lag_window = int(spec["windows"]["lag_window"])
    lead_window = int(spec["windows"]["lead_window"])

    for fold_spec in folds:
        fold = int(fold_spec["fold"])
        split_frames = {
            split: subset(frame, fold_spec[split][0], fold_spec[split][1])
            for split in ("train", "val", "test")
        }
        for region in regions:
            x_columns = [f"{region}-load", f"{region}-solar", f"{region}-wind"]
            y_column = f"{region}-price"
            missing = [column for column in x_columns + [y_column] if column not in frame.columns]
            if missing:
                raise RuntimeError(f"Missing PriceFM columns for {region}: {missing}")
            x_scaler = RobustScaler().fit(split_frames["train"][x_columns])
            y_scaler = RobustScaler().fit(split_frames["train"][[y_column]])
            scaler_file = artifact_root / "data" / "scalers" / f"fold_{fold}" / f"region={region}.npz"
            atomic_save_npz(
                scaler_file,
                x_center=np.asarray(x_scaler.center_, dtype=np.float64),
                x_scale=np.asarray(x_scaler.scale_, dtype=np.float64),
                y_center=np.asarray(y_scaler.center_, dtype=np.float64),
                y_scale=np.asarray(y_scaler.scale_, dtype=np.float64),
            )
            scaler_rows.append({
                "fold": fold,
                "region": region,
                "path": str(scaler_file),
                "sha256": sha256_file(scaler_file),
                "fit_split": "train",
                "x_columns_json": json.dumps(x_columns),
                "y_column": y_column,
            })

            scaled_frames: dict[str, pd.DataFrame] = {}
            for split, raw_split in split_frames.items():
                scaled = pd.DataFrame(index=raw_split.index)
                scaled[["load", "solar", "wind"]] = x_scaler.transform(raw_split[x_columns])
                scaled[["price"]] = y_scaler.transform(raw_split[[y_column]])
                scaled_frames[split] = scaled[["price", "load", "solar", "wind"]]
            contexts = {
                "train": scaled_frames["train"],
                "val": pd.concat([scaled_frames["train"], scaled_frames["val"]]),
                "test": pd.concat([scaled_frames["train"], scaled_frames["val"], scaled_frames["test"]]),
            }
            for split in ("train", "val", "test"):
                windows = make_windows(
                    contexts[split], fold_spec[split][0], fold_spec[split][1], lag_window, lead_window
                )
                expected = EXPECTED_ORIGINS.get((fold, split))
                if args.strict_source and windows["Y"].shape[0] != expected:
                    raise RuntimeError(
                        f"Origin count mismatch for {region}, fold {fold}, {split}: "
                        f"expected {expected}, got {windows['Y'].shape[0]}"
                    )
                window_file = artifact_root / "data" / "windows" / f"fold_{fold}" / f"region={region}" / f"{split}.npz"
                atomic_save_npz(window_file, **windows)
                comparison = (
                    compare_reference(reference_path(reference_root, fold, region, split), windows)
                    if reference_root else {"reference_exists": False, "reference_max_abs_diff": ""}
                )
                if args.strict_source and comparison["reference_exists"] and comparison["reference_max_abs_diff"] > 1e-6:
                    raise RuntimeError(f"Regenerated window differs from reference: {window_file}")
                window_rows.append({
                    "fold": fold,
                    "region": region,
                    "split": split,
                    "n_origins": windows["Y"].shape[0],
                    "path": str(window_file),
                    "sha256": sha256_file(window_file),
                    "first_anchor_ns": int(windows["anchors_ns"][0]),
                    "last_anchor_ns": int(windows["anchors_ns"][-1]),
                    **comparison,
                })

    atomic_write_csv(artifact_root / "data" / "scaler_manifest.csv", scaler_rows)
    atomic_write_csv(artifact_root / "data" / "window_manifest.csv", window_rows)

    adjacency = extract_public_adjacency(upstream_root)
    mask_rows = graph_mask_rows(adjacency, regions)
    canonical_rows = [row for row in mask_rows if row["is_canonical"]]
    graph_dir = artifact_root / "graph"
    atomic_write_json(graph_dir / "adjacency.json", adjacency)
    atomic_write_csv(graph_dir / "mask_manifest.csv", mask_rows)
    atomic_write_csv(graph_dir / "canonical_masks.csv", canonical_rows)
    expected_canonical = 349 if args.strict_source else len(canonical_rows)
    if len(canonical_rows) != expected_canonical:
        raise RuntimeError(f"Expected {expected_canonical} canonical regional masks, got {len(canonical_rows)}")

    phase1_rows = []
    run_tag = artifact_root.name
    for fold_spec in folds:
        fold = int(fold_spec["fold"])
        for replicate in range(1, PHASE1_REPLICATES + 1):
            trial_id = f"p1_f{fold}_rep{replicate}"
            phase1_rows.append({
                "task_kind": "fit",
                "phase": "phase1",
                "trial_id": trial_id,
                "fold": fold,
                "region": "",
                "canonical_degree": "",
                "mask_hash": "",
                "mask_json": "",
                "replicate": replicate,
                "seed": deterministic_seed(run_tag, "phase1", fold, replicate),
                "epochs": PHASE1_EPOCHS,
                "batch_size": BATCH_SIZE,
                "initializer_checkpoint": "",
                "initializer_sha256": "",
                "trial_dir": str(artifact_root / "phase1" / "trials" / trial_id),
            })
    atomic_write_csv(artifact_root / "phase1" / "trial_manifest.csv", phase1_rows)

    protocol = {
        "stage": "pricefm_operational_public_architecture_fullshot",
        "status": "prepared",
        "run_tag": run_tag,
        "raw_sha256": sha256_file(raw_csv),
        "upstream_commit": git_revision(upstream_root),
        "calendar": "fixed_CET_normalized_market_time_equals_time_utc_plus_1_hour",
        "selection": "validation_only",
        "primary_selector": "cell_specific",
        "sensitivity_selector": "region_global",
        "regions": regions,
        "folds": folds,
        "quantiles": QUANTILES,
        "lag_window": lag_window,
        "lead_window": lead_window,
        "hidden_dim": 168,
        "num_experts": 4,
        "model_parameter_count": MODEL_PARAMETER_COUNT,
        "phase1_replicates": PHASE1_REPLICATES,
        "phase1_epochs": PHASE1_EPOCHS,
        "phase2_epochs": 20,
        "batch_size": BATCH_SIZE,
        "nominal_graph_arms": len(mask_rows) * len(folds),
        "canonical_graph_arms": len(canonical_rows) * len(folds),
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    atomic_write_json(provenance / "protocol.json", protocol)
    summary = {
        "status": "completed",
        "n_regions": len(regions),
        "n_folds": len(folds),
        "n_windows": len(window_rows),
        "n_scalers": len(scaler_rows),
        "n_phase1_trials": len(phase1_rows),
        "n_nominal_phase2_trials": len(mask_rows) * len(folds),
        "n_canonical_phase2_trials": len(canonical_rows) * len(folds),
        "max_reference_abs_diff": max(
            [float(row["reference_max_abs_diff"]) for row in window_rows if row["reference_max_abs_diff"] != ""] or [0.0]
        ),
        "fits_models": False,
        "reads_test_predictions": False,
        "mutates_registry": False,
        "mutates_article": False,
    }
    atomic_write_json(provenance / "preparation_summary.json", summary)
    return summary


def main() -> None:
    result = prepare(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
