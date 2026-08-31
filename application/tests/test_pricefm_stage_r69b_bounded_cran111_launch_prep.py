import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/237_prepare_pricefm_stage_r69b_bounded_cran111_launch_prep.py"
TAUS = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]


def load_module():
    sys.path.insert(0, str(SCRIPT.parent))
    spec = importlib.util.spec_from_file_location("pricefm_r69b", SCRIPT)
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


def sha256(path):
    import hashlib

    digest = hashlib.sha256()
    digest.update(Path(path).read_bytes())
    return digest.hexdigest()


def runtime_manifest(path, fork_source=False):
    return write_json(path, {
        "status": "installed_exact_cran_exdqlm_1.1.1",
        "fork_source_used": fork_source,
        "library": str(path.parent),
        "source_tarball": {
            "sha256": "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e",
            "version": "1.1.1",
            "repository": "CRAN",
        },
        "installed_package": {
            "version": "1.1.1",
            "repository": "CRAN",
            "exports": [
                "exalStaticLDVB",
                "exal_make_vb_control",
                "exal_make_vb_sigmagam_control",
            ],
        },
    })


def source_component(root, case_id, region, fold, tau, feature_policy="target_only", graph_degree=None):
    tau_slug = str(tau).replace(".", "p")
    source = root / "historical" / case_id / f"tau{tau_slug}"
    source.mkdir(parents=True)
    data_config = source / "data.yaml"
    data_config.write_text(yaml.safe_dump({
        "pricefm": {
            "raw_dir": "application/data_local/pricefm/raw",
            "interim_dir": "application/data_local/pricefm/interim",
            "processed_dir": "application/data_local/pricefm/processed",
            "external_repo_dir": "application/data_local/pricefm/external/PriceFM",
            "log_dir": "application/logs/pricefm",
            "features": {"label": "price", "lag": ["price"], "lead": ["load", "wind"]},
            "windows": {"lag_window": 96, "lead_window": 96},
        }
    }, sort_keys=False))
    adapter = {
        "feature_map": "window_reservoir_v1",
        "feature_dim": 80,
        "depth": 2,
        "units": [80, 80],
        "alpha": 0.4,
        "rho": 0.9,
        "input_scale": 0.35,
        "projection_scale": 1.0,
        "recurrent_sparsity": 0.05,
        "reservoir_activation": "tanh",
        "state_output": "final_layer",
    }
    if graph_degree is not None:
        adapter["spatial"] = {"graph_degree": graph_degree}
    config = source / "config.yaml"
    config.write_text(yaml.safe_dump({
        "pricefm_desn_smoke": {
            "data_config": str(data_config),
            "region": region,
            "fold": fold,
            "splits": ["train", "val", "test"],
            "quantiles": [tau],
            "feature_policy": feature_policy,
            "adapter": adapter,
            "rhs_ns": {"tau0": 0.001, "shrink_intercept": False},
            "qdesn_vb": {"likelihoods": ["al"], "max_iter": 80, "n_samp_xi": 50},
            "training": {"train_origin_limit": 3000, "train_origin_selection": "tail"},
            "run": {"output_dir": str(source / "model")},
        }
    }, sort_keys=False))
    feature = source / "feature_manifest.json"
    feature.write_text(json.dumps({"feature_policy": feature_policy}))
    metric = source / "metric_summary.csv"
    pd.DataFrame([{"method_id": "old", "split": "val", "AQL": 1.0}]).to_csv(metric, index=False)
    return {
        "config_path": str(config),
        "config_sha256": sha256(config),
        "feature_manifest_path": str(feature),
        "feature_manifest_sha256": sha256(feature),
        "metric_path": str(metric),
        "metric_sha256": sha256(metric),
        "data_config_path": str(data_config),
        "config_exists": True,
        "feature_manifest_exists": True,
        "metric_exists": True,
        "data_config_exists": True,
        "historical_config_contains_test_split": True,
    }


def fixture_inputs(tmp_path, failed_gate=False, fork_runtime=False):
    artifact = tmp_path / "artifact"
    r69a = tmp_path / "r69a"
    anchors = []
    components = []
    cases = [
        ("pricefm_joint_aa_f1", "AA", 1, "al", "priority_0_near_miss", "target_only", None),
        ("pricefm_joint_bb_f2", "BB", 2, "exal", "priority_1_moderate_gap", "graph_khop", 1),
    ]
    for case_id, region, fold, family, priority, policy, degree in cases:
        anchors.append({
            "case_id": case_id,
            "region": region,
            "fold": fold,
            "selected_family": family,
            "refit_priority": priority,
            "operational_gap_class": "near_miss_target",
            "qdesn_minus_operational_pricefm_AQL": 0.1,
            "qdesn_minus_cached_pricefm_AQL": -0.2,
            "mechanism_queue": "near_loss_le_1pct",
            "panel_dir": str(artifact / "authority"),
            "base_id": f"base_{region.lower()}_f{fold}",
            "component_count": 7,
            "integrity_pass": True,
            "paper_quantiles": json.dumps(TAUS),
            "validation_AQL_recomputed": 1.25,
            "validation_AQL_panel": 1.25,
            "panel_metric_matches": True,
            "feature_policy": policy,
            "feature_map": "window_reservoir_v1",
            "input_scope": "local_target_only" if policy == "target_only" else "pricefm_graph_khop",
            "output_scope": "target_region_path",
            "spatial_information_set": (
                "local_only_not_pricefm_graph" if policy == "target_only" else "pricefm_released_graph_khop"
            ),
            "lead_covariate_status": "realized_ex_post",
            "depth_D": 2,
            "units_json": json.dumps([80, 80], separators=(",", ":")),
            "n_per_layer": 80,
            "reservoir_feature_dim": 80,
            "alpha": 0.4,
            "rho": 0.9,
            "input_scale": 0.35,
            "projection_scale": 1.0,
            "recurrent_sparsity": 0.05,
            "reservoir_activation": "tanh",
            "state_output": "final_layer",
            "graph_degree": degree,
            "rhs_tau0": 0.001,
            "lag_window": 96,
            "lead_window": 96,
            "train_origin_limit": 3000,
            "train_origin_selection": "tail",
            "anchor_launch_grade": True,
            "anchor_block_reason": "",
        })
        for tau in TAUS:
            component = source_component(artifact, case_id, region, fold, tau, policy, degree)
            component.update({"case_id": case_id, "region": region, "fold": fold, "tau": tau})
            components.append(component)
    write_csv(r69a / "pricefm_stage_r69a_spec_anchor_audit.csv", anchors)
    write_csv(r69a / "pricefm_stage_r69a_quantile_component_anchor_audit.csv", components)
    write_csv(r69a / "pricefm_stage_r69a_launch_readiness_gates.csv", [
        {"gate": "all_targets_launch_grade", "required": True, "passed": not failed_gate},
        {"gate": "launch_yaml_absent", "required": True, "passed": True},
    ])
    write_json(r69a / "summary.json", {
        "status": "completed_read_only_spec_anchor_audit",
        "targets": 2,
        "launch_grade_targets": 2,
        "all_readiness_gates_passed": not failed_gate,
    })
    runtime = runtime_manifest(tmp_path / "runtime" / "pricefm_r67_cran111_install_manifest.json", fork_runtime)
    return {"artifact": artifact, "r69a": r69a, "runtime": runtime}


def parse_args(module, inputs, output, grid):
    return module.parser().parse_args([
        "--artifact-repo", str(inputs["artifact"]),
        "--r69a-dir", str(inputs["r69a"]),
        "--runtime-manifest", str(inputs["runtime"]),
        "--grid-dir", str(grid),
        "--run-dir", str(output / "runs"),
        "--output-dir", str(output / "authority"),
        "--expected-targets", "2",
        "--recommended-workers", "2",
    ])


def test_r69b_materializes_train_val_launch_prep_without_launch(tmp_path, monkeypatch):
    module = load_module()
    inputs = fixture_inputs(tmp_path)
    args = parse_args(module, inputs, tmp_path / "out", tmp_path / "grid")
    monkeypatch.setattr(module, "git_head", lambda _path: "a" * 40)

    summary = module.run(args)
    cases = pd.read_csv(Path(summary["case_manifest"]))
    components = pd.read_csv(Path(summary["component_ledger"]))
    gates = pd.read_csv(tmp_path / "out/authority/pricefm_stage_r69b_launch_prep_gates.csv")

    assert summary["status"] == "prepared_bounded_cran111_independent_vb_launch_not_launched"
    assert summary["planned_cases"] == 2
    assert summary["planned_quantile_components"] == 14
    assert summary["planned_atomic_fits"] == 28
    assert Path(summary["launch_control_yaml"]).is_file()
    assert not (tmp_path / "grid/launch_status.csv").exists()
    assert not list((tmp_path / "grid").rglob("*.rds"))
    assert gates["passed"].all()
    assert set(cases["fit_family_surface"]) == {'["al","exal"]'}
    assert not cases["launch_authorized"].any()
    assert not cases["test_access_authorized"].any()
    assert components.groupby("case_id").size().eq(7).all()
    for config_path in cases["config"]:
        payload = yaml.safe_load(Path(config_path).read_text())
        smoke = payload["pricefm_desn_smoke"]
        assert smoke["splits"] == ["train", "val"]
        assert smoke["quantiles"] == TAUS
        assert smoke["package_authority"] == "exact_CRAN_exdqlm_1.1.1_public_API"
        assert smoke["qdesn_vb"]["public_api"] == "exalStaticLDVB"
        assert smoke["qdesn_vb"]["fork_only_namespace_calls_authorized"] is False


def test_r69b_rejects_failed_r69a_gate(tmp_path):
    module = load_module()
    inputs = fixture_inputs(tmp_path, failed_gate=True)
    args = parse_args(module, inputs, tmp_path / "out", tmp_path / "grid")

    with pytest.raises(RuntimeError, match="R69A required gates failed"):
        module.run(args)


def test_r69b_rejects_fork_runtime(tmp_path):
    module = load_module()
    inputs = fixture_inputs(tmp_path, fork_runtime=True)
    args = parse_args(module, inputs, tmp_path / "out", tmp_path / "grid")

    with pytest.raises(RuntimeError, match="must not use fork source"):
        module.run(args)
