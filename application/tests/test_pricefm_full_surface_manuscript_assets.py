"""Tests for PriceFM full-surface manuscript asset export."""

import importlib.util
import json
import sys
from pathlib import Path
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


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True))


def make_full_surface_fixture(tmp_path):
    closeout = tmp_path / "closeout"
    rows = []
    feature_cycle = [
        "target_only",
        "graph_khop",
        "graph_summary_mean",
        "graph_neighbor_spread_summary",
    ]
    source_cycle = ["current_r3q", "stage_m", "provenance_bridge_30"]
    decisions = ["qdesn_wins", "qdesn_close", "pricefm_wins"]
    for region_index in range(38):
        region = f"R{region_index + 1:02d}"
        for fold in (1, 2, 3):
            i = region_index * 3 + fold - 1
            qdesn_aql = 5.0 + 0.03 * i
            delta = (-0.35 if i % 3 == 0 else (0.08 if i % 3 == 1 else 0.42))
            pricefm_aql = qdesn_aql - delta
            rows.append({
                "region": region,
                "fold": fold,
                "source_class": source_cycle[i % len(source_cycle)],
                "qdesn_method_id": "qdesn_exal_rhs_ns_exact_chunked" if i % 2 else "qdesn_al_rhs_ns_exact_chunked",
                "qdesn_AQL": qdesn_aql,
                "pricefm_method_id": "pricefm_phase1_pretraining",
                "pricefm_AQL": pricefm_aql,
                "delta_AQL_qdesn_minus_pricefm": delta,
                "decision_label": decisions[i % len(decisions)],
                "rescue_tier": "priority0" if i % 17 == 0 else "none",
                "feature_policy": feature_cycle[i % len(feature_cycle)],
            })
    write_csv(closeout / "pricefm_full_surface_decision_registry.csv", rows)

    registry = pd.DataFrame(rows)
    write_csv(closeout / "pricefm_full_surface_method_summary.csv", [
        {
            "method_id": "qdesn_selected",
            "n": len(registry),
            "mean_AQL": registry["qdesn_AQL"].mean(),
            "median_AQL": registry["qdesn_AQL"].median(),
            "min_AQL": registry["qdesn_AQL"].min(),
            "max_AQL": registry["qdesn_AQL"].max(),
        },
        {
            "method_id": "pricefm_phase1_pretraining",
            "n": len(registry),
            "mean_AQL": registry["pricefm_AQL"].mean(),
            "median_AQL": registry["pricefm_AQL"].median(),
            "min_AQL": registry["pricefm_AQL"].min(),
            "max_AQL": registry["pricefm_AQL"].max(),
        },
    ])

    horizon_rows = []
    for row in rows[:12]:
        for horizon_group, delta in zip(["1-24", "25-48", "49-72", "73-96"], [0.2, -0.4, -0.1, 0.05]):
            horizon_rows.append({
                "region": row["region"],
                "fold": row["fold"],
                "source_class": row["source_class"],
                "horizon_group": horizon_group,
                "horizon_delta_AQL_qdesn_minus_pricefm": delta,
            })
    write_csv(closeout / "pricefm_full_surface_horizon_diagnostics.csv", horizon_rows)
    horizon_frame = pd.DataFrame(horizon_rows)
    horizon_summary = (
        horizon_frame.groupby("horizon_group", as_index=False)
        .agg(
            n=("region", "size"),
            qdesn_wins=("horizon_delta_AQL_qdesn_minus_pricefm", lambda x: int((x < 0).sum())),
            mean_delta_AQL=("horizon_delta_AQL_qdesn_minus_pricefm", "mean"),
            median_delta_AQL=("horizon_delta_AQL_qdesn_minus_pricefm", "median"),
        )
    )
    horizon_summary.to_csv(closeout / "pricefm_full_surface_horizon_summary.csv", index=False)

    write_json(closeout / "summary.json", {
        "status": "completed",
        "n_region_folds": 114,
        "n_regions": 38,
        "n_folds": 3,
        "n_horizon_diagnostic_region_folds": 12,
        "decision_counts": {
            "qdesn_wins": int((registry["decision_label"] == "qdesn_wins").sum()),
            "qdesn_close": int((registry["decision_label"] == "qdesn_close").sum()),
            "pricefm_wins": int((registry["decision_label"] == "pricefm_wins").sum()),
        },
        "expected_quantiles": [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90],
        "comparison_status_completed": True,
        "fits_models": False,
        "launches_models": False,
        "row_alignment_complete": True,
    })
    return closeout


def test_full_surface_manuscript_export_writes_compact_assets(tmp_path):
    mod = load_script("115_build_pricefm_full_surface_manuscript_assets.py")
    closeout = make_full_surface_fixture(tmp_path)
    args = SimpleNamespace(
        closeout_dir=str(closeout),
        table_dir=str(tmp_path / "tables"),
        figure_dir=str(tmp_path / "figures"),
    )

    summary = mod.build(args)

    assert summary["n_region_folds"] == 114
    outputs = tmp_path / "tables" / "pricefm_full_current_outputs.tex"
    assert outputs.exists()
    text = outputs.read_text()
    assert "\\PricefmFullMainSummaryTable" in text
    assert "\\PricefmFullInputSetSummaryTable" in text
    assert "\\PricefmFullHorizonDiagnosticSummaryTable" in text
    assert (tmp_path / "tables" / "pricefm_full_main_summary.tex").exists()
    assert (tmp_path / "tables" / "pricefm_full_input_set_summary.tex").exists()
    assert (tmp_path / "tables" / "pricefm_full_horizon_diagnostic_summary.tex").exists()
    assert "Stage-M" not in (tmp_path / "tables" / "pricefm_full_source_summary.tex").read_text()

    manifest = json.loads((tmp_path / "tables" / "pricefm_full_article_asset_manifest.json").read_text())
    paths = {row["path"] for row in manifest["files"]}
    assert str(tmp_path / "tables" / "pricefm_full_main_summary.tex") in paths
    assert str(tmp_path / "tables" / "pricefm_full_input_set_summary.tex") in paths
    assert len(list((tmp_path / "figures").glob("*.png"))) == 2
