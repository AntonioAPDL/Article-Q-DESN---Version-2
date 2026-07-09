"""Tests for the dry-run PriceFM bridge to package Q-DESN model selection."""

from pathlib import Path
import importlib.util
import sys

import pytest
import yaml


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


GRID = (
    ROOT
    / "application"
    / "config"
    / "pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml"
)


def test_pricefm_qdesn_model_selection_bridge_writes_dry_run_config(tmp_path):
    mod = load_script("29_prepare_qdesn_model_selection_bridge.py")
    out = mod.build_bridge(
        grid_config=GRID,
        output_dir=tmp_path / "bridge",
        regions=["DE_LU"],
        folds=[2],
        ids=["fup_f2_priorp2retest_l96_d1_n120_a0p5_r0p9_in0p25_seed20260601"],
        quantile=0.50,
        write=True,
    )

    assert out["summary"]["n_configs"] == 1
    assert out["summary"]["n_candidate_rows"] == 1
    assert out["summary"]["package_launch_ready"] is False
    cfg_path = ROOT / out["manifest"][0]["config_path"]
    if not cfg_path.exists():
        cfg_path = Path(out["manifest"][0]["config_path"])
    cfg = yaml.safe_load(cfg_path.read_text())
    assert cfg["pipeline"]["profile"] == "pricefm_bridge_dry_run"
    assert cfg["pipeline"]["pricefm_bridge_launch_ready"] is False
    assert cfg["pricefm_bridge"]["region"] == "DE_LU"
    assert cfg["pricefm_bridge"]["fold"] == 2
    assert cfg["pricefm_bridge"]["package_launch_ready"] is False
    stage = cfg["model_selection"]["stages"][0]
    candidates = stage["candidate_grid"]["candidates"]
    assert len(candidates) == 1
    cand = candidates[0]
    assert cand["D"] == 1
    assert cand["n"] == [120]
    assert cand["n_tilde"] == []
    assert cand["m"] == 96
    assert cand["alpha"] == 0.5
    assert cand["rho"] == 0.9
    assert cand["metadata"]["pricefm_feature_dim"] == 120
    assert cand["metadata"]["pricefm_projection_scale"] == 1.0
    assert cfg["vb"]["priors"]["beta"]["type"] == "rhs_ns"
    assert cfg["vb"]["priors"]["beta"]["rhs_ns"]["shrink_intercept"] is False
    assert (tmp_path / "bridge" / "bridge_manifest.csv").exists()
    assert (tmp_path / "bridge" / "bridge_compatibility.csv").exists()
    assert (tmp_path / "bridge" / "qdesn_model_selection_bridge_report.md").exists()


def test_pricefm_qdesn_model_selection_bridge_groups_region_folds(tmp_path):
    mod = load_script("29_prepare_qdesn_model_selection_bridge.py")
    out = mod.build_bridge(
        grid_config=GRID,
        output_dir=tmp_path / "bridge",
        regions=["DE_LU"],
        folds=[2, 3],
        priorities=[0],
        quantile=0.50,
        write=True,
    )

    by_fold = {int(row["fold"]): row for row in out["manifest"]}
    assert set(by_fold) == {2, 3}
    assert by_fold[2]["n_candidates"] == 5
    assert by_fold[3]["n_candidates"] == 120
    assert all(row["package_launch_ready"] is False for row in out["manifest"])


def test_pricefm_qdesn_model_selection_bridge_fails_when_filters_match_nothing(tmp_path):
    mod = load_script("29_prepare_qdesn_model_selection_bridge.py")
    with pytest.raises(ValueError, match="No PriceFM grid rows"):
        mod.build_bridge(
            grid_config=GRID,
            output_dir=tmp_path / "bridge",
            regions=["DOES_NOT_EXIST"],
            write=False,
        )
