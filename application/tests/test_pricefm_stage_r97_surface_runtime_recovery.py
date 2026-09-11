"""Focused tests for bounded PriceFM R97 surface-runtime recovery."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from pricefm_r97_distributed_contract import sealed_payload  # noqa: E402
from pricefm_region_frozen_contract import (  # noqa: E402
    atomic_write_json,
    canonical_sha256,
    file_record,
    sha256_file,
)


def load():
    path = SCRIPTS / "328_prepare_pricefm_stage_r97_surface_runtime_recovery.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class Identity:
    clean = True
    head = "new-head"
    upstream_head = "new-head"
    branch = "work/pricefm-r97-fixture"

    @staticmethod
    def to_dict():
        return {
            "worktree": "/fixture", "branch": "work/pricefm-r97-fixture",
            "head": "new-head", "upstream": "origin/work/pricefm-r97-fixture",
            "upstream_head": "new-head", "clean": True,
        }


def write_fixture(module, tmp_path: Path) -> tuple[Path, Path, Path]:
    campaign = tmp_path / "campaign"
    grid = campaign / "regions/AT/surface_grid"
    tasks = grid / "tasks"
    tasks.mkdir(parents=True)
    source = tmp_path / "source.txt"
    runner = tmp_path / "runner.R"
    launcher = tmp_path / "launcher.py"
    source.write_text("source\n")
    runner.write_text("# runner\n")
    launcher.write_text("# original launcher\n")
    records = {}
    for name in (
        "selected_normal_contract", "source_data_config", "generated_data_config",
        "normal_full_config", "runtime_manifest",
    ):
        path = tmp_path / f"{name}.txt"
        path.write_text(f"{name}\n")
        records[name] = file_record(path, name)
    pipeline = {
        "schema_version": 1, "stage": "R97", "region": "AT",
        **records, "runner": file_record(runner, "runner"),
        "launcher": file_record(launcher, "launcher"),
        "test_opened": False, "test_access_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False,
    }
    pipeline["pipeline_contract_sha256"] = canonical_sha256(pipeline)
    atomic_write_json(grid / "pipeline_contract.json", pipeline)

    rows = []
    for index in range(45):
        task_id = f"task_{index:02d}"
        task = {
            "task_id": task_id, "runner_type": "quantile_atom",
            "pipeline_contract_sha256": pipeline["pipeline_contract_sha256"],
            "data_config": str(source), "data_config_sha256": sha256_file(source),
            "runner_script": str(runner), "runner_script_sha256": sha256_file(runner),
            "test_opened": False,
        }
        task_path = tasks / f"{task_id}.json"
        atomic_write_json(task_path, task)
        rows.append({
            "task_id": task_id,
            "pipeline_contract_sha256": pipeline["pipeline_contract_sha256"],
            "task_config": str(task_path), "task_config_sha256": sha256_file(task_path),
            "launch_authorized": False, "test_opened": False,
            "test_access_authorized": False, "registry_mutation_authorized": False,
            "article_mutation_authorized": False, "joint_model_authorized": False,
            "mcmc_authorized": False,
        })
    pd.DataFrame(rows).to_csv(grid / "task_manifest.csv", index=False)
    artifact = tmp_path / "window.npz"
    artifact.write_bytes(b"validation-only")
    atomic_write_json(grid / "preprocessing_terminal.json", {
        "status": "completed",
        "pipeline_contract_sha256": pipeline["pipeline_contract_sha256"],
        "artifacts": [file_record(artifact, "train_validation_window")],
        "test_opened": False,
    })
    atomic_write_json(grid / "launch_control.json", {
        "pipeline_contract_sha256": pipeline["pipeline_contract_sha256"],
        "git_identity": {
            "worktree": "/old", "branch": "work/pricefm-r97-fixture",
            "head": "old-head", "upstream": "origin/work/pricefm-r97-fixture",
            "upstream_head": "old-head", "clean": True,
        },
        "launch_authorized": False, "test_opened": False,
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False,
    })

    parent = tmp_path / "parent.json"
    checkpoint = tmp_path / "checkpoint.json"
    assignment = tmp_path / "assignment.csv"
    parent.write_text("{}\n")
    checkpoint.write_text("{}\n")
    assignment.write_text("region,assigned_host\nAT,muscat\n")
    contract = sealed_payload({
        "mode": "freeze", "host": "muscat", "campaign_root": str(campaign),
        "regions": ["AT"], "code_git_identity": {"head": "old-head"},
        "parent_campaign_contract": file_record(parent, "parent"),
        "checkpoint": file_record(checkpoint, "checkpoint"),
        "assignment": file_record(assignment, "assignment"),
        "transition_recovery": {
            "surface_launch_control_rebind_authorized": True,
            "normal_convergence_retry_authorized": True,
            "normal_convergence_retry_max_iter": 500,
            "normal_convergence_tolerance": 1e-5,
        },
        "test_opened": False, "test_access_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False,
    }, "shard_contract_sha256")
    contract_path = tmp_path / "contract.json"
    atomic_write_json(contract_path, contract)
    return campaign, contract_path, grid


def test_surface_recovery_rebinds_only_control_and_preserves_surface_hashes(tmp_path, monkeypatch):
    module = load()
    campaign, contract, grid = write_fixture(module, tmp_path)
    monkeypatch.setattr(module.socket, "gethostname", lambda: "muscat.example")
    monkeypatch.setattr(module, "git_identity", lambda _: Identity())
    monkeypatch.setattr(module, "is_ancestor", lambda *_: True)
    monkeypatch.setattr(module, "lock_available", lambda _: True)
    protected = {
        name: sha256_file(grid / name)
        for name in ("pipeline_contract.json", "task_manifest.csv", "preprocessing_terminal.json")
    }
    task_hashes = {path.name: sha256_file(path) for path in (grid / "tasks").glob("*.json")}
    Path(json.loads((grid / "pipeline_contract.json").read_text())["launcher"]["path"]).write_text(
        "# repaired operational launcher\n"
    )
    result = module.run(SimpleNamespace(
        shard_contract=contract, campaign_root=campaign, code_root=tmp_path,
        host="muscat", output_dir=tmp_path / "output", write=True, force=False,
    ))
    assert result["status"] == "controls_rebound"
    assert result["controls_rebound"] == 1
    assert result["pipeline_or_manifest_mutated"] is False
    assert {name: sha256_file(grid / name) for name in protected} == protected
    assert {path.name: sha256_file(path) for path in (grid / "tasks").glob("*.json")} == task_hashes
    control = json.loads((grid / "launch_control.json").read_text())
    assert control["git_identity"] == Identity.to_dict()
    assert control["normal_convergence_recovery"] == module.RECOVERY_POLICY
    assert control["surface_runtime_recovery"]["DESN_or_tau0_changed"] is False


def test_surface_recovery_rejects_changed_scientific_runner(tmp_path):
    module = load()
    _, _, grid = write_fixture(module, tmp_path)
    pipeline = json.loads((grid / "pipeline_contract.json").read_text())
    Path(pipeline["runner"]["path"]).write_text("# changed scientific runner\n")
    with pytest.raises(RuntimeError, match="hash changed"):
        module.verify_pipeline(grid / "pipeline_contract.json")


def test_surface_recovery_refuses_to_rebind_live_launcher(tmp_path, monkeypatch):
    module = load()
    campaign, contract, grid = write_fixture(module, tmp_path)
    before = sha256_file(grid / "launch_control.json")
    monkeypatch.setattr(module.socket, "gethostname", lambda: "muscat.example")
    monkeypatch.setattr(module, "git_identity", lambda _: Identity())
    monkeypatch.setattr(module, "is_ancestor", lambda *_: True)
    monkeypatch.setattr(module, "lock_available", lambda _: False)
    with pytest.raises(RuntimeError, match="launcher is active"):
        module.run(SimpleNamespace(
            shard_contract=contract, campaign_root=campaign, code_root=tmp_path,
            host="muscat", output_dir=tmp_path / "output", write=True, force=False,
        ))
    assert sha256_file(grid / "launch_control.json") == before
