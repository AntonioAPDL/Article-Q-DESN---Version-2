"""Bind existing JSON training evidence into a reproducible audit configuration.

Run on a selected host's saved campaign roots. Other hosts remain unobserved;
explicit previously collected SI files are resolved locally, never via their
logical original Jerez identities.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import resource
import signal
import time

def main():
    resource.setrlimit(resource.RLIMIT_CPU, (8, 8))
    signal.alarm(90)
    require = lambda condition, reason: None if condition else (_ for _ in ()).throw(ValueError(reason))
    require(os.sched_getaffinity(0) == {31}, "administrativeCPU31 required")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--health-root", required=True)
    parser.add_argument("--authority", required=True)
    parser.add_argument("--data-root", required=True)
    parser.add_argument("--si-collected", required=True)
    parser.add_argument("--frozen-no4", required=True)
    parser.add_argument("--output-config", required=True)
    args = parser.parse_args()
    code = Path(__file__).with_name("training_metadata_audit.py").absolute()
    spec = importlib.util.spec_from_file_location("training_metadata_audit_bound_source", code)
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    health, data = audit.physical(args.health_root), audit.physical(args.data_root)
    si, authority = audit.physical(args.si_collected), audit.physical(args.authority)
    frozen = audit.physical(args.frozen_no4)
    cache = {}
    def doc(path):
        path = audit.physical(path)
        if str(path) not in cache:
            raw = audit.file_bytes(path)
            cache[str(path)] = ({"path": str(path), "sha256": hashlib.sha256(raw).hexdigest()}, audit.loads(raw))
        return cache[str(path)][1]
    def pin(path):
        doc(path)
        return cache[str(path)][0]
    auth = doc(authority)
    require(auth["status"] == "PROSPECTIVE_PRICEFM_CONTINUATION_IMPLEMENTATION_SCOPE"
            and time.time() < auth["expires_epoch"], "wrong or expired parent scope")
    output = audit.physical(args.output_config)
    output_root = output.parent
    approved = audit.physical(auth["allowed_metadata_output_root"])
    require(output_root != approved and output_root.is_relative_to(approved), "output outside approved scope")
    census = doc(health / "GLOBAL_CENSUS.json")
    local = doc(health / "MUSCAT_PROGRESS.json")["progress"]
    old_no4 = doc(frozen)
    entries = []
    for record in sorted(census["records"], key=lambda x: x["region"]):
        region = record["region"]
        root = None
        preparation = None
        availability = "REMOTE_NOT_OBSERVED"
        if region == "SI":
            root = si / "campaign"
            preparation = si / "preparation.json"
            availability = "COLLECTED_LOCAL_SNAPSHOT"
        elif record["host"].lower() == "muscat" and region in local:
            root = Path(local[region]["path"]).parent
            audit.physical(root)
            availability = "LOCAL_SNAPSHOT" if root.is_dir() else "MISSING_LOCAL_METADATA"
            candidate = data / "launch_prep" / root.name / "preparation.json"
            preparation = candidate if candidate.is_file() else None
        entry = {"region": region, "host": record["host"], "availability": availability,
                 "scores": [], "designs": [], "missingness": []}
        if root is None:
            entry["missingness"].append("REMOTE_TRAINING_JSON_NOT_COLLECTED")
            entries.append(entry)
            continue
        entry["logical_campaign_root"] = str(root)
        if preparation and preparation.is_file():
            entry["preparation"] = pin(preparation)
        else:
            entry["missingness"].append("PREPARATION_IDENTITY_UNOBSERVED")
        choice = root / "frozen_choices.json"
        if choice.is_file():
            entry["selection"] = pin(choice)
        else:
            entry["missingness"].append("FROZEN_TRAINING_CHOICE_NOT_PRESENT")
        for sealpath in sorted((root / "tasks_done").glob("*_score/completed_evidence.json")):
            name = sealpath.parent.name
            taskpath = root / "tasks" / (name + ".json")
            resultpath = sealpath.parent / "result.json"
            if not taskpath.is_file() or not resultpath.is_file():
                entry["missingness"].append("INCOMPLETE_SCORE_SOURCE:" + name)
                continue
            task = doc(taskpath)
            if task.get("kind") != "internal_score":
                continue
            score = {"task": pin(taskpath), "result": pin(resultpath), "seal": pin(sealpath), "certificates": []}
            complete = True
            for tau, alname in sorted(task.get("al_names", {}).items(), key=lambda x: float(x[0])):
                base = root / "tasks_done" / alname
                alpaths = {"task": root / "tasks" / (alname + ".json"),
                           "certificate": base / "fit/fixedpoint_certificate.json",
                           "terminal": base / "fit/terminal.json", "seal": base / "completed_evidence.json"}
                if not all(path.is_file() for path in alpaths.values()):
                    complete = False
                    entry["missingness"].append("INCOMPLETE_AL_METADATA:" + alname)
                    break
                score["certificates"].append({role: pin(path) for role, path in alpaths.items()})
            if complete:
                entry["scores"].append(score)
        for design in sorted((root / "tasks_done").glob("*_design/design/design.json")):
            name = design.parent.parent.name
            taskpath = root / "tasks" / (name + ".json")
            sealpath = design.parent.parent / "completed_evidence.json"
            if not taskpath.is_file() or not sealpath.is_file() or doc(taskpath).get("kind") != "internal_design":
                continue
            row = {"task": pin(taskpath), "design": pin(design), "seal": pin(sealpath)}
            scaler = design.parent / "scaler.json"
            if scaler.is_file():
                row["scaler"] = pin(scaler)
            entry["designs"].append(row)
        if not entry["scores"]:
            entry["missingness"].append("NO_COMPLETE_INTERNAL_SCORE_JSON_GROUPS")
        entries.append(entry)
    require({x["region"] for x in entries} == audit.CANONICAL_REGIONS, "inventory mismatch")
    no4_rows = []
    no4root = data / "campaigns/pricefm_stage_r141_recovery_rollout_20261019__NO_4"
    for failure in old_no4["NO4_required_failed_targets"]:
        name = failure["task"]
        row = {"task": pin(no4root / "tasks" / (name + ".json")),
               "terminal": pin(no4root / "tasks_done" / name / "fit/terminal.json"),
               "certificate": pin(no4root / "tasks_done" / name / "fit/fixedpoint_certificate.json"),
               "seal": pin(no4root / "tasks_done" / name / "completed_evidence.json")}
        require(row["certificate"] == failure["certificate"] and row["terminal"] == failure["terminal"],
                "NO4 original sealed identity drift")
        no4_rows.append(row)
    roots = [authority.parent, health, si.parent, frozen.parent, data / "campaigns", data / "launch_prep"]
    config = {"schema": audit.SCHEMA, "source": {"path": str(code), "sha256": hashlib.sha256(code.read_bytes()).hexdigest()},
              "authority": pin(authority), "expires_epoch": auth["expires_epoch"],
              "inventory": pin(health / "GLOBAL_CENSUS.json"), "output_root": str(output_root),
              "allowed_roots": [str(x) for x in roots], "regions": entries,
              "NO4": {"frozen_diagnosis": pin(frozen), "required_failures": no4_rows,
                      "RHS_precision_exclusion_count": old_no4["NO4_RHS_precision_exclusions_preserved_count"]},
              "binding_created_epoch": time.time(), "binder_source": {"path": str(Path(__file__).absolute()),
                  "sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},
              "logical_Jerez_paths_followed": False, "new_models_scores_jobs": 0}
    with output.open("x") as handle:
        json.dump(config, handle, sort_keys=True, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    print(json.dumps({"status": "BOUND_EXISTING_TRAINING_JSON_ONLY_NOT_AUDIT_EXECUTION", "config": pin(output),
                      "input_file_count": len(cache), "regions": len(entries),
                      "complete_score_records": sum(len(x["scores"]) for x in entries),
                      "self_CPU_seconds": sum(resource.getrusage(resource.RUSAGE_SELF)[:2])}))

if __name__ == "__main__":
    main()
