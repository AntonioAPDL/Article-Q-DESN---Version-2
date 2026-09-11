"""Focused tests for the complete PriceFM R97 region-specific campaign."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import threading
from types import SimpleNamespace

import joblib
import numpy as np
import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


class FakeGit:
    clean = True
    head = "abc123"
    upstream_head = "abc123"
    branch = "work/pricefm-r97-fixture"
    upstream = "origin/work/pricefm-r97-fixture"
    worktree = "/tmp/fixture"

    def to_dict(self):
        return {
            "clean": self.clean, "head": self.head,
            "upstream_head": self.upstream_head, "branch": self.branch,
            "upstream": self.upstream, "worktree": self.worktree,
        }


class IdentityScaler:
    def inverse_transform(self, values):
        return np.asarray(values, dtype=float)


def load(name: str):
    path = SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def write_yaml(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(payload, sort_keys=False))


def regions() -> list[str]:
    return ["SE_2", *[f"R{index:02d}" for index in range(1, 38)]]


def source_data(path: Path, region_names: list[str]) -> None:
    write_yaml(path, {"pricefm": {
        "regions": region_names,
        "raw_dir": "raw", "interim_dir": "interim", "processed_dir": "processed",
        "external_repo_dir": "external", "log_dir": "logs",
        "splits": [
            {"fold": 1, "train": ["2022-01-01", "2024-09-01"], "val": ["2024-09-01", "2025-01-01"], "test": ["2025-01-01", "2025-05-01"]},
            {"fold": 2, "train": ["2022-01-01", "2025-01-01"], "val": ["2025-01-01", "2025-05-01"], "test": ["2025-05-01", "2025-09-01"]},
            {"fold": 3, "train": ["2022-01-01", "2025-05-01"], "val": ["2025-05-01", "2025-09-01"], "test": ["2025-09-01", "2026-01-01"]},
        ],
        "windows": {
            "lag_window": 96, "lead_window": 96,
            "train_boundary_mode": "contained_half_open",
            "validation_boundary_mode": "operational_half_open",
            "test_boundary_mode": "operational_half_open",
        },
        "pilot": {"enabled": True, "region": region_names[0], "fold": 1},
    }})


def test_global_prep_resolves_all_114_controls_and_freezes_mean_rule(tmp_path):
    module = load("316_prepare_pricefm_stage_r97_global_region_campaign.py")
    region_names = regions()
    authority = tmp_path / "authority.csv"
    history = tmp_path / "history/stage"
    history.mkdir(parents=True)
    data = tmp_path / "data.yaml"
    se2 = tmp_path / "se2.csv"
    source_data(data, region_names)
    authority_rows = []
    history_rows = []
    policies = ("target_only", "graph_summary_mean", "graph_summary_mean_std")
    for region_index, region in enumerate(region_names):
        for fold in (1, 2, 3):
            experiment = f"experiment_{region}_{fold}"
            authority_rows.append({
                "region": region, "fold": fold, "experiment_id": experiment,
                "feature_policy": policies[fold - 1], "qdesn_AQL": 5.0,
                "pricefm_AQL": 6.0,
            })
            history_rows.append({
                "experiment_id": experiment, "lag_window": 48 + 48 * (fold - 1),
                "depth": 2.0, "units": "[64, 64]", "alpha": 0.2,
                "rho": 0.95, "input_scale": 0.2, "tau0": 0.001,
                "seed": 100 + region_index, "state_output": "final_layer",
            })
    pd.DataFrame(authority_rows).to_csv(authority, index=False)
    pd.DataFrame(history_rows).to_csv(history / "specs.csv", index=False)
    pd.DataFrame({
        "region": ["SE_2"] * 3, "fold": [1, 2, 3],
        "candidate_test_AQL": [4.0] * 3,
    }).to_csv(se2, index=False)
    args = module.parser().parse_args([
        "--authority-registry", str(authority), "--history-root", str(tmp_path / "history"),
        "--source-data-config", str(data), "--se2-comparison", str(se2),
        "--output-dir", str(tmp_path / "output"),
        "--campaign-root", str(tmp_path / "campaign"), "--allow-fixture-hashes",
    ])
    summary = module.run(args)
    contract = json.loads((args.output_dir / "pricefm_stage_r97_campaign_contract.json").read_text())
    controls = pd.read_csv(args.output_dir / "pricefm_stage_r97_authoritative_spec_controls.csv")
    assert summary["regions_to_fit"] == 37
    assert summary["cases"] == 114
    assert len(controls) == 114
    assert set(controls.feature_policy) == set(policies)
    assert contract["selection"]["unit"] == "region"
    assert contract["final_decision"]["per_case_dual_comparator_veto"] is False
    assert contract["final_decision"]["aggregation"].startswith("unweighted_arithmetic_mean")


def test_region_surface_materializes_one_desn_and_exact_45_task_dag(tmp_path, monkeypatch):
    module = load("317_prepare_pricefm_stage_r97_region_quantile_surface.py")
    monkeypatch.setattr(module, "git_identity", lambda _root: FakeGit())
    data = tmp_path / "data.yaml"
    source_data(data, ["SE_2", "R01"])
    normal_package = tmp_path / "normal_package"
    normal_package.mkdir()
    library = tmp_path / "library"
    library.mkdir()
    runtime = library / "pricefm_stage_r94_coherent_exal_init_manifest.json"
    write_json(runtime, {
        "version": "1.1.1.9005", "repair": module.EXPECTED_REPAIR,
    })
    contract = tmp_path / "selected.json"
    write_json(contract, {
        "region": "R01", "feature_policy": "target_only", "lag_window": 96,
        "depth": 2, "units": "[64,64]", "alpha": 0.2, "rho": 0.95,
        "input_scale": 0.2, "state_output": "final_layer", "seed": 11,
        "tau0": 0.001, "test_access_authorized": False,
    })
    args = module.parser().parse_args([
        "--selected-normal-contract", str(contract), "--source-data-config", str(data),
        "--normal-package", str(normal_package), "--r-library", str(library),
        "--runtime-manifest", str(runtime), "--processed-dir", str(tmp_path / "processed"),
        "--grid-dir", str(tmp_path / "grid"), "--run-dir", str(tmp_path / "runs"),
        "--output-dir", str(tmp_path / "prep"), "--code-root", str(ROOT),
    ])
    summary = module.run(args)
    manifest = pd.read_csv(args.grid_dir / "task_manifest.csv")
    pipeline = json.loads((args.grid_dir / "pipeline_contract.json").read_text())
    generated_data = yaml.safe_load((args.grid_dir / "configs/train_validation_data.yaml").read_text())
    normal_config = yaml.safe_load((args.grid_dir / "configs/normal_rhs_full.yaml").read_text())
    launch_control = json.loads((args.grid_dir / "launch_control.json").read_text())
    assert summary["tasks"] == 45
    assert manifest.likelihood_family.value_counts().to_dict() == {
        "al": 21, "exal": 21, "normal_rhs": 3,
    }
    assert set(manifest.fold) == {1, 2, 3}
    assert not manifest.test_access_authorized.astype(bool).any()
    assert all(set(split) == {"fold", "train", "val"} for split in generated_data["pricefm"]["splits"])
    assert pipeline["frozen_desn"]["units"] == "[64,64]"
    assert pipeline["rhs_tau0"] == pytest.approx(0.001)
    assert pipeline["family_selection_rule"].startswith("minimum_fold1_validation_AQL")
    assert normal_config["pricefm_desn_full"]["normal"]["vb_control"] == {
        "max_iter": 500, "min_iter": 50, "tol": 1e-5, "verbose": False,
    }
    assert launch_control["normal_convergence_recovery"] == {
        "enabled": True,
        "trigger": "finite_nonconverged_normal_rhs_at_iteration_ceiling",
        "retry_max_iter": 500,
        "tol": 1e-5,
        "preserve_initial_diagnostics": True,
    }


def test_ridge_bank_preserves_historical_spread_control_inside_240_arm_budget():
    module = load("291_prepare_pricefm_stage_r93_region_frozen_ladder.py")
    authority = pd.DataFrame([
        {
            "region": "IT_CNOR", "fold": fold, "experiment_id": f"exp{fold}",
            "qdesn_method_id": "qdesn", "qdesn_AQL": 5.0,
            "pricefm_AQL": 6.0, "decision_label": "qdesn_wins",
        }
        for fold in (1, 2, 3)
    ])
    controls = pd.DataFrame([
        {
            "region": "IT_CNOR", "fold": 1, "experiment_id": "exp1",
            "feature_policy": "graph_neighbor_spread_summary", "lag_window": 96,
            "depth": 2, "units": "[80,80]", "alpha": 0.4, "rho": 0.9,
            "input_scale": 0.35, "state_output": "final_layer", "seed": 1,
            "tau0": 0.001, "graph_degree": 1,
            "neighbor_regions": '["IT_CSUD","IT_NORD"]', "max_neighbor_regions": 2,
        },
        *[
            {
                "region": "IT_CNOR", "fold": fold, "experiment_id": f"exp{fold}",
                "feature_policy": "target_only", "lag_window": 96,
                "depth": 2, "units": f"[{48 + fold},{48 + fold}]", "alpha": 0.2,
                "rho": 0.95, "input_scale": 0.2, "state_output": "final_layer",
                "seed": fold, "tau0": 0.001, "graph_degree": 0,
                "neighbor_regions": "[]", "max_neighbor_regions": 0,
            }
            for fold in (2, 3)
        ],
    ])
    ledger = module.control_ledger(authority, controls)
    args = SimpleNamespace(target_region="IT_CNOR", candidate_count=240, search_seed=7)
    candidates = module.build_candidates(
        ledger, ["IT_CNOR", "IT_CSUD", "IT_NORD"], args,
    )
    spread = candidates[candidates.feature_policy.eq("graph_neighbor_spread_summary")]
    assert len(candidates) == 240
    assert candidates.semantic_fingerprint.is_unique
    assert len(spread) == 1
    assert spread.iloc[0].neighbor_regions == ["IT_CSUD", "IT_NORD"]
    assert spread.iloc[0].candidate_role == "authoritative_fold_geometry_control"


def test_family_selection_uses_fold1_only_and_never_mixes_cases():
    module = load("318_closeout_pricefm_stage_r97_region_quantile_surface.py")
    metrics = pd.DataFrame([
        {"family": family, "fold": fold, "AQL": value, "numerically_eligible": eligible}
        for family, values, eligibilities in (
            ("al", (2.0, 100.0, 100.0), (True, True, True)),
            ("exal", (1.0, 0.1, 0.1), (True, True, True)),
        )
        for fold, (value, eligible) in enumerate(zip(values, eligibilities), start=1)
    ])
    selected, fold1_winner, fallback = module.choose_family(metrics)
    assert (selected, fold1_winner, fallback) == ("exal", "exal", False)
    metrics.loc[(metrics.family == "exal") & (metrics.fold == 3), "numerically_eligible"] = False
    selected, fold1_winner, fallback = module.choose_family(metrics)
    assert (selected, fold1_winner, fallback) == ("al", "exal", True)


def test_shared_preprocessing_runs_splits_once_across_region_window_sets(tmp_path, monkeypatch):
    module = load("319_orchestrate_pricefm_stage_r97_global_campaign.py")
    calls = []
    monkeypatch.setattr(module, "command", lambda cmd, **kwargs: calls.append([str(value) for value in cmd]))
    first = tmp_path / "lag48.yaml"
    second = tmp_path / "lag96.yaml"
    for path, lag in ((first, 48), (second, 96)):
        write_yaml(path, {"pricefm": {"windows": {"lag_window": lag}}})
    shared = tmp_path / "shared"
    module.prepare_shared_data([first], ["R01"], [1, 2, 3], ROOT, tmp_path / "R01", shared_base_root=shared)
    module.prepare_shared_data([second], ["R02"], [1, 2, 3], ROOT, tmp_path / "R02", shared_base_root=shared)
    assert sum(str(module.MAKE_SPLITS) in call for call in calls) == 1
    assert sum(str(module.FIT_SCALERS) in call for call in calls) == 1
    assert sum(str(module.BUILD_WINDOWS) in call for call in calls) == 2


def test_r97_rhs_transition_uses_materialized_ridge_grid_and_fails_closed(tmp_path, monkeypatch):
    module = load("319_orchestrate_pricefm_stage_r97_global_campaign.py")
    calls = []
    materialized = []
    monkeypatch.setattr(
        module,
        "command",
        lambda cmd, **kwargs: calls.append([str(value) for value in cmd]),
    )
    monkeypatch.setattr(
        module,
        "materialize_grid",
        lambda grid, generated, code_root, log: materialized.append(
            (grid, generated, code_root, log)
        ),
    )
    campaign = module.Campaign.__new__(module.Campaign)
    campaign.code_root = ROOT
    paths = {
        "root": tmp_path / "region",
        "ridge_prep": tmp_path / "region/ridge_prep",
        "ridge_generated": tmp_path / "region/ridge_generated",
        "rhs_prep": tmp_path / "region/rhs_prep",
        "rhs_generated": tmp_path / "region/rhs_generated",
        "rhs_runs": tmp_path / "region/rhs_runs",
    }
    paths["ridge_prep"].mkdir(parents=True)
    with pytest.raises(RuntimeError, match="R97 Ridge grid is missing or empty"):
        campaign.prepare_rhs("R01", paths)
    assert calls == []

    ridge_grid = paths["ridge_prep"] / "ridge_grid.yaml"
    ridge_grid.write_text("pricefm_desn_experiment_grid: {}\n")
    campaign.prepare_rhs("R01", paths)
    assert len(calls) == 1
    assert calls[0][calls[0].index("--ridge-grid") + 1] == str(ridge_grid)
    assert materialized[0][0] == paths["rhs_prep"] / "pricefm_stage_r93_rhs_grid.yaml"


def test_screening_compaction_retains_only_selection_evidence(tmp_path):
    module = load("319_orchestrate_pricefm_stage_r97_global_campaign.py")
    run_dir = tmp_path / "experiment"
    model = run_dir / "cells/region=R01/fold=101/model"
    adapter = run_dir / "cells/region=R01/fold=101/adapter"
    model.mkdir(parents=True)
    adapter.mkdir()
    (model / "metric_summary.csv").write_text("AQL\n1\n")
    (model / "model_method_summary.csv").write_text("converged\ntrue\n")
    (model / "large_model.rds").write_bytes(b"heavy")
    (adapter / "X_train.csv").write_text("heavy\n")
    module.compact_experiment(SimpleNamespace(run_dir=str(run_dir), id="candidate"), "R01", [101])
    assert (model / "metric_summary.csv").is_file()
    assert (model / "model_method_summary.csv").is_file()
    assert not (model / "large_model.rds").exists()
    assert not adapter.exists()
    assert module.valid_marker(run_dir / "r97_compaction_terminal.json")


def test_preprocessing_terminal_preserves_full_config_and_verifies_artifacts(
    tmp_path, monkeypatch,
):
    module = load("319_orchestrate_pricefm_stage_r97_global_campaign.py")
    grid = tmp_path / "surface_grid"
    data_path = grid / "configs/train_validation_data.yaml"
    processed = tmp_path / "processed"
    active_regions = ["R01", "R02"]
    payload = {
        "pricefm": {
            "regions": active_regions,
            "processed_dir": str(processed),
            "splits": [
                {"fold": fold, "train": ["a", "b"], "val": ["b", "c"]}
                for fold in (1, 2, 3)
            ],
            "windows": {
                "lag_window": 48,
                "lead_window": 96,
                "train_boundary_mode": "contained_half_open",
                "validation_boundary_mode": "operational_half_open",
                "test_boundary_mode": "operational_half_open",
            },
        }
    }
    write_yaml(data_path, payload)
    pipeline = {
        "schema_version": 1,
        "stage": "R97",
        "region": "R01",
        "fit_folds": [1, 2, 3],
        "active_window_regions": active_regions,
        "processed_dir": str(processed),
        "generated_data_config": module.file_record(data_path, "R97_train_validation_data"),
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    pipeline["pipeline_contract_sha256"] = module.canonical_sha256(pipeline)
    write_json(grid / "pipeline_contract.json", pipeline)

    for fold in (1, 2, 3):
        scaler = processed / f"scalers/fold_{fold}/per_region_separate_xy_scalers.joblib"
        scaler.parent.mkdir(parents=True, exist_ok=True)
        scaler.write_bytes(f"scaler-{fold}".encode())
        for region in active_regions:
            for split in ("train", "val"):
                window = module.window_npz_path(payload, fold, region, split)
                window.parent.mkdir(parents=True, exist_ok=True)
                window.write_bytes(f"{fold}-{region}-{split}".encode())

    calls = []
    monkeypatch.setattr(module, "prepare_shared_data", lambda *args, **kwargs: calls.append((args, kwargs)))
    campaign = module.Campaign.__new__(module.Campaign)
    campaign.preprocess_lock = threading.Lock()
    campaign.code_root = tmp_path
    campaign.root = tmp_path / "campaign"
    campaign.preprocessing_terminal({"surface_grid": grid})

    terminal_path = grid / "preprocessing_terminal.json"
    terminal = json.loads(terminal_path.read_text())
    assert len(calls) == 1
    assert terminal["status"] == "completed"
    assert terminal["pipeline_contract_sha256"] == pipeline["pipeline_contract_sha256"]
    assert terminal["test_opened"] is False
    assert len(terminal["artifacts"]) == 15
    assert all("test" not in record["role"] for record in terminal["artifacts"])

    campaign.preprocessing_terminal({"surface_grid": grid})
    assert len(calls) == 1
    Path(terminal["artifacts"][0]["path"]).write_bytes(b"tampered")
    with pytest.raises(RuntimeError):
        campaign.preprocessing_terminal({"surface_grid": grid})


def make_campaign_contract(module, path: Path, authority: Path, data: Path, region_names: list[str]) -> dict:
    payload = {
        "schema_version": 1, "stage": "R97", "case_count": 114,
        "status": "campaign_frozen_not_launched", "workers": 20,
        "campaign_root": str(path.parent / "campaign"),
        "regions": region_names, "regions_to_fit": [name for name in region_names if name != "SE_2"],
        "authority_registry": module.file_record(authority, "authority"),
        "source_data_config": module.file_record(data, "data"),
        "final_decision": {
            "aggregation": "unweighted_arithmetic_mean_over_exactly_114_region_fold_cases",
            "per_case_dual_comparator_veto": False,
            "promotion_gate": "candidate_mean_AQL_strictly_below_current_R92_mean_AQL",
        },
        "frozen_comparator_values": {
            "current_authoritative_qdesn_mean_AQL": 5.0,
            "cached_pricefm_mean_AQL": 6.0,
        },
    }
    payload["campaign_contract_sha256"] = module.canonical_sha256(payload)
    write_json(path, payload)
    return payload


def test_global_scoring_prep_and_closeout_use_complete_surface_mean(tmp_path, monkeypatch):
    prep = load("321_prepare_pricefm_stage_r97_global_scoring.py")
    close = load("322_closeout_pricefm_stage_r97_global_surface.py")
    monkeypatch.setattr(prep, "git_identity", lambda _root: FakeGit())
    region_names = regions()
    data = tmp_path / "data.yaml"
    source_data(data, region_names)
    authority = tmp_path / "authority.csv"
    pd.DataFrame([
        {"region": region, "fold": fold, "qdesn_AQL": 5.0, "pricefm_AQL": 6.0}
        for region in region_names for fold in (1, 2, 3)
    ]).to_csv(authority, index=False)
    campaign_path = tmp_path / "campaign.json"
    make_campaign_contract(prep, campaign_path, authority, data, region_names)
    full_config = tmp_path / "full.yaml"
    write_yaml(full_config, {"pricefm_desn_full": {
        "package_path": str(tmp_path), "scope": {"feature_policy": "target_only"},
        "adapter": {"depth": 2, "units": [64, 64]},
        "run": {"nd_predictive": 100}, "artifact_hygiene": {},
    }})
    closeouts = tmp_path / "region_closeouts"
    for region in region_names[1:]:
        root = closeouts / region
        selected = root / "pricefm_stage_r97_selected_atom_manifest.csv"
        rows = [
            {"region": region, "fold": fold, "tau": tau,
             "source_case_config_path": str(full_config)}
            for fold in (1, 2, 3) for tau in QUANTILES
        ]
        selected.parent.mkdir(parents=True)
        pd.DataFrame(rows).to_csv(selected, index=False)
        surface = {
            "region": region, "selected_family": "al", "test_opened": False,
            "per_fold_or_quantile_family_mixing": False,
            "frozen_desn": {"lag_window": 96},
            "selected_atom_manifest": prep.file_record(selected, "selected"),
        }
        write_json(root / "pricefm_stage_r97_frozen_region_surface.json", surface)
        write_json(root / "summary.json", {"status": "completed_region_validation_surface_frozen"})
    args = prep.parser().parse_args([
        "--campaign-contract", str(campaign_path), "--authority-registry", str(authority),
        "--region-closeout-root", str(closeouts), "--source-data-config", str(data),
        "--processed-dir", str(tmp_path / "processed"), "--grid-dir", str(tmp_path / "grid"),
        "--run-dir", str(tmp_path / "runs"), "--output-dir", str(tmp_path / "prep"),
        "--code-root", str(ROOT),
    ])
    summary = prep.run(args)
    manifest = pd.read_csv(args.grid_dir / "task_manifest.csv")
    assert summary["new_scoring_tasks"] == 111
    assert len(manifest) == 111

    for index, row in enumerate(manifest.itertuples(index=False)):
        output = Path(row.output_dir)
        output.mkdir(parents=True)
        write_json(output / "terminal.json", {
            "status": "completed", "task_id": row.task_id,
            "model_fitted": False, "selection_changed": False, "test_opened": True,
        })
        candidate_aql = 8.0 if index == 0 else 4.0
        pd.DataFrame([{
            "region": row.region, "fold": row.fold, "selected_family": "al",
            "AQL": candidate_aql, "current_authoritative_qdesn_AQL": 5.0,
            "cached_pricefm_AQL": 6.0,
        }]).to_csv(output / "test_metric.csv", index=False)
    se2 = tmp_path / "se2.csv"
    pd.DataFrame({
        "region": ["SE_2"] * 3, "fold": [1, 2, 3],
        "candidate_test_AQL": [4.0] * 3,
        "authoritative_qdesn_test_AQL": [5.0] * 3,
        "cached_pricefm_test_AQL": [6.0] * 3,
    }).to_csv(se2, index=False)
    close_args = close.parser().parse_args([
        "--scoring-manifest", str(args.grid_dir / "task_manifest.csv"),
        "--campaign-contract", str(campaign_path), "--authority-registry", str(authority),
        "--se2-comparison", str(se2), "--output-dir", str(tmp_path / "closeout"),
    ])
    result = close.run(close_args)
    assert result["complete_surface_promotion_gate_passed"] is True
    assert result["candidate_mean_AQL"] < result["current_authoritative_qdesn_mean_AQL"]
    assert result["per_case_dual_comparator_veto_used"] is False
    surface = pd.read_csv(tmp_path / "closeout/pricefm_stage_r97_complete_surface.csv")
    assert len(surface) == 114
    assert (surface.AQL > surface.current_authoritative_qdesn_AQL).any()


def test_scoring_worker_replays_validation_and_scores_test_without_refit(tmp_path, monkeypatch):
    module = load("320_score_pricefm_stage_r97_frozen_case.py")
    frozen_adapter = tmp_path / "frozen_adapter"
    frozen_adapter.mkdir()
    rows = pd.DataFrame({"origin_id": [1, 2], "horizon": [1, 1], "y_scaled": [0.0, 0.0]})
    rows.to_csv(frozen_adapter / "rows_val.csv", index=False)
    np.savetxt(frozen_adapter / "X_val.csv", np.array([[1.0, 0.0], [1.0, 0.0]]), delimiter=",")
    (frozen_adapter / "feature_manifest.json").write_text("{}\n")
    scaler = tmp_path / "scaler.joblib"
    joblib.dump({"R01": {"y_scaler": IdentityScaler()}}, scaler)
    selected_rows = []
    for index, tau in enumerate(QUANTILES):
        atom = tmp_path / f"atom_{index}"
        atom.mkdir()
        beta = atom / "beta.csv"
        pd.DataFrame({"feature_index": [1, 2], "beta_mean": [tau, 0.0]}).to_csv(beta, index=False)
        prediction = atom / "prediction.csv"
        pd.DataFrame({
            "origin_id": [1, 2], "horizon": [1, 1], "pred_scaled": [tau, tau],
        }).to_csv(prediction, index=False)
        terminal = atom / "terminal.json"
        write_json(terminal, {"status": "completed"})
        selected_rows.append({
            "region": "R01", "fold": 1, "selected_family": "al", "tau": tau,
            "beta_path": str(beta), "beta_sha256": module.sha256(beta),
            "prediction_path": str(prediction), "prediction_sha256": module.sha256(prediction),
            "terminal_path": str(terminal), "terminal_sha256": module.sha256(terminal),
            "feature_manifest_path": str(frozen_adapter / "feature_manifest.json"),
            "feature_manifest_sha256": module.sha256(frozen_adapter / "feature_manifest.json"),
            "x_val_path": str(frozen_adapter / "X_val.csv"),
            "x_val_sha256": module.sha256(frozen_adapter / "X_val.csv"),
            "rows_val_path": str(frozen_adapter / "rows_val.csv"),
            "rows_val_sha256": module.sha256(frozen_adapter / "rows_val.csv"),
            "scaler_path": str(scaler), "scaler_sha256": module.sha256(scaler),
        })
    selected = tmp_path / "selected.csv"
    pd.DataFrame(selected_rows).to_csv(selected, index=False)
    case_config = tmp_path / "case.yaml"
    write_yaml(case_config, {"fixture": True})
    adapter_script = tmp_path / "adapter.py"
    adapter_script.write_text("# fixture\n")
    adapter_dir = tmp_path / "score_adapter"
    output = tmp_path / "score"

    class FakeAdapter:
        @staticmethod
        def build_adapter(_config, force):
            assert force is True
            adapter_dir.mkdir(parents=True)
            matrix = np.array([[1.0, 0.0], [1.0, 0.0]])
            np.savetxt(adapter_dir / "X_val.csv", matrix, delimiter=",")
            np.savetxt(adapter_dir / "X_test.csv", matrix, delimiter=",")
            np.savetxt(adapter_dir / "y_test.csv", np.zeros(2), delimiter=",")
            rows.to_csv(adapter_dir / "rows_val.csv", index=False)
            rows.to_csv(adapter_dir / "rows_test.csv", index=False)
            (adapter_dir / "feature_manifest.json").write_text("{}\n")

    monkeypatch.setattr(module, "load_adapter", lambda _path: FakeAdapter())
    task = {
        "stage": "R97", "role": "scoring_only_test", "task_id": "score_R01_f1",
        "region": "R01", "fold": 1, "selected_family": "al",
        "selected_atom_manifest": str(selected),
        "selected_atom_manifest_sha256": module.sha256(selected),
        "case_config": str(case_config), "case_config_sha256": module.sha256(case_config),
        "adapter_script": str(adapter_script), "adapter_script_sha256": module.sha256(adapter_script),
        "scorer_script": str(module.SCRIPT_DIR / "320_score_pricefm_stage_r97_frozen_case.py"),
        "scorer_script_sha256": module.sha256(module.SCRIPT_DIR / "320_score_pricefm_stage_r97_frozen_case.py"),
        "adapter_dir": str(adapter_dir), "output_dir": str(output),
        "current_authoritative_qdesn_AQL": 5.0, "cached_pricefm_AQL": 6.0,
        "replay_tolerance": 1e-12, "test_access_authorized": True,
        "test_opened": False, **{name: False for name in module.BLOCKED},
    }
    task_path = tmp_path / "task.json"
    write_json(task_path, task)
    result = module.run(SimpleNamespace(task_config=task_path, code_root=ROOT, force=False))
    assert result["status"] == "completed"
    assert result["model_fitted"] is False
    assert result["selection_changed"] is False
    assert result["validation_replay_max_abs_diff"] == pytest.approx(0.0)
    assert (output / "test_metric.csv").is_file()
    assert not (adapter_dir / "X_test.csv").exists()


def test_controller_requires_global_rule_and_is_fail_closed():
    text = (SCRIPTS / "319_orchestrate_pricefm_stage_r97_global_campaign.py").read_text()
    assert "RUN_PRICEFM_R97_COMPLETE_114_CASE_CAMPAIGN" in text
    assert '"overall_mean_decision": True' in text
    assert '"per_case_dual_comparator_veto": False' in text
    assert '"status": "failed_closed"' in text
    assert 'result[name] = "1"' in text
    assert '[queue[index::len(self.cpus)]' in text
