from __future__ import annotations

import importlib.util
from pathlib import Path
from types import SimpleNamespace
import sys

import pytest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts/pricefm"
sys.path.insert(0, str(SCRIPTS))
loader = importlib.util.spec_from_file_location("r123_centre_test", SCRIPTS / "435_audit_pricefm_stage_r123_rhs_centres.py")
RUN = importlib.util.module_from_spec(loader); loader.loader.exec_module(RUN)


@pytest.fixture
def item(tmp_path):
    contract = tmp_path / "contract.json"; contract.write_text('{"max_iter":2000}\n')
    output = tmp_path / "output"; log = tmp_path / "fit.log"
    command = ["Rscript", "frozen.R", "--contract", str(contract)]
    return {"contract": contract, "output": output, "log": log, "command": command}


def cap_log(item):
    item["log"].write_text("$ taskset -c 3 " + " ".join(item["command"]) + "\n" + RUN.CAP_ERROR + "\nExecution halted\n")


def evidence(item):
    return RUN.cap_evidence(item["command"], item["log"], item["contract"], item["output"])


def admission(tmp_path, item, rejected=None, command=None):
    calls = []
    def queue(tasks, cpus, code, progress, expected, **kwargs):
        calls.extend(tasks)
        return {"complete_this_resume": len(tasks), "failed_this_resume": 0}
    backend = SimpleNamespace(_command=command or (lambda *args: None), _run_queue=queue)
    frozen = SimpleNamespace(BACKEND=backend, guarded_normal_valid=lambda output: output.is_dir())
    return RUN.CentreAdmission(frozen, tmp_path / "attempt", {"fit": item}, rejected or {}), calls


def test_exact_frozen_convergence_failure_is_not_an_accepted_fit(item):
    cap_log(item); result = evidence(item)
    assert result["iteration_cap"] == 2000 and result["accepted_as_fit"] is False
    assert not item["output"].exists()


@pytest.mark.parametrize("bad", ["numerical", "warning", "partial", "wrong_command", "twice"])
def test_other_errors_or_partial_outputs_are_not_disguised_as_convergence(item, bad):
    cap_log(item)
    if bad == "numerical": item["log"].write_text(item["log"].read_text().replace(RUN.CAP_ERROR, "Error: non-finite precision"))
    if bad == "warning": item["log"].write_text(item["log"].read_text() + "Warning: changed target\n")
    if bad == "partial": item["output"].mkdir()
    if bad == "wrong_command": item["log"].write_text(item["log"].read_text().replace("frozen.R", "other.R"))
    if bad == "twice": item["log"].write_text(item["log"].read_text() * 2)
    with pytest.raises(RuntimeError, match="unexpected failure"): evidence(item)


def test_prior_convergence_failures_are_not_retried_or_overwritten(tmp_path, item):
    cap_log(item); before = item["log"].read_bytes()
    gate, calls = admission(tmp_path, item, {"fit": evidence(item)})
    result = gate.run_queue([("fit", item["command"], item["log"])], [1], tmp_path,
                            tmp_path / "center/fit_progress.json", 90, fail_fast=True)
    assert calls == [] and item["log"].read_bytes() == before
    assert result["prior_rejections_not_retried"] == 1


def test_tampered_rejection_evidence_blocks_admission(tmp_path, item):
    cap_log(item); gate, calls = admission(tmp_path, item, {"fit": evidence(item)})
    item["contract"].write_text('{"max_iter":5000}\n')
    with pytest.raises(RuntimeError, match="evidence changed"):
        gate.run_queue([("fit", item["command"], item["log"])], [1], tmp_path,
                       tmp_path / "center/fit_progress.json", 90)
    assert not calls


def test_new_known_cap_is_recorded_but_not_saved_as_a_fit(tmp_path, item):
    def fail(*args):
        cap_log(item); raise RuntimeError("command failed (1): Rscript frozen.R")
    gate, calls = admission(tmp_path, item, command=fail)
    gate.run_command(item["command"], tmp_path, item["log"], 1)
    assert gate.rejected["fit"]["accepted_as_fit"] is False
    assert not item["output"].exists()


@pytest.mark.parametrize("message", ["command failed (2): bad", "source checksum changed", "precision repair changed target"])
def test_unexpected_command_errors_still_fail_closed(tmp_path, item, message):
    def fail(*args): raise RuntimeError(message)
    gate, calls = admission(tmp_path, item, command=fail)
    with pytest.raises(RuntimeError, match=message.replace("(", "\\(").replace(")", "\\)")):
        gate.run_command(item["command"], tmp_path, item["log"], 1)
    assert not gate.rejected


@pytest.mark.parametrize("queue", ["pilot/fit_progress.json", "al_internal/fit_progress.json", "broad/progress.json"])
def test_audit_cannot_launch_other_fit_or_screening_stages(tmp_path, item, queue):
    gate, calls = admission(tmp_path, item)
    with pytest.raises(RuntimeError, match="refuses any stage"):
        gate.run_queue([("fit", item["command"], item["log"])], [1], tmp_path, tmp_path / queue, 90)
    assert not calls


def test_completed_or_partial_fit_cannot_be_dispatched_again(tmp_path, item):
    item["output"].mkdir(); gate, calls = admission(tmp_path, item)
    with pytest.raises(RuntimeError, match="repeat an attempted"):
        gate.run_queue([("fit", item["command"], item["log"])], [1], tmp_path,
                       tmp_path / "center/fit_progress.json", 90)
    assert not calls


def test_successful_fit_is_dispatched_with_identical_contract(tmp_path, item):
    gate, calls = admission(tmp_path, item)
    task = ("fit", item["command"], item["log"])
    gate.run_queue([task], [1], tmp_path, tmp_path / "center/fit_progress.json", 90, fail_fast=True)
    assert calls == [task] and gate.wanted["fit"]["command"] == item["command"]


def test_only_converged_centres_can_be_scored(tmp_path, item):
    gate, calls = admission(tmp_path, item)
    task = ("fit", ["python", "frozen.py", "--mode", "rhs-score"], tmp_path / "score.log")
    with pytest.raises(RuntimeError, match="successful frozen"):
        gate.run_queue([task], [1], tmp_path, tmp_path / "center/score_progress.json", 90)
    assert not calls


def test_final_progress_does_not_count_a_handled_cap_as_converged(tmp_path, item):
    gate, calls = admission(tmp_path, item)
    def queue(tasks, *args, **kwargs):
        cap_log(item); gate.rejected["fit"] = evidence(item)
        return {"complete_this_resume": 1, "failed_this_resume": 0}
    gate.queue = queue
    result = gate.run_queue([("fit", item["command"], item["log"])], [1], tmp_path,
                            tmp_path / "center/fit_progress.json", 90)
    assert result["complete_this_resume"] == 0 and result["failed_this_resume"] == 1
    assert result["handled_this_resume"] == 1 and result["convergence_rejected_task_ids"] == ["fit"]


@pytest.fixture
def inventory(tmp_path):
    source = RUN.DRIVER.load_frozen(SCRIPTS.parents[2])
    prep, campaign = tmp_path / "prep", tmp_path / "campaign"
    control = {"normal_runtime": "/frozen/runtime", "rhs_max_iter": 2000, "rscript": "Rscript"}
    RUN.REC.write(prep / "launch_control.json", control)
    candidates = source.pd.DataFrame([{"candidate_id": f"candidate{i}", "readout_dimension": 9} for i in range(30)])
    (campaign / "seed3").mkdir(parents=True); candidates.to_csv(campaign / "seed3/ranking.csv", index=False)
    stats = {"n": 100, "p": 9, "yty": 100., "XtX": source.np.eye(9), "Xty": source.np.ones(9)}
    backend = SimpleNamespace(_ordered_candidates=lambda *args: candidates,
        _tau_center=source.BACKEND._tau_center, _normal_contract=source.BACKEND._normal_contract,
        _canonical_fit=lambda *args: "unused", _stats_from_ridge=lambda *args: stats)
    frozen = SimpleNamespace(BACKEND=backend, pd=source.pd, np=source.np,
                             guarded_normal_valid=lambda path: (path / "terminal.json").is_file())
    args = SimpleNamespace(campaign_root=campaign, prep_dir=prep, frozen_code_root=tmp_path / "frozen")
    records = []
    for row in candidates.itertuples(index=False):
        tau0 = backend._tau_center(9, 766 * 96)
        for split in (1, 2, 3):
            identifier = f"r122rhs_{row.candidate_id}_s{split}_t{tau0:.8e}"
            packet = campaign / f"rhs/stats/{row.candidate_id}/split={split}"
            source.RT.write_stats_packet(packet, stats, {"candidate_id": row.candidate_id, "split": split})
            output = campaign / f"rhs/center/fits/{identifier}"
            contract = campaign / f"rhs/center/contracts/{identifier}.json"
            RUN.REC.write(contract, backend._normal_contract(identifier, packet, output, tau0, control, args.frozen_code_root))
            records.append({"candidate_id": row.candidate_id, "split": split, "tau0": tau0,
                "fit_id": identifier, "contract_path": str(contract), "output_dir": str(output), "stage_label": "center"})
    source.pd.DataFrame(records).to_csv(campaign / "rhs/center/manifest.csv", index=False)
    return frozen, args, records


def test_inventory_recovers_exact_frozen_contracts_and_protects_statistics(inventory):
    frozen, args, records = inventory
    candidates, wanted, protected, rejected, completed = RUN.centre_inventory(frozen, args)
    assert len(candidates) == 30 and len(wanted) == 90 and len(protected) == 450
    assert rejected == {} and completed == []
    assert all(RUN.REC.read(item["contract"])["max_iter"] == 2000 for item in wanted.values())


@pytest.mark.parametrize("problem", ["budget", "duplicate", "path", "binary", "metadata", "test_access", "missing_artifact"])
def test_inventory_corruption_is_rejected_without_recreating_evidence(inventory, problem):
    frozen, args, records = inventory
    row = records[0]; contract = Path(row["contract_path"])
    packet = args.campaign_root / "rhs/stats/candidate0/split=1"
    if problem == "budget":
        value = RUN.REC.read(contract); value["max_iter"] = 5000; RUN.REC.write(contract, value)
    if problem == "duplicate":
        frame = frozen.pd.read_csv(args.campaign_root / "rhs/center/manifest.csv")
        frame.loc[1, "fit_id"] = frame.loc[0, "fit_id"]; frame.to_csv(args.campaign_root / "rhs/center/manifest.csv", index=False)
    if problem == "path":
        frame = frozen.pd.read_csv(args.campaign_root / "rhs/center/manifest.csv")
        frame.loc[0, "output_dir"] = "/other/lane"; frame.to_csv(args.campaign_root / "rhs/center/manifest.csv", index=False)
    if problem == "binary": (packet / "XtX.bin").write_bytes(b"different data")
    if problem == "metadata":
        value = RUN.REC.read(packet / "statistics.json"); value["n"] = 101; RUN.REC.write(packet / "statistics.json", value)
    if problem == "test_access":
        value = RUN.REC.read(packet / "terminal.json"); value["test_opened"] = True; RUN.REC.write(packet / "terminal.json", value)
    if problem == "missing_artifact": (packet / "Xty.bin").unlink()
    before = sorted(str(path) for path in args.campaign_root.rglob("*") if path.is_file())
    with pytest.raises((RuntimeError, FileNotFoundError)): RUN.centre_inventory(frozen, args)
    assert before == sorted(str(path) for path in args.campaign_root.rglob("*") if path.is_file())
