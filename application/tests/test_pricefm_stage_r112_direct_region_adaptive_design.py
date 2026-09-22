from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/384_design_pricefm_stage_r112_direct_region_adaptive.py"
SPEC = importlib.util.spec_from_file_location("pricefm_r112", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def test_units_are_normalized_across_csv_spellings() -> None:
    assert MODULE.units_tuple("[96,64,48]") == (96, 64, 48)
    assert MODULE.units_tuple("[96, 64, 48]") == (96, 64, 48)
    assert MODULE.units_tuple([48, 48]) == (48, 48)


def test_host_assignment_is_deterministic_and_bounded() -> None:
    regions = ["AT", "BE", "BG", "CZ", "DE_LU"]
    first = MODULE.assigned_hosts(regions, 3)
    second = MODULE.assigned_hosts(list(reversed(regions)), 3)
    assert first == second
    assert list(first.values()).count("jerez") == 3
    assert list(first.values()).count("muscat") == 2


def test_real_frozen_design_is_complete_and_read_only(tmp_path: Path) -> None:
    summary = MODULE.run(ROOT, tmp_path)
    assert summary["status"] == "completed_direct_region_adaptive_design"
    assert summary["regions"] == 38
    assert summary["complete_surface_cases"] == 114
    assert summary["r100_normal_winners_reused"] == 17
    assert summary["r112_normal_extension_regions"] == 21
    assert summary["new_ridge_inner_fit_cells_max"] == 15120
    assert summary["new_rhs_inner_fit_cells_max"] == 5670
    assert summary["normal_outer_refit_cells"] == 114
    assert summary["quantile_family_selection_fit_cells_max"] == 1596
    assert summary["quantile_outer_fit_cells_max"] == 798
    assert summary["forecast_operator"] == "direct_96_horizon_no_recursive_target_lags"
    assert summary["selection_uses_outer_validation"] is False
    assert summary["selection_uses_test"] is False
    assert summary["row_level_fallback_authorized"] is False
    assert summary["model_fit_started"] is False
    assert summary["launch_started"] is False
    assert summary["launch_yaml_written"] is False
    assert summary["joint_fit_authorized"] is False
    assert summary["mcmc_authorized"] is False
    assert summary["registry_mutated"] is False
    assert summary["article_mutated"] is False

    inventory = pd.read_csv(tmp_path / "pricefm_stage_r112_region_inventory.csv")
    assert len(inventory) == 38
    assert inventory.region.nunique() == 38
    assert inventory.normal_screen_fit_required.sum() == 21
    assert (~inventory.normal_screen_fit_required).sum() == 17
    assert inventory.normal_winner_specification_reusable.sum() == 17
    assert not inventory.normal_posterior_object_reusable.any()
    assert inventory.outer_normal_refit_required.all()
    assert inventory.candidate_manifest_sha256.str.len().eq(64).all()

    candidates = pd.read_csv(tmp_path / "pricefm_stage_r112_candidate_bank_audit.csv")
    assert len(candidates) == 38
    assert candidates.candidate_count.eq(240).all()
    assert candidates.authority_geometry_present.all()
    assert not candidates.test_access_authorized.any()

    execution = pd.read_csv(tmp_path / "pricefm_stage_r112_execution_partition.csv")
    assert execution.ridge_inner_fit_cells.sum() == 15120
    assert execution.rhs_inner_fit_cells_max.sum() == 5670
    assert execution.normal_outer_fit_cells.sum() == 114
    assert execution.quantile_family_selection_fit_cells_max.sum() == 1596
    assert execution.quantile_outer_fit_cells_max.sum() == 798
    assert execution.normal_screen_host.eq("jerez").sum() == 14
    assert execution.normal_screen_host.eq("muscat").sum() == 7
    assert execution.normal_screen_host.eq("reuse").sum() == 17
    assert execution.quantile_host.eq("jerez").sum() == 26
    assert execution.quantile_host.eq("muscat").sum() == 12

    search = json.loads((tmp_path / "pricefm_stage_r112_normal_search_contract.json").read_text())
    quantile = json.loads((tmp_path / "pricefm_stage_r112_quantile_contract.json").read_text())
    assert search["test_or_outer_fold_metrics_may_select"] is False
    assert search["row_level_fallback_authorized"] is False
    assert quantile["forecast_operator"] == "direct_96_horizon_no_recursive_target_lags"
    assert quantile["families"] == ["AL_RHS_VB", "exAL_RHS_VB_structured_M0"]
    assert quantile["launch_authorized"] is False

    stages = pd.read_csv(tmp_path / "pricefm_stage_r112_stage_plan.csv")
    assert stages.iloc[0].status == "complete"
    assert set(stages.iloc[1:].status) == {"blocked"}
    assert not list(tmp_path.rglob("*.yaml"))
    assert not list(tmp_path.rglob("*.yml"))


def test_source_has_no_fit_launch_or_mutation_path() -> None:
    text = SCRIPT.read_text()
    assert '"model_fit_started": False' in text
    assert '"launch_started": False' in text
    assert '"launch_yaml_written": False' in text
    assert '"registry_mutated": False' in text
    assert '"article_mutated": False' in text
    assert "subprocess.run" not in text
    assert "ProcessPoolExecutor" not in text
    assert "yaml.safe_dump" not in text
