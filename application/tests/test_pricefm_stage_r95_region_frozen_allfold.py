"""Focused tests for the executable R95 region-frozen all-fold workflow."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
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


def record(module, path: Path, role: str) -> dict:
    return module.file_record(path, role)


def make_source_data(path: Path) -> None:
    path.write_text(yaml.safe_dump({
        "pricefm": {
            "repo_id": "fixture",
            "filename": "FINAL.csv",
            "raw_dir": "application/data_local/pricefm/raw",
            "interim_dir": "application/data_local/pricefm/interim",
            "processed_dir": "application/data_local/pricefm/processed",
            "external_repo_dir": "application/data_local/pricefm/external",
            "log_dir": "application/logs/pricefm",
            "regions": ["SE_2", "NO_3", "NO_4", "SE_1", "SE_3"],
            "features": {
                "label": "price", "raw": ["price", "load", "solar", "wind"],
                "lag": ["price", "load", "solar", "wind"],
                "lead": ["load", "solar", "wind"],
            },
            "splits": [
                {"fold": 1, "train": ["a", "b"], "val": ["b", "c"], "test": ["c", "d"]},
                {"fold": 2, "train": ["a", "c"], "val": ["c", "d"], "test": ["d", "e"]},
                {"fold": 3, "train": ["a", "d"], "val": ["d", "e"], "test": ["e", "f"]},
            ],
            "windows": {
                "lag_window": 96, "lead_window": 96,
                "train_boundary_mode": "contained_half_open",
                "validation_boundary_mode": "operational_half_open",
                "test_boundary_mode": "operational_half_open",
            },
            "pilot": {"enabled": True, "region": "SE_2", "fold": 1},
        }
    }, sort_keys=False))


def make_prep_fixture(tmp_path: Path):
    module = load("307_prepare_pricefm_stage_r95_region_frozen_allfold.py")
    adapter_scripts = []
    for index in range(3):
        path = tmp_path / f"adapter_{index}.R"
        path.write_text(f"# adapter {index}\n")
        adapter_scripts.append({
            "path": str(path), "role": "public_API_adapter",
            "sha256": module.sha256_file(path), "bytes": path.stat().st_size,
        })
    r93_config = tmp_path / "r93_config.yaml"
    r93_data = tmp_path / "r93_data.yaml"
    r93_data.write_text(yaml.safe_dump({"pricefm": {
        "splits": [{"fold": 1, "train": ["a", "b"], "val": ["b", "c"]}]
    }}))
    r93_config.write_text(yaml.safe_dump({"pricefm_desn_smoke": {
        "splits": ["train", "val"],
        "adapter": {
            "feature_map": "window_reservoir_v1", "feature_dim": 64,
            "seed": 2026090601, "row_chunk_size": 512,
            "recurrent_sparsity": 0.05, "reservoir_activation": "tanh",
            "spatial": {"neighbor_regions": ["NO_3", "NO_4", "SE_1", "SE_3"]},
        }
    }}))
    r93_task = tmp_path / "r93_task.json"
    write_json(r93_task, {
        "stage": "R93", "selection_split": "val",
        "quantiles": list(module.PAPER_QUANTILES), "config": str(r93_config),
        "data_config": str(r93_data),
        "adapter_scripts": adapter_scripts, "test_opened": False,
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False,
    })
    families = {"al": [], "exal": []}
    for family in families:
        for tau in module.PAPER_QUANTILES:
            root = tmp_path / "r94" / family / str(tau)
            root.mkdir(parents=True)
            beta = root / "beta.csv"
            prediction = root / "prediction.csv"
            terminal = root / "terminal.json"
            beta.write_text("beta_mean\n0\n")
            prediction.write_text("pred_scaled\n0\n")
            write_json(terminal, {"status": "completed", "numerical_gate_passed": True})
            families[family].append({
                "tau": tau,
                "beta": record(module, beta, "beta"),
                "prediction": record(module, prediction, "prediction"),
                "terminal": record(module, terminal, "terminal"),
            })
    frozen = tmp_path / "r94_frozen.json"
    write_json(frozen, {
        "schema_version": 1, "stage": "R94",
        "status": "validation_family_frozen_awaiting_allfold_pretest_fit",
        "region": "SE_2", "selection_fold": 1,
        "quantiles": list(module.PAPER_QUANTILES), "selected_family": "exal",
        "per_quantile_family_mixing": False,
        "frozen_desn": {
            "feature_policy": "graph_summary_mean", "depth": 2,
            "units": "[120,64]", "lag_window": 240, "alpha": 0.5,
            "rho": 0.95, "input_scale": 0.15, "state_output": "final_layer",
            "tau0": 0.01,
        },
        "rhs_tau0": 0.01, "selected_atoms": families["exal"],
        "all_family_atoms": families, "test_opened": False,
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False,
    })
    source_data = tmp_path / "data.yaml"
    make_source_data(source_data)
    normal_package = tmp_path / "normal_package"
    normal_package.mkdir()
    runtime = tmp_path / "runtime"
    (runtime / "exdqlm").mkdir(parents=True)
    runtime_manifest = runtime / "pricefm_stage_r94_coherent_exal_init_manifest.json"
    write_json(runtime_manifest, {
        "status": "installed_coherent_exal_initialization_runtime",
        "version": "1.1.1.9005",
        "repair": "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-plus-structured-plugin-init-plus-coherent-al-latent-init",
        "test_opened": False, "test_access_authorized": False,
    })
    args = SimpleNamespace(
        r94_frozen=frozen, r93_task=r93_task, source_data_config=source_data,
        normal_package=normal_package, r94_library=runtime,
        r94_runtime_manifest=runtime_manifest, grid_dir=tmp_path / "grid",
        run_dir=tmp_path / "runs", processed_dir=tmp_path / "processed",
        output_dir=tmp_path / "prep", code_root=ROOT, workers=20,
        quarantine_root=None, quarantine_existing=False, skip_git_check=True,
    )
    return module, args


def test_r95_prep_materializes_exact_dependency_graph_and_test_firewall(tmp_path):
    module, args = make_prep_fixture(tmp_path)
    summary = module.run(args)
    assert summary["tasks"] == 30
    assert summary["selected_family"] == "exal"
    manifest = pd.read_csv(args.grid_dir / "task_manifest.csv")
    assert manifest.likelihood_family.value_counts().to_dict() == {
        "al": 14, "exal": 14, "normal_rhs": 2,
    }
    assert set(manifest.fold) == {2, 3}
    assert not manifest.test_access_authorized.astype(bool).any()
    data = yaml.safe_load((args.grid_dir / "configs/pricefm_stage_r95_train_validation_data.yaml").read_text())
    assert all(set(split) == {"fold", "train", "val"} for split in data["pricefm"]["splits"])
    assert data["pricefm"]["windows"]["lag_window"] == 240
    normal = yaml.safe_load((args.grid_dir / "configs/pricefm_stage_r95_normal_rhs.yaml").read_text())
    assert normal["pricefm_desn_full"]["python_bin"].endswith("/pricefm/venv/bin/python")
    tasks = [json.loads(Path(path).read_text()) for path in manifest.task_config]
    for fold in (2, 3):
        normal = next(task for task in tasks if task["fold"] == fold and task["likelihood_family"] == "normal_rhs")
        al50 = next(task for task in tasks if task["fold"] == fold and task["likelihood_family"] == "al" and task["tau"] == 0.5)
        assert al50["parent_task_ids"] == [normal["task_id"]]
        for tau in module.PAPER_QUANTILES:
            al = next(task for task in tasks if task["fold"] == fold and task["likelihood_family"] == "al" and task["tau"] == tau)
            exal = next(task for task in tasks if task["fold"] == fold and task["likelihood_family"] == "exal" and task["tau"] == tau)
            assert exal["parent_task_ids"] == [al["task_id"]]
            assert exal["warm_start_mode"] == "al_qbeta_rhs_latent_first"


def test_r95_launcher_requires_explicit_authorization_and_caps_threads():
    text = (SCRIPTS / "309_launch_pricefm_stage_r95_allfold.py").read_text()
    assert 'APPROVAL_TOKEN = "RUN_PRICEFM_R95_ALLFOLD_VALIDATION"' in text
    assert "args.workers > 20" in text
    assert 'environment[name] = "1"' in text
    assert '"taskset", "-c"' in text
    assert "validate_git_identity" in text
    assert "quarantine_invalid_task" in text
    assert "closeout_output_dir" in text


def test_r95_cpu_parser_rejects_duplicates_and_bad_ranges():
    module = load("309_launch_pricefm_stage_r95_allfold.py")
    assert module.parse_cpus("2-4,7") == [2, 3, 4, 7]
    with pytest.raises(RuntimeError):
        module.parse_cpus("2,2")
    with pytest.raises(RuntimeError):
        module.parse_cpus("4-2")


def make_closeout_fixture(tmp_path: Path, *, exal_ineligible: bool = False):
    module = load("310_closeout_pricefm_stage_r95_allfold_validation.py")
    rows = pd.DataFrame({
        "origin_id": [1] * 96,
        "horizon": list(range(1, 97)),
        "y_scaled": np.zeros(96),
    })
    fold1_adapter = tmp_path / "fold1_adapter"
    fold1_adapter.mkdir()
    rows.to_csv(fold1_adapter / "rows_val.csv", index=False)
    fold1_scaler = tmp_path / "fold1_scaler.joblib"
    joblib.dump({"SE_2": {"y_scaler": IdentityScaler()}}, fold1_scaler)
    families = {"al": [], "exal": []}
    for family, prediction_value in (("al", 1.0), ("exal", 0.5)):
        for tau in module.PAPER_QUANTILES:
            root = tmp_path / "fold1" / family / str(tau)
            root.mkdir(parents=True)
            beta = root / "beta.csv"
            beta.write_text("beta_mean\n0\n")
            prediction = root / "prediction.csv"
            frame = rows[["origin_id", "horizon"]].copy()
            frame.insert(0, "split", "val")
            frame.insert(0, "method_id", family)
            frame["tau"] = tau
            frame["pred_scaled"] = prediction_value
            frame.to_csv(prediction, index=False)
            terminal = root / "terminal.json"
            write_json(terminal, {"status": "completed", "numerical_gate_passed": True})
            families[family].append({
                "tau": tau,
                "beta": record(module, beta, "beta"),
                "prediction": record(module, prediction, "prediction"),
                "terminal": record(module, terminal, "terminal"),
            })
    frozen = tmp_path / "frozen.json"
    write_json(frozen, {
        "selected_family": "exal", "test_opened": False, "region": "SE_2",
        "frozen_desn": {"depth": 2}, "rhs_tau0": 0.01,
        "adapter_files": [record(module, fold1_adapter / "rows_val.csv", "adapter_rows_val.csv")],
        "scaler": record(module, fold1_scaler, "fold1_scaler"),
        "all_family_atoms": families,
    })

    processed = tmp_path / "processed"
    data_config = tmp_path / "data.yaml"
    data_config.write_text(yaml.safe_dump({"pricefm": {"processed_dir": str(processed)}}))
    manifest_rows = []
    for fold in (2, 3):
        scaler = processed / "scalers" / f"fold_{fold}" / "per_region_separate_xy_scalers.joblib"
        scaler.parent.mkdir(parents=True)
        joblib.dump({"SE_2": {"y_scaler": IdentityScaler()}}, scaler)
        adapter = tmp_path / f"adapter_{fold}"
        adapter.mkdir()
        rows.to_csv(adapter / "rows_val.csv", index=False)
        for name in ("X_train.csv", "y_train.csv", "rows_train.csv", "X_val.csv", "y_val.csv"):
            (adapter / name).write_text("0\n")
        normal_task = {
            "task_id": f"normal_{fold}", "stage": "R95", "fold": fold,
            "region": "SE_2", "likelihood_family": "normal_rhs",
            "pipeline_contract_sha256": "pipeline", "selection_split": "val",
        }
        normal_path = tmp_path / "tasks" / f"normal_{fold}.json"
        write_json(normal_path, normal_task)
        manifest_rows.append({
            "task_id": normal_task["task_id"], "fold": fold,
            "task_config": str(normal_path), "task_config_sha256": module.sha256_file(normal_path),
        })
        for family, prediction_value in (("al", 1.0), ("exal", 0.5)):
            for tau in module.PAPER_QUANTILES:
                task_id = f"{family}_{fold}_{tau}"
                output = tmp_path / "outputs" / task_id
                output.mkdir(parents=True)
                beta = output / "beta_summary.csv"
                beta.write_text("beta_mean,beta_cov_diag\n0,1\n")
                prediction = output / "predictions_scaled.csv"
                frame = rows[["origin_id", "horizon"]].copy()
                frame.insert(0, "split", "val")
                frame.insert(0, "method_id", family)
                frame["tau"] = tau
                frame["pred_scaled"] = prediction_value
                frame.to_csv(prediction, index=False)
                parameter = output / "parameter_summary.csv"
                parameter.write_text("sigma\n1\n")
                ineligible = exal_ineligible and family == "exal" and fold == 3 and tau == 0.9
                terminal_path = output / "terminal.json"
                artifacts = [
                    record(module, beta, "beta_summary"),
                    record(module, prediction, "predictions_scaled"),
                    record(module, parameter, "parameter_summary"),
                ]
                write_json(terminal_path, {
                    "status": "completed_numerically_ineligible" if ineligible else "completed",
                    "task_id": task_id, "pipeline_contract_sha256": "pipeline",
                    "numerical_gate_passed": not ineligible, "artifacts": artifacts,
                    "test_loaded": False, "test_opened": False,
                    "test_access_authorized": False,
                })
                task = {
                    "task_id": task_id, "stage": "R95", "fold": fold,
                    "region": "SE_2", "likelihood_family": family, "tau": tau,
                    "pipeline_contract_sha256": "pipeline", "selection_split": "val",
                    "adapter_dir": str(adapter), "data_config": str(data_config),
                    "output_dir": str(output),
                }
                task_path = tmp_path / "tasks" / f"{task_id}.json"
                write_json(task_path, task)
                manifest_rows.append({
                    "task_id": task_id, "fold": fold,
                    "task_config": str(task_path),
                    "task_config_sha256": module.sha256_file(task_path),
                })
    manifest = tmp_path / "manifest.csv"
    pd.DataFrame(manifest_rows).to_csv(manifest, index=False)
    return module, manifest, frozen


def test_r95_closeout_retains_frozen_exal_when_all_atoms_are_eligible(tmp_path):
    module, manifest, frozen = make_closeout_fixture(tmp_path)
    summary = module.run(SimpleNamespace(
        manifest=manifest, r94_frozen=frozen, output_dir=tmp_path / "closeout",
        quarantine_root=None, quarantine_existing=False,
    ))
    assert summary["effective_whole_region_family"] == "exal"
    assert summary["whole_region_AL_fallback_used"] is False
    metrics = pd.read_csv(tmp_path / "closeout/pricefm_stage_r95_fold_family_validation_metrics.csv")
    assert len(metrics) == 6
    assert (metrics[metrics.family == "exal"].AQL < metrics[metrics.family == "al"].AQL.to_numpy()).all()


def test_r95_closeout_uses_whole_region_al_fallback_without_mixing(tmp_path):
    module, manifest, frozen = make_closeout_fixture(tmp_path, exal_ineligible=True)
    summary = module.run(SimpleNamespace(
        manifest=manifest, r94_frozen=frozen, output_dir=tmp_path / "closeout",
        quarantine_root=None, quarantine_existing=False,
    ))
    assert summary["effective_whole_region_family"] == "al"
    assert summary["whole_region_AL_fallback_used"] is True
    surface = json.loads((tmp_path / "closeout/pricefm_stage_r95_frozen_allfold_validation_surface.json").read_text())
    assert surface["per_fold_or_quantile_family_mixing"] is False
    assert set(surface["selected_atoms"]) == {"1", "2", "3"}


def test_r95_quantile_worker_uses_repaired_exal_and_writes_no_binary_objects():
    text = (SCRIPTS / "308_run_pricefm_stage_r95_quantile_atom.R").read_text()
    assert 'family %in% c("al", "exal")' in text
    assert 'warm_start_mode <- "al_qbeta_rhs_latent_first"' in text
    assert "r75_fit_quantile" in text
    assert "dqlm.ind = TRUE" in text
    assert "tail_prediction_scaled_below_0p01" in text
    assert ".rds" not in text.lower()
