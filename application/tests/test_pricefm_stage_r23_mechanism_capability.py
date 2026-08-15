"""Tests for the PriceFM Stage-R23 mechanism-capability audit."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script():
    path = SCRIPT_DIR / "147_audit_pricefm_stage_r23_mechanism_capability.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def manifest_row(exp_id: str, arm: str, units: str, feature_dim: int, state_output: str) -> dict:
    return {
        "experiment_id": exp_id,
        "region": "NO_4",
        "fold": 2,
        "priority": 0,
        "target_quantile": 0.5,
        "stage": "stage_r22c_case_specific_horizon_screening",
        "stage_r22b_case_id": "r22b_no4_f2",
        "stage_r22b_candidate_id": f"r22b_no4_f2_{exp_id}",
        "screening_arm": arm,
        "candidate_family": "case_specific_horizon_weighted_readout",
        "horizon_focus": "25-48",
        "horizon_weight_multiplier": 2.5,
        "max_promotable_test_AQL": 1.2,
        "feature_policy": "graph_summary_mean_std",
        "implemented_feature_policy": True,
        "lag_window": 96,
        "depth": 2,
        "units": units,
        "feature_dim": feature_dim,
        "state_output": state_output,
        "alpha": 0.35,
        "rho": 0.82,
        "input_scale": 0.3,
        "tau0": 0.001,
        "seed": 1,
        "graph_degree": 1,
        "selection_is_validation_only": True,
        "selection_rule": "validation_AQL_only_within_case_and_arm",
        "test_metrics_role": "audit_only_after_frozen_validation_selection",
        "launch_authorized_by_user": True,
        "launcher_invoked_by_prep": False,
        "fits_models_when_launched": True,
        "mutates_registry": False,
        "mutates_manuscript": False,
        "requires_stage_r22c_closeout_gate": True,
        "requires_full_quantile_gate": True,
        "case_specific_spec_key": exp_id,
    }


def make_sources(root: Path) -> Path:
    src = root / "sources"
    pkg = root / "pkg"
    files = {
        "stage_r22b_prep.py": "horizon_weight_multiplier = 2.5\ncalibration_rule = 'horizon_block_affine_shift_scale_on_validation'\n",
        "stage_r22c_launch_prep.py": "screening_arm = 'horizon_weighted_readout_loss'\nhorizon_focus = '25-48'\n",
        "stage_r22d_closeout.py": "selected_on_validation = True\n",
        "pricefm_full_run.py": "ADAPTER_FORWARD_KEYS = ['depth', 'units', 'alpha', 'rho', 'input_scale', 'state_output']\nquantiles = resolve_quantiles(full_cfg)\nfeature_policy = full_cfg['scope'].get('feature_policy')\n",
        "pricefm_desn_adapter.py": "def normalize_reservoir_config(adapter_cfg, feature_dim):\n    units = adapter_cfg.get('units')\n    depth = adapter_cfg.get('depth')\n    state_output = adapter_cfg.get('state_output', 'final_layer')\n    if state_output == 'concat_layers': return sum(units)\n    raise ValueError('Unknown feature_policy')\n",
        "08_run_desn_model_smoke.R": "quantiles <- as.numeric(unlist(cfg$quantiles))\nfit_cache$al <- fit_qdesn_like('al')\nfit_cache$exal <- fit_qdesn_like('exal')\nfit <- exdqlm::exal_ldvb_fit(y = y_tr, X = X_tr, p0 = tau, likelihood_family = likelihood)\n",
        "09_summarize_desn_model_smoke.py": "horizon_group_metrics = []\n",
        "template.yaml": "fixed:\n  qdesn_likelihoods:\n  - al\n  - exal\n",
    }
    for name, text in files.items():
        (src / name).parent.mkdir(parents=True, exist_ok=True)
        (src / name).write_text(text)
    (pkg / "R").mkdir(parents=True, exist_ok=True)
    (pkg / "R" / "exal_ldvb_fit.R").write_text(
        "exal_ldvb_fit <- function(y, X, p0, gamma_bounds, vb_control = NULL, ...) {\n  do.call(exal_ldvb_engine, list(y = y, X = X, p0 = p0))\n}\n"
    )
    (pkg / "R" / "exal_ldvb_engine.R").write_text(
        "exal_ldvb_engine <- function(y, X, p0, gamma_bounds, vb_control, init, beta_prior_obj, likelihood_family = c('exal','al')) {\n  TRUE\n}\n"
    )
    (pkg / "R" / "qdesn_vb.R").write_text("qdesn_vb <- function(y, X, weights = NULL) TRUE\n")
    return src


def make_fixture(tmp_path: Path):
    prep = tmp_path / "prep"
    r22d = tmp_path / "r22d"
    out = tmp_path / "out"
    src = make_sources(tmp_path)
    write_csv(
        prep / "pricefm_stage_r22c_launch_manifest.csv",
        [
            manifest_row("weighted", "horizon_weighted_readout_loss", "[96, 64]", 64, "final_layer"),
            manifest_row("interaction", "horizon_block_interaction_readout", "[96, 96]", 192, "concat_layers"),
        ],
    )
    write_csv(
        prep / "pricefm_stage_r22c_postfit_deferred_manifest.csv",
        [
            {
                "stage_r22b_case_id": "r22b_no4_f2",
                "region": "NO_4",
                "fold": 2,
                "screening_arm": "postfit_calibration",
                "candidate_family": "case_specific_postfit_affine",
                "uses_existing_predictions": True,
                "requires_new_fit": False,
                "existing_prediction_path": "",
                "existing_metric_summary_path": "",
                "calibration_rule": "horizon_block_affine_shift_scale_on_validation",
                "stage_r22b_candidate_id": "postfit_affine",
            }
        ],
    )
    write_csv(prep / "pricefm_stage_r22c_launch_prep_gates.csv", [{"gate": "ok", "passed": True, "detail": "ok"}])
    write_json(
        r22d / "summary.json",
        {
            "stage": "pricefm_stage_r22d_case_specific_screening_closeout",
            "status": "completed_no_promotions",
            "n_promotion_queue_rows": 0,
        },
    )
    return prep, r22d, out, src, tmp_path / "pkg"


def args_for(mod, prep: Path, r22d: Path, out: Path, src: Path, pkg: Path):
    return mod.parser().parse_args(
        [
            "--r22c-prep-dir",
            str(prep),
            "--r22d-dir",
            str(r22d),
            "--output-dir",
            str(out),
            "--package-root",
            str(pkg),
            "--source-stage-r22b-prep",
            str(src / "stage_r22b_prep.py"),
            "--source-stage-r22c-launch-prep",
            str(src / "stage_r22c_launch_prep.py"),
            "--source-stage-r22d-closeout",
            str(src / "stage_r22d_closeout.py"),
            "--source-full-run-orchestrator",
            str(src / "pricefm_full_run.py"),
            "--source-adapter-builder",
            str(src / "pricefm_desn_adapter.py"),
            "--source-model-fitter",
            str(src / "08_run_desn_model_smoke.R"),
            "--source-metric-summarizer",
            str(src / "09_summarize_desn_model_smoke.py"),
            "--source-template-grid",
            str(src / "template.yaml"),
            "--force",
            "true",
        ]
    )


def test_stage_r23_audits_mechanism_capability_without_launch_yaml(tmp_path):
    prep, r22d, out, src, pkg = make_fixture(tmp_path)
    mod = load_script()
    summary = mod.run(args_for(mod, prep, r22d, out, src, pkg))

    assert summary["status"] == "completed_expensive_path_blocked_until_mechanisms_are_real"
    assert summary["n_r22c_launch_rows"] == 2
    assert summary["n_postfit_deferred_rows"] == 1
    assert summary["launches_models"] is False
    assert summary["writes_launch_yaml"] is False

    capability = pd.read_csv(out / "pricefm_stage_r23_runner_capability_matrix.csv")
    weighted = capability.set_index("mechanism").loc["horizon_weighted_readout_loss"]
    assert weighted["effective_status"] == "metadata_only_not_implemented_in_pricefm_runner"
    interaction = capability.set_index("mechanism").loc["horizon_block_interaction_readout"]
    assert interaction["effective_status"] == "partially_implemented_as_concat_layer_state_not_horizon_specific_loss"

    search = pd.read_csv(out / "pricefm_stage_r23_r22c_effective_search_space.csv")
    feature_dim = search[(search["candidate_set"] == "r22c_new_fit_launch") & (search["axis"] == "feature_dim")].iloc[0]
    assert feature_dim["min"] == 64
    assert feature_dim["max"] == 192

    calibration = pd.read_csv(out / "pricefm_stage_r23_postfit_calibration_readiness.csv")
    assert calibration.iloc[0]["readiness_status"] == "blocked_missing_existing_prediction_and_metric_paths"

    gates = pd.read_csv(out / "pricefm_stage_r23_no_launch_gates.csv")
    assert gates["passed"].map(bool).all()
    assert not list(out.glob("*.yaml"))
    assert (out / "pricefm_stage_r23_mechanism_capability_audit_report.md").exists()


def test_stage_r23_refuses_failed_r22c_prep_gate(tmp_path):
    prep, r22d, out, src, pkg = make_fixture(tmp_path)
    write_csv(prep / "pricefm_stage_r22c_launch_prep_gates.csv", [{"gate": "bad", "passed": False, "detail": "stop"}])
    mod = load_script()
    with pytest.raises(ValueError, match="Stage-R22C launch-prep gates failed"):
        mod.run(args_for(mod, prep, r22d, out, src, pkg))
