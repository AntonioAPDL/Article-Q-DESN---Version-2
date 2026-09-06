import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def load(name, filename):
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def materialize(tmp_path):
    gate = tmp_path / "stability.json"
    gate.write_text(json.dumps({
        "status": "long_stability_gate_passed",
        "r76_broad_launch_authorized": True,
        "test_opened": False,
    }))
    prep = load("r76_prep", "258_prepare_pricefm_stage_r76_repaired_exal_surface.py")
    result = prep.run(prep.parser().parse_args([
        "--stability-gate", str(gate),
        "--grid-dir", str(tmp_path / "grid"),
        "--run-dir", str(tmp_path / "runs"),
        "--output-dir", str(tmp_path / "out"),
    ]))
    return gate, result, pd.read_csv(tmp_path / "grid/task_manifest.csv")


def test_r76_prep_is_42_case_294_atom_exal_only_surface(tmp_path):
    _, result, manifest = materialize(tmp_path)
    assert result["cases"] == 42 and result["tasks"] == 294
    assert result["al_atoms_refit"] == 0 and result["al_atoms_reused"] == 294
    assert manifest.case_id.nunique() == 42
    assert manifest.groupby("case_id").tau.nunique().eq(7).all()
    assert manifest.likelihood_family.eq("exal").all()
    assert manifest.selected_family_anchor.eq("exal").all()
    assert manifest.selection_split.eq("val").all()
    assert manifest.rhs_freeze_tau_iters.eq(50).all()
    assert manifest.launch_authorized.eq(False).all()
    assert manifest.test_access_authorized.eq(False).all()
    assert not list((tmp_path / "grid").rglob("*.yaml"))
    for row in manifest.itertuples(index=False):
        task = json.loads(Path(row.task_config).read_text())
        assert task["rhs_tau0"] == row.rhs_tau0
        assert task["al_beta_sha256"] == row.al_beta_sha256


def test_r76_launcher_preflight_checks_all_hashes_without_launching(tmp_path):
    gate, _, manifest = materialize(tmp_path)
    launcher = load("r76_launcher", "260_launch_pricefm_stage_r76_repaired_exal_surface.py")
    result = launcher.run(launcher.parser().parse_args([
        "--code-root", str(ROOT), "--manifest", str(tmp_path / "grid/task_manifest.csv"),
        "--gate-summary", str(gate), "--workers", "1", "--cpu-list", "0",
        "--minimum-free-gib", "0", "--minimum-available-memory-gib", "0",
        "--preflight-only",
    ]))
    assert result["status"] == "preflight_passed_not_launched"
    assert result["tasks"] == 294 and result["cases"] == 42
    assert not list((tmp_path / "runs").rglob("terminal.json"))
    assert len(manifest) == 294


def test_r76_r_runner_preflight_uses_repaired_public_api(tmp_path):
    _, _, manifest = materialize(tmp_path)
    source = json.loads(Path(manifest.iloc[0].task_config).read_text())
    source["output_dir"] = str(tmp_path / "r-preflight")
    task = tmp_path / "r76-task.json"
    task.write_text(json.dumps(source, indent=2, sort_keys=True) + "\n")
    subprocess.run([
        "Rscript", str(SCRIPTS / "259_run_pricefm_stage_r76_repaired_exal_component.R"),
        "--task-config", str(task), "--code-root", str(ROOT), "--preflight-only", "true",
    ], check=True)
    terminal = json.loads((tmp_path / "r-preflight/terminal.json").read_text())
    assert terminal["status"] == "preflight_passed"
    assert terminal["package"]["version"] == "1.1.1.9002"
    assert terminal["package"]["repair"] == "scale-aware-SPD-plus-large-n-GIG"
    assert terminal["test_loaded"] is False


def test_r76_runner_has_no_binary_model_writer():
    text = (SCRIPTS / "259_run_pricefm_stage_r76_repaired_exal_component.R").read_text()
    assert "saveRDS(" not in text and "save(" not in text
    assert 'c("X_test.csv", "y_test.csv", "rows_test.csv")' in text
    assert 'likelihood_family), "exal"' in text
