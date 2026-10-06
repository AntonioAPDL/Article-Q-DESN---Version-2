#!/usr/bin/env python3
"""Build one cross-fitted BG teacher/recursive exposure block for R111B."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
from typing import Any

import numpy as np
import pandas as pd


HERE = Path(__file__).resolve().parent
if str(HERE) not in os.sys.path:
    os.sys.path.insert(0, str(HERE))

from pricefm_common import load_config, sha256_file, write_json  # noqa: E402
from pricefm_desn_adapter import load_window  # noqa: E402
from pricefm_graph import graph_adj_matrix  # noqa: E402
from pricefm_recursive_adapter import build_policy_features  # noqa: E402
from pricefm_recursive_normal import _block, precompute_initial_states  # noqa: E402
from pricefm_recursive_quantile import read_design, recursive_quantile_design  # noqa: E402


def load_script(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


R103_RUNNER = load_script(HERE / "345_run_pricefm_stage_r103_quantile_case.py", "r103_case_runner")


def canonical_hash(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def verify_contract(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text())
    stored = value.pop("task_contract_sha256", None)
    if stored != canonical_hash(value):
        raise RuntimeError("R111B exposure-design contract hash mismatch")
    value["task_contract_sha256"] = stored
    if (
        value.get("stage") != "R111B"
        or value.get("phase") != "crossfit_exposure_design"
        or value.get("region") != "BG"
        or value.get("recursive_reduction") != "pathwise_design_mean"
        or value.get("test_access_authorized") is not False
        or int(value.get("posterior_paths", 0)) != 500
    ):
        raise RuntimeError("R111B exposure-design firewall violation")
    return value


def valid_output(path: Path, contract_hash: str) -> bool:
    terminal_path = path / "terminal.json"
    if not terminal_path.is_file():
        return False
    try:
        value = json.loads(terminal_path.read_text())
        if (
            value.get("status") != "completed_r111b_exposure_design"
            or value.get("task_contract_sha256") != contract_hash
            or value.get("test_opened") is not False
        ):
            return False
        return all(
            (path / row["path"]).is_file()
            and sha256_file(path / row["path"]) == row["sha256"]
            for row in value["artifacts"]
        )
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def training_context(config: dict[str, Any]) -> dict[str, Any]:
    reservoir, meta = R103_RUNNER.load_reservoir(Path(config["statistics_dir"]))
    spec = dict(meta["contract"])
    active = [str(value) for value in meta["feature_policy_manifest"]["active_regions"]]
    if active != ["BG"]:
        raise RuntimeError("R111B is bounded to target-only BG")
    data_config = load_config(config["data_config_path"])
    windows = {
        region: load_window(data_config, int(config["fold"]), region, "train")
        for region in active
    }
    initial = build_policy_features(
        "BG",
        {region: _block(window) for region, window in windows.items()},
        spec["feature_policy"], spec["spatial"], input_regions=list(graph_adj_matrix()),
    )
    context = {
        "region": "BG", "spec": spec, "active_regions": active,
        "input_regions": list(graph_adj_matrix()),
        "initial_lag": np.asarray(initial["X_lag"], dtype=float),
        "lead_features": np.asarray(initial["X_lead"], dtype=float),
        "raw_lead": {region: np.asarray(window["X_lead"], dtype=float) for region, window in windows.items()},
        "lag_columns": {region: list(window["lag_cols"]) for region, window in windows.items()},
        "lead_columns": {region: list(window["lead_cols"]) for region, window in windows.items()},
        "truth": np.asarray(windows["BG"]["Y"], dtype=float),
        "anchors": np.asarray(windows["BG"]["anchors"], dtype=str),
        "reservoir": reservoir, "reservoir_config": meta["reservoir_config"],
    }
    context["initial_states"] = precompute_initial_states(context)
    return context


def driver_paths(path: Path) -> tuple[np.ndarray, pd.DataFrame]:
    terminal = json.loads((path / "terminal.json").read_text())
    if (
        terminal.get("status") != "completed_r111b_crossfit_driver"
        or terminal.get("test_opened") is not False
        or int(terminal.get("n_paths", 0)) != 500
    ):
        raise RuntimeError("invalid R111B crossfit driver")
    for record in terminal["artifacts"]:
        source = path / record["path"]
        if not source.is_file() or sha256_file(source) != record["sha256"]:
            raise RuntimeError(f"changed R111B driver artifact: {source}")
    manifest = json.loads((path / "prediction_paths_manifest.json").read_text())
    rows = pd.read_csv(path / "evaluation_rows.csv")
    n_rows, n_paths = int(manifest["n_rows"]), int(manifest["n_paths"])
    values = np.fromfile(path / "prediction_paths_scaled.bin", dtype="<f8")
    if values.size != n_rows * n_paths or len(rows) != n_rows:
        raise RuntimeError("R111B driver path geometry changed")
    matrix = values.reshape(n_rows, n_paths)
    return matrix, rows


def run(contract_path: Path) -> dict[str, Any]:
    contract = verify_contract(contract_path.resolve())
    output = Path(contract["output_dir"]).resolve()
    if valid_output(output, contract["task_contract_sha256"]):
        return json.loads((output / "terminal.json").read_text())
    config_path = Path(contract["r103_case_config"])
    config = json.loads(config_path.read_text())
    if int(config["fold"]) != int(contract["outer_fold"]) or config["region"] != "BG":
        raise RuntimeError("R111B/R103 case identity mismatch")
    context = training_context(config)
    teacher_x, teacher_y, teacher_meta = read_design(Path(config["design_dir"]))
    n_origins = len(context["anchors"])
    p = int(teacher_meta["p"])
    teacher_by_origin = np.asarray(teacher_x).reshape(96, n_origins, p).transpose(1, 0, 2)
    y_by_origin = np.asarray(teacher_y).reshape(96, n_origins).T
    if not np.allclose(y_by_origin, context["truth"], rtol=0, atol=1e-12):
        raise RuntimeError("R111B teacher design response does not match the training window")

    raw_paths, rows = driver_paths(Path(contract["driver_dir"]))
    ordered = rows.sort_values(["origin_id", "horizon"]).reset_index(drop=True)
    if not ordered.equals(rows.reset_index(drop=True)):
        raise RuntimeError("R111B driver rows are not origin/horizon ordered")
    counts = rows.groupby("origin_id", sort=True).horizon.agg(["count", "min", "max"])
    if not ((counts["count"] == 96) & (counts["min"] == 1) & (counts["max"] == 96)).all():
        raise RuntimeError("R111B driver block does not contain complete horizons")
    origin_ids = counts.index.to_numpy(dtype=int)
    anchors = rows.groupby("origin_id", sort=True).origin_market_time.first().astype(str).to_numpy()
    if not np.array_equal(anchors, context["anchors"][origin_ids]):
        raise RuntimeError("R111B crossfit origins do not align with the training context")
    n_block = len(origin_ids)
    path_cube = raw_paths.reshape(n_block, 96, 500).transpose(2, 0, 1)
    recursive = np.empty((n_block, 96, p), dtype=float)
    for local, global_origin in enumerate(origin_ids):
        design = recursive_quantile_design(
            context, path_cube[:, local, :, None], int(global_origin), ["BG"]
        )
        recursive[local] = design.mean(axis=0)
    teacher = teacher_by_origin[origin_ids]
    truth = y_by_origin[origin_ids]
    if not all(np.isfinite(value).all() for value in (teacher, recursive, truth)):
        raise RuntimeError("R111B exposure design contains nonfinite values")
    if teacher.shape != recursive.shape or teacher.shape[:2] != truth.shape:
        raise RuntimeError("R111B exposure-design dimensions disagree")

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        teacher.reshape(-1, p).astype("<f8").tofile(temporary / "X_teacher.bin")
        recursive.reshape(-1, p).astype("<f8").tofile(temporary / "X_recursive_mean.bin")
        truth.reshape(-1).astype("<f8").tofile(temporary / "y.bin")
        rows.to_csv(temporary / "rows.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        metadata = {
            "stage": "R111B", "status": "completed_r111b_exposure_design_metadata",
            "region": "BG", "outer_fold": int(contract["outer_fold"]),
            "inner_fold": int(contract["inner_fold"]), "n_origins": n_block,
            "n": int(n_block * 96), "p": p, "posterior_paths": 500,
            "storage_order": "row_major", "recursive_reduction": "pathwise_design_mean",
            "training_exposure_only": True, "test_opened": False,
        }
        write_json(temporary / "design.json", metadata)
        artifacts = []
        for path in sorted(temporary.iterdir()):
            artifacts.append({"path": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path)})
        terminal = {
            **metadata,
            "status": "completed_r111b_exposure_design",
            "task_id": contract["task_id"],
            "task_contract_sha256": contract["task_contract_sha256"],
            "r103_case_config": str(config_path.resolve()),
            "r103_case_config_sha256": sha256_file(config_path),
            "driver_terminal_sha256": sha256_file(Path(contract["driver_dir"]) / "terminal.json"),
            "artifacts": artifacts,
            "registry_mutated": False, "article_mutated": False,
        }
        write_json(temporary / "terminal.json", terminal)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(run(args.contract), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
