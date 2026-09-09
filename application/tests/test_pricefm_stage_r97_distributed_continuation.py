from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import threading
import time
from types import SimpleNamespace

import pytest
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application/scripts/pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_r97_distributed_contract import (  # noqa: E402
    assign_regions,
    estimate_remaining,
    sealed_payload,
    valid_compaction_marker,
    verify_seal,
)
from pricefm_region_frozen_contract import atomic_write_json, file_record  # noqa: E402


def load_numbered(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


PREP = load_numbered(
    "pricefm_stage_r97_distributed_prep",
    "323_prepare_pricefm_stage_r97_distributed_continuation.py",
)
HOST = load_numbered(
    "pricefm_stage_r97_host_shard",
    "324_orchestrate_pricefm_stage_r97_host_shard.py",
)
TRANSFER = load_numbered(
    "pricefm_stage_r97_transfer",
    "325_transfer_pricefm_stage_r97_host_shard.py",
)
FINALIZE = load_numbered(
    "pricefm_stage_r97_finalize",
    "326_finalize_pricefm_stage_r97_distributed_campaign.py",
)


def test_seal_rejects_mutation() -> None:
    payload = sealed_payload({"stage": "R97", "launch_authorized": False}, "sha256")
    verify_seal(payload, "sha256", label="test")
    payload["launch_authorized"] = True
    with pytest.raises(RuntimeError, match="canonical hash changed"):
        verify_seal(payload, "sha256", label="test")


def test_compaction_marker_requires_hash_valid_retained_files(tmp_path: Path) -> None:
    retained = tmp_path / "metric.csv"
    retained.write_text("metric,value\nAQL,1.0\n")
    marker = tmp_path / "r97_compaction_terminal.json"
    atomic_write_json(marker, {
        "status": "completed_compacted",
        "retained": [file_record(retained, "selection_metric")],
    })
    assert valid_compaction_marker(marker)
    retained.write_text("metric,value\nAQL,2.0\n")
    assert not valid_compaction_marker(marker)


def test_assignment_is_exclusive_deterministic_and_quota_bound() -> None:
    rows = [
        {"region": f"R{index:02d}", "estimated_remaining_cpu_seconds": index * 100.0}
        for index in range(1, 38)
    ]
    first, loads = assign_regions(rows, jerez_region_count=25)
    second, _ = assign_regions(reversed(rows), jerez_region_count=25)
    assert [(row["region"], row["assigned_host"]) for row in first] == [
        (row["region"], row["assigned_host"]) for row in second
    ]
    assert len({row["region"] for row in first}) == 37
    assert sum(row["assigned_host"] == "jerez" for row in first) == 25
    assert sum(row["assigned_host"] == "muscat" for row in first) == 12
    assert all(row["max_concurrent_models_per_region"] == 2 for row in first)
    assert set(loads) == {"muscat", "jerez"}


def test_remaining_estimate_preserves_completed_work() -> None:
    rows = [{
        "region": "AT",
        "ridge_total": 240,
        "ridge_complete": 100,
        "rhs_total": 90,
        "rhs_complete": 0,
        "refinement_total": 0,
        "refinement_complete": 0,
        "surface_total": 45,
        "surface_complete": 0,
        "region_closeout_complete": False,
        "median_cell_seconds": 10.0,
    }]
    result = estimate_remaining(rows, 20.0)[0]
    assert result["estimated_remaining_cells"] == (140 * 3 + 90 * 3 + 45)
    assert result["estimated_remaining_cpu_seconds"] == 7350.0


def test_preview_materializes_non_launchable_host_contracts(tmp_path: Path, monkeypatch) -> None:
    campaign = tmp_path / "campaign"
    campaign.mkdir()
    sources = {}
    for name in ("authority_registry", "resolved_controls", "se2_reuse", "source_data_config"):
        path = tmp_path / f"{name}.txt"
        path.write_text(name)
        sources[name] = file_record(path, name)
    parent = {
        "schema_version": 1,
        "campaign_root": str(campaign.resolve()),
        "regions_to_fit": [f"R{index:02d}" for index in range(1, 38)],
        **sources,
    }
    parent = sealed_payload(parent, "campaign_contract_sha256")
    parent_path = tmp_path / "parent.json"
    atomic_write_json(parent_path, parent)
    monkeypatch.setattr(PREP, "controller_lock_available", lambda _: False)
    monkeypatch.setattr(PREP, "git_identity", lambda _: SimpleNamespace(to_dict=lambda: {
        "worktree": str(tmp_path), "branch": "work/pricefm-test", "head": "abc",
        "upstream": "origin/work/pricefm-test", "upstream_head": "abc", "clean": True,
    }))
    output = tmp_path / "output"
    args = SimpleNamespace(
        campaign_contract=parent_path,
        campaign_root=campaign,
        code_root=tmp_path,
        output_dir=output,
        mode="preview",
        muscat_workers=20,
        jerez_workers=50,
        jerez_regions=25,
        fallback_cell_seconds=260.0,
        write=True,
        force=False,
    )
    summary = PREP.build(args)
    assert summary["status"] == "preview_not_launchable"
    assert summary["assignment_counts"] == {"muscat": 12, "jerez": 25}
    for host in ("muscat", "jerez"):
        path = output / f"pricefm_stage_r97_{host}_shard_contract.json"
        payload = json.loads(path.read_text())
        verify_seal(payload, "shard_contract_sha256", label=host)
        assert payload["launch_authorized"] is False
        assert payload["global_test_scoring_authorized"] is False
        assert payload["test_opened"] is False


def test_freeze_refuses_live_original_controller(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(PREP, "_contract", lambda *_: {"regions_to_fit": []})
    monkeypatch.setattr(PREP, "controller_lock_available", lambda _: False)
    args = SimpleNamespace(
        campaign_contract=tmp_path / "parent.json", campaign_root=tmp_path,
        code_root=tmp_path, output_dir=tmp_path / "out", mode="freeze",
        muscat_workers=20, jerez_workers=50, jerez_regions=0,
        fallback_cell_seconds=260.0, write=False, force=False,
    )
    with pytest.raises(RuntimeError, match="stopped and drained"):
        PREP.build(args)


def test_host_controller_cannot_open_global_scoring() -> None:
    source = (SCRIPT_DIR / "324_orchestrate_pricefm_stage_r97_host_shard.py").read_text()
    assert ".score(" not in source
    assert "PREP_SCORING" not in source
    assert "SCORE_CASE" not in source
    assert "global_test_scoring_invoked\": False" in source


def test_host_contract_rejects_preview_mode(tmp_path: Path) -> None:
    contract = sealed_payload({
        "mode": "preview", "host": "muscat", "workers": 2,
        "campaign_root": str(tmp_path), "regions": [],
        "parent_campaign_contract": {}, "checkpoint": {}, "assignment": {},
        "launch_authorized": False, "global_test_scoring_authorized": False,
        "test_opened": False, "test_access_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False,
    }, "shard_contract_sha256")
    path = tmp_path / "contract.json"
    atomic_write_json(path, contract)
    args = SimpleNamespace(
        shard_contract=path, host="muscat", workers=2, campaign_root=tmp_path,
    )
    with pytest.raises(RuntimeError, match="only a frozen"):
        HOST.load_contract(args)


def test_screening_scheduler_caps_each_region_at_two_models(tmp_path: Path, monkeypatch) -> None:
    manifest_roots = {}
    for region in ("A", "B"):
        root = tmp_path / region / "generated"
        root.mkdir(parents=True)
        pd.DataFrame([
            {"id": f"{region}{index}", "run_dir": str(tmp_path / region / f"run{index}")}
            for index in range(4)
        ]).to_csv(root / "manifest.csv", index=False)
        manifest_roots[region] = root

    class FakeCampaign:
        def paths(self, region):
            return {"generated": manifest_roots[region]}

    shard = HOST.HostShard.__new__(HOST.HostShard)
    shard.args = SimpleNamespace(campaign_root=tmp_path, throttle_admission_free_gib=0.0)
    shard.regions = ["A", "B"]
    shard.cpus = [0, 1, 2, 3]
    shard.root = tmp_path / "state"
    shard.root.mkdir()
    shard.drain = shard.root / "DRAIN"
    shard.campaign = FakeCampaign()
    shard.state_lock = threading.Lock()
    shard.admission_open = lambda: True
    shard.per_region_limit = lambda: 2
    shard.update = lambda **_: None
    active = {"A": 0, "B": 0}
    maxima = {"A": 0, "B": 0}
    lock = threading.Lock()

    def fake_task(region, row, cpu, phase):
        with lock:
            active[region] += 1
            maxima[region] = max(maxima[region], active[region])
        time.sleep(0.01)
        with lock:
            active[region] -= 1
        return {"region": region, "id": row.id, "phase": phase, "status": "completed", "cpu": cpu}

    shard.screening_task = fake_task
    monkeypatch.setattr(HOST, "valid_compaction_marker", lambda _: False)
    assert shard.run_screening_phase("generated", "ridge")
    assert maxima == {"A": 2, "B": 2}
    assert len(pd.read_csv(shard.root / "ridge_status.csv")) == 8


def test_transfer_inventory_round_trip_and_hash_failure(tmp_path: Path, monkeypatch) -> None:
    base = tmp_path / "base"
    payload_root = base / "payload"
    payload_root.mkdir(parents=True)
    source = payload_root / "artifact.csv"
    source.write_text("x\n1\n")
    parent_path = base / "parent.json"
    atomic_write_json(parent_path, {"source": "test"})
    assignment = base / "assignment.csv"
    assignment.write_text("region,assigned_host\nAT,jerez\n")
    checkpoint = base / "checkpoint.json"
    atomic_write_json(checkpoint, {"status": "frozen"})
    contract = sealed_payload({
        "host": "jerez", "regions": ["AT"],
        "parent_campaign_contract": file_record(parent_path, "parent"),
        "checkpoint": file_record(checkpoint, "checkpoint"),
        "assignment": file_record(assignment, "assignment"),
    }, "shard_contract_sha256")
    contract_path = base / "contract.json"
    atomic_write_json(contract_path, contract)
    monkeypatch.setattr(TRANSFER, "transfer_roots", lambda *_: [(payload_root, "test_payload")])
    output = tmp_path / "inventory"
    inventory_args = SimpleNamespace(
        shard_contract=contract_path, base_root=base, campaign_root=base,
        output_dir=output, scope="all", force=False,
    )
    summary = TRANSFER.inventory(inventory_args)
    verify_args = SimpleNamespace(
        inventory=Path(summary["manifest"]), target_base_root=base, output=None,
    )
    assert TRANSFER.verify(verify_args)["status"] == "verified"
    source.write_text("x\n2\n")
    failure = TRANSFER.verify(verify_args)
    assert failure["status"] == "verification_failed"
    assert failure["failures"][0]["reason"] == "sha256_mismatch"


def test_transfer_rejects_symlink_escape(tmp_path: Path) -> None:
    base = tmp_path / "base"
    base.mkdir()
    outside = tmp_path / "outside.txt"
    outside.write_text("outside")
    link = base / "escape"
    link.symlink_to(outside)
    with pytest.raises(RuntimeError, match="escapes the declared root"):
        TRANSFER.record(link, base, "bad")


def test_reconciliation_rejects_overlapping_region_ownership(tmp_path: Path) -> None:
    campaign = tmp_path / "campaign"
    for host in ("muscat", "jerez"):
        root = campaign / "distributed" / host
        root.mkdir(parents=True)
        terminal = sealed_payload({
            "status": "completed_validation_shard", "host": host,
            "regions_assigned": ["AT"], "regions_completed": ["AT"],
            "test_opened": False, "test_access_authorized": False,
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
            "joint_model_authorized": False, "mcmc_authorized": False,
        }, "shard_terminal_sha256")
        atomic_write_json(root / "shard_terminal.json", terminal)
    contracts = []
    for host in ("muscat", "jerez"):
        payload = sealed_payload({
            "mode": "freeze", "host": host, "campaign_root": str(campaign),
            "regions": ["AT"],
            "checkpoint": {"sha256": "same"}, "assignment": {"sha256": "same"},
            "test_opened": False, "test_access_authorized": False,
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
            "joint_model_authorized": False, "mcmc_authorized": False,
        }, "shard_contract_sha256")
        path = tmp_path / f"{host}.json"
        atomic_write_json(path, payload)
        contracts.append(path)
    args = SimpleNamespace(
        muscat_contract=contracts[0], jerez_contract=contracts[1],
        campaign_root=campaign, output_dir=tmp_path / "out", force=False,
    )
    with pytest.raises(RuntimeError, match="disjoint"):
        FINALIZE.reconcile(args)


def test_scoring_requires_explicit_one_time_token(tmp_path: Path) -> None:
    reconciliation = sealed_payload({
        "status": "completed_37_region_validation_reconciliation_test_still_sealed",
        "muscat_contract": {"path": str(tmp_path / "missing")},
        "test_opened": False, "test_access_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False,
    }, "reconciliation_sha256")
    path = tmp_path / "reconciliation.json"
    atomic_write_json(path, reconciliation)
    args = SimpleNamespace(reconciliation_terminal=path, approval_token="", campaign_root=tmp_path)
    with pytest.raises(RuntimeError, match="one-time test scoring requires"):
        FINALIZE.score(args)
