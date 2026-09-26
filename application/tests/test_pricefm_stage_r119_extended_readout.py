from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


def load(relative: str, name: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PREP = load(
    "application/scripts/pricefm/409_prepare_pricefm_stage_r119_extended_readout.py",
    "pricefm_r119_prep_test",
)
RUN = load(
    "application/scripts/pricefm/411_run_pricefm_stage_r119_extended_readout.py",
    "pricefm_r119_run_test",
)
COMPARISON = load(
    "application/scripts/pricefm/412_closeout_pricefm_stage_r119_comparison.py",
    "pricefm_r119_comparison_test",
)


def decision() -> dict:
    return {
        "eligible_operators": ["path_specific", "mean_feature"],
        "thresholds": {
            "maximum_AQL": 20.91,
            "maximum_late_AQL": 28.19,
            "maximum_median_MAE": 50.37,
            "minimum_interval_80_coverage": 0.40,
            "maximum_interval_80_coverage": 0.95,
            "minimum_interval_80_width": 20.0,
            "maximum_interval_80_width": 150.0,
            "maximum_crossing_rate": 0.10,
        },
    }


def metric(operator: str, **overrides: float) -> dict:
    value = {
        "fold": 1, "operator": operator, "AQL": 12.0, "late_AQL": 18.0,
        "median_MAE": 25.0, "interval_80_coverage": 0.75,
        "interval_80_width": 70.0, "crossing_rate": 0.0,
    }
    value.update(overrides)
    return value


def test_extended_tau0_selection_uses_frozen_rank_not_outer_validation() -> None:
    ranking = pd.DataFrame([
        {"rank": 2, "tau0": 1.0e-5, "multiplier": 1, "mean_AQL": 0.4, "mean_late_AQL": 1.0, "worst_AQL": 0.9},
        {"rank": 1, "tau0": 7.5e-5, "multiplier": 4, "mean_AQL": 0.41, "mean_late_AQL": 1.1, "worst_AQL": 1.0},
    ])
    selected = PREP.selected_extended_tau0(ranking)
    assert selected["rank"] == 1
    assert selected["tau0"] == 7.5e-5


def test_fold1_gate_selects_only_admissible_quantile_operators() -> None:
    frame = pd.DataFrame([
        metric("path_specific", AQL=12.1),
        metric("mean_feature", AQL=12.0),
        metric("normal_driver", AQL=1.0, interval_80_width=1000.0),
    ])
    result = RUN.evaluate_fold1_gate(frame, decision())
    assert result["status"] == "passed"
    assert result["selected_operator"] == "mean_feature"
    assert result["continue_folds_2_3"] is True
    assert result["promotion_authorized"] is False


def test_fold1_gate_rejects_collapsed_intervals_even_with_good_aql() -> None:
    frame = pd.DataFrame([
        metric("path_specific", AQL=8.0, interval_80_coverage=0.05, interval_80_width=5.0),
        metric("mean_feature", AQL=8.1, interval_80_coverage=0.06, interval_80_width=6.0),
        metric("normal_driver", AQL=7.0),
    ])
    result = RUN.evaluate_fold1_gate(frame, decision())
    assert result["status"] == "failed"
    assert result["checks"]["coverage_lower"] is False
    assert result["checks"]["width_lower"] is False
    assert result["continue_folds_2_3"] is False
    assert result["retuning_authorized"] is False


def test_cpu_parser_is_explicit_and_unique() -> None:
    assert RUN.parse_cpus("17-19,22") == [17, 18, 19, 22]
    try:
        RUN.parse_cpus("17,17")
    except ValueError:
        pass
    else:
        raise AssertionError("duplicate CPU assignment was accepted")


def test_normal_contract_uses_canonical_test_blind_split(tmp_path: Path) -> None:
    campaign = tmp_path / "campaign"
    stats = campaign / "extended/full_folds/fold=1/normal_stats"
    stats.mkdir(parents=True)
    (stats / "terminal.json").write_text(json.dumps({
        "status": "completed_causal_sufficient_statistics",
        "test_opened": False,
    }))
    path = RUN.normal_contract(
        1,
        {"tau0": 7.5e-5},
        {"normal_runtime": "/tmp/exdqlm"},
        campaign,
        tmp_path,
    )
    contract = json.loads(path.read_text())
    assert contract["selection_split"] == "train_validation_only"
    assert contract["test_access_authorized"] is False


def test_r119_quantile_runner_requires_extended_exact_cran_al_only() -> None:
    source = (SCRIPTS / "410_fit_pricefm_stage_r119_quantile_atom.R").read_text()
    assert '!identical(config$family, "al")' in source
    assert '!identical(config$readout, "extended_all_layers")' in source
    assert 'expected_version = "1.1.1"' in source
    assert 'digits = 17' in source
    assert 'prior_center_from_initializer = FALSE' in source
    assert 'exal_fitted = FALSE' in source


def test_controller_preserves_nested_order_and_hard_firewalls() -> None:
    assert RUN.WARM_LEVELS == ((0.50,), (0.45, 0.55), (0.25, 0.75), (0.10, 0.90))
    assert RUN.WARM_PARENT[0.10] == 0.25
    source = (SCRIPTS / "411_run_pricefm_stage_r119_extended_readout.py").read_text()
    assert "LOCK_EX | fcntl.LOCK_NB" in source
    assert '"exal_authorized": False' in source
    assert '"promotion_authorized": False' in source
    assert '"joint_model_fitted": False' in source
    assert '"mcmc_fitted": False' in source


def test_r119_comparison_geometry_uses_seven_quantiles(tmp_path: Path) -> None:
    campaign = tmp_path / "campaign"
    (campaign / "closeout").mkdir(parents=True)
    (campaign / "campaign_terminal.json").write_text(json.dumps({
        "status": "completed_extended_bg_not_promoted", "test_opened": False,
    }))
    pd.DataFrame([
        {"fold": fold, "AQL": 10.0 + fold} for fold in (1, 2, 3)
    ]).to_csv(campaign / "closeout/fold1_frozen_choice_metrics.csv", index=False)
    expected = {1: 122 * 96 * 7, 2: 120 * 96 * 7, 3: 123 * 96 * 7}
    for fold, origins in ((1, 122), (2, 120), (3, 123)):
        target = campaign / f"forecasts/family=al/fold={fold}"
        target.mkdir(parents=True)
        np.savez_compressed(
            target / "predictions.npz", truth=np.zeros((origins, 96)),
            quantiles=np.asarray([0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]),
        )
    rows = COMPARISON.r119_rows(campaign)
    assert rows.set_index("fold").n_loss_atoms.to_dict() == expected
    assert rows.directly_comparable.astype(bool).all()


def test_plan_records_r118_negative_result_and_r119_stop_rule() -> None:
    plan = (ROOT / "local_trackers/pricefm_stage_r117_r118_quantile_repair_master_plan_20260925.md").read_text()
    assert "Pooled outer-validation AQL: 24.68481858060743" in plan
    assert "R119 justified successor" in plan
    assert "stop_without_retuning" in (SCRIPTS / "409_prepare_pricefm_stage_r119_extended_readout.py").read_text()
