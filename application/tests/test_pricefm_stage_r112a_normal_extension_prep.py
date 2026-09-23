from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/385_prepare_pricefm_stage_r112a_normal_extension.py"
SPEC = importlib.util.spec_from_file_location("pricefm_r112a", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def test_all_region_neighbor_signal_is_training_only() -> None:
    raw = pd.DataFrame({
        "time_utc": pd.date_range("2023-01-01", periods=6, freq="h", tz="UTC"),
        "AA-price": [1, 2, 4, 7, 11, 16],
        "BB-price": [2, 4, 8, 14, 22, 32],
    })
    original = MODULE.graph_adj_matrix
    MODULE.graph_adj_matrix = lambda: {"AA": ["AA", "BB"], "BB": ["AA", "BB"]}
    try:
        result = MODULE.all_region_neighbor_signal(raw, ["AA", "BB"])
    finally:
        MODULE.graph_adj_matrix = original
    assert len(result) == 2
    assert set(result.region) == {"AA", "BB"}
    assert set(result.selection_cutoff_exclusive) == {"2024-09-01"}
    assert result.change_rank.eq(1).all()
    assert result.top3_change_neighbor.all()


def test_real_r112a_package_is_complete_reproducible_and_not_launched(tmp_path: Path) -> None:
    output = tmp_path / "prep"
    campaign = tmp_path / "campaign"
    args = MODULE.parser().parse_args([
        "--code-root", str(ROOT),
        "--output-dir", str(output),
        "--campaign-root", str(campaign),
    ])
    summary = MODULE.run(args)
    assert summary["status"] == "completed_launch_prep_not_launched"
    assert summary["regions_reused_from_r100"] == 17
    assert summary["regions_prepared"] == 21
    assert summary["candidate_generator_regression_regions"] == 17
    assert summary["ridge_candidates"] == 5040
    assert summary["ridge_inner_fit_cells"] == 15120
    assert summary["maximum_rhs_candidates"] == 1890
    assert summary["maximum_rhs_inner_fit_cells"] == 5670
    assert summary["host_counts"] == {"jerez": 14, "muscat": 7}
    assert summary["selection_uses_outer_validation"] is False
    assert summary["selection_uses_test"] is False
    assert summary["model_fit_started"] is False
    assert summary["launch_started"] is False
    assert summary["quantile_fit_started"] is False
    assert summary["joint_fit_started"] is False
    assert summary["mcmc_fit_started"] is False
    assert summary["registry_mutated"] is False
    assert summary["article_mutated"] is False
    assert not campaign.exists()

    regression = pd.read_csv(output / "pricefm_stage_r112a_r100_regression_gate.csv")
    assert len(regression) == 17
    assert regression.candidate_ids_identical.all()
    assert regression.semantic_fingerprints_identical.all()

    launch = pd.read_csv(output / "pricefm_stage_r112a_normal_extension_launch_manifest.csv")
    assert len(launch) == 21
    assert launch.region.nunique() == 21
    assert launch.candidate_count.eq(240).all()
    assert launch.host.eq("jerez").sum() == 14
    assert launch.host.eq("muscat").sum() == 7
    assert not launch.test_access_authorized.any()
    assert not launch.launch_authorized.any()
    for row in launch.itertuples(index=False):
        assert Path(row.grid_path).is_file()
        assert Path(row.candidate_manifest).is_file()
        candidates = pd.read_csv(row.candidate_manifest)
        assert len(candidates) == 240
        assert candidates.semantic_fingerprint.is_unique
        assert candidates.selection_eligible.all()
        assert set(candidates.selection_split) == {"fold1_train_internal_temporal_validation"}
        assert not candidates.test_access_authorized.any()

    gates = pd.read_csv(output / "pricefm_stage_r112a_launch_prep_gates.csv")
    assert gates.passed.all()
    control = json.loads((output / "pricefm_stage_r112a_launch_control.json").read_text())
    assert control["launch_authorized"] is False
    assert control["runtime_cpu_preflight_required"] is True
    assert control["one_model_per_logical_cpu"] is True
    assert control["thread_count_per_model"] == 1
    assert control["quantile_fit_authorized"] is False
    assert control["registry_mutation_authorized"] is False
    assert control["article_mutation_authorized"] is False

    second = MODULE.run(args)
    assert second == summary


def test_source_has_no_model_execution_path() -> None:
    text = SCRIPT.read_text()
    assert '"model_fit_started": False' in text
    assert '"launch_started": False' in text
    assert '"launch_authorized": False' in text
    assert '"registry_mutated": False' in text
    assert '"article_mutated": False' in text
    assert "subprocess.run" not in text
    assert "Popen" not in text
    assert "ThreadPoolExecutor" not in text

