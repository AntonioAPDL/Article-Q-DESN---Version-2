import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/216_reconstruct_pricefm_stage_r62_matched_seven_quantile_authority.py"


def load_module():
    sys.path.insert(0, str(SCRIPT.parent))
    spec = importlib.util.spec_from_file_location("pricefm_r62", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_config(repo, root, region, fold, tau, string_numbers=False):
    cell = root / f"case_tau{str(tau).replace('.', 'p')}" / "cells" / f"region={region}" / f"fold={fold}"
    (cell / "adapter").mkdir(parents=True)
    data = repo / "data.yaml"
    if not data.exists():
        data.write_text(yaml.safe_dump({"pricefm": {
            "frequency": "15min",
            "features": {"label": "price", "lag": ["price"], "lead": ["load"]},
            "scaling": {"fit_on": "train_only"},
            "splits": [{"fold": fold, "train": ["a", "b"], "val": ["b", "c"], "test": ["c", "d"]}],
            "windows": {
                "lag_window": 96, "lead_window": 96, "anchor_hour": 0, "anchor_minute": 0,
                "train_boundary_mode": "contained_half_open",
                "validation_boundary_mode": "operational_half_open",
                "test_boundary_mode": "operational_half_open",
            },
        }}, sort_keys=False))
    number = (lambda value: str(value)) if string_numbers else (lambda value: value)
    smoke = {"pricefm_desn_smoke": {
        "data_config": str(data), "region": region, "fold": fold,
        "splits": ["train", "val", "test"], "quantiles": [tau],
        "horizons": list(range(1, 97)), "feature_policy": "graph_khop",
        "adapter": {
            "feature_map": "window_reservoir_v1", "feature_dim": 8,
            "depth": number(2), "units": [8, 8], "alpha": number(0.2),
            "rho": number(0.95), "input_scale": number(0.2),
            "projection_scale": 1.0, "recurrent_sparsity": number(0.05),
            "state_output": "final_layer", "seed": 11,
            "spatial": {"graph_degree": 1},
        },
        "rhs_ns": {"tau0": 0.001},
        "training": {"train_origin_limit": 100, "train_origin_selection": "tail"},
    }}
    (cell / "config.yaml").write_text(yaml.safe_dump(smoke, sort_keys=False))
    feature = {
        "feature_dim": 8, "feature_map": "window_reservoir_v1",
        "feature_policy": "graph_khop", "horizon_features": ["scaled_horizon"],
        "reservoir": {"depth": 2, "units": [8, 8]},
        "feature_policy_manifest": {
            "feature_policy": "graph_khop", "input_scope": "graph",
            "output_scope": "target", "spatial_information_set": "released_graph",
            "lead_covariate_status": "realized_ex_post",
            "graph": {"graph_degree": 1, "graph_hash": "g" * 64, "target_region": region,
                      "active_regions": [region, "ZZ"], "neighbor_regions": ["ZZ"]},
            "spatial": {"graph_degree": 1},
        },
    }
    (cell / "adapter/feature_manifest.json").write_text(json.dumps(feature))
    return cell


def write_metrics(cell, al, exal):
    pd.DataFrame([
        {"method_id": "qdesn_al_rhs_ns_exact_chunked", "split": "val", "unit": "original", "AQL": al, "AQCR": 0, "MAE": al * 3, "RMSE": al * 4},
        {"method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "val", "unit": "original", "AQL": exal, "AQCR": 0, "MAE": exal * 3, "RMSE": exal * 4},
    ]).to_csv(cell / "model/metric_summary.csv", index=False)


def test_r62_reconstructs_validation_only_bundle_and_reports_gap(tmp_path, monkeypatch):
    module = load_module()
    repo = tmp_path / "repo"
    repo.mkdir()
    panel = repo / "panels/panel"
    panel.mkdir(parents=True)
    run = repo / "runs"
    status = []
    taus = list(module.TAUS)
    al_values, exal_values = [], []
    for index, tau in enumerate(taus):
        cell = make_config(repo, run, "AA", 1, tau, string_numbers=True)
        (cell / "model").mkdir(exist_ok=True)
        al, exal = 2.0 + index / 10, 1.5 + index / 10
        write_metrics(cell, al, exal)
        al_values.append(al)
        exal_values.append(exal)
        status.append({
            "region": "AA", "fold": 1, "id": f"exact_case_tau0p{str(tau).split('.')[-1]}",
            "tau": tau, "complete": True, "model_dir": str(cell / "model"),
            "adapter_dir": str(cell / "adapter"),
        })
    pd.DataFrame(status).to_csv(panel / "panel_status.csv", index=False)
    pd.DataFrame([
        {"region": "AA", "fold": 1, "method_id": module.METHODS["al"], "split": "val", "unit": "original", "AQL": sum(al_values) / 7, "AQCR": 0, "MAE": 0, "RMSE": 0},
        {"region": "AA", "fold": 1, "method_id": module.METHODS["exal"], "split": "val", "unit": "original", "AQL": sum(exal_values) / 7, "AQCR": 0, "MAE": 0, "RMSE": 0},
    ]).to_csv(panel / "panel_metric.csv", index=False)

    authority_rows = []
    r59_rows = []
    for region in ("AA", "BB"):
        source = make_config(repo, repo / "legacy" / region, region, 1, 0.5)
        (source / "model").mkdir(exist_ok=True)
        write_metrics(source, 3.0, 2.5)
        manifest = json.loads((source / "adapter/feature_manifest.json").read_text())
        manifest["feature_policy_manifest"]["spatial"].update({"graph_hash": "g" * 64, "graph_source": "fixture"})
        (source / "adapter/feature_manifest.json").write_text(json.dumps(manifest))
        (source / "adapter/adapter_manifest.json").write_text(json.dumps({"feature_manifest_sha256": "fixture"}))
        authority_rows.append({
            "case_id": f"pricefm_joint_{region.lower()}_f1", "region": region, "fold": 1,
            "source_config": str(source / "config.yaml"),
            "source_adapter_manifest": str(source / "adapter/adapter_manifest.json"),
            "source_run_dir": str((repo / "legacy" / region / "case_tau0p5")),
            "source_method_id": module.METHODS["al"], "likelihood_family": "al",
            "current_authoritative_validation_AQL": 2.5,
        })
        r59_rows.append({
            "case_id": f"pricefm_joint_{region.lower()}_f1",
            "primary_validation_AQL": 2.0 if region == "AA" else 3.0,
        })
    authority = tmp_path / "authority.csv"
    decisions = tmp_path / "r59.csv"
    pd.DataFrame(authority_rows).to_csv(authority, index=False)
    pd.DataFrame(r59_rows).to_csv(decisions, index=False)
    monkeypatch.setattr(module, "git_head", lambda _path: "a" * 40)
    output = tmp_path / "output"
    args = module.parser().parse_args([
        "--artifact-repo", str(repo), "--r57-authority", str(authority),
        "--r59-decisions", str(decisions), "--panel-root", str(repo / "panels"),
        "--output-dir", str(output), "--expected-cells", "2",
    ])
    summary = module.run(args)
    matched = pd.read_csv(output / "pricefm_stage_r62_matched_seven_quantile_authority.csv")
    assert summary["matched_cells"] == 1
    assert summary["coverage_gap_cells"] == 1
    assert summary["legacy_median_only_cells"] == 2
    assert summary["legacy_family_value_mismatches"] == 2
    aa = matched[matched.region.eq("AA")].iloc[0]
    assert aa.selected_seven_quantile_family == "exal"
    assert bool(aa.family_changed_from_r57)
    assert matched.test_opened.eq(False).all()
    assert not list(output.glob("*.yaml"))


def test_r62_queue_boundaries():
    module = load_module()
    assert module.queue_label(-0.001) == "existing_joint_validation_win"
    assert module.queue_label(0.01) == "near_loss_le_1pct"
    assert module.queue_label(0.05) == "moderate_loss_1_to_5pct"
    assert module.queue_label(0.051) == "severe_loss_gt_5pct"
    assert module.queue_label(None) == "exact_comparator_missing"
