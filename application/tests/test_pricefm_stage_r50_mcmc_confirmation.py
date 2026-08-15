import importlib.util
import sys
from pathlib import Path

import pandas as pd

SCRIPTS = Path(__file__).parents[1] / "scripts/pricefm"
PREP = SCRIPTS / "176_prepare_pricefm_stage_r50_mcmc_confirmation.py"
INIT = SCRIPTS / "177_extract_pricefm_stage_r50_vb_initialization.py"
RUNNER = SCRIPTS / "178_run_pricefm_stage_r50_mcmc_chain.R"
LAUNCHER = SCRIPTS / "179_launch_pricefm_stage_r50_mcmc_confirmation.py"
CLOSEOUT = SCRIPTS / "180_closeout_pricefm_stage_r50_mcmc_confirmation.R"
sys.path.insert(0, str(SCRIPTS))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_manifest_is_case_specific_and_complete(tmp_path):
    mod = load(PREP, "r50prep")
    r48, cell, exd = tmp_path / "r48", tmp_path / "cell", tmp_path / "exd"
    r48.mkdir(); (cell / "adapter").mkdir(parents=True); (cell / "model").mkdir(); exd.mkdir()
    pd.DataFrame([{"region": "NO_3", "fold": 3, "mcmc_confirmation_eligible": True, "pooled_test_AQL": 3.8318982860174926}]).to_csv(r48 / "pricefm_stage_r48_mcmc_confirmation_queue.csv", index=False)
    import yaml, json
    cfg = {"pricefm_desn_smoke": {"region": "NO_3", "fold": 3, "quantiles": mod.TAUS, "package_path": str(exd), "adapter": {"output_dir": "x"}, "run": {"output_dir": "y"}}}
    (cell / "config.yaml").write_text(yaml.safe_dump(cfg))
    for p in [cell / "adapter/adapter_manifest.json", cell / "adapter/feature_map_matrix.npz", cell / "model/model_predictions_scaled.csv", cell / "model/model_parameter_summary.csv"]: p.write_text("x")
    args = mod.parser().parse_args(["--stage-r48-dir", str(r48), "--stage-r47-cell", str(cell), "--exdqlm-path", str(exd), "--output-dir", str(tmp_path / "out"), "--grid-dir", str(tmp_path / "grid"), "--run-dir", str(tmp_path / "runs")])
    result = mod.run(args)
    manifest = pd.read_csv(tmp_path / "out/pricefm_stage_r50_launch_manifest.csv")
    assert result["jobs"] == 56
    assert set(manifest.component) == {"shared_static", "horizon_1_24"}
    assert set(manifest.fold) == {3} and set(manifest.region) == {"NO_3"}
    assert manifest.groupby(["component", "tau"]).chain.nunique().eq(4).all()


def test_runner_preserves_contract_and_avoids_internal_vb():
    text = RUNNER.read_text()
    assert "init_from_vb = FALSE" in text
    assert "base_frequency" in text and "focused_frequency" in text
    assert 'likelihood_family = "exal"' in text
    assert "horizon_1_24" in text
    assert 'setdiff(list.files(out), "chain.log")' in text


def test_launcher_uses_one_cpu_lane_per_worker():
    text = LAUNCHER.read_text()
    assert "launch_lane" in text
    assert '"OPENBLAS_NUM_THREADS": "1"' in text
    assert "taskset" in text


def test_closeout_keeps_mutations_blocked_and_uses_dual_gate():
    text = CLOSEOUT.read_text()
    assert "test_aql < r48$authoritative_qdesn_AQL" in text
    assert "test_aql < r48$cached_pricefm_AQL" in text
    assert "registry_mutation_authorized = FALSE" in text
    assert "article_mutation_authorized = FALSE" in text
    assert "max_rhat <= 1.05" in text and "min_ess >= 200" in text


def test_initialization_requires_exact_design_hashes():
    text = INIT.read_text()
    assert 'for field in ("X_sha256", "y_sha256", "rows_sha256")' in text
    assert "feature_map_matrix_sha256" in text
    assert "np.linalg.lstsq" in text
    assert "prediction_replay_max_abs_diff" in text
