import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/200_freeze_pricefm_stage_r57_joint_authority.py"


def load_module():
    sys.path.insert(0, str(SCRIPT.parent))
    spec = importlib.util.spec_from_file_location("pricefm_r57_authority", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_case(repo, grid, run_name, region, fold, experiment, method, feature_policy):
    run = Path("application/data_local/pricefm/runs") / run_name
    cell = repo / run / "cells" / f"region={region}" / f"fold={fold}"
    cell.joinpath("adapter").mkdir(parents=True)
    manifest = repo / "application/data_local/pricefm/experiment_grids" / grid / "manifest.csv"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame([{"id": experiment}]).to_csv(manifest, index=False)
    data_config = repo / "application/data_local/pricefm/configs" / f"{experiment}.yaml"
    data_config.parent.mkdir(parents=True, exist_ok=True)
    data_config.write_text(yaml.safe_dump({"pricefm": {"processed_dir": "application/data_local/pricefm/processed"}}))
    smoke = {
        "pricefm_desn_smoke": {
            "data_config": str(data_config.relative_to(repo)), "region": region, "fold": fold,
            "splits": ["train", "val", "test"], "quantiles": [0.5], "feature_policy": feature_policy,
            "adapter": {
                "feature_map": "window_reservoir_v1", "feature_dim": 8, "depth": 2,
                "units": [8, 8], "alpha": 0.2, "rho": 0.95, "input_scale": 0.2,
                "projection_scale": 1.0, "recurrent_sparsity": 0.05,
                "state_output": "final_layer", "seed": 11, "include_intercept": True,
            },
            "rhs_ns": {"tau0": 0.001},
        }
    }
    cell.joinpath("config.yaml").write_text(yaml.safe_dump(smoke, sort_keys=False))
    cell.joinpath("adapter/adapter_manifest.json").write_text(json.dumps({"region": region, "fold": fold}))
    return run, manifest.relative_to(repo)


def test_stage_r57_freezes_joint_contract_and_seals_test(tmp_path, monkeypatch):
    module = load_module()
    repo = tmp_path / "repo"
    repo.mkdir()
    monkeypatch.setattr(module, "git_head", lambda path: "a" * 40)
    rows = []
    atlas = []
    cases = [
        ("AA", 1, "exp_al", module.AL_METHOD, "target_only"),
        ("BB", 2, "exp_exal", module.EXAL_METHOD, "graph_khop"),
    ]
    for region, fold, experiment, method, policy in cases:
        run_dir, manifest = make_case(repo, "grid", experiment, region, fold, experiment, method, policy)
        rows.append({
            "region": region, "fold": fold, "experiment_id": experiment,
            "qdesn_method_id": method, "feature_policy": policy,
            "selected_on_split": "val", "selection_metric": "AQL",
            "selection_metric_value": 2.5,
            "selection_is_validation_only": True, "test_metrics_role": "audit_only",
            "qdesn_AQL": 2.0, "pricefm_method_id": "pricefm", "pricefm_AQL": 3.0,
            "decision_label": "qdesn_wins", "evidence_path": "evidence.csv", "evidence_sha256": "b" * 64,
        })
        atlas.append({
            "region": region, "fold": fold, "experiment_id": experiment, "method_id": method,
            "run_dir": str(run_dir), "manifest_path": str(manifest), "lag_window": 96,
            "feature_map": "window_reservoir_v1", "feature_dim": 8, "depth": 2,
            "units": "[8,8]", "alpha": 0.2, "rho": 0.95, "input_scale": 0.2,
            "projection_scale": 1.0, "recurrent_sparsity": 0.05,
            "state_output": "final_layer", "tau0": 0.001, "seed": 11,
        })
    registry = tmp_path / "registry.csv"
    atlas_path = tmp_path / "atlas.csv"
    pd.DataFrame(rows).to_csv(registry, index=False)
    pd.DataFrame(atlas).to_csv(atlas_path, index=False)
    output = tmp_path / "output"
    args = module.parser().parse_args([
        "--artifact-repo", str(repo), "--registry", str(registry), "--atlas", str(atlas_path),
        "--output-dir", str(output), "--expected-cells", "2", "--expected-al", "1",
        "--expected-exal", "1",
    ])
    summary = module.run(args)
    authority = pd.read_csv(output / "pricefm_stage_r57_joint_case_authority.csv")
    sealed = pd.read_csv(output / "pricefm_stage_r57_sealed_test_reference_ledger.csv")
    assert summary["surface_cells"] == 2
    assert set(authority.likelihood_family) == {"al", "exal"}
    assert "qdesn_AQL" not in authority.columns and "pricefm_AQL" not in authority.columns
    assert set(sealed.role) == {"sealed_test_audit_reference_not_for_selection"}
    assert authority.registry_mutation_authorized.eq(False).all()
    assert authority.article_mutation_authorized.eq(False).all()
    assert pd.read_csv(output / "pricefm_stage_r57_authority_gates.csv").passed.all()
