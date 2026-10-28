"""Finite read-only R157 request refresh and measured eligible-node selection.

No claim, authority or job is created. Exact canonical self claims may be
excluded at post-READY activation; unknown or ambiguous ownership still blocks.
"""
from __future__ import annotations
import argparse
import inspect
import json
import math
import os
from pathlib import Path
import re
import resource
import signal
import subprocess
import time
from . import activation as a, control as ctl, cost_control as cost
from . import handoff, policy, readiness as rd, registry as r

RESULT_SCHEMA = "r157_readonly_admission_refresh_v1"
LIFECYCLE_SCHEMA = "r157_hb_lifecycle_v1"
CENTRAL = cost.CENTRAL
FINAL = {"COLLECTED", "FAILED_RECONCILED"}
SELF_STATES = {"SUBMITTED", "ACTIVATION_INTENT", "ACTIVATED"}
PREFIX_PURPOSES = {"CACHED_NORMAL_COMPONENT", "PREFIX_ASSESSMENT"}


class AdmissionError(ValueError):
    pass


class Budget(rd.Budget):
    """Delta accounting also works inside the long-lived sole controller."""
    def __init__(self):
        super().__init__()
        self.cpu0 = self.local_cpu()

    @staticmethod
    def local_cpu():
        return sum(resource.getrusage(resource.RUSAGE_SELF)[:2]) + sum(resource.getrusage(resource.RUSAGE_CHILDREN)[:2])

    def used_cpu(self):
        return self.local_cpu() - self.cpu0 + self.remote_cpu


def _state_snapshot():
    path = CENTRAL / "activation_registry.json"
    if not path.exists():
        return {"schema": LIFECYCLE_SCHEMA, "owner": policy.OWNER, "claims": {}, "spent_tests": []}
    lock = CENTRAL / "activation_registry.lock"
    if not lock.is_file():
        raise AdmissionError("canonical lifecycle ledger lacks its existing lock")
    with r.lock(lock):
        state = rd.metadata(path)
    if (state.get("schema") != LIFECYCLE_SCHEMA or state.get("owner") != policy.OWNER
            or not isinstance(state.get("claims"), dict)):
        raise AdmissionError("canonical lifecycle ledger identity differs")
    return state


def _release(claim):
    root = r.no_links(claim["release_path"])
    path = root / "release.json"
    if r.digest(path) != claim.get("release_sha256"):
        raise AdmissionError("canonical claimed release changed")
    value = rd.metadata(path)
    if (value.get("task_key") != claim.get("task_key")
            or value.get("plan_sha256") != claim.get("task", {}).get("plan_sha256")
            or value.get("remote_root") != claim.get("remote_root")
            or value.get("resources") != claim.get("resources")):
        raise AdmissionError("canonical claim/release identity differs")
    return value


def canonical_claims(packet, expected_plan_sha, exclusion_key, self_claim=None):
    """Return a fresh durable snapshot; supplied claim values are never authority."""
    state = _state_snapshot()
    active = [v for v in state["claims"].values() if v.get("state") not in FINAL]
    if len(active) > policy.hb_concurrency(packet):
        raise AdmissionError("active canonical claims exceed explicit HB policy")
    own = None
    if self_claim is not None:
        key = self_claim.get("task_key")
        own = state["claims"].get(key)
        if (own != self_claim or own.get("state") not in SELF_STATES
                or own.get("task", {}).get("plan_sha256") != expected_plan_sha
                or own["task"].get("scientific_exclusion_key") != exclusion_key
                or not re.fullmatch(r"[1-9][0-9]*", str(own.get("job_id", "")))):
            raise AdmissionError("self exclusion requires exact current canonical submitted claim")
        _release(own)
    peers = []
    for claim in active:
        if own is not None and claim["task_key"] == own["task_key"]:
            continue
        if (claim.get("state") == "AMBIGUOUS" or claim.get("task", {}).get("purpose") not in PREFIX_PURPOSES
                or claim["task"].get("scientific_exclusion_key") == exclusion_key
                or not re.fullmatch(r"[1-9][0-9]*", str(claim.get("job_id", "")))):
            raise AdmissionError("unknown, duplicate or non-prefix HB work remains active")
        _release(claim)
        peers.append(claim)
    return state, own, peers


def hb_snapshot(spec, site, budget):
    """One bounded metadata SSH captures all eligible nodes and exact self job."""
    # Serialize the unchanged stdlib own-process/registry reader, then append
    # scheduler metadata queries. No installed app/environment is imported here.
    script = "import json,subprocess,os,resource\n" + inspect.getsource(rd.metadata_snapshot)
    script += "\nspec=" + repr(dict(spec, slurm=False, remote_observer=True)) + "\n"
    script += "result=metadata_snapshot(spec)\nresult['slurm']={}\n"
    commands = {"queue": ["squeue", "-h", "-u", "jaguir26", "-o", "%i|%j|%T|%R"],
                "nodes": ["scontrol", "show", "nodes", "-o"],
                "partition": ["scontrol", "show", "partition", "128x24", "-o"]}
    if spec.get("self_job_id"):
        commands["self_job"] = ["scontrol", "show", "job", spec["self_job_id"], "-o"]
    script += "commands=" + repr(commands) + "\n"
    script += "for key,argv in commands.items():\n value=subprocess.run(argv,text=True,capture_output=True,timeout=8)\n if value.returncode:raise ValueError('scheduler metadata query failed:'+value.stderr[-400:])\n result['slurm'][key]=value.stdout\n"
    script += "s=os.statvfs(spec['disk_path']);result['free_disk_bytes']=s.f_bavail*s.f_frsize\n"
    script += "v=resource.getrusage(resource.RUSAGE_SELF);c=resource.getrusage(resource.RUSAGE_CHILDREN);result['CPU_seconds']=v.ru_utime+v.ru_stime+c.ru_utime+c.ru_stime\nprint(json.dumps(result))\n"
    value = json.loads(rd.run(ctl.ssh(site) + ["timeout 38s /usr/bin/python3 -B -"], budget,
                             stdin=script, maximum=42))
    if (value.get("host") not in {"hb.ucsc.edu", "rit-prd-clusterlogin-1.ucsc.edu", "rit-prd-clusterlogin-2.ucsc.edu"}
            or not cost.fresh(value, time.time()) or not policy.finite_number(value.get("CPU_seconds"))
            or value["CPU_seconds"] < 0):
        raise AdmissionError("HB metadata identity/freshness/accounting not established")
    budget.remote_cpu += value["CPU_seconds"]
    budget.check()
    return value


def _memory_mib(value):
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([KMGT]?)", str(value))
    if not match:
        raise AdmissionError("unknown allocated memory unit")
    factors = {"": 1, "K": 1 / 1024, "M": 1, "G": 1024, "T": 1024**2}
    number = float(match[1]) * factors[match[2]]
    if not number.is_integer():
        raise AdmissionError("nonintegral allocated memory MiB")
    return int(number)


def select_node(snapshot, memory_mib, wall_seconds, self_claim=None, candidates=None, preferred=None):
    partition = rd.fields(snapshot["slurm"]["partition"])
    if partition.get("State") != "UP" or rd.duration(partition["MaxTime"]) < wall_seconds + 60:
        raise AdmissionError("partition cannot fit the complete allocation and reserve")
    bound = _release(self_claim) if self_claim is not None else None
    if bound:
        job = rd.fields(snapshot["slurm"].get("self_job", ""))
        allocated = dict(v.split("=", 1) for v in job.get("AllocTRES", "").split(",") if "=" in v)
        if (job.get("JobId") != self_claim["job_id"] or job.get("JobState") != "RUNNING"
                or job.get("NodeList") != bound.get("node") or job.get("NumCPUs") != "1"
                or _memory_mib(allocated.get("mem", job.get("MinMemoryNode", ""))) != memory_mib
                or self_claim["resources"].get("memory_MiB") != memory_mib
                or self_claim["resources"].get("cpus") != 1):
            raise AdmissionError("self allocation resources/node do not match canonical claim")
    eligible = []
    for line in snapshot["slurm"]["nodes"].splitlines():
        node = rd.fields(line)
        if (not re.fullmatch(r"node-[0-9]+", node.get("NodeName", ""))
                or "128x24" not in node.get("Partitions", "").split(",")
                or any(x in node.get("State", "") for x in ("DOWN", "DRAIN", "FAIL", "MAINT"))):
            continue
        name = node["NodeName"]
        if bound and name != bound["node"] or candidates is not None and name not in candidates:
            continue
        add_cpu = 1 if bound else 0
        add_mem = memory_mib if bound else 0
        cpus = int(node.get("CPUEfctv", node["CPUTot"])) - int(node["CPUAlloc"]) + add_cpu
        memory = min(int(node["FreeMem"]), int(node["RealMemory"]) - int(node["AllocMem"]) + add_mem)
        if cpus >= 1 and memory >= memory_mib:
            eligible.append({"node": name, "available_cpus": cpus, "available_memory_mib": memory,
                             "self_allocation_added_back": bool(bound), "node_fields": node})
    if not eligible:
        raise AdmissionError("no measured eligible node fits the exact request")
    # Stable compact placement; no attempt to turn raw idle CPUs into authority.
    return min(eligible, key=lambda row: (0 if row["node"] == preferred else 1,
                                          -min(row["available_cpus"], row["available_memory_mib"] // memory_mib), row["node"]))


def _closure(config):
    value = policy.pinned(config["known_legacy_closure_audit"])
    if value.get("status") != "PASS_CLOSED_CACHED_SCOPE_PRESERVED" or value.get("errors"):
        raise AdmissionError("successful exact legacy closure audit required")
    hashes = {}
    def walk(item):
        if isinstance(item, dict):
            for key, value in item.items():
                if key.startswith("/") and isinstance(value, str) and cost.SHA.fullmatch(value):
                    hashes[key] = value
                walk(value)
        elif isinstance(item, list):
            for value in item:
                walk(value)
    walk(value)
    return value, hashes


def _overlap(plan, study, snapshots, closure, hashes, own, peers, packet, purpose="COST_ONLY"):
    unknown = []
    absences = []
    legacy_self = own.get("legacy_cost_key") if own else None
    parent_key = plan["claim"]["scientific_exclusion_key"]
    for host, snap in snapshots.items():
        unknown.extend(host + ":pid" + str(v["pid"]) for v in snap["matching_processes"])
        unknown.extend(host + ":unreadable_pid" + str(v["pid"]) for v in snap["unreadable_own_processes"])
        for item in snap["registries"]:
            if item.get("output_descriptor_only"):
                if not item.get("present"):
                    absences.append(dict(rd.never_admitted_absence(study, item["path"], plan, snapshots, closure, hashes), host=host))
                if any(name.startswith(("benchmark", "tasks_done", "components", "claim")) for name in item.get("entries", [])):
                    unknown.append(host + ":unreviewed_legacy_output:" + item["path"])
                continue
            if item["path"] in hashes and item.get("sha256") != hashes[item["path"]]:
                raise AdmissionError("legacy registry differs from original closed-scope audit")
            if item["path"] == str(CENTRAL / "cost_only_registry.json"):
                if not item.get("present") and not item.get("error"):
                    continue
                state = item.get("value", {})
                if state.get("schema") != cost.SCHEMA or state.get("owner") != policy.OWNER:
                    raise AdmissionError("legacy cost ledger identity differs")
                if study in state.get("spent_regions", {}) and state["spent_regions"][study] != legacy_self:
                    # A collected cost panel is a prerequisite for a prefix, not
                    # a reason to reject the later prefix's distinct scope.
                    key = state["spent_regions"][study]
                    old = state.get("claims", {}).get(key, {})
                    if purpose == "COST_ONLY" or old.get("state") not in cost.FINAL:
                        unknown.append("spent_or_unresolved_regional_cost:" + study)
                for key, claim in state.get("claims", {}).items():
                    if key == legacy_self:
                        if (claim.get("task", {}).get("study") != study
                                or claim["task"].get("plan_sha256") != own["task"]["plan_sha256"]
                                or claim["task"].get("scientific_exclusion_key") != parent_key):
                            raise AdmissionError("legacy self cost key is not the same exact scientific claim")
                    elif claim.get("state") not in cost.FINAL:
                        unknown.append("legacy_cost_active:" + key)
                continue
            unknown.extend(host + ":" + text for text in rd.registry_overlaps(item, parent_key))
    allowed = {v["job_id"] for v in peers}
    if own:
        allowed.add(own["job_id"])
    seen = set()
    for line in snapshots["hb.ucsc.edu"]["slurm"]["queue"].splitlines():
        job = line.split("|", 1)[0]
        if job not in allowed:
            unknown.append("unknown_HB_job:" + job)
        seen.add(job)
    if own and own["job_id"] not in seen:
        raise AdmissionError("known self job is absent from actual own queue")
    if len(allowed) > policy.hb_concurrency(packet):
        raise AdmissionError("own queue exceeds source-bound resource matrix")
    if unknown:
        raise AdmissionError("overlap or unknown ownership: " + json.dumps(unknown))
    return absences


def _prefix_context(execution_plan_pin, cost_plan, key, purpose, self_claim, policy_pin):
    """Read only the existing admitted scientific master/current-stage ledger."""
    from . import prefix, prefix_control as pc
    plan = policy.pinned(execution_plan_pin)
    prep, _ = prefix.validate_plan(plan)
    if plan["cost_plan"] != cost_plan:
        raise AdmissionError("prefix execution plan has a different original cost contract")
    path, lock = CENTRAL / "prefix_registry.json", CENTRAL / "prefix_registry.lock"
    if not path.is_file() or not lock.is_file():
        raise AdmissionError("canonical admitted prefix registry absent")
    with r.lock(lock):
        state = rd.metadata(path)
    if (state.get("schema") != pc.SCHEMA or state.get("owner") != policy.OWNER
            or state.get("policy") != policy_pin):
        raise AdmissionError("prefix study/policy identity differs")
    entry = state.get("studies", {}).get(plan["study"], {})
    if entry.get("plan") != execution_plan_pin:
        raise AdmissionError("execution plan is not the admitted scientific study")
    pc.validate_master(policy.pinned(entry["master"]), plan)
    phase = prefix.manifest_state(prep, plan["pricing"], entry["results"], entry["decisions"])
    parent_key = cost_plan["claim"]["scientific_exclusion_key"]
    if purpose == "PREFIX_ASSESSMENT":
        if key != parent_key + "|ASSESSMENT" or phase.get("assessment_ready") is not True:
            raise AdmissionError("complete scientific predecessor set required before assessment")
        wall = a.PURPOSES[purpose]
    else:
        allowed = {parent_key + "|" + name: name for name in phase["pending"] if name not in phase["unfunded"]}
        if key not in allowed:
            raise AdmissionError("component is outside the current fully funded scientific stage")
        name = allowed[key]
        if self_claim is None and any(c.get("task") == name and c.get("state") not in pc.FINAL for c in entry["claims"].values()):
            raise AdmissionError("component already has an active scientific owner")
        wall = math.ceil(plan["pricing"]["task_estimates"][name]["estimated_wall_seconds"])
        if not 1 <= wall <= a.PURPOSES[purpose]:
            raise AdmissionError("entire component cannot fit original dispatch ceiling")
    return plan, wall


def refresh_request(plan_path, config_path, policy_pin, output, *, self_claim=None,
                    purpose="COST_ONLY", owner_receipt_pin=None,
                    execution_plan_pin=None, execution_plan_sha256=None,
                    scientific_exclusion_key=None):
    policy.owner()
    if os.sched_getaffinity(0) != {31} or purpose not in a.PURPOSES:
        raise AdmissionError("known purpose and administrativeCPU31 required")
    output = r.no_links(output)
    if not output.is_absolute() or output.exists():
        raise FileExistsError("new absolute proof directory required")
    output.mkdir(parents=True)
    budget = Budget()
    prior_alarm = signal.getsignal(signal.SIGALRM)
    def expired(*args):
        raise AdmissionError("60wall admission observer deadline reached")
    signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, 60)
    result = {"schema": RESULT_SCHEMA, "status": "BLOCKED", "observed_epoch": time.time(),
              "new_fits": 0, "new_forecasts": 0, "array_loads": 0, "jobs_submitted": 0,
              "claims_created": 0, "authorities_created": 0}
    try:
        config = rd.metadata(config_path) if not isinstance(config_path, dict) else config_path
        if config.get("schema") not in {rd.SCHEMA, "r157_readiness_operator_v1"}:
            raise AdmissionError("unknown operator configuration")
        plan = cost.load_plan(plan_path)
        study = plan["study"]
        plan_pin = policy.pin(plan_path)
        packet = policy.pinned(policy_pin)
        policy.validate_policy(packet)
        site = ctl.config(config["site_config"])
        request = {"schema": a.REQUEST_SCHEMA, "purpose": purpose, "plan": plan_pin,
                   "study": "TEST" if purpose == "CONTROL_TEST" else study,
                   "resource_study": study, "policy_pin": policy_pin,
                   "full_prefix_admitted": False, "automatic_retry": False}
        if 'control_cpu_scope' in config:
            request['control_cpu_scope']=config['control_cpu_scope']
        if purpose=='CONTROL_TEST' and 'control_test_requalification' in config:
            request['control_test_requalification']=config['control_test_requalification']
        request.update(rd.qualification(config["runtime_publication"], "runtime"))
        request.update(rd.qualification(config["parity_publication"], "parity"))
        parity_root = r.no_links(config["parity_publication"]) / "outputs"
        request["parity_seal"] = policy.pin(parity_root / "TEST/parity/completed_evidence.json")
        request["parity_runtime_result"] = policy.pin(parity_root / "environment-runtime.json")
        runtime = policy.pinned(request["runtime_result"])
        parity = policy.pinned(request["parity_result"])
        request["runtime_python"] = runtime["executable"]
        request["environment_bundle"] = str(Path(runtime["executable"]).parents[3] / "env")
        request["accepted_parity_fixture_manifest_sha256"] = parity["execution"]["fixture_manifest_sha256"]
        request["adapter_review"] = config["adapter_reviews"][study]
        policy.pinned(request["adapter_review"])
        a.validate_qualification(request, reader=policy.pinned)
        actual_plan_sha = plan_pin["sha256"]
        wall = a.PURPOSES[purpose]
        key = plan["claim"]["scientific_exclusion_key"]
        if purpose == "CONTROL_TEST":
            key = "R157_CONTROL_TEST|" + request["accepted_parity_fixture_manifest_sha256"]
        elif purpose in PREFIX_PURPOSES:
            if execution_plan_pin is None:
                raise AdmissionError("prefix request requires the exact reviewed execution-plan pin")
            if scientific_exclusion_key is None and self_claim is not None:
                scientific_exclusion_key = self_claim.get("task", {}).get("scientific_exclusion_key")
            _, wall = _prefix_context(execution_plan_pin, plan, scientific_exclusion_key,
                                      purpose, self_claim, policy_pin)
            actual_plan_sha = execution_plan_pin["sha256"]
            key = scientific_exclusion_key
            request["execution_plan"] = execution_plan_pin
            request["execution_plan_pin"] = execution_plan_pin
        if execution_plan_sha256 is not None and execution_plan_sha256 != actual_plan_sha:
            raise AdmissionError("execution plan SHA differs from actual reviewed bytes")
        request["execution_plan_sha256"] = actual_plan_sha
        request["scientific_exclusion_key"] = key
        if key in config.get('control_operation_prices',{}):
            request['control_operation_price']=config['control_operation_prices'][key]
        state, own, peers = canonical_claims(packet, actual_plan_sha, key, self_claim)
        if purpose not in PREFIX_PURPOSES and peers:
            raise AdmissionError("test and cost stages require all other own HB work drained")
        if own and own["policy_pin"] != policy_pin:
            raise AdmissionError("self claim is bound to a different resource packet")
        raw = json.loads(rd.run(rd.EE_COMMAND, budget, maximum=8))
        raw_pin = rd.save(output, "EE_source529.json", raw)
        closed = handoff.build_handoff_receipt(raw_pin, packet["historical_EE_release"],
                    config["delivered_EE_report"], policy_pin, owner_receipt_pin)
        request["handoff_receipt"] = rd.save(output, "EE_handoff.json", closed)
        legacy = config.get("legacy_registries", [])
        if not legacy:
            raise AdmissionError("explicit known legacy registry locations required")
        closure, hashes = _closure(config)
        snapshots = {}
        for host in (policy.OWNER, "jerez.be.ucsc.edu", "hb.ucsc.edu"):
            registries = [entry for entry in legacy if entry["host"] == host]
            if host == policy.OWNER:
                registries += [{"path": str(CENTRAL / "cost_only_registry.json")}]
            location = config.get("legacy_outputs", {}).get(study)
            if isinstance(location, dict):
                location = location.get(host)
            spec = {"exclusion_key": key, "registries": registries,
                    "legacy_outputs": [location] if location and host != "hb.ucsc.edu" else [],
                    "slurm": False, "disk_path": site["remote_root"]}
            if host == "hb.ucsc.edu":
                spec["self_job_id"] = own["job_id"] if own else None
                snapshot = hb_snapshot(spec, site, budget)
            else:
                snapshot = rd.observe(host, spec, site, budget)
            snapshots[host] = snapshot
            rd.save(output, host.split(".")[0] + "_observation.json", snapshot)
        absences = _overlap(plan, study, snapshots, closure, hashes, own, peers, packet, purpose)
        request["all_hosts_observation"] = rd.save(output, "all_hosts_observation.json", {
            "schema": "r157_all_hosts_task_observation_v1", "status": "NO_OVERLAP", "controller": policy.OWNER,
            "hosts": sorted(cost.HOSTS), "observed_epoch": min(v["observed_epoch"] for v in snapshots.values()),
            "scientific_exclusion_key": key, "overlapping_scientific_claims": [],
            "self_claim_key": own["task_key"] if own else None,
            "self_claim_sha256": r.identity(own) if own else None,
            "other_known_prefix_claims": [v["task_key"] for v in peers],
            "lifecycle_snapshot_sha256": r.identity(state),
            "canonical_legacy_descriptor_absences": absences,
            "known_legacy_closure_audit": config["known_legacy_closure_audit"],
            "snapshots": {host: policy.pin(output / (host.split(".")[0] + "_observation.json")) for host in snapshots}})
        sizing = policy.pinned(config["sizing_evidence"][study])
        calendar_pin = config["calendar_evidence"][study]
        calendar = policy.pinned(calendar_pin)
        if sizing.get("study") != study or sizing.get("plan_sha256") != plan_pin["sha256"]:
            raise AdmissionError("sizing changed original plan identity")
        if purpose in PREFIX_PURPOSES:
            from . import prefix_control
            prefix_control.validate_calendar_observation(calendar, execution_plan_pin, plan_pin,
                                                         allow_stale=own is not None)
        elif (calendar.get("study") != study or calendar.get("plan_sha256") != plan_pin["sha256"]
                or calendar.get("status") != "PROPOSED_FINITE_COST_WINDOW_NOT_AUTHORITY"
                or calendar.get("authority_issued") is not False or calendar.get("claim_created") is not False
                or not policy.finite_number(calendar.get("expires_epoch"))):
            raise AdmissionError("original finite calendar proposal required")
        if own:
            original_request = rd.metadata(Path(own["release_path"]) / "launch-request.json")
            if original_request.get("calendar_proposal") != calendar_pin:
                raise AdmissionError("claimed calendar cannot be renewed or replaced")
        elif purpose not in PREFIX_PURPOSES and not cost.fresh({"observed_epoch": calendar.get("created_epoch")}, time.time()):
            raise AdmissionError("fresh unclaimed calendar required before reservation")
        if calendar["expires_epoch"] < time.time() + wall + 60:
            raise AdmissionError("whole allocation no longer fits original calendar")
        chosen = select_node(snapshots["hb.ucsc.edu"], sizing["memory_mib"], wall, own,
                             config.get("eligible_node_candidates"), config.get("preferred_node"))
        hb = snapshots["hb.ucsc.edu"]
        if hb["free_disk_bytes"] < 3 * plan["inventory"]["bytes"] + 1024**3:
            raise AdmissionError("insufficient measured staging/output disk")
        request["calendar_proposal"] = calendar_pin
        request["node"] = chosen["node"]
        request["memory_MiB"] = sizing["memory_mib"]
        request["requested_wall_seconds"] = wall
        request["site_admission"] = rd.save(output, "site_admission.json", {
            "schema": "r157_hb_site_admission_v1", "status": "ADMITTED_COST_ONLY_RESOURCES",
            "purpose": purpose, "study": request["study"], "resource_study": study,
            "plan_sha256": plan_pin["sha256"], "execution_plan_sha256": actual_plan_sha,
            "account": site["account"], "partition": site["partition"], "qos": site["qos"],
            "node": chosen["node"], "observed_epoch": hb["observed_epoch"],
            "memory_mib": sizing["memory_mib"], "minimum_required_memory_mib": sizing["minimum_required_memory_mib"],
            "available_memory_mib": chosen["available_memory_mib"], "available_cpus": chosen["available_cpus"],
            "maximum_parent_p": sizing["maximum_parent_p"], "free_disk_bytes": hb["free_disk_bytes"],
            "calendar_expires_epoch": calendar["expires_epoch"],
            "self_allocation_added_back": chosen["self_allocation_added_back"],
            "sizing_evidence": config["sizing_evidence"][study], "observation": policy.pin(output / "hb_observation.json")})
        budget.check()
        request_pin = rd.save(output, "launch-request.json", request)
        result.update(status="READY_FOR_PREPARE_ONLY_NOT_ADMITTED", request=request_pin,
                      study=request["study"], node=chosen["node"], purpose=purpose)
    except (OSError, ValueError, KeyError, TypeError, IndexError, subprocess.SubprocessError) as exc:
        result["reason"] = str(exc)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, prior_alarm)
    result["completed_epoch"] = time.time()
    result["observer_budget"] = budget.receipt()
    rd.save(output, "readiness-result.json", result)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("plan", "config", "policy", "output"):
        parser.add_argument("--" + key, required=True)
    parser.add_argument("--purpose", choices=sorted(a.PURPOSES), default="COST_ONLY")
    parser.add_argument("--owner-receipt")
    parser.add_argument("--execution-plan")
    parser.add_argument("--scientific-exclusion-key")
    args = parser.parse_args(argv)
    result = refresh_request(args.plan, args.config, policy.pin(args.policy), args.output,
                 purpose=args.purpose, owner_receipt_pin=policy.pin(args.owner_receipt) if args.owner_receipt else None,
                 execution_plan_pin=policy.pin(args.execution_plan) if args.execution_plan else None,
                 scientific_exclusion_key=args.scientific_exclusion_key)
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "READY_FOR_PREPARE_ONLY_NOT_ADMITTED" else 2


if __name__ == "__main__":
    raise SystemExit(main())
