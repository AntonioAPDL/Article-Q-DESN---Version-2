#!/usr/bin/env python3
"""Regenerate one frozen PriceFM design and score it without model fitting."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
from typing import Any

import numpy as np
import pandas as pd


TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
BLOCKED = (
    "model_refit_authorized", "selection_change_authorized",
    "registry_mutation_authorized", "article_mutation_authorized",
    "joint_model_authorized", "mcmc_authorized",
)
HEAVY_TEMPORARIES = ("X_val.csv", "y_val.csv", "X_test.csv", "y_test.csv")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--task-config", type=Path, required=True)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"true", "1", "yes", "y", "on"}


def load_beta(path: Path) -> np.ndarray:
    frame = pd.read_csv(path)
    if "beta_mean" not in frame or "feature_index" not in frame:
        raise RuntimeError(f"Invalid beta artifact: {path}")
    frame = frame.sort_values("feature_index")
    expected = np.arange(1, len(frame) + 1)
    if not np.array_equal(frame.feature_index.to_numpy(int), expected):
        raise RuntimeError(f"Non-contiguous beta feature indices: {path}")
    beta = frame.beta_mean.to_numpy(float)
    if not np.isfinite(beta).all():
        raise RuntimeError(f"Non-finite beta artifact: {path}")
    return beta


def validation_replay(
    rows: pd.DataFrame, prediction: pd.DataFrame, calculated: np.ndarray,
    tau: float, tolerance: float,
) -> dict[str, Any]:
    required = {"origin_id", "horizon", "pred_scaled", "split", "tau"}
    if not required.issubset(prediction):
        raise RuntimeError("Frozen validation prediction schema is incomplete")
    if set(prediction.split.astype(str)) != {"val"} or not np.allclose(
        prediction.tau.to_numpy(float), tau
    ):
        raise RuntimeError("Frozen validation prediction identity changed")
    expected = rows[["origin_id", "horizon"]].copy()
    expected["calculated"] = calculated
    replay = expected.merge(
        prediction[["origin_id", "horizon", "pred_scaled"]],
        on=["origin_id", "horizon"], how="left", validate="one_to_one",
    )
    if len(replay) != len(rows) or replay.pred_scaled.isna().any():
        raise RuntimeError("Frozen validation prediction rows do not align")
    delta = np.abs(replay.calculated.to_numpy(float) - replay.pred_scaled.to_numpy(float))
    maximum = float(delta.max(initial=0.0))
    return {
        "tau": tau, "rows": len(replay), "maximum_absolute_difference": maximum,
        "tolerance": tolerance, "passed": maximum <= tolerance,
    }


def load_adapter_module(path: Path):
    spec = importlib.util.spec_from_file_location("pricefm_r90_adapter", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def run(args: argparse.Namespace) -> dict[str, Any]:
    task_path = args.task_config.resolve()
    task = json.loads(task_path.read_text())
    if task.get("stage") != "R90" or task.get("test_access_authorized") is not True:
        raise RuntimeError("R90 scoring authorization is missing")
    if any(boolish(task.get(name)) for name in BLOCKED):
        raise RuntimeError("R90 task authorizes fitting, reselection, or mutation")
    scorer = Path(task["scorer_script"])
    adapter_script = Path(task["adapter_script"])
    for path_key, hash_key in (
        ("scorer_script", "scorer_script_sha256"),
        ("adapter_script", "adapter_script_sha256"),
        ("config", "config_sha256"),
        ("selected_manifest", "selected_manifest_sha256"),
    ):
        path = Path(task[path_key])
        if not path.is_file() or sha256(path) != task[hash_key]:
            raise RuntimeError(f"Changed R90 input: {path}")
    if scorer.resolve() != Path(__file__).resolve():
        raise RuntimeError("R90 scorer identity mismatch")

    selected = pd.read_csv(task["selected_manifest"])
    atoms = selected[selected.case_id.eq(task["case_id"])].sort_values("tau")
    if len(atoms) != 7 or not np.allclose(atoms.tau.to_numpy(float), TAUS):
        raise RuntimeError("R90 selected case is not a complete seven-quantile surface")
    if atoms.selected_family.nunique() != 1:
        raise RuntimeError("R90 selected case mixes AL and exAL atoms")
    for row in atoms.itertuples(index=False):
        for path_name, hash_name in (
            ("beta_path", "beta_sha256"),
            ("validation_prediction_path", "validation_prediction_sha256"),
            ("terminal_path", "terminal_sha256"),
            ("feature_manifest_path", "feature_manifest_sha256"),
            ("x_val_path", "x_val_sha256"),
            ("rows_val_path", "rows_val_sha256"),
            ("source_case_config", "source_case_config_sha256"),
            ("scaler_path", "scaler_sha256"),
        ):
            path = Path(getattr(row, path_name))
            if not path.is_file() or sha256(path) != str(getattr(row, hash_name)):
                raise RuntimeError(f"Changed frozen R89 input: {path}")

    output = Path(task["output_dir"]).resolve()
    terminal_path = output / "terminal.json"
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True)

    adapter_dir = Path(task["adapter_dir"])
    if adapter_dir.exists():
        shutil.rmtree(adapter_dir)
    adapter = load_adapter_module(adapter_script)
    adapter.build_adapter(str(Path(task["config"]).resolve()), force=True)
    generated_hashes = {
        name: sha256(adapter_dir / name)
        for name in (
            "X_val.csv", "y_val.csv", "rows_val.csv",
            "X_test.csv", "y_test.csv", "rows_test.csv",
            "adapter_manifest.json", "feature_manifest.json",
        )
    }
    expected_x_hashes = set(atoms.x_val_sha256.astype(str))
    expected_row_hashes = set(atoms.rows_val_sha256.astype(str))
    if len(expected_x_hashes) != 1 or generated_hashes["X_val.csv"] not in expected_x_hashes:
        raise RuntimeError("Regenerated validation design does not match frozen R89 design")
    if len(expected_row_hashes) != 1 or generated_hashes["rows_val.csv"] not in expected_row_hashes:
        raise RuntimeError("Regenerated validation rows do not match frozen R89 rows")

    x_val = np.loadtxt(adapter_dir / "X_val.csv", delimiter=",")
    x_test = np.loadtxt(adapter_dir / "X_test.csv", delimiter=",")
    rows_val = pd.read_csv(adapter_dir / "rows_val.csv")
    rows_test = pd.read_csv(adapter_dir / "rows_test.csv")
    if x_val.ndim != 2 or x_test.ndim != 2 or x_val.shape[1] != x_test.shape[1]:
        raise RuntimeError("R90 design dimensions are inconsistent")
    if len(rows_val) != len(x_val) or len(rows_test) != len(x_test):
        raise RuntimeError("R90 row and design counts differ")

    replay_rows: list[dict[str, Any]] = []
    test_predictions: list[pd.DataFrame] = []
    for atom in atoms.itertuples(index=False):
        tau = float(atom.tau)
        beta = load_beta(Path(atom.beta_path))
        if len(beta) != x_val.shape[1]:
            raise RuntimeError(f"Beta/design dimension mismatch at tau={tau}")
        val_calculated = x_val @ beta
        test_calculated = x_test @ beta
        if not np.isfinite(val_calculated).all() or not np.isfinite(test_calculated).all():
            raise RuntimeError(f"Non-finite R90 predictions at tau={tau}")
        replay = validation_replay(
            rows_val, pd.read_csv(atom.validation_prediction_path), val_calculated,
            tau, float(task["replay_tolerance"]),
        )
        replay_rows.append(replay)
        prediction = rows_test[["origin_id", "horizon"]].copy()
        prediction.insert(0, "split", "test")
        prediction["tau"] = tau
        prediction["pred_scaled"] = test_calculated
        test_predictions.append(prediction)
    replay = pd.DataFrame(replay_rows).sort_values("tau")
    if not replay.passed.all():
        raise RuntimeError("Validation prediction replay failed; test scores are inadmissible")
    predictions = pd.concat(test_predictions, ignore_index=True)
    if len(predictions) != len(rows_test) * 7 or not np.isfinite(predictions.pred_scaled).all():
        raise RuntimeError("R90 test prediction surface is incomplete")

    replay_path = output / "validation_replay.csv"
    prediction_path = output / "test_predictions_scaled.csv"
    replay.to_csv(replay_path, index=False)
    predictions.to_csv(prediction_path, index=False)
    retained = {
        "validation_replay.csv": sha256(replay_path),
        "test_predictions_scaled.csv": sha256(prediction_path),
        "rows_test.csv": generated_hashes["rows_test.csv"],
        "adapter_manifest.json": generated_hashes["adapter_manifest.json"],
        "feature_manifest.json": generated_hashes["feature_manifest.json"],
    }
    for name in HEAVY_TEMPORARIES:
        (adapter_dir / name).unlink()
    terminal = {
        "status": "completed", "stage": "R90", "task_id": task["task_id"],
        "case_id": task["case_id"], "region": task["region"], "fold": int(task["fold"]),
        "task_config_sha256": sha256(task_path),
        "config_sha256": task["config_sha256"],
        "selected_manifest_sha256": task["selected_manifest_sha256"],
        "scorer_script_sha256": task["scorer_script_sha256"],
        "adapter_script_sha256": task["adapter_script_sha256"],
        "selected_family": str(atoms.selected_family.iloc[0]),
        "selected_atoms": 7, "validation_rows": len(rows_val), "test_rows": len(rows_test),
        "features": int(x_val.shape[1]), "validation_replay_passed": True,
        "maximum_validation_replay_difference": float(replay.maximum_absolute_difference.max()),
        "generated_adapter_hashes_before_cleanup": generated_hashes,
        "retained_artifact_sha256": retained,
        "heavy_design_matrices_removed_after_scoring": list(HEAVY_TEMPORARIES),
        "model_fitted": False, "selection_changed": False, "test_loaded": True,
        "registry_mutated": False, "article_mutated": False,
        "joint_or_mcmc_run": False,
    }
    write_json(terminal_path, terminal)
    return terminal


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
