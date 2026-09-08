#!/usr/bin/env python3
"""Score one frozen R97 region/fold surface on test without fitting or reselection."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
from typing import Any

import joblib
import numpy as np
import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_metrics import inverse_scale_y, metric_dict
from pricefm_region_frozen_contract import PAPER_QUANTILES, atomic_write_json, file_record


BLOCKED = (
    "model_refit_authorized", "selection_change_authorized",
    "registry_mutation_authorized", "article_mutation_authorized",
    "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--task-config", type=Path, required=True)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--force", action="store_true")
    return value


def sha256(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_adapter(path: Path):
    spec = importlib.util.spec_from_file_location("pricefm_r97_scoring_adapter", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def beta(path: Path) -> np.ndarray:
    frame = pd.read_csv(path).sort_values("feature_index")
    expected = np.arange(1, len(frame) + 1)
    if not np.array_equal(frame.feature_index.to_numpy(int), expected):
        raise RuntimeError(f"non-contiguous frozen beta indices: {path}")
    values = frame.beta_mean.to_numpy(float)
    if not np.isfinite(values).all():
        raise RuntimeError(f"non-finite frozen beta: {path}")
    return values


def run(args: argparse.Namespace) -> dict[str, Any]:
    task_path = args.task_config.resolve()
    task = json.loads(task_path.read_text())
    if (
        task.get("stage") != "R97" or task.get("role") != "scoring_only_test"
        or task.get("test_access_authorized") is not True
        or task.get("test_opened") is not False
        or any(task.get(name) is not False for name in BLOCKED)
    ):
        raise RuntimeError("R97 scoring task is not explicitly authorized and mutation-blocked")
    for path_name, hash_name in (
        ("selected_atom_manifest", "selected_atom_manifest_sha256"),
        ("case_config", "case_config_sha256"),
        ("adapter_script", "adapter_script_sha256"),
        ("scorer_script", "scorer_script_sha256"),
    ):
        path = Path(task[path_name])
        if not path.is_file() or sha256(path) != str(task[hash_name]):
            raise RuntimeError(f"R97 frozen scoring source changed: {path}")
    selected = pd.read_csv(task["selected_atom_manifest"])
    atoms = selected[
        (selected.region.astype(str) == str(task["region"]))
        & (selected.fold.astype(int) == int(task["fold"]))
    ].sort_values("tau")
    if len(atoms) != 7 or not np.allclose(atoms.tau.to_numpy(float), PAPER_QUANTILES):
        raise RuntimeError("R97 scoring case is not an exact seven-quantile frozen surface")
    if atoms.selected_family.nunique() != 1 or atoms.selected_family.iloc[0] != task["selected_family"]:
        raise RuntimeError("R97 scoring family differs from the frozen region family")
    for row in atoms.itertuples(index=False):
        for name in ("beta", "prediction", "terminal", "feature_manifest", "x_val", "rows_val", "scaler"):
            path = Path(getattr(row, f"{name}_path"))
            if not path.is_file() or sha256(path) != str(getattr(row, f"{name}_sha256")):
                raise RuntimeError(f"R97 selected atom source changed: {path}")

    output = Path(task["output_dir"]).resolve()
    terminal_path = output / "terminal.json"
    if terminal_path.is_file():
        terminal = json.loads(terminal_path.read_text())
        if terminal.get("status") == "completed" and terminal.get("task_config_sha256") == sha256(task_path):
            return terminal
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    adapter_dir = Path(task["adapter_dir"])
    if adapter_dir.exists():
        if not args.force and any(adapter_dir.iterdir()):
            raise FileExistsError(adapter_dir)
        shutil.rmtree(adapter_dir)
    adapter = load_adapter(Path(task["adapter_script"]))
    adapter.build_adapter(str(Path(task["case_config"])), force=True)
    x_val = np.loadtxt(adapter_dir / "X_val.csv", delimiter=",")
    x_test = np.loadtxt(adapter_dir / "X_test.csv", delimiter=",")
    rows_val = pd.read_csv(adapter_dir / "rows_val.csv")
    rows_test = pd.read_csv(adapter_dir / "rows_test.csv")
    y_test = np.loadtxt(adapter_dir / "y_test.csv", delimiter=",")
    if x_val.ndim != 2 or x_test.ndim != 2 or x_val.shape[1] != x_test.shape[1]:
        raise RuntimeError("R97 regenerated validation/test designs are incompatible")
    if len(rows_test) != len(y_test) or len(rows_test) != len(x_test):
        raise RuntimeError("R97 test rows, truth, and design do not align")

    replay_rows = []
    prediction_frames = []
    test_matrix = []
    for atom in atoms.itertuples(index=False):
        tau = float(atom.tau)
        coefficients = beta(Path(atom.beta_path))
        if len(coefficients) != x_val.shape[1]:
            raise RuntimeError(f"R97 beta/design mismatch at tau={tau}")
        calculated_val = x_val @ coefficients
        frozen_val = pd.read_csv(atom.prediction_path).sort_values(["origin_id", "horizon"])
        ordered_rows = rows_val.sort_values(["origin_id", "horizon"])
        if not np.array_equal(
            frozen_val[["origin_id", "horizon"]].to_numpy(),
            ordered_rows[["origin_id", "horizon"]].to_numpy(),
        ):
            raise RuntimeError("R97 validation replay row identity differs")
        calculated_val = calculated_val[ordered_rows.index.to_numpy()]
        difference = np.abs(calculated_val - frozen_val.pred_scaled.to_numpy(float))
        replay_rows.append({
            "tau": tau, "rows": len(difference),
            "maximum_absolute_difference": float(difference.max(initial=0.0)),
            "passed": bool(difference.max(initial=0.0) <= float(task["replay_tolerance"])),
        })
        prediction = x_test @ coefficients
        test_matrix.append(prediction)
        frame = rows_test[["origin_id", "horizon"]].copy()
        frame.insert(0, "split", "test")
        frame["tau"] = tau
        frame["pred_scaled"] = prediction
        prediction_frames.append(frame)
    replay = pd.DataFrame(replay_rows)
    if not replay.passed.astype(bool).all():
        raise RuntimeError("R97 exact validation replay failed before test scoring")
    scaler = joblib.load(atoms.scaler_path.iloc[0])[str(task["region"])]["y_scaler"]
    truth = inverse_scale_y(np.asarray(y_test, dtype=float), scaler)
    prediction_original = inverse_scale_y(np.column_stack(test_matrix), scaler)
    metrics = metric_dict(truth, prediction_original, PAPER_QUANTILES)
    metric_row = {
        "region": task["region"], "fold": int(task["fold"]),
        "selected_family": task["selected_family"], **metrics,
        "current_authoritative_qdesn_AQL": float(task["current_authoritative_qdesn_AQL"]),
        "cached_pricefm_AQL": float(task["cached_pricefm_AQL"]),
    }
    metric_row["delta_AQL_candidate_minus_current"] = metrics["AQL"] - metric_row["current_authoritative_qdesn_AQL"]
    metric_row["delta_AQL_candidate_minus_pricefm"] = metrics["AQL"] - metric_row["cached_pricefm_AQL"]
    replay_path = output / "validation_replay.csv"
    prediction_path = output / "test_predictions_scaled.csv"
    metrics_path = output / "test_metric.csv"
    replay.to_csv(replay_path, index=False)
    pd.concat(prediction_frames, ignore_index=True).to_csv(prediction_path, index=False)
    pd.DataFrame([metric_row]).to_csv(metrics_path, index=False)
    for name in ("X_train.csv", "y_train.csv", "X_val.csv", "y_val.csv", "X_test.csv", "y_test.csv"):
        path = adapter_dir / name
        if path.exists():
            path.unlink()
    terminal = {
        "status": "completed", "stage": "R97", "role": "scoring_only_test",
        "task_id": task["task_id"], "region": task["region"], "fold": int(task["fold"]),
        "selected_family": task["selected_family"], "AQL": metrics["AQL"],
        "validation_replay_passed": True,
        "validation_replay_max_abs_diff": float(replay.maximum_absolute_difference.max()),
        "artifacts": [
            file_record(replay_path, "validation_replay"),
            file_record(prediction_path, "test_predictions"),
            file_record(metrics_path, "test_metric"),
            file_record(adapter_dir / "rows_test.csv", "test_rows"),
            file_record(adapter_dir / "feature_manifest.json", "feature_manifest"),
        ],
        "task_config_sha256": sha256(task_path),
        "model_fitted": False, "selection_changed": False,
        "test_loaded": True, "test_opened": True, "test_access_authorized": True,
        "registry_mutated": False, "article_mutated": False,
    }
    atomic_write_json(terminal_path, terminal)
    return terminal


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
