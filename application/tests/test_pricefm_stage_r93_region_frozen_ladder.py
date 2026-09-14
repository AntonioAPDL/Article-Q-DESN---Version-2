"""Focused tests for the PriceFM Stage-R93 region-frozen ladder prep."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application/scripts/pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
SCRIPT = SCRIPT_DIR / "291_prepare_pricefm_stage_r93_region_frozen_ladder.py"


def load_script():
    spec = importlib.util.spec_from_file_location(SCRIPT.stem, SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_yaml(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(payload, sort_keys=False))


def fixture(tmp_path: Path):
    r92 = tmp_path / "r92.csv"
    control = tmp_path / "controls.csv"
    data = tmp_path / "data.yaml"
    full = tmp_path / "full.yaml"
    template = tmp_path / "template.yaml"
    output = tmp_path / "output"
    generated = tmp_path / "generated"
    runs = tmp_path / "runs"

    pd.DataFrame([
        {
            "region": "SE_2", "fold": fold, "qdesn_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "experiment_id": experiment,
            "qdesn_AQL": aql, "pricefm_AQL": pricefm, "decision_label": decision,
        }
        for fold, experiment, aql, pricefm, decision in [
            (1, "broad", 6.4456386889, 4.2135339868, "pricefm_wins"),
            (2, "local2", 3.0275322919, 3.6377627079, "qdesn_wins"),
            (3, "local3", 5.3023264652, 4.6333665507, "pricefm_wins"),
        ]
    ]).to_csv(r92, index=False)
    specs = [
        (1, "broad", 2, [120, 120], 0.40, 0.90, 0.25, 20260608),
        (2, "local2", 2, [80, 80], 0.50, 0.90, 0.20, 20260610),
        (3, "local3", 3, [40, 40, 40], 0.45, 0.90, 0.35, 20260610),
    ]
    pd.DataFrame([
        {
            "region": "SE_2", "fold": fold, "experiment_id": experiment,
            "qdesn_method_id": "qdesn_exal_rhs_ns_exact_chunked", "feature_policy": "target_only",
            "lag_window": 96, "depth": depth, "units": json.dumps(units), "alpha": alpha,
            "rho": rho, "input_scale": input_scale, "state_output": "final_layer",
            "seed": seed, "tau0": 0.001,
        }
        for fold, experiment, depth, units, alpha, rho, input_scale, seed in specs
    ]).to_csv(control, index=False)

    write_yaml(data, {
        "pricefm": {
            "regions": ["NO_3", "NO_4", "SE_1", "SE_2", "SE_3"],
            "raw_dir": "application/data_local/pricefm/raw",
            "interim_dir": "application/data_local/pricefm/interim",
            "processed_dir": "application/data_local/pricefm/processed",
            "external_repo_dir": "application/data_local/pricefm/external/PriceFM",
            "log_dir": "application/data_local/pricefm/logs",
            "splits": [], "windows": {"lag_window": 96, "lead_window": 96},
            "pilot": {"enabled": True, "region": "SE_2", "fold": 1},
        }
    })
    write_yaml(full, {
        "pricefm_desn_full": {
            "data_config": str(data), "package_path": str(tmp_path), "rscript_bin": "Rscript",
            "python_bin": "python3", "scope": {}, "adapter": {}, "run": {},
            "rhs_ns": {}, "normal": {}, "qdesn_vb": {}, "exact_equivalence": {},
        }
    })
    write_yaml(template, {
        "pricefm_desn_experiment_grid": {
            "grid_id": "fixture", "purpose": "fixture",
            "base": {"data_config": str(data), "full_config": str(full), "generated_root": str(generated), "run_root": str(runs)},
            "scope": {},
            "fixed": {"train_origin_limit": 3000},
            "launch": {}, "experiments": [], "experiment_blocks": [],
        }
    })
    return r92, control, template, output, generated, runs


def args_for(module, tmp_path: Path, count: int = 40):
    r92, control, template, output, generated, runs = fixture(tmp_path)
    return module.parser().parse_args([
        "--r92-registry", str(r92), "--control-registry", str(control),
        "--template-grid", str(template), "--output-dir", str(output),
        "--generated-root", str(generated), "--run-root", str(runs),
        "--artifact-repo", str(tmp_path), "--candidate-count", str(count),
        "--normal-runtime-source", str(tmp_path),
        "--ridge-top-k", "30", "--write-grid", "true", "--allow-fixture-hashes",
    ])


def test_r93_prep_includes_all_fold_controls_and_quarantines_test(tmp_path):
    module = load_script()
    args = args_for(module, tmp_path)
    summary = module.run(args)
    assert summary["status"] == "completed_not_launched"
    assert summary["candidate_count"] == 40
    assert summary["authoritative_fold_controls"] == 3
    assert summary["planned_ridge_fits"] == 120
    assert summary["launcher_invoked"] is False

    candidates = pd.read_csv(args.output_dir / "pricefm_stage_r93_ridge_candidate_manifest.csv")
    controls = candidates[candidates.candidate_role.eq("authoritative_fold_geometry_control")]
    assert sorted(controls.source_fold.astype(int).tolist()) == [1, 2, 3]
    assert candidates.semantic_fingerprint.is_unique
    assert candidates.feature_policy.value_counts().to_dict() == {
        "target_only": 16, "graph_summary_mean": 12,
        "graph_summary_mean_std": 8, "graph_khop": 4,
    }
    assert not candidates.test_access_authorized.map(bool).any()

    grid_path = args.output_dir / "pricefm_stage_r93_ridge_grid.yaml"
    grid = yaml.safe_load(grid_path.read_text())["pricefm_desn_experiment_grid"]
    base_data = yaml.safe_load(Path(grid["base"]["data_config"]).read_text())["pricefm"]
    base_full = yaml.safe_load(Path(grid["base"]["full_config"]).read_text())["pricefm_desn_full"]
    assert base_data["allow_absolute_local_paths"] is True
    for key in ["raw_dir", "interim_dir", "processed_dir"]:
        assert Path(base_data[key]).is_absolute()
    assert Path(base_data["processed_dir"]).name == "processed_stage_r93_region_frozen_20260906"
    assert all("test" not in split for split in base_data["splits"])
    assert Path(base_full["package_path"]) == tmp_path
    assert grid["scope"]["splits"] == ["train", "val"]
    assert grid["scope"]["folds"] == [101, 102, 103]
    assert grid["fixed"]["normal"]["prior_types"] == ["scaled_ridge"]
    assert grid["fixed"]["normal"]["predictive_quantile_mode"] == "analytic_student_t"
    assert grid["fixed"]["qdesn_vb"]["enabled"] is False
    assert grid["launch"]["prepared_not_authorized"]["authorized"] is False
    assert len(grid["experiments"]) == 40
    assert not any("test_AQL" in exp for exp in grid["experiments"])

    continuation = json.loads((args.output_dir / "pricefm_stage_r93_continuation_contract.json").read_text())
    assert continuation["ridge"]["top_k_to_rhs"] == 30
    assert continuation["freeze"]["scope"] == "one DESN geometry and one tau0 for SE_2"
    assert continuation["firewalls"]["forecast_window_selects_or_retunes"] is False


def test_r93_rejects_control_from_a_different_authoritative_experiment(tmp_path):
    module = load_script()
    args = args_for(module, tmp_path)
    frame = pd.read_csv(args.control_registry)
    frame.loc[frame.fold.eq(2), "experiment_id"] = "wrong_experiment"
    frame.to_csv(args.control_registry, index=False)
    try:
        module.run(args)
    except RuntimeError as exc:
        assert "control experiment IDs differ" in str(exc)
    else:
        raise AssertionError("R93 should reject a changed authoritative fold control")


def test_stage_selective_runner_contract_is_wired():
    runner = (SCRIPT_DIR / "08_run_desn_model_smoke.R").read_text()
    grid_prep = (SCRIPT_DIR / "12_prepare_desn_experiment_grid.py").read_text()
    assert "normal_prior_types" in runner
    assert 'identical(predictive_mode, "analytic_student_t")' in runner
    assert 'identical(predictive_mode, "analytic_normal")' in runner
    assert 'c("scaled_ridge", "rhs_ns")' in runner
    assert "qdesn_enabled" in runner
    assert "if (!qdesn_enabled) return(invisible(NULL))" in runner
    assert 'file.path(out_dir, "normal_beta_mean.csv")' in runner
    assert 'file.path(out_dir, "normal_beta_cov_diag.csv")' in runner
    assert '"stage_r93_semantic_fingerprint"' in grid_prep
