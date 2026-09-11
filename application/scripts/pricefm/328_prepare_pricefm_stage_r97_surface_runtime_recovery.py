#!/usr/bin/env python3
"""Rebind preserved R97 surfaces and authorize only bounded normal convergence recovery."""

from __future__ import annotations

import argparse
import fcntl
import json
import math
from pathlib import Path
import socket
import subprocess
from typing import Any

import pandas as pd

from pricefm_r97_distributed_contract import firewall, validate_firewall, verify_seal, write_sealed
from pricefm_region_frozen_contract import (
    atomic_write_json,
    canonical_sha256,
    file_record,
    git_identity,
    sha256_file,
    verify_file_record,
)


TRIGGER = "finite_nonconverged_normal_rhs_at_iteration_ceiling"
RECOVERY_POLICY = {
    "enabled": True,
    "trigger": TRIGGER,
    "retry_max_iter": 500,
    "tol": 1e-5,
    "preserve_initial_diagnostics": True,
}
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--shard-contract", type=Path, required=True)
    value.add_argument("--campaign-root", type=Path, required=True)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--host", choices=("muscat", "jerez"), required=True)
    value.add_argument("--output-dir", type=Path, required=True)
    value.add_argument("--write", action="store_true")
    value.add_argument("--force", action="store_true")
    return value


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"true", "1", "yes", "y", "on"}


def is_ancestor(root: Path, ancestor: str, descendant: str) -> bool:
    return subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    ).returncode == 0


def lock_available(path: Path) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = path.open("a+")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        return False
    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    handle.close()
    return True


def load_contract(path: Path, host: str, campaign_root: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text())
    verify_seal(payload, "shard_contract_sha256", label="R97 surface recovery shard contract")
    validate_firewall(payload, label="R97 surface recovery shard contract")
    if payload.get("mode") != "freeze" or payload.get("host") != host:
        raise RuntimeError("R97 surface recovery requires the matching frozen host contract")
    if Path(payload["campaign_root"]).resolve() != campaign_root.resolve():
        raise RuntimeError("R97 surface recovery campaign root differs from the shard contract")
    recovery = payload.get("transition_recovery") or {}
    required = {
        "surface_launch_control_rebind_authorized": True,
        "normal_convergence_retry_authorized": True,
        "normal_convergence_retry_max_iter": 500,
    }
    if any(recovery.get(name) != expected for name, expected in required.items()):
        raise RuntimeError("R97 shard contract does not authorize the bounded surface recovery")
    if not math.isclose(float(recovery.get("normal_convergence_tolerance", math.nan)), 1e-5, rel_tol=0.0, abs_tol=1e-15):
        raise RuntimeError("R97 shard contract does not preserve the normal convergence tolerance")
    for name in ("parent_campaign_contract", "checkpoint", "assignment"):
        verify_file_record(payload[name], label=f"R97 surface recovery {name}")
    assignment = pd.read_csv(payload["assignment"]["path"])
    owned = assignment.loc[assignment.assigned_host.astype(str).eq(host), "region"].astype(str).tolist()
    if owned != list(payload["regions"]):
        raise RuntimeError("R97 surface recovery ownership differs from the sealed assignment")
    return payload


def verify_pipeline(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text())
    expected = str(payload.get("pipeline_contract_sha256", ""))
    unhashed = {key: value for key, value in payload.items() if key != "pipeline_contract_sha256"}
    if not expected or canonical_sha256(unhashed) != expected:
        raise RuntimeError(f"R97 surface pipeline canonical hash changed: {path}")
    validate_firewall(payload, label="R97 surface pipeline")
    for name in (
        "selected_normal_contract", "source_data_config", "generated_data_config",
        "normal_full_config", "runtime_manifest", "runner",
    ):
        record = payload.get(name)
        if name == "runner":
            # The task-bound scientific runner remains hash-pinned below. The launcher
            # itself is intentionally repaired by this operational recovery.
            continue
        verify_file_record(record, label=f"R97 surface pipeline {name}")
    return payload


def verify_manifest(path: Path, pipeline_hash: str) -> pd.DataFrame:
    frame = pd.read_csv(path)
    if frame.empty or frame.task_id.duplicated().any() or len(frame) != 45:
        raise RuntimeError(f"R97 surface manifest is not the exact 45-task DAG: {path}")
    if set(frame.pipeline_contract_sha256.astype(str)) != {pipeline_hash}:
        raise RuntimeError("R97 surface manifest is not bound to the preserved pipeline")
    for name in ("launch_authorized", "test_opened", *BLOCKED):
        if name not in frame or frame[name].map(boolish).any():
            raise RuntimeError(f"R97 surface manifest violates firewall field {name}")
    for row in frame.to_dict("records"):
        task_path = Path(row["task_config"])
        if sha256_file(task_path) != str(row["task_config_sha256"]):
            raise RuntimeError(f"R97 surface task hash changed: {row['task_id']}")
        task = json.loads(task_path.read_text())
        if task.get("pipeline_contract_sha256") != pipeline_hash or task.get("test_opened") is not False:
            raise RuntimeError(f"R97 surface task violates its pipeline/firewall: {row['task_id']}")
        for source, digest in (
            (task["data_config"], task["data_config_sha256"]),
            (task["runner_script"], task["runner_script_sha256"]),
        ):
            if sha256_file(source) != str(digest):
                raise RuntimeError(f"R97 surface task source hash changed: {source}")
        if task["runner_type"] == "normal_full" and sha256_file(task["normal_full_config"]) != str(
            task["normal_full_config_sha256"]
        ):
            raise RuntimeError(f"R97 normal full configuration hash changed: {row['task_id']}")
    return frame


def verify_preprocessing(path: Path, pipeline_hash: str) -> dict[str, Any]:
    payload = json.loads(path.read_text())
    if (
        payload.get("status") != "completed"
        or payload.get("pipeline_contract_sha256") != pipeline_hash
        or payload.get("test_opened") is not False
    ):
        raise RuntimeError(f"R97 preprocessing terminal is not reusable: {path}")
    for record in payload.get("artifacts") or []:
        verify_file_record(record, label="R97 surface preprocessing artifact")
    return payload


def updated_control(
    control: dict[str, Any], identity: dict[str, Any], source_record: dict[str, Any],
) -> dict[str, Any]:
    payload = dict(control)
    payload["git_identity"] = identity
    payload["normal_convergence_recovery"] = dict(RECOVERY_POLICY)
    payload["surface_runtime_recovery"] = {
        "reason": "preserve_R97_surface_DAG_and_retry_only_finite_normal_RHS_iteration_ceiling",
        "source_launch_control_path": source_record["path"],
        "source_launch_control_sha256": source_record["sha256"],
        "source_launch_control_bytes": source_record["bytes"],
        "source_git_identity": control["git_identity"],
        "pipeline_changed": False,
        "manifest_changed": False,
        "task_configs_changed": False,
        "DESN_or_tau0_changed": False,
        "test_opened": False,
    }
    return payload


def run(args: argparse.Namespace) -> dict[str, Any]:
    campaign_root = args.campaign_root.resolve()
    code_root = args.code_root.resolve()
    if not socket.gethostname().lower().startswith(args.host):
        raise RuntimeError(f"R97 {args.host} surface recovery cannot run on {socket.gethostname()}")
    output = args.output_dir.resolve()
    ledger_path = output / "pricefm_stage_r97_surface_runtime_recovery_ledger.csv"
    summary_path = output / "pricefm_stage_r97_surface_runtime_recovery.json"
    if (ledger_path.exists() or summary_path.exists()) and not args.force:
        raise FileExistsError("R97 surface recovery output exists; use --force for an idempotent refresh")
    contract = load_contract(args.shard_contract.resolve(), args.host, campaign_root)
    identity = git_identity(code_root)
    if not identity.clean or identity.head != identity.upstream_head or not identity.branch.startswith("work/pricefm-"):
        raise RuntimeError("R97 surface recovery requires a clean synchronized PriceFM task branch")
    source_head = str(contract["code_git_identity"]["head"])
    if not is_ancestor(code_root, source_head, identity.head):
        raise RuntimeError("R97 surface recovery code is not a descendant of the sealed shard code")

    rows: list[dict[str, Any]] = []
    pending: list[tuple[Path, dict[str, Any]]] = []
    for region in contract["regions"]:
        grid = campaign_root / "regions" / region / "surface_grid"
        pipeline_path = grid / "pipeline_contract.json"
        manifest_path = grid / "task_manifest.csv"
        control_path = grid / "launch_control.json"
        preprocessing_path = grid / "preprocessing_terminal.json"
        if not pipeline_path.is_file():
            rows.append({"region": region, "status": "surface_not_prepared", "control_changed": False})
            continue
        pipeline = verify_pipeline(pipeline_path)
        pipeline_hash = str(pipeline["pipeline_contract_sha256"])
        manifest = verify_manifest(manifest_path, pipeline_hash)
        preprocessing = verify_preprocessing(preprocessing_path, pipeline_hash)
        control = json.loads(control_path.read_text())
        validate_firewall(control, label=f"R97 {region} launch control")
        if control.get("launch_authorized") is not False or control.get("pipeline_contract_sha256") != pipeline_hash:
            raise RuntimeError(f"R97 {region} launch control is not bound and sealed pre-test")
        old_identity = control["git_identity"]
        if not is_ancestor(code_root, str(old_identity["head"]), identity.head):
            raise RuntimeError(f"R97 {region} launch control is not an ancestor of recovery code")
        already_current = old_identity == identity.to_dict() and control.get("normal_convergence_recovery") == RECOVERY_POLICY
        unlocked = lock_available(grid / "launcher.lock")
        status = "already_current" if already_current else ("ready_to_rebind" if unlocked else "deferred_live_launcher")
        replacement = updated_control(control, identity.to_dict(), file_record(control_path, "preserved_launch_control"))
        if args.write and not already_current:
            if not unlocked:
                raise RuntimeError(f"R97 {region} launcher is active; recovery rebind refused")
            pending.append((control_path, replacement))
            status = "rebound"
        rows.append({
            "region": region, "status": status, "control_changed": bool(args.write and not already_current),
            "tasks": len(manifest), "preprocessing_artifacts": len(preprocessing.get("artifacts") or []),
            "pipeline_contract_sha256": pipeline_hash,
            "source_control_sha256": sha256_file(control_path),
            "source_git_head": old_identity["head"], "target_git_head": identity.head,
            "test_opened": False,
        })

    for path, payload in pending:
        atomic_write_json(path, payload)
        observed = json.loads(path.read_text())
        if observed.get("git_identity") != identity.to_dict() or observed.get("normal_convergence_recovery") != RECOVERY_POLICY:
            raise RuntimeError(f"R97 surface launch-control recovery verification failed: {path}")

    output.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(ledger_path, index=False)
    result = {
        "schema_version": 1,
        "stage": "R97-surface-runtime-recovery",
        "status": "controls_rebound" if args.write else "audited_not_mutated",
        "host": args.host,
        "regions_assigned": len(contract["regions"]),
        "surfaces_prepared": sum(row["status"] != "surface_not_prepared" for row in rows),
        "controls_rebound": sum(row["status"] == "rebound" for row in rows),
        "deferred_live_launchers": sum(row["status"] == "deferred_live_launcher" for row in rows),
        "normal_convergence_recovery": RECOVERY_POLICY,
        "code_git_identity": identity.to_dict(),
        "shard_contract": file_record(args.shard_contract.resolve(), "surface_recovery_shard_contract"),
        "ledger": file_record(ledger_path, "surface_runtime_recovery_ledger"),
        "pipeline_or_manifest_mutated": False,
        "model_fitting_invoked": False,
        "launch_invoked": False,
        **firewall(),
    }
    result = write_sealed(summary_path, result, "surface_runtime_recovery_sha256")
    report = output / "pricefm_stage_r97_surface_runtime_recovery.md"
    report.write_text(
        "# PriceFM Stage-R97 surface runtime recovery\n\n"
        f"- Host: `{args.host}`\n"
        f"- Status: `{result['status']}`\n"
        f"- Prepared surfaces: {result['surfaces_prepared']}\n"
        f"- Controls rebound: {result['controls_rebound']}\n"
        f"- Deferred live launchers: {result['deferred_live_launchers']}\n"
        "- Recovery changes only the clean synchronized launch identity and the bounded "
        "normal-RHS iteration ceiling (500 at unchanged tolerance 1e-5).\n"
        "- DESN, tau0, data, task IDs, dependencies, validation-only selection, and all "
        "test/registry/article/joint/MCMC firewalls remain unchanged.\n"
    )
    return result


def main() -> int:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
