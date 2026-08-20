from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_ROOT = REPO_ROOT / "application" / "scripts" / "pricefm"
sys.path.insert(0, str(SCRIPT_ROOT))


def load_script(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_ROOT / filename)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


prep_module = load_script(
    "pricefm_stage_r56_prep", "188_prepare_pricefm_stage_r56_ee_f1_confirmation.py"
)
launch_module = load_script(
    "pricefm_stage_r56_launch", "189_launch_pricefm_stage_r56_ee_f1_confirmation.py"
)


def build_fixture(tmp_path: Path) -> tuple[Path, Path]:
    r55 = tmp_path / "r55"
    r53 = tmp_path / "r53"
    r55.mkdir()
    r53.mkdir()
    pd.DataFrame([{
        "case_id": "r52_ee_f1",
        "region": "EE",
        "fold": 1,
        "quantiles": json.dumps(list(prep_module.TAUS)),
        "chains_per_quantile": 4,
        "planned_chain_jobs": 28,
        "current_burn": 500,
        "current_retained_per_chain": 500,
        "established_burn": 5000,
        "established_retained_per_chain": 20000,
        "linear_ess_projected_retained_per_chain": 17000,
        "recommended_burn": 5000,
        "recommended_retained_per_chain": 20000,
        "selection_basis": "validation_selected+harm_guard+authority_replay; dual test comparison audit_only",
        "required_prelaunch_audit": "exact_restart_state_and_runtime_budget_capability",
        "launch_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }]).to_csv(r55 / "pricefm_stage_r55_confirmation_design.csv", index=False)
    (r55 / "summary.json").write_text(json.dumps({
        "status": "completed_read_only_functional_convergence_audit",
        "bounded_confirmation_targets": 1,
    }))

    engine = tmp_path / "engine"
    engine.mkdir()
    case_dir = tmp_path / "case"
    init_dir = case_dir / "initialization"
    init_dir.mkdir(parents=True)
    case_summary = case_dir / "case_summary.json"
    case_summary.write_text(json.dumps({"status": "completed", "m0_launch_eligible": True}))
    case_config = tmp_path / "case.yaml"
    case_config.write_text("pricefm_stage_r52_case: {}\n")
    adapter_dir = case_dir / "adapter"
    adapter_dir.mkdir()
    rows = []
    for tau in prep_module.TAUS:
        label = prep_module.tau_label(tau)
        init_path = init_dir / f"{label}_init.rds"
        init_path.write_bytes(f"init {tau}\n".encode())
        for chain in range(1, 5):
            job_id = f"r53_ee_f1_{label}_chain{chain}"
            config = tmp_path / "configs" / f"{job_id}.yaml"
            config.parent.mkdir(exist_ok=True)
            payload = {
                "pricefm_stage_r53_m0": {
                    "id": job_id,
                    "case_id": "r52_ee_f1",
                    "region": "EE",
                    "fold": 1,
                    "tau": tau,
                    "chain": chain,
                    "seed": 1000 + len(rows),
                    "case_config": str(case_config),
                    "case_summary": str(case_summary),
                    "adapter_dir": str(adapter_dir),
                    "init_path": str(init_path),
                    "exdqlm_path": str(engine),
                    "output_dir": str(tmp_path / "old" / job_id),
                    "likelihood_family": "exal",
                    "prior_family": "rhs_ns",
                    "n_burn": 500,
                    "n_mcmc": 500,
                    "thin": 1,
                    "core_update_mode": prep_module.M0_MODE,
                    "width_gamma": 4.0,
                    "max_steps_out": 100,
                    "max_shrink": 1000,
                    "core_extra_passes": 0,
                    "init_from_vb": False,
                    "store_latent_draws": False,
                    "store_rhs_draws": True,
                    "registry_mutation_authorized": False,
                    "article_mutation_authorized": False,
                }
            }
            config.write_text(yaml.safe_dump(payload, sort_keys=False))
            rows.append({
                "id": job_id,
                "case_id": "r52_ee_f1",
                "region": "EE",
                "fold": 1,
                "tau": tau,
                "chain": chain,
                "seed": payload["pricefm_stage_r53_m0"]["seed"],
                "config": str(config),
                "output_dir": str(tmp_path / "old" / job_id),
            })
    pd.DataFrame(rows).to_csv(r53 / "pricefm_stage_r53_launch_manifest.csv", index=False)
    pd.DataFrame([{
        "id": "r52_ee_f1",
        "region": "EE",
        "fold": 1,
        "config": str(case_config),
        "adapter_dir": str(adapter_dir),
        "output_dir": str(case_dir),
    }]).to_csv(r53 / "pricefm_stage_r52_case_manifest.csv", index=False)
    (r53 / "summary.json").write_text(json.dumps({"exdqlm_head": "fixture-engine"}))
    return r55, r53


def make_args(tmp_path: Path, r55: Path, r53: Path, authorize: bool = False) -> argparse.Namespace:
    return argparse.Namespace(
        stage_r55_dir=r55,
        stage_r53_prep_dir=r53,
        output_dir=tmp_path / "prep",
        grid_dir=tmp_path / "grid",
        run_dir=tmp_path / "runs",
        chains=4,
        n_burn=5000,
        n_mcmc=20000,
        workers=20,
        expected_targets=1,
        authorize_launch=authorize,
        force=False,
    )


def test_r56_materializes_exact_bounded_full_budget_surface(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    r55, r53 = build_fixture(tmp_path)
    monkeypatch.setattr(prep_module, "git_head", lambda _: "fixture-engine")
    args = make_args(tmp_path, r55, r53, authorize=True)
    summary = prep_module.run(args)
    assert summary["status"] == "materialized_ready_to_launch"
    assert summary["chain_jobs"] == 28
    assert summary["target"] == "EE/fold=1"
    assert summary["fresh_restart"] is True
    assert summary["exact_continuation_possible"] is False
    manifest = pd.read_csv(args.output_dir / "pricefm_stage_r56_launch_manifest.csv")
    assert manifest.groupby("tau").chain.nunique().eq(4).all()
    assert manifest.n_burn.eq(5000).all()
    assert manifest.n_mcmc.eq(20000).all()
    assert manifest.restart_mode.eq("fresh_from_frozen_explicit_vb_init").all()
    assert set(manifest.seed).isdisjoint(set(pd.read_csv(r53 / "pricefm_stage_r53_launch_manifest.csv").seed))
    config = yaml.safe_load(Path(manifest.iloc[0].config).read_text())["pricefm_stage_r53_m0"]
    assert config["n_burn"] == 5000
    assert config["n_mcmc"] == 20000
    assert config["core_update_mode"] == prep_module.M0_MODE
    assert config["registry_mutation_authorized"] is False
    gates = pd.read_csv(args.output_dir / "pricefm_stage_r56_prelaunch_gates.csv")
    assert gates.passed.astype(bool).all()


def test_r56_defaults_to_no_launch_authorization(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    r55, r53 = build_fixture(tmp_path)
    monkeypatch.setattr(prep_module, "git_head", lambda _: "fixture-engine")
    args = make_args(tmp_path, r55, r53, authorize=False)
    summary = prep_module.run(args)
    assert summary["launch_authorized"] is False
    launch = yaml.safe_load((args.output_dir / "pricefm_stage_r56_launch.yaml").read_text())
    assert launch["pricefm_stage_r56_launch"]["launch_authorized_by_user"] is False


def test_r56_rejects_target_drift(tmp_path: Path) -> None:
    r55, r53 = build_fixture(tmp_path)
    design_path = r55 / "pricefm_stage_r55_confirmation_design.csv"
    design = pd.read_csv(design_path)
    design.loc[0, "region"] = "SK"
    design.to_csv(design_path, index=False)
    with pytest.raises(RuntimeError, match="bounded"):
        prep_module.run(make_args(tmp_path, r55, r53))


def test_r56_completion_contract_requires_budget_mode_and_artifacts(tmp_path: Path) -> None:
    output = tmp_path / "job"
    output.mkdir()
    row = argparse.Namespace(id="r56_x", output_dir=str(output), n_burn=5000, n_mcmc=20000)
    (output / "job_summary.json").write_text(json.dumps({
        "status": "completed",
        "id": "r56_x",
        "n_burn": 5000,
        "n_mcmc": 20000,
        "core_update_mode": prep_module.M0_MODE,
        "finite_draws": True,
    }))
    assert launch_module.completed_job(row) is False
    for filename in ("posterior_draws.rds", "scalar_draws.csv.gz", "posterior_mean_predictions.csv.gz"):
        (output / filename).write_bytes(b"fixture\n")
    assert launch_module.completed_job(row) is True


def test_r56_launcher_requires_twenty_physical_workers(tmp_path: Path) -> None:
    args = argparse.Namespace(
        jobs=19,
        required_idle_physical_cores=20,
        prep_dir=tmp_path / "prep",
    )
    with pytest.raises(ValueError, match="exactly 20"):
        launch_module.Campaign(args)
