"""R176 candidate lane; derived from frozen startup_batch.py.

Original remains unchanged. Candidate supervisor/source closure is explicit.
"""
"""Native SSH/SFTP/Slurm control for two finite, data-free compute proofs.

No Python, R, supervisor or payload interpreter is executed on the login node.
Every network mutation has an exclusive durable intent. Ambiguous submission
retains its claim and never retries. Scientific output is not a supported role.
"""
import argparse
import contextlib
import datetime
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import resource
import shlex
import signal
import subprocess
import sys
import time

from . import startup_helper as h

ROLES = ("COMPUTE_RUNTIME_INVENTORY", "EXACT_R46_STARTUP_METADATA")
NAMES = ("__init__.py", "profile_supervisor.py", "startup_helper.py", "startup_helper_fixture.py",
         "startup_helper_kernel_tests.py", "startup_helper_metadata_fixture.R", "startup_batch.py",
         "startup_batch_worker.py", "startup_batch_kernel.py",
         "startup_stop_candidate.py", "startup_stop_helper.py",
         "startup_batch_stop.py", "startup_batch_stop_worker.py", "startup_batch_stop_kernel.py")
NATIVE = {"mkdir", "chmod", "test", "sha256sum", "sbatch", "squeue", "sacct", "scancel", "rm", "rmdir"}
TERMINAL = {"COMPLETED", "FAILED", "CANCELLED", "TIMEOUT", "OUT_OF_MEMORY", "NODE_FAIL", "PREEMPTED", "BOOT_FAIL"}
ACTION_ENVELOPE = {
    "stage": dict(local_CPU=18, remote_unknown_fee=18, wall=300, maximum_calls=1),
    "submit": dict(local_CPU=4, remote_unknown_fee=4, wall=45, maximum_calls=1),
    "ready": dict(local_CPU=6, remote_unknown_fee=6, wall=330, maximum_calls=1),
    "release": dict(local_CPU=4, remote_unknown_fee=4, wall=180, maximum_calls=1),
    "observe": dict(local_CPU=3, remote_unknown_fee=3, wall=45, maximum_calls=3),
    "collect": dict(local_CPU=6, remote_unknown_fee=6, wall=300, maximum_calls=1),
    "accept": dict(local_CPU=5, remote_unknown_fee=5, wall=180, maximum_calls=1),
    "cancel": dict(local_CPU=4, remote_unknown_fee=4, wall=45, maximum_calls=1),
}
NATIVE_CONTROL_TOTAL = 2 * sum((x["local_CPU"] + x["remote_unknown_fee"]) * x["maximum_calls"]
                             for x in ACTION_ENVELOPE.values()) + 16
assert NATIVE_CONTROL_TOTAL == 240  # canonical local validation8 + final failure/claim tail8


def safe_path(value):
    h.require(type(value) is str and re.fullmatch(r"/[A-Za-z0-9_./-]+", value)
              and ".." not in Path(value).parts, "safe absolute path required")
    return value


def safe_relative(value):
    path = PurePosixPath(value)
    h.require(type(value) is str and re.fullmatch(r"[A-Za-z0-9_./-]+", value) and not path.is_absolute()
              and ".." not in path.parts and path.parts and not ({".ssh", ".git", ".codex"} & set(path.parts)),
              "safe metadata-relative path required")
    return path


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def native_command(argv):
    h.require(argv and argv[0] in NATIVE and all(type(x) is str and "\x00" not in x for x in argv),
              "only native administrative commands may run on login")
    return shlex.join(argv)


def site_config(value):
    site = h.read(value)
    h.require((site["host"], site["user"], site["account"], site["partition"], site["qos"])
              == ("hb.ucsc.edu", "jaguir26", "128x24", "128x24", "normal"), "verified HB association required")
    for name in ("known_hosts_file", "ssh_identity_file"):
        h.require(h.physical(site[name]).is_file(), "configured trust/identity path required")
    return site


def ssh_options(site):
    options = {"BatchMode": "yes", "StrictHostKeyChecking": "yes", "UpdateHostKeys": "no",
        "CheckHostIP": "no", "ControlMaster": "no", "ControlPath": "none", "IdentitiesOnly": "yes",
        "IdentityAgent": "none", "ForwardAgent": "no", "ClearAllForwardings": "yes",
        "PreferredAuthentications": "publickey", "PasswordAuthentication": "no", "KbdInteractiveAuthentication": "no",
        "ConnectTimeout": "10", "ConnectionAttempts": "1", "UserKnownHostsFile": site["known_hosts_file"]}
    return [item for key, value in options.items() for item in ("-o", key + "=" + value)] + ["-i", site["ssh_identity_file"]]


def run_native(site, argv, *, runner=subprocess.run):
    command = ["/usr/bin/ssh", *ssh_options(site), site["user"] + "@" + site["host"], native_command(argv)]
    # Public preexec_fn forces the reviewed fork path. There is no inner kill
    # or timeout: the actual whole-action original guardian owns both.
    result = runner(command, capture_output=True, text=True, preexec_fn=lambda: None)
    h.require(len(result.stdout.encode()) + len(result.stderr.encode()) <= 2 * 1024**2, "bounded native command output required")
    return dict(argv=argv, returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)


def run_sftp(site, commands, batch_path, *, runner=subprocess.run):
    h.require(all("\n" not in x and "\x00" not in x for x in commands), "single-line SFTP requests required")
    with Path(batch_path).open("x") as handle:
        handle.write("\n".join(commands) + "\n"); handle.flush(); os.fsync(handle.fileno())
    result = runner(["/usr/bin/sftp", "-q", "-b", str(batch_path), *ssh_options(site),
                     site["user"] + "@" + site["host"]], capture_output=True, text=True, preexec_fn=lambda: None)
    h.require(len(result.stdout.encode()) + len(result.stderr.encode()) <= 2 * 1024**2, "bounded SFTP output required")
    return dict(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)


def append(root, state, **fields):
    records = sorted(root.glob("record_*.json"))
    value = dict(state=state, epoch=time.time(), previous=h.pin(records[-1]) if records else None, **fields)
    path = root / ("record_%04d.json" % len(records)); h.write_new(path, value)
    return value


def records(root):
    paths = sorted(root.glob("record_*.json")); result = []; previous = None
    for path in paths:
        value = h.read(h.pin(path)); h.require(value["previous"] == previous, "canonical journal chain differs")
        result.append(value); previous = h.pin(path)
    return result


def one_shot(root, name):
    path = root / (name + ".intent.json")
    h.write_new(path, dict(status="INTENT_NOT_SUCCESS", operation=name, epoch=time.time()))
    return path


def action_limits(action):
    if action == "prepare": return dict(local_CPU=4, wall=120)
    if action == "retire_failed": return dict(local_CPU=3, wall=120)
    return ACTION_ENVELOPE[action]


def passing_guard(guard,CPU,wall):
    """Metadata-only healthy original-H envelope; never settles native state."""
    h.require(type(guard.get('returncode')) is int and type(guard.get('command_returncode')) is int
              and guard['returncode']==guard['command_returncode']==0 and guard.get('cap_reason') is None
              and type(guard.get('CPU_limit')) is int and guard['CPU_limit']==CPU
              and type(guard.get('aggregate_CPU_seconds')) in (int,float)
              and math.isfinite(guard['aggregate_CPU_seconds']) and 0<=guard['aggregate_CPU_seconds']<CPU
              and type(guard.get('complete_lifecycle_wall_seconds')) in (int,float)
              and math.isfinite(guard['complete_lifecycle_wall_seconds']) and 0<=guard['complete_lifecycle_wall_seconds']<=wall
              and guard.get('guardian_forced_monitor_stop') is False
              and all(guard.get(k) is True for k in ('all_owned_descendants_reaped','independent_guardian',
                  'kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once')),
              'actual healthy complete original guardian envelope')


def require_outer_context():
    values = dict(line.split(":", 1) for line in Path("/proc/self/status").read_text().splitlines() if ":" in line)
    h.require(os.getpid() == os.getsid(0) == os.getpgrp()
              and values["NoNewPrivs"].strip() == "1" and values["Seccomp"].strip() == "2",
              "each native action requires the actual original outer guardian")


def started_action(registry, role, action):
    index = len(list(registry.glob("control_*.started.json")))
    path = registry / ("control_%04d.started.json" % index)
    h.write_new(path, dict(status="ACTION_STARTED_NOT_SUCCESS", role=role, action=action,
        created_epoch=time.time(), command_pid=os.getpid(), command_birth_ticks=h.process_birth_ticks(),
        source_sha256=digest(Path(__file__).absolute()), limits=action_limits(action)))
    return path


def pending_action(started, value):
    value_start = h.read(h.pin(started))
    path = started.with_name(started.name.replace(".started.json", ".pending.json"))
    h.write_new(path, dict(status="INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS",
        **{key: item for key, item in value_start.items() if key != "status"}, result=value))


def finish_previous(registry, guard_path):
    pending = sorted(x for x in registry.glob("control_*.started.json")
                     if not x.with_name(x.name.replace(".started.json", ".validated.json")).exists()
                     and not x.with_name(x.name.replace(".started.json", ".failed_ack.json")).exists())
    if not pending:
        h.require(guard_path is None, "no pending action matches supplied guard")
        return None
    h.require(len(pending) == 1 and guard_path is not None, "actual prior outer guardian required before another action")
    started = pending[0]; start = h.read(h.pin(started))
    path = started.with_name(started.name.replace(".started.json", ".pending.json"))
    h.require(path.is_file(), "prior action did not complete internal publication; retain failed guard/claim and stop")
    value = h.read(h.pin(path)); guard_pin = h.pin(guard_path); guard = h.read(guard_pin)
    h.require(all(value[key] == item for key, item in start.items() if key != "status")
              and value["source_sha256"] == digest(Path(__file__).absolute()), "pending action source/identity changed")
    limit = value["limits"]
    h.require(type(guard["returncode"]) is type(guard["command_returncode"]) is int
              and guard["returncode"] == guard["command_returncode"] == 0
              and guard.get("cap_reason") is None and type(guard["CPU_limit"]) is int and guard["CPU_limit"] == limit["local_CPU"]
              and type(guard["aggregate_CPU_seconds"]) in (int, float) and math.isfinite(guard["aggregate_CPU_seconds"])
              and 0 <= guard["aggregate_CPU_seconds"] < limit["local_CPU"]
              and type(guard["complete_lifecycle_wall_seconds"]) in (int, float)
              and math.isfinite(guard["complete_lifecycle_wall_seconds"])
              and 0 <= guard["complete_lifecycle_wall_seconds"] <= limit["wall"]
              and guard.get("guardian_forced_monitor_stop") is False
              and all(guard.get(x) is True for x in ("all_owned_descendants_reaped", "independent_guardian", "kernel_escape_filter",
                  "orphan_subreaper", "guardian_included_in_CPU", "inherited_waited_history_included_once"))
              and guard["session_id"] == value["command_pid"] and guard["leader_start_ticks"] == value["command_birth_ticks"]
              and h.strict_json(guard["stdout"]) == value["result"], "actual prior whole-action guard failed or differs")
    h.write_new(started.with_name(started.name.replace(".started.json", ".validated.json")),
                dict(status="ACTUAL_ACTION_GUARD_PASSED", started=h.pin(started), pending=h.pin(path), guard=guard_pin))
    if value["action"] == "accept":
        root = registry / value["role"]; accepted = dict(value["result"], status="ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE",
                                          actual_accept_action_guard=guard_pin)
        h.write_new(root / "ACCEPTED.json", accepted); append(root, "ACCEPTED", accepted=h.pin(root / "ACCEPTED.json"), claim_released=True)
    return dict(status="PRIOR_ACTION_GUARD_VALIDATED", action=value["action"], guard=guard_pin)


def acknowledge_failed_previous(registry, role, guard_path):
    pending = sorted(x for x in registry.glob("control_*.started.json")
                     if not x.with_name(x.name.replace(".started.json", ".validated.json")).exists()
                     and not x.with_name(x.name.replace(".started.json", ".failed_ack.json")).exists())
    h.require(len(pending) == 1, "one failed prior action must be identified")
    started = pending[0]; start = h.read(h.pin(started)); root = registry / role
    h.require(start["role"] == role and start["source_sha256"] == digest(Path(__file__).absolute()),
              "failed recovery must retain exact prior role/source")
    submitted = next(x for x in reversed(records(root)) if x["state"] == "SUBMITTED")
    known = h.read(submitted["job"])
    h.require(submitted["job"]["path"] == str(root / "JOB.json") and known["job_id"] == submitted["job_id"]
              and known["scope_id"] == packet(root)["scope_id"], "exact known canonical job required for cancellation tail")
    gp = h.pin(guard_path); guard = h.read(gp); witness = guard.get("owned_stop_witness", {})
    sid = guard.get("session_id", witness.get("session_id")); birth = guard.get("leader_start_ticks", witness.get("leader_start_ticks"))
    h.require(type(guard["returncode"]) is int and guard["returncode"] != 0
              and guard.get("independent_guardian") is True and guard.get("all_owned_descendants_reaped") is True
              and guard.get("CPU_limit", start["limits"]["local_CPU"]) == start["limits"]["local_CPU"]
              and sid == start["command_pid"] and birth == start["command_birth_ticks"],
              "actual failed/drained prior outer guardian identity required; no success is inferred")
    value = dict(status="FAILED_ACTION_ACKNOWLEDGED_FOR_KNOWN_JOB_CANCELLATION_ONLY", started=h.pin(started),
                 failed_guard=gp, known_job=submitted["job"], no_successor_compute_authority=True, old_fees_retained=True)
    h.write_new(started.with_name(started.name.replace(".started.json", ".failed_ack.json")), value)
    if not (root / "ROLE_FAILED_SPENT.json").exists(): h.write_new(root / "ROLE_FAILED_SPENT.json", value)
    return value


def canonical_identity(config):
    return {key:value for key,value in config.items() if key!='canonical_authority'}


STARTUP_WATCH_PROFILE=dict(maximum_probes=10,interval_seconds=20,deadline_seconds=300,
    probe_local_CPU=3,probe_remote_unknown_fee=3,probe_wall_seconds=45,combined_startup_watch_CPU_ceiling=60)


def validate_startup_watch_budget(config,scope,roles):
    b=h.read(config['startup_watch_budget']);count=len(roles)
    roots=config.get('startup_watch_roots',{})
    h.require(type(roots) is dict and set(roots)==set(roles) and len(set(roots.values()))==count,
              'one distinct canonical startup output root per exact funded role')
    base=h.physical(scope['allowed_metadata_output_root'])
    h.require(all(h.physical(value).is_relative_to(base) and h.physical(value)!=base for value in roots.values()),
              'startup roots stay in private prospective scope')
    h.require(b.get('status')=='PROSPECTIVE_FRESH_NODE_STARTUP_WATCH_BUDGET'
              and b.get('scope')==config['scope'] and b.get('profile')==STARTUP_WATCH_PROFILE
              and all(type(b['profile'][key]) is int for key in STARTUP_WATCH_PROFILE)
              and b.get('roles')==list(roles) and type(b.get('combined_startup_watch_CPU_ceiling')) is int
              and b['combined_startup_watch_CPU_ceiling']==60*count
              and b.get('expires_epoch')==scope['expires_epoch']
              and scope.get('administrative_allocations',{}).get('startup_watch'+str(60*count))==60*count,
              'each fresh role has separately paid local30 and remote30 startup observations')


def validate_failure_tail_budgets(config,scope,roles):
    values=config.get('failure_tail_budgets',{})
    h.require(type(values) is dict and set(values)==set(roles),'distinct prepriced failure budget for every funded role')
    allocations=dict(query_local4=4,query_remote4=4,independent_review4=4,drain_local4=4,drain_remote4=4,preparation4=4,closeout4=4)
    for role,value in values.items():
        b=h.read(value)
        h.require(b.get('schema')=='node_unallocated_failure_budget_v1'
                  and b.get('status')=='PROSPECTIVE_DISTINCT_NODE_UNALLOCATED_FAILURE_TAIL_BUDGET'
                  and b.get('parent_scope')==config['scope'] and b.get('role')==role
                  and b.get('allocations')==allocations and all(type(x) is int for x in b['allocations'].values())
                  and type(b.get('total_administrative_CPU')) is int and b['total_administrative_CPU']==28
                  and all(type(b.get(k)) is int and b[k]==1 for k in ['maximum_query_calls','maximum_drain_calls','maximum_peer_calls'])
                  and b.get('expires_epoch')==scope['expires_epoch'],
                  'complete separate28 tail scope, not original native/H3 credit')


def validate_node_context(config,scope):
    node=config.get('node');route=scope.get('qualification_route_id')
    h.require(type(node) is str and re.fullmatch(r'node-(?:1[5-9]|2[01])',node)
              and scope.get('execution_node')==scope.get('qualification_node')==node
              and type(route) is str and re.fullmatch('[0-9a-f]{32}',route)
              and scope.get('cached_artifact_origin_node')=='node-13',
              'one exact scope-selected available-node route; historical cached origin is not admission')
    jobs=1 if 'role' in config else 2
    h.require(all(type(scope.get(k)) is int and scope[k]==v for k,v in
              dict(maximum_jobs=jobs,max_concurrent_jobs=1,cpus_per_task=1,threads=1,memory_MiB=8192,compute_CPU_reservation=600*jobs).items()),
              'exact integer whole-role jobs/CPU/thread/memory funding')
    return node,route


def load_config(path):
    h.require(os.sched_getaffinity(0) == {31}, "administrative controller must already use CPU31")
    config = h.read(h.pin(path)); h.require(config["schema"] == "pricefm_startup_batch_config_v1", "controller config schema differs")
    scope = h.read(config["scope"])
    validate_node_context(config,scope)
    validate_startup_watch_budget(config,scope,ROLES)
    validate_failure_tail_budgets(config,scope,ROLES)
    h.require(scope["status"] == "PROSPECTIVE_TWO_ROLE_HB_RUNTIME_QUALIFICATION_SCOPE"
              and time.time() < scope["expires_epoch"] and scope["max_concurrent_jobs"] == 1
              and scope["compute_CPU_reservation"] == 1200, "live two-role finite qualification scope required")
    budget = h.read(config["native_control_budget"])
    h.require(budget["status"] == "PROSPECTIVE_TWO_JOB_NATIVE_CONTROL_BUDGET"
              and budget["combined_native_control_CPU_ceiling"] == NATIVE_CONTROL_TOTAL
              and budget["expires_epoch"] == scope["expires_epoch"], "prepriced complete240 native control envelope required")
    h.require(h.physical(config["registry"]).is_relative_to(h.physical(scope["allowed_metadata_output_root"])),
              "canonical registry must stay within new Q output scope")
    auth_pin = config["canonical_authority"]
    h.require(auth_pin["path"] == str(Path(scope["allowed_metadata_output_root"]) / "CANONICAL_STARTUP_BATCH_AUTHORITY.json"),
              "one Q canonical config authority path required across servers")
    auth = h.read(auth_pin)
    h.require(auth["status"] == "ROOT_AUTHORIZED_CANONICAL_STARTUP_BATCH_CONFIG"
              and auth["binding"] == canonical_identity(config) and auth["roles"] == list(ROLES)
              and auth["maximum_jobs"] == 2 and auth["max_concurrent_jobs"] == 1
              and scope["issued_epoch"] <= auth["issued_epoch"] <= time.time() < auth["expires_epoch"] <= scope["expires_epoch"],
              "actual immutable canonical config/namespace authority required")
    safe_path(config["remote_namespace"])
    h.require(config["remote_namespace"].startswith("/mnt/beegfs/home/jaguir26/pricefm_")
              and config["node"] == scope["execution_node"], "new private approved HB namespace/node required")
    h.require(re.fullmatch(r"/mnt/beegfs/home/jaguir26/pricefm_[A-Za-z0-9_/-]+/runtime/venv/bin/python",
                           config["cached_python"]), "previously verified cached compute Python required")
    publication = h.read(config["publication"]); source = h.physical(config["source_dir"])
    hashes = {name: digest(source / name) for name in NAMES}
    h.require(publication["status"] == "PASS_STARTUP_BATCH_SOURCE_PUBLICATION"
              and re.fullmatch("[0-9a-f]{40}", publication["commit"])
              and all(publication["source_files"].get(k) == v for k, v in hashes.items()),
              "actual published source readback required before packet preparation/network")
    review = h.read(config["source_review"])
    h.require(review["status"] == "PASS_REVIEWED_STARTUP_BATCH_SOURCE"
              and all(review["source_files"].get(k) == v for k, v in hashes.items()), "actual independent source review required")
    return config, scope, site_config(config["site"]), hashes


@contextlib.contextmanager
def canonical(config):
    parent = h.physical(config["registry"]); parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(parent / ".controller.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield parent
    finally:
        os.close(descriptor)


def build_R_startup_plan(ready,packet,spec,scope,review,manifest,now,scope_pin,expected_sources):
    h.require(now+180<scope["expires_epoch"] and spec["expires_epoch"]==scope["expires_epoch"], "complete lifecycle does not fit unchanged deadline")
    h.require(scope["status"]=="PROSPECTIVE_TWO_ROLE_HB_RUNTIME_QUALIFICATION_SCOPE" and scope["maximum_jobs"]==2 and scope["compute_CPU_reservation"]==1200, "fresh corrected-source scope required")
    h.require(spec["role"]==packet["role"]==ready["role"]=="EXACT_R46_STARTUP_METADATA", "actual role2 READY required")
    h.require(spec["schema"]=="pricefm_startup_batch_spec_v1" and spec["sources"]==packet["sources"]==ready["sources"], "exact source maps differ")
    h.require(set(spec["sources"])==set(expected_sources) and all(spec["sources"][n]["sha256"]==v for n,v in expected_sources.items()), "reviewed fourteen-source candidate closure required")
    h.require(spec["scope"]["sha256"]==scope_pin["sha256"] and spec['scope']['path']==packet['remote_root']+'/Q_SCOPE.json'
              and spec["aggregate_CPU_reservation"]==600 and spec["threads"]==1 and spec["memory_MiB"]==8192, "new staged scope/resource binding differs")
    h.require(ready["status"]=="READY_SOURCE_BOUND_COMPUTE_METADATA" and ready["scope_id"]==packet["scope_id"]==spec["scope_id"] and ready["spec_sha256"]==packet["spec_sha256"], "READY/SPEC identity differs")
    h.require(type(ready["job_id"]) is str and ready["job_id"].isdigit() and ready["node"]==spec["node"]==scope["execution_node"]
              and ready.get("qualification_route_id")==spec.get("qualification_route_id")==scope["qualification_route_id"] and len(ready["affinity"])==1 and ready["cpus_per_task"]==1 and type(ready["models"]) is int and ready["models"]==0, "actual one-CPU compute allocation required")
    prior=spec["accepted_inventory"]
    h.require(prior["status"]=="ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE" and prior["role"]=="COMPUTE_RUNTIME_INVENTORY" and prior["kernel_matrix_pass"] is True
              and prior.get('qualification_route_id')==scope['qualification_route_id'], "actual accepted new kernel/inventory proof required")
    root=spec["remote_root"]; h.require(root==packet["remote_root"] and root.startswith("/mnt/beegfs/home/jaguir26/pricefm_") and ".." not in Path(root).parts, "private remote root differs")
    h.require(review["status"]=="PASS_REVIEWED_STREAMING_RUNTIME_ARCHIVE_REAL_ARTIFACT" and review["manifest"]["sha256"]==spec["carrier_manifest"]["sha256"] and review["archive"]["sha256"]==spec["carrier"]["sha256"], "actual independently reviewed carrier binding differs")
    rows=manifest["files"]; h.require(type(rows) is list and 0<len(rows)<=2048, "bounded carrier files required")
    seen=set(); expected=[]; sizes=0; native=None
    for row in rows:
        name=row["relative"]; rel=Path(name)
        h.require(type(name) is str and str(rel)==name and not rel.is_absolute() and ".." not in rel.parts and rel.parts[0] in {"R_HOME","lib"} and name not in seen, "unsafe/duplicate runtime member")
        h.require(type(row["bytes"]) is int and 0<=row["bytes"]<=64*1024**2 and type(row["mode"]) is int and 0<=row["mode"]<=0o777 and re.fullmatch("[0-9a-f]{64}",row["sha256"]), "runtime size/mode/hash boundary")
        seen.add(name); sizes+=row["bytes"]; value={"path":root+"/runtime_carrier/"+name,"sha256":row["sha256"]}; expected.append(value)
        if name=="R_HOME/bin/exec/R": native=value
    h.require(native and native["sha256"]=="9d76330f01cace4574a9ec7a5407ca50b9faacc9813bbf4339595582e5c33c27" and sizes==manifest["total_bytes"], "exact native R4.6 ELF and manifest total required")
    carrier=ready["carrier"]
    h.require(carrier["status"]=="DURABLE_BYTE_IDENTICAL_RUNTIME_CARRIER_INSTALLED" and carrier["root"]==root+"/runtime_carrier" and carrier["manifest"]==spec["carrier_manifest"] and carrier["files"]==expected and carrier["file_count"]==len(rows) and carrier["total_bytes"]==sizes and carrier["all_writes_before_file_sync"] is True and carrier["no_original_runtime_mutation"] is True, "actual carrier install differs from reviewed bytes")
    inventory=ready["inventory"]
    h.require(inventory["status"]=="COMPUTE_RUNTIME_FACTS_NO_R" and inventory["job_id"]==ready["job_id"] and inventory["node"]==ready["node"]
              and inventory.get('qualification_route_id')==scope['qualification_route_id']
              and inventory["affinity"]==ready["affinity"] and inventory["R_executions"]==0, "actual runtime inventory binding differs")
    python=inventory["python"];h.require(python["path"]==spec["cached_python"] and python["sha256"]==spec["cached_python_sha256"], "cached native Python differs")
    aliases=[]; helpers={}
    for name in ("which","uname"):
        item=inventory["helpers"][name]; target=item["resolved_file"]
        h.require(item["logical_path"]=="/usr/bin/"+name and type(item["bytes"]) is int and 0<item["bytes"]<=64*1024**2 and re.fullmatch("[0-9a-f]{64}",target["sha256"]) and target["path"].startswith("/usr/") and ".." not in Path(target["path"]).parts, "actual helper alias metadata required")
        h.require(target not in expected, "helper duplicates runtime member"); expected.append(target);sizes+=item["bytes"];helpers[name]=target;aliases.append({"logical_path":item["logical_path"],"resolved_file":target})
    h.require(len(expected)<=2048 and sizes<=128*1024**2, "complete runtime/helper closure exceeds limits")
    sources={"adapter":spec["sources"]["startup_stop_helper.py"],"supervisor":spec["sources"]["startup_stop_candidate.py"],"fixture":spec["sources"]["startup_helper_metadata_fixture.R"],"original_supervisor":spec["sources"]["profile_supervisor.py"],"original_adapter":spec["sources"]["startup_helper.py"]}
    nonce=hashlib.sha256((ready["scope_id"]+"/"+ready["job_id"]+"/R46-metadata").encode()).hexdigest()[:32]
    rhome=root+"/runtime_carrier/R_HOME"; env={k:"1" for k in ("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS","VECLIB_MAXIMUM_THREADS","NUMEXPR_NUM_THREADS","BLIS_NUM_THREADS")}
    env.update(PATH="/usr/bin:/bin",LC_ALL="C",LANG="C",TZ="UTC",HOME=root,TMPDIR=root,R_HOME=rhome,R_ARCH="",R_DOC_DIR=rhome+"/doc",R_INCLUDE_DIR=rhome+"/include",R_SHARE_DIR=rhome+"/share",R_LIBS_USER="",R_LIBS_SITE="",LD_LIBRARY_PATH=rhome+"/lib:"+root+"/runtime_carrier/lib",SLURM_JOB_ID=ready["job_id"],SLURMD_NODENAME=ready["node"],SLURM_CPUS_PER_TASK="1")
    placement={"kind":"SLURM_SINGLE_CPU_METADATA","job_id":ready["job_id"],"node":ready["node"]};limits={"CPU":30,"wall":120,"output_cap":1048576}
    plan={"schema":"pricefm_startup_helper_plan_v1","role":"R_STARTUP_METADATA_ONLY","nonce":nonce,"sources":sources,"supervisor_python":python,"runtime":{"kind":"NATIVE_R_METADATA","version":"4.6.0","executable":native,"R_home":rhome,"uname":helpers["uname"],"which":helpers["which"],"helper_aliases":aliases},"runtime_files":expected,"environment":env,"placement":placement,"limits":limits,"command":[native["path"],"--vanilla","--slave","--no-save","--no-restore","--file="+sources["fixture"]["path"],"--args",nonce],"output_dir":root+"/result/R_STARTUP_"+nonce}
    child={"status":"TEMPLATE_NOT_ISSUED","required_issued_status":"PROSPECTIVE_PRICEFM_STARTUP_COMPUTE_QUALIFICATION_SCOPE","parent":scope_pin,"issued_epoch":None,"expires_epoch":scope["expires_epoch"],"role":"R_STARTUP_METADATA_ONLY","funded_within_role600":30,"no_new_compute_reservation":True,"job_id":ready["job_id"],"node":ready["node"],"optimizer_invocations":0,"scientific_data_access":False}
    plan["qualification_route_id"]=scope["qualification_route_id"];child["qualification_route_id"]=scope["qualification_route_id"]
    return plan,child


def prepare_foundation_release(config_path,bundle,role=None):
    config,scope,site,hashes=load_config(config_path);role=role or ROLES[0]
    h.require(role in ROLES,'exact supported foundation role')
    root=Path(config['registry'])/role;p=packet(root);job=h.read(h.pin(root/'JOB.json'))
    ready_value=h.read(h.pin(root/'READY.json'));validate_ready(ready_value,p,job['job_id'])
    spec=h.read(dict(path=str(root/'packet/SPEC.json'),sha256=p['spec_sha256']))
    out=h.physical(bundle);h.require(out.is_relative_to(h.physical(scope['allowed_metadata_output_root'])),'new private foundation release bundle')
    out.mkdir(mode=0o700)
    folder=p['remote_root']+'/release/'
    remote=lambda name:dict(path=folder+name,sha256=digest(out/name))
    proposed=dict(required_status='ROOT_RELEASED_STARTUP_BATCH_ROLE',role=role,scope_id=p['scope_id'],
        job_id=job['job_id'],node=config['node'],qualification_route_id=scope['qualification_route_id'],
        ready_sha256=digest(root/'READY.json'),spec_sha256=p['spec_sha256'],sources=p['sources'],
        scope_sha256=config['scope']['sha256'],issued_epoch=None,expires_epoch=scope['expires_epoch'])
    if role==ROLES[0]:
        proposed.update(kernel_matrix_CPU_reservation=30,kernel_case_caps=[4]*6,kernel_driver_SELF_cap=6)
    else:
        validate_kernel_prerequisite(config,hashes)
        integrity=h.read(config['carrier_integrity_review']);manifest=h.read(config['carrier_manifest'])
        plan,child=build_R_startup_plan(ready_value,p,spec,scope,integrity,manifest,time.time(),config['scope'],hashes)
        h.write_new(out/'R_STARTUP_PLAN.json',plan);h.write_new(out/'R_CHILD_SCOPE_TEMPLATE.json',child)
        h.write_new(out/'R_AUTHORITY_TEMPLATE.json',dict(schema='pricefm_startup_helper_authority_v1',
            required_status='ROOT_AUTHORIZED_SOURCE_BOUND_STARTUP_HELPER_PROOF',plan=remote('R_STARTUP_PLAN.json'),
            role=plan['role'],sources=plan['sources'],limits=plan['limits'],placement=plan['placement'],
            executions=1,no_real_target_data_or_optimizer=True,allowed_output_parent=p['remote_root']+'/result',
            issued_epoch=None,expires_epoch=scope['expires_epoch']))
    h.write_new(out/'RELEASE_TEMPLATE.json',proposed)
    result=dict(status='PREPARED_FOUNDATION_RELEASE_NOT_ROOT_OR_PEER_AUTHORITY',role=role,config=h.pin(config_path),
        packet=h.pin(root/'PACKET.json'),actual_ready=h.pin(root/'READY.json'),bundle=str(out),R_executions=0)
    h.write_new(out/'PREPARATION.json',result);return result


def foundation_release_proposal(config_path,bundle,role):
    config,scope,site,hashes=load_config(config_path);out=h.physical(bundle)
    value=h.read(h.pin(out/'RELEASE_TEMPLATE.json'));h.require(value['role']==role,'exact prepared role')
    root=Path(config['registry'])/role;p=packet(root);job=h.read(h.pin(root/'JOB.json'))
    ready=h.read(h.pin(root/'READY.json'));validate_ready(ready,p,job['job_id'])
    peer=h.read(h.pin(out/'PEER_RELEASE.json'))
    h.require(peer.get('status')=='PASS_REVIEWED_STARTUP_BATCH_RELEASE'
              and peer.get('role')==role and peer.get('job_id')==job['job_id']
              and peer.get('node')==config['node'] and peer.get('qualification_route_id')==scope['qualification_route_id']
              and peer.get('ready_sha256')==digest(root/'READY.json') and peer.get('spec_sha256')==p['spec_sha256']
              and peer.get('sources')==hashes,'actual same-route independent release review before root proposal')
    folder=p['remote_root']+'/release/'
    rp=lambda name:dict(path=folder+name,sha256=digest(out/name))
    names=['PEER_RELEASE.json']
    if role==ROLES[1]:
        names+=['R_STARTUP_PLAN.json','R_CHILD_SCOPE.json','R_REVIEW.json','R_AUTHORITY.json']
        value.update(startup_plan=rp('R_STARTUP_PLAN.json'),startup_authority=rp('R_AUTHORITY.json'),startup_review=rp('R_REVIEW.json'))
    for name in names:h.physical(out/name)
    value['independent_review']=rp('PEER_RELEASE.json')
    value['files']=[dict(relative=name,sha256=digest(out/name)) for name in names]
    return value


def validate_kernel_prerequisite(config,hashes):
    root=Path(config['registry'])/ROLES[0];accepted=h.read(h.pin(root/'ACCEPTED.json'))
    scope=h.read(config['scope']);result=h.read(accepted['result']);account=h.read(accepted['accounting'])
    h.require(accepted.get('status')=='ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE'
              and accepted.get('role')==ROLES[0] and accepted.get('kernel_matrix_pass') is True
              and accepted.get('qualification_route_id')==result.get('qualification_route_id')==scope['qualification_route_id']
              and result.get('node')==config['node'] and result.get('job_id')==accepted['job_id']
              and result.get('status')=='INVENTORY_COMPLETE_KERNEL_PASS_NO_R'
              and {name:value['sha256'] for name,value in result['sources'].items()}==hashes,
              'fresh same-node same-route same14-source actual kernel result')
    guard=h.read(accepted['actual_accept_action_guard'])
    h.require(type(guard.get('returncode')) is type(guard.get('command_returncode')) is int
              and guard['returncode']==guard['command_returncode']==0 and guard.get('cap_reason') is None
              and type(guard.get('CPU_limit')) is int and guard['CPU_limit']==5
              and type(guard.get('aggregate_CPU_seconds')) in (int,float) and math.isfinite(guard['aggregate_CPU_seconds'])
              and 0<=guard['aggregate_CPU_seconds']<5
              and type(guard.get('complete_lifecycle_wall_seconds')) in (int,float)
              and math.isfinite(guard['complete_lifecycle_wall_seconds']) and 0<=guard['complete_lifecycle_wall_seconds']<=180
              and all(guard.get(k) is True for k in ['all_owned_descendants_reaped','independent_guardian','kernel_escape_filter',
                    'orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once'])
              and guard.get('guardian_forced_monitor_stop') is False,
              'actual healthy original kernel acceptance guardian')
    h.require(dict(h.strict_json(guard['stdout']),status=accepted['status'],
                   actual_accept_action_guard=accepted['actual_accept_action_guard'])==accepted,
              'actual guarded kernel acceptance candidate')
    review=h.read(accepted['independent_review']);manifest=h.read(accepted['full_return_manifest'])
    h.require(account.get('complete') is True and account.get('terminal') is True
              and account.get('job_id')==accepted['job_id'] and account.get('primary_charge_counted_once') is True
              and review.get('status')=='PASS_REVIEWED_STARTUP_BATCH_ROLE'
              and review.get('result')==accepted['result'] and review.get('accounting')==accepted['accounting']
              and review.get('return_manifest')==accepted['full_return_manifest'],'complete actual kernel account/independent return')
    files={row['relative']:row for row in manifest['files']}
    h.require(len(files)==len(manifest['files']) and 'INVENTORY.json' in files
              and result['outcome'].get('status')=='PASS_COMPUTE_OWNED_HELPER_KERNEL_MATRIX_NOT_R'
              and len(result['outcome'].get('case_results',[]))==6
              and all(row.get('test_expectation_met') is True and row.get('all_private_descendants_reaped') is True
                      for row in result['outcome']['case_results']),'all six actual helper cases complete and drained')
    inventory=h.read(dict(path=str(Path(accepted['full_return_manifest']['path']).parent/'INVENTORY.json'),
                          sha256=files['INVENTORY.json']['sha256']))
    h.require(inventory.get('node')==config['node'] and inventory.get('qualification_route_id')==scope['qualification_route_id']
              and inventory.get('job_id')==accepted['job_id'],'fresh qualified kernel inventory')
    return accepted


def prepare(config, scope, role, hashes, registry):
    h.require(role in ROLES, "metadata-only qualification role required")
    if role == ROLES[1]:
        first = registry / ROLES[0] / "ACCEPTED.json"
        h.require(first.is_file() and h.read(h.pin(first))["role"] == ROLES[0]
                  and records(first.parent)[-1]["state"] == "ACCEPTED", "accepted inventory/kernel role with released claim required first")
        validate_kernel_prerequisite(config,hashes)
    root = registry / role; root.mkdir(mode=0o700)
    packet = root / "packet"; packet.mkdir(mode=0o700); (packet / "package").mkdir(); (packet / "package/pricefm_hb").mkdir()
    token = hashlib.sha256((str(root) + str(time.time_ns())).encode()).hexdigest()[:20]
    scope_id = "r174-" + ("inventory-" if role == ROLES[0] else "R46-") + token
    remote = config["remote_namespace"] + "/" + scope_id
    uploads = []; sources = {}
    for name in NAMES:
        source = Path(config["source_dir"]) / name; target = packet / "package/pricefm_hb" / name
        with target.open("xb") as handle: handle.write(source.read_bytes())
        relative = "package/pricefm_hb/" + name
        uploads.append(dict(local=str(target), relative=relative, sha256=hashes[name], bytes=target.stat().st_size))
        sources[name] = dict(path=remote + "/" + relative, sha256=hashes[name])
    scope_bytes = h.read_pin(config["scope"])
    (packet / "Q_SCOPE.json").write_bytes(scope_bytes)
    uploads.append(dict(local=str(packet / "Q_SCOPE.json"), relative="Q_SCOPE.json",
                        sha256=config["scope"]["sha256"], bytes=len(scope_bytes)))
    spec = dict(schema="pricefm_startup_batch_spec_v1", role=role, scope_id=scope_id, remote_root=remote,
        scope=dict(path=remote + "/Q_SCOPE.json", sha256=config["scope"]["sha256"]),
        source_commit=h.read(config["publication"])["commit"], sources=sources,
        cached_python=config["cached_python"], cached_python_sha256=config["cached_python_sha256"],
        node=config["node"], qualification_route_id=scope["qualification_route_id"], nonce=token, expires_epoch=scope["expires_epoch"], release_wait_seconds=300,
        component_CPU_caps=dict(shell_srun=30, worker=30, kernel_or_R_guard=30, launch_reserve=30),
        aggregate_CPU_reservation=600, wall_seconds=1200, memory_MiB=8192, threads=1,
        maximum_return_bytes=32 * 1024**2, maximum_return_files=4096, new_models=0)
    if role == ROLES[1]:
        for label in ("carrier", "carrier_manifest"):
            value = config[label]; raw = h.read_pin(value, 128 * 1024**2)
            filename = "carrier.tar.gz" if label == "carrier" else "carrier_manifest.json"
            path = packet / filename; path.write_bytes(raw)
            spec[label] = dict(path=remote + "/" + filename, sha256=value["sha256"])
            uploads.append(dict(local=str(path), relative=filename, sha256=value["sha256"], bytes=len(raw)))
        spec["accepted_inventory"] = h.read(h.pin(registry / ROLES[0] / "ACCEPTED.json"))
    h.write_new(packet / "SPEC.json", spec)
    spec_sha = digest(packet / "SPEC.json")
    body = ("#!/bin/bash\nset -euo pipefail\numask 077\nulimit -c 0\nulimit -t 30\nexport PATH=/usr/bin:/bin\n"
        + "\n".join("export " + key + "=1" for key in sorted(h.THREAD_KEYS)) + "\n"
        + "exec /usr/bin/srun --ntasks=1 --cpus-per-task=1 --cpu-bind=threads --kill-on-bad-exit=1 --propagate=CPU --export=ALL "
        + shlex.join([config["cached_python"], "-I", "-B", remote + "/package/pricefm_hb/startup_batch_stop_worker.py",
                      "--spec", remote + "/SPEC.json", "--sha256", spec_sha]) + "\n")
    with (packet / "job.sbatch").open("x") as handle: handle.write(body)
    for name in ("SPEC.json", "job.sbatch"):
        path = packet / name; uploads.append(dict(local=str(path), relative=name, sha256=digest(path), bytes=path.stat().st_size))
    manifest = dict(scope_id=scope_id, role=role, remote_root=remote, execution_node=config["node"], qualification_route_id=scope["qualification_route_id"], spec_sha256=spec_sha, uploads=uploads, sources=sources,
                    source_publication=config["publication"], source_review=config["source_review"])
    h.write_new(root / "PACKET.json", manifest); append(root, "PREPARED", packet=h.pin(root / "PACKET.json"))
    return manifest


def packet(root):
    first = records(root)[0]
    h.require(first["state"] == "PREPARED" and first["packet"]["path"] == str(root / "PACKET.json"),
              "original immutable packet pin required")
    return h.read(first["packet"])


def stage(config, site, registry, root):
    p = packet(root); one_shot(root, "stage")
    h.require(not any(x["state"] in {"SUBMITTED", "AMBIGUOUS_SPENT", "RELEASED"}
                      for other in registry.iterdir() if other.is_dir() and other != root for x in records(other)[-1:]),
              "another canonical role may still own a job")
    lock = config["remote_namespace"] + "/qualification.lock"
    append(root, "STAGING_INTENT", remote_claim=lock)
    for argv in (["mkdir", "-p", "-m", "700", config["remote_namespace"]], ["mkdir", "-m", "700", lock]):
        result = run_native(site, argv); h.require(result["returncode"] == 0, "native exclusive staging/claim failed; claim retained")
    spent = run_native(site, ["mkdir", "-m", "700", config["remote_namespace"] + "/ROLE_" + p["role"] + "_SPENT"])
    if spent["returncode"] != 0:
        run_native(site, ["rmdir", lock])  # Our just-created, still-empty private claim only.
        raise ValueError("canonical remote role already spent; no cross-server replay")
    h.require(run_native(site, ["mkdir", "-m", "700", p["remote_root"]])["returncode"] == 0, "new remote role namespace required")
    commands = []
    for directory in ("package", "package/pricefm_hb", "release", "result", "tmp"):
        commands.append("mkdir " + safe_path(p["remote_root"] + "/" + directory))
    marker = root / "CLAIM_MARKER"; marker.write_bytes(b"")
    commands.append("put " + safe_path(str(marker)) + " " + lock + "/OWNED_" + p["scope_id"])
    for row in p["uploads"]:
        h.require(digest(row["local"]) == row["sha256"], "local upload bytes changed")
        commands.append("put " + safe_path(row["local"]) + " " + safe_path(p["remote_root"] + "/" + row["relative"]))
    transfer = run_sftp(site, commands, root / "stage.sftp")
    h.require(transfer["returncode"] == 0, "partial or failed SFTP stage; no retry/submission allowed")
    expected = {p["remote_root"] + "/" + x["relative"]: x["sha256"] for x in p["uploads"]}
    expected[config["cached_python"]] = config["cached_python_sha256"]
    hashes = run_native(site, ["sha256sum", *sorted(expected)])
    h.require(hashes["returncode"] == 0, "native complete stage hash observation failed")
    actual = {}
    for line in hashes["stdout"].splitlines():
        parts = line.split(None, 1)
        h.require(len(parts) == 2 and re.fullmatch("[0-9a-f]{64}", parts[0]) and parts[1] not in actual,
                  "complete unique native staged hash rows required")
        actual[parts[1]] = parts[0]
    h.require(actual == expected, "partial/changed stage or cached Python identity; no submission")
    append(root, "STAGED", transfer=transfer)
    return dict(status="STAGED_NOT_SUBMITTED", scope_id=p["scope_id"])


def parse_job_id(raw):
    h.require(type(raw) is str and re.fullmatch(r"[1-9][0-9]*(?:;[A-Za-z0-9_.-]+)?\n?", raw), "ambiguous sbatch reply")
    return raw.strip().split(";", 1)[0]


def validate_submission_calendar(scope,role,*,paired=False,now=None):
    now=time.time() if now is None else now
    cutoffs=scope.get('fixed_submit_cutoffs',{});remaining=scope.get('remaining_route_role_count')
    h.require(type(cutoffs) is dict and role in cutoffs and type(cutoffs[role]) in (int,float)
              and type(scope.get('not_before_epoch')) in (int,float)
              and scope['not_before_epoch']<=now<cutoffs[role]
              and type(remaining) is int and remaining>=1
              and type(scope.get('role_slot_seconds')) is int and scope['role_slot_seconds']==7200
              and type(scope.get('final_route_reserve_seconds')) is int and scope['final_route_reserve_seconds']==3600,
              'fresh fixed per-role submission window and complete remaining-route price')
    if paired:remaining-=ROLES.index(role)
    h.require(remaining>=1 and now+remaining*7200+3600<=scope['expires_epoch'],
              'complete remaining serial route and failure/handoff reserves cannot fit')


def submit(config, scope, site, root):
    p = packet(root)
    validate_submission_calendar(scope,p['role'],paired=True); h.require(records(root)[-1]["state"] == "STAGED", "exact completed stage required")
    one_shot(root, "submit")
    h.require(time.time() + 1200 < scope["expires_epoch"], "full new batch wall must fit fixed scope")
    queue = run_native(site, ["squeue", "--noheader", "--user", site["user"], "--format", "%i"])
    h.require(queue["returncode"] == 0 and not queue["stdout"].strip(), "existing own queue blocks single-job admission")
    append(root, "SUBMISSION_INTENT", whole_compute_CPU_reservation=600,
                                     wall_seconds=1200, automatic_retry=False)
    argv = ["sbatch", "--parsable", "--export=NONE", "--propagate=NONE", "--mail-type=NONE",
        "--account=" + site["account"], "--partition=" + site["partition"],
        "--qos=" + site["qos"], "--nodelist=" + config["node"], "--nodes=1", "--ntasks=1",
        "--cpus-per-task=1", "--hint=nomultithread", "--mem=8192M",
        "--time=00:20:00", "--no-requeue", "--job-name=" + p["scope_id"], "--chdir=" + p["remote_root"],
        "--output=" + p["remote_root"] + "/slurm-%j.out", "--error=" + p["remote_root"] + "/slurm-%j.err",
        p["remote_root"] + "/job.sbatch"]
    result = None
    try:
        result = run_native(site, argv)
        h.require(result["returncode"] == 0, "sbatch failed or reply lost")
        job_id = parse_job_id(result["stdout"])
    except BaseException as error:
        append(root, "AMBIGUOUS_SPENT", error=type(error).__name__ + ": " + str(error), available_native_reply=result,
               all_claims_and_fees_retained=True)
        raise
    h.write_new(root / "JOB.json", dict(job_id=job_id, scope_id=p["scope_id"], submission=result))
    append(root, "SUBMITTED", job_id=job_id, job=h.pin(root / "JOB.json"))
    return dict(status="SUBMITTED", job_id=job_id)


def validate_ready(ready, p, job_id):
    h.require(ready["status"] == "READY_SOURCE_BOUND_COMPUTE_METADATA" and ready["scope_id"] == p["scope_id"]
              and ready["job_id"] == job_id and ready["spec_sha256"] == p["spec_sha256"]
              and ready["node"] == p["execution_node"] and ready["qualification_route_id"] == p["qualification_route_id"] and len(ready["affinity"]) == 1
              and ready["cpus_per_task"] == 1 and type(ready["models"]) is int and ready["models"] == 0
              and ready["sources"] == p["sources"] and ready["role"] == p["role"],
              "stale/foreign/malformed READY cannot release payload")


def ready(site, root):
    p = packet(root); job = h.read(h.pin(root / "JOB.json")); one_shot(root, "ready")
    # One paid observation only. Wait outside this guarded action, then fetch
    # once; protected sleeps consume guardian stop-window/accounting headroom.
    result = run_native(site, ["test", "-f", p["remote_root"] + "/READY.json"])
    if result["returncode"] == 1:
        prior = next((x["accounting"] for x in reversed(records(root)) if x["state"] == "OBSERVED"), None)
        diagnostic = h.read(prior) if prior is not None else None
        error = None
        if diagnostic is None or not diagnostic["terminal"]:
            try:
                # This diagnostic consumes one of the same three throttled
                # accounting intents, within this unchanged six-CPU action.
                diagnostic = observe(site, root)
            except BaseException as exc:
                error = type(exc).__name__ + ": " + str(exc)
        append(root, "READY_ABSENT_DIAGNOSTIC", accounting=diagnostic,
               accounting_error=error, ready_observations=1, automatic_retry=False)
        raise ValueError("READY absent after one observation; diagnostic retained; no automatic retry")
    h.require(result["returncode"] == 0, "READY observation transport failed; no automatic retry")
    one_shot(root, "ready_fetch")
    result = run_sftp(site, ["get " + p["remote_root"] + "/READY.json " + safe_path(str(root / "READY.json"))], root / "ready.sftp")
    h.require(result["returncode"] == 0, "READY transfer incomplete")
    value = h.read(h.pin(root / "READY.json")); validate_ready(value, p, job["job_id"])
    append(root, "READY_VALIDATED", ready=h.pin(root / "READY.json"))
    return value


def release(site, root, bundle):
    p = packet(root); job = h.read(h.pin(root / "JOB.json")); ready_value = h.read(h.pin(root / "READY.json"))
    validate_ready(ready_value, p, job["job_id"])
    release_path = h.physical(bundle) / "RELEASE.json"; value = h.read(h.pin(release_path))
    h.require(value["status"] == "ROOT_RELEASED_STARTUP_BATCH_ROLE" and value["scope_id"] == p["scope_id"]
              and value.get('node')==p['execution_node'] and value.get('qualification_route_id')==p['qualification_route_id']
              and value["job_id"] == job["job_id"] and value["ready_sha256"] == digest(root / "READY.json")
              and value["spec_sha256"] == p["spec_sha256"] and value["role"] == p["role"], "actual root READY-bound release required")
    commands = []
    for row in value["files"]:
        relative = str(safe_relative(row["relative"])); local = h.physical(bundle) / relative
        h.require(local.parent == h.physical(bundle) and digest(local) == row["sha256"], "flat exact release metadata required")
        commands.append("put " + safe_path(str(local)) + " " + p["remote_root"] + "/release/" + relative)
    h.require(all(x["relative"] not in {"RELEASE.json", "RELEASE.json.partial"} for x in value["files"]), "reserved release publication filename")
    commands.append("put " + safe_path(str(release_path)) + " " + p["remote_root"] + "/release/RELEASE.json.partial")
    commands.append("rename " + p["remote_root"] + "/release/RELEASE.json.partial " + p["remote_root"] + "/release/RELEASE.json")
    one_shot(root, "release"); append(root, "RELEASE_INTENT", release=h.pin(release_path))
    result = run_sftp(site, commands, root / "release.sftp"); h.require(result["returncode"] == 0, "partial release retained; no retry")
    append(root, "RELEASED", release=h.pin(release_path), transfer=result)
    return dict(status="RELEASED", job_id=job["job_id"])


def CPU_seconds(text):
    match = re.fullmatch(r"(?:(\d+)-)?(?:(\d+):)?(\d\d):(\d\d(?:\.\d+)?)", text)
    h.require(match is not None, "complete Slurm TotalCPU required")
    days, hours, minutes, seconds = match.groups()
    value = int(days or 0) * 86400 + int(hours or 0) * 3600 + int(minutes) * 60 + float(seconds)
    h.require(math.isfinite(value) and value >= 0 and int(minutes) < 60 and float(seconds) < 60, "invalid Slurm CPU")
    return value


def parse_accounting(raw,job_id,scope_id,expected_node=None):
    lines=[line.split('|') for line in raw.splitlines() if line.strip()]
    h.require(lines and all(len(row) in (11,16) and row[0] in {job_id,job_id+'.batch',job_id+'.extern'} for row in lines)
              and len({row[0] for row in lines})==len(lines) and len({len(row) for row in lines})==1,
              'foreign/duplicate/partial accounting row')
    primary=[row for row in lines if row[0]==job_id]
    h.require(len(primary)==1,'one complete canonical primary Slurm row required')
    x=primary[0];state=x[1].split()[0]
    h.require(x[6]==scope_id and x[7:9]==['128x24','128x24'] and x[5] in ('0','1'),
              'foreign job/account/allocation')
    memory=re.fullmatch(r'([0-9.]+)([KMG])([cn])?',x[9])
    h.require(memory is not None and float(memory[1])*{'K':1/1024,'M':1,'G':1024}[memory[2]]==8192,
              'actual primary requested memory differs from8GiB')
    cpu=CPU_seconds(x[3]);elapsed=int(x[4]);h.require(cpu<=600 and 0<=elapsed<=1200,'whole batch reservation exceeded')
    if len(x)==16:
        h.require(x[11]=='jaguir26' and x[12]==str(os.getuid()) and x[13]=='1','exact primary Slurm user/UID/requestedCPU')
    elif expected_node is not None:
        raise ValueError('current scoped accounting requires complete owner/start/node fields')
    if x[5]=='0':
        h.require(len(x)==16 and len(lines)==1 and cpu==0 and elapsed==0 and x[2]=='0:0'
                  and state in {'PENDING','CONFIGURING','CANCELLED'}
                  and x[14] in {'','None','Unknown','N/A'} and x[15] in {'','None','None assigned','Unknown','N/A'},
                  'unallocated primary has no start/node/steps/CPU/elapsed; never numerical success')
        return dict(job_id=job_id,state=state,exit_code=x[2],canonical_primary_CPU_seconds=0.,elapsed_seconds=0,
            complete=False,terminal=state=='CANCELLED',allocation_state='UNALLOCATED_NO_NUMERICAL_SUCCESS',
            allocated_CPUs=0,numerical_admission=False,missing_required_rows=[job_id+'.batch'],
            user=x[11],uid=int(x[12]),requested_CPUs=1,start_raw=x[14] or None,node_raw=x[15] or None,
            MaxRSS_raw={job_id:x[10] or None},unknown_MaxRSS_is_not_zero=True,
            primary_CPU_consistent_with_each_step=True,raw_sacct=raw,step_rows_diagnostic_not_added=True,primary_charge_counted_once=True)
    if expected_node is not None:
        h.require(x[15]==expected_node and x[14] not in {'','None','Unknown','N/A'},'allocated primary must start on exact selected node')
    required={job_id,job_id+'.batch'};actual={row[0] for row in lines}
    for row in lines:
        h.require(re.fullmatch(r'[0-9]+:[0-9]+',row[2]) and 0<=int(row[4])<=1200
                  and int(row[5]) in (0,1) and CPU_seconds(row[3])<=600,'invalid step/accounting bound')
    complete_rows=required<=actual;consistent=cpu+.01>=max(CPU_seconds(row[3]) for row in lines)
    complete=complete_rows and consistent and all(row[1].split()[0]=='COMPLETED' and row[2]=='0:0' for row in lines)
    terminal=complete_rows and consistent and all(row[1].split()[0] in TERMINAL for row in lines)
    return dict(job_id=job_id,state=state,exit_code=x[2],canonical_primary_CPU_seconds=cpu,elapsed_seconds=elapsed,
        complete=complete,terminal=terminal,missing_required_rows=sorted(required-actual),
        MaxRSS_raw={row[0]:row[10] or None for row in lines},unknown_MaxRSS_is_not_zero=True,
        primary_CPU_consistent_with_each_step=consistent,raw_sacct=raw,step_rows_diagnostic_not_added=True,primary_charge_counted_once=True)


def observe(site, root):
    p = packet(root); job = h.read(h.pin(root / "JOB.json")); past = records(root)
    count = len(list(root.glob("observe_*.intent.json")))
    h.require(count < 3, "finite accounting polls exhausted")
    one_shot(root, "observe_%02d" % count)
    intents = sorted(root.glob("observe_*.intent.json"))
    if len(intents) > 1:
        h.require(h.read(h.pin(intents[-1]))["epoch"] - h.read(h.pin(intents[-2]))["epoch"] >= 300,
                  "minimum300seconds between paid Slurm accounting intents, including failures")
    result = run_native(site, ["sacct", "--jobs", job["job_id"], "--noheader", "--parsable2", "--format",
        "JobIDRaw,State,ExitCode,TotalCPU,ElapsedRaw,AllocCPUS,JobName%128,Account,Partition,ReqMem,MaxRSS,User,UID,ReqCPUS,Start,NodeList"])
    raw_path=root/("accounting_raw_%04d.json"%count);h.write_new(raw_path,result)
    h.require(result["returncode"] == 0, "accounting observation failed")
    value = parse_accounting(result["stdout"], job["job_id"], p["scope_id"],p.get("execution_node"))
    value["raw_observation"]=h.pin(raw_path)
    path = root / ("accounting_%04d.json" % sum(x["state"] == "OBSERVED" for x in past)); h.write_new(path, value)
    append(root, "OBSERVED", accounting=h.pin(path))
    return value


def validate_manifest(manifest, spec, job_id):
    h.require(manifest["schema"] == "pricefm_startup_batch_return_manifest_v1"
              and manifest["scope_id"] == spec["scope_id"] and manifest["job_id"] == job_id,
              "returned manifest identity differs")
    rows = manifest["files"]; h.require(type(rows) is list and 1 <= len(rows) <= 4096, "bounded return file count required")
    names = [str(safe_relative(x["relative"])) for x in rows]
    h.require(len(set(names)) == len(names) and "RESULT.json" in names
              and all(type(x["bytes"]) is int and 0 <= x["bytes"] <= 16 * 1024**2 for x in rows)
              and sum(x["bytes"] for x in rows) <= 32 * 1024**2, "bounded unique metadata-only return required")
    h.require(all(Path(x).suffix.lower() not in {".rds", ".rda", ".rdata", ".npz", ".npy"} for x in names),
              "scientific binary payload is not a runtime metadata return")


def collect(site, root):
    p = packet(root); job = h.read(h.pin(root / "JOB.json"))
    account = next(h.read(x["accounting"]) for x in reversed(records(root)) if x["state"] == "OBSERVED")
    h.require(account["terminal"], "known terminal job required before one-shot return")
    one_shot(root, "collect")
    diagnostics = root / "diagnostics"; diagnostics.mkdir(mode=0o700)
    # Optional raw logs remain useful even if the worker failed before sealing.
    logs = run_sftp(site, ["-get " + p["remote_root"] + "/slurm-" + job["job_id"] + ".out "
                           + safe_path(str(diagnostics / "slurm.stdout")),
                         "-get " + p["remote_root"] + "/slurm-" + job["job_id"] + ".err "
                           + safe_path(str(diagnostics / "slurm.stderr"))], root / "diagnostics.sftp")
    append(root, "DIAGNOSTICS_FETCHED", transport=logs,
           files=[h.pin(x) for x in sorted(diagnostics.iterdir()) if x.is_file()])
    raw = root / "returned"; raw.mkdir(mode=0o700)
    transfer = run_sftp(site, ["get " + p["remote_root"] + "/result/RETURN_MANIFEST.json "
                              + safe_path(str(raw / "RETURN_MANIFEST.json"))], root / "manifest.sftp")
    h.require(transfer["returncode"] == 0, "manifest return failed; no retry")
    manifest = h.read(h.pin(raw / "RETURN_MANIFEST.json")); validate_manifest(manifest, p, job["job_id"])
    commands = []
    for row in manifest["files"]:
        path = raw / row["relative"]; path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        commands.append("get " + p["remote_root"] + "/result/" + row["relative"] + " " + safe_path(str(path)))
    transfer = run_sftp(site, commands, root / "return.sftp"); h.require(transfer["returncode"] == 0, "partial return retained; no retry")
    for row in manifest["files"]:
        path = raw / row["relative"]
        h.require(path.is_file() and not path.is_symlink() and path.stat().st_size == row["bytes"]
                  and digest(path) == row["sha256"], "returned metadata bytes/hash differ")
    append(root, "RETURNED", manifest=h.pin(raw / "RETURN_MANIFEST.json"), full_return_hash_verified=True)
    return dict(status="COMPLETE_HASH_VERIFIED_RETURN_NOT_YET_ACCEPTED", manifest=h.pin(raw / "RETURN_MANIFEST.json"))


def accept(config, site, root, actual_review):
    p = packet(root); job = h.read(h.pin(root / "JOB.json")); past = records(root)
    returned = next(x for x in reversed(past) if x["state"] == "RETURNED")
    accounting_pin = next(x["accounting"] for x in reversed(past) if x["state"] == "OBSERVED")
    account = h.read(accounting_pin); h.require(account["complete"] and account["terminal"], "actual terminal successful primary accounting required")
    one_shot(root, "accept")
    queue = run_native(site, ["squeue", "--noheader", "--user", site["user"], "--format", "%i"])
    h.require(queue["returncode"] == 0 and job["job_id"] not in queue["stdout"].split(), "job still queued/unknown")
    result = h.read(h.pin(root / "returned/RESULT.json"))
    manifest = h.read(returned["manifest"]); validate_manifest(manifest, p, job["job_id"])
    for row in manifest["files"]:
        path = root / "returned" / row["relative"]
        h.require(path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], "returned bytes changed before acceptance")
    expected = "INVENTORY_COMPLETE_KERNEL_PASS_NO_R" if p["role"] == ROLES[0] else "R46_STARTUP_METADATA_PASS_NOT_NUMERICAL_PARITY"
    h.require(result["status"] == expected and result["job_id"] == job["job_id"]
              and result["role"] == p["role"]
              and result["scope_id"] == p["scope_id"] and result["spec_sha256"] == p["spec_sha256"]
              and type(result["new_models"]) is int and result["new_models"] == 0
              and result["sources"] == p["sources"] and result["node"] == p["execution_node"] and result.get("qualification_route_id") == p["qualification_route_id"], "actual matching compute-role result required")
    outcome = result["outcome"]
    if p["role"] == ROLES[0]:
        expected_labels = ["wait_and_escape", "orphan", "aggregate_CPU", "wall", "monitor_death", "guardian_death"]
        h.require(outcome["status"] == "PASS_COMPUTE_OWNED_HELPER_KERNEL_MATRIX_NOT_R"
                  and outcome["job_id"] == job["job_id"] and outcome["node"] == p["execution_node"]
                  and outcome["all_private_descendants_reaped"] is True and outcome["aggregate_CPU_seconds"] < 30
                  and [x["label"] for x in outcome["case_results"]] == expected_labels
                  and all(x["test_expectation_met"] is True for x in outcome["case_results"]),
                  "all six actual source-bound compute kernel cases required")
        remote_files = {p["remote_root"] + "/result/" + x["relative"]: x["sha256"] for x in manifest["files"]}
        h.require(all(remote_files.get(x["guard"]["path"]) == x["guard"]["sha256"]
                      and remote_files.get(x["stderr"]["path"]) == x["stderr"]["sha256"] for x in outcome["case_results"]),
                  "actual kernel case outputs must be part of complete verified return")
    else:
        h.require(outcome["status"] == "PASS_R_METADATA_STARTUP_UNDER_OWNED_HELPER_GUARD"
                  and outcome["R_startup_proved"] is True and outcome["production_ready"] is False
                  and outcome["numerical_parity_proved"] is False, "actual R startup proof is not a fit/numerical proof")
    review_pin = h.pin(actual_review); review = h.read(review_pin)
    h.require(review["status"] == "PASS_REVIEWED_STARTUP_BATCH_ROLE" and review["job_id"] == job["job_id"]
              and review["role"] == p["role"] and review["result"] == h.pin(root / "returned/RESULT.json")
              and review["return_manifest"] == returned["manifest"] and review["accounting"] == accounting_pin,
              "actual independent complete role review required")
    value = dict(status="ACCEPTANCE_PENDING_ACTUAL_OUTER_GUARD", role=p["role"], job_id=job["job_id"],
        scope_id=p["scope_id"], result=h.pin(root / "returned/RESULT.json"),
        full_return_manifest=returned["manifest"], accounting=accounting_pin,
        canonical_primary_CPU_seconds=account["canonical_primary_CPU_seconds"], primary_charge_counted_once=True,
        independent_review=review_pin, qualification_route_id=p["qualification_route_id"], kernel_matrix_pass=p["role"] == ROLES[0],
        no_numerical_parity_or_target_or_production_claim=True)
    h.write_new(root / "ACCEPTANCE_CANDIDATE.json", value); append(root, "ACCEPTANCE_VALIDATED", candidate=h.pin(root / "ACCEPTANCE_CANDIDATE.json"))
    lock = config["remote_namespace"] + "/qualification.lock"
    for argv in (["test", "-f", lock + "/OWNED_" + p["scope_id"]],
                 ["rm", "--", lock + "/OWNED_" + p["scope_id"]], ["rmdir", lock]):
        native = run_native(site, argv); h.require(native["returncode"] == 0, "accepted data but exclusive claim release failed; stop")
    append(root, "ACCEPTANCE_PENDING_GUARD", candidate=h.pin(root / "ACCEPTANCE_CANDIDATE.json"), claim_released=True)
    return value


def cancel(site, root):
    p = packet(root); job = h.read(h.pin(root / "JOB.json")); one_shot(root, "cancel")
    append(root, "CANCEL_INTENT", job_id=job["job_id"], compute_fee_retained=600)
    value = run_native(site, ["scancel", "--user", site["user"], "--name", p["scope_id"], job["job_id"]])
    h.require(value["returncode"] == 0, "own exact-job cancellation unknown; claim remains")
    append(root, "CANCEL_REQUESTED", result=value)
    return dict(status="CANCEL_REQUESTED_NOT_TERMINAL_PROOF", job_id=job["job_id"])


def retire_failed(config, site, root, actual_review):
    p = packet(root); job = h.read(h.pin(root / "JOB.json")); one_shot(root, "retire_failed")
    account_pin = next(x["accounting"] for x in reversed(records(root)) if x["state"] == "OBSERVED")
    account = h.read(account_pin)
    h.require(account["terminal"] and not account["complete"], "failed terminal primary accounting required")
    h.require(account.get('allocation_state')!='UNALLOCATED_NO_NUMERICAL_SUCCESS','unallocated cancellation requires separately funded H4 query/review/drain, never original H3')
    peer = h.read(h.pin(actual_review))
    h.require(peer["status"] == "PASS_REVIEWED_FAILED_STARTUP_BATCH_RETIREMENT"
              and peer["job_id"] == job["job_id"] and peer["accounting"] == account_pin,
              "actual failed-role retirement review required")
    queue = run_native(site, ["squeue", "--noheader", "--user", site["user"], "--format", "%i"])
    h.require(queue["returncode"] == 0 and job["job_id"] not in queue["stdout"].split(), "failed job still queued/unknown")
    lock = config["remote_namespace"] + "/qualification.lock"
    for argv in (["test", "-f", lock + "/OWNED_" + p["scope_id"]], ["rm", "--", lock + "/OWNED_" + p["scope_id"]], ["rmdir", lock]):
        h.require(run_native(site, argv)["returncode"] == 0, "failed claim release unknown; no retry")
    append(root, "FAILED_RETIRED_NO_RETRY", accounting=account_pin, independent_review=h.pin(actual_review),
           all_fees_and_partial_artifacts_retained=True, same_role_resubmission_forbidden=True)
    return dict(status="FAILED_RETIRED_NO_RETRY", job_id=job["job_id"])


def main():
    p = argparse.ArgumentParser(description=__doc__); p.add_argument("action", choices=("prepare", "stage", "submit", "ready", "release", "observe", "collect", "accept", "cancel", "retire_failed", "finalize"))
    p.add_argument("--config", required=True); p.add_argument("--role", choices=ROLES, required=True); p.add_argument("--bundle"); p.add_argument("--actual-review"); p.add_argument("--previous-guard"); p.add_argument("--failed-guard")
    a = p.parse_args(); config, scope, site, hashes = load_config(a.config)
    if a.action != "finalize":
        require_outer_context()
        h.require(resource.getrlimit(resource.RLIMIT_CPU)[1] == action_limits(a.action)["local_CPU"],
                  "actual inherited action CPU hard cap differs from prepriced envelope")
    else:
        resource.setrlimit(resource.RLIMIT_CPU, (2, 2)); signal.alarm(15)
    with canonical(config) as registry:
        if a.failed_guard:
            h.require(a.action in {"cancel", "observe", "collect", "retire_failed", "finalize"}, "failure acknowledgement cannot release or submit work")
            acknowledge_failed_previous(registry, a.role, a.failed_guard)
        previous = finish_previous(registry, a.previous_guard)
        if a.action == "finalize":
            print(json.dumps(previous, sort_keys=True)); return
        root = registry / a.role
        h.require(a.action not in {"prepare", "stage", "submit", "release", "accept"}
                  or not any((registry / role / "ROLE_FAILED_SPENT.json").exists() for role in ROLES),
                  "failed prior action quarantines all new compute/release/accept authority")
        started = started_action(registry, a.role, a.action)
        try:
            if a.action == "prepare": value = prepare(config, scope, a.role, hashes, registry)
            elif a.action == "stage": value = stage(config, site, registry, root)
            elif a.action == "submit": value = submit(config, scope, site, root)
            elif a.action == "ready": value = ready(site, root)
            elif a.action == "release": value = release(site, root, a.bundle)
            elif a.action == "observe": value = observe(site, root)
            elif a.action == "collect": value = collect(site, root)
            elif a.action == "accept": value = accept(config, site, root, a.actual_review)
            elif a.action == "cancel": value = cancel(site, root)
            else: value = retire_failed(config, site, root, a.actual_review)
        except BaseException as error:
            if root.is_dir(): append(root, "ACTION_FAILED_RETAINED", action=a.action, error=type(error).__name__ + ": " + str(error))
            raise
        pending_action(started, value)
    print(json.dumps(value, sort_keys=True))


if __name__ == "__main__":
    main()
