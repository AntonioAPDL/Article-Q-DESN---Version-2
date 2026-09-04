import importlib.util
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
PREP = SCRIPTS / "280_prepare_pricefm_stage_r86_homogeneous_exal_refit.py"
LAUNCH = SCRIPTS / "281_launch_pricefm_stage_r87_homogeneous_exal_refit.py"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_task_transform_changes_only_repair_runtime_and_identity(tmp_path):
    module = load(PREP, "pricefm_r86")
    source_path = tmp_path / "source.json"
    source = {
        "task_id": "old", "case_id": "case", "tau": 0.25,
        "selection_split": "val", "likelihood_family": "exal",
        "depth_D": 3, "units_json": "[64,64,64]", "rhs_tau0": 0.0001,
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    source_path.write_text(json.dumps(source))
    runtime = tmp_path / "runtime"; runtime.mkdir()
    runtime_manifest = tmp_path / "runtime.json"; runtime_manifest.write_text("{}")
    gate = tmp_path / "gate.json"; gate.write_text("{}")
    task = module.build_task(source, source_path, {}, runtime, runtime_manifest, gate, tmp_path / "runs")
    assert task["stage"] == "R87" and task["sigmagam_freeze_warmup_iters"] == 0
    assert task["depth_D"] == 3 and task["units_json"] == "[64,64,64]"
    assert task["rhs_tau0"] == 0.0001
    assert task["runner_script_sha256"] == module.sha256(module.RUNNER)
    assert task["test_access_authorized"] is False


def test_prep_and_launcher_enforce_exact_nonoverlapping_scope():
    prep = PREP.read_text(); launch = LAUNCH.read_text()
    assert 'runtime.get("installed_package") or runtime' in prep
    assert "len(refit) != 280" in prep and "len(retained) != 14" in prep
    assert '"scientific_fields_changed": []' in prep
    assert "R86 prep must not create launch YAML" in prep
    assert "len(manifest) != 280" in launch and 'manifest.stage.eq("R87")' in launch
    assert '"one_process_per_cpu": True' in launch
    assert "selected CPUs exceed the usage gate" in launch
    assert '"code_commit": code_commit' in launch
    shared = (SCRIPTS / "260_launch_pricefm_stage_r76_repaired_exal_surface.py").read_text()
    assert 'Path("/proc/stat")' in shared
    assert "idle / total" in shared
    assert '"ps", "-e"' not in shared
    assert "test data" in launch.lower()


def test_shared_r_runner_accepts_r87_only_as_scientific_repair():
    text = (SCRIPTS / "259_run_pricefm_stage_r76_repaired_exal_component.R").read_text()
    assert 'task_stage %in% c("R83", "R87")' in text
    assert 'task_stage %in% c("R82D", "R83", "R87")' in text
