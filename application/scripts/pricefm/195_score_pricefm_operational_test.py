#!/usr/bin/env python3
"""Score frozen PriceFM winners on test after validation-only selection."""

from __future__ import annotations

import argparse
from collections import defaultdict
import json
import os
from pathlib import Path
import sys
import time
import traceback

import numpy as np

from pricefm_operational_fullshot import (
    BATCH_SIZE,
    atomic_save_npz,
    atomic_write_csv,
    atomic_write_json,
    inverse_scale_y,
    load_scaler,
    model_metrics,
    pack_target,
    read_csv_rows,
    read_json,
    sha256_file,
    stack_regional_inputs,
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("mode", choices=("prepare", "run-one", "aggregate"))
    p.add_argument("--artifact-root", required=True)
    p.add_argument("--upstream-root", default="")
    p.add_argument("--row-index", type=int, default=-1)
    return p


def verify_winner_freeze(root: Path) -> dict[str, object]:
    freeze = read_json(root / "selection" / "winner_freeze.json")
    if freeze.get("status") != "frozen_before_test" or freeze.get("selection_reads_test") is not False:
        raise RuntimeError("Winner selection was not frozen under the validation-only contract")
    for label in ("cell_specific_winners", "region_global_winners"):
        path = Path(freeze[label])
        if sha256_file(path) != freeze[f"{label}_sha256"]:
            raise RuntimeError(f"Frozen winner hash mismatch: {label}")
    return freeze


def prepare(root: Path) -> dict[str, object]:
    freeze = verify_winner_freeze(root)
    unique: dict[tuple[object, ...], dict[str, object]] = {}
    links = []
    for selector, label in (
        ("cell_specific", "cell_specific_winners"),
        ("region_global", "region_global_winners"),
    ):
        rows = read_csv_rows(freeze[label])
        if len(rows) != 114:
            raise RuntimeError(f"Expected 114 {selector} winners, observed {len(rows)}")
        for row in rows:
            key = (
                int(row["fold"]), row["region"], row["checkpoint_sha256"], row["mask_hash"]
            )
            if key not in unique:
                task_id = f"test_{len(unique):03d}_f{row['fold']}_{row['region']}"
                unique[key] = {
                    "task_id": task_id,
                    "fold": int(row["fold"]),
                    "region": row["region"],
                    "candidate_id": row["candidate_id"],
                    "phase": row["phase"],
                    "canonical_degree": row["canonical_degree"],
                    "checkpoint": row["checkpoint"],
                    "checkpoint_sha256": row["checkpoint_sha256"],
                    "mask_json": row["mask_json"],
                    "mask_hash": row["mask_hash"],
                    "seed": int(row["seed"]),
                    "task_dir": str(root / "test" / "tasks" / task_id),
                }
            links.append({
                "selector": selector,
                "fold": int(row["fold"]),
                "region": row["region"],
                "task_id": unique[key]["task_id"],
            })
    manifest = root / "test" / "trial_manifest.csv"
    link_path = root / "test" / "selector_task_map.csv"
    atomic_write_csv(manifest, list(unique.values()))
    atomic_write_csv(link_path, links)
    summary = {
        "status": "prepared_after_winner_freeze",
        "n_unique_test_tasks": len(unique),
        "n_selector_rows": len(links),
        "manifest": str(manifest),
        "manifest_sha256": sha256_file(manifest),
        "selector_task_map": str(link_path),
        "selector_task_map_sha256": sha256_file(link_path),
    }
    atomic_write_json(root / "test" / "preparation_summary.json", summary)
    return summary


def test_status_complete(task_dir: Path) -> bool:
    status_path = task_dir / "status.json"
    if not status_path.is_file():
        return False
    status = read_json(status_path)
    metrics = Path(status.get("metrics", ""))
    predictions = Path(status.get("predictions", ""))
    return (
        status.get("status") == "completed"
        and metrics.is_file()
        and predictions.is_file()
        and sha256_file(metrics) == status.get("metrics_sha256")
        and sha256_file(predictions) == status.get("predictions_sha256")
    )


def run_one(root: Path, upstream_root: Path, row_index: int) -> dict[str, object]:
    verify_winner_freeze(root)
    preparation = read_json(root / "test" / "preparation_summary.json")
    manifest = Path(preparation["manifest"])
    if sha256_file(manifest) != preparation["manifest_sha256"]:
        raise RuntimeError("Frozen test task manifest hash mismatch")
    rows = read_csv_rows(manifest)
    if row_index < 0 or row_index >= len(rows):
        raise IndexError(row_index)
    row = rows[row_index]
    task_dir = Path(row["task_dir"])
    if test_status_complete(task_dir):
        return read_json(task_dir / "status.json")
    task_dir.mkdir(parents=True, exist_ok=True)
    started = time.time()
    atomic_write_json(task_dir / "status.json", {
        "status": "running", "task_id": row["task_id"], "pid": os.getpid(), "started_unix": started
    })
    try:
        checkpoint = Path(row["checkpoint"])
        if sha256_file(checkpoint) != row["checkpoint_sha256"]:
            raise RuntimeError(f"Selected checkpoint hash mismatch: {checkpoint}")
        os.environ.setdefault("CUDA_VISIBLE_DEVICES", "-1")
        os.environ.setdefault("TF_DETERMINISTIC_OPS", "1")
        sys.path.insert(0, str(upstream_root))
        import tensorflow as tf
        import PriceFM.model  # noqa: F401

        tf.keras.utils.set_random_seed(int(row["seed"]))
        try:
            tf.config.threading.set_intra_op_parallelism_threads(1)
            tf.config.threading.set_inter_op_parallelism_threads(1)
        except RuntimeError:
            pass
        model = tf.keras.models.load_model(checkpoint, compile=False, safe_mode=True)
        protocol = read_json(root / "provenance" / "protocol.json")
        regions = list(protocol["regions"])
        fold = int(row["fold"])
        region = row["region"]
        x_lag, x_lead, targets, anchors = stack_regional_inputs(root, fold, "test", regions)
        mask = [int(value) for value in json.loads(row["mask_json"])]
        x1, x2, gate, y_true_scaled = pack_target(x_lag, x_lead, targets, region, mask)
        prediction_scaled = model.predict(
            {"X_lag_all": x1, "X_lead_all": x2, "graph_gate": gate},
            batch_size=BATCH_SIZE,
            verbose=0,
        )
        scaler = load_scaler(root, fold, region)
        center = float(np.asarray(scaler["y_center"]).reshape(-1)[0])
        scale = float(np.asarray(scaler["y_scale"]).reshape(-1)[0])
        y_true = inverse_scale_y(y_true_scaled, center, scale)
        prediction = inverse_scale_y(prediction_scaled, center, scale)
        metrics = model_metrics(y_true, prediction)
        metric_path = task_dir / "test_metrics.csv"
        prediction_path = task_dir / "predictions.npz"
        atomic_write_csv(metric_path, [{
            "task_id": row["task_id"],
            "fold": fold,
            "region": region,
            "candidate_id": row["candidate_id"],
            "phase": row["phase"],
            "canonical_degree": row["canonical_degree"],
            "n_origins": len(anchors),
            **metrics,
        }])
        atomic_save_npz(
            prediction_path,
            anchors_ns=anchors,
            y_true=np.asarray(y_true, dtype=np.float32),
            y_pred=np.asarray(prediction, dtype=np.float32),
        )
        status = {
            "status": "completed",
            "task_id": row["task_id"],
            "metrics": str(metric_path),
            "metrics_sha256": sha256_file(metric_path),
            "predictions": str(prediction_path),
            "predictions_sha256": sha256_file(prediction_path),
            "elapsed_seconds": time.time() - started,
        }
        atomic_write_json(task_dir / "status.json", status)
        tf.keras.backend.clear_session()
        return status
    except BaseException as error:
        atomic_write_json(task_dir / "status.json", {
            "status": "failed",
            "task_id": row.get("task_id", ""),
            "error_type": type(error).__name__,
            "error": str(error),
            "traceback": traceback.format_exc(),
            "elapsed_seconds": time.time() - started,
        })
        raise


def aggregate(root: Path) -> dict[str, object]:
    verify_winner_freeze(root)
    preparation = read_json(root / "test" / "preparation_summary.json")
    tasks = {row["task_id"]: row for row in read_csv_rows(preparation["manifest"])}
    task_metrics = {}
    for task_id, row in tasks.items():
        task_dir = Path(row["task_dir"])
        if not test_status_complete(task_dir):
            raise RuntimeError(f"Test task is incomplete: {task_id}")
        task_metrics[task_id] = read_csv_rows(task_dir / "test_metrics.csv")[0]
    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    for link in read_csv_rows(preparation["selector_task_map"]):
        task = tasks[link["task_id"]]
        metric = task_metrics[link["task_id"]]
        grouped[link["selector"]].append({
            "selector": link["selector"],
            "fold": int(link["fold"]),
            "region": link["region"],
            "candidate_id": task["candidate_id"],
            "phase": task["phase"],
            "canonical_degree": task["canonical_degree"],
            "AQL": float(metric["AQL"]),
            "AQCR": float(metric["AQCR"]),
            "MAE": float(metric["MAE"]),
            "RMSE": float(metric["RMSE"]),
            "task_id": link["task_id"],
            "predictions": str(Path(task["task_dir"]) / "predictions.npz"),
        })
    outputs = {}
    for selector, rows in grouped.items():
        if len(rows) != 114:
            raise RuntimeError(f"Expected 114 {selector} test rows, observed {len(rows)}")
        path = root / "test" / f"{selector}_metrics.csv"
        atomic_write_csv(path, sorted(rows, key=lambda row: (int(row["fold"]), str(row["region"]))))
        outputs[selector] = {"path": str(path), "sha256": sha256_file(path)}
    summary = {
        "status": "completed",
        "n_unique_test_tasks": len(tasks),
        "selectors": outputs,
        "winner_freeze_sha256": sha256_file(root / "selection" / "winner_freeze.json"),
    }
    atomic_write_json(root / "test" / "aggregation_summary.json", summary)
    return summary


def main() -> None:
    args = parser().parse_args()
    root = Path(args.artifact_root).resolve()
    if args.mode == "prepare":
        result = prepare(root)
    elif args.mode == "run-one":
        if not args.upstream_root:
            raise ValueError("--upstream-root is required for run-one")
        result = run_one(root, Path(args.upstream_root).resolve(), args.row_index)
    else:
        result = aggregate(root)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
