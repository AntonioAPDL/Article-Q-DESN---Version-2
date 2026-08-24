#!/usr/bin/env python3
"""Fit one validation-only PriceFM Phase-I or Phase-II trial."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import time
import traceback

import numpy as np

from pricefm_operational_fullshot import (
    MODEL_PARAMETER_COUNT,
    QUANTILES,
    atomic_write_csv,
    atomic_write_json,
    inverse_scale_y,
    load_scaler,
    model_metrics,
    pack_phase1,
    pack_target,
    read_csv_rows,
    read_json,
    sha256_file,
    stack_regional_inputs,
    status_is_complete,
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", required=True)
    p.add_argument("--row-index", required=True, type=int, help="Zero-based manifest row")
    p.add_argument("--artifact-root", required=True)
    p.add_argument("--upstream-root", required=True)
    return p


def manifest_row(path: str | Path, row_index: int) -> dict[str, str]:
    rows = read_csv_rows(path)
    if row_index < 0 or row_index >= len(rows):
        raise IndexError(f"Manifest row {row_index} is outside [0, {len(rows)})")
    return rows[row_index]


def configure_tensorflow(seed: int, upstream_root: Path):
    os.environ.setdefault("CUDA_VISIBLE_DEVICES", "-1")
    os.environ.setdefault("TF_DETERMINISTIC_OPS", "1")
    os.environ.setdefault("TF_ENABLE_ONEDNN_OPTS", "0")
    sys.path.insert(0, str(upstream_root))
    import tensorflow as tf
    from PriceFM.model import QuantileLoss, build_graph_gated_quantile_model

    tf.keras.utils.set_random_seed(seed)
    try:
        tf.config.experimental.enable_op_determinism()
    except (AttributeError, RuntimeError):
        pass
    try:
        tf.config.threading.set_intra_op_parallelism_threads(1)
        tf.config.threading.set_inter_op_parallelism_threads(1)
    except RuntimeError:
        pass
    return tf, QuantileLoss, build_graph_gated_quantile_model


def load_upstream_model(tf, checkpoint: Path):
    return tf.keras.models.load_model(checkpoint, compile=False, safe_mode=True)


def original_scale_metrics(
    artifact_root: Path,
    fold: int,
    region: str,
    y_true: np.ndarray,
    y_pred: np.ndarray,
) -> dict[str, float]:
    scaler = load_scaler(artifact_root, fold, region)
    center = float(np.asarray(scaler["y_center"]).reshape(-1)[0])
    scale = float(np.asarray(scaler["y_scale"]).reshape(-1)[0])
    return model_metrics(
        inverse_scale_y(y_true, center, scale),
        inverse_scale_y(y_pred, center, scale),
    )


def run(args: argparse.Namespace) -> dict[str, object]:
    row = manifest_row(args.manifest, args.row_index)
    artifact_root = Path(args.artifact_root).resolve()
    upstream_root = Path(args.upstream_root).resolve()
    trial_dir = Path(row["trial_dir"]).resolve()
    if status_is_complete(trial_dir):
        return read_json(trial_dir / "status.json")

    trial_dir.mkdir(parents=True, exist_ok=True)
    status_path = trial_dir / "status.json"
    started = time.time()
    atomic_write_json(status_path, {
        "status": "running",
        "trial_id": row["trial_id"],
        "manifest": str(Path(args.manifest).resolve()),
        "manifest_row_index": args.row_index,
        "pid": os.getpid(),
        "started_unix": started,
    })

    try:
        protocol = read_json(artifact_root / "provenance" / "protocol.json")
        regions = list(protocol["regions"])
        fold = int(row["fold"])
        phase = row["phase"]
        seed = int(row["seed"])
        tf, QuantileLoss, build_model = configure_tensorflow(seed, upstream_root)

        train_lag, train_lead, train_targets, _ = stack_regional_inputs(
            artifact_root, fold, "train", regions
        )
        val_lag, val_lead, val_targets, val_anchors = stack_regional_inputs(
            artifact_root, fold, "val", regions
        )

        if phase == "phase1":
            x1_train, x2_train, gate_train, y_train = pack_phase1(
                train_lag, train_lead, train_targets, regions
            )
            x1_val, x2_val, gate_val, y_val = pack_phase1(
                val_lag, val_lead, val_targets, regions
            )
        elif phase == "phase2":
            region = row["region"]
            mask = [int(value) for value in json.loads(row["mask_json"])]
            if len(mask) != len(regions) or not mask[regions.index(region)]:
                raise RuntimeError(f"Invalid graph mask for target {region}")
            x1_train, x2_train, gate_train, y_train = pack_target(
                train_lag, train_lead, train_targets, region, mask
            )
            x1_val, x2_val, gate_val, y_val = pack_target(
                val_lag, val_lead, val_targets, region, mask
            )
        else:
            raise ValueError(f"Unsupported phase {phase!r}")

        model = build_model(
            x1_shape=x1_train.shape[2:],
            x2_shape=x2_train.shape[2:],
            y_dim=y_train.shape[1],
            quantiles=QUANTILES,
            emb_dim=168,
            num_experts=4,
        )
        if model.count_params() != MODEL_PARAMETER_COUNT:
            raise RuntimeError(
                f"Public architecture parameter count drift: expected {MODEL_PARAMETER_COUNT}, "
                f"observed {model.count_params()}"
            )
        if phase == "phase2":
            initializer = Path(row["initializer_checkpoint"])
            expected_hash = row["initializer_sha256"]
            if sha256_file(initializer) != expected_hash:
                raise RuntimeError(f"Phase-I initializer hash mismatch: {initializer}")
            phase1_model = load_upstream_model(tf, initializer)
            model.set_weights(phase1_model.get_weights())
            del phase1_model

        model.compile(
            optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
            loss=QuantileLoss(QUANTILES),
        )
        checkpoint = trial_dir / "best_model.keras"
        history_path = trial_dir / "history.csv"
        checkpoint.unlink(missing_ok=True)
        history_path.unlink(missing_ok=True)
        callbacks = [
            tf.keras.callbacks.ModelCheckpoint(
                checkpoint,
                monitor="val_loss",
                mode="min",
                save_best_only=True,
                save_weights_only=False,
                verbose=0,
            ),
            tf.keras.callbacks.CSVLogger(history_path),
            tf.keras.callbacks.TerminateOnNaN(),
        ]
        history = model.fit(
            {"X_lag_all": x1_train, "X_lead_all": x2_train, "graph_gate": gate_train},
            y_train,
            validation_data=(
                {"X_lag_all": x1_val, "X_lead_all": x2_val, "graph_gate": gate_val},
                y_val,
            ),
            epochs=int(row["epochs"]),
            batch_size=int(row["batch_size"]),
            callbacks=callbacks,
            shuffle=True,
            verbose=0,
        )
        if not checkpoint.is_file():
            raise RuntimeError("Training did not materialize a best validation checkpoint")
        best_model = load_upstream_model(tf, checkpoint)
        prediction = best_model.predict(
            {"X_lag_all": x1_val, "X_lead_all": x2_val, "graph_gate": gate_val},
            batch_size=int(row["batch_size"]),
            verbose=0,
        )

        metric_rows = []
        if phase == "phase1":
            n_origins = val_lag.shape[0]
            for region_index, region in enumerate(regions):
                start = region_index * n_origins
                stop = start + n_origins
                metrics = original_scale_metrics(
                    artifact_root,
                    fold,
                    region,
                    y_val[start:stop],
                    prediction[start:stop],
                )
                metric_rows.append({
                    "trial_id": row["trial_id"],
                    "phase": phase,
                    "fold": fold,
                    "region": region,
                    "canonical_degree": "phase1",
                    "replicate": int(row["replicate"]),
                    "seed": seed,
                    "n_origins": n_origins,
                    **metrics,
                })
        else:
            region = row["region"]
            metrics = original_scale_metrics(artifact_root, fold, region, y_val, prediction)
            metric_rows.append({
                "trial_id": row["trial_id"],
                "phase": phase,
                "fold": fold,
                "region": region,
                "canonical_degree": int(row["canonical_degree"]),
                "replicate": int(row["replicate"]),
                "seed": seed,
                "n_origins": len(val_anchors),
                **metrics,
            })
        metrics_path = trial_dir / "validation_metrics.csv"
        atomic_write_csv(metrics_path, metric_rows)
        best_epoch = int(np.argmin(history.history["val_loss"])) + 1
        status = {
            "status": "completed",
            "trial_id": row["trial_id"],
            "phase": phase,
            "fold": fold,
            "region": row["region"],
            "replicate": int(row["replicate"]),
            "seed": seed,
            "best_epoch": best_epoch,
            "best_normalized_validation_loss": float(min(history.history["val_loss"])),
            "checkpoint": str(checkpoint),
            "checkpoint_sha256": sha256_file(checkpoint),
            "validation_metrics": str(metrics_path),
            "validation_metrics_sha256": sha256_file(metrics_path),
            "reads_test_split": False,
            "elapsed_seconds": time.time() - started,
        }
        atomic_write_json(status_path, status)
        tf.keras.backend.clear_session()
        return status
    except BaseException as error:
        atomic_write_json(status_path, {
            "status": "failed",
            "trial_id": row.get("trial_id", ""),
            "error_type": type(error).__name__,
            "error": str(error),
            "traceback": traceback.format_exc(),
            "elapsed_seconds": time.time() - started,
        })
        raise


def main() -> None:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
