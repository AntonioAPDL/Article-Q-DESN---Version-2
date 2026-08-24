import ast
import csv
import importlib.util
from pathlib import Path
import sys

import numpy as np


SCRIPT = (
    Path(__file__).parents[1]
    / "scripts"
    / "pricefm"
    / "199_audit_pricefm_operational_postcloseout.py"
)
sys.path.insert(0, str(SCRIPT.parent))


def module():
    spec = importlib.util.spec_from_file_location("pricefm_operational_postcloseout", SCRIPT)
    loaded = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(loaded)
    return loaded


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def test_prediction_diagnostics_replays_pinball_and_calibration() -> None:
    audit = module()
    truth = np.zeros((2, 96), dtype=float)
    path = np.array([-2.0, -1.0, -0.1, 0.0, 0.1, 1.0, 2.0])
    prediction = np.broadcast_to(path, (2, 96, 7)).copy()
    result = audit.prediction_diagnostics(truth, prediction)

    assert np.isclose(result["case"]["AQL"], 0.99 / 7.0)
    assert result["case"]["AQCR"] == 0.0
    assert result["case"]["MAE"] == 0.0
    assert result["case"]["coverage_q10_q90"] == 1.0
    assert len(result["quantile_rows"]) == 7
    assert len(result["horizon_rows"]) == 4
    assert len(result["horizon_quantile_rows"]) == 28
    assert np.allclose(result["origin_AQL"], 0.99 / 7.0)


def test_circular_block_bootstrap_is_deterministic() -> None:
    audit = module()
    values = np.arange(1.0, 13.0)
    first = audit.circular_block_bootstrap(values, 500, 3, 1234)
    second = audit.circular_block_bootstrap(values, 500, 3, 1234)
    third = audit.circular_block_bootstrap(values, 500, 3, 5678)

    assert np.array_equal(first, second)
    assert not np.array_equal(first, third)
    low, high = np.quantile(first, [0.025, 0.975])
    assert low < values.mean() < high


def test_selector_evidence_never_promotes_sensitivity_only() -> None:
    audit = module()
    assert audit.classify_selector_evidence(True, True) == "tier_a_both_selectors_dual_reference"
    assert audit.classify_selector_evidence(True, False) == "tier_b_preregistered_primary_only"
    assert audit.classify_selector_evidence(False, True) == "sensitivity_only_not_promotable"
    assert audit.classify_selector_evidence(False, False) == "no_dual_reference_evidence"


def test_r56_is_blocked_when_old_candidate_loses_operational_comparator() -> None:
    audit = module()
    result = audit.r56_disposition(15.1138366768145, 14.692011396307796, True)

    assert result["prior_r56_launch_authorized"] is True
    assert result["m0_beats_operational_pricefm"] is False
    assert result["r56_launch_authorized_now"] is False
    assert result["decision"] == "superseded_do_not_launch"
    assert result["existing_r56_artifacts_mutated"] is False


def test_reference_lineage_detects_method_and_prediction_limitations(tmp_path: Path) -> None:
    audit = module()
    source = tmp_path / "source.csv"
    run_dir = tmp_path / "run"
    metric = run_dir / "cells" / "region=A" / "fold=1" / "model" / "metric_summary.csv"
    write_csv(source, [{
        "region": "A",
        "fold": 1,
        "qdesn_method_id": "qdesn_reported",
        "selected_method_id": "qdesn_validation_selected",
        "qdesn_AQL": 1.0,
        "run_dir": str(run_dir),
    }])
    write_csv(metric, [{
        "method_id": "qdesn_reported",
        "split": "test",
        "unit": "original",
        "AQL": 1.2,
    }])
    registry = tmp_path / "registry.csv"
    write_csv(registry, [{
        "region": "A",
        "fold": 1,
        "source_class": "fixture",
        "qdesn_method_id": "qdesn_reported",
        "qdesn_AQL": 1.0,
        "pricefm_AQL": 1.5,
        "registry_source_path": str(source),
        "registry_source_sha256": audit.sha256_file(source),
    }])
    horizons = tmp_path / "horizons.csv"
    write_csv(horizons, [
        {
            "region": "A",
            "fold": 1,
            "horizon_group": group,
            "horizon_delta_AQL_qdesn_minus_pricefm": 0.0,
        }
        for group, _, _ in audit.HORIZON_BLOCKS
    ])

    rows = audit.audit_reference_lineage(
        registry, horizons, tmp_path, audit.SourceLedger()
    )
    assert len(rows) == 1
    row = rows[0]
    assert row["authority_matches_source_reported_method"] is True
    assert row["authority_matches_source_validation_selected_method"] is False
    assert row["retained_metric_summary_exists"] is True
    assert row["retained_metric_matches_authority_qdesn_scalar"] is False
    assert row["retained_prediction_file_exists"] is False
    assert row["horizon_delta_evidence_available"] is True
    assert row["operational_paired_prediction_comparison_ready"] is False


def test_gate_ledger_separates_surface_freeze_from_paired_claims() -> None:
    audit = module()
    fits = [
        {"completed_fits": 9},
        {"completed_fits": 1047},
        {"completed_fits": 48},
    ]
    replay = [
        {
            "replay_pass": True,
            "anchors_match_frozen_window": True,
            "y_true_max_abs_diff_from_frozen_window": 0.0,
        }
        for _ in range(136)
    ]
    selectors = [
        {
            "primary_dual_reference_point_gate": True,
            "region_global_dual_reference_point_gate": True,
            "whole_surface_included_in_comparator_proposal": True,
        }
        for _ in range(114)
    ]
    references = [
        {
            "authority_matches_source_validation_selected_method": False,
            "qdesn_prediction_level_reference_ready": False,
            "cached_pricefm_prediction_level_reference_ready": False,
        }
        for _ in range(114)
    ]
    gates = audit.gate_rows(
        fits,
        replay,
        selectors,
        references,
        [{"m0_beats_operational_pricefm": False, "decision": "superseded_do_not_launch"}],
    )

    operational = [row for row in gates if row["scope"] == "operational_surface_freeze"]
    paired = [row for row in gates if row["scope"] == "paired_superiority_claim"]
    r56 = [row for row in gates if row["scope"] == "r56_launch"]
    assert operational and all(row["passed"] for row in operational)
    assert paired and not all(row["passed"] for row in paired)
    assert r56 == [next(row for row in gates if row["scope"] == "r56_launch")]
    assert r56[0]["passed"] is False


def test_comparator_proposal_keeps_all_rows_and_separates_harm_guards() -> None:
    audit = module()
    selectors = []
    cases = []
    for index in range(114):
        region = f"R{index:03d}"
        selectors.append({
            "region": region,
            "fold": 1,
            "evidence_tier": "tier_a_both_selectors_dual_reference",
        })
        loses_qdesn = index < 11
        cases.append({
            "selector": "cell_specific",
            "region": region,
            "fold": 1,
            "candidate_id": "candidate",
            "phase": "phase2",
            "canonical_degree": 1,
            "validation_AQL": 1.0,
            "AQL": 1.1 if loses_qdesn else 0.9,
            "current_qdesn_method_id": "qdesn",
            "current_qdesn_AQL": 1.0,
            "cached_pricefm_method_id": "cached",
            "cached_pricefm_AQL": 1.2,
            "comparison_outcome": (
                "current_qdesn_lower_only" if loses_qdesn else "operational_below_both"
            ),
            "beats_current_qdesn": not loses_qdesn,
            "delta_operational_minus_qdesn": 0.1 if loses_qdesn else -0.1,
        })

    proposal, guards = audit.comparator_ledgers(selectors, cases)
    assert len(proposal) == 114
    assert len(guards) == 11
    assert all(row["whole_surface_included"] for row in proposal)
    assert not any(row["individual_test_win_required_for_inclusion"] for row in proposal)
    assert all(not row["operational_comparator_row_excluded"] for row in guards)


def test_script_has_no_launcher_or_mutation_dependency() -> None:
    tree = ast.parse(SCRIPT.read_text(encoding="utf-8"))
    imports = {
        alias.name
        for node in ast.walk(tree)
        if isinstance(node, (ast.Import, ast.ImportFrom))
        for alias in node.names
    }
    source = SCRIPT.read_text(encoding="utf-8")

    assert "subprocess" not in imports
    assert "yaml" not in imports
    assert "atomic_save_npz" not in source
    assert '"registry_mutation_authorized": False' in source
    assert '"article_mutation_authorized": False' in source
    assert '"launch_authorized": False' in source
    assert "whole_surface_all_or_none" in source
