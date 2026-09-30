from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
sys.path.insert(0, str(SCRIPTS))

from pricefm_r122_engine import paired_cap_predictive_stability


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec); assert spec and spec.loader
    spec.loader.exec_module(module); return module


EVALUATION = _load("pricefm_r122_evaluation_test", "425_prepare_pricefm_stage_r122_evaluation_contract.py")
PREP_STAGE0B = _load("pricefm_r122_stage0b_prep_test", "426_prepare_pricefm_stage_r122_stage0b.py")


def _write_pair(root: Path, beta: np.ndarray, covariance: np.ndarray, target: str = "same") -> Path:
    root.mkdir(parents=True)
    beta.astype("<f8").tofile(root / "beta_mean.bin")
    covariance.astype("<f8").tofile(root / "beta_cov.bin")
    (root / "terminal.json").write_text(json.dumps({"status": "completed_r121_quantile_atom",
                                                      "posterior_target_sha256": target, "test_opened": False}))
    (root / "diagnostics.json").write_text(json.dumps({"external_gate_passed": False, "finite_core": True,
        "relative_sigma_tail_max": 1e-9, "relative_elbo_tail_max": 1e-10}))
    (root / "parameter_summary.json").write_text(json.dumps({"sigma": 1.0}))
    return root


def _design(root: Path) -> Path:
    root.mkdir(parents=True)
    x = np.linspace(-2, 2, 200)
    matrix = np.column_stack([np.ones_like(x), x, 2 * x])
    response = np.sin(x)
    matrix.astype("<f8").tofile(root / "X.bin"); response.astype("<f8").tofile(root / "y.bin")
    (root / "design.json").write_text(json.dumps({"n": len(x), "p": matrix.shape[1]}))
    (root / "terminal.json").write_text(json.dumps({"status": "completed_r121_quantile_design", "test_opened": False}))
    return root


def test_paired_cap_gate_accepts_null_direction_but_rejects_predictive_motion(tmp_path):
    design = _design(tmp_path / "design"); covariance = np.eye(3) * 0.01
    lower = _write_pair(tmp_path / "lower", np.zeros(3), covariance)
    null_upper = _write_pair(tmp_path / "null_upper", np.array([0.0, 2.0, -1.0]), covariance)
    stable = paired_cap_predictive_stability(design, lower, null_upper)
    assert stable["passed"] is True
    assert stable["location_delta_rms_response_scale"] < 1e-12
    assert stable["near_null_beta_delta_fraction"] > 0.999
    moving_upper = _write_pair(tmp_path / "moving_upper", np.array([0.0, 1.0, 0.0]), covariance)
    unstable = paired_cap_predictive_stability(design, lower, moving_upper)
    assert unstable["passed"] is False
    assert unstable["checks"]["location_rms_stable"] is False


def test_evaluation_contract_records_historical_opening_and_no_pristine_holdout(tmp_path):
    artifact = tmp_path / "artifact"; config = artifact / "application/config"; config.mkdir(parents=True)
    payload = {"pricefm": {"splits": [
        {"fold": 1, "train": ["2022-01-01", "2024-09-01"], "val": ["2024-09-01", "2025-01-01"], "test": ["2025-01-01", "2025-05-01"]},
        {"fold": 2, "train": ["2022-01-01", "2025-01-01"], "val": ["2025-01-01", "2025-05-01"], "test": ["2025-05-01", "2025-09-01"]},
        {"fold": 3, "train": ["2022-01-01", "2025-05-01"], "val": ["2025-05-01", "2025-09-01"], "test": ["2025-09-01", "2026-01-01"]},
    ]}}
    (config / "pricefm_data_pipeline.yaml").write_text(yaml.safe_dump(payload))
    metric_root = artifact / "application/data_local/pricefm/campaigns" / EVALUATION.R97_TAG / "global_scoring/runs"
    closeout = artifact / "application/data_local/pricefm/campaigns" / EVALUATION.R97_TAG / "global_scoring/closeout"
    rows = []
    for region in ["BG", *[f"R{value:02d}" for value in range(36)]]:
        for fold in (1, 2, 3):
            metric = metric_root / f"region={region}/fold={fold}/score/test_metric.csv"
            metric.parent.mkdir(parents=True); metric.write_text("AQL\n1.0\n")
            rows.append({"path": str(metric), "sha256": "a" * 64})
    closeout.mkdir(parents=True); pd.DataFrame(rows).to_csv(closeout / "source_manifest.csv", index=False)
    output = tmp_path / "out"
    result = EVALUATION.run(argparse.Namespace(artifact_repo=artifact, code_root=artifact, output_dir=output))
    contract = json.loads((output / "evaluation_contract.json").read_text())
    assert result["status"] == "R122_EVALUATION_CONTRACT_READY"
    assert contract["historical_test_status"] == "HISTORICALLY_OPENED_NOT_PRISTINE"
    assert contract["fresh_holdout_available_in_current_snapshot"] is False
    assert contract["selection_protocol"]["fold2_or_fold3_validation_for_specification_selection"] is False


def test_stage0b_manifest_is_three_candidates_by_three_splits(tmp_path):
    campaign = tmp_path / "r121b"
    shortlist = pd.DataFrame({"candidate_id": ["A", "B", "C"], "tau0": [1e-4, 2e-4, 3e-4]})
    for candidate in shortlist.candidate_id:
        for split in (1, 2, 3):
            root = campaign / f"al_internal/{candidate}/split={split}"
            (root / "design").mkdir(parents=True); (root / "quantiles/contracts").mkdir(parents=True)
            (root / "design/terminal.json").write_text(json.dumps({"status": "completed_r121_quantile_design"}))
            parent = tmp_path / f"normal_{candidate}_{split}"; parent.mkdir(); (parent / "terminal.json").write_text("{}")
            (root / "quantiles/contracts/tau=0.50.json").write_text(json.dumps({"parent_dir": str(parent)}))
    manifest = PREP_STAGE0B.build_ladder_manifest(campaign, shortlist)
    assert len(manifest) == 9
    assert manifest.groupby("candidate_id").split.nunique().eq(3).all()


def test_stage0b_surface_preserves_firewalls_and_exact_final_cap():
    runner = (SCRIPTS / "427_run_pricefm_stage_r122_stage0b.py").read_text()
    fitter = (SCRIPTS / "420_fit_pricefm_stage_r121_quantile_atom.R").read_text()
    assert '"final_max_iter": 1000' in (SCRIPTS / "426_prepare_pricefm_stage_r122_stage0b.py").read_text()
    assert '"test_access_authorized": False' in runner
    assert "paired_cap_predictive_stability" in runner
    assert "selected_physical_cores_idle" in runner
    assert "python_runtime" in runner
    assert "R122_internal_selection" in fitter
    assert "test_metric" not in runner
