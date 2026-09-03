import json
from pathlib import Path
import subprocess

import numpy as np
import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
RUNTIME = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/"
    "runtime_libraries/exdqlm_pricefm_r72_spd_repair"
)
RUNTIME_MANIFEST = RUNTIME / "pricefm_stage_r72_spd_repair_manifest.json"


def test_r72_atomic_runner_preflight_and_firewall(tmp_path):
    source_config = tmp_path / "source.yaml"
    source_config.write_text(yaml.safe_dump({
        "pricefm_desn_smoke": {
            "splits": ["train", "val"],
            "qdesn_vb": {"max_iter": 5, "tol": 1e-4},
        }
    }))
    task = {
        "stage": "R72", "task_id": "case_a__tau_0p25__al", "case_id": "case_a",
        "region": "AA", "fold": 1, "tau": 0.25, "likelihood_family": "al",
        "method_id": "qdesn_al_rhs_ns_pricefm_r72_spd_repair",
        "source_case_config": str(source_config), "adapter_dir": str(tmp_path / "adapter"),
        "output_dir": str(tmp_path / "output"), "r_library": str(RUNTIME),
        "runtime_manifest": str(RUNTIME_MANIFEST), "selection_split": "val",
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False, "exal_mechanism_gate_passed": False,
    }
    task_path = tmp_path / "task.json"
    task_path.write_text(json.dumps(task))
    subprocess.run([
        "Rscript", str(ROOT / "application/scripts/pricefm/243_run_pricefm_stage_r72_repair_component.R"),
        "--task-config", str(task_path), "--preflight-only", "true",
    ], cwd=ROOT, check=True)
    terminal = json.loads((tmp_path / "output/terminal.json").read_text())
    assert terminal["status"] == "preflight_passed"
    assert terminal["package"]["version"] == "1.1.1.9001"
    assert terminal["test_loaded"] is False


def test_r72_atomic_runner_blocks_exal_without_mechanism_gate(tmp_path):
    source_config = tmp_path / "source.yaml"
    source_config.write_text(yaml.safe_dump({
        "pricefm_desn_smoke": {"splits": ["train", "val"], "qdesn_vb": {}}
    }))
    output = tmp_path / "output"
    task = {
        "stage": "R72", "task_id": "blocked_exal", "case_id": "case_a",
        "region": "AA", "fold": 1, "tau": 0.25, "likelihood_family": "exal",
        "source_case_config": str(source_config), "adapter_dir": str(tmp_path / "adapter"),
        "output_dir": str(output), "r_library": str(RUNTIME),
        "runtime_manifest": str(RUNTIME_MANIFEST), "selection_split": "val",
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False, "exal_mechanism_gate_passed": False,
    }
    task_path = tmp_path / "task.json"
    task_path.write_text(json.dumps(task))
    result = subprocess.run([
        "Rscript", str(ROOT / "application/scripts/pricefm/243_run_pricefm_stage_r72_repair_component.R"),
        "--task-config", str(task_path), "--preflight-only", "true",
    ], cwd=ROOT, check=False)
    terminal = json.loads((output / "terminal.json").read_text())
    assert result.returncode != 0
    assert terminal["status"] == "failed"
    assert "mechanism gate" in terminal["error_message"]


def test_r72_atomic_runner_writes_complete_al_atom(tmp_path):
    rng = np.random.default_rng(72)
    adapter = tmp_path / "adapter"
    adapter.mkdir()
    x_train = np.column_stack([np.ones(60), rng.normal(size=(60, 3))])
    y_train = x_train @ np.array([0.2, -0.1, 0.3, 0.05]) + rng.normal(scale=0.2, size=60)
    x_val = np.column_stack([np.ones(12), rng.normal(size=(12, 3))])
    np.savetxt(adapter / "X_train.csv", x_train, delimiter=",")
    np.savetxt(adapter / "y_train.csv", y_train, delimiter=",")
    np.savetxt(adapter / "X_val.csv", x_val, delimiter=",")
    pd.DataFrame({"origin_id": range(12), "horizon": [1, 2, 3] * 4}).to_csv(
        adapter / "rows_val.csv", index=False
    )
    source_config = tmp_path / "source.yaml"
    source_config.write_text(yaml.safe_dump({
        "pricefm_desn_smoke": {
            "splits": ["train", "val"],
            "qdesn_vb": {"max_iter": 8, "tol": 1e-4, "n_samp": 5, "n_samp_xi": 10},
        }
    }))
    output = tmp_path / "output"
    task = {
        "stage": "R72", "task_id": "tiny_al", "case_id": "case_a",
        "region": "AA", "fold": 1, "tau": 0.5, "likelihood_family": "al",
        "method_id": "qdesn_al_rhs_ns_pricefm_r72_spd_repair",
        "source_case_config": str(source_config), "adapter_dir": str(adapter),
        "output_dir": str(output), "r_library": str(RUNTIME),
        "runtime_manifest": str(RUNTIME_MANIFEST), "selection_split": "val",
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False, "exal_mechanism_gate_passed": False,
        "max_iter": 8, "tol": 1e-4, "n_samp": 5, "n_samp_xi": 10,
        "rhs_tau0": 0.001, "rhs_init_tau": 1.0,
        "rhs_freeze_tau_iters": 5, "rhs_freeze_tau_warmup_iters": 5,
        "seed": 72,
    }
    task_path = tmp_path / "task.json"
    task_path.write_text(json.dumps(task))
    subprocess.run([
        "Rscript", str(ROOT / "application/scripts/pricefm/243_run_pricefm_stage_r72_repair_component.R"),
        "--task-config", str(task_path),
    ], cwd=ROOT, check=True)
    terminal = json.loads((output / "terminal.json").read_text())
    spd = pd.read_csv(output / "spd_factorization_trace.csv")
    rhs = json.loads((output / "rhs_diagnostics.json").read_text())
    assert terminal["status"] == "completed"
    assert terminal["package"]["version"] == "1.1.1.9001"
    assert len(spd) == terminal["iter"]
    assert rhs["preflight"]["init_tau_source"] == "init_tau"
    assert not list(output.rglob("*.rds"))
