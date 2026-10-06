import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
from types import SimpleNamespace

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application/scripts/pricefm"))
loader = importlib.util.spec_from_file_location("r123_successor_tests",
    ROOT / "application/scripts/pricefm/441_run_pricefm_stage_r123_certified_successor.py")
M = importlib.util.module_from_spec(loader); loader.loader.exec_module(M)
PROTOCOL = ROOT / "application/config/pricefm_stage_r123_certified_successor_protocol_20261005.json"


def packet(tmp_path, certified=True):
    output = tmp_path / "fit"; output.mkdir()
    contract = tmp_path / "contract.json"
    M.REC.write(contract, dict(tag=M.TAG, output_dir=str(output), convergence_mode="full_variational",
        posterior_target_sha256="fixed_target", candidate_id="candidate", split=1, tau0=.001))
    (output / "fit.rds").write_bytes(b"saved_state")
    terminal = dict(tag=M.TAG, contract_path=str(contract), contract_sha256=M.REC.digest(contract),
        posterior_target_sha256="fixed_target", test_opened=False, official_validation_opened=False,
        status="completed_recursive_normal_fit" if certified else "R123_SUCCESSOR_UNCERTIFIED",
        converged=certified, full_variational_certified=certified, precision_accuracy=dict(accepted=certified),
        artifacts=[dict(path="fit.rds", sha256=M.REC.digest(output / "fit.rds"))])
    M.REC.write(output / "terminal.json", terminal)
    return output, contract, terminal


def test_scope_and_nonredundant_budgets():
    p = M.REC.read(PROTOCOL); M.protocol_valid(p)
    assert p["center_checks"] == 21 * 3
    assert p["tau_top_k"] * len(p["tau_multipliers"]) * 3 == 60
    assert p["al_top_k"] * 3 * len(p["quantiles"]) == 63
    assert p["maximum_workers"] == 15 and p["normal_max_iter"] == 2000
    assert p["screening_refits_authorized"] is False
    for name in ("official_test_authorized", "exal_authorized", "joint_authorized", "mcmc_authorized"):
        bad = dict(p); bad[name] = True
        with pytest.raises(ValueError): M.protocol_valid(bad)


def test_only_complete_saved_groups_are_continued(tmp_path):
    rows = []
    for identifier, splits in [("complete", (1, 2, 3)), ("incomplete", (1, 2)), ("failed", ())]:
        for split in (1, 2, 3):
            output = tmp_path / identifier / str(split)
            if split in splits:
                output.mkdir(parents=True); (output / "terminal.json").write_text("{}")
            rows.append(dict(candidate_id=identifier, split=str(split), output_dir=str(output)))
    assert [r["candidate_id"] for r in M.choose_complete(rows)] == ["complete"] * 3


@pytest.mark.parametrize("change", ["target", "artifact", "tag", "cap", "precision", "contract"])
def test_saved_state_is_never_implicitly_certified(tmp_path, change):
    output, contract, terminal = packet(tmp_path)
    if change == "target": terminal["posterior_target_sha256"] = "changed"
    elif change == "artifact": (output / "fit.rds").write_bytes(b"changed")
    elif change == "tag": terminal["tag"] = "old_campaign"
    elif change == "cap": terminal["status"] = "R123_SUCCESSOR_UNCERTIFIED"
    elif change == "precision": terminal["precision_accuracy"]["accepted"] = False
    else: M.REC.write(contract, {})
    M.REC.write(output / "terminal.json", terminal)
    with pytest.raises((RuntimeError, KeyError)): M.normal_valid(output)


def test_explicit_cap_not_selected_and_partial_not_overwritten(tmp_path):
    output, _, _ = packet(tmp_path, certified=False)
    assert M.normal_outcome(output)["status"] == "R123_SUCCESSOR_UNCERTIFIED"
    assert not M.normal_valid(output) and M.normal_outcome(tmp_path / "missing") is None
    partial = tmp_path / "partial"; partial.mkdir()
    with pytest.raises(FileNotFoundError): M.normal_valid(partial)
    assert partial.exists()


def test_continuation_and_tau_probe_separate_state_from_target(tmp_path):
    runtime = tmp_path / "runtime/R"; runtime.mkdir(parents=True)
    for name in ("priors_beta.R", "qdesn_rhs_ns_prior.R"): (runtime / name).write_text("frozen")
    stats = tmp_path / "stats"; stats.mkdir(); (stats / "terminal.json").write_text("{}")
    parent = tmp_path / "parent.json"
    M.REC.write(parent, dict(tau0=.001, stats_dir=str(stats), prior_type="rhs_ns"))
    saved = tmp_path / "fit.rds"; saved.write_bytes(b"old_target")
    row = dict(contract_path=str(parent), candidate_id="a", split=1)
    args = SimpleNamespace(campaign_root=tmp_path / "new")
    ctl = dict(normal_runtime=str(runtime.parent)); p = M.REC.read(PROTOCOL)
    resume = M.normal_contract(row, args, ctl, p, saved, 151)
    fresh = M.normal_contract(row, args, ctl, p, tau0=.003, label="pilot")
    assert resume["min_iter"] == 161 and resume["max_iter"] == 2000
    assert resume["initial_fit_sha256"] == M.REC.digest(saved)
    assert fresh["initial_fit_path"] is None and fresh["tau0"] == .003
    assert resume["posterior_target_sha256"] != fresh["posterior_target_sha256"]
    assert saved.read_bytes() == b"old_target"


def test_supported_atom_stage_and_distinct_campaign(monkeypatch):
    monkeypatch.setattr(M, "ORIGINAL_QUANTILE_CONTRACT", lambda: dict(stage="R122_internal_selection", atom_id="r122_id"))
    c = M.quantile_contract()
    assert c == dict(stage="R122_internal_selection", atom_id="r123s_id", tag=M.TAG,
                     scientific_stage="R123_certified_successor")


def test_design_resume_checks_bytes_metadata_and_partial_state(tmp_path):
    X = np.column_stack([np.ones(4), np.arange(4.)]); y = np.arange(4.)
    path = tmp_path / "design"; meta = dict(feature_names=["intercept", "layer1::0"], depth=1)
    M.guarded_design(path, X, y, meta); old = M.REC.digest(path / "X.bin")
    M.guarded_design(path, X, y, meta)
    with pytest.raises(RuntimeError): M.guarded_design(path, X + 1, y, meta)
    with pytest.raises(RuntimeError): M.guarded_design(path, X, y, dict(meta, depth=2))
    assert M.REC.digest(path / "X.bin") == old
    partial = tmp_path / "partial"; partial.mkdir()
    with pytest.raises(RuntimeError, match="partial design"): M.guarded_design(partial, X, y, meta)


def test_completed_ladder_resume_is_hash_verified(tmp_path, monkeypatch):
    result = dict(candidate_id="a", split=1, tau0=.001, eligible=True, test_opened=False)
    root = tmp_path / "al_internal/a/split=1"
    def run(*args): M.REC.write(root / "metrics.json", result); return result
    monkeypatch.setattr(M, "ORIGINAL_LADDER", run)
    args = (tmp_path, tmp_path, tmp_path, {}, "a", .001, 1, 0)
    assert M.guarded_ladder(*args) == result
    monkeypatch.setattr(M, "ORIGINAL_LADDER", lambda *args: pytest.fail("completed ladder refitted"))
    assert M.guarded_ladder(*args) == result
    M.REC.write(root / "metrics.json", dict(result, eligible=False))
    with pytest.raises(RuntimeError, match="evidence changed"): M.guarded_ladder(*args)


@pytest.mark.parametrize("change", ["none", "target", "scope", "metric", "parent", "contract"])
def test_score_resume_is_target_and_scope_checked(tmp_path, change):
    output, contract, _ = packet(tmp_path)
    score = dict(candidate_id="candidate", split=1, tau0=.001, full_variational_certified=True,
        test_opened=False, official_validation_opened=False,
        fit_terminal_sha256=M.REC.digest(output / "terminal.json"), contract_sha256=M.REC.digest(contract),
        score_scope="fold1_training_internal_validation_only", forecast_operator="recursive_normal_conditional_mean",
        AQL=.1, late_AQL=.2, median_MAE=.3, interval_80_width=.4)
    if change == "target": score["tau0"] = .003
    elif change == "scope": score["official_validation_opened"] = True
    elif change == "metric": score["AQL"] = -1
    elif change == "parent": score["fit_terminal_sha256"] = "old"
    elif change == "contract": score["contract_sha256"] = "old"
    path = output / "validation_score.json"; M.REC.write(path, score)
    if change == "none": assert M.verified_score(path, contract) == score
    else:
        with pytest.raises(RuntimeError): M.verified_score(path, contract)


def test_physical_resource_gate_excludes_busy_siblings(tmp_path, monkeypatch):
    args = SimpleNamespace(workers=2, campaign_root=tmp_path / "campaign")
    monkeypatch.setattr(M.B, "_cpu_snapshot", lambda seconds: {0: 0, 1: 0, 2: 0, 3: 90, 4: 0, 5: 0})
    monkeypatch.setattr(M.B, "_physical", lambda cpu: cpu // 2)
    monkeypatch.setattr(M.os, "sched_getaffinity", lambda pid: set(range(6)))
    p = dict(M.REC.read(PROTOCOL), minimum_memory_gib=0, minimum_free_gib=0, resource_attempts=1)
    assert M.preflight(args, p) == [0, 4]
    args.workers = 3
    with pytest.raises(RuntimeError, match="idle physical cores"): M.preflight(args, p)


@pytest.mark.parametrize("enough", [True, False])
def test_controller_automatic_sequence_is_gated(tmp_path, monkeypatch, enough):
    args = SimpleNamespace(prep_dir=tmp_path / "prep", campaign_root=tmp_path / "campaign",
        parent_campaign=tmp_path / "parent", frozen_code_root=tmp_path, workers=15)
    args.parent_campaign.mkdir()
    for name in ("controller.lock", "recovery_controller.lock"): (args.parent_campaign / name).touch()
    M.REC.write(args.prep_dir / "protocol.json", M.REC.read(PROTOCOL))
    M.REC.write(args.prep_dir / "protected_parent.json", dict(evidence_sha256={}))
    jobs = [dict(candidate_id=cid, split=split, tau0=.001, fit_id=f"{cid}{split}",
        contract_path="mock", output_dir="mock") for cid in ("a", "b", "c") for split in (1, 2, 3)]
    M.REC.write(args.prep_dir / "center_jobs.json", jobs)
    events = []
    monkeypatch.setattr(M, "verify", lambda args: dict(workers=15, code_head="committed"))
    monkeypatch.setattr(M, "preflight", lambda *args: list(range(15)))
    def normal_phase(args, jobs, label, cpus):
        events.append(label)
        cells = [dict(candidate_id=c["candidate_id"], split=c["split"], tau0=c["tau0"],
            full_variational_certified=enough or c["candidate_id"] != "c", test_opened=False,
            AQL=.1, late_AQL=.2) for c in jobs]
        return jobs, cells
    monkeypatch.setattr(M, "run_normal_phase", normal_phase)
    monkeypatch.setattr(M, "normal_contract", lambda row, args, control, p, tau0, label:
        dict(row, tau0=tau0, fit_id=f"{row['candidate_id']}{row['split']}_{tau0}"))
    def al(*args): events.append("al"); return pd.DataFrame([dict(candidate_id=x) for x in ("a", "b", "c")])
    monkeypatch.setattr(M.B, "_run_al", al)
    if enough:
        result = M.controller(args)
        assert events == ["center", "pilot", "al"]
        assert result["tau_attempts"] == 18 and result["test_opened"] is False
        assert M.controller(args) == result and events == ["center", "pilot", "al"]
    else:
        with pytest.raises(RuntimeError, match="fewer than three"): M.controller(args)
        assert events == ["center"] and not (args.campaign_root / "al_launch_authorization.json").exists()


@pytest.mark.parametrize("reject_precision", [False, True])
def test_real_normal_certification_and_cran_al_interface(tmp_path, reject_precision):
    runtime = M.DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"
    rscript = "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
    if not Path(rscript).exists() or not runtime.exists(): pytest.skip("pinned R/Normal runtime unavailable")
    rng = np.random.default_rng(76); X = np.column_stack([np.ones(80), rng.normal(size=(80, 4))])
    y = X @ np.array([1, .5, 0, 0, -.2]) + rng.normal(size=80) * .4
    stats = tmp_path / "stats"; stats.mkdir()
    np.asarray(X.T @ X, dtype="<f8").tofile(stats / "XtX.bin")
    np.asarray(X.T @ y, dtype="<f8").tofile(stats / "Xty.bin")
    M.REC.write(stats / "statistics.json", dict(n=80, p=5, yty=float(y @ y), test_opened=False))
    M.REC.write(stats / "terminal.json", dict(status="completed_causal_sufficient_statistics", test_opened=False,
        files={p.name: dict(sha256=M.REC.digest(p)) for p in stats.iterdir()}))
    parent = tmp_path / "original.json"
    M.REC.write(parent, dict(stats_dir=str(stats), tau0=.05, package_path=str(runtime),
        selection_split="train_validation_only", test_access_authorized=False, prior_type="rhs_ns",
        tol=1e-5, predictive_tol=1e-7, relative_beta_tol=1e-6, sigma_relative_tol=1e-8,
        prior_rms_log_precision_tol=1e-6))
    p = M.REC.read(PROTOCOL)
    if reject_precision: p["precision_accuracy_tol"] = 1e-30
    c = M.normal_contract(dict(contract_path=str(parent), candidate_id="tiny", split=1),
        SimpleNamespace(campaign_root=tmp_path / "campaign"), dict(normal_runtime=str(runtime)), p)
    path = tmp_path / "contract.json"; M.REC.write(path, c)
    cmd = [rscript, str(ROOT / "application/scripts/pricefm/442_fit_pricefm_stage_r123_certified_normal.R"), "--contract", str(path)]
    run = subprocess.run(cmd, capture_output=True, text=True); assert run.returncode == 0, run.stderr
    terminal = M.normal_outcome(c["output_dir"])
    assert terminal["full_variational_certified"] is not reject_precision
    assert terminal["resumed_from_iteration"] == 0 and terminal["iterations"] >= 100
    assert subprocess.run(cmd, capture_output=True).returncode != 0
    if reject_precision: return
    design = tmp_path / "design"
    M.guarded_design(design, X, y, dict(depth=2,
        feature_names=["intercept", "layer1::0", "layer1::1", "layer2::0", "layer2::1"]))
    prep = tmp_path / "prep"
    adapter = ROOT / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R"
    M.B._write_immutable_csv(pd.DataFrame([dict(path=str(adapter))]), prep / "source_manifest.csv")
    library = M.DATA / "runtime_libraries/exdqlm_cran_1p1p1"
    ctl = dict(cran_manifest=str(library / "pricefm_r67_cran111_install_manifest.json"), cran_library=str(library))
    qc = M.quantile_contract(prep, ctl, "tiny", 1, .5, .05, design,
        Path(c["output_dir"]), "normal_rhs", tmp_path / "al", 40)
    config = tmp_path / "al_contract.json"; M.REC.write(config, qc)
    M.guarded_command([rscript, str(ROOT / "application/scripts/pricefm/420_fit_pricefm_stage_r121_quantile_atom.R"),
                       "--config", str(config)], ROOT, tmp_path / "al.log")
    assert M.quantile_valid(tmp_path / "al", qc["posterior_target_sha256"])
    qt = M.REC.read(tmp_path / "al/terminal.json")
    assert qt["finite_core"] and qt["initializer_changes_prior"] is False
    assert qt["package"]["version"] == "1.1.1" and qt["package"]["repository"] == "CRAN"
    (tmp_path / "al/beta_mean.bin").write_bytes(b"changed")
    with pytest.raises(RuntimeError, match="output changed"): M.quantile_valid(tmp_path / "al", qc["posterior_target_sha256"])
