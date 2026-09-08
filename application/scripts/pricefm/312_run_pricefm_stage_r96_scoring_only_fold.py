#!/usr/bin/env python3
"""Regenerate one frozen R95 fold design and score test without fitting."""

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
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--task-config", type=Path, required=True)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--force", action="store_true")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


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
        raise RuntimeError(f"Invalid R96 beta artifact: {path}")
    frame = frame.sort_values("feature_index")
    expected = np.arange(1, len(frame) + 1)
    if not np.array_equal(frame.feature_index.to_numpy(int), expected):
        raise RuntimeError(f"Non-contiguous R96 beta indices: {path}")
    beta = frame.beta_mean.to_numpy(float)
    if not np.isfinite(beta).all():
        raise RuntimeError(f"Non-finite R96 beta artifact: {path}")
    return beta


def validation_replay(
    rows: pd.DataFrame,
    prediction: pd.DataFrame,
    calculated: np.ndarray,
    tau: float,
    tolerance: float,
) -> dict[str, Any]:
    required = {"origin_id", "horizon", "pred_scaled", "split", "tau"}
    if not required.issubset(prediction):
        raise RuntimeError("Frozen R95 validation prediction schema is incomplete")
    if set(prediction.split.astype(str)) != {"val"} or not np.allclose(
        prediction.tau.to_numpy(float), tau
    ):
        raise RuntimeError("Frozen R95 validation prediction identity changed")
    expected = rows[["origin_id", "horizon"]].copy()
    expected["calculated"] = calculated
    replay = expected.merge(
        prediction[["origin_id", "horizon", "pred_scaled"]],
        on=["origin_id", "horizon"], how="left", validate="one_to_one",
    )
    if len(replay) != len(rows) or replay.pred_scaled.isna().any():
        raise RuntimeError("R96 validation replay rows do not align")
    delta = np.abs(replay.calculated.to_numpy(float) - replay.pred_scaled.to_numpy(float))
    maximum = float(delta.max(initial=0.0))
    return {
        "tau": tau, "rows": len(replay),
        "maximum_absolute_difference": maximum,
        "tolerance": tolerance, "passed": maximum <= tolerance,
    }


def load_adapter_module(path: Path):
    if str(path.parent) not in sys.path:
        sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location("pricefm_r96_adapter", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def run(args: argparse.Namespace) -> dict[str, Any]:
    task_path = args.task_config.resolve()
    task = json.loads(task_path.read_text())
    if task.get("stage") != "R96" or task.get("test_access_authorized") is not True:
        raise RuntimeError("R96 scoring-only test authorization is missing")
    if task.get("test_opened") is not False or any(boolish(task.get(name)) for name in BLOCKED):
        raise RuntimeError("R96 task authorizes fitting, reselection, or mutation")
    if Path(task["scorer_script"]).resolve() != Path(__file__).resolve():
        raise RuntimeError("R96 scorer identity mismatch")
    for path_key, hash_key in (
        ("scorer_script", "scorer_script_sha256"),
        ("adapter_script", "adapter_script_sha256"),
        ("config", "config_sha256"),
        ("selected_manifest", "selected_manifest_sha256"),
        ("reference_manifest", "reference_manifest_sha256"),
    ):
        path = Path(task[path_key])
        if not path.is_file() or sha256(path) != task[hash_key]:
            raise RuntimeError(f"Changed R96 frozen input: {path}")

    selected = pd.read_csv(task["selected_manifest"])
    atoms = selected.loc[selected.case_id.eq(task["case_id"])].sort_values("tau")
    if (
        len(atoms) != 7
        or not np.allclose(atoms.tau.to_numpy(float), TAUS)
        or atoms.selected_family.nunique() != 1
        or atoms.selected_family.iloc[0] != "exal"
    ):
        raise RuntimeError("R96 task is not a complete coherent exAL surface")
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
                raise RuntimeError(f"Changed R95 frozen atom input: {path}")

    output = Path(task["output_dir"]).resolve()
    terminal_path = output / "terminal.json"
    if terminal_path.is_file():
        terminal = json.loads(terminal_path.read_text())
        if (
            terminal.get("status") == "completed"
            and terminal.get("task_config_sha256") == sha256(task_path)
            and terminal.get("validation_replay_passed") is True
            and terminal.get("model_fitted") is False
        ):
            return terminal
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)

    adapter_dir = Path(task["adapter_dir"]).resolve()
    if adapter_dir.exists():
        if not args.force and any(adapter_dir.iterdir()):
            raise FileExistsError(adapter_dir)
        shutil.rmtree(adapter_dir)
    adapter = load_adapter_module(Path(task["adapter_script"]))
    adapter.build_adapter(str(Path(task["config"]).resolve()), force=True)
    generated = {
        name: sha256(adapter_dir / name)
        for name in (
            "X_val.csv", "y_val.csv", "rows_val.csv",
            "X_test.csv", "y_test.csv", "rows_test.csv",
            "adapter_manifest.json", "feature_manifest.json",
        )
    }
    if set(atoms.x_val_sha256.astype(str)) != {generated["X_val.csv"]}:
        raise RuntimeError("R96 regenerated validation design differs from frozen R95")
    if set(atoms.rows_val_sha256.astype(str)) != {generated["rows_val.csv"]}:
        raise RuntimeError("R96 regenerated validation rows differ from frozen R95")

    x_val = np.loadtxt(adapter_dir / "X_val.csv", delimiter=",")
    x_test = np.loadtxt(adapter_dir / "X_test.csv", delimiter=",")
    rows_val = pd.read_csv(adapter_dir / "rows_val.csv")
    rows_test = pd.read_csv(adapter_dir / "rows_test.csv")
    if x_val.ndim != 2 or x_test.ndim != 2 or x_val.shape[1] != x_test.shape[1]:
        raise RuntimeError("R96 validation/test design dimensions differ")
    if len(rows_val) != len(x_val) or len(rows_test) != len(x_test):
        raise RuntimeError("R96 design and row counts differ")
    if rows_test.duplicated(["origin_id", "horizon"]).any():
        raise RuntimeError("R96 test truth contains duplicate keys")

    replay_rows: list[dict[str, Any]] = []
    predictions: list[pd.DataFrame] = []
    for atom in atoms.itertuples(index=False):
        tau = float(atom.tau)
        beta = load_beta(Path(atom.beta_path))
        if len(beta) != x_val.shape[1]:
            raise RuntimeError(f"R96 beta/design mismatch at tau={tau}")
        val_prediction = x_val @ beta
        test_prediction = x_test @ beta
        if not np.isfinite(val_prediction).all() or not np.isfinite(test_prediction).all():
            raise RuntimeError(f"R96 generated non-finite predictions at tau={tau}")
        replay_rows.append(validation_replay(
            rows_val, pd.read_csv(atom.validation_prediction_path), val_prediction,
            tau, float(task["replay_tolerance"]),
        ))
        frame = rows_test[["origin_id", "horizon"]].copy()
        frame.insert(0, "split", "test")
        frame["tau"] = tau
        frame["pred_scaled"] = test_prediction
        predictions.append(frame)
    replay = pd.DataFrame(replay_rows).sort_values("tau")
    if not replay.passed.astype(bool).all():
        raise RuntimeError("R96 exact validation replay failed; test scores are inadmissible")
    test_predictions = pd.concat(predictions, ignore_index=True)
    if len(test_predictions) != len(rows_test) * 7:
        raise RuntimeError("R96 test prediction surface is incomplete")

    replay_path = output / "validation_replay.csv"
    prediction_path = output / "test_predictions_scaled.csv"
    replay.to_csv(replay_path, index=False)
    test_predictions.to_csv(prediction_path, index=False)
    retained = {
        "validation_replay.csv": sha256(replay_path),
        "test_predictions_scaled.csv": sha256(prediction_path),
        "rows_test.csv": generated["rows_test.csv"],
        "rows_val.csv": generated["rows_val.csv"],
        "adapter_manifest.json": generated["adapter_manifest.json"],
        "feature_manifest.json": generated["feature_manifest.json"],
    }
    for name in HEAVY_TEMPORARIES:
        path = adapter_dir / name
        if path.exists():
            path.unlink()
    terminal = {
        "status": "completed", "stage": "R96", "task_id": task["task_id"],
        "case_id": task["case_id"], "region": task["region"], "fold": int(task["fold"]),
        "selected_family": "exal", "selected_atoms": 7,
        "validation_replay_passed": True,
        "validation_replay_max_abs_diff": float(replay.maximum_absolute_difference.max()),
        "test_prediction_rows": len(test_predictions),
        "retained_artifact_sha256": retained,
        "task_config_sha256": sha256(task_path),
        "heavy_temporary_files_removed": list(HEAVY_TEMPORARIES),
        "model_fitted": False, "selection_changed": False,
        "test_loaded": True, "test_opened": True, "test_access_authorized": True,
        "registry_mutated": False, "article_mutated": False,
        "joint_model_fitted": False, "mcmc_fitted": False,
    }
    write_json(terminal_path, terminal)
    return terminal


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
