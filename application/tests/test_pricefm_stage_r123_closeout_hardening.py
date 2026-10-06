from pathlib import Path
import importlib.util
import sys
from types import SimpleNamespace

import pytest
from pricefm_r123_closeout_evidence import active_fit_processes, authorized_ladders, verified_atom, audit_ladder

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application/scripts/pricefm"))


def observer():
    spec = importlib.util.spec_from_file_location("r123_hardened_observer",
        ROOT / "application/scripts/pricefm/443_audit_pricefm_stage_r123_cadence_closeout.py")
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def partial_freeze(tmp_path, monkeypatch):
    m = observer()
    args = SimpleNamespace(output=tmp_path / m.TAG, parent_campaign=tmp_path / m.PARENT)
    parent = args.parent_campaign / "evidence.json"
    m.REC.write(parent, {"preserved": True})
    for name in ("source_identity.json", "cadence_audit.json"):
        m.REC.write(args.output / name, {"evidence_sha256": {}})
    m.REC.write(args.output / "parent_evidence.json",
        {"evidence_sha256": {str(parent): m.REC.digest(parent)}})
    m.REC.write(args.output / "terminal.json", {"status": "frozen", "test_opened": False})
    monkeypatch.setattr(m, "own_identity", lambda args: "frozen")
    return m, args, parent


def test_resume_after_terminal_before_final_ledger_never_refits(tmp_path, monkeypatch):
    m, args, parent = partial_freeze(tmp_path, monkeypatch)
    before = m.REC.digest(parent)
    assert m.run(args)["status"] == "frozen"
    assert m.REC.digest(parent) == before
    m.REC.verify_evidence(m.REC.read(args.output / "completed_evidence.json"))
    assert m.run(args)["status"] == "frozen"


def test_interrupted_freeze_rejects_changed_parent_instead_of_rehashing(tmp_path, monkeypatch):
    m, args, parent = partial_freeze(tmp_path, monkeypatch)
    m.REC.write(parent, {"changed": True})
    with pytest.raises(RuntimeError, match="evidence changed"):
        m.run(args)
    assert not (args.output / "completed_evidence.json").exists()


@pytest.mark.parametrize("missing", ["source_identity.json", "cadence_audit.json", "parent_evidence.json"])
def test_partial_closeout_requires_all_preserved_receipts(tmp_path, monkeypatch, missing):
    m, args, _ = partial_freeze(tmp_path, monkeypatch)
    (args.output / missing).unlink()
    with pytest.raises((OSError, RuntimeError)):
        m.run(args)


def test_mutable_live_receipts_do_not_invalidate_completed_freeze(tmp_path, monkeypatch):
    m, args, _ = partial_freeze(tmp_path, monkeypatch)
    m.run(args)
    m.REC.write(args.output / "live.json", {"updated": True})
    m.REC.write(args.output / "validation/new_receipt.json", {"passed": True})
    assert m.run(args)["status"] == "frozen"
    m.REC.write(args.output / "terminal.json", {"changed": True})
    with pytest.raises(RuntimeError, match="closure differs"):
        m.run(args)


@pytest.mark.parametrize("defect", ["duplicate", "test", "exal", "tau", "path"])
def test_authorization_is_exact_and_scoped(tmp_path, defect):
    m = observer()
    value = dict(independent_al_authorized=True, test_opened=False,
        exal_authorized=False, joint_authorized=False, mcmc_authorized=False,
        selected=[dict(candidate_id=f"c{i}", tau0=.001) for i in range(3)])
    m.REC.write(tmp_path / "al_launch_authorization.json", value)
    assert len(authorized_ladders(tmp_path)) == 9
    if defect == "duplicate": value["selected"][2] = value["selected"][1]
    elif defect == "test": value["test_opened"] = True
    elif defect == "exal": value["exal_authorized"] = True
    elif defect == "tau": value["selected"][0]["tau0"] = -1
    else: value["selected"][0]["candidate_id"] = "../other"
    m.REC.write(tmp_path / "al_launch_authorization.json", value)
    with pytest.raises(RuntimeError): authorized_ladders(tmp_path)


def atom_fixture(tmp_path):
    m = observer()
    root = tmp_path / "c0/split=1"
    atom = root / "quantiles/al/tau=0.50"
    expected = dict(atom_id="c0_s1_q0.50_i1000", tag=m.PARENT, stage="R122_internal_selection",
        readout="pure_all_layers", family="al", fold=1, split=1, tau=.5, tau0=.001,
        posterior_target_sha256="independent_expected_target", max_iter=1000)
    terminal = dict(expected, initialization_only=True, prior_center_from_initializer=False,
        initializer_changes_prior=False, test_opened=False, registry_mutated=False,
        article_mutated=False, joint_model_fitted=False, mcmc_fitted=False, exal_fitted=False,
        package_version="1.1.1", package_repository="CRAN")
    m.REC.write(root / "contracts/final/tau=0.50.json", expected)
    m.REC.write(atom / "terminal.json", terminal)
    m.REC.write(atom / "diagnostics.json", dict(external_gate_passed=True))
    owner = SimpleNamespace(B=SimpleNamespace(PARENT={.5: None}, QUANTILE_ORDER=[.5]),
        quantile_contract=lambda *args: expected,
        quantile_valid=lambda path, target: m.REC.read(path / "terminal.json")["posterior_target_sha256"] == target,
        normal_valid=lambda path: True)
    args = SimpleNamespace(parent_prep=tmp_path / "prep")
    control = dict(al_companion_max_iter=750, al_final_max_iter=1000)
    return m, root, atom, expected, terminal, owner, args, control


@pytest.mark.parametrize("defect", ["none", "contract_target", "terminal_target", "tau0", "split", "prior", "api", "test"])
def test_atom_identity_comes_from_authorization_not_its_own_terminal(tmp_path, defect):
    m, root, atom, expected, terminal, owner, args, control = atom_fixture(tmp_path)
    if defect == "contract_target":
        wrong = dict(expected, posterior_target_sha256="self_consistent_wrong_target")
        m.REC.write(root / "contracts/final/tau=0.50.json", wrong)
        terminal["posterior_target_sha256"] = wrong["posterior_target_sha256"]
    elif defect == "terminal_target": terminal["posterior_target_sha256"] = "wrong_target"
    elif defect == "tau0": terminal["tau0"] = .002
    elif defect == "split": terminal["split"] = 2
    elif defect == "prior": terminal["initializer_changes_prior"] = True
    elif defect == "api": terminal["package_version"] = "fork"
    elif defect == "test": terminal["test_opened"] = True
    m.REC.write(atom / "terminal.json", terminal)
    call = lambda: verified_atom(args, owner, control, root, "c0", 1, .001, .5, tmp_path / "normal")
    if defect == "none": assert call()["external_gate_passed"] is True
    else:
        with pytest.raises(RuntimeError): call()


@pytest.mark.parametrize("defect", ["none", "duplicate", "candidate", "split", "scale", "raw_gate", "method", "scope"])
def test_ladder_cannot_be_certified_by_counts_alone(tmp_path, defect):
    m, root, atom, _, _, owner, args, control = atom_fixture(tmp_path)
    owner.B.QUANTILE_ORDER = [.5, .45]
    owner.B.PARENT[.45] = .5
    accepted = [dict(tau=.5, accepted=True, raw_external_gate_passed=True, acceptance_method="raw_external_gate")]
    value = dict(candidate_id="c0", split=1, tau0=.001, test_opened=False,
        eligible=False, accepted_quantiles=accepted)
    if defect == "duplicate": value["accepted_quantiles"] *= 2
    elif defect == "candidate": value["candidate_id"] = "other"
    elif defect == "split": value["split"] = 2
    elif defect == "scale": value["tau0"] = .002
    elif defect == "raw_gate": accepted[0]["accepted"] = False
    elif defect == "method": accepted[0]["acceptance_method"] = "unrecognized"
    elif defect == "scope": value.update(eligible=True, score_scope="official_test")
    path = root / "metrics.json"
    m.REC.write(path, value)
    rows = [dict(candidate_id="c0", split=1, tau0=.001, output_dir=str(tmp_path / "normal"))]
    call = lambda: audit_ladder(args, owner, control, path, {("c0", 1): .001}, rows)
    if defect == "none": assert call() == value
    else:
        with pytest.raises(RuntimeError): call()


def test_live_counts_distinguish_finite_caps_and_malformed_receipts(tmp_path):
    m = observer()
    args = SimpleNamespace(parent_campaign=tmp_path)
    for q, value in [(.5, dict(external_gate_passed=True, formal_converged=True)),
                     (.45, dict(external_gate_passed=False, formal_converged=False)), (.55, {})]:
        m.REC.write(tmp_path / f"al_internal/c0/split=1/quantiles/al/tau={q:.2f}/terminal.json", value)
    value = m.snapshot(args)
    assert value["primary_al_atoms_complete"] == 3
    assert value["primary_al_atoms_raw_eligible"] == 1
    assert value["primary_al_atoms_not_formal_converged"] == 1
    assert value["primary_al_atoms_malformed"] == 1
    assert value["live_counts_contract_certified"] is False


def test_orphaned_parent_writer_is_detected_without_touching_other_lanes(tmp_path):
    proc = tmp_path / "proc"
    campaign, prep = tmp_path / "parent", tmp_path / "prep"
    cases = {
        1: ["/opt/R/bin/exec/R", "--file=/src/420_fit_pricefm_stage_r121_quantile_atom.R", "--config", str(campaign / "atom.json")],
        2: ["/opt/R/bin/exec/R", "--file=/src/442_fit_pricefm_stage_r123_certified_normal.R", "--contract", str(prep / "normal.json")],
        3: ["/opt/R/bin/exec/R", "--file=/src/420_fit_pricefm_stage_r121_quantile_atom.R", "--config", str(tmp_path / "another_lane/atom.json")],
        4: ["/bin/bash", "420_fit_pricefm_stage_r121_quantile_atom.R", str(campaign / "atom.json")],
    }
    for pid, argv in cases.items():
        folder = proc / str(pid); folder.mkdir(parents=True)
        (folder / "cmdline").write_bytes("\0".join(argv).encode())
    assert active_fit_processes(campaign, prep, proc) == [1, 2]


def test_orphaned_fit_blocks_receipt_freeze_after_controller_lock_release(tmp_path, monkeypatch):
    m = observer()
    parent = tmp_path / "parent"; parent.mkdir(); (parent / "controller.lock").touch()
    args = SimpleNamespace(parent_campaign=parent, parent_prep=tmp_path / "prep")
    monkeypatch.setattr(m, "active_fit_processes", lambda *args: [123])
    with pytest.raises(BlockingIOError, match="writers remain active"):
        m.freeze_parent(args, None, {})
