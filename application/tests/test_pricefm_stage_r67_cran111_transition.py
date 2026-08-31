import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tarfile
from types import SimpleNamespace

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def load(name, filename):
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_source_tarball(path, version="1.1.1"):
    description = (
        "Package: exdqlm\n"
        f"Version: {version}\n"
        "Repository: CRAN\n"
        "Packaged: 2026-08-28 18:00:00 UTC; maintainer\n"
        "Date/Publication: 2026-08-28 18:30:00 UTC\n"
    ).encode()
    path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(path, "w:gz") as archive:
        member = tarfile.TarInfo("exdqlm/DESCRIPTION")
        member.size = len(description)
        archive.addfile(member, io.BytesIO(description))
    return path


def test_materializer_pins_tarball_identity_and_rejects_fork_api(tmp_path, monkeypatch):
    module = load("r67_materializer", "materialize_pricefm_stage_r67_cran111_package.py")
    tarball = write_source_tarball(tmp_path / "exdqlm_1.1.1.tar.gz")
    digest = hashlib.sha256(tarball.read_bytes()).hexdigest()
    monkeypatch.setattr(module, "CRAN_SHA256", digest)
    observed = module.verify_tarball(tarball)
    assert observed["sha256"] == digest
    assert observed["version"] == "1.1.1"
    assert observed["repository"] == "CRAN"

    library = tmp_path / "library"
    library.mkdir()
    payload = {
        "version": "1.1.1",
        "repository": "CRAN",
        "exports": list(module.REQUIRED_EXPORTS) + ["exal_ldvb_fit"],
    }
    monkeypatch.setattr(
        module.subprocess,
        "check_output",
        lambda *args, **kwargs: json.dumps(payload),
    )
    with pytest.raises(RuntimeError, match="fork_only"):
        module.package_probe(library)


def source_contract_fixture():
    comparisons = {
        "cran_110_vs_111_static_beta_prior_identical": True,
        "cran_110_vs_111_public_al_prefix_identical": True,
        "cran_110_vs_111_static_al_solver_identical": True,
        "cran_110_vs_111_structured_sigmagam_identical": False,
        "cran_111_vs_r65_static_beta_prior_identical": True,
        "cran_111_vs_r65_public_al_prefix_identical": True,
        "cran_111_vs_r65_static_al_solver_identical": True,
        "cran_111_vs_r65_structured_sigmagam_identical": True,
        "cran_111_vs_r66_static_beta_prior_identical": True,
        "cran_111_vs_r66_public_al_prefix_identical": True,
        "cran_111_vs_r66_static_al_solver_identical": True,
        "cran_111_vs_r66_structured_sigmagam_identical": False,
        "r65_vs_r66_structured_sigmagam_identical": False,
        "r65_custom_engine_absent_from_cran": True,
        "r65_exact_chunking_absent_from_cran": True,
        "r66_custom_engine_absent_from_cran": True,
        "r66_exact_chunking_absent_from_cran": True,
    }
    return {
        "status": "source_contract_complete",
        "comparisons": comparisons,
        "version_only_al_rhs_reuse_supported": True,
        "old_custom_fits_may_be_relabelled_as_cran": False,
    }


def test_r67_audit_freezes_authority_without_launch_or_relabelling(tmp_path, monkeypatch):
    module = load("r67_audit", "234_audit_pricefm_stage_r67_cran111_rhs_reuse.py")
    r62 = tmp_path / "r62.csv"
    pd.DataFrame([{
        "case_id": "pricefm_joint_aa_f1",
        "selected_seven_quantile_family": "al",
        "selection_split": "val",
        "test_opened": False,
    }]).to_csv(r62, index=False)
    r62_summary = tmp_path / "r62_summary.json"
    r62_summary.write_text(json.dumps({"matched_cells": 1, "test_opened": False}))
    r65_summary = tmp_path / "r65_summary.json"
    r65_summary.write_text(json.dumps({
        "status": "scientifically_stopped_mechanism_failure",
        "valid_al_fit_checkpoints": 1,
        "valid_exal_fit_checkpoints": 0,
        "completed_case_structured_winners": 0,
    }))
    r65_reuse = tmp_path / "r65_reuse.csv"
    pd.DataFrame([{"reuse_al_fit_authorized": True}]).to_csv(r65_reuse, index=False)
    launch_status = tmp_path / "launch_status.csv"
    pd.DataFrame([{"case_id": "pricefm_joint_aa_f1", "status": "failed"}]).to_csv(
        launch_status, index=False
    )
    r66_runs = tmp_path / "r66_runs"
    r66_runs.mkdir()
    source_tarball = write_source_tarball(tmp_path / "source.tar.gz")
    output = tmp_path / "output"

    monkeypatch.setattr(module, "ensure_tarball", lambda *args, **kwargs: source_tarball)
    monkeypatch.setattr(module, "active_r66_processes", lambda: [])

    def fake_run_json(command, output_path):
        payload = source_contract_fixture()
        output_path.write_text(json.dumps(payload))
        return payload

    monkeypatch.setattr(module, "run_json", fake_run_json)
    args = module.parser().parse_args([
        "--r62-authority", str(r62),
        "--r62-summary", str(r62_summary),
        "--r65-summary", str(r65_summary),
        "--r65-reuse-manifest", str(r65_reuse),
        "--r66-launch-status", str(launch_status),
        "--r66-run-dir", str(r66_runs),
        "--output-dir", str(output),
        "--run-numerical-probes", "false",
        "--expected-r62-cases", "1",
        "--expected-r65-valid-al", "1",
        "--expected-r65-valid-exal", "0",
        "--expected-r66-launch-rows", "1",
    ])
    summary = module.run(args)
    decisions = pd.read_csv(output / "pricefm_stage_r67_artifact_reuse_decisions.csv")
    gates = pd.read_csv(output / "pricefm_stage_r67_decision_gates.csv")

    assert summary["status"] == "completed_cran111_authority_transition_no_broad_refit"
    assert summary["existing_authority_refit_required"] is False
    assert summary["historical_custom_engine_may_be_relabelled_as_cran111"] is False
    assert summary["launch_authorized"] is False
    assert gates.loc[gates.required, "passed"].all()
    assert not decisions.refit_required_now.any()
    assert not decisions.loc[
        decisions.artifact_class.ne("future_new_PriceFM_fits"), "may_relabel_as_cran111"
    ].any()
    assert not list(output.rglob("*.yaml"))
    assert not list(output.rglob("*.yml"))


def test_process_probe_ignores_its_own_pgrep_command(monkeypatch):
    module = load("r67_process_probe", "234_audit_pricefm_stage_r67_cran111_rhs_reuse.py")
    output = (
        "123 pgrep -af pricefm_stage_r66|230_run_pricefm_stage_r66\n"
        "456 Rscript 230_run_pricefm_stage_r66_corrected_structured_exal_vb_case.R\n"
    )
    monkeypatch.setattr(
        module.subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(stdout=output),
    )
    assert module.active_r66_processes() == [
        "456 Rscript 230_run_pricefm_stage_r66_corrected_structured_exal_vb_case.R"
    ]
