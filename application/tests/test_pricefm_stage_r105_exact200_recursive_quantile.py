from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


def load(name: str):
    path = SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


WORKER = load("354_run_pricefm_stage_r105_exact200_quantile_case.py")
CLOSEOUT = load("355_closeout_pricefm_stage_r105_exact200_recursive_quantile.py")
ORCHESTRATOR = load("356_orchestrate_pricefm_stage_r105_exact200_recursive_quantile.py")


def test_score_surface_uses_all_quantiles_origins_and_horizons() -> None:
    truth = np.zeros((2, 96))
    prediction = np.zeros((7, 2, 96))
    result = WORKER.score_surface(truth, prediction)
    assert result["validation_AQL_original"] == 0.0
    assert result["n_loss_atoms"] == 2 * 96 * 7
    assert result["coverage_10_90"] == 1.0


def test_fold1_selects_one_complete_family_policy_per_region() -> None:
    rows = []
    for index in range(38):
        region = f"R{index:02d}"
        for fold in (1, 2, 3):
            for family in ("al", "exal"):
                for policy in ("rhs", "ridge"):
                    aql = 3.0
                    if family == "al" and policy == "rhs":
                        aql = 2.0
                    if fold == 1 and family == "exal" and policy == "ridge":
                        aql = 1.0
                    rows.append({
                        "region": region,
                        "fold": fold,
                        "family": family,
                        "policy": policy,
                        "validation_AQL_original": aql,
                        "numerically_eligible": not (
                            index == 0 and family == "exal" and policy == "ridge" and fold == 2
                        ),
                        "all_atoms_exact_200": True,
                    })
    decisions = CLOSEOUT.select_combinations(pd.DataFrame(rows))
    first = decisions[decisions.region.eq("R00")].iloc[0]
    second = decisions[decisions.region.eq("R01")].iloc[0]
    assert (first.selected_family, first.selected_policy) == ("al", "rhs")
    assert (second.selected_family, second.selected_policy) == ("exal", "ridge")
    assert decisions.selection_split.eq("fold1_validation_only").all()
    assert not decisions.per_fold_or_quantile_mixing.any()


def test_region_without_complete_numerical_combination_is_preserved() -> None:
    rows = []
    for fold in (1, 2, 3):
        rows.append({
            "region": "X",
            "fold": fold,
            "family": "al",
            "policy": "self",
            "validation_AQL_original": 1.0,
            "numerically_eligible": False,
            "all_atoms_exact_200": True,
        })
    decision = CLOSEOUT.select_combinations(pd.DataFrame(rows)).iloc[0]
    assert decision.decision_status == "no_numerically_eligible_combination"
    assert pd.isna(decision.selected_family)


def test_raw_elbo_summary_requires_exactly_200_rows() -> None:
    trace = pd.DataFrame({
        "iter": np.arange(1, 201),
        "elbo": np.linspace(-100, -1, 200),
        "delta_elbo": np.repeat(0.01, 200),
    })
    summary = CLOSEOUT.summarize_trace(trace)
    assert summary["trace_rows"] == 200
    assert summary["decrease_count"] == 0
    try:
        CLOSEOUT.summarize_trace(trace.iloc[:-1])
    except RuntimeError as error:
        assert "exact-200" in str(error)
    else:
        raise AssertionError("199-row trace passed the exact-200 gate")


def test_early_stop_comparison_is_keyed_by_family_and_policy(tmp_path: Path) -> None:
    early = pd.DataFrame({
        "region": ["BE"], "fold": [1], "family": ["al"],
        "policy": ["quantile_curve_self"], "AQL": [4.0],
    })
    source = tmp_path / "early.csv"
    early.to_csv(source, index=False)
    current = pd.DataFrame({
        "region": ["BE", "BE"], "fold": [1, 1], "family": ["al", "exal"],
        "policy": ["quantile_curve_self", "quantile_curve_self"],
        "validation_AQL_original": [3.5, 1.0],
    })
    result = CLOSEOUT.compare_early_stop(current, source)
    assert len(result) == 1
    assert result.iloc[0].exact200_minus_early_stop_AQL == -0.5


def test_exact_iteration_and_forecast_firewalls_are_wired() -> None:
    prep = (SCRIPTS / "352_prepare_pricefm_stage_r105_exact200_recursive_quantile.py").read_text()
    r_source = (SCRIPTS / "353_run_pricefm_stage_r105_exact200_quantile_case.R").read_text()
    worker = (SCRIPTS / "354_run_pricefm_stage_r105_exact200_quantile_case.py").read_text()
    orchestrator = (SCRIPTS / "356_orchestrate_pricefm_stage_r105_exact200_recursive_quantile.py").read_text()
    assert '"min_iter": 200' in prep
    assert '"max_iter": 200' in prep
    assert '"patience": 1' in prep
    assert "exdqlm.vb.min_iter = 200L" in r_source
    assert "exdqlm.vb.patience = 1L" in r_source
    assert "retry_max_iter" not in r_source
    assert "R105 fit violated the exact-200 iteration contract" in r_source
    assert "recursive_quantile_curve_forecast" in worker
    assert "paired_quantile_prediction" not in worker
    assert "RUN_PRICEFM_R105_EXACT200_RECURSIVE_QUANTILE" in orchestrator


def test_cpu_gate_keeps_one_logical_thread_per_physical_core(monkeypatch) -> None:
    snapshot = {25: 0.0, 57: 0.0, 26: 0.0}
    monkeypatch.setattr(ORCHESTRATOR, "cpu_snapshot", lambda: snapshot)
    monkeypatch.setattr(
        ORCHESTRATOR,
        "physical_core",
        lambda cpu: "socket0:core25" if cpu in {25, 57} else "socket0:core26",
    )
    cpus, _ = ORCHESTRATOR.choose_cpus(2, 20.0, "25,57,26")
    assert cpus == [25, 26]
