from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from pricefm_common import sha256_file  # noqa: E402


def load(relative: str, name: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PREP = load(
    "application/scripts/pricefm/403_prepare_pricefm_stage_r118_quantile_repair.py",
    "pricefm_r118_prep",
)
RUNNER = load(
    "application/scripts/pricefm/405_run_pricefm_stage_r118_quantile_repair.py",
    "pricefm_r118_runner",
)
ENGINE = load(
    "application/scripts/pricefm/pricefm_r118_engine.py",
    "pricefm_r118_engine_test",
)
CONTINUATION = load(
    "application/scripts/pricefm/407_continue_pricefm_stage_r118_quantile_repair.py",
    "pricefm_r118_continuation",
)
COMPARISON = load(
    "application/scripts/pricefm/408_closeout_pricefm_stage_r118_comparison.py",
    "pricefm_r118_comparison",
)


def terminal(output: Path, *, arm: dict, passed: bool, target: str) -> None:
    output.mkdir(parents=True)
    artifact = output / "diagnostics.json"
    artifact.write_text('{"finite":true}')
    value = {
        "status": "completed_r118_mechanism_probe",
        "arm_id": arm["arm_id"],
        "family": arm["family"],
        "formal_converged": False,
        "external_gate_passed": passed,
        "finite_core": True,
        "bounded": passed,
        "sigma": 0.01 if passed else 1.0e8,
        "gamma": 0.0 if arm["family"] == "al" else 1.0,
        "relative_state_tail_max": 1.0e-5 if passed else 1.0e5,
        "relative_sigma_tail_max": 1.0e-7 if passed else 1.0e5,
        "relative_elbo_tail_max": 1.0e-8 if passed else 1.0,
        "post_release_updates": 40,
        "train_seconds": 1.0,
        "posterior_target_sha256": target,
        "test_opened": False,
        "artifacts": [{"path": artifact.name, "sha256": sha256_file(artifact)}],
    }
    (output / "terminal.json").write_text(json.dumps(value))


def test_probe_arms_change_schedule_only_within_exal_family() -> None:
    frame = pd.DataFrame(PREP.ARMS)
    assert len(frame) == 4
    assert frame.family.value_counts().to_dict() == {"exal": 3, "al": 1}
    assert set(frame.loc[frame.family.eq("exal"), "sigmagam_freeze_warmup_iters"]) == {10, 100}
    assert set(frame.loc[frame.family.eq("exal"), "rhs_freeze_tau_warmup_iters"]) == {0, 100}


def test_probe_closeout_selects_passed_lowest_priority_exal_schedule(tmp_path: Path) -> None:
    rows = []
    for arm in PREP.ARMS:
        output = tmp_path / str(arm["arm_id"])
        passed = arm["family"] == "al" or arm["arm_id"] in {
            "exal_delayed_sigmagam", "exal_delayed_sigmagam_rhs",
        }
        target = "al-target" if arm["family"] == "al" else "exal-target"
        terminal(output, arm=arm, passed=passed, target=target)
        rows.append({
            **arm,
            "output_dir": str(output),
            "posterior_target_sha256": target,
        })
    summary = RUNNER.closeout(pd.DataFrame(rows), tmp_path / "campaign")
    assert summary["decision"] == "continue_al_and_exal"
    assert summary["selected_exal_schedule"] == "exal_delayed_sigmagam_rhs"
    assert summary["posterior_target_sha256_by_family"] == {
        "al": "al-target", "exal": "exal-target",
    }
    assert summary["test_opened"] is False


def test_probe_runner_preserves_small_tau0_and_records_damping_limitation() -> None:
    source = (SCRIPTS / "404_probe_pricefm_stage_r118_quantile_mechanism.R").read_text()
    assert 'digits = 17' in source
    assert 'structured_postwarmup_damping_effective = FALSE' in source
    assert 'initializer_changes_prior = FALSE' in source
    assert 'test_access_authorized' in source


def test_runner_rejects_one_target_hash_claimed_for_both_families(tmp_path: Path) -> None:
    rows = []
    for arm in PREP.ARMS:
        output = tmp_path / str(arm["arm_id"])
        terminal(output, arm=arm, passed=True, target="incorrect-common-target")
        rows.append({
            **arm,
            "output_dir": str(output),
            "posterior_target_sha256": "incorrect-common-target",
        })
    try:
        RUNNER.closeout(pd.DataFrame(rows), tmp_path / "campaign")
    except RuntimeError as error:
        assert "must not claim the same posterior target" in str(error)
    else:
        raise AssertionError("AL/exAL common posterior target was not rejected")


def test_external_gate_is_scale_aware_for_large_coefficients() -> None:
    trace = pd.DataFrame({
        "iter": np.arange(1, 41),
        "elbo": np.full(40, 2.0e5),
        "delta_elbo": np.full(40, 1.0e-4),
        "delta_sigma": np.full(40, 1.0e-10),
        "delta_state": np.full(40, 0.05),
    })
    large = ENGINE.relative_tail_gate(np.asarray([5000.0]), trace, 0.01, 0.0)
    scaled_trace = trace.copy()
    scaled_trace["delta_state"] /= 100
    small = ENGINE.relative_tail_gate(np.asarray([50.0]), scaled_trace, 0.01, 0.0)
    assert large["external_gate_passed"] is True
    assert small["external_gate_passed"] is True
    assert np.isclose(large["relative_state_tail_max"], small["relative_state_tail_max"])


def test_production_controller_has_resume_lock_and_no_promotion_authority() -> None:
    source = (SCRIPTS / "407_continue_pricefm_stage_r118_quantile_repair.py").read_text()
    assert "LOCK_EX | fcntl.LOCK_NB" in source
    assert '"registry_mutated": False' in source
    assert '"article_mutated": False' in source
    assert '"joint_model_fitted": False' in source
    assert '"mcmc_fitted": False' in source
    assert 'extended_variant_authorized": False' in source


def test_full_target_al_gate_requires_every_completed_atom_and_central_fold_coverage() -> None:
    rows = [
        {"fold": fold, "tau": tau, "reason": "passed_external_gate", "admissible": True}
        for fold in (1, 2, 3) for tau in (0.45, 0.50, 0.55)
    ]
    rows.extend([
        {"fold": 1, "tau": 0.25, "reason": "passed_external_gate", "admissible": True},
        {"fold": 2, "tau": 0.25, "reason": "passed_external_gate", "admissible": True},
    ])
    passed = CONTINUATION.full_target_al_continuation_gate(pd.DataFrame(rows))
    assert passed["authorized"] is True
    assert passed["completed_full_target_al_atoms"] == 11
    failed_rows = list(rows)
    failed_rows[-1] = {**failed_rows[-1], "admissible": False}
    failed = CONTINUATION.full_target_al_continuation_gate(pd.DataFrame(failed_rows))
    assert failed["authorized"] is False
    assert failed["exal_authorized"] is False


def test_comparison_pools_with_loss_atom_weights_and_keeps_context_separate() -> None:
    frame = pd.DataFrame([
        {
            "reference": "candidate", "fold": 1, "AQL": 1.0,
            "n_loss_atoms": 1, "comparison_role": "aligned", "directly_comparable": True,
        },
        {
            "reference": "candidate", "fold": 2, "AQL": 3.0,
            "n_loss_atoms": 3, "comparison_role": "aligned", "directly_comparable": True,
        },
        {
            "reference": "context", "fold": 1, "AQL": 0.5,
            "n_loss_atoms": 4, "comparison_role": "final_test", "directly_comparable": False,
        },
    ])
    result = COMPARISON.pooled(frame).set_index("reference")
    assert result.loc["candidate", "mean_fold_AQL"] == 2.0
    assert result.loc["candidate", "pooled_AQL"] == 2.5
    assert bool(result.loc["candidate", "directly_comparable"]) is True
    assert bool(result.loc["context", "directly_comparable"]) is False


def test_comparison_source_blocks_promotion_and_labels_pricefm_as_context() -> None:
    source = (SCRIPTS / "408_closeout_pricefm_stage_r118_comparison.py").read_text()
    assert '"promotion_authorized": False' in source
    assert '"authority_context_is_directly_comparable": False' in source
    assert '"cached_PriceFM_final_test"' in source
