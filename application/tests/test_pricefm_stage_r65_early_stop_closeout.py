import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def load_module():
    sys.path.insert(0, str(SCRIPTS))
    path = SCRIPTS / "228_closeout_pricefm_stage_r65_early_stop.py"
    spec = importlib.util.spec_from_file_location("r65_early_stop", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_fit_contract(root, family, converged=True):
    fit = root / f"{family}_fit.rds"
    status = root / f"{family}_status.json"
    fit.write_bytes(f"{root}:{family}".encode())
    status.write_text(json.dumps({
        "fit_sha256": digest(fit),
        "converged": converged,
        "fit_state": "completed_converged" if converged else "terminal_nonconverged",
        "package_head": "old-r65-package",
    }))
    return fit


def write_adapter(adapter):
    adapter.mkdir(parents=True)
    for name in (
        "adapter_manifest.json", "feature_manifest.json", "X_train.csv",
        "y_train.csv", "X_val.csv", "y_val.csv", "rows_val.csv",
    ):
        (adapter / name).write_text("{}\n" if name.endswith(".json") else "0\n")


def write_normal(model):
    root = model / "normal_anchor"
    root.mkdir(parents=True)
    fit = root / "normal_rhs_anchor.rds"
    fit.write_bytes(b"normal-anchor")
    (root / "normal_rhs_anchor.json").write_text(json.dumps({
        "fit_sha256": digest(fit), "converged": True, "package_head": "old-r65-package",
    }))


def fixture(tmp_path):
    rows = []
    component_rows = []
    for index, state in enumerate(("complete", "partial", "not_started"), start=1):
        case_id = f"pricefm_joint_aa_f{index}"
        root = tmp_path / "runs" / case_id
        adapter = root / "adapter"
        model = root / "model"
        rows.append({
            "case_id": case_id,
            "region": "AA",
            "fold": index,
            "adapter_dir": str(adapter),
            "output_dir": str(model),
            "config_sha256": "a" * 64,
            "package_commit": "old-r65-package",
            "legacy_selected_family": "al",
            "legacy_selected_validation_AQL": 5.0,
            "legacy_al_validation_AQL": 5.0,
            "legacy_exal_validation_AQL": 5.2,
        })
        for tau in TAUS:
            component_rows.append({
                "case_id": case_id, "region": "AA", "fold": index, "tau": tau,
            })
        if state == "not_started":
            continue
        write_adapter(adapter)
        model.mkdir(parents=True)
        write_normal(model)
        limit = 7 if state == "complete" else 2
        for tau_index, tau in enumerate(TAUS):
            if tau_index >= limit:
                break
            slug = str(float(tau)).rstrip("0").rstrip(".").replace(".", "p")
            component = model / "components" / f"tau={slug}"
            component.mkdir(parents=True)
            write_fit_contract(component, "al", converged=True)
            (component / "al_predictions_scaled.csv").write_text("split,pred_scaled\nval,0\n")
            (component / "al_method_summary.csv").write_text("method_id\nal\n")
            if state == "complete" or tau_index == 0:
                write_fit_contract(component, "exal", converged=(tau == 0.5))
                (component / "component_terminal.json").write_text(json.dumps({
                    "selection_eligible": tau == 0.5,
                }))
        if state != "complete":
            continue
        pd.DataFrame([
            {"method_id": "qdesn_al_rhs_ns_exact_chunked_r65_parity", "split": "val", "unit": "original", "AQL": 5.0, "AQCR": 0.02},
            {"method_id": "qdesn_exal_rhs_ns_exact_chunked_structured_r65", "split": "val", "unit": "original", "AQL": 50.0, "AQCR": 0.50},
        ]).to_csv(model / "metric_summary.csv", index=False)
        pd.DataFrame([{
            "method_id": "qdesn_exal_rhs_ns_exact_chunked_structured_r65",
            "tau": tau,
            "gamma": 0.0 if tau == 0.5 else (7.0 if tau < 0.5 else -7.0),
            "sigma": 0.02,
            "beta_l2": 20.0,
            "beta_max_abs": 10.0,
        } for tau in TAUS]).to_csv(model / "model_parameter_summary.csv", index=False)
        pd.DataFrame([{
            "tau": tau,
            "exal_converged": tau == 0.5,
            "selection_eligible": tau == 0.5,
        } for tau in TAUS]).to_csv(model / "r65_component_status.csv", index=False)
        (model / "r65_case_fit_summary.json").write_text("{}\n")
        pd.DataFrame([{"split": "val", "pred_scaled": 0.0}]).to_csv(
            model / "model_predictions_scaled.csv", index=False
        )
    manifest = tmp_path / "case_manifest.csv"
    components = tmp_path / "component_ledger.csv"
    launch = tmp_path / "launch_status.csv"
    pd.DataFrame(rows).to_csv(manifest, index=False)
    pd.DataFrame(component_rows).to_csv(components, index=False)
    pd.DataFrame([{"case_id": rows[0]["case_id"], "status": "completed_with_quarantine"}]).to_csv(
        launch, index=False
    )
    return manifest, components, launch, rows


def test_r65_early_stop_freezes_all_cases_and_reusable_checkpoints(tmp_path, monkeypatch):
    module = load_module()
    monkeypatch.setattr(module, "active_r65_processes", lambda: [])
    manifest, components, launch, _ = fixture(tmp_path)
    output = tmp_path / "closeout"
    args = module.parser().parse_args([
        "--manifest", str(manifest),
        "--component-ledger", str(components),
        "--launch-status", str(launch),
        "--output-dir", str(output),
        "--expected-cases", "3",
    ])
    summary = module.run(args)
    cases = pd.read_csv(output / "pricefm_stage_r65_early_stop_case_inventory.csv")
    reuse = pd.read_csv(output / "pricefm_stage_r65_checkpoint_reuse_manifest.csv")
    queue = pd.read_csv(output / "pricefm_stage_r65_promotion_queue.csv")

    assert summary["status"] == "scientifically_stopped_mechanism_failure"
    assert summary["metric_complete_cases"] == 1
    assert summary["partial_checkpointed_cases"] == 1
    assert summary["not_started_cases"] == 1
    assert summary["terminal_components"] == 8
    assert summary["valid_al_fit_checkpoints"] == 9
    assert summary["valid_exal_fit_checkpoints"] == 8
    assert summary["completed_case_structured_winners"] == 0
    assert set(cases.early_stop_state) == {"metric_complete", "partial_checkpointed", "not_started"}
    assert len(reuse) == 21
    assert int(reuse.reuse_al_fit_authorized.sum()) == 9
    assert queue.empty
    assert summary["test_opened"] is False
    assert summary["r66_authorized"] is False


def test_r65_early_stop_rejects_test_artifacts(tmp_path, monkeypatch):
    module = load_module()
    monkeypatch.setattr(module, "active_r65_processes", lambda: [])
    manifest, components, launch, rows = fixture(tmp_path)
    (Path(rows[1]["adapter_dir"]) / "X_test.csv").write_text("0\n")
    args = module.parser().parse_args([
        "--manifest", str(manifest),
        "--component-ledger", str(components),
        "--launch-status", str(launch),
        "--output-dir", str(tmp_path / "closeout"),
        "--expected-cases", "3",
    ])
    try:
        module.run(args)
    except RuntimeError as exc:
        assert "test firewall violation" in str(exc)
    else:
        raise AssertionError("R65 early-stop closeout accepted a test artifact")
