"""Prospective FI/DK2 COST_ONLY control, separate from spent qualification grants.

Nothing is submitted on import or prepare-launch. Positive pinned EE delivery,
drain, runtime/parity, source review and site/all-host evidence are mandatory.
All network and Slurm mutations are explicit CLI actions. Held submission lets
Muscat bind the final finite authority to an actual job before releasing it.
"""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import socket
import subprocess
import sys
import time
import uuid

from . import benchmark as b, benchmark_plan as p, control as ctl, registry as r
from .environment import (THREAD_ENV, REFERENCE_NUMERICAL_ENV, EnvironmentError,
                          require_compute, validate_reference_profile_record)

SCHEMA = "r156_hb_cost_control_v1"
REQUEST_SCHEMA = "r156_hb_cost_launch_request_v1"
OWNER = "muscat.be.ucsc.edu"
CENTRAL = p.DATA / "hb_control_registry"
HOSTS = {"muscat.be.ucsc.edu", "jerez.be.ucsc.edu", "hb.ucsc.edu"}
FINAL = {"COLLECTED_COST_ONLY", "FAILED_RECONCILED"}
CODE = ("__init__.py", "benchmark.py", "benchmark_plan.py", "science.py", "fixture.py",
        "environment.py", "control.py", "registry.py", "cost_control.py")
SHA = re.compile(r"[a-f0-9]{64}\Z")


class GateError(ValueError):
    pass


def pin(path):
    path = r.no_links(path)
    return {"path": str(path), "sha256": r.digest(path)}


def pinned(value, parse=True):
    if (not isinstance(value, dict) or set(value) != {"path", "sha256"}
            or not isinstance(value["sha256"], str) or not SHA.fullmatch(value["sha256"])):
        raise GateError("missing exact path/SHA256 evidence pin")
    if not Path(value["path"]).is_absolute():
        raise GateError("absolute evidence paths required")
    path = r.no_links(value["path"])
    if not path.is_absolute() or not path.is_file() or r.digest(path) != value["sha256"]:
        raise GateError("missing or changed pinned evidence: " + str(path))
    return r.read(path) if parse else path


def fresh(value, now):
    epoch = value.get("observed_epoch")
    return type(epoch) in (int, float) and math.isfinite(epoch) and 0 <= now - epoch <= 300


def owner():
    if socket.getfqdn() != OWNER:
        raise GateError("only canonical Muscat may issue or mutate COST_ONLY claims")


def executed_sources():
    return {name: r.digest(Path(__file__).with_name(name)) for name in CODE}


def load_plan(path):
    r.no_links(path)
    p.dry_run(path)
    plan = p.read_metadata(path)
    if plan.get("study") not in ("FI", "DK2") or plan.get("resources") != p.LIMITS:
        raise GateError("only the exact future FI/DK2 COST_ONLY protocol is supported")
    if set(plan["adapter_feasibility"]["adapter_sources"]) != {"benchmark.py", "benchmark_plan.py", "science.py", "fixture.py", "environment.py"}:
        raise GateError("complete five-file benchmark adapter pin set required")
    for name, sha in plan["adapter_feasibility"]["adapter_sources"].items():
        if name not in CODE or r.digest(Path(__file__).with_name(name)) != sha:
            raise GateError("reviewed benchmark adapter source differs")
    return plan


def validate_gates(request, plan, plan_sha, now=None):
    """Pure local proof checks. Missing/currently negative gates cannot claim work."""
    now = time.time() if now is None else now
    if (request.get("schema") != REQUEST_SCHEMA or request.get("plan", {}).get("sha256") != plan_sha
            or request.get("study") != plan["study"] or request.get("full_prefix_admitted") is not False
            or request.get("automatic_retry") is not False):
        raise GateError("new explicitly reviewed region-specific COST_ONLY request required")
    if pinned(request["plan"]) != plan:
        raise GateError("request plan identity differs")
    runtime = pinned(request.get("runtime_result"))
    pools = runtime.get("threadpoolctl")
    if (runtime.get("status") != "verified" or runtime.get("python_version") != "3.11.13"
            or not isinstance(pools, list) or not pools or any(not isinstance(pool, dict) or pool.get("num_threads") != 1 for pool in pools)
            or runtime.get("executable") != request.get("runtime_python")):
        raise GateError("accepted exact qualified HB Python/native runtime required")
    for key in ("runtime_python", "environment_bundle"):
        value = request.get(key, "")
        if (not isinstance(value, str) or not value.startswith("/mnt/beegfs/home/jaguir26/")
                or ".." in Path(value).parts or "\n" in value):
            raise GateError("verified physical HB runtime/bundle paths required")
    if not request["runtime_python"].endswith("/runtime/venv/bin/python"):
        raise GateError("qualified environment interpreter path required")
    parity = pinned(request.get("parity_result"))
    parity_seal = pinned(request.get("parity_seal"))
    if (parity.get("status") != "PASS_TEST_FORECAST_PARITY" or parity.get("accepted") is not True
            or parity.get("execution", {}).get("namespace") != "TEST"
            or parity["execution"].get("fixture_manifest_sha256") != request.get("accepted_parity_fixture_manifest_sha256")
            or parity_seal.get("status") != "COMPLETE_TEST_ONLY"
            or parity_seal.get("artifacts", {}).get(Path(request["parity_result"]["path"]).name)
                != request["parity_result"]["sha256"]):
        raise GateError("complete sealed accepted HB scientific parity required")
    parity_runtime = pinned(request.get("parity_runtime_result"))
    try:
        validate_reference_profile_record(parity_runtime.get("reference_numerical_profile", {}))
    except EnvironmentError as exc:
        raise GateError("accepted parity runtime must attest the historical numerical profile") from exc
    native = parity_runtime.get("native_library_sha256", {})
    if (parity_runtime.get("status") != "verified" or parity_runtime.get("python_version") != runtime["python_version"]
            or parity_runtime.get("executable") != runtime["executable"] or parity_runtime.get("versions") != runtime.get("versions")
            or not parity_runtime.get("threadpoolctl") or any(pool.get("num_threads") != 1 for pool in parity_runtime["threadpoolctl"])
            or len(native) != 2 or any(not Path(path).is_absolute() or not isinstance(sha, str) or not SHA.fullmatch(sha)
                                       for path, sha in native.items())):
        raise GateError("exact same qualified runtime and actual native-library SHA256s required for accepted parity")
    parity_outer_seal = pinned(request.get("parity_qualification_seal"))
    if (parity_outer_seal.get("files", {}).get("environment-runtime.json") != request["parity_runtime_result"]["sha256"]
            or parity_outer_seal.get("job_id") != parity["execution"].get("slurm_job_id")
            or parity_outer_seal.get("job_id") != parity_runtime.get("allocation", {}).get("job_id")):
        raise GateError("historical numerical profile must belong to the same accepted parity job")
    for prefix, result_pin, output_name in (
            ("runtime", request["runtime_result"], "environment-evidence/runtime-verification.json"),
            ("parity", request["parity_result"], "TEST/parity/parity.json")):
        seal = pinned(request.get(prefix + "_qualification_seal"))
        accounting = pinned(request.get(prefix + "_accounting"))
        if (seal.get("schema") != r.SCHEMA or seal.get("application_passed") is not True
                or seal.get("files", {}).get(output_name) != result_pin["sha256"]
                or accounting.get("job_id") != seal.get("job_id") or accounting.get("complete") is not True
                or accounting.get("squeue", "").strip()):
            raise GateError("successful scheduler and application qualification seals required")
        qualification_limits = {"cpus": 1, "memory_MiB": 8192, "wall_seconds": 1800}
        if not ctl.accounting(accounting["sacct"], seal["job_id"], qualification_limits)["complete"]:
            raise GateError("incomplete qualification scheduler accounting")
    ee = pinned(request.get("EE_completion_receipt"))
    required = ee.get("required_task_names", [])
    if (ee.get("status") != "COMPLETE_EE_DISPOSITION_DELIVERED_DRAINED" or len(required) != 12
            or len(required) != len(set(required)) or ee.get("completed_task_names") != required
            or ee.get("assessment_accepted") is not True):
        raise GateError("complete accepted EE disposition and delivered assessment required")
    assessment = pinned(ee.get("scientific_assessment"))
    qualified = assessment.get("qualified_from_unchanged_initial_S0")
    valid_qualified = qualified in (["r134_5c42f007409acfb3"], ["r134_984fd326bd5fd13e"])
    expected_names = ["EE_{}_s{}_S_seed{}".format(package, split, seed)
                      for package in (["C0"] + qualified if valid_qualified else [])
                      for seed in (1, 2) for split in (1, 2, 3)]
    if (assessment.get("status") != "COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT_NOT_PROMOTED"
            or assessment.get("required_task_names") != required or required != expected_names
            or assessment.get("disposition") not in {"STOP_NO_QUALIFYING_CONFIRMED_LEAD",
                "HOLD_ALGORITHMIC_STABILITY_UNRESOLVED", "ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED"}
            or assessment.get("all_new_components_independently_revalidated") is not True
            or assessment.get("AL_proposal_admitted") is not False or assessment.get("automatic_followon") is not False
            or assessment.get("new_fits") != 0 or assessment.get("official_origins") != 0):
        raise GateError("matched complete EE scientific assessment required")
    pinned(ee.get("delivered_report"), parse=False)
    drain = pinned(ee.get("physical_drain"))
    if (drain.get("status") != "DRAINED" or not fresh(drain, now)
            or any(drain.get(key) != [] for key in ("live_worker_pids", "live_job_ids", "active_scientific_claims"))):
        raise GateError("fresh physical EE drain proof required")
    review = pinned(request.get("adapter_review"))
    if (review.get("schema") != "r156_hb_cost_adapter_review_v1" or review.get("status") != "REVIEWED_TESTED_COST_ONLY"
            or review.get("plan_sha256") != plan_sha or review.get("adapter_sources") != plan["adapter_feasibility"]["adapter_sources"]
            or review.get("issuer") != OWNER or review.get("controller_sources") != executed_sources()
            or review.get("tests_passed") is not True or review.get("no_AQL") is not True
            or review.get("no_selection") is not True or review.get("full_prefix_admitted") is not False):
        raise GateError("independently reviewed and tested exact cost adapter required")
    hosts = pinned(request.get("all_hosts_observation"))
    if (hosts.get("schema") != "r156_hb_all_hosts_cost_observation_v1" or hosts.get("status") != "NO_OVERLAP"
            or hosts.get("controller") != OWNER or set(hosts.get("hosts", [])) != HOSTS
            or hosts.get("scientific_exclusion_key") != plan["claim"]["scientific_exclusion_key"]
            or hosts.get("overlapping_scientific_claims") != [] or hosts.get("live_cost_jobs") != [] or not fresh(hosts, now)):
        raise GateError("fresh physical all-host no-overlap observation required")
    site = pinned(request.get("site_admission"))
    memory = site.get("memory_mib")
    if (site.get("schema") != "r156_hb_cost_site_admission_v1" or site.get("status") != "ADMITTED_COST_ONLY_RESOURCES"
            or site.get("study") != plan["study"] or site.get("plan_sha256") != plan_sha
            or site.get("account") != "128x24" or site.get("partition") != "128x24" or site.get("qos") != "normal"
            or not re.fullmatch(r"node-[0-9]+", site.get("node", "")) or not fresh(site, now)
            or type(memory) is not int or not 1024 <= memory <= 8192
            or type(site.get("minimum_required_memory_mib")) is not int or not 0 < site["minimum_required_memory_mib"] <= memory
            or type(site.get("available_memory_mib")) is not int or site["available_memory_mib"] < memory
            or type(site.get("free_disk_bytes")) is not int or site["free_disk_bytes"] < 3 * plan["inventory"]["bytes"] + 1024**3
            or type(site.get("available_cpus")) is not int or site["available_cpus"] < 1
            or type(site.get("calendar_expires_epoch")) not in (int, float)
            or not math.isfinite(site["calendar_expires_epoch"]) or site["calendar_expires_epoch"] < now + 1260
            or site.get("maximum_parent_p") != max(row["p"] for row in plan["all_parent_preflight"])):
        raise GateError("fresh measured account/memory/disk/node/calendar admission required")
    return {"runtime": runtime, "parity": parity, "parity_runtime": parity_runtime, "EE": ee, "site": site, "hosts": hosts}


def task_identity(plan, plan_sha):
    return {"study": plan["study"], "region": plan["region"], "plan_sha256": plan_sha,
            "source": plan["canonical_preparation"]["source"],
            "preparation_sha256": plan["canonical_preparation"]["sha256"],
            "scientific_exclusion_key": plan["claim"]["scientific_exclusion_key"], "all_hosts": sorted(HOSTS)}


class Ledger:
    """Separate one-attempt-per-region journal; no qualification counter reset."""
    def __init__(self, root=None):
        owner()
        root = CENTRAL if root is None else root
        self.root = r.no_links(root)
        if self.root != r.no_links(CENTRAL):
            raise GateError("COST_ONLY claims must use the canonical all-host registry")
        self.root.mkdir(parents=True, exist_ok=True)
        self.path = self.root / "cost_only_registry.json"

    def snapshot(self):
        with r.lock(self.root / "cost_only_registry.lock"):
            return r.read(self.path) if self.path.exists() else {"schema": SCHEMA, "owner": OWNER, "claims": {}, "spent_regions": {}}

    def reserve(self, plan, plan_sha, release_sha, config_sha, release_path, remote_root):
        task = task_identity(plan, plan_sha)
        key = r.identity(task)
        with r.lock(self.root / "cost_only_registry.lock"):
            state = r.read(self.path) if self.path.exists() else {"schema": SCHEMA, "owner": OWNER, "claims": {}, "spent_regions": {}}
            if state.get("schema") != SCHEMA or state.get("owner") != OWNER:
                raise GateError("canonical cost registry identity differs")
            if plan["study"] in state["spent_regions"] or key in state["claims"]:
                raise GateError("regional one-attempt allowance already spent; no retry/refund")
            if any(claim["state"] not in FINAL for claim in state["claims"].values()):
                raise GateError("another all-host cost claim remains active or ambiguous")
            claim = dict(task_key=key, task=task, scope_id=plan["claim"]["planned_attempt_id"], state="RESERVED",
                         release_sha256=release_sha, config_sha256=config_sha, release_path=str(release_path),
                         remote_root=remote_root, reserved_CPU_seconds=1200, wall_seconds=1200, created=time.time(), events=[])
            state["claims"][key] = claim
            state["spent_regions"][plan["study"]] = key
            r.write(self.path, state)
            return claim

    def transition(self, key, expected, target, **fields):
        allowed = {"RESERVED": {"STAGED", "AMBIGUOUS"}, "STAGED": {"SUBMISSION_INTENT", "AMBIGUOUS"},
                   "SUBMISSION_INTENT": {"HELD", "AMBIGUOUS"}, "HELD": {"AUTHORITY_INTENT", "AMBIGUOUS"},
                   "AUTHORITY_INTENT": {"AUTHORIZED", "AMBIGUOUS"},
                   "AUTHORIZED": {"RELEASE_INTENT", "AMBIGUOUS"}, "RELEASE_INTENT": {"SUBMITTED", "AMBIGUOUS"},
                   "SUBMITTED": FINAL, "AMBIGUOUS": FINAL}
        if target not in allowed.get(expected, set()):
            raise GateError("unreviewed cost state transition")
        protected = {"task_key", "task", "scope_id", "release_sha256", "config_sha256", "release_path", "remote_root",
                     "reserved_CPU_seconds", "wall_seconds", "created", "events", "state"}
        if protected & set(fields):
            raise GateError("immutable central claim fields")
        with r.lock(self.root / "cost_only_registry.lock"):
            state = r.read(self.path)
            claim = state["claims"][key]
            if claim["state"] != expected:
                raise GateError("claim state changed")
            claim["events"].append({"from": expected, "to": target, "epoch": time.time()})
            claim.update(fields, state=target)
            r.write(self.path, state)
            return claim

    def poll(self, key):
        with r.lock(self.root / "cost_only_registry.lock"):
            state = r.read(self.path)
            claim = state["claims"][key]
            if claim["state"] not in {"SUBMITTED", "AMBIGUOUS"} or not claim.get("job_id") or time.time() - claim.get("last_poll", 0) < 300:
                raise GateError("known submitted job and 300-second status interval required")
            claim["last_poll"] = time.time()
            r.write(self.path, state)
            return claim


def new_write(path, value):
    path = r.no_links(path)
    if path.exists():
        raise FileExistsError("create-only evidence: " + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    r.write(path, value)


def prepare_launch(plan_path, request_path, config_path, destination):
    """Block before writes, claim creation or SSH unless every positive gate passes."""
    owner()
    try:
        plan = load_plan(plan_path)
        request = r.read(request_path)
        gate = validate_gates(request, plan, r.digest(plan_path))
        c = ctl.config(config_path)
        if not c["remote_root"].startswith("/mnt/beegfs/home/jaguir26/"):
            raise GateError("future cost releases require the verified physical HB namespace")
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError) as exc:
        return {"status": "BLOCKED_NO_CLAIM_NO_NETWORK", "reason": str(exc), "model_calls": 0}
    destination = r.no_links(destination)
    if destination.exists():
        raise FileExistsError("fresh local cost release required")
    destination.mkdir(parents=True)
    release_id = "r156-cost-" + uuid.uuid4().hex
    remote_root = c["remote_root"] + "/" + release_id
    shutil.copyfile(plan_path, destination / "plan.json")
    (destination / "plan.sha256").write_text(r.digest(plan_path) + "\n")
    new_write(destination / "launch-request.json", request)
    stage = destination / "stage"
    for logical, entry in plan["input_allowlist"].items():
        source = r.no_links(logical)
        if ({".ssh", ".git", ".codex"} & set(source.parts)
                or source.name in {"id_rsa", "id_ed25519", "authorized_keys", "known_hosts", ".env"}):
            raise GateError("credential/Git/agent files are excluded from cost staging")
        relative = Path(entry["staged_relative_path"])
        if relative.is_absolute() or ".." in relative.parts or relative != Path("files") / source.relative_to("/"):
            raise GateError("unsafe or altered plan staging membership")
        if not source.is_file() or source.stat().st_size != entry["bytes"] or r.digest(source) != entry["sha256"]:
            raise GateError("future source/parent/bank allowlist bytes differ: " + logical)
        target = stage / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        if r.digest(target) != entry["sha256"]:
            raise GateError("copied allowlist bytes differ")
    code = destination / "code/pricefm_hb"
    code.mkdir(parents=True)
    for name in CODE:
        shutil.copyfile(Path(__file__).with_name(name), code / name)
        if r.digest(code / name) != pinned(request["adapter_review"])["controller_sources"][name]:
            raise GateError("reviewed executed Python closure changed during staging")
    # Nested EE proof pins are relocated only after source proofs pass. Preserve
    # original bytes too; the derived receipt records original receipt SHA256.
    def stage_pin(value):
        original = pinned(value, parse=False)
        rel = Path("proofs") / value["sha256"] / original.name
        target = destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            shutil.copyfile(original, target)
        return {"path": str(Path(remote_root) / rel), "sha256": value["sha256"]}
    proof_pins = {key: stage_pin(request[key]) for key in ("runtime_result", "parity_result", "parity_seal", "adapter_review",
                                                         "parity_runtime_result", "parity_qualification_seal")}
    ee = dict(gate["EE"])
    stage_pin(request["EE_completion_receipt"])
    for name in ("scientific_assessment", "delivered_report", "physical_drain"):
        ee[name] = stage_pin(ee[name])
    ee["relocated_from_receipt_sha256"] = request["EE_completion_receipt"]["sha256"]
    new_write(destination / "proofs/EE_completion_receipt.json", ee)
    proof_pins["EE_completion_receipt"] = {"path": remote_root + "/proofs/EE_completion_receipt.json",
                                           "sha256": r.digest(destination / "proofs/EE_completion_receipt.json")}
    job = """#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 SLURM_EXPORT_ENV=ALL
root=$1
release_sha=$2
export PYTHONPATH="$root/code"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 BLIS_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 NUMEXPR_MAX_THREADS=1
__REFERENCE_PROFILE_EXPORTS__
ulimit -t 1200
exec /usr/bin/srun --cpu-bind=cores /usr/bin/python3 -B -m pricefm_hb.cost_control cost-worker --release "$root" --release-sha256 "$release_sha"
"""
    profile = gate["parity_runtime"]["reference_numerical_profile"]["environment"]
    job = job.replace("__REFERENCE_PROFILE_EXPORTS__", "\n".join("export " + key + "=" + shlex.quote(value) for key, value in sorted(profile.items())))
    (destination / "job.sh").write_text(job)
    files = {str(path.relative_to(destination)): {"sha256": r.digest(path), "bytes": path.stat().st_size}
             for path in sorted(destination.rglob("*")) if path.is_file()}
    release = {"schema": SCHEMA, "release_id": release_id, "study": plan["study"], "remote_root": remote_root,
               "plan_sha256": r.digest(plan_path), "request_sha256": r.digest(destination / "launch-request.json"),
               "config_sha256": r.identity(c), "files": files, "proof_pins": proof_pins,
               "node": gate["site"]["node"], "memory_mib": gate["site"]["memory_mib"], "resources": p.LIMITS,
               "runtime_python": request["runtime_python"], "full_prefix_admitted": False}
    release["reference_numerical_environment"] = profile
    new_write(destination / "release.json", release)
    return {"status": "PREPARED_COST_ONLY_NOT_CLAIMED_NOT_SUBMITTED", "release": str(destination),
            "release_sha256": r.digest(destination / "release.json"), "input_bytes": plan["inventory"]["bytes"]}


def verify_release(root):
    root = ctl.safe_tree(root)
    release = r.read(root / "release.json")
    if (release.get("schema") != SCHEMA or release.get("study") not in ("FI", "DK2")
            or not re.fullmatch(r"r156-cost-[a-f0-9]{32}", release.get("release_id", ""))
            or release.get("resources") != p.LIMITS or release.get("full_prefix_admitted") is not False):
        raise GateError("invalid immutable COST_ONLY release")
    observed = {str(path.relative_to(root)) for path in root.rglob("*") if path.is_file()
                and path.relative_to(root).parts[0] not in {"outputs", "logs", "authorization"}}
    if observed != set(release["files"]) | {"release.json"}:
        raise GateError("cost release membership changed")
    for name, entry in release["files"].items():
        if Path(name).is_absolute() or ".." in Path(name).parts:
            raise GateError("unsafe release member")
        path = root / name
        if r.digest(path) != entry["sha256"] or path.stat().st_size != entry["bytes"]:
            raise GateError("cost release hash changed: " + name)
    if r.digest(root / "plan.json") != release["plan_sha256"] or r.digest(root / "launch-request.json") != release["request_sha256"]:
        raise GateError("cost plan/request hash differs")
    return release


def recheck(root, config_path):
    release = verify_release(root)
    plan = load_plan(Path(root) / "plan.json")
    request = r.read(Path(root) / "launch-request.json")
    gate = validate_gates(request, plan, release["plan_sha256"])
    c = ctl.config(config_path)
    if r.identity(c) != release["config_sha256"] or release["remote_root"] != c["remote_root"] + "/" + release["release_id"]:
        raise GateError("reviewed cost site configuration changed")
    if gate["site"]["node"] != release["node"] or gate["site"]["memory_mib"] != release["memory_mib"]:
        raise GateError("reviewed allocation differs")
    if release.get("reference_numerical_environment") != gate["parity_runtime"]["reference_numerical_profile"]["environment"]:
        raise GateError("reviewed historical numerical profile differs")
    return release, plan, request, gate, c


def pinned_claim_release(claim):
    """A structurally self-consistent rewritten manifest is still not admitted."""
    path = r.no_links(Path(claim["release_path"]) / "release.json")
    if r.digest(path) != claim["release_sha256"]:
        raise GateError("canonical claim release SHA256 differs")
    release = verify_release(claim["release_path"])
    if release["plan_sha256"] != claim["task"]["plan_sha256"] or release["remote_root"] != claim["remote_root"]:
        raise GateError("canonical claim plan/location differs")
    return release


def transfer(c, source, target):
    return ctl.run(["rsync", "-rlt", "--checksum", "--partial", "--delay-updates", "--no-links",
                    "-e", shlex.join(ctl.ssh(c)[:-1]), str(Path(source).absolute()) + "/",
                    c["user"] + "@" + c["host"] + ":" + target + "/"], timeout=240)


def submit_held(release_root, config_path):
    owner()
    release, plan, request, gate, c = recheck(release_root, config_path)
    if ctl.remote(c, ["squeue", "-h", "-u", c["user"], "-o", "%i"]).strip():
        raise GateError("another HB job exists; no cost reservation made")
    ledger = Ledger()
    claim = ledger.reserve(plan, release["plan_sha256"], r.digest(Path(release_root) / "release.json"),
                           r.identity(c), Path(release_root).absolute(), release["remote_root"])
    key, target = claim["task_key"], claim["remote_root"]
    try:
        ctl.remote(c, ["mkdir", "-p", c["remote_root"]])
        ctl.remote(c, ["mkdir", target])
        transfer(c, release_root, target)
        if ctl.remote(c, ["sha256sum", target + "/release.json"]).split()[0] != claim["release_sha256"]:
            raise GateError("staged cost manifest differs")
        ctl.remote(c, ["mkdir", target + "/outputs", target + "/logs"])
        ledger.transition(key, "RESERVED", "STAGED")
    except Exception as exc:
        ledger.transition(key, "RESERVED", "AMBIGUOUS", diagnostic="staging interrupted: " + str(exc))
        raise
    argv = ["sbatch", "--parsable", "--hold", "--export=NONE", "--nodes=1", "--ntasks=1", "--cpus-per-task=1",
            "--no-requeue", "--nodelist=" + release["node"], "--mem=" + str(release["memory_mib"]) + "M",
            "--time=00:20:00", "--account=128x24", "--partition=128x24", "--qos=normal",
            "--job-name=" + release["release_id"], "--chdir=" + target,
            "--output=" + target + "/logs/%j.out", "--error=" + target + "/logs/%j.err",
            target + "/job.sh", target, claim["release_sha256"]]
    ledger.transition(key, "STAGED", "SUBMISSION_INTENT", submission_argv=argv)
    try:
        answer = ctl.remote(c, argv).strip()
        if not re.fullmatch(r"[1-9][0-9]*(?:;[A-Za-z0-9_.-]+)?", answer):
            raise GateError("ambiguous held sbatch reply")
    except Exception as exc:
        ledger.transition(key, "SUBMISSION_INTENT", "AMBIGUOUS", diagnostic="submission may have reached Slurm: " + str(exc))
        raise
    return ledger.transition(key, "SUBMISSION_INTENT", "HELD", job_id=answer.split(";", 1)[0])


def issue_authority(key, config_path):
    """Explicit Muscat CLI issuance; never grants authority to a missing gate."""
    ledger = Ledger()
    claim = ledger.snapshot()["claims"][key]
    if claim["state"] != "HELD":
        raise GateError("one known held job required for authority issuance")
    pinned_claim_release(claim)
    release, plan, request, gate, c = recheck(claim["release_path"], config_path)
    now = time.time()
    cross = {"schema": "r156_hb_cross_server_cost_claim_v1", "status": "EXCLUSIVE_CLAIMED",
             "controller": OWNER, "scope_id": claim["scope_id"], "slurm_job_id": claim["job_id"],
             "scientific_exclusion_key": plan["claim"]["scientific_exclusion_key"],
             "task_key": key, "plan_sha256": release["plan_sha256"], "all_hosts": sorted(HOSTS),
             "study": plan["study"], "region": plan["region"],
             "overlapping_live_claims": [], "all_hosts_observed": True, "observed_epoch": now,
             "observation": request["all_hosts_observation"]}
    packet_root = Path(claim["release_path"]) / "authorization"
    ledger.transition(key, "HELD", "AUTHORITY_INTENT")
    new_write(packet_root / "cross-server-claim.json", cross)
    authority = {"schema": b.AUTHORITY_SCHEMA, "status": "ADMITTED_COST_ONLY", "role": plan["study"] + "_COST_ONLY_BENCHMARK",
                 "issuer": OWNER, "controller": OWNER, "executed_sources": executed_sources(),
                 "reference_numerical_environment": release["reference_numerical_environment"],
                 "study": plan["study"], "scope_id": claim["scope_id"], "plan_sha256": release["plan_sha256"],
                 "scientific_exclusion_key": plan["claim"]["scientific_exclusion_key"], "slurm_job_id": claim["job_id"],
                 "node": release["node"], "resources": p.LIMITS, "memory_mib": release["memory_mib"],
                 "started_epoch": now, "expires_epoch": now + 1200, "automatic_retry": False,
                 "full_prefix_admitted": False, "accepted_parity_fixture_manifest_sha256": request["accepted_parity_fixture_manifest_sha256"],
                 **release["proof_pins"], "cross_server_claim": {
                     "path": claim["remote_root"] + "/authorization/cross-server-claim.json",
                     "sha256": r.digest(packet_root / "cross-server-claim.json")}}
    new_write(packet_root / "authority.json", authority)
    packet = {"schema": SCHEMA, "task_key": key, "release_sha256": claim["release_sha256"],
              "request_sha256": release["request_sha256"], "authority_sha256": r.digest(packet_root / "authority.json"),
              "cross_claim_sha256": r.digest(packet_root / "cross-server-claim.json")}
    new_write(packet_root / "packet.json", packet)
    try:
        transfer(c, packet_root, claim["remote_root"] + "/authorization")
        if ctl.remote(c, ["sha256sum", claim["remote_root"] + "/authorization/packet.json"]).split()[0] != r.digest(packet_root / "packet.json"):
            raise GateError("remote authority packet differs; held claim retained")
    except Exception as exc:
        ledger.transition(key, "AUTHORITY_INTENT", "AMBIGUOUS", diagnostic="authority transfer interrupted: " + str(exc))
        raise
    return ledger.transition(key, "AUTHORITY_INTENT", "AUTHORIZED", authority_sha256=packet["authority_sha256"],
                             packet_sha256=r.digest(packet_root / "packet.json"), expires_epoch=authority["expires_epoch"])


def release_job(key, config_path):
    ledger = Ledger()
    claim = ledger.snapshot()["claims"][key]
    if claim["state"] != "AUTHORIZED":
        raise GateError("known authorized held job required")
    pinned_claim_release(claim)
    _, _, _, _, c = recheck(claim["release_path"], config_path)
    packet_root = Path(claim["release_path"]) / "authorization"
    if (r.digest(packet_root / "packet.json") != claim["packet_sha256"]
            or r.digest(packet_root / "authority.json") != claim["authority_sha256"]):
        raise GateError("canonical issued authority packet changed")
    if claim["expires_epoch"] - time.time() < 60:
        raise GateError("finite cost lease has insufficient remaining time; held claim retained")
    if ctl.remote(c, ["sha256sum", claim["remote_root"] + "/authorization/packet.json"]).split()[0] != claim["packet_sha256"]:
        raise GateError("remote authority packet differs from canonical issue")
    ledger.transition(key, "AUTHORIZED", "RELEASE_INTENT")
    try:
        ctl.remote(c, ["scontrol", "release", claim["job_id"]])
    except Exception as exc:
        ledger.transition(key, "RELEASE_INTENT", "AMBIGUOUS", diagnostic="held-job release may have reached Slurm: " + str(exc))
        raise
    return ledger.transition(key, "RELEASE_INTENT", "SUBMITTED")


def cost_accounting(text, job_id, memory):
    result = ctl.accounting(text, job_id, {"cpus": 1, "wall_seconds": 1200, "memory_MiB": memory})
    result["scope_violations"] = []
    for row in result["rows"]:
        if int(row[3]) > 1200 or ctl.cpu_seconds(row[5]) > 1200:
            result["scope_violations"].append({"job_row": row[0], "reason": "whole COST_ONLY wall/aggregate CPU cap exceeded"})
    if result["scope_violations"]:
        result["complete"] = False
    return result


def cancel_held(key, config_path):
    """Explicit cancellation only; retain the spent claim until terminal collection."""
    ledger = Ledger()
    claim = ledger.snapshot()["claims"][key]
    c = ctl.config(config_path)
    if (claim["state"] not in {"HELD", "AUTHORITY_INTENT", "AUTHORIZED"}
            or r.identity(c) != claim["config_sha256"] or not claim.get("job_id")):
        raise GateError("known held cost job and original site configuration required")
    pinned_claim_release(claim)
    ledger.transition(key, claim["state"], "AMBIGUOUS", diagnostic="explicit held-job cancellation requested; terminal accounting still required")
    ctl.remote(c, ["scancel", claim["job_id"]])
    return ledger.snapshot()["claims"][key]


def status(key, config_path, receipt_path):
    ledger = Ledger()
    claim = ledger.snapshot()["claims"][key]
    c = ctl.config(config_path)
    if r.identity(c) != claim["config_sha256"]:
        raise GateError("cost configuration differs")
    release = pinned_claim_release(claim)
    claim = ledger.poll(key)
    all_queue = ctl.remote(c, ["squeue", "-h", "-u", c["user"], "-o", "%i|%T|%R"])
    queue = "\n".join(line for line in all_queue.splitlines() if line.split("|", 1)[0].strip() == claim["job_id"])
    accounting = ctl.remote(c, ["sacct", "-nP", "--units=K", "-j", claim["job_id"],
                                "--format=JobID,State%30,ExitCode,ElapsedRaw,AllocCPUS,TotalCPU,MaxRSS,NodeList"])
    parsed = cost_accounting(accounting, claim["job_id"], release["memory_mib"])
    receipt = {"schema": SCHEMA, "task_key": key, "job_id": claim["job_id"], "release_sha256": claim["release_sha256"],
               "observed_epoch": time.time(), "squeue": queue, "own_queue": all_queue, "sacct": accounting,
               "scope_violations": parsed["scope_violations"],
               "terminal": not queue.strip() and parsed["terminal"], "complete": not queue.strip() and parsed["complete"]}
    new_write(receipt_path, receipt)
    return receipt


def validate_results(outputs, claim, release):
    outputs = ctl.safe_tree(outputs)
    seal = r.read(outputs / "worker_evidence.json")
    if (seal.get("schema") != SCHEMA or seal.get("task_key") != claim["task_key"]
            or seal.get("release_sha256") != claim["release_sha256"] or seal.get("job_id") != claim["job_id"]
            or seal.get("authority_sha256") != claim["authority_sha256"] or seal.get("full_prefix_admitted") is not False):
        raise GateError("cost output provenance differs")
    observed = {str(path.relative_to(outputs)) for path in outputs.rglob("*") if path.is_file() and path != outputs / "worker_evidence.json"}
    if observed != set(seal["files"]):
        raise GateError("cost outputs are partial or unsealed")
    for name, sha in seal["files"].items():
        if Path(name).is_absolute() or ".." in Path(name).parts or r.digest(outputs / name) != sha:
            raise GateError("cost output hash differs")
    if seal.get("application_passed") is not True:
        return False
    relative = Path("BENCHMARK_TEST") / release["study"] / claim["task"]["preparation_sha256"][:16] / claim["scope_id"]
    result = r.read(outputs / relative / "timings.json")
    inner = r.read(outputs / relative / "completed_evidence.json")
    execution = result.get("execution", {})
    plan = r.read(Path(claim["release_path"]) / "plan.json")
    if (result.get("status") != "COMPLETE_COST_ONLY_18_CALL_PANEL_NO_SELECTION_NO_ADMISSION"
            or inner.get("status") != "COMPLETE_COST_PANEL_ONLY_NO_SCIENCE_ADMISSION"
            or execution != inner.get("execution") or execution.get("plan_sha256") != claim["task"]["plan_sha256"]
            or execution.get("authority_sha256") != claim["authority_sha256"]
            or execution.get("scope_id") != claim["scope_id"] or execution.get("allocation", {}).get("job_id") != claim["job_id"]
            or execution.get("namespace") != "BENCHMARK_TEST" or execution.get("full_prefix_admitted") is not False
            or execution.get("scientific_exclusion_key") != claim["task"]["scientific_exclusion_key"]
            or execution.get("allocation", {}).get("cpus_per_task") != 1 or len(execution.get("allocation", {}).get("affinity", [])) != 1
            or result.get("arithmetic_calls") != 18 or result.get("timed_prediction_calls") != 16
            or result.get("untimed_control_replay_prediction_calls") != 2 or len(result.get("rows", [])) != 16
            or result.get("no_new_candidate_AQL_computed") is not True or result.get("no_scientific_selection") is not True
            or result.get("full_prefix_admitted") is not False or result.get("prefix_pricing_performed") is not False
            or result.get("automatic_retry") is not False or result.get("new_model_fits") != 0 or result.get("official_origins") != 0
            or any(type(result.get(key)) not in (int, float) or not math.isfinite(result[key]) or not 0 <= result[key] <= 1200
                   for key in ("process_CPU_seconds", "aggregate_CPU_seconds", "elapsed_seconds"))):
        raise GateError("incomplete or scientifically expanded cost panel")
    expected_rows = [(call["mode"], call["package_id"], call["repetition"], call["p"])
                     for call in plan["schedule"] if call["kind"] == "timed_prediction"]
    actual_rows = [(row.get("mode"), row.get("package_id"), row.get("repetition"), row.get("p")) for row in result["rows"]]
    expected_calls = [{key: call[key] for key in ("sequence", "kind", "task")} for call in plan["schedule"]]
    if (actual_rows != expected_rows or result.get("calls") != expected_calls
            or result.get("numerical_preflight", {}).get("parents") != p.COUNTS[release["study"]]["parents"]
            or any(row.get("split") != 3 or row.get("clock_offset_steps") != 0 or row.get("origin_count") != 8 for row in result["rows"])):
        raise GateError("cost result schedule or all-parent preflight differs")
    inner_members = {str(path.relative_to(outputs / relative)) for path in (outputs / relative).rglob("*")
                     if path.is_file() and path != outputs / relative / "completed_evidence.json"}
    if inner_members != set(inner["artifacts"]):
        raise GateError("partial inner benchmark output seal")
    timed_calls = [call for call in plan["schedule"] if call["kind"] == "timed_prediction"]
    expected_packets = [call["serialization"]["retained_packet"] for call in timed_calls]
    if (len(set(expected_packets)) != 16 or any(Path(name).name != name or not name.endswith(".npz") for name in expected_packets)
            or set(inner["artifacts"]) != {"execution_identity.json", "timings.json", *expected_packets}
            or r.read(outputs / relative / "execution_identity.json") != execution):
        raise GateError("complete retained prediction packet/identity membership required")
    for name, sha in inner["artifacts"].items():
        if Path(name).is_absolute() or ".." in Path(name).parts or r.digest(outputs / relative / name) != sha:
            raise GateError("inner benchmark output seal differs")
    for row, packet_name in zip(result["rows"], expected_packets):
        if not row.get("numerical_threadpools") or any(pool.get("num_threads") != 1 for pool in row["numerical_threadpools"]):
            raise GateError("actual benchmark numerical pool count differs")
        packet_path = outputs / relative / packet_name
        if (row.get("retained_prediction_packet") != packet_name
                or row.get("retained_prediction_sha256") != inner["artifacts"].get(packet_name)
                or type(row.get("compressed_bytes")) is not int or row["compressed_bytes"] <= 0
                or packet_path.stat().st_size != row["compressed_bytes"]):
            raise GateError("retained prediction packet row/hash/bytes mismatch")
    return True


def collect(key, config_path, receipt_path, incoming, destination):
    ledger = Ledger()
    claim = ledger.snapshot()["claims"][key]
    c = ctl.config(config_path)
    if claim["state"] not in {"SUBMITTED", "AMBIGUOUS"} or r.identity(c) != claim["config_sha256"]:
        raise GateError("known cost claim/configuration required")
    release = pinned_claim_release(claim)
    receipt = r.read(receipt_path)
    if any(receipt.get(name) != claim[name] for name in ("task_key", "job_id", "release_sha256")):
        raise GateError("cost accounting identity differs")
    parsed = cost_accounting(receipt["sacct"], claim["job_id"], release["memory_mib"])
    if receipt["squeue"].strip() or not parsed["terminal"]:
        raise GateError("unknown/incomplete cost job retains its claim")
    incoming, destination = ctl.safe_tree(incoming), r.no_links(destination)
    if incoming.exists() or destination.exists():
        raise FileExistsError("fresh incoming and atomic create-only publication required")
    incoming.mkdir(parents=True)
    for name in ("outputs", "logs"):
        (incoming / name).mkdir()
        ctl.run(["rsync", "-rlt", "--partial", "--delay-updates", "--no-links", "-e", shlex.join(ctl.ssh(c)[:-1]),
                 c["user"] + "@" + c["host"] + ":" + claim["remote_root"] + "/" + name + "/",
                 str(incoming / name) + "/"], timeout=240)
    ctl.safe_tree(incoming)
    new_write(incoming / "accounting.json", receipt)
    shutil.copyfile(Path(claim["release_path"]) / "release.json", incoming / "release.json")
    accepted = parsed["complete"] and validate_results(incoming / "outputs", claim, release)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.parent / (".cost-incoming-" + uuid.uuid4().hex)
    try:
        shutil.copytree(incoming, temporary)
        ctl.safe_tree(temporary)
        if parsed["complete"]:
            validate_results(temporary / "outputs", claim, release)
        with r.lock(destination.parent / "cost-publication.lock"):
            if destination.exists():
                raise FileExistsError("cost publication already exists")
            temporary.rename(destination)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return ledger.transition(key, claim["state"], "COLLECTED_COST_ONLY" if accepted else "FAILED_RECONCILED",
                             application_accepted=accepted, publication=str(destination), full_prefix_admitted=False)


def cost_worker(root, expected_sha):
    root = Path(root).absolute()
    if r.digest(root / "release.json") != expected_sha:
        raise GateError("admitted cost release hash differs")
    release = verify_release(root)
    allocation = require_compute()
    packet = r.read(root / "authorization/packet.json")
    authority_path = root / "authorization/authority.json"
    if (packet.get("release_sha256") != expected_sha or packet.get("request_sha256") != release["request_sha256"]
            or r.digest(authority_path) != packet.get("authority_sha256")
            or r.digest(root / "authorization/cross-server-claim.json") != packet.get("cross_claim_sha256")):
        raise GateError("cost authority packet differs")
    authority = r.read(authority_path)
    if authority.get("executed_sources") != executed_sources() or authority.get("issuer") != OWNER or authority.get("controller") != OWNER:
        raise GateError("entire executed Python closure or canonical issuer differs")
    if (authority.get("reference_numerical_environment") != REFERENCE_NUMERICAL_ENV
            or any(os.environ.get(key) != value for key, value in REFERENCE_NUMERICAL_ENV.items())):
        raise GateError("accepted historical numerical profile must propagate before worker imports")
    plan = r.read(root / "plan.json")
    b.validate_authority(authority, plan, release["plan_sha256"], allocation)
    outputs = root / "outputs"
    if set(outputs.iterdir()):
        raise FileExistsError("cost worker does not retry existing output")
    relative = Path("BENCHMARK_TEST") / release["study"] / plan["canonical_preparation"]["sha256"][:16] / authority["scope_id"]
    env = dict(os.environ, **THREAD_ENV, **REFERENCE_NUMERICAL_ENV, PYTHONNOUSERSITE="1", PYTHONDONTWRITEBYTECODE="1", PYTHONPATH=str(root / "code"))
    passed, error = False, None
    try:
        remaining = min(1200, authority["expires_epoch"] - time.time()) - 5
        if remaining <= 0:
            raise GateError("cost authority already exhausted")
        subprocess.run([release["runtime_python"], "-B", "-m", "pricefm_hb.benchmark", "--plan", str(root / "plan.json"),
                        "--authority", str(authority_path), "--authority-sha256", packet["authority_sha256"],
                        "--stage-root", str(root / "stage"), "--output-dir", str(outputs / relative)],
                       env=env, check=True, timeout=remaining)
        passed = True
    except Exception as exc:
        error = {"type": type(exc).__name__, "message": str(exc)}
        new_write(outputs / "worker-failure.json", error)
    ctl.safe_tree(outputs)
    files = {str(path.relative_to(outputs)): r.digest(path) for path in sorted(outputs.rglob("*")) if path.is_file()}
    new_write(outputs / "worker_evidence.json", {"schema": SCHEMA, "task_key": packet["task_key"],
              "release_sha256": expected_sha, "job_id": allocation["job_id"], "authority_sha256": packet["authority_sha256"],
              "allocation": allocation, "application_passed": passed, "error": error, "files": files, "full_prefix_admitted": False})
    if not passed:
        raise RuntimeError("cost worker failed; no admission or automatic retry")
    return {"status": "COMPLETE_COST_ONLY_PENDING_ACCOUNTING_AND_COLLECTION"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    q = sub.add_parser("prepare-launch")
    for key in ("plan", "request", "config", "destination"):
        q.add_argument("--" + key, required=True)
    q = sub.add_parser("submit-held")
    q.add_argument("--release", required=True); q.add_argument("--config", required=True)
    for name in ("issue-authority", "release-job", "cancel-held", "status", "collect"):
        q = sub.add_parser(name)
        q.add_argument("--key", required=True); q.add_argument("--config", required=True)
        if name in ("status", "collect"):
            q.add_argument("--receipt", required=True)
        if name == "collect":
            q.add_argument("--incoming", required=True); q.add_argument("--destination", required=True)
    q = sub.add_parser("cost-worker")
    q.add_argument("--release", required=True); q.add_argument("--release-sha256", required=True)
    a = parser.parse_args(argv)
    if a.action == "prepare-launch": result = prepare_launch(a.plan, a.request, a.config, a.destination)
    elif a.action == "submit-held": result = submit_held(a.release, a.config)
    elif a.action == "issue-authority": result = issue_authority(a.key, a.config)
    elif a.action == "release-job": result = release_job(a.key, a.config)
    elif a.action == "cancel-held": result = cancel_held(a.key, a.config)
    elif a.action == "status": result = status(a.key, a.config, a.receipt)
    elif a.action == "collect": result = collect(a.key, a.config, a.receipt, a.incoming, a.destination)
    else: result = cost_worker(a.release, a.release_sha256)
    print(json.dumps(result, sort_keys=True, allow_nan=False))


if __name__ == "__main__":
    main()
