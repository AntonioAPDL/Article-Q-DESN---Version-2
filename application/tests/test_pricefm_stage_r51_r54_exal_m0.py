import importlib.util
import json
import math
import os
import subprocess
import sys
from pathlib import Path

import pandas as pd
import pytest
import yaml


SCRIPTS = Path(__file__).parents[1] / "scripts/pricefm"
R51 = SCRIPTS / "181_freeze_pricefm_stage_r51_exal_m0_authority.py"
R52 = SCRIPTS / "182_prepare_pricefm_stage_r52_r53_exal_m0_launch.py"
CASE_RUNNER = SCRIPTS / "183_prepare_pricefm_stage_r52_exal_m0_case.R"
CHAIN_RUNNER = SCRIPTS / "184_run_pricefm_stage_r53_exal_m0_chain.R"
LAUNCHER = SCRIPTS / "185_launch_pricefm_stage_r53_exal_m0.py"
CLOSEOUT = SCRIPTS / "186_closeout_pricefm_stage_r54_exal_m0.R"
R_BIN = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
EXDQLM = Path("/data/jaguir26/local/src/exdqlm__wt__independent_exal_m0_relaunch_v1_1p0p0")
sys.path.insert(0, str(SCRIPTS))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_r51_selects_only_authoritative_exal_and_freezes_complete_lineage():
    mod = load(R51, "pricefm_r51")
    registry = pd.DataFrame([
        {"region": "AA", "fold": 1, "experiment_id": "ex1", "qdesn_method_id": mod.EXAL_METHOD},
        {"region": "BB", "fold": 2, "experiment_id": "al1", "qdesn_method_id": "qdesn_al_rhs_ns_exact_chunked"},
    ])
    atlas = pd.DataFrame([
        {"region": "AA", "fold": 1, "experiment_id": "ex1", "method_id": mod.EXAL_METHOD},
        {"region": "BB", "fold": 2, "experiment_id": "al1", "method_id": "qdesn_al_rhs_ns_exact_chunked"},
    ])
    selected, excluded = mod.selected_specs(registry, atlas)
    assert len(selected) == 1
    assert selected.iloc[0].method_id == mod.EXAL_METHOD
    assert len(excluded) == 1

    target = pd.DataFrame([{"region": "AA", "fold": 1, "experiment_id": "ex1", "qdesn_AQL": 3.0}])
    candidates = pd.DataFrame([
        {
            "region": "AA", "fold": 1, "experiment_id": "ex1", "lineage_grid": "grid_a",
            "child_experiment_id": f"child_{tau}", "tau": tau, "val_AQL": 2.0 + tau,
            "test_AQL": 3.0, "child_metric_summary": "metric.csv",
        }
        for tau in mod.TAUS
    ])
    status, lineage = mod.choose_lineages(target, candidates, 1e-12)
    assert status.iloc[0].lineage_status == "complete_exact"
    assert len(lineage) == 7
    assert lineage.tau.nunique() == 7


def test_r52_materializes_full_case_specific_bundle_for_fixture(tmp_path):
    mod = load(R52, "pricefm_r52")
    r51 = tmp_path / "r51"
    r51.mkdir()
    source_config = tmp_path / "source.yaml"
    source_config.write_text(yaml.safe_dump({
        "pricefm_desn_smoke": {
            "package_path": "old", "region": "AA", "fold": 1, "quantiles": [0.5],
            "adapter": {"output_dir": "old-adapter"}, "run": {"output_dir": "old-run"},
            "artifact_hygiene": {"enabled": True},
        }
    }))
    targets = pd.DataFrame([{
        "region": "AA", "fold": 1, "experiment_id": "ex1",
        "qdesn_method_id": "qdesn_exal_rhs_ns_exact_chunked", "qdesn_AQL": 3.0,
        "pricefm_AQL": 3.2, "lineage_val_AQL": 2.8, "lineage_status": "complete_exact",
        "source_config": str(source_config), "source_adapter_manifest": str(tmp_path / "adapter.json"),
        "source_metric_summary": str(tmp_path / "metric.csv"), "m0_eligible": True,
        "selection_role": "validation_only",
    }])
    targets.to_csv(r51 / "pricefm_stage_r51_exal_target_ledger.csv", index=False)
    pd.DataFrame([{"region": "AA", "fold": 1, "experiment_id": "ex1", "seed": 7}]).to_csv(
        r51 / "pricefm_stage_r51_case_specification_freeze.csv", index=False
    )
    engine_head = mod.git_head(mod.EXDQLM_REPO)
    (r51 / "summary.json").write_text(json.dumps({
        "status": "completed_authority_freeze", "exdqlm_head": engine_head
    }))
    args = mod.parser().parse_args([
        "--stage-r51-dir", str(r51), "--output-dir", str(tmp_path / "prep"),
        "--grid-dir", str(tmp_path / "grid"), "--run-dir", str(tmp_path / "runs"),
        "--expected-targets", "1", "--expected-exdqlm-head", engine_head,
    ])
    result = mod.run(args)
    manifest = pd.read_csv(tmp_path / "prep/pricefm_stage_r53_launch_manifest.csv")
    assert result["chain_jobs"] == 28
    assert manifest.tau.nunique() == 7
    assert manifest.groupby("tau").chain.nunique().eq(4).all()
    config = yaml.safe_load(Path(manifest.iloc[0].config).read_text())["pricefm_stage_r53_m0"]
    assert config["core_update_mode"] == "m0_v_collapsed_support_logit"
    assert config["n_burn"] == 500 and config["n_mcmc"] == 500
    assert config["init_from_vb"] is False
    assert config["store_latent_draws"] is False
    assert config["store_rhs_draws"] is True
    launch = yaml.safe_load((tmp_path / "prep/pricefm_stage_r53_launch.yaml").read_text())
    assert launch["pricefm_stage_r53_launch"]["one_process_per_physical_core"] is True
    case_config = yaml.safe_load(next((tmp_path / "grid/case_configs").glob("*.yaml")).read_text())
    assert "/venv/bin/python" in case_config["pricefm_stage_r52_case"]["python_executable"]


def test_case_and_chain_runners_consume_the_frozen_m0_contract():
    case_text = CASE_RUNNER.read_text()
    chain_text = CHAIN_RUNNER.read_text()
    assert "design_replay_audit.csv" in case_text
    assert 'fit_vb("al", tau' in case_text
    assert 'fit_vb("exal", tau' in case_text
    assert "promotion_replay_eligible" in case_text
    assert 'core_update_mode = as.character(cfg$core_update_mode)' in chain_text
    assert 'identical(mode_observed, "m0_v_collapsed_support_logit")' in chain_text
    assert "init_from_vb = FALSE" in chain_text
    assert "store_latent_draws = FALSE, store_rhs_draws = TRUE" in chain_text
    assert "registry_mutation_authorized = FALSE" in chain_text


def test_launcher_uses_distinct_physical_cpu_lanes_and_single_thread_env():
    mod = load(LAUNCHER, "pricefm_r53_launcher")
    text = LAUNCHER.read_text()
    assert "validate_distinct_physical" in text
    assert '"OPENBLAS_NUM_THREADS": "1"' in text
    assert '"MKL_NUM_THREADS": "1"' in text
    assert '"taskset", "-c"' in text
    assert "case replay jobs failed; M0 chains were not started" in text
    assert 'recorder.publish("finished", status=final["status"])' in text
    assert 'recorder.publish("failed", status="failed", error=str(exc))' in text
    cases = pd.DataFrame([{"id": "a"}, {"id": "b"}])
    regular, external = mod.partition_external_case(cases, "b")
    assert [row.id for row in regular] == ["a"]
    assert [row.id for row in external] == ["b"]
    with pytest.raises(ValueError, match="exactly one"):
        mod.partition_external_case(cases, "missing")


@pytest.mark.skipif(not R_BIN.exists() or not EXDQLM.exists(), reason="local R/exdqlm integration unavailable")
def test_chain_runner_executes_collapsed_m0_and_publishes_atomic_summary(tmp_path):
    adapter = tmp_path / "adapter"
    adapter.mkdir()
    train_x = [[1.0, (i - 15) / 10, math.sin(i / 3)] for i in range(30)]
    train_y = [0.5 + 0.4 * row[1] - 0.2 * row[2] for row in train_x]
    pd.DataFrame(train_x).to_csv(adapter / "X_train.csv", index=False, header=False)
    pd.DataFrame(train_y).to_csv(adapter / "y_train.csv", index=False, header=False)
    for split, offset in (("val", 30), ("test", 36)):
        x = [[1.0, (i - 15) / 10, math.sin(i / 3)] for i in range(offset, offset + 6)]
        pd.DataFrame(x).to_csv(adapter / f"X_{split}.csv", index=False, header=False)
        pd.DataFrame({"origin_id": range(offset, offset + 6), "horizon": range(1, 7)}).to_csv(
            adapter / f"rows_{split}.csv", index=False
        )

    source = tmp_path / "source.yaml"
    source.write_text(yaml.safe_dump({"pricefm_desn_smoke": {
        "rhs_ns": {"tau0": 1e-4, "shrink_intercept": False, "freeze_tau_iters": 0,
                   "freeze_tau_warmup_iters": 0},
        "qdesn_vb": {"prior_sigma": {"a": 1.0, "b": 1.0},
                     "prior_gamma": {"mu0": 0.0, "s20": 10.0}},
    }}))
    case_config = tmp_path / "case.yaml"
    case_config.write_text(yaml.safe_dump({"pricefm_stage_r52_case": {"source_config": str(source)}}))
    case_summary = tmp_path / "case_summary.json"
    case_summary.write_text(json.dumps({"status": "completed", "m0_launch_eligible": True}))
    init = tmp_path / "init.rds"
    make_init = tmp_path / "make_init.R"
    make_init.write_text(
        f"saveRDS(list(beta=rep(0,3),sigma=1,gamma=0,v=rep(1,30),s=rep(0,30)),"
        f"{json.dumps(str(init))})\n"
    )
    subprocess.run([str(R_BIN), str(make_init)], check=True, timeout=30)

    output = tmp_path / "chain"
    config = tmp_path / "chain.yaml"
    config.write_text(yaml.safe_dump({"pricefm_stage_r53_m0": {
        "id": "fixture_tau50_chain1", "case_id": "fixture", "region": "AA", "fold": 1,
        "tau": 0.5, "chain": 1, "seed": 17, "case_config": str(case_config),
        "case_summary": str(case_summary), "adapter_dir": str(adapter), "init_path": str(init),
        "exdqlm_path": str(EXDQLM), "output_dir": str(output), "n_burn": 4, "n_mcmc": 5,
        "thin": 1, "core_update_mode": "m0_v_collapsed_support_logit", "width_gamma": 4.0,
        "max_steps_out": 20, "max_shrink": 100, "core_extra_passes": 0,
    }}))
    env = os.environ.copy()
    env.update({"OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1"})
    completed = subprocess.run(
        [str(R_BIN), str(CHAIN_RUNNER), "--config", str(config), "--force", "true"],
        check=False, capture_output=True, text=True, timeout=180, env=env,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    summary = json.loads((output / "job_summary.json").read_text())
    assert summary["status"] == "completed"
    assert summary["core_update_mode"] == "m0_v_collapsed_support_logit"
    assert summary["finite_draws"] is True
    assert summary["n_mcmc"] == 5
    assert (output / "posterior_draws.rds").exists()
    assert (output / "posterior_mean_predictions.csv.gz").exists()


def test_closeout_freezes_validation_selection_before_dual_test_audit():
    text = CLOSEOUT.read_text()
    assert "m0_val < vb_val" in text
    assert "m0_test < as.numeric(case_summary$authority_qdesn_AQL)" in text
    assert "m0_test < as.numeric(case_cfg$cached_pricefm_AQL)" in text
    assert "internal_registry_promotion_candidate" in text
    assert "article_pricefm_promotion_candidate" in text
    assert "Expected four unique chains" in text
    assert "Retained-draw count mismatch" in text
    assert "Incomplete chain predictions" in text
    assert "registry_mutation_authorized = FALSE" in text
    assert "article_mutation_authorized = FALSE" in text
