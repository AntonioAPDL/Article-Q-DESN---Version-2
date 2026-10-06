#!/usr/bin/env python3
"""Execution-only R123 AL resume; frozen numerical models and scores are reused."""
from __future__ import annotations

import argparse
from contextlib import ExitStack
import fcntl
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
             "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ[name] = "1"

import pandas as pd
import pricefm_r123_recovery as REC
from pricefm_r123_closeout_evidence import authorized_ladders, verified_atom
from pricefm_r123_dependency_queue import (process_identity, same_process, signal_exact,
                                         run_dependencies, choose_cpu_pool, BoundedScorer)

ROOT = Path(__file__).resolve().parents[3]
TAG = "pricefm_stage_r123_dependency_resume_20261006"
THREADS = ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
           "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS", "VECLIB_MAXIMUM_THREADS")
ATOM_FILES = {"beta_mean.bin", "beta_cov.bin", "vb_trace.csv", "parameter_summary.json",
              "diagnostics.json", "terminal.json"}


def load_owner(args):
    sys.path.insert(0, str(args.owner_root / "application/scripts/pricefm"))
    spec = importlib.util.spec_from_file_location("dependency_frozen_owner",
        args.owner_root / "application/scripts/pricefm/441_run_pricefm_stage_r123_certified_successor.py")
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    for actual,wanted in ((args.campaign_root,m.DATA / "campaigns" / m.TAG),
            (args.prep_dir,m.DATA / "launch_prep" / m.TAG),
            (args.parent_campaign,m.DATA / "campaigns" / m.PARENT),
            (args.attempt,m.DATA / "campaigns" / TAG)):
        if actual.resolve() != wanted.resolve(): raise RuntimeError("execution namespace differs from assigned PriceFM lane")
    m.verify(args)
    return m


def own_source():
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
    if not branch.startswith("work/pricefm-") or subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip():
        raise RuntimeError("scheduler requires clean committed dedicated PriceFM branch")
    files = [Path(__file__).resolve(), Path(__file__).with_name("pricefm_r123_dependency_queue.py")]
    return dict(head=head, branch=branch, source_sha256={str(p): REC.digest(p) for p in files})


def nodes(args, m, control):
    records = {}
    rows = REC.rows(args.campaign_root / "rhs/manifest.csv")
    for (candidate, split), tau0 in authorized_ladders(args.campaign_root).items():
        root = args.campaign_root / f"al_internal/{candidate}/split={split}"
        matched = [r for r in rows if r["candidate_id"] == candidate and int(r["split"]) == split
                   and math.isclose(float(r["tau0"]), tau0, rel_tol=1e-10, abs_tol=0)]
        if len(matched) != 1 or not m.normal_valid(matched[0]["output_dir"]):
            raise RuntimeError("unique certified frozen Normal parent required")
        design = root / "design"
        terminal = REC.read(design / "terminal.json")
        for name in ("X", "y"):
            if REC.digest(design / f"{name}.bin") != terminal[f"{name}_sha256"]:
                raise RuntimeError("frozen design changed")
        if terminal["test_opened"] is not False: raise RuntimeError("test boundary differs")
        for tau in m.B.QUANTILE_ORDER:
            key = f"{candidate}/s{split}/q{tau:.2f}"
            parent_tau = m.B.PARENT[tau]
            records[key] = dict(candidate=candidate, split=split, tau0=tau0, tau=tau,
                root=str(root), normal=matched[0]["output_dir"],
                output=str(root / f"quantiles/al/tau={tau:.2f}"),
                contract=str(root / f"contracts/final/tau={tau:.2f}.json"),
                parent=None if parent_tau is None else f"{candidate}/s{split}/q{parent_tau:.2f}")
    if len(records) != 63: raise RuntimeError("frozen 63-node scope differs")
    return records


def expected_contract(args, m, control, node, companion=False):
    root, tau = Path(node["root"]), node["tau"]
    parent_tau = m.B.PARENT[tau]
    parent = Path(node["normal"]) if parent_tau is None else root / f"quantiles/al/tau={parent_tau:.2f}"
    cap = int(control["al_companion_max_iter"] if companion else control["al_final_max_iter"])
    output = root / (f"companions/cap={cap}/tau={tau:.2f}" if companion else f"quantiles/al/tau={tau:.2f}")
    contract = m.quantile_contract(args.prep_dir, control, node["candidate"], node["split"], tau,
        node["tau0"], root / "design", parent, "normal_rhs" if parent_tau is None else "quantile", output, cap)
    path = root / (f"contracts/companions/tau={tau:.2f}.json" if companion else f"contracts/final/tau={tau:.2f}.json")
    if path.exists() and REC.read(path) != contract: raise RuntimeError("frozen AL contract changed")
    return path, contract


def fit_processes(args, m, control, records):
    found = {}
    contracts = {}
    for key,node in records.items():
        contracts[str(Path(node["contract"]).resolve())] = (key,False)
        contracts[str(Path(node["root"]) / f"contracts/companions/tau={node['tau']:.2f}.json")] = (key,True)
    for folder in Path("/proc").iterdir():
        if not folder.name.isdigit(): continue
        identity = process_identity(int(folder.name))
        if not identity or identity["state"] == "Z": continue
        argv = identity["argv"]
        if Path(argv[0]).name not in ("R", "Rscript"): continue
        if not any(arg.startswith(str(args.campaign_root) + "/") for arg in argv): continue
        if "--config" not in argv: raise RuntimeError("unexpected campaign numerical writer")
        config = str(Path(argv[argv.index("--config") + 1]).resolve())
        if config not in contracts or not any(arg == "--file=" + str(args.owner_root /
                "application/scripts/pricefm/420_fit_pricefm_stage_r121_quantile_atom.R") for arg in argv):
            raise RuntimeError("unexpected campaign fit; no adoption or signaling")
        key,companion = contracts[config]
        _, expected = expected_contract(args, m, control, records[key],companion)
        if REC.read(config) != expected: raise RuntimeError("active contract differs")
        if folder.stat().st_uid != os.getuid(): raise RuntimeError("active fit owner differs")
        affinity = sorted(os.sched_getaffinity(identity["pid"]))
        if len(affinity) != 1: raise RuntimeError("active fit must use one logical CPU")
        env = dict(part.split("=", 1) for part in (folder / "environ").read_bytes().decode().split("\0") if "=" in part)
        if any(env.get(name) != "1" for name in THREADS): raise RuntimeError("active numerical threads exceed one")
        if key in found: raise RuntimeError("duplicate active atom")
        found[key] = dict(identity, cpu=affinity[0], config=config,
                          contract_sha256=REC.digest(config), output=expected["output_dir"],companion=companion)
    return found


def completed(args, m, control, records, unsealed=()):
    accepted = set()
    for key, node in records.items():
        output = Path(node["output"])
        if not output.exists(): continue
        if not (output / "successor_output_hashes.json").exists():
            if key not in unsealed: raise RuntimeError("unowned unsealed output; preserved, not rehashed")
            continue
        contract_path, c = expected_contract(args, m, control, node)
        diagnostics = verified_atom(type("AuditArgs", (), {"parent_prep": args.prep_dir})(), m, control,
            Path(node["root"]), node["candidate"], node["split"], node["tau0"], node["tau"], Path(node["normal"]))
        if diagnostics["external_gate_passed"] is True:
            accepted.add(key)
        else:
            pair = Path(node["root"]) / f"paired_cap/tau={node['tau']:.2f}.json"
            if pair.exists():
                verified_atom(type("AuditArgs", (), {"parent_prep": args.prep_dir})(), m, control,
                    Path(node["root"]), node["candidate"], node["split"], node["tau0"], node["tau"],
                    Path(node["normal"]), companion=True)
                if REC.read(pair)["passed"] is True: accepted.add(key)
    return accepted


def reserve_check(args):
    memory = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines()
                  if line.startswith("MemAvailable:")) / 2**20
    disk = shutil.disk_usage(args.campaign_root).free / 2**30
    if min(memory, disk) < 200: raise RuntimeError("200 GiB memory/disk reserve failed")
    return dict(available_memory_gib=memory, free_disk_gib=disk)


def cpu_pool(args, m, active, old_cpus):
    if len(old_cpus) != 15 or len({m.B._physical(cpu) for cpu in old_cpus}) != 15:
        raise RuntimeError("frozen 15-physical-core pool differs")
    usage = m.B._cpu_snapshot(10)
    occupied = {v["cpu"] for v in active.values()}
    foreign = set()
    ours = {v["pid"] for v in active.values()}
    for folder in Path("/proc").iterdir():
        if not folder.name.isdigit() or int(folder.name) in ours: continue
        identity = process_identity(int(folder.name))
        if not identity or not identity["argv"]: continue
        name=Path(identity["argv"][0]).name
        if name not in ("R", "Rscript") and not name.startswith("python"): continue
        try: affinity = os.sched_getaffinity(int(folder.name))
        except ProcessLookupError: continue
        if len(affinity) == 1: foreign.add(m.B._physical(next(iter(affinity))))
    allowed=os.sched_getaffinity(0)
    physical={cpu:m.B._physical(cpu) for cpu in set(usage)|set(old_cpus)|set(allowed)}
    busy={group:max(usage[cpu] for cpu in usage if physical[cpu]==group) for group in set(physical.values())}
    chosen=choose_cpu_pool(old_cpus,occupied,allowed,physical,busy,foreign)
    return chosen, dict(reserve_check(args), cpus=chosen, worker_ceiling=15, at_epoch=time.time())


def audit(args):
    source = own_source(); m = load_owner(args); control = m.verify(args)
    if args.workers != 15 or control["workers"] != 15: raise RuntimeError("worker ceiling must remain 15")
    if (args.campaign_root / "terminal.json").exists() or (args.campaign_root / "blocked.json").exists():
        raise RuntimeError("campaign is already terminal/blocked; no takeover")
    records = nodes(args, m, control)
    running = REC.read(args.campaign_root / "running.json")
    identity = process_identity(running["pid"])
    if not identity or identity["state"] == "Z" or not any(arg == str(args.owner_root /
            "application/scripts/pricefm/441_run_pricefm_stage_r123_certified_successor.py") for arg in identity["argv"]):
        raise RuntimeError("expected frozen Python scheduler is not active")
    if identity["pid"] != args.expected_controller_pid: raise RuntimeError("expected scheduler PID differs")
    active = fit_processes(args, m, control, records)
    done = completed(args, m, control, records, active)
    cpus, resource = cpu_pool(args, m, active, running["cpus"])
    value = dict(tag=TAG, scientific_tag=m.TAG, scheduler_source=source, frozen_owner_head=control["code_head"],
        prep_identity_sha256=REC.digest(args.prep_dir / "identity.json"), nodes=records,
        old_controller=identity, old_cpu_pool=running["cpus"], completed=sorted(done), active=active,
        resource=resource, test_opened=False, official_validation_opened=False,
        execution_only=True, max_workers=15)
    preserved={str(p):REC.digest(p) for key in done for p in Path(records[key]["output"]).iterdir() if p.is_file()}
    for path in sorted((args.campaign_root / "al_internal").glob("*/split=*/successor_ladder_hashes.json")):
        ledger=REC.read(path); REC.verify_evidence(ledger)
        preserved.update(ledger["evidence_sha256"]); preserved[str(path)]=REC.digest(path)
    value["preserved_evidence_sha256"]=preserved
    REC.immutable(args.attempt / "preparation.json", value)
    return dict(status="DEPENDENCY_RESUME_PREPARED", completed=len(done), active=len(active),
                remaining=len(records) - len(done), cpus=cpus)


def takeover(args, m, control, records, preparation):
    expected = preparation["old_controller"]
    if not same_process(expected, process_identity(expected["pid"])):
        raise RuntimeError("old scheduler identity changed; refusing takeover")
    # Only the Python scheduler is paused. Numerical R children retain their state.
    signal_exact(expected, signal.SIGSTOP)
    committed = False
    try:
        for _ in range(50):
            identity = process_identity(expected["pid"])
            if same_process(expected, identity) and identity["state"] == "T": break
            time.sleep(.1)
        else: raise RuntimeError("scheduler pause was not confirmed")
        m.verify(args)
        active = fit_processes(args, m, control, records)
        known = dict(preparation["active"], **active)
        done = completed(args, m, control, records, known)
        adopted = {key: record for key, record in known.items() if key not in done}
        cpus, resource = cpu_pool(args, m, active, preparation["old_cpu_pool"])
        if any(record["cpu"] not in cpus for record in adopted.values()):
            raise RuntimeError("adopted core unavailable")
        receipt = dict(old_controller=expected, adopted=adopted, completed=sorted(done), resource=resource,
                       scheduler_pid=os.getpid(), at_epoch=time.time(), r_children_signaled=False)
        REC.immutable(args.attempt / "transition.json", receipt)
        signal_exact(expected, signal.SIGTERM)
        signal_exact(expected, signal.SIGCONT)
        committed = True
        for _ in range(100):
            identity = process_identity(expected["pid"])
            if not same_process(expected, identity) or identity["state"] == "Z": break
            time.sleep(.1)
        else: raise RuntimeError("old scheduler did not exit")
        return receipt
    finally:
        if not committed and same_process(expected, process_identity(expected["pid"])):
            signal_exact(expected, signal.SIGCONT)


def seal_output(args, m, control, node, record, companion=False):
    path, contract = expected_contract(args, m, control, node, companion)
    if REC.digest(path) != record["contract_sha256"]: raise RuntimeError("executed contract changed")
    output = Path(contract["output_dir"])
    if (output / "successor_output_hashes.json").exists():
        if not m.quantile_valid(output,contract["posterior_target_sha256"]):
            raise RuntimeError("sealed atom is not valid")
        return
    if {p.name for p in output.iterdir()} != ATOM_FILES:
        raise RuntimeError("fit is incomplete or has unexpected files; no refit")
    terminal = REC.read(output / "terminal.json")
    if terminal.get("status") != "completed_r121_quantile_atom" or terminal.get("posterior_target_sha256") != contract["posterior_target_sha256"]:
        raise RuntimeError("fit did not complete its authorized target")
    for name in ("atom_id","tag","stage","readout","family","fold","split","tau","tau0"):
        if terminal.get(name) != contract[name]: raise RuntimeError("completed atom identity differs")
    if terminal.get("initialization_only") is not True or any(terminal.get(name) is not False for name in
            ("prior_center_from_initializer","initializer_changes_prior","test_opened","registry_mutated",
             "article_mutated","joint_model_fitted","mcmc_fitted","exal_fitted")):
        raise RuntimeError("completed atom prior/scope differs")
    if terminal.get("package_version") != "1.1.1" or terminal.get("package_repository") != "CRAN":
        raise RuntimeError("completed atom package differs")
    p = int(terminal["p"])
    if (output / "beta_mean.bin").stat().st_size != 8*p or (output / "beta_cov.bin").stat().st_size != 8*p*p:
        raise RuntimeError("compact coefficient dimensions differ")
    hashes = {p.name: REC.digest(p) for p in output.iterdir() if p.is_file()}
    REC.immutable(args.attempt / "sealed" / f"{contract['atom_id']}.json",
                  dict(process=record, output_sha256=hashes, source_head=control["code_head"]))
    REC.immutable(output / "successor_output_hashes.json", hashes)


def seal_adopted(args, m, control, node, record):
    while True:
        identity = process_identity(record["pid"])
        if not same_process(record, identity) or identity["state"] == "Z": break
        time.sleep(5)
    seal_output(args,m,control,node,record,record.get("companion",False))


def config_active(config):
    for folder in Path("/proc").iterdir():
        if not folder.name.isdigit(): continue
        identity = process_identity(int(folder.name))
        if not identity or identity["state"] == "Z": continue
        argv = identity["argv"]
        if Path(argv[0]).name in ("R","Rscript") and "--config" in argv \
                and argv[argv.index("--config")+1] == str(config): return True
    return False


def run_atom(args,m,control,node,cpu,path,contract,companion=False):
    output = Path(contract["output_dir"])
    if output.exists() or config_active(path): raise RuntimeError("existing/active atom preserved; no duplicate fit")
    log = Path(node["root"]) / f"logs/{'companion' if companion else 'final'}_tau={node['tau']:.2f}.log"
    command = ["taskset","-c",str(cpu),control["rscript"],str(args.owner_root /
        "application/scripts/pricefm/420_fit_pricefm_stage_r121_quantile_atom.R"),"--config",str(path)]
    log.parent.mkdir(parents=True,exist_ok=True)
    with log.open("a") as handle:
        handle.write("$ " + " ".join(command) + "\n"); handle.flush()
        child = subprocess.Popen(command,cwd=args.owner_root,env=dict(os.environ),stdout=handle,stderr=subprocess.STDOUT)
        record = None
        for _ in range(100):
            identity = process_identity(child.pid)
            if identity and Path(identity["argv"][0]).name == "R" and "--config" in identity["argv"] \
                    and any(arg == "--file=" + str(args.owner_root /
                        "application/scripts/pricefm/420_fit_pricefm_stage_r121_quantile_atom.R") for arg in identity["argv"]):
                record = dict(identity,cpu=cpu,config=str(path),contract_sha256=REC.digest(path),output=str(output),companion=companion)
                REC.immutable(args.attempt / "launched" / f"{contract['atom_id']}.json",record)
                break
            if child.poll() is not None: break
            time.sleep(.05)
        if record is None: raise RuntimeError("new numerical worker identity unavailable; preserved, never killed")
        if child.wait() != 0: raise RuntimeError("numerical worker failed; evidence preserved")
    seal_output(args,m,control,node,record,companion)


def execute_node(args, m, control, node, cpu, adopted=None):
    path, contract = expected_contract(args, m, control, node)
    REC.immutable(path, contract)
    if adopted is not None: seal_adopted(args, m, control, node, adopted)
    output = Path(contract["output_dir"])
    if not m.quantile_valid(output, contract["posterior_target_sha256"]):
        run_atom(args,m,control,node,cpu,path,contract)
    diagnostics = verified_atom(type("AuditArgs", (), {"parent_prep": args.prep_dir})(), m, control,
        Path(node["root"]), node["candidate"], node["split"], node["tau0"], node["tau"], Path(node["normal"]))
    if diagnostics["external_gate_passed"] is True: return True
    path, companion = expected_contract(args, m, control, node, companion=True)
    REC.immutable(path, companion)
    if not m.quantile_valid(companion["output_dir"], companion["posterior_target_sha256"]):
        run_atom(args,m,control,node,cpu,path,companion,companion=True)
    pair = m.B.paired_cap_predictive_stability(Path(node["root"]) / "design", Path(companion["output_dir"]), output)
    REC.immutable(Path(node["root"]) / f"paired_cap/tau={node['tau']:.2f}.json", pair)
    return pair["passed"] is True


def controller(args):
    preparation = REC.read(args.attempt / "preparation.json")
    if own_source() != preparation["scheduler_source"]: raise RuntimeError("prepared scheduler source changed")
    REC.verify_evidence({"evidence_sha256":preparation["preserved_evidence_sha256"]})
    m = load_owner(args); control = m.verify(args)
    if REC.digest(args.prep_dir / "identity.json") != preparation["prep_identity_sha256"]:
        raise RuntimeError("frozen preparation changed")
    records = nodes(args, m, control)
    if records != preparation["nodes"]: raise RuntimeError("authorization changed")
    transition=args.attempt / "transition.json"
    if transition.exists() and not same_process(preparation["old_controller"],
            process_identity(preparation["old_controller"]["pid"])):
        previous=REC.read(args.campaign_root / "running.json")
        identity=process_identity(previous["pid"])
        if identity and identity["state"] != "Z" and previous["pid"] != os.getpid():
            raise RuntimeError("another controller is active; refusing duplicate resume")
        if previous.get("scheduler_attempt") != str(args.attempt):
            raise RuntimeError("resume attempt does not own previous controller")
        old=REC.read(transition)
        known=dict(old["adopted"])
        by_config={v["contract"]:k for k,v in records.items()}
        by_config.update({str(Path(v["root"]) / f"contracts/companions/tau={v['tau']:.2f}.json"):k for k,v in records.items()})
        for path in sorted((args.attempt / "launched").glob("*.json")):
            record=REC.read(path)
            if record["config"] not in by_config or REC.digest(record["config"]) != record["contract_sha256"]:
                raise RuntimeError("saved numerical worker provenance changed")
            known[by_config[record["config"]]]=record
        active=fit_processes(args,m,control,records); known.update(active)
        done=completed(args,m,control,records,known)
        adopted={key:record for key,record in known.items() if key not in done}
        cpus,resource=cpu_pool(args,m,active,preparation["old_cpu_pool"])
        receipt=dict(old,adopted=adopted,completed=sorted(done),resource=resource)
    else:
        receipt = takeover(args, m, control, records, preparation)
    with ExitStack() as stack:
        for path in (args.campaign_root / "controller.lock", args.parent_campaign / "controller.lock",
                     args.parent_campaign / "recovery_controller.lock"):
            handle = stack.enter_context(path.open("a+"))
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        cpus = receipt["resource"]["cpus"]
        REC.write(args.campaign_root / "running.json", dict(pid=os.getpid(), cpus=cpus,
            source_head=control["code_head"], scheduler_head=preparation["scheduler_source"]["head"],
            scheduler_attempt=str(args.attempt), started_at_epoch=time.time(), test_opened=False))
        run_dependencies({k:v["parent"] for k,v in records.items()}, receipt["completed"], receipt["adopted"], cpus,
            lambda key,cpu,record: execute_node(args,m,control,records[key],cpu,record),
            lambda value: REC.write(args.attempt / "progress.json", value), lambda: reserve_check(args))
        if fit_processes(args,m,control,records): raise RuntimeError("numerical writer remains before scoring")
        # The original frozen scoring code may reuse fits only, never start another fit.
        def forbid_fit(*args, **kwargs): raise RuntimeError("unexpected refit during frozen scoring")
        m.B._command = forbid_fit
        m.B._al_ladder=BoundedScorer(m.guarded_ladder,cpus)
        chosen = pd.DataFrame(REC.read(args.campaign_root / "al_launch_authorization.json")["selected"])
        score_slots=[cpus[index%len(cpus)] for index in range(9)]
        al = m.B._run_al(args.prep_dir,args.campaign_root,args.owner_root,score_slots,chosen)
        m.verify(args); REC.verify_evidence(REC.read(args.prep_dir / "protected_parent.json"))
        REC.verify_evidence({"evidence_sha256":preparation["preserved_evidence_sha256"]})
        result = dict(status="R123_CERTIFIED_INTERNAL_COMPLETE_TEST_BLOCKED",tag=m.TAG,
            center_checks=len(REC.read(args.prep_dir / "center_jobs.json")),
            complete_center_candidates=len({r["candidate_id"] for r in REC.read(args.campaign_root / "rhs/center/selection.json")["ranking"]}),
            tau_attempts=len(REC.read(args.campaign_root / "rhs/pilot/jobs.json")), complete_al_families=len(al),
            source_head=control["code_head"], parent_evidence_unchanged=True,test_opened=False,
            official_validation_opened=False,registry_mutated=False,article_mutated=False,
            integration_status="NOT_READY_FOR_INTEGRATION")
        REC.immutable(args.attempt / "terminal.json", dict(result,scheduler_head=preparation["scheduler_source"]["head"]))
        REC.immutable(args.attempt / "completed_evidence.json", {"evidence_sha256": {
            str(p):REC.digest(p) for p in sorted(args.attempt.rglob("*")) if p.is_file()
            and p.name not in ("completed_evidence.json","controller.log") and not p.name.endswith(".tmp")}})
        REC.immutable(args.campaign_root / "terminal.json",result)
        REC.immutable(args.campaign_root / "completed_evidence.json", {"evidence_sha256": {
            str(p):REC.digest(p) for p in sorted(args.campaign_root.rglob("*")) if p.is_file()
            and p.name not in ("completed_evidence.json","controller.lock","controller.log") and not p.name.endswith(".tmp")}})
        return result


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode",choices=("prepare","controller"),required=True)
    p.add_argument("--owner-root",type=Path,required=True)
    p.add_argument("--frozen-code-root",type=Path,required=True)
    p.add_argument("--prep-dir",type=Path,required=True)
    p.add_argument("--campaign-root",type=Path,required=True)
    p.add_argument("--parent-campaign",type=Path,required=True)
    p.add_argument("--attempt",type=Path,required=True)
    p.add_argument("--expected-controller-pid",type=int,required=True)
    p.add_argument("--workers",type=int,default=15)
    return p


if __name__ == "__main__":
    args = parser().parse_args()
    try: print(json.dumps(audit(args) if args.mode == "prepare" else controller(args),sort_keys=True))
    except Exception as error:
        REC.write(args.attempt / "blocked.json",dict(error_type=type(error).__name__,error=str(error),
            at_epoch=time.time(),test_opened=False,numerical_children_stopped=False))
        raise
