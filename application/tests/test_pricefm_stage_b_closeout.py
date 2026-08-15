"""Tests for Stage-B PriceFM median closeout triage."""

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


def args():
    return SimpleNamespace(
        grid_id="unit_stage_b",
        candidate_source="unit_stage_b_source",
        selection_methods="qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked",
        naive_methods="naive1_prev_day,naive2_prev3_avg",
        diagnostic_methods="normal_rhs_ns",
        selection_split="val",
        test_split="test",
        unit="original",
        metric="AQL",
        close_rel_threshold=0.05,
        severe_aql_warning=1.0,
        severe_rel_warning=0.10,
        previous_registry_csv=None,
    )


def registry_rows():
    return pd.DataFrame([
        {
            "region": "AT",
            "fold": 1,
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "experiment_id": "exp_at",
            "selected_on_split": "val",
            "selected_on_unit": "original",
            "selection_metric": "AQL",
            "selection_metric_value": 5.0,
            "depth": 1,
            "units": "[120]",
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
        },
        {
            "region": "IT_NORD",
            "fold": 1,
            "selected_method_id": "qdesn_al_rhs_ns_exact_chunked",
            "experiment_id": "exp_it",
            "selected_on_split": "val",
            "selected_on_unit": "original",
            "selection_metric": "AQL",
            "selection_metric_value": 4.0,
            "depth": 2,
            "units": "[80, 80]",
            "alpha": 0.4,
            "rho": 0.9,
            "input_scale": 0.35,
        },
    ])


def metric_rows():
    rows = []
    for region, exp, method, val_aql, test_aql, naive_test in [
        ("AT", "exp_at", "qdesn_exal_rhs_ns_exact_chunked", 5.0, 6.0, 9.0),
        ("IT_NORD", "exp_it", "qdesn_al_rhs_ns_exact_chunked", 4.0, 8.0, 5.0),
    ]:
        rows.extend([
            {
                "region": region,
                "fold": 1,
                "experiment_id": exp,
                "method_id": method,
                "split": "val",
                "unit": "original",
                "AQL": val_aql,
                "MAE": 2 * val_aql,
                "RMSE": 3 * val_aql,
            },
            {
                "region": region,
                "fold": 1,
                "experiment_id": exp,
                "method_id": method,
                "split": "test",
                "unit": "original",
                "AQL": test_aql,
                "MAE": 2 * test_aql,
                "RMSE": 3 * test_aql,
            },
            {
                "region": region,
                "fold": 1,
                "experiment_id": exp,
                "method_id": "naive1_prev_day",
                "split": "test",
                "unit": "original",
                "AQL": naive_test,
                "MAE": 2 * naive_test,
                "RMSE": 3 * naive_test,
            },
            {
                "region": region,
                "fold": 1,
                "experiment_id": exp,
                "method_id": "normal_rhs_ns",
                "split": "test",
                "unit": "original",
                "AQL": test_aql + 0.5,
                "MAE": 2 * (test_aql + 0.5),
                "RMSE": 3 * (test_aql + 0.5),
            },
        ])
    return pd.DataFrame(rows)


def test_stage_b_closeout_triages_new_regions_without_previous_registry():
    mod = load_script("47_closeout_pricefm_stage_b_median_registry.py")
    selection = mod.build_selection_with_triage(registry_rows(), metric_rows(), None, args())
    regions = mod.region_summary(selection)

    assert selection.shape[0] == 2
    assert not selection["already_in_previous_registry"].any()
    assert selection.loc[selection["region"].eq("AT"), "fold_triage"].iloc[0] == "local_beats_naive"
    assert selection.loc[selection["region"].eq("IT_NORD"), "fold_triage"].iloc[0] == "local_lags_naive"
    assert regions.loc[regions["region"].eq("AT"), "stage_b_triage"].iloc[0] == "local_strong"
    assert regions.loc[regions["region"].eq("IT_NORD"), "stage_b_triage"].iloc[0] == "local_fail_rescue"


def test_stage_b_closeout_writes_reproducible_outputs(tmp_path):
    mod = load_script("47_closeout_pricefm_stage_b_median_registry.py")
    registry_dir = tmp_path / "registry"
    out_dir = tmp_path / "out"
    registry_dir.mkdir()
    registry_rows().to_csv(registry_dir / "median_selection_registry.csv", index=False)
    metric_rows().to_csv(registry_dir / "median_candidate_metrics.csv", index=False)
    a = args()
    a.registry_dir = str(registry_dir)
    a.output_dir = str(out_dir)

    summary = mod.closeout(a)

    assert summary["n_region_folds"] == 2
    assert (out_dir / "stage_b_selection_registry_with_triage.csv").exists()
    assert (out_dir / "stage_b_region_summary.csv").exists()
    assert (out_dir / "stage_b_method_spec_summary.csv").exists()
    assert (out_dir / "stage_b_normal_diagnostic.csv").exists()
    assert (out_dir / "stage_b_closeout_report.md").exists()


def test_stage_b_closeout_marks_previous_registry_context():
    mod = load_script("47_closeout_pricefm_stage_b_median_registry.py")
    previous = pd.DataFrame([{"region": "AT", "fold": 1}])

    selection = mod.build_selection_with_triage(registry_rows(), metric_rows(), previous, args())

    assert selection.loc[selection["region"].eq("AT"), "already_in_previous_registry"].iloc[0]
    assert not selection.loc[selection["region"].eq("IT_NORD"), "already_in_previous_registry"].iloc[0]
