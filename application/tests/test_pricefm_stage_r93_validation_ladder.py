"""Focused tests for the R93 validation-ladder advancement and quantile gate."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
SCRIPT = SCRIPTS / "294_advance_pricefm_stage_r93_validation_ladder.py"
R_RUNNER = SCRIPTS / "295_run_pricefm_stage_r93_quantile_ladder.R"


def load_script():
    if str(SCRIPTS) not in sys.path:
        sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(SCRIPT.stem, SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def ranked_tau0(rows):
    frame = pd.DataFrame(rows)
    frame["selection_eligible"] = True
    return frame.sort_values(
        ["median_validation_AQL", "experiment_id"], kind="stable"
    ).reset_index(drop=True)


def test_conditional_tau0_refinement_is_bounded_and_data_dependent():
    module = load_script()
    boundary = ranked_tau0([
        {"experiment_id": "low", "parent_ridge_candidate_id": "g", "tau0": 1e-4,
         "median_validation_AQL": 1.0},
        {"experiment_id": "middle", "parent_ridge_candidate_id": "g", "tau0": 1e-3,
         "median_validation_AQL": 1.2},
        {"experiment_id": "high", "parent_ridge_candidate_id": "g", "tau0": 1e-2,
         "median_validation_AQL": 1.3},
    ])
    assert module.refinement_decision(boundary, 0.01)["reason"] == "coarse_tau0_boundary"

    near_tie = ranked_tau0([
        {"experiment_id": "middle", "parent_ridge_candidate_id": "g", "tau0": 1e-3,
         "median_validation_AQL": 1.0},
        {"experiment_id": "low", "parent_ridge_candidate_id": "g", "tau0": 1e-4,
         "median_validation_AQL": 1.005},
        {"experiment_id": "high", "parent_ridge_candidate_id": "g", "tau0": 1e-2,
         "median_validation_AQL": 1.2},
    ])
    assert module.refinement_decision(near_tie, 0.01)["reason"] == "coarse_tau0_near_tie"

    clear = near_tie.copy()
    clear.loc[clear.experiment_id.eq("low"), "median_validation_AQL"] = 1.05
    decision = module.refinement_decision(clear, 0.01)
    assert decision["refinement_required"] is False
    assert decision["reason"] == "interior_tau0_with_clear_margin"


def test_refinement_separates_structural_presence_from_numerical_eligibility():
    module = load_script()
    ranked = ranked_tau0([
        {"experiment_id": "high", "parent_ridge_candidate_id": "g", "tau0": 1e-2,
         "median_validation_AQL": 1.0},
        {"experiment_id": "low", "parent_ridge_candidate_id": "g", "tau0": 1e-4,
         "median_validation_AQL": 1.001},
        {"experiment_id": "middle", "parent_ridge_candidate_id": "g", "tau0": 1e-3,
         "median_validation_AQL": 1.02},
    ])
    ranked.loc[ranked.experiment_id.eq("middle"), "selection_eligible"] = False

    decision = module.refinement_decision(ranked, 0.01)

    assert decision["winning_experiment_id"] == "high"
    assert decision["coarse_surface_structurally_complete"] is True
    assert decision["coarse_surface_arm_count"] == 3
    assert decision["coarse_surface_eligible_arm_count"] == 2
    assert decision["coarse_surface_ineligible_experiment_ids"] == ["middle"]
    assert "coarse_tau0_numerically_incomplete" in decision["refinement_triggers"]


def test_exact_coarse_winner_can_be_accepted_without_changing_selection():
    module = load_script()
    decision = {
        "winning_experiment_id": "winner",
        "winning_tau0": 0.01,
        "refinement_required": True,
        "reason": "coarse_tau0_boundary",
    }

    amended = module.apply_coarse_winner_acceptance(
        decision,
        accepted=True,
        expected_winner_id="winner",
        expected_winner_tau0=0.01,
    )

    assert amended["pre_registered_refinement_required"] is True
    assert amended["pre_registered_refinement_reason"] == "coarse_tau0_boundary"
    assert amended["refinement_required"] is False
    assert amended["protocol_amendment"] is True
    assert amended["selection_changed_by_amendment"] is False
    assert amended["test_evidence_consulted"] is False

    with pytest.raises(RuntimeError, match="ID does not match"):
        module.apply_coarse_winner_acceptance(
            decision,
            accepted=True,
            expected_winner_id="different",
            expected_winner_tau0=0.01,
        )


def coarse_grid(experiment_ids, feature_dims):
    return {
        "pricefm_desn_experiment_grid": {
            "experiments": [
                {"id": experiment_id, "feature_dim": feature_dim}
                for experiment_id, feature_dim in zip(experiment_ids, feature_dims)
            ]
        }
    }


def test_legacy_coarse_manifest_recovers_feature_dim_from_matching_grid():
    module = load_script()
    arms = pd.DataFrame({"experiment_id": ["a", "b"], "tau0": [1e-4, 1e-3]})

    hydrated, audit = module.hydrate_coarse_arm_geometry(
        arms, coarse_grid(["a", "b"], [48, 96])
    )

    assert hydrated.feature_dim.tolist() == [48, 96]
    assert set(audit.resolution) == {"recovered_from_source_grid"}
    assert audit.passed.map(bool).all()


def test_coarse_manifest_geometry_mismatch_and_id_drift_fail_closed():
    module = load_script()
    arms = pd.DataFrame({"experiment_id": ["a"], "feature_dim": [64]})
    with pytest.raises(RuntimeError, match="feature_dim mismatch"):
        module.hydrate_coarse_arm_geometry(arms, coarse_grid(["a"], [48]))
    with pytest.raises(RuntimeError, match="experiment IDs differ"):
        module.hydrate_coarse_arm_geometry(
            pd.DataFrame({"experiment_id": ["b"]}), coarse_grid(["a"], [48])
        )


def test_incomplete_coarse_closeout_resume_is_explicit_hashed_and_bounded(tmp_path):
    module = load_script()
    output = tmp_path / "rhs_coarse_closeout"
    output.mkdir()
    partial = output / "pricefm_stage_r93_rhs_coarse_ranking.csv"
    partial.write_text("experiment_id\na\n")

    with pytest.raises(FileExistsError, match="output is nonempty"):
        module.prepare_coarse_closeout_output(
            output, force=False, resume_incomplete=False
        )
    stage, recovery = module.prepare_coarse_closeout_output(
        output, force=False, resume_incomplete=True
    )
    assert stage == output.resolve()
    assert len(recovery) == 1
    assert recovery[0]["relative_path"] == partial.name
    assert len(recovery[0]["sha256"]) == 64
    recovery_path = output / "incomplete_closeout_recovery.json"
    assert json.loads(recovery_path.read_text())["prior_files"] == recovery

    recovery_path.unlink()
    unexpected = output / "unexpected.txt"
    unexpected.write_text("do not replace")
    with pytest.raises(RuntimeError, match="unexpected files"):
        module.prepare_coarse_closeout_output(
            output, force=False, resume_incomplete=True
        )
    assert unexpected.read_text() == "do not replace"


def test_refinement_grid_preserves_verified_feature_dim(tmp_path):
    module = load_script()
    data = tmp_path / "data.yaml"
    full = tmp_path / "full.yaml"
    data.write_text(yaml.safe_dump({"pricefm": {}}))
    full.write_text(yaml.safe_dump({"pricefm_desn_full": {"data_config": str(data)}}))
    payload = coarse_grid(["winner"], [48])
    payload["pricefm_desn_experiment_grid"].update({
        "base": {"data_config": str(data), "full_config": str(full)},
        "experiments": [{"id": "winner", "feature_dim": 48, "tau0": 0.01}],
    })
    winner = pd.Series({
        "experiment_id": "winner", "parent_ridge_candidate_id": "ridge",
        "ridge_rank": 1, "region": "AT", "feature_policy": "target_only",
        "lag_window": 48, "depth": 1, "units": "[48]", "feature_dim": 48,
        "alpha": 0.2, "rho": 0.9, "input_scale": 0.2,
        "state_output": "final_layer", "seed": 1,
    })

    _, _, manifest = module.build_refinement_grid(
        payload, winner, tmp_path / "output", tmp_path / "generated", tmp_path / "runs"
    )

    assert manifest.feature_dim.tolist() == [48, 48, 48]


def make_quantile_closeout(tmp_path: Path, *, exal_eligible=True, add_test=False):
    module = load_script()
    output = tmp_path / "output"
    prep = output / "outer_normal_closeout"
    model = tmp_path / "quantile_model"
    prep.mkdir(parents=True)
    model.mkdir()
    task = tmp_path / "task.json"
    task.write_text(json.dumps({
        "output_dir": str(model),
        "semantic_contract": {"region": "SE_2", "tau0": 0.001},
    }))
    (prep / "summary.json").write_text(json.dumps({"quantile_task": str(task)}))

    metric_rows = [
        {"method_id": module.AL_METHOD, "split": "val", "unit": "original", "AQL": 8.0},
        {"method_id": module.EXAL_METHOD, "split": "val", "unit": "original", "AQL": 7.5},
    ]
    if add_test:
        metric_rows.append({
            "method_id": module.AL_METHOD, "split": "test", "unit": "original", "AQL": 1.0,
        })
    pd.DataFrame(metric_rows).to_csv(model / "metric_summary.csv", index=False)
    methods = []
    for method_id in (module.AL_METHOD, module.EXAL_METHOD):
        for tau in module.PAPER_QUANTILES:
            methods.append({"method_id": method_id, "tau": tau, "converged": True})
    pd.DataFrame(methods).to_csv(model / "model_method_summary.csv", index=False)
    (model / "pricefm_stage_r93_quantile_run_summary.json").write_text(json.dumps({
        "status": "completed_validation_surface",
        "test_loaded": False,
        "exal_surface_numerically_eligible": exal_eligible,
    }))
    args = module.parser().parse_args([
        "close-quantile", "--output-root", str(output),
    ])
    return module, args


def test_quantile_closeout_selects_only_a_complete_eligible_family(tmp_path):
    module, args = make_quantile_closeout(tmp_path, exal_eligible=True)
    summary = module.run(args)
    assert summary["selected_family"] == "exal"
    assert summary["status"] == "validation_family_frozen_awaiting_test_audit_authorization"
    assert summary["test_opened"] is False
    assert summary["test_access_authorized"] is False
    assert summary["registry_mutation_authorized"] is False


def test_quantile_closeout_falls_back_to_al_and_rejects_test_rows(tmp_path):
    module, args = make_quantile_closeout(tmp_path / "fallback", exal_eligible=False)
    assert module.run(args)["selected_family"] == "al"

    module, args = make_quantile_closeout(tmp_path / "contaminated", add_test=True)
    with pytest.raises(RuntimeError, match="forbidden test evidence"):
        module.run(args)


def test_quantile_runner_uses_public_api_and_branched_warm_start():
    module = load_script()
    assert module.WARM_PARENT_BY_TAU == {
        "0.50": "outer_normal_rhs", "0.45": "0.50", "0.25": "0.45",
        "0.10": "0.25", "0.55": "0.50", "0.75": "0.55", "0.90": "0.75",
    }
    text = R_RUNNER.read_text()
    assert 'getExportedValue("exdqlm", "exalStaticLDVB")' in text
    assert 'status = "preflight_passed_not_fitted"' in text
    assert 'al_states[[tau_key]]' in text
    assert 'parent <- as.character(expected_parents[[tau_key]])' in text
    assert 'getExportedValue("exdqlm", "exal_ldvb_fit")' not in text
    assert 'exdqlm::qdesn_fit_vb' not in text
    assert 'test_loaded = FALSE' in text
