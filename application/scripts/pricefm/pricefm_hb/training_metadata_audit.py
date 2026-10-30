"""Audit saved internal-training JSON without importing a model or opening arrays.

This module only verifies frozen evidence and reproduces the existing equal-three-
split selection. It never registers, promotes or schedules a candidate.
"""
from __future__ import annotations
import argparse
import csv
import datetime as dt
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import resource
import signal
import stat
import time

SCHEMA = "pricefm_saved_training_metadata_audit_v1"
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
LIMITS = {"beta_posterior_sd_rms": 1e-4, "predictor_rms": 1e-6,
          "covariance_whitened_rms": 1e-4, "sigma_relative": 1e-6,
          "rhs_joint_log_rates": 1e-6, "rhs_start_log_precision": 1e-6,
          "elbo_relative": 1e-8}
REGION = re.compile(r"[A-Z][A-Z0-9_]{0,15}\Z")
CANONICAL_REGIONS = frozenset(("AT BE BG CZ DE_LU DK_1 DK_2 EE ES FI FR GR HR HU IT_CALA IT_CNOR IT_CSUD IT_NORD IT_SARD IT_SICI IT_SUD LT LV NL NO_1 NO_2 NO_3 NO_4 NO_5 PL PT RO SE_1 SE_2 SE_3 SE_4 SI SK").split())
MAX_JSON = 16 * 1024 * 1024

class AuditError(ValueError):
    pass

class IntegrityError(AuditError):
    pass

def require(condition, reason):
    if not condition:
        raise AuditError(reason)

def finite(value, name, *, positive=False):
    require(type(value) in (float, int) and math.isfinite(value), name + ": finite number required")
    require(value > 0 if positive else value >= 0, name + ": invalid sign")
    return float(value)

def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key: " + key)
        result[key] = value
    return result

def loads(raw):
    return json.loads(raw, object_pairs_hook=unique_pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(AuditError("nonfinite JSON: " + value)))

def physical(path):
    path = Path(path)
    require(path.is_absolute() and ".." not in path.parts, "absolute physical path required")
    require(not any(x.is_symlink() for x in (path, *path.parents)), "symlink path forbidden")
    return path

def file_bytes(path, *, roots=None):
    path = physical(path)
    require(path.suffix == ".json", "only JSON input payloads may be opened")
    if roots is not None:
        require(any(path.is_relative_to(root) for root in roots), "input outside declared allowlist roots")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as handle:
        before = os.fstat(handle.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid()
                and before.st_nlink == 1 and before.st_size <= MAX_JSON, "unsafe/oversized metadata file")
        raw = handle.read(MAX_JSON + 1)
        after = os.fstat(handle.fileno())
    key = lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns, x.st_ctime_ns)
    physical(path)
    require(key(before) == key(after) == key(path.stat()) and len(raw) == before.st_size, "metadata changed during read")
    return raw

def pin(path):
    return {"path": str(path), "sha256": hashlib.sha256(file_bytes(path)).hexdigest()}

class Inputs:
    def __init__(self, roots):
        self.roots = [physical(x) for x in roots]
        require(all(len(x.parts) >= 5 for x in self.roots), "allowlist root too broad")
        self.used = {}

    def read(self, value):
        try:
            require(type(value) is dict and set(value) == {"path", "sha256"}, "strict two-field input pin required")
            require(type(value["sha256"]) is str and re.fullmatch(r"[0-9a-f]{64}", value["sha256"]), "invalid SHA256")
            raw = file_bytes(value["path"], roots=self.roots)
            require(hashlib.sha256(raw).hexdigest() == value["sha256"], "input pin drift: " + value["path"])
            prior = self.used.setdefault(value["path"], value["sha256"])
            require(prior == value["sha256"], "same path bound to different bytes")
            return loads(raw)
        except (AuditError, OSError, json.JSONDecodeError) as error:
            raise IntegrityError(str(error)) from error

def no_test_flags(value):
    for name in ("test_opened", "test_used_for_selection", "official_test_used_for_selection"):
        require(value.get(name) is None or value.get(name) is False, "official-test evidence forbidden: " + name)
    require(value.get("evidence_scope") in (None, "internal_training"), "mixed evidence scope")

def validate_certificate(certificate, terminal):
    """Classify the original finite AND(formal OR independent) rule unchanged."""
    require(type(certificate) is dict and type(terminal) is dict, "certificate/terminal objects required")
    no_test_flags(terminal)
    require(certificate.get("limits") == LIMITS, "original seven limits changed")
    measures = certificate.get("measures", {})
    checks = certificate.get("checks", {})
    require(set(measures) == set(LIMITS) and set(checks) == set(LIMITS), "seven-measure surface differs")
    ratios = {k: finite(measures[k], k) / LIMITS[k] for k in LIMITS}
    expected = {k: ratios[k] <= 1 for k in LIMITS}
    require(all(type(checks[k]) is bool and checks[k] == expected[k] for k in LIMITS), "certificate check flags contradict measures")
    starts = certificate.get("rhs_reconstruction", {})
    both = starts.get("unit_converged") is True and starts.get("dispersed_converged") is True
    independent = all(expected.values()) and both
    require(type(certificate.get("certified")) is bool and certificate["certified"] == independent,
            "certificate certified flag contradicts original measures/starts")
    formal = terminal.get("formal_converged")
    require(type(formal) is bool and type(terminal.get("finite_core")) is bool, "finite/formal flags required")
    require(type(terminal.get("independent_fixedpoint_certified")) is bool
            and terminal["independent_fixedpoint_certified"] == independent, "terminal independent flag differs")
    require(type(terminal.get("iterations")) is int and 0 < terminal["iterations"] <= 300, "AL300 cap violated")
    require(terminal.get("family") == "al" and terminal.get("initialization_only") is True, "AL initialization contract differs")
    accepted = terminal["finite_core"] and (formal or independent)
    require(terminal.get("computationally_certified") is accepted, "terminal computational flag contradicts finite AND(formal OR independent)")
    return {"accepted_original_rule": accepted, "independent": independent, "formal": formal,
            "finite_core": terminal["finite_core"], "both_RHS_starts": both,
            "ratios": ratios, "failing_gates": [k for k in LIMITS if not expected[k]],
            "iterations": terminal["iterations"]}

def task_identity(task):
    no_test_flags(task)
    require(task.get("kind") == "internal_score", "only fixed internal_score task kind eligible")
    require(type(task.get("split")) is int and task["split"] in (1, 2, 3), "internal split1/2/3 required")
    require(REGION.fullmatch(task.get("region", "")), "region identity missing")
    require(type(task.get("candidate_id")) is str and re.fullmatch(r"[0-9a-f]{64}", task.get("specification_sha256", "")), "candidate source identity missing")
    require(task["candidate_id"].endswith(task["specification_sha256"][:16]), "candidate/specification identity mismatch")
    finite(task.get("tau0"), "tau0", positive=True)
    spec = task.get("spec", {})
    require(spec.get("region") == task["region"] and spec.get("readout") == "pure_all_layers", "pure regional Q-DESN contract differs")
    if task["region"] == "SI":
        require(spec.get("feature_policy") == "target_only" and spec.get("calendar") == "none", "SI target-only/no-calendar contract differs")
    return task["region"], task["candidate_id"], float(task["tau0"]), task["split"]

def verify_seal(inputs, row, task, result, *, result_key="result.json"):
    seal = inputs.read(row["seal"])
    require(seal.get("artifacts", {}).get(result_key) == row["result"]["sha256"], "result not bound by completion seal")
    metadata = seal.get("metadata", {})
    require(metadata.get("task_sha256") == row["task"]["sha256"], "task not bound by completion seal")
    require(re.fullmatch(r"[0-9a-f]{40}", metadata.get("source_head", "")), "frozen producer source head required")
    require(metadata.get("certified") is result.get("certified"), "score seal certification differs")
    return metadata["source_head"]

def score_row(inputs, region, row, expected_head):
    task = inputs.read(row["task"])
    identity = task_identity(task)
    require(identity[0] == region, "region crosswire")
    result = inputs.read(row["result"])
    no_test_flags(result)
    require(type(result.get("split")) is int, "saved score split must be integer")
    finite(result.get("tau0"), "saved score tau0", positive=True)
    require(result.get("candidate_id") == identity[1] and result.get("split") == identity[3]
            and result.get("tau0") == identity[2], "score/result identity crosswire")
    head = verify_seal(inputs, row, task, result)
    require(head == expected_head, "producer source head differs from pinned regional context")
    require(type(result.get("certified")) is bool, "saved score certification required")
    aql = finite(result.get("AQL"), "saved AQL")
    coverage = finite(result.get("coverage_80"), "saved coverage")
    require(coverage <= 1, "coverage outside [0,1]")
    width = finite(result.get("width_80"), "saved width")
    companions = row.get("certificates", [])
    require(len(companions) == 7, "seven AL companions required")
    certs, taus = [], []
    for companion in companions:
        al = inputs.read(companion["task"])
        no_test_flags(al)
        require(al.get("kind") == "internal_al" and (al.get("region"), al.get("candidate_id"),
                al.get("tau0"), al.get("split")) == identity, "AL companion task identity differs")
        tau = finite(al.get("tau"), "tau", positive=True)
        taus.append(tau)
        require(task.get("al_names", {}).get(str(tau)) == al.get("name"), "AL companion not declared by score")
        cert = inputs.read(companion["certificate"])
        terminal = inputs.read(companion["terminal"])
        seal = inputs.read(companion["seal"])
        require(seal.get("artifacts", {}).get("fit/fixedpoint_certificate.json") == companion["certificate"]["sha256"]
                and seal["artifacts"].get("fit/terminal.json") == companion["terminal"]["sha256"]
                and seal.get("metadata", {}).get("task_sha256") == companion["task"]["sha256"], "AL certificate/terminal/task not sealed")
        require(seal["metadata"].get("source_head") == head, "score/AL source-head drift")
        require(terminal.get("tau") == tau and terminal.get("tau0") == identity[2]
                and terminal.get("fold") == identity[3], "AL terminal target crosswire")
        certs.append(validate_certificate(cert, terminal))
    require(tuple(sorted(taus)) == QUANTILES, "duplicate/missing quantile companions")
    eligible = result["certified"] and all(x["accepted_original_rule"] for x in certs)
    clocks = result.get("clock_metrics", [])
    tails = []
    for clock in clocks:
        ex = clock.get("exceedance")
        if type(ex) is list and len(ex) == 7:
            require(all(0 <= finite(x, "exceedance") <= 1 for x in ex), "invalid saved tail frequency")
            tails.append({"lower": 1 - ex[0], "upper": ex[-1]})
    pairs = result.get("origin_clock_pairs")
    require(type(pairs) is int and pairs > 0, "saved origin-clock count required")
    return {"region": region, "candidate_id": identity[1], "tau0": identity[2], "split": identity[3],
            "specification_sha256": task["specification_sha256"], "spec": task["spec"],
            "producer_source_head": head, "AQL": aql, "coverage_80": coverage,
            "width_80": width, "crossing_rate": result.get("crossing_rate"),
            "clock_tail_frequencies": tails, "origin_clock_pairs": pairs,
            "eligible_original_rule": eligible,
            "max_original_gate_ratio": max(v for c in certs for v in c["ratios"].values()),
            "all_independent": all(c["independent"] for c in certs),
            "all_both_RHS_starts": all(c["both_RHS_starts"] for c in certs),
            "score_task": row["task"], "score_result": row["result"], "score_seal": row["seal"]}

def reproduce_selection(rows, frozen):
    groups = {}
    for row in rows:
        key = (row["candidate_id"], row["tau0"])
        group = groups.setdefault(key, {})
        require(row["split"] not in group, "duplicate candidate/split")
        group[row["split"]] = row
    ranked, excluded = [], []
    for (candidate, tau), group in groups.items():
        if set(group) != {1, 2, 3} or not all(x["eligible_original_rule"] for x in group.values()):
            excluded.append({"candidate_id": candidate, "tau0": tau, "reason": "missing_or_uncertified_three_split_group"})
            continue
        heads = {x["producer_source_head"] for x in group.values()}
        specs = {x["specification_sha256"] for x in group.values()}
        require(len(heads) == len(specs) == 1, "source/specification drift across internal splits")
        mean = sum(group[k]["AQL"] for k in (1, 2, 3)) / 3
        ranked.append({"candidate_id": candidate, "tau0": tau, "mean_AQL": mean,
                       "split_AQL": {str(k): group[k]["AQL"] for k in (1, 2, 3)}})
    ranked.sort(key=lambda x: (x["mean_AQL"], x["candidate_id"], x["tau0"]))
    match = None
    if frozen is not None:
        no_test_flags(frozen)
        require(frozen.get("selected_before_test") is True
                and frozen.get("selected_on") == "fold1_train_internal_only_seven_quantile_AL_AQL", "frozen choice lacks training-only provenance")
        if ranked:
            winner = ranked[0]
            match = winner["candidate_id"] == frozen.get("candidate_id") and winner["tau0"] == frozen.get("tau0")
            require(match, "saved frozen winner not reproduced; no replacement authorized")
            saved = next((x for x in frozen.get("ranking", []) if x.get("candidate_id") == winner["candidate_id"] and x.get("tau0") == winner["tau0"]), None)
            require(saved and abs(saved["mean_AQL"] - winner["mean_AQL"]) <= 1e-12, "frozen mean AQL mismatch")
    return {"ranking": ranked, "excluded": excluded, "frozen_winner_reproduced": match, "winner_mutated": False}

def design_provenance(inputs, region, rows, scores, expected_head):
    result = []
    for row in rows:
        value = inputs.read(row["design"])
        task = inputs.read(row["task"])
        seal = inputs.read(row["seal"])
        no_test_flags(value)
        require(value.get("selection_stage") == "inner_training_only", "design is not internal training")
        require(value.get("region") == task.get("region") == region and value.get("split") == task.get("split")
                and value.get("source_specification_sha256") == task.get("specification_sha256"), "design identity mismatch")
        require(task.get("kind") == "internal_design", "wrong design task kind")
        require(seal.get("artifacts", {}).get("design/design.json") == row["design"]["sha256"]
                and seal.get("metadata", {}).get("task_sha256") == row["task"]["sha256"]
                and seal["metadata"].get("source_head") == expected_head, "design/source/task not bound by original seal")
        matching = [x for x in scores if (x["candidate_id"], x["tau0"], x["split"]) ==
                    (task.get("candidate_id"), task.get("tau0"), task.get("split"))]
        require(not matching or all(x["specification_sha256"] == value["source_specification_sha256"] for x in matching), "design and score specification crosswire")
        end = value.get("response_end_exclusive")
        require(type(end) is str and dt.datetime.fromisoformat(end).tzinfo is not None, "timezone-bound training cutoff missing")
        scaler = None
        if row.get("scaler"):
            scaler = inputs.read(row["scaler"])
            no_test_flags(scaler)
            require(seal["artifacts"].get("design/scaler.json") == row["scaler"]["sha256"], "scaler metadata not sealed")
        boundary = next((scaler[k] for k in ("fit_end_exclusive", "response_end_exclusive", "train_end", "fit_end", "fit_cutoff") if scaler and k in scaler), None)
        result.append({"region": region, "candidate_id": task.get("candidate_id"), "tau0": task.get("tau0"),
                       "split": value["split"], "response_end_exclusive": end,
                       "n": value.get("n"), "p": value.get("p"),
                       "source_specification_sha256": value["source_specification_sha256"],
                       "reservoir_sha256": value.get("audit", {}).get("reservoir_sha256"),
                       "score_crossmatch": bool(matching),
                       "scaler_metadata": row.get("scaler"), "scaler_fit_boundary": boundary,
                       "scaler_fit_boundary_status": "RECORDED_NOT_ARRAY_RECOMPUTED" if boundary else "NOT_RECORDED_IN_AVAILABLE_SAVED_METADATA",
                       "recursive_target_alignment": "NOT_RECOMPUTED_NO_ARRAY_ACCESS",
                       "design": row["design"]})
    return result

def classify_no4(inputs, rows, exclusions, frozen):
    require(frozen.get("status") == "COMPLETE_READONLY_HELD_AND_ACTIVE_FRONTIER_DIAGNOSIS", "wrong NO4 frozen diagnosis")
    require(exclusions == frozen.get("NO4_RHS_precision_exclusions_preserved_count"), "NO4 exclusions differ from pinned diagnosis")
    old = {x["task"]: x for x in frozen["NO4_required_failed_targets"]}
    require(type(exclusions) is int and exclusions == 144, "NO4 original exclusion count must remain144")
    require(len(rows) == 8, "eight required NO4 failures must be explicit")
    output, names = [], set()
    for row in rows:
        task = inputs.read(row["task"])
        name = task.get("name")
        require(name not in names and task.get("region") == "NO_4" and task.get("kind") == "internal_al", "duplicate/wrong NO4 task")
        require(type(task.get("split")) is int and task["split"] in (1, 2, 3)
                and task.get("tau") in QUANTILES, "NO4 original split/quantile surface differs")
        finite(task.get("tau0"), "NO4tau0", positive=True)
        require(name in old and row["certificate"] == old[name]["certificate"]
                and row["terminal"] == old[name]["terminal"], "NO4 task/certificate/terminal differs from frozen failed set")
        names.add(name)
        terminal = inputs.read(row["terminal"])
        cert = inputs.read(row["certificate"])
        require(terminal.get("tau") == task.get("tau") and terminal.get("tau0") == task.get("tau0")
                and terminal.get("fold") == task.get("split"), "NO4 target identity crosswire")
        seal = inputs.read(row["seal"])
        require(seal.get("artifacts", {}).get("fit/fixedpoint_certificate.json") == row["certificate"]["sha256"]
                and seal["artifacts"].get("fit/terminal.json") == row["terminal"]["sha256"]
                and seal.get("metadata", {}).get("task_sha256") == row["task"]["sha256"], "NO4 original failure seal mismatch")
        classification = validate_certificate(cert, terminal)
        require(not classification["accepted_original_rule"], "required failed NO4 fit unexpectedly marked accepted")
        output.append(dict(classification, task=name, split=task.get("split"), tau=task.get("tau"),
                           tau0=task.get("tau0"), candidate_id=task.get("candidate_id"),
                           certificate=row["certificate"], original_failure_remains_authoritative=True))
    require(names == set(old), "NO4 frozen failed task set incomplete")
    pairs = []
    groups = {}
    for row in output:
        groups.setdefault((row["candidate_id"], row["split"], row["tau"]), []).append(row)
    for key, group in sorted(groups.items()):
        if len(group) == 2:
            group.sort(key=lambda x: x["tau0"])
            pairs.append({"candidate_id": key[0], "split": key[1], "tau": key[2],
                          "tau0s": [x["tau0"] for x in group],
                          "max_absolute_difference_in_gate_ratio": max(abs(group[0]["ratios"][k] - group[1]["ratios"][k]) for k in LIMITS),
                          "failing_gate_sets_identical": group[0]["failing_gates"] == group[1]["failing_gates"]})
    return {"required_failed_count": 8, "required_failures": output, "paired_tau_comparisons": pairs,
            "RHS_precision_exclusions_preserved_separately": exclusions, "reruns_authorized": 0,
            "recommendation": "Classify Gaussian/covariance/objective mechanisms before any fit; no automatic eight-target replay."}

def audit(config):
    require(config.get("schema") == SCHEMA, "unknown audit schema")
    source = config.get("source", {})
    require(source.get("path") == str(Path(__file__).absolute())
            and hashlib.sha256(Path(__file__).read_bytes()).hexdigest() == source.get("sha256"), "auditor source pin drift")
    require(time.time() < config["expires_epoch"], "audit authority expired")
    inputs = Inputs(config["allowed_roots"])
    authority = inputs.read(config["authority"])
    require(authority.get("status") == "PROSPECTIVE_PRICEFM_CONTINUATION_IMPLEMENTATION_SCOPE"
            and time.time() < config["expires_epoch"] <= authority["expires_epoch"], "wrong/expired parent authority")
    approved_root = physical(authority["allowed_metadata_output_root"])
    output_root = physical(config["output_root"])
    require(output_root != approved_root and output_root.is_relative_to(approved_root), "output root outside actual parent authority")
    census = inputs.read(config["inventory"])
    require(census.get("schema") == "pricefm_stdlib_metadata_census_v1"
            and {x["region"] for x in census["records"]} == CANONICAL_REGIONS, "wrong pinned regional inventory")
    contexts = {x["region"]: x for x in census["records"]}
    entries = config["regions"]
    names = [x["region"] for x in entries]
    require(len(names) == len(set(names)) == 38 and set(names) == CANONICAL_REGIONS, "exact canonical38region inventory required")
    output, all_rows, designs = [], [], []
    for entry in entries:
        region = entry["region"]
        require(entry["availability"] in ("LOCAL_SNAPSHOT", "COLLECTED_LOCAL_SNAPSHOT", "REMOTE_NOT_OBSERVED", "MISSING_LOCAL_METADATA"), "unknown availability")
        preparation = inputs.read(entry["preparation"]) if entry.get("preparation") else None
        expected_head = (preparation or {}).get("source", {}).get("head") or contexts[region].get("source", {}).get("head")
        if entry.get("scores") or entry.get("designs"):
            require(re.fullmatch(r"[0-9a-f]{40}", expected_head or ""), "authoritative producer source context unobserved")
        rows, issues = [], []
        for score in entry.get("scores", []):
            try:
                rows.append(score_row(inputs, region, score, expected_head))
            except IntegrityError:
                raise
            except AuditError as error:
                issues.append({"task": score["task"], "reason": str(error), "eligibility": False})
        frozen = inputs.read(entry["selection"]).get(region) if entry.get("selection") else None
        selection = reproduce_selection(rows, frozen)
        provenance = design_provenance(inputs, region, entry.get("designs", []), rows, expected_head)
        context = None if preparation is None else {
            "source": preparation.get("source"), "source_sha256": preparation.get("source_sha256"),
            "input_sha256": preparation.get("input_sha256"), "bank_sha256": preparation.get("bank_sha256"),
            "test_used_for_selection": preparation.get("test_used_for_selection"),
            "official_development_test_seen_previously": preparation.get("official_development_test_seen_previously"),
            "scalers_not_opened": True,
        }
        if preparation is not None:
            require(preparation.get("test_used_for_selection") is False, "preparation used official test for selection")
        output.append({"region": region, "host": entry["host"], "availability": entry["availability"],
                       "score_count": len(rows), "eligible_complete_groups": len(selection["ranking"]),
                       "issues": issues, "selection": selection, "preparation_identity": context,
                       "missingness": entry.get("missingness", []),
                       "scaler_boundary_proof": "UNPROVED_FROM_SAVED_METADATA",
                       "new_selection_or_promotion": False})
        all_rows.extend(rows)
        designs.extend(provenance)
    no4 = classify_no4(inputs, config["NO4"]["required_failures"], config["NO4"]["RHS_precision_exclusion_count"],
                       inputs.read(config["NO4"]["frozen_diagnosis"]))
    return {"status": "COMPLETE_SAVED_TRAINING_METADATA_AUDIT_NO_LAUNCH",
            "schema": SCHEMA, "created_epoch": time.time(), "source": source,
            "regions": output, "score_rows": all_rows, "design_provenance": designs, "NO4": no4,
            "input_pins": [{"path": p, "sha256": sha} for p, sha in sorted(inputs.used.items())],
            "uniform_eligibility": "fixed internal_score + sealed source/task/result + seven AL companions + complete1/2/3 + unchanged finite AND(formal OR independent); diagnostics only",
            "limits": ["Saved scalar metadata only; no new scores or loss evaluation", "No binary arrays, model fits, official-test ranking, altered selection, promotion or scheduling", "Missing remote/scaler/target alignment evidence remains explicit; absence is not a passing proof"],
            "new_models": 0, "new_scores": 0, "new_jobs": 0}

def write_new(path, data):
    with path.open("x") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--config-sha256", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    require(os.sched_getaffinity(0) == {31}, "administrativeCPU31 required")
    resource.setrlimit(resource.RLIMIT_CPU, (12, 12))
    signal.alarm(90)
    raw = file_bytes(args.config)
    require(hashlib.sha256(raw).hexdigest() == args.config_sha256, "configuration pin drift")
    config = loads(raw)
    out = physical(args.output)
    allowed_output = physical(config["output_root"])
    require(out != allowed_output and out.is_relative_to(allowed_output), "output outside approved metadata root")
    require(not out.exists(), "audit output must be create-only")
    result = audit(config)
    out.mkdir(mode=0o700)
    write_new(out / "RESULT.json", json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n")
    columns = ("region", "candidate_id", "tau0", "split", "AQL", "coverage_80", "width_80", "origin_clock_pairs", "max_original_gate_ratio", "all_independent", "all_both_RHS_starts", "eligible_original_rule", "producer_source_head")
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=columns)
    writer.writeheader()
    writer.writerows({key: row.get(key) for key in columns} for row in result["score_rows"])
    write_new(out / "TRAINING_SPLITS.csv", buf.getvalue())
    rows = result["regions"]
    brief = "\n".join(f'| {x["region"]} | {x["availability"]} | {x["score_count"]} | {x["eligible_complete_groups"]} | {len(x["issues"])} |' for x in rows)
    report = "# Saved training metadata audit\n\nNo candidate, fit, score or job was created. The existing equal-three-split primary selection was only reproduced, never changed.\n\n| Region | Evidence availability | Valid score rows | Complete eligible groups | Invalid rows |\n|---|---|---:|---:|---:|\n" + brief + "\n\nNO4 retains eight required failures and144 separate RHS precision exclusions. See RESULT.json for component ratios and paired-tau comparisons. Missing remote records, scaler-fit boundaries and recursive target alignment remain unproved. Official tests cannot select a continuation.\n"
    write_new(out / "REPORT.md", report)
    manifest = {"status": "COMPLETE_TRAINING_AUDIT_OUTPUTS", "source": config["source"],
                "config": {"path": str(physical(args.config)), "sha256": args.config_sha256},
                "files": {name: hashlib.sha256((out / name).read_bytes()).hexdigest() for name in ("RESULT.json", "TRAINING_SPLITS.csv", "REPORT.md")},
                "self_CPU_seconds": sum(resource.getrusage(resource.RUSAGE_SELF)[:2]), "new_jobs": 0}
    write_new(out / "MANIFEST.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    fd = os.open(out, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
    print(json.dumps({"status": result["status"], "regions": len(rows), "valid_training_score_rows": len(result["score_rows"]), "output": str(out)}))

if __name__ == "__main__":
    main()
