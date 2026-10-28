"""Prospective FI/DK2 COST_ONLY control, separate from spent qualification grants.

Nothing is submitted on import or prepare-launch. Positive pinned EE delivery,
drain, runtime/parity, source review and site/all-host evidence are mandatory.
All network and Slurm mutations are explicit CLI actions. Held submission lets
Muscat bind the final finite authority to an actual job before releasing it.
"""
from __future__ import annotations

import argparse
import ast
import inspect
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
REPLACEMENT_PROTOCOL = 'r161_cost_replacement_v1'
REPLACEMENT_SCHEMA = 'r161_cost_replacement_authorization_v1'
REPLACEMENT_STATUS = 'ROOT_ADMITTED_ONE_R161_COST_REPLACEMENT'
REPLACEMENT_STAGE_SCHEMA = 'r161_two_phase_replacement_stage_v1'
STAGE_PART_BYTES = 384*1024**2
STAGE_GROUP_BYTES = 192*1024**2


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


def validate_replacement_document_binding(document, plan_sha, study, scope, sources, now=None):
    """Pure worker-safe binding checks; historical proofs stay controller-only."""
    from . import operation_budget as budget
    now=time.time() if now is None else now
    value=document;resources=value.get('resources',{})
    finite=lambda number:type(number) in (int,float) and math.isfinite(number)
    exact_ints=dict(scientific_CPU_seconds=1200,scientific_wall_seconds=1200,control_CPU_reservation=230,
        priced_maximum_CPU=217,parent_CPU_cap=60,parent_lifetimes=7,parent_slice_CPU=8)
    if (value.get('protocol_version')!=REPLACEMENT_PROTOCOL or value.get('schema')!=REPLACEMENT_SCHEMA
            or value.get('status')!=REPLACEMENT_STATUS or value.get('controller')!=OWNER
            or study not in {'FI','DK2'} or value.get('study')!=study
            or value.get('new_plan_sha256')!=plan_sha or not SHA.fullmatch(str(plan_sha))
            or value.get('new_scope_id')!=scope or not re.fullmatch(r'[A-Za-z0-9_-]{8,160}',str(scope))
            or value.get('new_executed_sources')!=sources
            or not isinstance(sources,dict) or not sources
            or any(not SHA.fullmatch(str(sha)) for sha in sources.values())
            or not SHA.fullmatch(str(value.get('new_operational_task_key','')))
            or not SHA.fullmatch(str(value.get('new_legacy_task_key','')))
            or type(value.get('max_new_attempts')) is not int or value.get('max_new_attempts')!=1
            or value.get('old_charges_refunded') is not False or value.get('old_clocks_mutated') is not False
            or value.get('automatic_retry') is not False
            or not finite(value.get('created_epoch')) or not finite(value.get('expires_epoch'))
            or not finite(now) or not 0<=value['created_epoch']<=now<value['expires_epoch']
            or not 0<value['expires_epoch']-value['created_epoch']<=7200
            or not isinstance(resources,dict) or set(resources)!={'cpus','memory_MiB','cpu_seconds','wall_seconds'}
            or type(resources.get('cpus')) is not int or resources.get('cpus')!=1
            or type(resources.get('memory_MiB')) is not int or resources['memory_MiB']!=4096
            or type(resources.get('cpu_seconds')) is not int or resources.get('cpu_seconds')!=1200
            or type(resources.get('wall_seconds')) is not int or resources.get('wall_seconds')!=1200
            or value.get('scientific_CPU_seconds')!=1200 or value.get('scientific_wall_seconds')!=1200
            or value.get('control_CPU_reservation')!=230 or value.get('priced_maximum_CPU')!=217
            or value.get('parent_CPU_cap')!=60 or value.get('parent_lifetimes')!=7 or value.get('parent_slice_CPU')!=8
            or any(type(value.get(name)) is not int or value[name]!=expected for name,expected in exact_ints.items())
            or value.get('operation_limits')!=budget.INITIAL_LIMITS):
        raise GateError('exact finite source-bound one-replacement scientific/control grant required')
    return value


def _replacement_pin(value):
    from .operation_budget import replacement_metadata, BudgetError
    try:return replacement_metadata(value)
    except (BudgetError,OSError,TypeError,KeyError) as exc:
        raise GateError('invalid explicit replacement JSON proof: '+str(exc)) from exc


def _terminal_epoch(claim):
    epochs=[claim.get(name) for name in ('completed_epoch','completed','terminal_epoch')]
    epochs += [event.get('epoch') for event in claim.get('events',[])
        if event.get('to',event.get('to_state'))=='FAILED_RECONCILED']
    finite=[value for value in epochs if type(value) in (int,float) and math.isfinite(value)]
    if not finite:raise GateError('retained terminal failure epoch required')
    return max(finite)


def _validate_failed_replacement_predecessor(value,reference,old_plan):
    """Validate explicit sealed failure or a bound terminal no-job audit."""
    prior=reference['operational'];legacy=reference['legacy'];release=reference['release']
    proof=value.get('prior_failure',{});terminal=max(_terminal_epoch(prior),_terminal_epoch(legacy))
    zero=_replacement_pin(proof.get('zero_arithmetic'))
    if (zero.get('schema')!='r161_zero_arithmetic_evidence_v1'
            or zero.get('status')!='ROOT_VERIFIED_NO_COST_ARITHMETIC' or zero.get('controller')!=OWNER
            or zero.get('prior_legacy_claim_key')!=value['prior_legacy_claim_key']
            or zero.get('prior_operational_claim_key')!=value['prior_operational_claim_key']
            or zero.get('release_sha256')!=value['prior_release']['sha256']
            or zero.get('job_id')!=prior.get('job_id') or zero.get('arithmetic_calls')!=0
            or zero.get('numerical_payload_started') is not False or zero.get('benchmark_outputs_present') is not False
            or type(zero.get('observed_epoch')) not in (int,float) or not math.isfinite(zero['observed_epoch'])
            or not terminal<=zero['observed_epoch']<=value['created_epoch']):
        raise GateError('current exact zero-arithmetic predecessor evidence required')
    if proof.get('kind')=='root_terminal_audit':
        audit=_replacement_pin(proof.get('terminal_audit'))
        bindings=('prior_legacy_claim_key','prior_operational_claim_key','prior_release','prior_plan',
                  'prior_legacy_snapshot','prior_operational_snapshot','paid_control_snapshot')
        if (audit.get('schema')!='r161_terminal_cost_failure_audit_v1'
                or audit.get('status')!='ROOT_VERIFIED_TERMINAL_COST_FAILURE_NO_ARITHMETIC'
                or audit.get('controller')!=OWNER or audit.get('study')!=value['study']
                or any(audit.get(name)!=value[name] for name in bindings)
                or audit.get('job_id')!=prior.get('job_id') or prior.get('job_id') is not None
                or audit.get('state')!='FAILED_RECONCILED' or audit.get('application_accepted') is not False
                or audit.get('arithmetic_calls')!=0 or audit.get('no_active_jobs') is not True
                or audit.get('scientific_CPU_reserved')!=1200 or audit.get('control_CPU_reserved')!=230
                or audit.get('parent_control_violations')!=reference['control_claim'].get('violations',[])
                or type(audit.get('observed_epoch')) not in (int,float)
                or not terminal<=audit['observed_epoch']<=value['created_epoch']):
            raise GateError('exact terminal no-job audit and unchanged paid violations required')
    elif proof.get('kind')=='worker':
        from . import lifecycle
        accounting=_replacement_pin(proof.get('accounting'));worker=_replacement_pin(proof.get('worker_evidence'))
        failure=_replacement_pin(proof.get('worker_failure'));collection=_replacement_pin(proof.get('collection'))
        publication=Path(prior.get('publication',''))
        expected={'accounting':publication/'accounting.json','worker_evidence':publication/'outputs/worker_evidence.json',
                  'worker_failure':publication/'outputs/worker-failure.json','collection':publication/'collection.json'}
        if (not re.fullmatch(r'[1-9][0-9]*',str(prior.get('job_id','')))
                or any(proof[name]['path']!=str(path) for name,path in expected.items())
                or legacy.get('job_id')!=prior['job_id']
                or accounting.get('task_key')!=prior['task_key'] or accounting.get('job_id')!=prior['job_id']
                or accounting.get('release_sha256')!=value['prior_release']['sha256']
                or accounting.get('terminal') is not True or accounting.get('complete') is not False
                or accounting.get('squeue','').strip()
                or worker.get('schema')!='r157_hb_lifecycle_v1' or worker.get('task_key')!=prior['task_key']
                or worker.get('job_id')!=prior['job_id'] or worker.get('release_sha256')!=value['prior_release']['sha256']
                or worker.get('source_hashes')!=release['source_hashes'] or worker.get('application_passed') is not False
                or worker.get('error')!=failure or not failure
                or worker.get('files',{}).get('worker-failure.json')!=proof['worker_failure']['sha256']
                or any(name.startswith('BENCHMARK_TEST/') or name=='payload-process-limits.json' for name in worker.get('files',{}))
                or worker.get('new_model_fits')!=0 or worker.get('official_origins')!=0
                or collection.get('schema')!='r157_hb_lifecycle_v1' or collection.get('task_key')!=prior['task_key']
                or collection.get('application_accepted') is not False or collection.get('no_refund') is not True
                or collection.get('reserved_CPU_seconds')!=1200):
            raise GateError('exact sealed pre-payload failed worker/accounting/publication required')
        parsed=lifecycle.parse_accounting(accounting['sacct_with_times'],prior['job_id'],release['resources'])
        if not parsed['terminal'] or parsed['complete']:
            raise GateError('predecessor accounting must independently parse as terminal failure')
    else:raise GateError('explicit independently bound predecessor failure proof required')
    if value['created_epoch']<terminal:
        raise GateError('replacement authority cannot be backdated before retained failure')


def validate_replacement(replacement_pin,plan,plan_sha,*,state=None,operational_state=None,now=None,phase='preclaim'):
    """One root replacement; no mutation, refund or relaxation of default gates."""
    from . import activation, operation_budget as budget, policy
    now=time.time() if now is None else now
    value=_replacement_pin(replacement_pin)
    validate_replacement_document_binding(value,plan_sha,plan.get('study'),plan.get('claim',{}).get('planned_attempt_id'),
        activation.executed_sources('COST_ONLY'),now)
    if phase not in {'preclaim','reserve','own'}:raise GateError('explicit replacement validation phase required')
    if state is None:state=Ledger().snapshot()
    if operational_state is None:
        operational_state=_replacement_pin(pin(CENTRAL/'activation_registry.json'))
    if state.get('schema')!=SCHEMA or state.get('owner')!=OWNER or operational_state.get('schema')!='r157_hb_lifecycle_v1' or operational_state.get('owner')!=OWNER:
        raise GateError('canonical cost/operational state identity required')
    spec=value.get('new_control_cpu_scope',{})
    if (not isinstance(spec,dict) or set(spec)!={'path','authorization_pin','scope_id'}
            or Path(spec['path']).parent!=CENTRAL or Path(spec['path']).name!=spec['scope_id']+'.control_cpu.json'):
        raise GateError('new canonical04 control scope required')
    authorization=_replacement_pin(spec['authorization_pin']);control=_replacement_pin(pin(spec['path']))
    try:
        roles=budget.recovery_claims(authorization);lineages=budget.validate_replacement_lineage(authorization)
    except (budget.BudgetError,ValueError,OSError,TypeError,KeyError) as exc:
        raise GateError('replacement funding lineage invalid: '+str(exc)) from exc
    expected_role={'purpose':'COST_ONLY','study':plan['study'],'scope_id':value['new_scope_id']}
    if (authorization.get('protocol_version')!=REPLACEMENT_PROTOCOL or lineages is None
            or roles.get(value['new_operational_task_key'])!=expected_role
            or authorization.get('resource_policy')!=value.get('resource_policy')
            or control.get('schema')!=budget.SCHEMA or control.get('owner')!=OWNER
            or control.get('authorization')!=spec['authorization_pin'] or control.get('scope_id')!=spec['scope_id']
            or control.get('kind')!='INITIAL' or control.get('CPU_ceiling')!=720 or control.get('no_refund') is not True
            or control.get('recovery_claims')!=roles
            or control.get('created_epoch',-1)<authorization['created_epoch']
            or not control['created_epoch']<=value['created_epoch']<=now<value['expires_epoch']<=control['expires_epoch']):
        raise GateError('separate prospective04 grant and exact replacement role required')
    outer=_replacement_pin(value['resource_policy']);policy.validate_policy(outer,now=now,check_files=False)
    activation.validate_policy_sources(outer,value['new_executed_sources'])
    if value['expires_epoch']>outer['expires_epoch']:raise GateError('replacement cannot outlive resource policy')
    reference=lineages[plan['study']]
    for name in ('prior_legacy_claim_key','prior_operational_claim_key','prior_legacy_snapshot','prior_operational_snapshot',
                 'prior_release','paid_control_snapshot','paid_control_authorization'):
        if value.get(name)!=reference['reference'][name]:raise GateError('replacement permit differs from exact funding predecessor')
    old_legacy=reference['legacy'];old_operational=reference['operational'];old_plan=_replacement_pin(value.get('prior_plan'))
    if (value['prior_plan']['sha256']!=old_legacy['task']['plan_sha256']
            or value['prior_plan']['path']!=str(Path(old_operational['release_path'])/'plan.json')
            or value['new_scope_id']==old_legacy['scope_id'] or value['new_plan_sha256']==old_legacy['task']['plan_sha256']
            or value['new_operational_task_key']==value['prior_operational_claim_key']
            or value['new_legacy_task_key']!=r.identity(task_identity(plan,plan_sha))
            or value['new_legacy_task_key']==value['prior_legacy_claim_key']
            or plan.get('claim',{}).get('scientific_exclusion_key')!=old_plan.get('claim',{}).get('scientific_exclusion_key')):
        raise GateError('new replacement attempt must preserve scientific identity without old key/scope reuse')
    science=('study','region','canonical_preparation','canonical_config','canonical_dependency','scientific_universe',
             'packages','resources','schedule','all_parent_preflight','input_allowlist','inventory',
             'schedule_summary','dependency_scope','future_full_prefix_pricing')
    if any(plan.get(name)!=old_plan.get(name) for name in science):
        raise GateError('replacement changed original science/preparation/config/parents/schedule/RNG/input membership')
    old_flags={name:item for name,item in old_plan['claim'].items() if name not in {'planned_attempt_id','execution_namespace'}}
    new_flags={name:item for name,item in plan['claim'].items() if name not in {'planned_attempt_id','execution_namespace'}}
    if (old_flags!=new_flags or plan['claim'].get('execution_namespace')!='BENCHMARK_TEST/'+plan['study']+'/'+
            plan['canonical_preparation']['sha256'][:16]+'/'+value['new_scope_id']):
        raise GateError('replacement must preserve all nonidentity claim flags and exact fresh execution namespace')
    for current,snapshot in ((state,reference['legacy_state']),(operational_state,reference['operational_state'])):
        if any(current.get('claims',{}).get(key)!=claim for key,claim in snapshot['claims'].items()):
            raise GateError('retained old claim or violation history changed')
    if state.get('spent_regions')!=reference['legacy_state']['spent_regions']:
        raise GateError('original spent region counter cannot be reset or rewritten')
    _validate_failed_replacement_predecessor(value,reference,old_plan)
    test_roles=[key for key,role in roles.items() if role['purpose']=='CONTROL_TEST']
    test=operational_state.get('claims',{}).get(test_roles[0],{})
    test_release=_replacement_pin(dict(path=str(Path(test.get('release_path',''))/'release.json'),sha256=test.get('release_sha256')))
    qualification=_replacement_pin(authorization['qualification_lineage'])
    expected_tests=[item['prior_failed_claim_key'] for item in qualification['prior_failed_tests']]+[
        qualification['prior_accepted_test']['claim_key'],test_roles[0]]
    if (test.get('state')!='COLLECTED' or test.get('application_accepted') is not True
            or test.get('scope_id')!='r161_control_placement_04' or test.get('task',{}).get('purpose')!='CONTROL_TEST'
            or test_release.get('purpose')!='CONTROL_TEST' or test_release.get('scope_id')!='r161_control_placement_04'
            or test_release.get('source_hashes')!=value['new_executed_sources']
            or test_release.get('control_cpu_scope')!=spec or operational_state.get('spent_tests')!=expected_tests):
        raise GateError('accepted current-source TEST04 and exact preserved qualification history required')
    new_key=value['new_legacy_task_key'];op_key=value['new_operational_task_key']
    own=state.get('claims',{}).get(new_key);operational=operational_state.get('claims',{}).get(op_key)
    replacement_spent=state.get('replacement_spent_regions',{})
    if phase in {'preclaim','reserve'}:
        if own is not None or plan['study'] in replacement_spent:
            raise GateError('one additional replacement allowance is already reserved or spent')
        if phase=='preclaim' and operational is not None:raise GateError('replacement operational intent already exists')
        if phase=='reserve' and (operational is None or operational.get('state')!='RESERVED'):
            raise GateError('exact new reserved operational intent required before scientific reserve')
    else:
        if (own is None or replacement_spent.get(plan['study'])!=new_key
                or own.get('cost_replacement')!=replacement_pin or own.get('replacement_for')!=value['prior_legacy_claim_key']
                or own.get('task')!=task_identity(plan,plan_sha) or own.get('scope_id')!=value['new_scope_id']
                or own.get('reserved_CPU_seconds')!=1200 or own.get('wall_seconds')!=1200):
            raise GateError('exact previously reserved replacement claim and immutable pointer required')
    if operational is not None and (operational.get('task_key')!=op_key or operational.get('scope_id')!=value['new_scope_id']
            or operational.get('task',{}).get('purpose')!='COST_ONLY' or operational.get('task',{}).get('plan_sha256')!=plan_sha
            or operational.get('task',{}).get('study')!=plan['study']
            or operational.get('task',{}).get('scientific_exclusion_key')!=plan['claim']['scientific_exclusion_key']
            or operational.get('cost_replacement')!=replacement_pin or operational.get('resources')!=value['resources']):
        raise GateError('new operational replacement identity/resources/pointer differ')
    if phase=='own' and (operational is None or operational.get('legacy_cost_key')!=new_key):
        raise GateError('replacement requires exact paired current operational claim')
    if any(claim.get('state') not in FINAL and key!=new_key for key,claim in state['claims'].items()):
        raise GateError('another scientific cost owner remains active')
    if any(claim.get('state') not in {'COLLECTED','FAILED_RECONCILED'} and key!=op_key for key,claim in operational_state['claims'].items()):
        raise GateError('another operational owner remains active')
    return value


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

    def reserve(self, plan, plan_sha, release_sha, config_sha, release_path, remote_root, *, replacement_pin=None):
        task = task_identity(plan, plan_sha)
        key = r.identity(task)
        with r.lock(self.root / "cost_only_registry.lock"):
            state = r.read(self.path) if self.path.exists() else {"schema": SCHEMA, "owner": OWNER, "claims": {}, "spent_regions": {}}
            if state.get("schema") != SCHEMA or state.get("owner") != OWNER:
                raise GateError("canonical cost registry identity differs")
            replacement=None
            if replacement_pin is not None:
                operational_state=_replacement_pin(pin(CENTRAL/'activation_registry.json'))
                replacement=validate_replacement(replacement_pin,plan,plan_sha,state=state,operational_state=operational_state,phase='reserve')
                operational=operational_state['claims'][replacement['new_operational_task_key']]
                if (operational.get('release_sha256')!=release_sha or operational.get('config_sha256')!=config_sha
                        or operational.get('release_path')!=str(release_path) or operational.get('remote_root')!=remote_root):
                    raise GateError('scientific replacement reserve must bind the same exact operational release/site')
            if (replacement is None and plan["study"] in state["spent_regions"]) or key in state["claims"]:
                raise GateError("regional one-attempt allowance already spent; no retry/refund")
            if any(claim["state"] not in FINAL for claim in state["claims"].values()):
                raise GateError("another all-host cost claim remains active or ambiguous")
            claim = dict(task_key=key, task=task, scope_id=plan["claim"]["planned_attempt_id"], state="RESERVED",
                         release_sha256=release_sha, config_sha256=config_sha, release_path=str(release_path),
                         remote_root=remote_root, reserved_CPU_seconds=1200, wall_seconds=1200, created=time.time(), events=[])
            if replacement is not None:
                claim.update(replacement_for=replacement['prior_legacy_claim_key'],cost_replacement=replacement_pin)
            state["claims"][key] = claim
            if replacement is None:state["spent_regions"][plan["study"]] = key
            else:state.setdefault('replacement_spent_regions',{})[plan['study']]=key
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
                     "reserved_CPU_seconds", "wall_seconds", "created", "events", "state",'replacement_for','cost_replacement'}
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


def replacement_partition_manifest(release,release_sha):
    """Price two transfer partitions and four bounded verification groups."""
    if not SHA.fullmatch(str(release_sha)):raise GateError('exact staged release SHA required')
    parts=[dict(bytes=0,members=[]) for _ in range(2)]
    groups=[dict(bytes=0,members=[]) for _ in range(4)]
    files=release.get('files',{})
    if not isinstance(files,dict) or not files:raise GateError('complete sealed staging membership required')
    for name,value in sorted(files.items(),key=lambda item:(-item[1]['bytes'],item[0])):
        path=Path(name);size=value['bytes']
        if (path.is_absolute() or not path.parts or '..' in path.parts
                or path.parts[0] in {'outputs','logs','authorization'} or name=='release.json'
                or type(size) is not int or not 0<=size<=STAGE_GROUP_BYTES
                or not SHA.fullmatch(str(value.get('sha256','')))):
            raise GateError('unsafe or oversized sealed replacement staging member')
        for bins in (parts,groups):
            chosen=min(range(len(bins)),key=lambda index:(bins[index]['bytes'],index))
            bins[chosen]['bytes']+=size;bins[chosen]['members'].append(name)
    if any(part['bytes']>STAGE_PART_BYTES for part in parts) or any(group['bytes']>STAGE_GROUP_BYTES for group in groups):
        raise GateError('complete two-part/four-group stage does not fit unchanged priced command ceilings')
    return dict(schema=REPLACEMENT_STAGE_SCHEMA,release_sha256=release_sha,
        pending_manifest='.r161-stage-manifest-'+release_sha+'.pending',parts=parts,verification_groups=groups,
        maximum_partition_bytes=STAGE_PART_BYTES,maximum_verification_group_bytes=STAGE_GROUP_BYTES)


def replacement_make_partitions(release_root,release,plan,destination):
    root=r.no_links(release_root);target=r.no_links(destination)
    if target.exists() or root==target or root in target.parents:
        raise GateError('new partitions outside immutable release required')
    if plan!=replacement_partition_manifest(release,r.digest(root/'release.json')):
        raise GateError('replacement partition plan differs from sealed release')
    manifest_size=(root/'release.json').stat().st_size
    if plan['parts'][1]['bytes']+manifest_size>STAGE_PART_BYTES:
        raise GateError('second partition plus pending manifest cannot fit its fixed transfer cap')
    target.mkdir(parents=True)
    for index,part in enumerate(plan['parts']):
        folder=target/('part'+str(index+1));folder.mkdir()
        for name in part['members']:
            source=r.no_links(root/name)
            if not source.is_file() or source.stat().st_size!=release['files'][name]['bytes']:
                raise GateError('sealed partition member size changed')
            target_file=folder/name;target_file.parent.mkdir(parents=True,exist_ok=True)
            os.link(source,target_file,follow_symlinks=False)
    os.link(root/'release.json',target/'part2'/plan['pending_manifest'],follow_symlinks=False)
    return [target/'part1',target/'part2']


def replacement_verification_script(remote_root,release_sha,pending,index):
    """One metered metadata command per group; publication occurs only last."""
    if type(index) is not int or not 0<=index<4:raise GateError('one of four exact stage verification groups required')
    return '''import hashlib,json,pathlib
root=pathlib.Path(__ROOT__);pending=root/__PENDING__;expected=__SHA__
if root.is_symlink() or any(p.is_symlink() for p in root.parents) or not root.is_dir():raise ValueError('physical release root required')
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for block in iter(lambda:f.read(1048576),b''):h.update(block)
 return h.hexdigest()
if (root/'release.json').exists() or pending.is_symlink() or digest(pending)!=expected:raise ValueError('manifest already published or pending bytes changed')
m=json.loads(pending.read_text());members=m['files'];groups=[dict(bytes=0,members=[]) for _ in range(4)]
for name,v in sorted(members.items(),key=lambda item:(-item[1]['bytes'],item[0])):
 i=min(range(4),key=lambda i:(groups[i]['bytes'],i));groups[i]['bytes']+=v['bytes'];groups[i]['members'].append(name)
index=__INDEX__;selected=groups[index]['members']
if groups[index]['bytes']>192*1024**2:raise ValueError('verification group exceeds declared metadata cap')
for name in selected:
 v=members[name];rel=pathlib.Path(name);p=root/rel
 if rel.is_absolute() or '..' in rel.parts or p.is_symlink() or any(q.is_symlink() for q in p.parents) or p.stat().st_size!=v['bytes'] or digest(p)!=v['sha256']:raise ValueError('staged member differs:'+name)
if index==3:
 paths=list(root.rglob('*'))
 if any(p.is_symlink() or not(p.is_file() or p.is_dir()) for p in paths):raise ValueError('special staging member')
 found={str(p.relative_to(root)) for p in paths if p.is_file()}
 if found!=set(members)|{pending.name}:raise ValueError('unexpected or missing sealed staging membership')
 for name in ('outputs','logs'):
  p=root/name
  if p.exists() and (not p.is_dir() or any(p.iterdir())):raise ValueError('nonempty preexecution namespace')
 pending.rename(root/'release.json')
 for name in ('outputs','logs'):(root/name).mkdir(exist_ok=True)
group_sha=hashlib.sha256(json.dumps({name:members[name] for name in selected},sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
print(json.dumps(dict(status='COMPLETE_VERIFIED_STAGE_GROUP',release_sha256=expected,group_index=index,group_sha256=group_sha,members=len(selected),bytes=groups[index]['bytes'],manifest_published=index==3)))
'''.replace('__ROOT__',repr(remote_root)).replace('__PENDING__',repr(pending)).replace('__SHA__',repr(release_sha)).replace('__INDEX__',repr(index))


def replacement_submit_factory(stage_fn):
    """Preserve stock claim/gates and replace exactly its staging triple."""
    from . import lifecycle
    tree=ast.parse(inspect.getsource(lifecycle.submit_component));function=tree.body[0]
    expected=ast.parse("""transfer(config,release_path,release['remote_root'],link_dest=link_dest)
if remote(config,['sha256sum',release['remote_root']+'/release.json']).split()[0]!=claim['release_sha256']:
 raise a.ActivationError('staged release hash differs')
remote(config,['mkdir',release['remote_root']+'/outputs',release['remote_root']+'/logs'])""").body
    matches=[]
    for node in ast.walk(function):
        if isinstance(node,ast.Try):
            for offset in range(len(node.body)-2):
                if [ast.dump(item,include_attributes=False) for item in node.body[offset:offset+3]]==[
                        ast.dump(item,include_attributes=False) for item in expected]:matches.append((node,offset))
    if len(matches)!=1:raise GateError('exact unchanged stock staging triple required')
    block,offset=matches[0]
    block.body[offset:offset+3]=ast.parse('return stage_reserved_part1(config,release_path,release,claim,ledger)').body
    function.name='reserve_and_stage_replacement_part1';namespace=dict(lifecycle.__dict__)
    namespace['stage_reserved_part1']=stage_fn
    exec(compile(ast.fix_missing_locations(tree),'<r161-qualified-two-phase-stage>','exec'),namespace)
    return namespace[function.name]


def replacement_submission_tail():
    """Compile only the unchanged stock post-STAGED intent/held submission."""
    from . import lifecycle
    body=ast.parse(inspect.getsource(lifecycle.submit_component)).body[0].body
    start=next(index for index,node in enumerate(body) if isinstance(node,ast.Assign)
        and any(isinstance(target,ast.Name) and target.id=='seconds' for target in node.targets))
    function=ast.FunctionDef(name='submit_staged_replacement',args=ast.arguments(posonlyargs=[],
        args=[ast.arg(arg=name) for name in ('ledger','key','release','claim','config')],kwonlyargs=[],kw_defaults=[],defaults=[]),
        body=body[start:],decorator_list=[])
    tree=ast.fix_missing_locations(ast.Module(body=[function],type_ignores=[]));namespace=dict(lifecycle.__dict__)
    exec(compile(tree,'<r161-qualified-stock-held-tail>','exec'),namespace)
    return namespace[function.name]


def _replacement_stage_release(release_path,config_path,phase):
    from . import lifecycle
    lifecycle.owner();root=r.no_links(release_path)
    release=_replacement_pin(pin(root/'release.json'));plan=_replacement_pin(pin(root/'plan.json'))
    if release.get('purpose')!='COST_ONLY' or release.get('cost_replacement') is None:
        raise GateError('explicit first-class replacement release required')
    value=validate_replacement(release['cost_replacement'],plan,release['plan_sha256'],phase=phase)
    if (release.get('task_key')!=value['new_operational_task_key'] or release.get('scope_id')!=value['new_scope_id']
            or release.get('resources')!=value['resources'] or release.get('control_cpu_scope')!=value['new_control_cpu_scope']
            or release.get('policy_pin')!=value['resource_policy'] or release.get('source_hashes')!=value['new_executed_sources']):
        raise GateError('replacement stager cannot change the sealed root intent/resources/source')
    return root,release,ctl.config(config_path),value


def submit_replacement_part1(release_path,config_path,output_root):
    """First8CPU lifetime: stock single reserve and only the first partition."""
    from . import lifecycle
    root,release,config,value=_replacement_stage_release(release_path,config_path,'preclaim')
    output=r.no_links(output_root);phase2=output.with_name(output.name+'-phase2')
    if output.exists() or phase2.exists() or root==output or root in output.parents or root in phase2.parents:
        raise GateError('new independent stage audit directories required')
    release_pin=pin(root/'release.json');plan=replacement_partition_manifest(release,release_pin['sha256'])
    if plan['parts'][1]['bytes']+(root/'release.json').stat().st_size>STAGE_PART_BYTES:
        raise GateError('complete pending-manifest partition cannot fit unchanged transfer cap')
    output.mkdir(parents=True)
    def stage(config,release_path,release,claim,ledger):
        parts=replacement_make_partitions(release_path,release,plan,output/'partitions')
        lifecycle.transfer(config,parts[0],release['remote_root'])
        current=ledger.snapshot()['claims'][release['task_key']];legacy=Ledger().snapshot()['claims'][current['legacy_cost_key']]
        if (current['state']!='RESERVED' or legacy['state']!='RESERVED' or current.get('job_id') or legacy.get('job_id')
                or current.get('cost_replacement')!=release['cost_replacement'] or legacy.get('cost_replacement')!=release['cost_replacement']):
            raise GateError('phase1 must retain exactly one unsubmitted replacement pair')
        packet=dict(schema=REPLACEMENT_STAGE_SCHEMA,status='PART1_COMPLETE_SAME_RESERVED_REPLACEMENT',
            release_pin=release_pin,cost_replacement=release['cost_replacement'],task_key=release['task_key'],
            source_hashes=release['source_hashes'],config_identity=claim['config_sha256'],partition_plan=plan,
            partitions_root=str(output/'partitions'),phase1_output=str(output),phase2_output=str(phase2),
            activation_pin=pin(ledger.path),legacy_pin=pin(Ledger().path),operational_claim=current,legacy_claim=legacy,
            part1_transfer_complete=True,old_charges_refunded=False)
        lifecycle.write_new(output/'PHASE1_RESERVED.json',packet)
        return packet
    try:return replacement_submit_factory(stage)(str(root),config_path)
    finally:lifecycle.finish_parent_contexts()


def submit_replacement_part2(phase1_packet_path,config_path,output_root):
    """Second8CPU lifetime: no reserve; four hashes precede stock submission."""
    from . import lifecycle
    lifecycle.owner();packet_path=r.no_links(phase1_packet_path);packet=_replacement_pin(pin(packet_path))
    output=r.no_links(output_root)
    if (packet.get('schema')!=REPLACEMENT_STAGE_SCHEMA or packet.get('status')!='PART1_COMPLETE_SAME_RESERVED_REPLACEMENT'
            or packet.get('part1_transfer_complete') is not True or packet.get('old_charges_refunded') is not False
            or packet_path.name!='PHASE1_RESERVED.json' or str(packet_path.parent)!=packet.get('phase1_output')
            or output!=r.no_links(packet.get('phase2_output'))
            or output!=packet_path.parent.with_name(packet_path.parent.name+'-phase2') or output.exists()):
        raise GateError('exact unspent phase2 destination and durable phase1 packet required')
    root,release,config,value=_replacement_stage_release(Path(packet['release_pin']['path']).parent,config_path,'own')
    ledger=lifecycle.Ledger();claim=ledger.snapshot()['claims'][release['task_key']];legacy=Ledger().snapshot()['claims'][claim['legacy_cost_key']]
    if (packet['release_pin']!=pin(root/'release.json') or packet['cost_replacement']!=release['cost_replacement']
            or packet['task_key']!=release['task_key'] or packet['source_hashes']!=release['source_hashes']
            or packet['activation_pin']!=pin(ledger.path) or packet['legacy_pin']!=pin(Ledger().path)
            or packet['operational_claim']!=claim or packet['legacy_claim']!=legacy
            or claim['state']!='RESERVED' or legacy['state']!='RESERVED' or claim.get('job_id') or legacy.get('job_id')
            or claim['events'] or legacy['events'] or r.identity(config)!=packet['config_identity']
            or packet['partition_plan']!=replacement_partition_manifest(release,claim['release_sha256'])
            or r.no_links(packet['partitions_root'])!=packet_path.parent/'partitions'):
        raise GateError('phase2 must bind the exact untouched reserved pair/source/config/plan')
    request=_replacement_pin(pin(root/'launch-request.json'));lifecycle.validate_request(request,release)
    # Claim this immutable destination before any I/O. A killed/failed phase2
    # cannot replay its packet by choosing another output path.
    output.mkdir(parents=True)
    lifecycle.write_new(output/'PHASE2_INTENT.json',dict(phase1=pin(packet_path),cost_replacement=release['cost_replacement'],
        task_key=release['task_key'],no_second_reservation=True))
    try:
        lifecycle.bind_control(config,release)
        funding=config['_r157_control_budget'].snapshot()['claims'][release['task_key']]
        if (funding['counts']['transfer']!=1 or funding['counts']['metadata']!=3 or funding['violations']
                or funding['operation_limits']!=value['operation_limits'] or funding['reserved_CPU']!=230
                or funding['parent_CPU_cap']!=60 or funding['priced_command_and_parent_maximum_CPU']!=217):
            raise GateError('phase1 funding counts or complete original price changed')
        if lifecycle.remote(config,['squeue','-h','-u',config['user'],'-o','%i']).strip():
            raise GateError('all other jobs must remain drained before phase2')
        lifecycle.verify_release(root)
        part2=r.no_links(Path(packet['partitions_root'])/'part2')
        for name in packet['partition_plan']['parts'][1]['members']:
            staged=r.no_links(part2/name)
            if staged.stat().st_size!=release['files'][name]['bytes'] or not os.path.samefile(root/name,staged):
                raise GateError('immutable part2 link membership changed')
        if not os.path.samefile(root/'release.json',part2/packet['partition_plan']['pending_manifest']):
            raise GateError('pending release manifest link changed')
        lifecycle.transfer(config,part2,release['remote_root']);seals=[]
        for index,group in enumerate(packet['partition_plan']['verification_groups']):
            seal=json.loads(lifecycle.remote(config,['/usr/bin/python3','-B','-c',replacement_verification_script(
                release['remote_root'],claim['release_sha256'],packet['partition_plan']['pending_manifest'],index)]))
            expected=dict(status='COMPLETE_VERIFIED_STAGE_GROUP',release_sha256=claim['release_sha256'],group_index=index,
                group_sha256=r.identity({name:release['files'][name] for name in group['members']}),
                members=len(group['members']),bytes=group['bytes'],manifest_published=index==3)
            if seal!=expected:raise GateError('exact complete replacement stage verification group required')
            seals.append(seal);lifecycle.write_new(output/('stage-group-'+str(index)+'.json'),seal)
        lifecycle.write_new(output/'stage-seal.json',dict(groups=seals,all_member_hashes_and_membership_verified=True,
            release_pin=packet['release_pin'],cost_replacement=release['cost_replacement']))
        lifecycle.validate_request(request,release)
        ledger.transition(release['task_key'],'RESERVED','STAGED',replacement_stage_seal=pin(output/'stage-seal.json'))
        lifecycle._cost_transition(release['task_key'],'RESERVED','STAGED')
        held=replacement_submission_tail()(ledger,release['task_key'],release,claim,config)
        lifecycle.write_new(output/'HELD.json',dict(schema=REPLACEMENT_STAGE_SCHEMA,status='ONE_REPLACEMENT_INTENT_HELD',
            claim=held,cost_replacement=release['cost_replacement'],phase1=pin(packet_path)))
        return held
    except BaseException as exc:
        current=ledger.snapshot()['claims'][release['task_key']]
        if current['state'] in {'RESERVED','STAGED'}:
            ledger.transition(release['task_key'],current['state'],'AMBIGUOUS',diagnostic='replacement segmented stage interrupted: '+str(exc))
            prior=Ledger().snapshot()['claims'][claim['legacy_cost_key']]
            if prior['state'] in {'RESERVED','STAGED'}:Ledger().transition(prior['task_key'],prior['state'],'AMBIGUOUS',diagnostic='same replacement stage interruption')
        raise
    finally:lifecycle.finish_parent_contexts()


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
    if r.read(path).get("schema") == "r157_hb_release_v1":
        from . import lifecycle
        release = lifecycle.verify_release(claim["release_path"])
    else:
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
    if release.get("schema") == "r157_hb_release_v1":
        from . import lifecycle
        return lifecycle.validate_cost_outputs(outputs, claim, release)
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
