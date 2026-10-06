from pathlib import Path
import importlib.util
import sys
from types import SimpleNamespace

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application/scripts/pricefm"))
from pricefm_internal_target_embargo import guarded_splits, regular_axis


def splits():
    return [dict(split=i, train=np.arange(stop), validation=np.arange(stop, end))
        for i, (stop, end) in enumerate(((506, 631), (631, 766), (766, 940)), 1)]


@pytest.mark.parametrize("cadence,counts", [("1h", [122, 132, 171]), ("15min", [125, 135, 174])])
def test_daily_origins_are_classified_using_actual_target_cadence(cadence, counts):
    anchors = pd.date_range("2022-02-04", periods=940, freq="24h", tz="UTC")
    clean, evidence = guarded_splits(anchors, splits(), sample_step=cadence)
    assert [x["clean_validation_origins"] for x in evidence] == counts
    for before, after, receipt in zip(splits(), clean, evidence):
        assert np.array_equal(before["train"], after["train"])
        assert pd.Timestamp(receipt["first_scored_origin_utc"]) > pd.Timestamp(receipt["last_fitted_target_utc"])
        assert receipt["posterior_target_unchanged"] is True


def test_cadence_cannot_be_silently_assumed_to_be_hourly():
    with pytest.raises(TypeError): guarded_splits([], [])


@pytest.mark.parametrize("step,excluded", [("1h", 95), ("24h", 3), ("96h", 0), ("168h", 0)])
def test_hourly_embargo_is_derived_from_times_not_a_hardcoded_count(step, excluded):
    anchors = pd.date_range("2022-01-01", periods=300, freq=step, tz="UTC")
    _, evidence = guarded_splits(anchors, [dict(split=1, train=np.arange(30), validation=np.arange(30, 300))], sample_step="1h")
    assert len(evidence[0]["excluded_origin_indices"]) == excluded


@pytest.mark.parametrize("case", ["same_index", "duplicates", "out_of_range", "no_safe_origin", "bad_horizon", "bad_step"])
def test_invalid_boundary_contract_fails_closed(case):
    anchors = pd.date_range("2022-01-01", periods=10, freq="24h", tz="UTC")
    train, val, horizon, step = [0, 1, 2], [3, 4, 5, 6, 7], 96, "1h"
    if case == "same_index": val = [2, 3, 4]
    elif case == "duplicates": train = [0, 0, 1]
    elif case == "out_of_range": val = [15]
    elif case == "no_safe_origin": val = [3, 4]
    elif case == "bad_horizon": horizon = 48
    else: step = "0h"
    with pytest.raises(ValueError): guarded_splits(anchors, [dict(split=1, train=train, validation=val)],
        horizon=horizon, sample_step=step)


@pytest.mark.parametrize("freq,minutes", [("1h", 60), ("15min", 15)])
def test_axis_proves_cadence_and_supports_microsecond_storage(freq, minutes):
    values = pd.date_range("2022-01-01", periods=200, freq=freq, tz="UTC")
    assert regular_axis(values)["sample_step_minutes"] == minutes
    assert regular_axis(pd.Series(values.as_unit("us")))["sample_step_minutes"] == minutes
    with pytest.raises(ValueError): regular_axis(values.delete(5))


def followup():
    spec = importlib.util.spec_from_file_location("cadence_dispatch_test",
        ROOT / "application/scripts/pricefm/443_audit_pricefm_stage_r123_cadence_closeout.py")
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m


def synthetic():
    frame = pd.DataFrame({"BG-price": np.arange(941 * 96, dtype=np.float32)},
        index=pd.date_range("2022-02-04", periods=941 * 96, freq="15min", tz="UTC"))
    anchors = frame.index[np.arange(940) * 96]
    arrays = SimpleNamespace(anchors=anchors, response=frame["BG-price"].to_numpy().reshape(941, 96)[:940].astype(float))
    return arrays, frame


def test_actual_labels_and_dates_prove_no_embargo_needed():
    m = followup(); arrays, frame = synthetic(); result = m.audit_arrays(arrays, frame)
    assert result["targets_exactly_match_source"] and result["excluded_origins"] == 0
    assert result["last_target_offset_hours"] == 23.75 and result["forecast_duration_hours"] == 24
    assert [x["clean_validation_origins"] for x in result["boundaries"]] == [125, 135, 174]
    frame.index = frame.index.as_unit("us")
    assert m.audit_arrays(arrays, frame) == result


def test_closed_parent_lock_prevents_freezing_active_evidence(tmp_path):
    m = followup(); root = tmp_path / m.PARENT; root.mkdir()
    with (root / "controller.lock").open("a+") as lock:
        m.fcntl.flock(lock, m.fcntl.LOCK_EX | m.fcntl.LOCK_NB)
        with pytest.raises(BlockingIOError):
            m.freeze_parent(SimpleNamespace(parent_campaign=root), None, {})


@pytest.mark.parametrize("defect", ["labels", "missing_row", "wrong_cadence", "overlap"])
def test_timestamp_or_label_inconsistency_blocks_certification(defect):
    m = followup(); arrays, frame = synthetic()
    if defect == "labels": arrays.response[0, 0] += 1
    elif defect == "missing_row": frame = frame.drop(frame.index[100])
    elif defect == "wrong_cadence": frame.index = pd.date_range(frame.index[0], periods=len(frame), freq="1h", tz="UTC")
    else:
        frame.index = pd.date_range(frame.index[0], periods=len(frame), freq="1h", tz="UTC")
        arrays.anchors = frame.index[np.arange(940) * 24]
        rows = np.arange(940)[:, None] * 24 + np.arange(96)[None, :]
        arrays.response = frame["BG-price"].to_numpy()[rows].astype(float)
    with pytest.raises((ValueError, RuntimeError)):
        m.audit_arrays(arrays, frame, expected_step_minutes=60 if defect == "overlap" else 15)


def test_watcher_never_launches_models_or_mutates_parent():
    m = followup()
    assert m.TAG != m.PARENT
    text = Path(m.__file__).read_text()
    assert "no_fits_repeated=True" in text and "no_scores_regenerated=True" in text
    assert '"controller.lock").open("r")' in text
    assert "parent_evidence.json" in text and "NOT_READY_FOR_INTEGRATION" in text
    assert "_run_al(" not in text and "_run_queue(" not in text and "Rscript" not in text


def test_progress_and_completed_evidence_resume_are_read_only(tmp_path, monkeypatch):
    m = followup(); parent = tmp_path / m.PARENT; output = tmp_path / m.TAG
    args = SimpleNamespace(parent_campaign=parent, output=output)
    m.REC.write(parent / "al_internal/x/split=1/quantiles/al/tau=0.50/terminal.json", {})
    assert m.snapshot(args)["primary_al_atoms_complete"] == 1
    for path in (output / "terminal.json", output / "source_identity.json", parent / "example.json"):
        m.REC.write(path, {})
    m.REC.write(output / "cadence_audit.json", dict(evidence_sha256={}))
    m.REC.write(output / "parent_evidence.json", dict(evidence_sha256={str(parent / "example.json"): m.REC.digest(parent / "example.json")}))
    m.finish_receipt(output)
    monkeypatch.setattr(m, "own_identity", lambda args: "frozen")
    assert m.run(args) == {}
    m.REC.write(parent / "example.json", {"changed": True})
    with pytest.raises(RuntimeError): m.run(args)


@pytest.mark.parametrize("state", ["complete", "blocked", "false_complete"])
def test_final_freeze_independently_checks_completion_and_preserves_parent(tmp_path, monkeypatch, state):
    m = followup(); parent = tmp_path / m.PARENT; output = tmp_path / m.TAG
    args = SimpleNamespace(parent_campaign=parent, output=output, parent_prep=tmp_path / "prep", frozen_code_root=tmp_path)
    parent.mkdir(); (parent / "controller.lock").touch()
    jobs = []
    for candidate in range(37):
        for split in (1, 2, 3):
            fit = parent / f"rhs/fits/c{candidate}s{split}"
            m.REC.write(fit / "validation_score.json", {"score": 1})
            jobs.append(dict(candidate_id=f"c{candidate}", tau0=.001, split=split,
                output_dir=str(fit), contract_path="unused"))
    (parent / "rhs").mkdir(exist_ok=True)
    pd.DataFrame(jobs).to_csv(parent / "rhs/manifest.csv", index=False)
    for candidate in range(3):
        for split in (1, 2, 3):
            root = parent / f"al_internal/c{candidate}/split={split}"
            eligible = state != "false_complete" or (candidate, split) != (0, 1)
            m.REC.write(root / "metrics.json", dict(eligible=eligible, test_opened=False,
                candidate_id=f"c{candidate}", split=split, tau0=.001,
                accepted_quantiles=[dict(accepted=True) for _ in range(7)]))
            m.REC.write(root / "successor_ladder_hashes.json", dict(evidence_sha256={
                str(root / "metrics.json"): m.REC.digest(root / "metrics.json")}))
            for q in m.RT.QUANTILES:
                m.REC.write(root / f"quantiles/al/tau={q:.2f}/terminal.json", dict(
                    posterior_target_sha256="target", external_gate_passed=True, formal_converged=True))
    m.REC.write(parent / "al_internal/progress.json", dict(complete=9, failed=0))
    if state == "blocked": m.REC.write(parent / "blocked.json", dict(error="gated"))
    else: m.REC.write(parent / "terminal.json", dict(status="R123_CERTIFIED_INTERNAL_COMPLETE_TEST_BLOCKED"))
    m.REC.write(output / "cadence_audit.json", dict(evidence_sha256={}))
    m.REC.write(output / "source_identity.json", {})
    m.REC.write(parent / "al_launch_authorization.json", dict(independent_al_authorized=True,
        test_opened=False, exal_authorized=False, joint_authorized=False, mcmc_authorized=False,
        selected=[dict(candidate_id=f"c{i}", tau0=.001) for i in range(3)]))
    monkeypatch.setattr(m, "own_identity", lambda args: "frozen")
    owner = SimpleNamespace(verify=lambda args: None, normal_valid=lambda path: True,
        verified_score=lambda *args: None, quantile_valid=lambda *args: True)
    # Exact atom/contract checks have their own fault-injection suite.
    monkeypatch.setattr(m, "audit_ladder", lambda args, owner, control, path, expected, rows: m.REC.read(path))
    before = {str(p): m.REC.digest(p) for p in parent.rglob("*") if p.is_file()}
    if state == "false_complete":
        with pytest.raises(RuntimeError): m.freeze_parent(args, owner, dict(code_head="frozen"))
    else:
        result = m.freeze_parent(args, owner, dict(code_head="frozen"))
        assert result["status"] == ("R123_CADENCE_VERIFIED_PARENT_COMPLETE" if state == "complete" else "R123_PARENT_INCOMPLETE_FROZEN")
        assert result["integration_status"] == "NOT_READY_FOR_INTEGRATION"
        assert result["complete_normal_candidate_scale_groups"] == 37
        m.REC.verify_evidence(m.REC.read(output / "completed_evidence.json"))
    assert {str(p): m.REC.digest(p) for p in parent.rglob("*") if p.is_file()} == before
