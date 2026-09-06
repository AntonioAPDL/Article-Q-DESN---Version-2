import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/236_audit_pricefm_stage_r69a_spec_anchor.py"


def load_module():
    sys.path.insert(0, str(SCRIPT.parent))
    spec = importlib.util.spec_from_file_location("pricefm_r69a", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload))
    return path


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)
    return path


def write_case_component(root, region, fold, base_id, tau):
    tau_slug = str(tau).replace(".", "p")
    cell = root / "runs" / f"{base_id}_tau{tau_slug}" / "cells" / f"region={region}" / f"fold={fold}"
    adapter = cell / "adapter"
    model = cell / "model"
    adapter.mkdir(parents=True)
    model.mkdir(parents=True)
    data = root / "configs" / f"data_{region}_{fold}_tau{tau_slug}.yaml"
    data.parent.mkdir(parents=True, exist_ok=True)
    data.write_text(yaml.safe_dump({
        "pricefm": {
            "features": {"label": "price", "lag": ["price"], "lead": ["load", "wind"]},
            "windows": {"lag_window": 96, "lead_window": 96},
        }
    }, sort_keys=False))
    config = {
        "pricefm_desn_smoke": {
            "data_config": str(data),
            "region": region,
            "fold": fold,
            "splits": ["train", "val", "test"],
            "horizons": list(range(1, 97)),
            "quantiles": [tau],
            "feature_policy": "graph_summary_mean",
            "adapter": {
                "feature_map": "window_reservoir_v1",
                "feature_dim": 120,
                "depth": 1,
                "units": [120],
                "alpha": 0.5,
                "rho": 0.9,
                "input_scale": 0.35,
                "projection_scale": 1.0,
                "recurrent_sparsity": 0.05,
                "reservoir_activation": "tanh",
                "state_output": "final_layer",
                "spatial": {"graph_degree": 1},
            },
            "rhs_ns": {"tau0": 0.001, "shrink_intercept": False, "freeze_tau_iters": 5, "freeze_tau_warmup_iters": 5},
            "qdesn_vb": {
                "likelihoods": ["al", "exal"],
                "max_iter": 100,
                "min_iter_elbo": 50,
                "n_samp_xi": 80,
            },
            "training": {"train_origin_limit": 3000, "train_origin_selection": "tail"},
            "warm_start": {"enabled": True},
            "artifact_hygiene": {"enabled": True},
        }
    }
    (cell / "config.yaml").write_text(yaml.safe_dump(config, sort_keys=False))
    feature = {
        "feature_policy": "graph_summary_mean",
        "feature_map": "window_reservoir_v1",
        "feature_dim": 120,
        "feature_policy_manifest": {
            "input_scope": "pricefm_graph_summary_mean_degree1",
            "output_scope": "target",
            "spatial_information_set": "pricefm_released_graph_summary",
            "lead_covariate_status": "realized_ex_post",
            "graph": {
                "graph_degree": 1,
                "graph_hash": "a" * 64,
                "neighbor_regions": ["ZZ"],
                "active_regions": [region, "ZZ"],
            },
        },
    }
    (adapter / "feature_manifest.json").write_text(json.dumps(feature))
    pd.DataFrame([{"method_id": "qdesn_al_rhs_ns_exact_chunked", "split": "val", "AQL": 1.0}]).to_csv(
        model / "metric_summary.csv", index=False
    )
    return cell / "config.yaml", adapter / "feature_manifest.json", model / "metric_summary.csv"


def fixture_inputs(tmp_path, missing_ledger=False):
    artifact = tmp_path / "artifact"
    taus = [0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9]
    cases = [("AA", 1, "al", "priority_0_near_miss"), ("BB", 2, "exal", "priority_1_moderate_gap")]
    target_rows = []
    ledger_rows = []
    for region, fold, family, priority in cases:
        base_id = f"base_{region.lower()}_f{fold}"
        panel_dir = str(artifact / "summary")
        target_rows.append({
            "case_id": f"pricefm_joint_{region.lower()}_f{fold}",
            "region": region,
            "fold": fold,
            "selected_panel_dir": panel_dir,
            "selected_base_id": base_id,
            "selected_seven_quantile_family": family,
            "selected_method_id": f"qdesn_{family}_rhs_ns_exact_chunked",
            "refit_priority": priority,
            "operational_gap_class": "near_miss_target" if priority.startswith("priority_0") else "moderate_gap_target",
            "qdesn_minus_operational_pricefm_AQL": 0.1 if priority.startswith("priority_0") else 0.5,
            "qdesn_minus_cached_pricefm_AQL": -0.2,
            "mechanism_queue": "near_loss_le_1pct",
        })
        config_paths, feature_paths, metric_paths = [], [], []
        for tau in taus:
            config, feature, metric = write_case_component(artifact, region, fold, base_id, tau)
            config_paths.append(str(config))
            feature_paths.append(str(feature))
            metric_paths.append(str(metric))
        if not missing_ledger or region != "BB":
            ledger_rows.append({
                "panel_dir": panel_dir,
                "base_id": base_id,
                "region": region,
                "fold": fold,
                "likelihood_family": family,
                "method_id": f"qdesn_{family}_rhs_ns_exact_chunked",
                "paper_quantiles": json.dumps(taus),
                "component_count": 7,
                "scientific_contract_sha256": "b" * 64,
                "feature_semantics_sha256": "c" * 64,
                "validation_AQL_recomputed": 1.25,
                "validation_AQL_panel": 1.25,
                "panel_metric_matches": True,
                "config_paths": json.dumps(config_paths),
                "feature_manifest_paths": json.dumps(feature_paths),
                "metric_paths": json.dumps(metric_paths),
                "integrity_pass": True,
            })
    return {
        "artifact": artifact,
        "targets": write_csv(tmp_path / "targets.csv", target_rows),
        "r68_summary": write_json(tmp_path / "r68_summary.json", {
            "targeted_refit_candidates": 2,
            "future_new_fit_package_authority": "exact_CRAN_exdqlm_1.1.1_public_API",
        }),
        "ledger": write_csv(tmp_path / "ledger.csv", ledger_rows),
        "r62_summary": write_json(tmp_path / "r62_summary.json", {"matched_cells": 114}),
    }


def parse_args(module, inputs, output):
    return module.parser().parse_args([
        "--artifact-repo", str(inputs["artifact"]),
        "--r68-target-queue", str(inputs["targets"]),
        "--r68-summary", str(inputs["r68_summary"]),
        "--r62-candidate-ledger", str(inputs["ledger"]),
        "--r62-summary", str(inputs["r62_summary"]),
        "--output-dir", str(output),
        "--expected-targets", "2",
    ])


def mutate_bundle_files(inputs, region, config_mutator, feature_mutator):
    ledger = pd.read_csv(inputs["ledger"])
    row = ledger.loc[ledger["region"].eq(region)].iloc[0]
    for path in json.loads(row["config_paths"]):
        config_path = Path(path)
        payload = yaml.safe_load(config_path.read_text())
        config_mutator(payload["pricefm_desn_smoke"])
        config_path.write_text(yaml.safe_dump(payload, sort_keys=False))
    for path in json.loads(row["feature_manifest_paths"]):
        feature_path = Path(path)
        payload = json.loads(feature_path.read_text())
        feature_mutator(payload)
        feature_path.write_text(json.dumps(payload))


def test_r69a_recovers_launch_grade_anchor_specs(tmp_path, monkeypatch):
    module = load_module()
    inputs = fixture_inputs(tmp_path)
    output = tmp_path / "out"
    args = parse_args(module, inputs, output)
    monkeypatch.setattr(module, "git_head", lambda _path: "d" * 40)

    summary = module.run(args)
    anchors = pd.read_csv(output / "pricefm_stage_r69a_spec_anchor_audit.csv")
    components = pd.read_csv(output / "pricefm_stage_r69a_quantile_component_anchor_audit.csv")
    specs = pd.read_csv(output / "pricefm_stage_r69a_spec_distribution.csv")
    gates = pd.read_csv(output / "pricefm_stage_r69a_launch_readiness_gates.csv")

    assert summary["status"] == "completed_read_only_spec_anchor_audit"
    assert summary["launch_grade_targets"] == 2
    assert summary["component_rows"] == 14
    assert set(anchors["depth_D"]) == {1}
    assert set(anchors["n_per_layer"]) == {120}
    assert set(anchors["rhs_tau0"]) == {0.001}
    assert anchors["future_launch_must_strip_test_split"].all()
    assert anchors["future_launch_must_use_cran111_public_api"].all()
    assert components["historical_config_contains_test_split"].all()
    assert len(specs) == 2
    assert gates.loc[gates.required, "passed"].all()
    assert not list(output.rglob("*.yaml"))
    assert not list(output.rglob("*.rds"))


def test_r69a_allows_local_target_only_without_graph_scope_metadata(tmp_path, monkeypatch):
    module = load_module()
    inputs = fixture_inputs(tmp_path)

    def config_mutator(smoke):
        smoke["feature_policy"] = "target_only"
        smoke["adapter"].pop("spatial", None)

    def feature_mutator(payload):
        payload["feature_policy"] = "target_only"
        payload.pop("feature_policy_manifest", None)

    mutate_bundle_files(inputs, "AA", config_mutator, feature_mutator)
    output = tmp_path / "out"
    args = parse_args(module, inputs, output)
    monkeypatch.setattr(module, "git_head", lambda _path: "d" * 40)

    summary = module.run(args)
    anchors = pd.read_csv(output / "pricefm_stage_r69a_spec_anchor_audit.csv")
    local = anchors.loc[anchors["region"].eq("AA")].iloc[0]

    assert summary["launch_grade_targets"] == 2
    assert bool(local["anchor_launch_grade"])
    assert bool(local["graph_degree_consistent"])
    assert not bool(local["graph_degree_required"])
    assert bool(local["graph_degree_semantic_pass"])
    assert local["input_scope"] == "local_target_only"
    assert local["output_scope"] == "target_region_path"
    assert local["spatial_information_set"] == "local_only_not_pricefm_graph"
    assert local["lead_covariate_status"] == "realized_ex_post"


def test_r69a_requires_graph_degree_for_graph_policies(tmp_path):
    module = load_module()
    inputs = fixture_inputs(tmp_path)

    def config_mutator(smoke):
        smoke["adapter"].pop("spatial", None)

    def feature_mutator(payload):
        manifest = payload["feature_policy_manifest"]
        manifest.pop("graph", None)
        manifest.pop("spatial", None)
        payload["feature_policy_manifest"] = manifest

    mutate_bundle_files(inputs, "AA", config_mutator, feature_mutator)
    output = tmp_path / "out"
    args = parse_args(module, inputs, output)

    summary = module.run(args)
    missing = pd.read_csv(output / "pricefm_stage_r69a_missing_or_inconsistent_anchors.csv")
    row = missing.loc[missing["region"].eq("AA")].iloc[0]

    assert summary["status"] == "completed_with_blocked_anchors"
    assert bool(row["graph_degree_required"])
    assert "graph_degree_required_for_graph_policy" in row["anchor_block_reason"]


def test_r69a_blocks_missing_ledger_match(tmp_path):
    module = load_module()
    inputs = fixture_inputs(tmp_path, missing_ledger=True)
    output = tmp_path / "out"
    args = parse_args(module, inputs, output)

    summary = module.run(args)
    missing = pd.read_csv(output / "pricefm_stage_r69a_missing_or_inconsistent_anchors.csv")
    gates = pd.read_csv(output / "pricefm_stage_r69a_launch_readiness_gates.csv")

    assert summary["status"] == "completed_with_blocked_anchors"
    assert summary["blocked_targets"] == 1
    assert "missing_r62_candidate_bundle_ledger_match" in set(missing["anchor_block_reason"])
    assert not gates.loc[gates.gate.eq("all_targets_launch_grade"), "passed"].iloc[0]


def test_r69a_rejects_stale_r68_count(tmp_path):
    module = load_module()
    inputs = fixture_inputs(tmp_path)
    inputs["r68_summary"].write_text(json.dumps({
        "targeted_refit_candidates": 3,
        "future_new_fit_package_authority": "exact_CRAN_exdqlm_1.1.1_public_API",
    }))
    args = parse_args(module, inputs, tmp_path / "out")

    with pytest.raises(RuntimeError, match="R68 target queue count changed"):
        module.run(args)
