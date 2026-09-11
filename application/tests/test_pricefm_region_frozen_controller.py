"""Focused tests for the reusable PriceFM region-frozen DAG controller."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


def load():
    path = SCRIPTS / "315_launch_pricefm_region_frozen_allfold.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def fixture(module, tmp_path: Path):
    tmp_path.mkdir(parents=True, exist_ok=True)
    data = tmp_path / "data.yaml"
    runner = tmp_path / "runner.R"
    full = tmp_path / "full.yaml"
    data.write_text("pricefm: {}\n")
    runner.write_text("# fixture\n")
    full.write_text("pricefm_desn_full:\n  python_bin: python3\n")
    region = {
        "target_region": "FI", "real_folds": [1, 2, 3],
        "test_opened": False, "test_access_authorized": False,
    }
    region["contract_sha256"] = module.canonical_sha256(region)
    pipeline = {
        "region": "FI", "test_opened": False, "test_access_authorized": False,
        "frozen_desn": {"depth": 2},
    }
    pipeline["pipeline_contract_sha256"] = module.canonical_sha256(pipeline)
    control = {
        "pipeline_contract_sha256": pipeline["pipeline_contract_sha256"],
        "git_identity": {}, "test_opened": False, "test_access_authorized": False,
        "normal_convergence_recovery": {
            "enabled": True,
            "trigger": module.NORMAL_RECOVERY_TRIGGER,
            "retry_max_iter": 500,
            "tol": 1e-5,
            "preserve_initial_diagnostics": True,
        },
    }
    rows = []
    for index, family in enumerate(("normal_rhs", "al"), start=1):
        task_id = f"fi_task_{index}_0123456789ab"
        task = {
            "stage": "fixture", "task_id": task_id, "region": "FI", "fold": 2,
            "likelihood_family": family, "tau": None if family == "normal_rhs" else 0.5,
            "parent_task_ids": [] if family == "normal_rhs" else [rows[0]["task_id"]],
            "pipeline_contract_sha256": pipeline["pipeline_contract_sha256"],
            "selection_split": "val", "launch_authorized": False,
            "test_opened": False, "test_access_authorized": False,
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
            "joint_model_authorized": False, "mcmc_authorized": False,
            "runner_type": "normal_full" if family == "normal_rhs" else "quantile_atom",
            "runner_script": str(runner), "runner_script_sha256": module.sha256(runner),
            "data_config": str(data), "data_config_sha256": module.sha256(data),
            "output_dir": str(tmp_path / "runs" / task_id),
        }
        if family == "normal_rhs":
            task.update({
                "normal_full_config": str(full),
                "normal_full_config_sha256": module.sha256(full),
            })
        path = tmp_path / "tasks" / f"{task_id}.json"
        write_json(path, task)
        rows.append({
            "task_id": task_id, "region": "FI", "fold": 2,
            "pipeline_contract_sha256": pipeline["pipeline_contract_sha256"],
            "task_config": str(path), "task_config_sha256": module.sha256(path),
            "launch_authorized": False, "test_opened": False,
            "test_access_authorized": False, "registry_mutation_authorized": False,
            "article_mutation_authorized": False, "joint_model_authorized": False,
            "mcmc_authorized": False,
        })
    return region, pipeline, control, pd.DataFrame(rows)


def test_generic_controller_accepts_arbitrary_region_and_dependency_dag(tmp_path):
    module = load()
    region, pipeline, control, manifest = fixture(module, tmp_path)
    tasks = module.validate_launch_contract(region, pipeline, control, manifest)
    assert set(tasks) == {"fi_task_1_0123456789ab", "fi_task_2_0123456789ab"}
    assert tasks["fi_task_2_0123456789ab"]["parent_task_ids"] == ["fi_task_1_0123456789ab"]


def test_generic_controller_rejects_cross_region_and_non_content_addressed_output(tmp_path):
    module = load()
    region, pipeline, control, manifest = fixture(module, tmp_path)
    bad = manifest.copy()
    bad.loc[1, "region"] = "SE_2"
    with pytest.raises(RuntimeError, match="regions"):
        module.validate_launch_contract(region, pipeline, control, bad)

    task_path = Path(manifest.loc[1, "task_config"])
    task = json.loads(task_path.read_text())
    task["output_dir"] = str(tmp_path / "not_the_task_id")
    write_json(task_path, task)
    manifest.loc[1, "task_config_sha256"] = module.sha256(task_path)
    with pytest.raises(RuntimeError, match="content-addressed"):
        module.validate_launch_contract(region, pipeline, control, manifest)


def test_generic_controller_rejects_cycles_and_test_access(tmp_path):
    module = load()
    region, pipeline, control, manifest = fixture(module, tmp_path)
    first_path = Path(manifest.loc[0, "task_config"])
    first = json.loads(first_path.read_text())
    first["parent_task_ids"] = [manifest.loc[1, "task_id"]]
    write_json(first_path, first)
    manifest.loc[0, "task_config_sha256"] = module.sha256(first_path)
    with pytest.raises(RuntimeError, match="cycle"):
        module.validate_launch_contract(region, pipeline, control, manifest)

    region, pipeline, control, manifest = fixture(module, tmp_path / "second")
    manifest.loc[0, "test_access_authorized"] = True
    with pytest.raises(RuntimeError, match="firewall"):
        module.validate_launch_contract(region, pipeline, control, manifest)


def test_generic_controller_has_explicit_token_and_no_region_literal():
    text = (SCRIPTS / "315_launch_pricefm_region_frozen_allfold.py").read_text()
    assert 'APPROVAL_TOKEN = "RUN_PRICEFM_REGION_FROZEN_ALLFOLD_VALIDATION"' in text
    assert '"OMP_NUM_THREADS"' in text
    assert '"taskset", "-c"' in text
    assert "SE_2" not in text


def normal_partial(module, tmp_path: Path, *, converged=False, finite=True):
    cell = tmp_path / "normal/cells/region=FI/fold=2"
    model = cell / "model"
    output = tmp_path / "tasks/normal"
    model.mkdir(parents=True)
    output.mkdir(parents=True)
    (output / "worker.log").write_text("initial normal fit\n")
    write_json(model / "repo_state.json", {"test_opened": False})
    write_json(model / "run_manifest.json", {"splits": ["train", "val"]})
    pd.DataFrame([{
        "method_id": "normal_rhs_ns", "converged": converged, "iter": 100,
    }]).to_csv(model / "model_method_summary.csv", index=False)
    pd.DataFrame([{
        "method_id": "normal_rhs_ns", "beta_l2": 1.0, "beta_max_abs": 0.5,
        "beta_cov_trace": 2.0, "sigma": 0.2, "omega2": 0.04,
    }]).to_csv(model / "model_parameter_summary.csv", index=False)
    pd.DataFrame({"beta_mean": [0.1, 0.2]}).to_csv(model / "normal_beta_mean.csv", index=False)
    pd.DataFrame({"beta_cov_diag": [0.3, 0.4]}).to_csv(model / "normal_beta_cov_diag.csv", index=False)
    pd.DataFrame({"pred_scaled": [0.1, float("nan") if not finite else 0.2]}).to_csv(
        model / "model_predictions_scaled.csv", index=False,
    )
    pd.DataFrame([{
        "sigma": 0.2, "omega2": 0.04, "beta_max_abs_delta": 0.01,
        "parameter_change": 0.01,
    }]).to_csv(model / "model_trace_summary.csv", index=False)
    pd.DataFrame([{"AQL": 1.0}]).to_csv(model / "metric_summary.csv", index=False)
    pd.DataFrame([{"weight": 1.0}]).to_csv(model / "training_weight_summary.csv", index=False)
    pd.DataFrame([{"warm": True}]).to_csv(model / "warm_start_diagnostics.csv", index=False)
    write_yaml = {
        "pricefm_desn_smoke": {
            "normal": {"vb_control": {"max_iter": 100, "min_iter": 50, "tol": 1e-5}},
            "run": {"output_dir": str(model)},
            "adapter": {"output_dir": str(cell / "adapter")},
        }
    }
    import yaml
    (cell / "config.yaml").write_text(yaml.safe_dump(write_yaml, sort_keys=False))
    task = {
        "task_id": "normal", "runner_type": "normal_full", "region": "FI", "fold": 2,
        "normal_model_dir": str(model), "adapter_dir": str(cell / "adapter"),
        "output_dir": str(output),
    }
    policy = {
        "enabled": True, "trigger": module.NORMAL_RECOVERY_TRIGGER,
        "retry_max_iter": 500, "tol": 1e-5, "preserve_initial_diagnostics": True,
    }
    return task, policy


def test_normal_recovery_recognizes_only_finite_iteration_ceiling_and_changes_only_budget(tmp_path):
    module = load()
    task, policy = normal_partial(module, tmp_path)
    diagnostics = module.normal_model_diagnostics(task)
    assert diagnostics["complete"] is True
    assert diagnostics["finite"] is True
    assert diagnostics["converged"] is False
    assert diagnostics["iterations"] == 100
    assert module.normal_partial_is_recognized(task, policy)

    config_path, original = module.write_normal_recovery_config(task, policy)
    import yaml
    recovered = yaml.safe_load(config_path.read_text())["pricefm_desn_smoke"]
    assert original == {"max_iter": 100, "min_iter": 50, "tol": 1e-5}
    assert recovered["normal"]["vb_control"] == {
        "max_iter": 500, "min_iter": 50, "tol": 1e-5,
    }
    records = module.preserve_normal_diagnostics(task)
    assert {Path(record["path"]).name for record in records} >= {
        "model_method_summary.csv", "model_parameter_summary.csv", "model_trace_summary.csv",
    }


def test_normal_recovery_rejects_nonfinite_and_exhausted_partials(tmp_path):
    module = load()
    task, policy = normal_partial(module, tmp_path / "nonfinite", finite=False)
    assert module.normal_model_diagnostics(task)["finite"] is False
    assert not module.normal_partial_is_recognized(task, policy)

    task, policy = normal_partial(module, tmp_path / "exhausted")
    config = module.normal_cell_config(task)
    import yaml
    payload = yaml.safe_load(config.read_text())
    payload["pricefm_desn_smoke"]["normal"]["vb_control"]["max_iter"] = 500
    config.write_text(yaml.safe_dump(payload, sort_keys=False))
    method = Path(task["normal_model_dir"]) / "model_method_summary.csv"
    frame = pd.read_csv(method)
    frame.loc[0, "iter"] = 500
    frame.to_csv(method, index=False)
    assert not module.normal_partial_is_recognized(task, policy)


def test_normal_recovery_policy_is_strict(tmp_path):
    module = load()
    region, pipeline, control, manifest = fixture(module, tmp_path)
    control["normal_convergence_recovery"]["tol"] = 1e-4
    with pytest.raises(RuntimeError, match="tol=1e-5"):
        module.validate_launch_contract(region, pipeline, control, manifest)
