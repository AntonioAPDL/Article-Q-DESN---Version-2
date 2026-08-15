import importlib.util
import sys
from pathlib import Path

import pandas as pd
import pytest
import yaml


SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "scripts"
    / "pricefm"
    / "159_prepare_pricefm_stage_r33a_se1_guard_repair.py"
)


def load_module():
    script_dir = str(SCRIPT.parent)
    if script_dir not in sys.path:
        sys.path.insert(0, script_dir)
    spec = importlib.util.spec_from_file_location("stage_r33a", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_yaml(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(payload, sort_keys=False))


def fixture_tree(tmp_path, missing_adapter=False, wrong_error=False):
    source_grid = tmp_path / "source_grid.yaml"
    source_manifest = tmp_path / "source_manifest.csv"
    source_grid_root = tmp_path / "source_grid_root"
    source_run_root = tmp_path / "source_runs"
    output_dir = tmp_path / "output"
    repair_grid = tmp_path / "repair.yaml"
    repair_generated_root = tmp_path / "repair_grid_root"
    experiments = []
    manifest = []
    status = []
    for index in range(3):
        experiment_id = f"r33_se1_f3_arm_{index}"
        experiments.append(
            {
                "id": experiment_id,
                "stage": "stage_r33_lean_capacity_history_screening",
                "priority": 0,
                "regions": ["SE_1"],
                "folds": [3],
                "lag_window": 96,
                "depth": 2,
                "units": [48, 48],
                "feature_dim": 48,
                "seed": 100 + index,
                "selection_is_validation_only": True,
                "mutates_registry": False,
                "mutates_manuscript": False,
                "training": {
                    "horizon_weighting": {
                        "enabled": True,
                        "focus": "25-48",
                        "multiplier": 3.5,
                        "integer_scale": 4,
                        "max_expansion_factor": 6,
                    }
                },
            }
        )
        manifest.append(
            {
                "experiment_id": experiment_id,
                "region": "SE_1",
                "fold": 3,
                "seed": 100 + index,
                "selection_is_validation_only": True,
                "mutates_registry": False,
                "mutates_manuscript": False,
            }
        )
        failed = index == 2
        status.append(
            {
                "id": experiment_id,
                "kind": "experiment",
                "status": "failed" if failed else "completed",
                "return_code": 1 if failed else 0,
            }
        )
        if failed:
            adapter = (
                source_run_root
                / experiment_id
                / "cells"
                / "region=SE_1"
                / "fold=3"
                / "adapter"
            )
            for name in load_module().ADAPTER_REQUIRED:
                if missing_adapter and name == "X_train.csv":
                    continue
                path = adapter / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("nonempty\n")
            model_log = source_run_root / experiment_id / "logs" / "region=SE_1_fold=3.model.log"
            model_log.parent.mkdir(parents=True, exist_ok=True)
            error = "different error" if wrong_error else load_module().DEFAULT_FAILURE_PATTERN
            model_log.write_text(f"Error: {error}\n")
    write_yaml(
        source_grid,
        {
            "pricefm_desn_experiment_grid": {
                "grid_id": "source_r33",
                "purpose": "fixture",
                "base": {
                    "data_config": "data.yaml",
                    "full_config": "full.yaml",
                    "generated_root": str(source_grid_root),
                    "run_root": str(source_run_root),
                },
                "scope": {"regions": ["SE_1"], "folds": [3]},
                "fixed": {},
                "launch": {},
                "experiments": experiments,
                "experiment_blocks": [],
            }
        },
    )
    write_csv(source_manifest, manifest)
    write_csv(source_grid_root / "launch_status.csv", status)
    module = load_module()
    args = module.argparse.Namespace(
        source_grid_config=str(source_grid),
        source_manifest=str(source_manifest),
        source_grid_root=str(source_grid_root),
        source_run_root=str(source_run_root),
        output_dir=str(output_dir),
        repair_grid_config=str(repair_grid),
        repair_grid_id="repair_r33a",
        repair_generated_root=str(repair_generated_root),
        repair_run_root=str(source_run_root),
        expected_source_experiments=3,
        expected_repairs=1,
        repair_region="SE_1",
        repair_fold=3,
        guard_before=6.0,
        guard_after=7.0,
        failure_pattern=module.DEFAULT_FAILURE_PATTERN,
        recommended_experiment_jobs=2,
        launch_authorized=True,
        write_grid=True,
        force=False,
    )
    return module, args


def test_repair_is_single_factor_and_excludes_successes(tmp_path):
    module, args = fixture_tree(tmp_path)
    result = module.prepare(args)

    assert len(result["repair_manifest"]) == 1
    assert result["summary"]["source_successes_excluded"] == 2
    assert result["adapter_audit"]["adapter_ready_for_model"].map(module.boolish).all()
    assert set(result["diff_audit"]["field"]) == {
        "training.horizon_weighting.max_expansion_factor"
    }
    repair = result["repair_payload"][module.GRID_BLOCK]
    assert len(repair["experiments"]) == 1
    assert repair["experiments"][0]["id"] == "r33_se1_f3_arm_2"
    assert repair["experiments"][0]["seed"] == 102
    assert repair["experiments"][0]["training"]["horizon_weighting"]["max_expansion_factor"] == 7.0
    assert repair["base"]["run_root"] == str(Path(args.source_run_root))

    module.materialize(result, args)
    assert Path(args.repair_grid_config).exists()
    assert (Path(args.output_dir) / module.OUT_MANIFEST).exists()
    assert result["gates"]["passed"].map(module.boolish).all()


@pytest.mark.parametrize("missing_adapter,wrong_error", [(True, False), (False, True)])
def test_repair_refuses_unproven_or_nonreusable_failures(tmp_path, missing_adapter, wrong_error):
    module, args = fixture_tree(
        tmp_path,
        missing_adapter=missing_adapter,
        wrong_error=wrong_error,
    )
    with pytest.raises(ValueError, match="repair-prep gates failed"):
        module.prepare(args)
    assert not Path(args.repair_grid_config).exists()
    assert not Path(args.output_dir).exists()
