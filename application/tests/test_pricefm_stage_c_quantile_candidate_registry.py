"""Tests for freezing Stage-C median winners into quantile candidate queues."""

from pathlib import Path
import importlib.util
import sys
from types import SimpleNamespace

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script(name):
    path = SCRIPT_DIR / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def args(tmp_path):
    return SimpleNamespace(
        median_selection_dir=str(tmp_path / "median"),
        manifest_dir=str(tmp_path / "manifest"),
        cached_pricefm_root=str(tmp_path / "cached_pricefm"),
        output_dir=str(tmp_path / "out"),
        grid_id="unit_stage_c_quantile_candidates",
    )


def selected_row(region, fold, method="qdesn_exal_rhs_ns_exact_chunked", value=9.0):
    depth = 2 if "exal" in method else 1
    units = "[80, 80]" if depth == 2 else "[120]"
    return {
        "region": region,
        "fold": fold,
        "experiment_id": f"exp_{region.lower()}_{fold}",
        "selected_method_id": method,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "selection_metric_value": value,
        "selection_AQL": value,
        "feature_map": "window_reservoir_v1",
        "lag_window": 96,
        "depth": depth,
        "units": units,
        "alpha": 0.4 if depth == 2 else 0.5,
        "rho": 0.9,
        "input_scale": 0.35 if depth == 2 else 0.25,
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "seed": 20260618,
        "test_AQL": value + 1.0,
        "test_MAE": 2.0 * value,
        "test_RMSE": 3.0 * value,
    }


def manifest_row(region, fold, queue, priority):
    return {
        "region": region,
        "fold": fold,
        "queue": queue,
        "stage_c_priority": priority,
        "recommended_next_gate": "median_screen",
        "paper_quantiles": "0.10,0.25,0.45,0.50,0.55,0.75,0.90",
        "selection_split": "val",
        "selection_metric": "AQL",
        "selection_unit": "original",
        "candidate_strategy": "unit",
        "allowed_final_methods": "qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked",
        "input_scope": "local_target_only",
        "output_scope": "target_region_path",
        "feature_policy": "target_only",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "local_only_not_pricefm_graph",
        "cleanup_binary_artifacts": True,
        "preserve_pricefm_as_benchmark_only": True,
        "phase1_AQL": 7.0,
        "phase1_MAE": 14.0,
        "phase1_RMSE": 21.0,
        "degree1_n": 3,
        "degree2_n": 8,
        "rationale": "unit",
        "caution_label": "unit",
    }


def write_cache(root, region, fold):
    base = root / f"region={region}" / f"fold={fold}"
    base.mkdir(parents=True)
    for name in [
        "pricefm_phase1_metrics.csv",
        "pricefm_phase1_predictions_original.csv",
        "pricefm_phase1_predictions_scaled.csv",
        "pricefm_phase1_row_audit.csv",
        "pricefm_phase1_metric_by_horizon.csv",
    ]:
        (base / name).write_text("x\n1\n")


def write_inputs(tmp_path, bad_split=False, bad_coverage=False, include_fi3=False):
    median = tmp_path / "median"
    manifest = tmp_path / "manifest"
    cached = tmp_path / "cached_pricefm"
    median.mkdir()
    manifest.mkdir()
    cached.mkdir()
    rows = [
        selected_row("AT", 1, method="qdesn_al_rhs_ns_exact_chunked", value=10.0),
        selected_row("BE", 1, value=7.0),
        selected_row("BE", 2, value=8.0),
        selected_row("BE", 3, value=8.5),
        selected_row("DK_1", 1, value=11.0),
        selected_row("EE", 1, method="qdesn_al_rhs_ns_exact_chunked", value=20.0),
    ]
    if include_fi3:
        rows.append(selected_row("FI", 3, value=12.0))
    registry = pd.DataFrame(rows)
    if bad_split:
        registry.loc[0, "selected_on_split"] = "test"
    registry.to_csv(median / "median_selection_registry.csv", index=False)

    cov_rows = []
    for row in rows:
        for method in ["qdesn_al_rhs_ns_exact_chunked", "qdesn_exal_rhs_ns_exact_chunked"]:
            cov_rows.append({
                "region": row["region"],
                "fold": row["fold"],
                "method_id": method,
                "covered": not bad_coverage,
                "n_finite_metric_rows": 3 if not bad_coverage else 0,
            })
    pd.DataFrame(cov_rows).to_csv(median / "median_selection_method_coverage.csv", index=False)

    manifest_rows = [
        manifest_row("AT", 1, "completion_folds", 0),
        manifest_row("BE", 1, "diverse_new_regions", 1),
        manifest_row("BE", 2, "diverse_new_regions", 1),
        manifest_row("BE", 3, "diverse_new_regions", 1),
        manifest_row("DK_1", 1, "diverse_new_regions", 1),
        manifest_row("EE", 1, "diverse_new_regions", 1),
    ]
    if include_fi3:
        manifest_rows.append(manifest_row("FI", 3, "completion_folds", 0))
    pd.DataFrame(manifest_rows).to_csv(manifest / "stage_c_candidate_manifest.csv", index=False)
    write_cache(cached, "AT", 1)


def test_stage_c_quantile_candidate_registry_freezes_queues_and_cache(tmp_path):
    mod = load_script("52_freeze_pricefm_stage_c_quantile_candidate_registry.py")
    write_inputs(tmp_path)

    summary = mod.freeze(args(tmp_path))
    out = tmp_path / "out"
    registry = pd.read_csv(out / "stage_c_quantile_candidate_registry.csv")
    p0 = pd.read_csv(out / "stage_c_quantile_priority0_completion_registry.csv")
    p1 = pd.read_csv(out / "stage_c_quantile_priority1_green_registry.csv")
    p2 = pd.read_csv(out / "stage_c_quantile_priority2_yellow_registry.csv")
    hold = pd.read_csv(out / "stage_c_quantile_hold_registry.csv")
    cache = pd.read_csv(out / "stage_c_benchmark_cache_requirements.csv")

    assert summary["n_rows"] == 6
    assert summary["n_priority0_completion"] == 1
    assert summary["n_priority1_green"] == 3
    assert summary["n_priority2_yellow"] == 1
    assert summary["n_hold"] == 1
    assert set(p0["region"]) == {"AT"}
    assert set(p1["region"]) == {"BE"}
    assert set(p2["region"]) == {"DK_1"}
    assert set(hold["region"]) == {"EE"}
    assert registry["selection_uses_test_or_pricefm_metrics"].eq(False).all()
    assert cache.loc[cache["region"].eq("AT"), "cached_pricefm_exists"].iloc[0]
    assert not cache.loc[cache["region"].eq("BE"), "cached_pricefm_exists"].iloc[0]
    assert "stage_c_quantile_candidate_report.md" in summary["outputs"]["report"]


def test_stage_c_quantile_candidate_registry_rejects_test_selected_rows(tmp_path):
    mod = load_script("52_freeze_pricefm_stage_c_quantile_candidate_registry.py")
    write_inputs(tmp_path, bad_split=True)

    try:
        mod.freeze(args(tmp_path))
    except ValueError as exc:
        assert "validation/original/AQL" in str(exc)
    else:
        raise AssertionError("test-selected median rows should fail")


def test_stage_c_quantile_candidate_registry_rejects_bad_method_coverage(tmp_path):
    mod = load_script("52_freeze_pricefm_stage_c_quantile_candidate_registry.py")
    write_inputs(tmp_path, bad_coverage=True)

    try:
        mod.freeze(args(tmp_path))
    except ValueError as exc:
        assert "coverage is incomplete" in str(exc)
    else:
        raise AssertionError("incomplete method coverage should fail")


def test_stage_c_quantile_candidate_registry_rejects_fi_fold3(tmp_path):
    mod = load_script("52_freeze_pricefm_stage_c_quantile_candidate_registry.py")
    write_inputs(tmp_path, include_fi3=True)

    try:
        mod.freeze(args(tmp_path))
    except ValueError as exc:
        assert "FI fold 3" in str(exc)
    else:
        raise AssertionError("FI fold 3 should stay in the exception queue")
