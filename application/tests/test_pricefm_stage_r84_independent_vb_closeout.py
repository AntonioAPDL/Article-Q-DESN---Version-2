import hashlib
import importlib.util
import json
from pathlib import Path

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/278_closeout_pricefm_stage_r83_independent_vb_surface.py"


def load_script():
    spec = importlib.util.spec_from_file_location("pricefm_r84_closeout", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_closeout_reuses_only_valid_r76_and_exact_r83_replacements():
    text = SCRIPT.read_text()
    assert 'source_stage.value_counts().to_dict() != {"R76": 280, "R83": 14}' in text
    assert "len(frame) != 294" in text and "frame.case_id.nunique() != 42" in text
    assert 'r83_summary.get("failed") != 0' in text
    assert "validate_output(output, source_task, source_stage)" in text
    assert 'required.append("structured_initialization.json")' in text
    assert '"1.1.1.9002"' in text and '"1.1.1.9004"' in text


def test_selection_is_case_specific_raw_validation_only():
    text = SCRIPT.read_text()
    assert '"exal_raw_beats_al"' in text
    assert 'selected, reason = "exal", "lower_raw_validation_AQL_and_integrity_pass"' in text
    assert '"raw_original_seven_quantile_validation_AQL_with_integrity_guard"' in text
    assert '"rearrangement_is_sensitivity_only"' in text
    assert "len(selection) != 56 or len(selected_manifest) != 392" in text
    assert 'source_stage != "R83"' in text
    assert "max_sigma < 100" in text and "beta_l2_ratio < 10" in text
    assert "max_abs_gamma < 4" in text and "first_delta_state < 100" in text
    assert 'pd.to_numeric, errors="raise"' in text
    assert 'raise RuntimeError(f"Non-numeric {source_stage} trace: {output}")' in text


def test_closeout_cannot_mutate_or_open_test():
    text = SCRIPT.read_text()
    assert '"scientific_authority": False' in text
    assert "provisional_selection_quarantined_pending_surface_wide_repair" in text
    assert "audit_and_refit_all_280_legacy_r76_atoms_before_selection_or_test" in text
    assert '"test_opened": False' in text
    assert '"registry_mutated": False' in text
    assert '"article_mutated": False' in text
    assert "X_test.csv" in text and "y_test.csv" in text
    assert "launch" not in SCRIPT.name


def test_r83_output_requires_hashed_structured_initialization_provenance(tmp_path):
    module = load_script()
    contract = module.RUNTIME_CONTRACTS["R83"]
    files = {
        "predictions_scaled.csv": "method_id,split,origin_id,horizon,tau,pred_scaled\nfoo,val,0,1,0.25,0\n",
        "method_summary.csv": "package_version,repair\n1.1.1.9004,placeholder\n",
        "parameter_summary.csv": "beta_l2,sigma,gamma\n1,1,0\n",
        "vb_trace.csv": "sigma,gamma,delta_state,delta_sigma,delta_gamma,delta_s\n1,0,0,0,0,0\n",
        "warm_start_manifest.json": "{}\n",
        "structured_initialization.json": json.dumps({
            "mode": "plugin_at_warm_start_before_structured_update",
            "package_version": contract["version"],
            "package_repair": contract["repair"],
            "test_loaded": False,
        }) + "\n",
    }
    hashes = {}
    for name, payload in files.items():
        path = tmp_path / name
        path.write_text(payload)
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    terminal = {
        "status": "completed",
        "task_id": "r83-task",
        "test_loaded": False,
        "artifact_sha256": hashes,
        "package": contract,
    }
    (tmp_path / "terminal.json").write_text(json.dumps(terminal) + "\n")
    module.validate_output(tmp_path, "r83-task", "R83")

    initialization = json.loads((tmp_path / "structured_initialization.json").read_text())
    initialization["mode"] = "laplace_delta"
    (tmp_path / "structured_initialization.json").write_text(json.dumps(initialization) + "\n")
    terminal["artifact_sha256"]["structured_initialization.json"] = hashlib.sha256(
        (tmp_path / "structured_initialization.json").read_bytes()
    ).hexdigest()
    (tmp_path / "terminal.json").write_text(json.dumps(terminal) + "\n")
    with pytest.raises(RuntimeError, match="initialization provenance"):
        module.validate_output(tmp_path, "r83-task", "R83")


def test_numeric_trace_coercion_handles_strict_string_dtype(tmp_path):
    module = load_script()
    columns = ["sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s"]
    trace = pd.DataFrame({name: pd.Series(["0", "1e-8"], dtype="string") for name in columns})
    numeric = module.numeric_trace_frame(trace, columns, "R76", tmp_path)
    assert numeric.dtypes.eq(float).all()
    assert numeric.loc[1, "delta_sigma"] == pytest.approx(1e-8)

    trace.loc[1, "delta_sigma"] = "not-a-number"
    with pytest.raises(RuntimeError, match="Non-numeric R76 trace"):
        module.numeric_trace_frame(trace, columns, "R76", tmp_path)
