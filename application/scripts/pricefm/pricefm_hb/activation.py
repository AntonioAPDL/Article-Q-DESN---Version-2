"""R157 immutable queue authority and fresh compute-ready activation.

No numerical imports, submission, resource admission or foreign-host live claim
is performed here. Original proof bytes retain their original logical hashes;
an explicit release allowlist resolves staged proof locations.
"""
from __future__ import annotations
import datetime as dt
import hashlib
import math
import os
from pathlib import Path
import re
import subprocess
import time

from . import registry as r
from .environment import THREAD_ENV, REFERENCE_NUMERICAL_ENV, require_compute

AUTHORITY_SCHEMA = "r157_hb_execution_authority_v1"
ACTIVATION_SCHEMA = "r157_hb_compute_activation_v1"
READY_SCHEMA = "r157_hb_compute_ready_v1"
REQUEST_SCHEMA = "r157_hb_launch_request_v1"
OWNER = "muscat.be.ucsc.edu"
PURPOSES = {"CONTROL_TEST": 120, "COST_ONLY": 1200,
            "CACHED_NORMAL_COMPONENT": 5400, "PREFIX_ASSESSMENT": 1800}
BASE_SOURCES = ("__init__.py", "benchmark.py", "benchmark_plan.py", "science.py", "fixture.py",
                "environment.py", "control.py", "registry.py", "cost_control.py",
                "activation.py", "lifecycle.py", "handoff.py", "policy.py", "admission.py",
                "readiness.py", "operation_budget.py", "metered_io.py")


class ActivationError(ValueError):
    pass


def executed_sources(purpose):
    names = BASE_SOURCES + (("prefix.py", "prefix_control.py")
                            if purpose in {"CACHED_NORMAL_COMPONENT", "PREFIX_ASSESSMENT"} else ())
    return {name: r.digest(Path(__file__).with_name(name)) for name in names}


def validate_policy_sources(packet, sources):
    approved = {}
    for value in packet.get('execution_sources', []):
        name = Path(value['path']).name
        if name in approved and approved[name] != value['sha256']:
            raise ActivationError('policy contains conflicting execution source basenames')
        approved[name] = value['sha256']
    if any(approved.get(name) != sha for name, sha in sources.items()):
        raise ActivationError('policy does not bind the complete actual execution closure')


def fresh(value, now=None, seconds=300):
    now = time.time() if now is None else now
    epoch = value.get("observed_epoch")
    return type(epoch) in (int, float) and math.isfinite(epoch) and 0 <= now - epoch <= seconds


def read_pin(pin, authority=None, root=None):
    if (not isinstance(pin, dict) or set(pin) != {"path", "sha256"}
            or not isinstance(pin["path"], str) or not Path(pin["path"]).is_absolute()
            or not re.fullmatch(r"[a-f0-9]{64}", str(pin["sha256"]))):
        raise ActivationError("exact absolute path/SHA256 proof pin required")
    path = Path(pin["path"])
    if authority is not None:
        entry = authority.get("proof_manifest", {}).get(str(path))
        if not isinstance(entry, dict) or entry.get("sha256") != pin["sha256"]:
            raise ActivationError("proof absent from immutable staged allowlist")
        relative = Path(entry.get("relative_path", ""))
        if relative.is_absolute() or ".." in relative.parts or not relative.parts:
            raise ActivationError("unsafe staged proof location")
        root = root or os.environ.get("PRICEFM_RELEASE_ROOT")
        if not root:
            raise ActivationError("explicit verified release proof root required")
        path = r.no_links(Path(root) / relative)
        if path.stat().st_size != entry.get("bytes"):
            raise ActivationError("staged proof byte count differs")
    path = r.no_links(path)
    if r.digest(path) != pin["sha256"]:
        raise ActivationError("proof hash differs: " + str(path))
    return r.read(path)


def merge_proofs(authority, activation):
    manifest = dict(authority.get("proof_manifest", {}))
    for logical, entry in activation.get("proof_manifest", {}).items():
        if logical in manifest and manifest[logical] != entry:
            raise ActivationError("activation attempts to replace an original proof")
        manifest[logical] = entry
    return dict(authority, proof_manifest=manifest)


def verify_proof_manifest(authority, root=None):
    root=root or os.environ.get('PRICEFM_RELEASE_ROOT')
    if not root:raise ActivationError('verified proof root required')
    for logical,entry in authority.get('proof_manifest',{}).items():
        rel=Path(entry.get('relative_path',''))
        if not Path(logical).is_absolute() or rel.is_absolute() or '..' in rel.parts or not rel.parts:
            raise ActivationError('unsafe proof membership')
        path=r.no_links(Path(root)/rel)
        if not path.is_file() or path.stat().st_size!=entry.get('bytes') or r.digest(path)!=entry.get('sha256'):
            raise ActivationError('changed staged nested proof')


def validate_qualification(authority, reader=None):
    read = (lambda pin: read_pin(pin, authority)) if reader is None else reader
    runtime = read(authority["runtime_result"])
    parity = read(authority["parity_result"])
    seal = read(authority["parity_seal"])
    actual = read(authority["parity_runtime_result"])
    outer = read(authority["parity_qualification_seal"])
    if (runtime.get("status") != "verified" or runtime.get("python_version") != "3.11.13"
            or parity.get("status") != "PASS_TEST_FORECAST_PARITY" or parity.get("accepted") is not True
            or parity.get("execution", {}).get("namespace") != "TEST"
            or parity["execution"].get("fixture_manifest_sha256") != authority.get("accepted_parity_fixture_manifest_sha256")
            or seal.get("status") != "COMPLETE_TEST_ONLY"
            or seal.get("artifacts", {}).get("parity.json") != authority["parity_result"]["sha256"]
            or outer.get("application_passed") is not True
            or outer.get("files", {}).get("TEST/parity/parity.json") != authority["parity_result"]["sha256"]
            or outer["files"].get("environment-runtime.json") != authority["parity_runtime_result"]["sha256"]
            or outer.get("job_id") != parity["execution"].get("slurm_job_id")
            or outer.get("job_id") != actual.get("allocation", {}).get("job_id")
            or actual.get("status") != "verified" or actual.get("versions") != runtime.get("versions")
            or actual.get("executable") != runtime.get("executable")
            or actual.get("python_version") != runtime["python_version"]):
        raise ActivationError("accepted exact scientific/runtime qualification required")
    from .environment import validate_reference_profile_record
    validate_reference_profile_record(actual.get("reference_numerical_profile", {}))
    for record in (runtime, actual):
        pools = record.get("threadpoolctl")
        if not pools or any(p.get("num_threads") != 1 for p in pools):
            raise ActivationError("qualified native pools must be single-threaded")
    native = actual.get("native_library_sha256", {})
    if len(native) != 2 or any(not re.fullmatch(r"[a-f0-9]{64}", str(v)) for v in native.values()):
        raise ActivationError("both qualified actual native-library hashes required")
    from . import control
    for prefix,result_name,relative in (('runtime','runtime_result','environment-evidence/runtime-verification.json'),
                                        ('parity','parity_result','TEST/parity/parity.json')):
        q=read(authority[prefix+'_qualification_seal']);accounting=read(authority[prefix+'_accounting'])
        if (q.get('schema')!=r.SCHEMA or q.get('application_passed') is not True
                or q.get('files',{}).get(relative)!=authority[result_name]['sha256']
                or accounting.get('job_id')!=q.get('job_id') or accounting.get('complete') is not True
                or accounting.get('squeue','').strip()
                or not control.accounting(accounting['sacct'],q['job_id'],dict(cpus=1,memory_MiB=8192,wall_seconds=1800))['complete']):
            raise ActivationError('complete scheduler and application qualification required')
    return {"runtime": runtime, "parity": parity, "parity_runtime": actual}


def validate_authority(authority, purpose, plan_sha256, sources, now=None):
    now = time.time() if now is None else now
    allowed_schema = {AUTHORITY_SCHEMA, "r157_hb_cached_normal_component_authority_v1"}
    if (authority.get("schema") not in allowed_schema or purpose not in PURPOSES
            or authority.get("purpose") != purpose
            or authority.get("issuer") != OWNER or authority.get("controller") != OWNER
            or authority.get("plan_sha256") != plan_sha256
            or authority.get("executed_sources") != sources
            or authority.get("reference_numerical_environment") != REFERENCE_NUMERICAL_ENV
            or authority.get("automatic_retry") is not False
            or authority.get("new_model_fits") != 0 or authority.get("official_origins") != 0
            or authority.get("promotion") is not False):
        raise ActivationError("exact new purpose/source-bound authority required")
    if sources != executed_sources(purpose):
        raise ActivationError("actual execution source closure differs")
    if purpose == 'COST_ONLY' and (authority.get('study') not in {'FI','DK2'}
            or authority.get('role') != authority['study'] + '_COST_ONLY_BENCHMARK'):
        raise ActivationError('exact study-specific COST_ONLY benchmark role required')
    replacement=authority.get('cost_replacement')
    if replacement is not None:
        if (purpose!='COST_ONLY' or authority.get('protocol_version')!='r161_cost_replacement_v1'
                or not isinstance(replacement,dict) or set(replacement)!={'path','sha256'}
                or not isinstance(replacement.get('path'),str) or not Path(replacement['path']).is_absolute()
                or not re.fullmatch(r'[a-f0-9]{64}',str(replacement.get('sha256')))):
            raise ActivationError('explicit cost-only replacement protocol/pin required')
    elif authority.get('protocol_version') is not None:
        raise ActivationError('replacement protocol cannot omit its exact permit')
    issued, expires = authority.get("issued_epoch"), authority.get("calendar_expires_epoch")
    resources = authority.get("resources", {})
    wall = resources.get("wall_seconds")
    cpu = resources.get("cpu_seconds", resources.get("aggregate_cpu_seconds"))
    queue = authority.get("max_queue_seconds")
    if (type(issued) not in (int, float) or type(expires) not in (int, float)
            or not math.isfinite(issued) or not math.isfinite(expires)
            or not issued <= now < expires or not 0 < expires - issued <= 7200
            or type(queue) is not int or not 1 <= queue <= 1800
            or resources.get("cpus") != 1 or type(wall) is not int or not 1 <= wall <= PURPOSES[purpose]
            or type(cpu) not in (int, float) or not 0 < cpu <= wall
            or type(resources.get("memory_MiB")) is not int or not 1024 <= resources["memory_MiB"] <= 8192
            or not re.fullmatch(r"[1-9][0-9]*", str(authority.get("slurm_job_id", "")))
            or not re.fullmatch(r"node-[0-9]+", str(authority.get("node", "")))):
        raise ActivationError("finite nonrenewing calendar/queue/allocated resources required")
    if purpose == 'COST_ONLY' and (queue > 180 or wall != 1200 or cpu != 1200
            or resources['memory_MiB'] != 4096):
        raise ActivationError('COST_ONLY requires original1200/4GiB resources and at most180second queue')
    return resources


def validate_replacement_worker(authority,proof_view,now=None):
    """Compute-side scalar binding only; never read controller journals/history."""
    pointer=authority.get('cost_replacement')
    if pointer is None:return None
    from . import cost_control
    document=read_pin(pointer,proof_view)
    value=cost_control.validate_replacement_document_binding(document,authority['plan_sha256'],
        authority['study'],authority['scope_id'],authority['executed_sources'],now=now)
    if (value['new_operational_task_key']!=authority.get('task_key')
            or value['new_control_cpu_scope']!=authority.get('control_cpu_scope')
            or value['resource_policy']!=authority.get('policy_pin')
            or value['resources']!=authority.get('resources')
            or authority['calendar_expires_epoch']>value['expires_epoch']
            or authority['issued_epoch']<value['created_epoch']):
        raise ActivationError('staged replacement permit differs from exact authority scope/source/resources/calendar')
    return value


def allocation_start(allocation, runner=subprocess.run, environ=None, now=None):
    """Require RUNNING server identity; never trust a pending estimated start."""
    environ = dict(os.environ if environ is None else environ, TZ="UTC")
    now = time.time() if now is None else now
    result = runner(["scontrol", "show", "job", allocation["job_id"], "-o"],
                    text=True, capture_output=True, check=True, timeout=10, env=environ)
    fields = dict(re.findall(r"(\w+)=([^\s]+)", result.stdout))
    if (fields.get("JobId") != allocation["job_id"] or fields.get("JobState") != "RUNNING"
            or fields.get("NodeList") != allocation["node"] or fields.get("NumCPUs") != "1"):
        raise ActivationError("actual single-CPU RUNNING job/node identity required")
    try:
        start = dt.datetime.fromisoformat(fields["StartTime"]).replace(tzinfo=dt.timezone.utc).timestamp()
        recorded = float(environ["SLURM_JOB_START_TIME"])
    except (KeyError, ValueError, OverflowError) as exc:
        raise ActivationError("actual Slurm start epoch and server time required") from exc
    if abs(start - recorded) > 1 or not 0 <= now - start <= 7200:
        raise ActivationError("Slurm environment/server actual starts disagree")
    return start


def validate_worker(authority, activation, allocation, purpose, plan_sha256, executed_sources):
    """Before any model/input import, verify allocation and fresh activation."""
    now = time.time()
    resources = validate_authority(authority, purpose, plan_sha256, executed_sources, now)
    actual = require_compute()
    if actual != allocation or authority["slurm_job_id"] != actual["job_id"] or authority["node"] != actual["node"]:
        raise ActivationError("worker allocation differs from bound authority")
    start = allocation_start(actual, now=now)
    if (start - authority["issued_epoch"] > authority["max_queue_seconds"]
            or activation.get("schema") != ACTIVATION_SCHEMA or activation.get("status") != "ACTIVATED_ONCE"
            or activation.get('controller') != OWNER
            or activation.get("authority_identity_sha256") != r.identity(authority)
            or activation.get("job_id") != actual["job_id"] or activation.get("node") != actual["node"]
            or activation.get("plan_sha256") != plan_sha256 or not fresh(activation, now)):
        raise ActivationError("fresh one-time activation of the exact allocated job required")
    view = merge_proofs(authority, activation)
    verify_proof_manifest(view)
    validate_replacement_worker(authority,view,now)
    ready = read_pin(activation["ready"], view)
    if (ready.get("schema") != READY_SCHEMA or ready.get("job_id") != actual["job_id"]
            or ready.get("node") != actual["node"] or ready.get("authority_identity_sha256") != r.identity(authority)
            or ready.get('allocation') != actual
            or ready.get("allocation_start_epoch") != start
            or ready.get("release_sha256") != authority.get("release_sha256")
            or not 0 <= activation["observed_epoch"] - ready.get("observed_epoch", 0) <= 30):
        raise ActivationError("exact READY and bounded notification latency required")
    end = min(start + resources["wall_seconds"], authority["calendar_expires_epoch"])
    if activation.get("started_epoch") != start or activation.get("expires_epoch") != end or not start <= now < end:
        raise ActivationError("allocated-start ceiling or original absolute expiry differs")
    gate = validate_qualification(view)
    from . import policy, handoff
    matrix = read_pin(authority["policy_pin"], view)
    policy.validate_policy(matrix, now=now, require_admitted=True, check_files=False)
    validate_policy_sources(matrix, executed_sources)
    closed = read_pin(activation["handoff_receipt"], view)
    handoff.validate_handoff_receipt(closed, matrix, now=now, check_live=False)
    if not fresh(closed, now):
        raise ActivationError("fresh controller-side EE/permit handoff required")
    hosts = read_pin(activation["all_hosts_observation"], view)
    if (hosts.get("status") != "NO_OVERLAP" or hosts.get("controller") != OWNER
            or set(hosts.get('hosts',[])) != {OWNER,'jerez.be.ucsc.edu','hb.ucsc.edu'}
            or not fresh(hosts, now) or hosts.get("scientific_exclusion_key") != authority.get("scientific_exclusion_key")
            or hosts.get("overlapping_scientific_claims") != []):
        raise ActivationError("fresh task-specific cross-host exclusive observation required")
    if purpose=='COST_ONLY' and (closed['observed_epoch']<authority['issued_epoch']
            or hosts['observed_epoch']<authority['issued_epoch']):
        raise ActivationError('COST worker requires post-authority handoff and host observations')
    if any(os.environ.get(k) != v for k, v in dict(THREAD_ENV,**REFERENCE_NUMERICAL_ENV).items()):
        raise ActivationError("historical numerical profile must precede imports")
    return dict(gate, started_epoch=start, expires_epoch=end, handoff=closed,
                all_hosts=hosts, resources=resources, proof_view=view)
