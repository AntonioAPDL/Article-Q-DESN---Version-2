import importlib.util
import json
from pathlib import Path
import sys
import threading
import time

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def load(name, filename):
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def source_bundle(repo, region="AA", fold=1):
    configs = []
    metrics = []
    features = []
    data = repo / "data.yaml"
    data.write_text("pricefm:\n  processed_dir: processed\n  regions: [AA]\n")
    for tau in TAUS:
        root = repo / f"legacy_tau_{str(tau).replace('.', 'p')}"
        root.mkdir(parents=True)
        config = root / "config.yaml"
        smoke = {
            "data_config": str(data),
            "package_path": str(repo / "package"),
            "region": region,
            "fold": fold,
            "splits": ["train", "val", "test"],
            "horizons": [1, 2],
            "quantiles": [tau],
            "feature_policy": "target_only",
            "adapter": {
                "output_dir": str(root / "adapter"),
                "feature_map": "window_reservoir_v1",
                "feature_dim": 8,
                "depth": 1,
                "units": [8],
                "alpha": 0.2,
                "rho": 0.95,
                "input_scale": 0.2,
                "projection_scale": 1.0,
                "recurrent_sparsity": 0.05,
                "state_output": "final_layer",
                "seed": 10,
            },
            "run": {"output_dir": str(root / "model"), "seed": 10},
            "rhs_ns": {"tau0": 0.001},
            "normal": {"omega_prior": {"a": 2, "b": 1}, "vb_control": {"max_iter": 10}},
            "qdesn_vb": {
                "likelihoods": ["al", "exal"],
                "max_iter": 10,
                "min_iter_elbo": 5,
                "tol": 1e-4,
                "tol_par": 1e-4,
                "n_samp_xi": 5,
                "prior_sigma": {"a": 1, "b": 1},
                "prior_gamma": {"mu0": 0, "s20": 10},
                "chunking": {"enabled": True, "mode": "exact", "chunk_size": 8},
            },
            "exact_equivalence": {"enabled": True, "quantile": tau},
            "training": {"train_origin_limit": 10},
            "warm_start": {"qdesn": {"al": {"tau_order": [tau]}}},
        }
        config.write_text(yaml.safe_dump({"pricefm_desn_smoke": smoke}, sort_keys=False))
        metric = root / "metric_summary.csv"
        pd.DataFrame([
            {"method_id": "qdesn_al_rhs_ns_exact_chunked", "split": "val", "unit": "original", "AQL": tau},
            {"method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "val", "unit": "original", "AQL": tau + 0.1},
        ]).to_csv(metric, index=False)
        feature = root / "feature_manifest.json"
        feature.write_text("{}\n")
        configs.append(str(config)); metrics.append(str(metric)); features.append(str(feature))
    return configs, metrics, features


def test_r65_prep_builds_complete_case_grouped_contract(tmp_path, monkeypatch):
    module = load("r65_prep", "223_prepare_pricefm_stage_r65_independent_structured_exal_vb.py")
    repo = tmp_path / "repo"; repo.mkdir()
    package = tmp_path / "package"; package.mkdir()
    library = tmp_path / "library"; library.mkdir()
    (library / "pricefm_r65_install_manifest.json").write_text("{}\n")
    configs, metrics, features = source_bundle(repo)
    r62 = tmp_path / "r62"; r62.mkdir()
    panel = str(tmp_path / "panel")
    base = "case_aa_f1"
    ledger_rows = []
    for family, method, value in [
        ("al", "qdesn_al_rhs_ns_exact_chunked", 0.5),
        ("exal", "qdesn_exal_rhs_ns_exact_chunked", 0.6),
    ]:
        ledger_rows.append({
            "panel_dir": panel, "base_id": base, "region": "AA", "fold": 1,
            "likelihood_family": family, "method_id": method,
            "paper_quantiles": json.dumps(TAUS), "component_count": 7,
            "scientific_contract_sha256": "a" * 64, "feature_semantics_sha256": "b" * 64,
            "validation_AQL_recomputed": value, "validation_AQL_panel": value,
            "panel_metric_matches": True, "config_paths": json.dumps(configs),
            "feature_manifest_paths": json.dumps(features), "metric_paths": json.dumps(metrics),
            "integrity_pass": True,
        })
    pd.DataFrame(ledger_rows).to_csv(r62 / "pricefm_stage_r62_candidate_bundle_ledger.csv", index=False)
    pd.DataFrame([{
        "case_id": "pricefm_joint_aa_f1", "region": "AA", "fold": 1,
        "selected_panel_dir": panel, "selected_base_id": base,
        "selected_seven_quantile_family": "al", "selected_seven_quantile_validation_AQL": 0.5,
        "scientific_contract_sha256": "a" * 64, "feature_semantics_sha256": "b" * 64,
    }]).to_csv(r62 / "pricefm_stage_r62_matched_seven_quantile_authority.csv", index=False)
    (r62 / "summary.json").write_text(json.dumps({
        "matched_cells": 1, "coverage_gap_cells": 0, "provenance_conflict_cells": 0,
    }))
    monkeypatch.setattr(module, "verify_package", lambda path: {
        "path": str(package), "commit": module.PACKAGE_COMMIT,
        "source_sha256": module.PACKAGE_HASHES,
    })
    monkeypatch.setattr(module, "verify_runtime_library", lambda path: str(library))
    args = module.parser().parse_args([
        "--code-root", str(ROOT), "--artifact-repo", str(repo), "--r62-dir", str(r62),
        "--package-path", str(package), "--python-bin", str(tmp_path / "python"),
        "--grid-dir", str(tmp_path / "grid"), "--run-dir", str(tmp_path / "runs"),
        "--output-dir", str(tmp_path / "output"), "--expected-cases", "1",
    ])
    summary = module.run(args)
    cases = pd.read_csv(tmp_path / "grid/case_manifest.csv")
    components = pd.read_csv(tmp_path / "grid/component_ledger.csv")
    generated = yaml.safe_load(Path(cases.iloc[0].config).read_text())
    smoke = generated["pricefm_desn_smoke"]
    r65 = generated["pricefm_stage_r65"]
    assert summary["planned_case_jobs"] == 1
    assert len(components) == 7
    assert smoke["splits"] == ["train", "val"]
    assert smoke["quantiles"] == list(TAUS)
    assert smoke["warm_start"]["qdesn"]["al"]["source_each_tau"] == "shared_normal_rhs_anchor"
    assert r65["structured_sigmagam"]["factorization"] == "structured"
    assert set(r65["code"]["source_sha256"]) == set(module.RUNTIME_CODE_SOURCES)
    assert r65["test_access_authorized"] is False
    assert not list((tmp_path / "grid").glob("*.yaml"))


def test_r65_runner_contract_is_explicit_and_atomic():
    runner = (SCRIPTS / "224_run_pricefm_stage_r65_independent_structured_exal_vb_case.R").read_text()
    helper = (SCRIPTS / "pricefm_stage_r65_vb_helpers.R").read_text()
    assert 'source_each_tau' not in runner  # runner enforces the sequence directly
    assert '"shared_normal_rhs_anchor"' in runner
    assert 'paste0("same_tau_al_", r65_tau_key(tau))' in runner
    assert "r65_atomic_save_rds" in runner
    assert "Pinned R65 runtime source hash mismatch" in runner
    assert "normalizePath(cfg$python_bin" not in runner
    assert "path.expand(as.character(cfg$python_bin))" in runner
    assert "structured_telemetry_pass" in runner
    assert "exal_make_vb_sigmagam_control" in helper
    assert 'factorization = as.character(profile$factorization)' in helper


def test_r65_launcher_requires_authorization_and_twenty_workers(tmp_path):
    module = load("r65_launcher", "225_launch_pricefm_stage_r65_independent_structured_exal_vb.py")
    manifest = pd.DataFrame([{
        "case_id": "x", "region": "AA", "fold": 1,
        **{name: False for name in [
            "launch_authorized", "test_access_authorized", "registry_mutation_authorized",
            "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
        ]},
    }])
    args = module.parser().parse_args([
        "--code-root", str(ROOT), "--manifest", str(tmp_path / "manifest.csv"),
        "--cpu-list", "0-19", "--expected-cases", "1",
    ])
    try:
        module.preflight(manifest, args, list(range(20)))
    except RuntimeError as exc:
        assert "--authorize true" in str(exc)
    else:
        raise AssertionError("R65 launcher accepted an unauthorized launch")


def test_r65_launcher_reuses_a_cpu_only_after_its_case_exits(tmp_path, monkeypatch):
    module = load("r65_scheduler", "225_launch_pricefm_stage_r65_independent_structured_exal_vb.py")
    manifest_path = tmp_path / "case_manifest.csv"
    pd.DataFrame([
        {"case_id": f"case_{index}", "region": "AA", "fold": index + 1}
        for index in range(6)
    ]).to_csv(manifest_path, index=False)
    active = set()
    collisions = []
    lock = threading.Lock()

    def fake_run_one(row, cpu, code_root, python_bin):
        with lock:
            if cpu in active:
                collisions.append(cpu)
            active.add(cpu)
        time.sleep(0.01 if row["fold"] % 2 else 0.03)
        with lock:
            active.remove(cpu)
        return {**row, "cpu": cpu, "status": "completed", "returncode": 0}

    monkeypatch.setattr(module, "run_one", fake_run_one)
    monkeypatch.setattr(module, "preflight", lambda manifest, args, cpus: {
        "manifest_cases": len(manifest), "workers": args.workers,
    })
    args = module.parser().parse_args([
        "--code-root", str(ROOT), "--manifest", str(manifest_path),
        "--cpu-list", "0,1", "--workers", "2", "--expected-cases", "6",
        "--authorize", "true",
    ])
    summary = module.run(args)
    status = pd.read_csv(tmp_path / "launch_status.csv")
    assert collisions == []
    assert len(status) == 6
    assert summary["status"] == "completed"


def test_r65_completion_requires_both_full_quantile_methods(tmp_path):
    module = load("r65_completion", "225_launch_pricefm_stage_r65_independent_structured_exal_vb.py")
    output = tmp_path / "model"; output.mkdir()
    (output / "r65_case_fit_summary.json").write_text(json.dumps({
        "terminal_components": 7, "eligible_components": 7, "test_loaded": False,
    }))
    (output / "run_manifest.json").write_text("{}\n")
    pd.DataFrame([{"selection_eligible": True}] * 7).to_csv(output / "r65_component_status.csv", index=False)
    rows = []
    for method in module.METHODS:
        for tau in TAUS:
            rows.append({"method_id": method, "split": "val", "tau": tau, "origin_id": 1, "horizon": 1, "pred_scaled": 0})
    pd.DataFrame(rows).to_csv(output / "model_predictions_scaled.csv", index=False)
    pd.DataFrame([{"method_id": method} for method in module.METHODS]).to_csv(output / "model_method_summary.csv", index=False)
    pd.DataFrame([
        {"method_id": method, "split": "val", "unit": "original", "AQL": 1}
        for method in module.METHODS
    ]).to_csv(output / "metric_summary.csv", index=False)
    assert module.completion_state(output) == "completed"


def test_r65_closeout_selects_whole_structured_bundle_after_parity(tmp_path):
    module = load("r65_closeout", "227_closeout_pricefm_stage_r65_independent_structured_exal_vb.py")
    model = tmp_path / "case/model"; model.mkdir(parents=True)
    adapter = tmp_path / "case/adapter"; adapter.mkdir(parents=True)
    pd.DataFrame([{"origin_id": 1, "horizon": 1, "y_scaled": 1.0}]).to_csv(adapter / "rows_val.csv", index=False)
    predictions = []
    for tau in TAUS:
        predictions.extend([
            {"method_id": module.METHOD_AL, "split": "val", "origin_id": 1, "horizon": 1, "tau": tau, "pred_scaled": 0.0},
            {"method_id": module.METHOD_EXAL, "split": "val", "origin_id": 1, "horizon": 1, "tau": tau, "pred_scaled": 0.2},
        ])
    pd.DataFrame(predictions).to_csv(model / "model_predictions_scaled.csv", index=False)
    pd.DataFrame([
        {"method_id": module.METHOD_AL, "split": "val", "unit": unit, "AQL": 0.5}
        for unit in ["scaled", "original"]
    ] + [
        {"method_id": module.METHOD_EXAL, "split": "val", "unit": unit, "AQL": 0.4}
        for unit in ["scaled", "original"]
    ]).to_csv(model / "metric_summary.csv", index=False)
    pd.DataFrame([{
        "tau": tau, "selection_eligible": True, "structured_telemetry_pass": True,
    } for tau in TAUS]).to_csv(model / "r65_component_status.csv", index=False)
    (model / "r65_case_fit_summary.json").write_text("{}\n")

    manifest = tmp_path / "manifest.csv"
    pd.DataFrame([{
        "case_id": "case", "region": "AA", "fold": 1, "output_dir": str(model),
        "adapter_dir": str(adapter), "legacy_selected_family": "al",
        "legacy_selected_validation_AQL": 0.5, "legacy_al_validation_AQL": 0.5,
        "legacy_exal_validation_AQL": 0.6,
    }]).to_csv(manifest, index=False)
    component = tmp_path / "components.csv"
    pd.DataFrame([{
        "case_id": "case", "region": "AA", "fold": 1, "tau": tau,
        "legacy_al_validation_AQL": tau, "legacy_exal_validation_AQL": tau + 0.1,
    } for tau in TAUS]).to_csv(component, index=False)
    status = tmp_path / "status.csv"
    pd.DataFrame([{"case_id": "case", "status": "completed"}]).to_csv(status, index=False)
    args = module.parser().parse_args([
        "--manifest", str(manifest), "--component-ledger", str(component),
        "--launch-status", str(status), "--output-dir", str(tmp_path / "closeout"),
        "--expected-cases", "1",
    ])
    summary = module.run(args)
    decisions = pd.read_csv(tmp_path / "closeout/pricefm_stage_r65_case_decisions.csv")
    assert summary["structured_exal_validation_winners"] == 1
    assert decisions.iloc[0].selected_family == "structured_exal"
    assert bool(decisions.iloc[0].al_parity_pass)
    assert summary["test_opened"] is False
