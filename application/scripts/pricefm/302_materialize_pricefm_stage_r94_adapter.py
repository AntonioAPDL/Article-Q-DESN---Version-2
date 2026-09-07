#!/usr/bin/env python3
"""Regenerate and hash-freeze the train/validation-only R94 design adapter."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import sys
import tempfile
from typing import Any

import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import pricefm_desn_adapter
from pricefm_region_frozen_contract import (
    atomic_write_json,
    binary_artifacts,
    file_record,
    prepare_empty_directory,
    sha256_file,
    validate_no_test_adapter,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R93_TASK = DATA / (
    "authoritative/pricefm_stage_r93_overnight_validation_ladder_20260906/"
    "outer_normal_closeout/pricefm_stage_r93_quantile_task.json"
)
R94_ADAPTER = DATA / (
    "runs/pricefm_stage_r94_coherent_exal_refit_20260906/"
    "r94_se2_region_frozen/adapter"
)
REQUIRED = (
    "X_train.csv", "y_train.csv", "rows_train.csv",
    "X_val.csv", "y_val.csv", "rows_val.csv",
    "adapter_manifest.json", "feature_manifest.json", "feature_map_matrix.npz",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--r93-task", type=Path, default=R93_TASK)
    value.add_argument("--output-dir", type=Path, default=R94_ADAPTER)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    return value


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open() as handle:
        value = yaml.safe_load(handle)
    if not isinstance(value, dict):
        raise RuntimeError(f"invalid R93 cell configuration: {path}")
    return value


def run(args: argparse.Namespace) -> dict[str, Any]:
    task_path = args.r93_task.resolve()
    task = json.loads(task_path.read_text())
    if task.get("stage") != "R93" or task.get("selection_split") != "val":
        raise RuntimeError("R94 adapter materialization requires the frozen R93 task")
    if task.get("test_access_authorized") is not False:
        raise RuntimeError("R93 task does not preserve the test firewall")
    source_config = Path(task["config"]).resolve()
    if sha256_file(source_config) != str(task["config_sha256"]):
        raise RuntimeError("R93 quantile configuration hash changed")
    source_adapter = Path(task["adapter_dir"]).resolve()
    source_manifest_path = source_adapter / "adapter_manifest.json"
    source_feature_path = source_adapter / "feature_manifest.json"
    for path in (source_manifest_path, source_feature_path):
        if not path.is_file():
            raise FileNotFoundError(path)
    source_manifest = json.loads(source_manifest_path.read_text())
    if set(source_manifest.get("splits", {})) != {"train", "val"}:
        raise RuntimeError("R93 source adapter is not train/validation only")

    output = args.output_dir.resolve()
    quarantine_root = Path(
        args.quarantine_root or (output.parents[2] / "quarantine")
    ).resolve()
    if output.exists() and any(output.iterdir()):
        prepare_empty_directory(
            output, quarantine_root=quarantine_root,
            reason="replaced_r94_adapter", allow_quarantine=args.quarantine_existing,
        )
        output.rmdir()
    elif output.exists():
        output.rmdir()

    config = copy.deepcopy(load_yaml(source_config))
    smoke = config.get("pricefm_desn_smoke")
    if not isinstance(smoke, dict):
        raise RuntimeError("R93 quantile configuration omits pricefm_desn_smoke")
    if list(smoke.get("splits", [])) != ["train", "val"]:
        raise RuntimeError("R94 adapter source configuration includes a forbidden split")
    smoke["adapter"]["output_dir"] = str(output)
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".yaml", prefix="pricefm_r94_adapter_", delete=False
    ) as handle:
        yaml.safe_dump(config, handle, sort_keys=False)
        temporary_config = Path(handle.name)
    try:
        pricefm_desn_adapter.build_adapter(str(temporary_config), force=False)
    finally:
        temporary_config.unlink(missing_ok=True)

    validate_no_test_adapter(output)
    missing = [name for name in REQUIRED if not (output / name).is_file()]
    if missing:
        raise RuntimeError(f"regenerated R94 adapter is incomplete: {missing}")
    regenerated = json.loads((output / "adapter_manifest.json").read_text())
    for split in ("train", "val"):
        for key in ("X_sha256", "y_sha256", "rows_sha256"):
            expected = str(source_manifest["splits"][split][key])
            observed = str(regenerated["splits"][split][key])
            if observed != expected:
                raise RuntimeError(
                    f"R94 regenerated {split} {key} differs from R93: "
                    f"{observed} != {expected}"
                )
    expected_map = str(source_manifest["feature_manifest"]["feature_map_matrix_sha256"])
    observed_map = str(regenerated["feature_manifest"]["feature_map_matrix_sha256"])
    if observed_map != expected_map:
        raise RuntimeError("R94 regenerated reservoir map differs from R93")
    if binary_artifacts(output):
        raise RuntimeError("R94 adapter unexpectedly contains binary R model artifacts")

    regenerated["smoke_config_path"] = str(source_config)
    regenerated["pricefm_stage_r94_materialization"] = {
        "role": "deterministic_regeneration_of_cleaned_R93_design",
        "source_r93_task": str(task_path),
        "source_r93_task_sha256": sha256_file(task_path),
        "source_adapter_manifest": str(source_manifest_path),
        "source_adapter_manifest_sha256": sha256_file(source_manifest_path),
        "test_opened": False,
        "test_access_authorized": False,
    }
    atomic_write_json(output / "adapter_manifest.json", regenerated)
    records = [file_record(output / name, f"r94_adapter_{name}") for name in REQUIRED]
    freeze = {
        "stage": "R94",
        "status": "adapter_materialized_and_hash_matched",
        "region": task["semantic_contract"]["region"],
        "fold": int(task["semantic_contract"]["fold"]),
        "source_r93_task": str(task_path),
        "source_r93_task_sha256": sha256_file(task_path),
        "source_adapter_manifest": str(source_manifest_path),
        "source_adapter_manifest_sha256": sha256_file(source_manifest_path),
        "adapter_dir": str(output),
        "files": records,
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    atomic_write_json(output / "r94_adapter_freeze.json", freeze)
    return freeze


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
