"""Strict admission for a new, isolated paired component profiling experiment.

Standard-library metadata only. This module neither submits jobs nor renews
legacy permits. A reviewed new window, exact job attestation, immutable source
closure and separately funded paired allowance precede compute execution.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import subprocess
import time

from .environment import validate_reference_profile_record

OWNER = "muscat.be.ucsc.edu"
PURPOSE = "ACTUAL_COMPONENT_PROFILE"
REQUEST_SCHEMA = "r164_actual_component_profile_request_v1"
AUTHORITY_SCHEMA = "r164_actual_component_profile_authority_v1"
POLICY_SCHEMA = "r164_profile_resource_policy_v1"
SHA = re.compile(r"[a-f0-9]{64}\Z")
MAX_JSON = 16 * 1024**2
REQUEST_FIELDS = {"schema", "purpose", "profile_plan", "cost_plan", "policy",
                  "study", "task", "task_sha256", "stage_root", "execution_order", "storage_mode"}
LIMIT_FIELDS = {"aggregate_cpu_seconds", "wall_seconds", "memory_MiB"}


class AdmissionError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise AdmissionError(message)


def identity(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     allow_nan=False).encode()).hexdigest()


def physical(path):
    p = Path(path)
    require(p.is_absolute() and ".." not in p.parts, "absolute physical path required")
    for part in (p, *p.parents):
        require(not part.is_symlink(), "symlink path forbidden")
    return p


def digest(path):
    h = hashlib.sha256()
    with physical(path).open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def _pairs(pairs):
    d = {}
    for key, value in pairs:
        require(key not in d, "duplicate JSON member")
        d[key] = value
    return d


def read_pin(pin):
    require(isinstance(pin, dict) and set(pin) == {"path", "sha256"}, "exact evidence pin required")
    require(isinstance(pin["sha256"], str) and SHA.fullmatch(pin["sha256"]), "SHA256 required")
    p = physical(pin["path"])
    require(p.suffix == '.json', "JSON-only metadata evidence required")
    fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as f:
        before = os.fstat(f.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid() and before.st_nlink == 1
                and before.st_size <= MAX_JSON, "owned bounded single-link regular JSON required")
        raw = f.read(MAX_JSON + 1)
        require(len(raw) <= MAX_JSON, "JSON grew past bound")
        after = os.fstat(f.fileno())
    def fp(s):
        return s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns
    require(fp(before) == fp(after) == fp(p.lstat()), "evidence changed while reading")
    require(hashlib.sha256(raw).hexdigest() == pin["sha256"], "evidence hash differs")
    def bad(value):
        raise AdmissionError("nonfinite JSON forbidden: " + value)
    def floating(value):
        result = float(value)
        require(math.isfinite(result), "overflowed JSON float forbidden")
        return result
    try:
        result = json.loads(raw, object_pairs_hook=_pairs, parse_constant=bad, parse_float=floating)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise AdmissionError("invalid JSON evidence") from exc
    require(isinstance(result, dict), "JSON object required")
    physical(p)
    return result


def number(v, positive=False):
    return type(v) in (int, float) and math.isfinite(v) and (v > 0 if positive else v >= 0)


def validate_limits(limits):
    require(isinstance(limits, dict) and set(limits) == LIMIT_FIELDS, "exact paired limit fields required")
    require(number(limits["aggregate_cpu_seconds"], True) and limits["aggregate_cpu_seconds"] <= 2000,
            "paired CPU must be positive and at most2000")
    require(type(limits["wall_seconds"]) is int and 0 < limits["wall_seconds"] <= 5400,
            "paired allocated wall must fit5400seconds")
    require(type(limits["memory_MiB"]) is int and 1024 <= limits["memory_MiB"] <= 8192,
            "scientific memory must be explicitly bounded")
    return limits


def allocation_limits(authority, worker):
    limits = authority.get('allocation_limits', {})
    require(set(limits) == {'aggregate_cpu_seconds', 'wall_seconds', 'memory_MiB',
                           'wrapper_cpu_seconds', 'ready_reserve_seconds', 'exit_reserve_seconds'},
            'complete whole-job startup/worker/exit allowances required')
    require(number(limits['aggregate_cpu_seconds'], True) and limits['aggregate_cpu_seconds'] <= 2300
            and number(limits['wrapper_cpu_seconds'], True)
            and worker['aggregate_cpu_seconds'] + limits['wrapper_cpu_seconds'] == limits['aggregate_cpu_seconds'],
            'whole job must fund paired worker plus separate wrapper CPU')
    require(all(type(limits[k]) is int for k in ('wall_seconds', 'memory_MiB', 'ready_reserve_seconds', 'exit_reserve_seconds'))
            and 0 < limits['wall_seconds'] <= 7200
            and limits['memory_MiB'] == worker['memory_MiB']
            and 0 < limits['ready_reserve_seconds'] <= 900 and 10 <= limits['exit_reserve_seconds'] <= 120
            and worker['wall_seconds'] + limits['ready_reserve_seconds'] + limits['exit_reserve_seconds'] == limits['wall_seconds'],
            'whole allocation must include honest READY and finalization wall')
    return limits


def validate_policy(policy, now, read_evidence=None):
    # Local source preparation resolves copied HB-absolute metadata through an
    # exact allowlist. Actual compute always uses the default physical reader.
    reader = read_pin if read_evidence is None else read_evidence
    require(policy.get("schema") == POLICY_SCHEMA and policy.get("status") == "ROOT_ADMITTED_NEW_PROFILE_WINDOW"
            and policy.get("purpose") == PURPOSE and policy.get("controller") == OWNER,
            "distinct admitted profiling policy required")
    require(number(policy.get("created_epoch")) and number(policy.get("expires_epoch"))
            and policy["created_epoch"] <= now < policy["expires_epoch"]
            and policy["expires_epoch"] - policy["created_epoch"] <= 86400,
            "new finite profiling window invalid or expired")
    expected = {"max_workers": 1, "cpus_per_task": 1, "numerical_threads": 1,
                "HB_total_CPU_ceiling": 72, "Jerez_extra_workers": 0, "Muscat_new_numerical_workers": 0}
    require(all(type(policy.get(k)) is int and policy[k] == v for k, v in expected.items()),
            "isolated single-worker HB policy required")
    for key in ("legacy_scope_renewed", "old_charges_refunded", "baseline_allocations_changed", "scientific_rules_changed"):
        require(policy.get(key) is False, "old policy/history cannot change: " + key)
    require(policy.get("profile_only") is True and number(policy.get("new_profile_CPU_budget"), True)
            and policy["new_profile_CPU_budget"] <= 4000, "finite new profile funding required")
    history = reader(policy["prior_history"])
    require(history.get("old_scope_renewed") is False and history.get("old_charges_refunded") is False
            and isinstance(history.get("retained_evidence"), list) and history["retained_evidence"],
            "retained history with immutable prior evidence required")
    for pin in history["retained_evidence"]:
        reader(pin)
    authorization = reader(policy["authorization"])
    require(authorization.get("status") == "ROOT_REVIEWED_R164_NEW_PROFILE_POLICY"
            and authorization.get("user_requested_implementation") is True
            and authorization.get("policy_scientific_identity_sha256") == identity({k: v for k, v in policy.items() if k != "authorization"}),
            "root exact new policy authorization required")
    return policy


def validate_request(request):
    require(isinstance(request, dict) and set(request) == REQUEST_FIELDS
            and request["schema"] == REQUEST_SCHEMA and request["purpose"] == PURPOSE,
            "exact actual-component request required")
    require(request["study"] in ("FI", "DK2") and isinstance(request["task"], str)
            and isinstance(request["task_sha256"], str) and SHA.fullmatch(request["task_sha256"]),
            "exact study/task identity required")
    require(request["execution_order"] == ["reference", "instrumented"]
            and request["storage_mode"] == "DIRECT_RETAINED_SOURCE", "fixed full paired direct-source comparison required")
    root = physical(request["stage_root"])
    require(root.is_dir(), "existing retained input root required")
    plan = read_pin(request["profile_plan"])
    require(plan.get("schema") == "r163_execution_profile_plan_v1"
            and plan.get("purpose") == "PROSPECTIVE_ACTUAL_COMPONENT_PROFILE_PREPARATION"
            and plan.get("numerical_execution_authorized") is False
            and plan.get("full_screening_admitted") is False, "original non-admitting profiling contract required")
    rows = plan.get("studies", {}).get(request["study"], {}).get("tasks", [])
    matches = [r for r in rows if r.get("name") == request["task"]]
    require(len(matches) == 1 and matches[0].get("task_sha256") == request["task_sha256"]
            and matches[0].get("imported") is False, "one exact non-imported complete component required")
    cost = read_pin(request["cost_plan"])
    from . import execution_profile_plan as planning
    require(cost.get("study") == request["study"]
            and request['cost_plan']['sha256'] == planning.CANONICAL[request['study']]['cost_plan']
            and request['cost_plan']['sha256'] == plan['input_pins']['studies'][request['study']]['cost_plan']['sha256'],
            "exact original regional cost-plan identity differs")
    return {"profile_plan": plan, "cost_plan": cost, "task": matches[0]}


def _parent_start_ticks(pid):
    require(type(pid) is int and pid > 1, "exact controller PID required")
    path = Path('/proc') / str(pid)
    require(path.stat().st_uid == os.getuid(), "controller owner differs")
    return int((path / 'stat').read_text().rsplit(')', 1)[1].split()[19])


def _memory_MiB(value):
    match = re.fullmatch(r'([0-9]+)([KMGT]?)', value)
    require(match is not None, "bounded Slurm memory unit required")
    return int(match[1]) * {'K': 1/1024, '': 1, 'M': 1, 'G': 1024, 'T': 1024**2}[match[2]]


def _wall_seconds(value):
    match = re.fullmatch(r'(?:(\d+)-)?(\d+):(\d+):(\d+)', value)
    require(match is not None, "finite Slurm whole-job wall required")
    return int(match[1] or 0)*86400 + int(match[2])*3600 + int(match[3])*60 + int(match[4])


def cgroup_memory_limit():
    """Read only this process's kernel cgroup memory hierarchy."""
    limits = []
    for line in Path('/proc/self/cgroup').read_text().splitlines():
        _, controllers, suffix = line.split(':', 2)
        require(suffix.startswith('/') and '..' not in Path(suffix).parts, "safe own cgroup required")
        if controllers == '':
            mount, name = Path('/sys/fs/cgroup'), 'memory.max'
        elif 'memory' in controllers.split(','):
            mount, name = Path('/sys/fs/cgroup/memory'), 'memory.limit_in_bytes'
        else:
            continue
        root = mount / suffix.lstrip('/')
        for directory in (root, *root.parents):
            if not directory.is_relative_to(mount):
                break
            path = directory / name
            if path.is_file():
                value = path.read_text().strip()
                if value != 'max':
                    require(value.isdigit(), "numeric own cgroup memory bound required")
                    limit = int(value)
                    if 0 < limit < 2**60:
                        limits.append(limit)
    require(limits, "actual Slurm/cgroup memory enforcement is unproved")
    return min(limits)


def scheduler_evidence(allocation):
    """Live scheduler/cgroup facts; invoked on compute before numerical imports."""
    result = subprocess.run(['scontrol', 'show', 'job', '-o', str(allocation['job_id'])],
                            text=True, capture_output=True, timeout=10, check=True)
    fields = dict(re.findall(r'(\S+?)=(\S*)', result.stdout))
    require(fields.get('JobId') == str(allocation['job_id']) and fields.get('JobState') == 'RUNNING'
            and fields.get('NumCPUs') == '1' and fields.get('NumTasks') == '1'
            and fields.get('NumNodes') == '1' and fields.get('Requeue') == '0',
            "live job must be running, single-task/single-CPU, nonrequeueing")
    require(fields.get('Partition') == '128x24' and fields.get('Account') == '128x24'
            and fields.get('QOS') == 'normal', "exact reviewed HB allocation class required")
    value = fields.get('MinMemoryNode') or fields.get('MinMemoryCPU', '')
    return {'job_id': fields['JobId'], 'cpus': 1, 'tasks': 1, 'nodes': 1, 'requeue': False,
            'memory_MiB': _memory_MiB(value), 'wall_seconds': _wall_seconds(fields.get('TimeLimit', '')),
            'cgroup_memory_limit_bytes': cgroup_memory_limit(),
            'end_epoch': time.mktime(time.strptime(fields.get('EndTime', ''), '%Y-%m-%dT%H:%M:%S'))}


def validate_worker(*, request, request_sha256, authority, authority_sha256,
                    attestation, attestation_sha256, allocation, executed_sources,
                    now=None, role="controller"):
    now = time.time() if now is None else now
    require(number(now) and role in ("controller", "reference", "instrumented"), "valid role and clock required")
    for value in (request_sha256, authority_sha256, attestation_sha256):
        require(isinstance(value, str) and SHA.fullmatch(value), "complete packet SHA256s required")
    contract = validate_request(request)
    require(authority.get("schema") == AUTHORITY_SCHEMA
            and authority.get("status") == "ROOT_ADMITTED_COMPONENT_PROFILE_PAIR"
            and authority.get("purpose") == PURPOSE and authority.get("controller") == OWNER,
            "exact profile-pair authority required")
    require(authority.get("phase") in ("QUALIFICATION_PAIR", "MEASUREMENT_PAIR")
            and authority.get("request_sha256") == request_sha256
            and authority.get("policy") == request["policy"], "authority request/policy role mismatch")
    require(re.fullmatch(r"r164-profile-[a-z0-9]{16,64}", str(authority.get("scope_id", ""))), "unique R164 profile scope required")
    policy = validate_policy(read_pin(request["policy"]), now)
    require(number(authority.get("created_epoch")) and number(authority.get("expires_epoch"))
            and policy["created_epoch"] <= authority["created_epoch"] <= now < authority["expires_epoch"] <= policy["expires_epoch"],
            "authority cannot outlive distinct window")
    limits = validate_limits(authority.get("limits"))
    whole_limits = allocation_limits(authority, limits)
    require(authority["expires_epoch"] - now >= (limits["wall_seconds"] if role == "controller" else 0) + whole_limits['exit_reserve_seconds'],
            "whole paired job does not fit absolute authority window")
    require(authority.get("new_model_fits") == 0 and type(authority.get("new_model_fits")) is int
            and authority.get("official_origins") == 0 and type(authority.get("official_origins")) is int,
            "profile cannot admit fitting or official evaluation")
    for key in ("selection_authorized", "repricing_authorized", "automatic_retry", "promotion_authorized"):
        require(authority.get(key) is False, "profile cannot expand science: " + key)
    require(authority.get("job_id") == allocation.get("job_id") and authority.get("node") == allocation.get("node")
            and type(allocation.get("cpus_per_task")) is int and allocation["cpus_per_task"] == 1
            and len(allocation.get("affinity", [])) == 1
            and type(allocation['affinity'][0]) is int,
            "exact one-CPU compute allocation differs")
    require(re.fullmatch(r"[0-9]+", str(allocation.get("job_id", "")))
            and not re.search("login|head|submit", str(allocation.get("node", "")), re.I), "actual compute node required")
    require(isinstance(executed_sources, dict) and executed_sources
            and authority.get("source_files") == executed_sources
            and all(isinstance(v, str) and SHA.fullmatch(v) for v in executed_sources.values()),
            "complete exact executing-source map required")
    for name in ("execution_profile.py", "profile_admission.py", "execution_profile_plan.py", "prefix.py", "benchmark.py", "science.py", "environment.py"):
        require(name in executed_sources, "missing executing source: " + name)
    from .prefix import SOURCE_FILES
    require(set(executed_sources) == set(SOURCE_FILES) | {'execution_profile.py', 'execution_profile_plan.py', 'profile_admission.py'},
            "complete frozen execution closure required")
    require(executed_sources["profile_admission.py"] == digest(Path(__file__)), "admission source differs from executing gate")
    review = read_pin(authority["review"])
    require(review.get("schema") == "r164_profile_source_review_v1" and review.get("status") == "PASS"
            and review.get('authority_contract_sha256') == identity({k: v for k, v in authority.items() if k != 'review'})
            and review.get("request_sha256") == request_sha256 and review.get("policy") == request["policy"]
            and review.get("source_files") == executed_sources and review.get("phase") == authority["phase"]
            and review.get("limits") == limits and review.get('allocation_limits') == whole_limits
            and review.get("whole_component_reference_is_frozen") is True
            and review.get("fixed_reference_then_instrumented") is True
            and review.get("all_old_scopes_and_charges_preserved") is True, "exact independent profile-source review required")
    require(authority.get("attestation_sha256") == attestation_sha256
            and attestation.get("schema") == "r164_profile_job_attestation_v1"
            and attestation.get("status") == "COMPUTE_READY"
            and attestation.get("scope_id") == authority["scope_id"]
            and attestation.get("allocation") == allocation
            and number(attestation.get("observed_epoch"))
            and 0 <= now - attestation["observed_epoch"] <= (300 if role == 'controller' else limits['wall_seconds'] + 300),
            "fresh exact-job compute attestation required")
    output_root = physical(authority['output_root'])
    require('ACTUAL_COMPONENT_PROFILE' in output_root.parts and output_root.name == authority['scope_id'],
            "exact owned scope-specific profile output required")
    if role != 'controller':
        path = output_root / 'execution_identity.json'
        claim = read_pin({'path': str(path), 'sha256': digest(path)})
        for key, value in {'request_sha256': request_sha256, 'authority_sha256': authority_sha256,
                           'attestation_sha256': attestation_sha256, 'executed_sources': executed_sources,
                           'allocation': allocation, 'scope_id': authority['scope_id'],
                           'task_sha256': request['task_sha256']}.items():
            require(claim.get(key) == value, "paired controller claim differs: " + key)
        parent = claim.get('process', {})
        require(parent.get('pid') == os.getppid()
                and _parent_start_ticks(os.getppid()) == parent.get('process_start_ticks'),
                "live exact controller lifetime required for child role")
        invocation = authority.get('invocation', {})
        require(set(invocation) == {'executable', 'working_directory', 'request_path', 'authority_path', 'attestation_path'},
                'reviewed exact controller invocation required')
        expected_argv = [invocation['executable'], '-B', '-m', 'pricefm_hb.execution_profile',
                         '--request', invocation['request_path'], '--authority', invocation['authority_path'],
                         '--attestation', invocation['attestation_path'], '--output', str(output_root)]
        parent_root = Path('/proc') / str(os.getppid())
        command = (parent_root / 'cmdline').read_bytes().rstrip(b'\0').split(b'\0')
        require([x.decode() for x in command] == expected_argv
                and (parent_root / 'exe').resolve() == Path(invocation['executable']).resolve()
                and (parent_root / 'cwd').resolve() == physical(invocation['working_directory']),
                'child parent is not the exact reviewed sequential controller')
    actual = scheduler_evidence(allocation)
    require(0 < actual['memory_MiB'] <= whole_limits['memory_MiB']
            and 0 < actual['cgroup_memory_limit_bytes'] <= whole_limits['memory_MiB'] * 1024**2
            and 0 < actual['wall_seconds'] <= whole_limits['wall_seconds']
            and number(actual.get('end_epoch'), True)
            and now + (limits['wall_seconds'] if role == 'controller' else 0) + whole_limits['exit_reserve_seconds'] < actual['end_epoch'],
            "actual scheduler/cgroup memory/wall exceeds reviewed pair allowance")
    require(attestation.get('scheduler_resources') == actual,
            "attested actual scheduler/cgroup resource envelope differs")
    runtime = attestation.get("runtime", {})
    require(runtime == authority.get("parity_runtime") and runtime.get("status") == "verified"
            and runtime.get("allocation") == allocation and runtime.get("threadpoolctl")
            and all(type(p.get("num_threads")) is int and p['num_threads'] == 1 for p in runtime["threadpoolctl"]), "actual one-thread runtime required")
    validate_reference_profile_record(runtime.get("reference_numerical_profile", {}))
    accepted_native = contract['profile_plan']['studies'][request['study']]['numerical_environment_evidence']
    require(runtime.get('native_library_sha256') == accepted_native.get('native_library_sha256')
            and all(runtime.get('reference_numerical_profile', {}).get(k) == accepted_native.get(k)
                    for k in ('enabled', 'environment', 'numpy_dispatch_targets', 'openblas_architectures')),
            'fresh runtime must match original accepted R163 native numerical profile')
    require(isinstance(runtime.get("native_library_sha256"), dict) and len(runtime["native_library_sha256"]) == 2
            and all(isinstance(v, str) and SHA.fullmatch(v) for v in runtime["native_library_sha256"].values()),
            "two exact loaded native libraries required")
    funding = read_pin(authority["funding"])
    require(funding.get("schema") == "r164_profile_funding_v1"
            and funding.get("scope_id") == authority["scope_id"]
            and funding.get("phase") == authority["phase"]
            and funding.get("status") == "RESERVED_BEFORE_SUBMISSION"
            and number(funding.get("reserved_CPU_seconds"))
            and funding["reserved_CPU_seconds"] >= whole_limits["aggregate_cpu_seconds"]
            and number(funding.get("cumulative_reserved_CPU_seconds"))
            and funding["reserved_CPU_seconds"] <= funding["cumulative_reserved_CPU_seconds"] <= policy["new_profile_CPU_budget"]
            and funding.get("old_claims_reused") is False and funding.get("failed_charges_refunded") is False,
            "new prospectively reserved paired funding required")
    require(funding.get('job_id') == allocation['job_id'] and funding.get('request_sha256') == request_sha256
            and funding.get('source_files') == executed_sources,
            'job/task/source-bound precharged funding required')
    reserved = read_pin(funding['reservation'])
    submitted = read_pin(funding['submission'])
    require(reserved.get('schema') == 'r164_profile_reservation_v1'
            and reserved.get('status') == 'CPU_RESERVED_BEFORE_SUBMISSION'
            and reserved.get('scope_id') == authority['scope_id']
            and reserved.get('request_sha256') == request_sha256
            and reserved.get('phase') == authority['phase']
            and reserved.get('reserved_CPU_seconds') == funding['reserved_CPU_seconds']
            and reserved.get('cumulative_reserved_CPU_seconds') == funding['cumulative_reserved_CPU_seconds']
            and reserved.get('source_files') == executed_sources
            and submitted.get('status') == 'HELD_SUBMISSION_JOB_IDENTIFIED'
            and submitted.get('scope_id') == authority['scope_id']
            and submitted.get('job_id') == allocation['job_id']
            and submitted.get('reservation') == funding['reservation']
            and number(reserved.get('created_epoch')) and number(submitted.get('created_epoch'))
            and reserved['created_epoch'] <= submitted['created_epoch'] <= authority['created_epoch'],
            'immutable reservation and identified held submission order required')
    if authority["phase"] == "MEASUREMENT_PAIR":
        qualification = read_pin(authority["qualification"])
        require(qualification.get("status") == "ACCEPTED_COMPLETE_PAIRED_COMPONENT_QUALIFICATION"
                and qualification.get("source_files") == executed_sources
                and qualification.get("whole_accounting_accepted") is True
                and qualification.get("all_canonical_array_bytes_equal") is True,
                "complete actual-component qualification required before measurement")
        require(review.get('accepted_qualification') == authority['qualification'],
                "independent review must bind actual qualification receipt")
        previous_request = read_pin(qualification['request'])
        previous = validate_request(previous_request)
        require(previous_request['study'] == request['study'] and previous_request['storage_mode'] == request['storage_mode']
                and previous_request['profile_plan']['sha256'] == request['profile_plan']['sha256']
                and previous_request['cost_plan']['sha256'] == request['cost_plan']['sha256']
                and all(qualification.get('parity_runtime', {}).get(k) == runtime.get(k)
                        for k in ('python_version', 'versions', 'executable', 'native_library_sha256', 'reference_numerical_profile')),
                "qualification study/input/storage/native-runtime differs")
        pair = read_pin(qualification['component_pair_result'])
        require(pair.get('status') == 'COMPLETE_PAIRED_PROFILE_NOT_SCREENING_ADMISSION'
                and pair.get('parity_status') == 'PASS_EXACT_WHOLE_COMPONENT_ARRAY_AND_SAMPLER_PARITY'
                and pair.get('execution', {}).get('request_sha256') == qualification['request']['sha256']
                and pair.get('execution', {}).get('task_sha256') == previous['task']['task_sha256'],
                "actual qualification component/result identity differs")
        accounting = read_pin(qualification['whole_accounting'])
        require(accounting.get('status') == 'ACCEPTED_COMPLETE_JOB_ACCOUNTING'
                and accounting.get('job_id') == pair['execution']['allocation']['job_id']
                and accounting.get('source_files') == executed_sources
                and accounting.get('all_raw_outputs_returned_and_verified') is True,
                "qualified pair needs accepted canonical job accounting and raw return")
    return {"limits": limits, "expires_epoch": authority["expires_epoch"],
            "scope_id": authority["scope_id"], "parity_runtime": runtime, "contract": contract,
            "output_root": str(output_root), "scheduler_resources": actual, 'allocation_limits': whole_limits}
