"""Bounded saved-training JSON collection and immutable packet materialization.

Remote collection is Python3.6 compatible, read-only and has no child processes.
Local mode creates one authoritative durable packet and reconstructible JSON
cache, then a new audit configuration. Existing audit01 evidence is untouched.
"""
import argparse
import base64
import copy
import gzip
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
import sys
import time

SCHEMA = "pricefm_jerez_training_collection_v1"
REGIONS = set("BE CZ DK_1 ES FR HR IT_CNOR IT_NORD IT_SARD IT_SUD LV NO_1 NO_3 NO_5 PT SE_1 SE_3 SK".split())
TOKEN = re.compile(r"[A-Za-z0-9_.-]+\Z")
QUANTILES = set((0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90))
DATA = "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm"

def require(value, reason):
    if not value:
        raise ValueError(reason)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def pairs(values):
    result = {}
    for key, value in values:
        require(key not in result, "duplicate JSON key:" + key)
        result[key] = value
    return result

def loads(raw):
    def nonfinite(value):
        raise ValueError("nonfinite JSON:" + value)
    def finite_float(text):
        value = float(text)
        require(math.isfinite(value), "nonfinite JSON float")
        return value
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=nonfinite, parse_float=finite_float)

def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")

def physical(path):
    path = Path(path)
    require(path.is_absolute() and ".." not in path.parts, "absolute physical path required")
    require(not any(x.is_symlink() for x in [path] + list(path.parents)), "symlink path")
    return path

def below(path, root):
    return os.path.commonpath((str(path), str(root))) == str(root)

def fingerprint(value):
    return [value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_ctime_ns, stat.S_IMODE(value.st_mode)]

def read_json(path, maximum, allowed_root=None):
    path = physical(path)
    require(path.suffix == ".json", "JSON inputs only")
    require(allowed_root is None or below(path, allowed_root), "outside source root")
    fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as handle:
        before = os.fstat(handle.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid()
                and before.st_nlink == 1 and before.st_size <= maximum, "unsafe or oversized JSON")
        raw = handle.read(maximum + 1)
        after = os.fstat(handle.fileno())
    physical(path)
    require(fingerprint(before) == fingerprint(after) == fingerprint(path.stat())
            and len(raw) == before.st_size, "source changed during read")
    return raw, loads(raw), fingerprint(before)

def no_test(value):
    require(isinstance(value, dict), "metadata object required")
    for name in ("test_opened", "test_used_for_selection", "official_test_used_for_selection"):
        require(value.get(name) is None or value.get(name) is False, "test evidence flag:" + name)
    require(value.get("evidence_scope") in (None, "internal_training"), "mixed test evidence scope")

def validate_plan(plan, require_live=True):
    require(plan.get("schema") == SCHEMA and plan.get("status") == "ROOT_AUTHORIZED_PRICEFM_ONLY_JEREZ_COLLECTION", "actual root collection authorization required")
    if require_live:
        require(time.time() + 120 < plan["expires_epoch"], "complete collection must fit current scope")
    require(plan.get("data_root") == DATA, "wrong PriceFM root")
    require(re.fullmatch(r"jerez-training-[0-9a-f]{32}", plan.get("collection_id", "")), "unique collection ID required")
    require(len(plan["regions"]) == 18 and set(x["region"] for x in plan["regions"]) == REGIONS, "exact18Jerez inventory required")
    require(plan.get("maximum_files") == 5120 and plan.get("maximum_source_JSON_bytes") == 2097152
            and plan.get("maximum_payload_bytes") == 67108864 and plan.get("maximum_encoded_pack_bytes") == 100663296
            and plan.get("maximum_compressed_bytes") == 8388608, "fixed metadata shape limits changed")
    require(len(plan.get("SI_scaler_supplements", [])) == 6, "six exact SI scaler supplements required")
    for name, expected in (("local_transport_CPU", 6), ("remote_CPU", 6),
                           ("local_transport_wall", 120), ("remote_wall", 120)):
        require(type(plan.get(name)) is int and plan[name] == expected, "fixed local/remote CPU6wall120 binding:" + name)
    for entry in plan["regions"]:
        root = physical(entry["root"])
        require(below(root, Path(DATA) / "campaigns") and root != Path(DATA) / "campaigns", "wrong campaign root")
        prep = physical(entry["preparation"])
        require(prep == Path(DATA) / "launch_prep" / root.name / "preparation.json", "wrong preparation path")
        require(re.fullmatch(r"[0-9a-f]{40}", entry.get("expected_source_head", "")), "producer source context required")
    return plan

class Collector:
    def __init__(self, plan):
        self.plan = plan
        self.files = {}
        self.originals = {}
        self.total = 0

    def original(self, path, root):
        path = str(physical(path))
        if path in self.originals:
            return self.originals[path]
        raw, value, identity = read_json(path, self.plan["maximum_source_JSON_bytes"], root)
        result = (raw, value, identity)
        self.originals[path] = result
        return result

    def add(self, region, relative, path, root, role="BYTE_EXACT_ORIGINAL_JSON", projection=None):
        require(TOKEN.fullmatch(region), "unsafe region alias")
        relative = Path(relative)
        require(not relative.is_absolute() and ".." not in relative.parts
                and relative.suffix == ".json" and all(TOKEN.fullmatch(x) for x in relative.parts), "unsafe relative JSON path")
        identity = region + "/" + str(relative)
        raw, value, file_id = self.original(path, root)
        original_sha = sha(raw)
        if projection is not None:
            raw = encoded(projection)
            require(role == "DERIVED_TRAINING_CONTEXT_NOT_ORIGINAL_BYTE_COPY", "projection role must be explicit")
        record = {"id": identity, "region": region, "relative": str(relative), "role": role,
                  "original": {"path": str(path), "sha256": original_sha, "fingerprint": file_id},
                  "bytes": len(raw), "sha256": sha(raw), "base64": base64.b64encode(raw).decode("ascii")}
        if identity in self.files:
            require(self.files[identity] == record, "same collection alias bound twice")
        else:
            self.total += len(raw)
            require(len(self.files) + 1 <= self.plan["maximum_files"] and self.total <= self.plan["maximum_payload_bytes"], "metadata collection shape cap")
            self.files[identity] = record
        return {"id": identity, "sha256": record["sha256"]}

    def snapshot_stable(self):
        for path, item in self.originals.items():
            physical(path)
            require(fingerprint(Path(path).stat()) == item[2], "source snapshot drift before publication")

def collect(plan):
    validate_plan(plan)
    require(globals().get("_PRICEFM_VERIFIED_COLLECTOR_SOURCE_SHA256") == plan["collector_source_sha256"],
            "actual transmitted source must be verified by reviewed bootstrap before collection")
    collector = Collector(plan)
    regions = []
    for entry in plan["regions"]:
        region, root = entry["region"], physical(entry["root"])
        result = {"region": region, "host": "jerez", "availability": "COLLECTED_LOCAL_SNAPSHOT",
                  "logical_campaign_root": str(root), "scores": [], "designs": [], "missingness": []}
        if not root.is_dir():
            result["availability"] = "MISSING_LOCAL_METADATA"
            result["missingness"].append("CAMPAIGN_ROOT_NOT_PRESENT")
        prep = physical(entry["preparation"])
        if prep.is_file():
            raw, value, identity = collector.original(prep, Path(DATA) / "launch_prep")
            require(value.get("source", {}).get("head") == entry["expected_source_head"], "preparation producer differs from reviewed region")
            require(value.get("test_used_for_selection") is False, "preparation has test-selected origin")
            context = {key: value.get(key) for key in ("source", "source_sha256", "input_sha256", "bank_sha256",
                       "test_used_for_selection", "official_development_test_seen_previously")}
            context["metadata_role"] = "DERIVED_TRAINING_CONTEXT_NOT_ORIGINAL_BYTE_COPY"
            context["original_preparation"] = {"path": str(prep), "sha256": sha(raw), "fingerprint": identity}
            context["excluded_sections"] = ["references", "control", "historical fits and official-test comparison scalars"]
            result["preparation"] = collector.add(region, "training_context.json", prep, Path(DATA) / "launch_prep",
                role="DERIVED_TRAINING_CONTEXT_NOT_ORIGINAL_BYTE_COPY", projection=context)
        else:
            result["missingness"].append("PREPARATION_IDENTITY_UNOBSERVED")
        choice = root / "frozen_choices.json"
        if choice.is_file():
            raw, value, identity = collector.original(choice, root)
            if region in value:
                no_test(value[region])
                require(value[region].get("selected_before_test") is True, "frozen choice not before test")
            result["selection"] = collector.add(region, "frozen_choices.json", choice, root)
        else:
            result["missingness"].append("FROZEN_TRAINING_CHOICE_NOT_PRESENT")
        for sealpath in sorted((root / "tasks_done").glob("*_score/completed_evidence.json")):
            name = sealpath.parent.name
            require(TOKEN.fullmatch(name), "unsafe score task name")
            taskpath = root / "tasks" / (name + ".json")
            scorepath = sealpath.parent / "result.json"
            if not taskpath.is_file() or not scorepath.is_file():
                result["missingness"].append("INCOMPLETE_SCORE_SOURCE:" + name)
                continue
            task_raw, task, identity = collector.original(taskpath, root)
            if task.get("kind") != "internal_score":
                continue
            no_test(task)
            require(task.get("region") == region and type(task.get("split")) is int and task["split"] in (1, 2, 3), "training task identity differs")
            raw, score, identity = collector.original(scorepath, root)
            no_test(score)
            seal_raw, seal, identity = collector.original(sealpath, root)
            require(seal.get("metadata", {}).get("source_head") == entry["expected_source_head"]
                    and seal["metadata"].get("task_sha256") == sha(task_raw)
                    and seal.get("artifacts", {}).get("result.json") == sha(raw), "score not sealed under reviewed source/task")
            score_row = {"task": collector.add(region, "tasks/" + name + ".json", taskpath, root),
                         "result": collector.add(region, "tasks_done/" + name + "/result.json", scorepath, root),
                         "seal": collector.add(region, "tasks_done/" + name + "/completed_evidence.json", sealpath, root), "certificates": []}
            names = task.get("al_names", {})
            require(len(names) == 7 and set(float(x) for x in names) == QUANTILES, "seven AL quantile declarations required")
            complete = True
            for tau, alname in sorted(names.items(), key=lambda x: float(x[0])):
                require(TOKEN.fullmatch(alname), "unsafe declared AL companion")
                base = root / "tasks_done" / alname
                paths = {"task": root / "tasks" / (alname + ".json"),
                         "certificate": base / "fit/fixedpoint_certificate.json",
                         "terminal": base / "fit/terminal.json", "seal": base / "completed_evidence.json"}
                if not all(path.is_file() for path in paths.values()):
                    result["missingness"].append("INCOMPLETE_AL_METADATA:" + alname)
                    complete = False
                    break
                docs = {key: collector.original(path, root) for key, path in paths.items()}
                no_test(docs["task"][1])
                no_test(docs["terminal"][1])
                al = docs["task"][1]
                require(al.get("kind") == "internal_al" and al.get("region") == region
                        and al.get("candidate_id") == task.get("candidate_id")
                        and al.get("split") == task.get("split") and al.get("tau0") == task.get("tau0")
                        and al.get("tau") == float(tau), "declared AL task crosswire")
                alseal = docs["seal"][1]
                require(alseal.get("metadata", {}).get("source_head") == entry["expected_source_head"]
                        and alseal["metadata"].get("task_sha256") == sha(docs["task"][0])
                        and alseal.get("artifacts", {}).get("fit/fixedpoint_certificate.json") == sha(docs["certificate"][0])
                        and alseal["artifacts"].get("fit/terminal.json") == sha(docs["terminal"][0]), "AL metadata seal mismatch")
                rels = {"task": "tasks/" + alname + ".json", "certificate": "tasks_done/" + alname + "/fit/fixedpoint_certificate.json",
                        "terminal": "tasks_done/" + alname + "/fit/terminal.json", "seal": "tasks_done/" + alname + "/completed_evidence.json"}
                score_row["certificates"].append({key: collector.add(region, rels[key], path, root) for key, path in paths.items()})
            if complete:
                result["scores"].append(score_row)
        for design in sorted((root / "tasks_done").glob("*_design/design/design.json")):
            name = design.parent.parent.name
            require(TOKEN.fullmatch(name), "unsafe design task")
            taskpath, sealpath = root / "tasks" / (name + ".json"), design.parent.parent / "completed_evidence.json"
            if not taskpath.is_file() or not sealpath.is_file():
                continue
            task_raw, task, identity = collector.original(taskpath, root)
            if task.get("kind") != "internal_design":
                continue
            no_test(task)
            raw, value, identity = collector.original(design, root)
            no_test(value)
            require(value.get("selection_stage") == "inner_training_only" and value.get("region") == region, "nontraining design")
            seal_raw, seal, identity = collector.original(sealpath, root)
            require(seal.get("metadata", {}).get("source_head") == entry["expected_source_head"]
                    and seal["metadata"].get("task_sha256") == sha(task_raw)
                    and seal.get("artifacts", {}).get("design/design.json") == sha(raw), "design not sealed")
            row = {"task": collector.add(region, "tasks/" + name + ".json", taskpath, root),
                   "design": collector.add(region, "tasks_done/" + name + "/design/design.json", design, root),
                   "seal": collector.add(region, "tasks_done/" + name + "/completed_evidence.json", sealpath, root)}
            scaler = design.parent / "scaler.json"
            if scaler.is_file():
                raw, value, identity = collector.original(scaler, root)
                no_test(value)
                require(seal["artifacts"].get("design/scaler.json") == sha(raw), "training scaler not sealed")
                row["scaler"] = collector.add(region, "tasks_done/" + name + "/design/scaler.json", scaler, root)
            result["designs"].append(row)
        if not result["scores"]:
            result["missingness"].append("NO_COMPLETE_INTERNAL_SCORE_JSON_GROUPS")
        regions.append(result)
    supplements = []
    for row in plan["SI_scaler_supplements"]:
        require(TOKEN.fullmatch(row["task_name"]) and row["task_name"].endswith("_design"), "unsafe SI supplement task")
        root = Path(DATA) / "campaigns/pricefm_stage_r141_recovery_rollout_20261019__SI"
        expected = root / "tasks_done" / row["task_name"] / "design/scaler.json"
        require(str(expected) == row["original_path"], "SI supplement outside exact manifest")
        raw, value, identity = collector.original(expected, root)
        no_test(value)
        require(sha(raw) == row["sha256"], "SI original scaler pin drift")
        supplements.append({"task_name": row["task_name"], "scaler": collector.add("SI", "tasks_done/" + row["task_name"] + "/design/scaler.json", expected, root)})
    collector.snapshot_stable()
    return {"schema": SCHEMA, "status": "COLLECTED_SAVED_TRAINING_JSON_NO_MODELS",
            "collection_id": plan["collection_id"], "plan_sha256": sha(encoded(plan)),
            "collector_source_sha256": plan["collector_source_sha256"], "source_self_verified_by_bootstrap": True,
            "source_binding_method": "SHA256_OF_ACTUAL_TRANSMITTED_SOURCE_BEFORE_EXEC",
            "observed_epoch": time.time(), "regions": regions, "SI_scaler_supplements": supplements,
            "files": [collector.files[key] for key in sorted(collector.files)], "payload_bytes": collector.total,
            "source_files_observed": len(collector.originals), "snapshot_stat_rechecked": True,
            "self_CPU_seconds": sum(resource.getrusage(resource.RUSAGE_SELF)[:2]),
            "new_models": 0, "new_scores": 0, "new_jobs": 0}

def wire(packet, plan):
    raw = encoded(packet)
    require(len(raw) <= plan["maximum_encoded_pack_bytes"], "encoded metadata pack cap")
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb", compresslevel=1, mtime=0) as handle:
        handle.write(raw)
    compressed = buffer.getvalue()
    require(len(compressed) <= plan["maximum_compressed_bytes"], "compressed metadata cap")
    return {"schema": "pricefm_gzip_training_metadata_wire_v1", "collection_id": plan["collection_id"],
            "plan_sha256": sha(encoded(plan)), "uncompressed_bytes": len(raw), "uncompressed_sha256": sha(raw),
            "compressed_bytes": len(compressed), "compressed_sha256": sha(compressed),
            "gzip_base64": base64.b64encode(compressed).decode("ascii")}

def unpack_wire(envelope, plan):
    require(envelope.get("schema") == "pricefm_gzip_training_metadata_wire_v1"
            and envelope.get("collection_id") == plan["collection_id"]
            and envelope.get("plan_sha256") == sha(encoded(plan)), "foreign metadata wire")
    compressed = base64.b64decode(envelope["gzip_base64"], validate=True)
    require(len(compressed) == envelope["compressed_bytes"] <= plan["maximum_compressed_bytes"]
            and sha(compressed) == envelope["compressed_sha256"], "compressed wire mismatch")
    with gzip.GzipFile(fileobj=io.BytesIO(compressed), mode="rb") as handle:
        raw = handle.read(plan["maximum_encoded_pack_bytes"] + 1)
        require(not handle.read(1), "expanded packet cap")
    require(len(raw) == envelope["uncompressed_bytes"] <= plan["maximum_encoded_pack_bytes"]
            and sha(raw) == envelope["uncompressed_sha256"], "expanded wire mismatch")
    packet = loads(raw)
    require(packet.get("schema") == SCHEMA and packet.get("collection_id") == plan["collection_id"]
            and packet.get("plan_sha256") == sha(encoded(plan))
            and packet.get("collector_source_sha256") == plan["collector_source_sha256"]
            and packet.get("source_self_verified_by_bootstrap") is True
            and packet.get("source_binding_method") == "SHA256_OF_ACTUAL_TRANSMITTED_SOURCE_BEFORE_EXEC", "packet/source identity mismatch")
    require(len(packet["files"]) <= plan["maximum_files"], "file count cap")
    require(len(packet["regions"]) == 18 and set(x["region"] for x in packet["regions"]) == REGIONS, "regional packet surface")
    require(len(packet.get("SI_scaler_supplements", [])) == 6
            and set(x["task_name"] for x in packet["SI_scaler_supplements"]) == set(x["task_name"] for x in plan["SI_scaler_supplements"]),
            "SI supplement reference surface differs")
    for reference in packet["SI_scaler_supplements"]:
        expected = next(x for x in plan["SI_scaler_supplements"] if x["task_name"] == reference["task_name"])
        require(reference["scaler"] == {"id": "SI/tasks_done/" + reference["task_name"] + "/design/scaler.json",
                                      "sha256": expected["sha256"]}, "SI supplement reference crosswire")
    files = {}
    total = 0
    regional = {x["region"]: x for x in plan["regions"]}
    supplemental = {x["original_path"]: x for x in plan["SI_scaler_supplements"]}
    for row in packet["files"]:
        relative = Path(row["id"])
        require(not relative.is_absolute() and ".." not in relative.parts and relative.suffix == ".json"
                and all(TOKEN.fullmatch(x) for x in relative.parts), "unsafe received cache path")
        require(row["id"] == row["region"] + "/" + row["relative"] and row["id"] not in files, "duplicate/crosswired cache alias")
        require(row["region"] in REGIONS or row["region"] == "SI", "foreign region file")
        require(row["role"] in ("BYTE_EXACT_ORIGINAL_JSON", "DERIVED_TRAINING_CONTEXT_NOT_ORIGINAL_BYTE_COPY"), "unknown metadata role")
        payload = base64.b64decode(row["base64"], validate=True)
        require(len(payload) == row["bytes"] <= plan["maximum_source_JSON_bytes"] and sha(payload) == row["sha256"], "JSON payload mismatch")
        value = loads(payload)
        original = row["original"]
        if row["region"] == "SI":
            require(row["role"] == "BYTE_EXACT_ORIGINAL_JSON" and original["path"] in supplemental
                    and original["sha256"] == supplemental[original["path"]]["sha256"] == row["sha256"],
                    "foreign SI supplement")
        elif row["role"] == "DERIVED_TRAINING_CONTEXT_NOT_ORIGINAL_BYTE_COPY":
            allowed_context = set(("source", "source_sha256", "input_sha256", "bank_sha256",
                "test_used_for_selection", "official_development_test_seen_previously",
                "metadata_role", "original_preparation", "excluded_sections"))
            require(set(value) == allowed_context and row["relative"] == "training_context.json"
                    and value["metadata_role"] == row["role"] and value["original_preparation"] == original
                    and original["path"] == regional[row["region"]]["preparation"]
                    and value.get("source", {}).get("head") == regional[row["region"]]["expected_source_head"],
                    "context projection role/original/source binding differs")
            no_test(value)
        else:
            require(original["path"] == str(Path(regional[row["region"]]["root"]) / row["relative"])
                    and original["sha256"] == row["sha256"], "byte-exact original binding differs")
        total += len(payload)
        require(total <= plan["maximum_payload_bytes"], "payload byte cap")
        files[row["id"]] = payload
    require(total == packet["payload_bytes"], "packet total differs")
    return packet, files

def pin_json(path):
    raw, value, identity = read_json(path, 16 * 1024 * 1024)
    return {"path": str(path), "sha256": sha(raw)}

def read_pinned_json(value, maximum):
    require(type(value) is dict and set(value) == set(("path", "sha256")), "strict metadata pin required")
    raw, doc, identity = read_json(value["path"], maximum)
    require(sha(raw) == value["sha256"], "metadata pin drift")
    return doc

def source_pin(path):
    path = physical(path)
    require(path.suffix == ".py", "Python source pin required")
    fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as handle:
        before = os.fstat(handle.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid()
                and before.st_nlink == 1 and before.st_size <= 131072, "unsafe source file")
        raw = handle.read(131073)
        after = os.fstat(handle.fileno())
    physical(path)
    require(fingerprint(before) == fingerprint(after) == fingerprint(path.stat()) and len(raw) == before.st_size, "source changed during read")
    return {"path": str(path), "sha256": sha(raw)}

def validate_guard(guard, plan):
    require(type(guard.get("returncode")) is int and guard["returncode"] == 0
            and type(guard.get("command_returncode")) is int and guard["command_returncode"] == 0,
            "actual integer zero collection returncodes required")
    require(guard.get("independent_guardian") is True and guard.get("all_owned_descendants_reaped") is True
            and guard.get("kernel_escape_filter") is True and guard.get("guardian_forced_monitor_stop") is False
            and "cap_reason" in guard and guard["cap_reason"] is None, "actual independent owned guardian required")
    require(type(guard.get("CPU_limit")) is int and guard["CPU_limit"] == plan["local_transport_CPU"] == 6,
            "actual collection CPU6 guard required")
    cpu, wall = guard.get("aggregate_CPU_seconds"), guard.get("complete_lifecycle_wall_seconds")
    require(type(cpu) in (float, int) and math.isfinite(cpu) and 0 <= cpu < 6,
            "actual finite nonnegative CPU below6 required")
    require(type(wall) in (float, int) and math.isfinite(wall)
            and 0 <= wall <= plan["local_transport_wall"] == 120, "actual complete lifecycle wall<=120 required")
    return guard

def write_new(path, raw, durable=False):
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(raw)
        handle.flush()
        if durable:
            os.fsync(handle.fileno())

def cache_materialize(cache, files):
    require(not cache.exists(), "reconstructible cache already exists")
    cache.mkdir(mode=0o700)
    mapped = {}
    for name in sorted(files):
        target = cache / name
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        write_new(target, files[name])
        require(sha(target.read_bytes()) == sha(files[name]), "cache readback differs")
        mapped[name] = {"path": str(target), "sha256": sha(files[name])}
    return mapped

def materialize(args):
    plan_raw, plan, identity = read_json(args.plan, 2 * 1024 * 1024)
    require(sha(plan_raw) == args.plan_sha256, "plan pin drift")
    validate_plan(plan)
    source = physical(__file__)
    require(sha(source.read_bytes()) == plan["collector_source_sha256"], "local collection source drift")
    receipt_raw, receipt, identity = read_json(args.execution_receipt, 2 * 1024 * 1024)
    plan_pin = {"path": str(physical(args.plan)), "sha256": args.plan_sha256}
    collector_pin = source_pin(source)
    bootstrap_pin = source_pin(plan["bootstrap_source"]["path"])
    require(bootstrap_pin == plan["bootstrap_source"], "reviewed bootstrap source drift")
    require(receipt.get("status") == "EXECUTED_REVIEWED_JEREZ_TRAINING_COLLECTION"
            and receipt.get("plan") == plan_pin and receipt.get("collector_source") == collector_pin
            and receipt.get("bootstrap_source") == bootstrap_pin,
            "actual reviewed execution source/plan/bootstrap receipt required")
    review = read_pinned_json(receipt["independent_review"], 2 * 1024 * 1024)
    require(review.get("status") == "PASS_REVIEWED_JEREZ_TRAINING_METADATA_COLLECTION"
            and review.get("plan") == plan_pin and review.get("collector_source") == collector_pin
            and review.get("bootstrap_source") == bootstrap_pin, "actual independent source-bound collection review required")
    grant = read_pinned_json(receipt["root_execution_grant"], 2 * 1024 * 1024)
    require(grant.get("status") == "ROOT_AUTHORIZED_JEREZ_TRAINING_COLLECTION_EXECUTION"
            and grant.get("plan") == plan_pin and grant.get("collector_source") == collector_pin
            and grant.get("bootstrap_source") == bootstrap_pin
            and grant.get("independent_review") == receipt["independent_review"], "actual source-bound root EXECgrant required")
    require(type(grant.get("expires_epoch")) in (int, float) and math.isfinite(grant["expires_epoch"])
            and time.time() < grant["expires_epoch"] <= plan["expires_epoch"], "root EXECgrant expired or exceeds plan")
    require(receipt.get("source_transmission") == {
        "mode": "SHA256_VERIFIED_BOOTSTRAP",
        "collector_sha256": collector_pin["sha256"], "bootstrap_source": bootstrap_pin},
        "verified actual transmitted-source bootstrap receipt required")
    guard_raw, guard, identity = read_json(receipt["guardian"]["path"], 16 * 1024 * 1024)
    require(sha(guard_raw) == receipt["guardian"]["sha256"], "collection guardian pin drift")
    validate_guard(guard, plan)
    envelope = loads(guard["stdout"])
    packet, files = unpack_wire(envelope, plan)
    config_raw, config, identity = read_json(args.base_config, 16 * 1024 * 1024)
    require(sha(config_raw) == plan["base_config"]["sha256"]
            and str(physical(args.base_config)) == plan["base_config"]["path"], "audit01 base pin differs")
    authority_raw, authority, identity = read_json(config["authority"]["path"], 2 * 1024 * 1024)
    require(sha(authority_raw) == config["authority"]["sha256"] and time.time() < authority["expires_epoch"], "parent authority drift/expiry")
    bank = physical(args.bank)
    allowed = physical(authority["allowed_metadata_output_root"])
    require(bank != allowed and below(bank, allowed) and not bank.exists(), "new bank outside actual authority")
    output = physical(args.output_config)
    require(below(output, allowed) and not output.exists(), "new config outside authority or already exists")
    bank.mkdir(mode=0o700)
    write_new(bank / "RAW_PACK.json", encoded(envelope) + b"\n", durable=True)
    cache = bank / "reconstructible_cache"
    mapped = cache_materialize(cache, files)
    def replace(value):
        if isinstance(value, dict):
            if set(value) == set(("id", "sha256")):
                require(value["id"] in mapped and mapped[value["id"]]["sha256"] == value["sha256"], "undeclared packet reference")
                return mapped[value["id"]]
            return {key: replace(item) for key, item in value.items()}
        if isinstance(value, list):
            return [replace(item) for item in value]
        return value
    entries = {entry["region"]: entry for entry in config["regions"]}
    for entry in packet["regions"]:
        require(entries[entry["region"]]["availability"] == "REMOTE_NOT_OBSERVED", "expanded input would replace alreadyobserved audit01 evidence")
        entries[entry["region"]] = replace(entry)
    supplements = replace(packet["SI_scaler_supplements"])
    si_designs = entries["SI"]["designs"]
    for supplement in supplements:
        matching = [row for row in si_designs if Path(row["task"]["path"]).stem == supplement["task_name"]]
        require(len(matching) == 1 and not matching[0].get("scaler"), "SI supplement would overwrite existing or unmatched evidence")
        matching[0]["scaler"] = supplement["scaler"]
    config["regions"] = [entries[name] for name in sorted(entries)]
    config["allowed_roots"] = sorted(set(config["allowed_roots"] + [str(cache)]))
    config["preserved_audit01_configuration"] = {"path": str(physical(args.base_config)), "sha256": sha(config_raw)}
    config["metadata_expansion"] = {"role": "COLLECTED_TRAINING_JSON_AND_DERIVED_CONTEXT",
                                  "authoritative_durable_packet": pin_json(bank / "RAW_PACK.json"),
                                  "reconstructible_cache_not_canonical_scientific_output": True,
                                  "derived_context_regions": sorted(REGIONS),
                                  "collector_source": {"path": str(source), "sha256": sha(source.read_bytes())},
                                  "actual_execution_receipt": pin_json(physical(args.execution_receipt)),
                                  "collection_id": plan["collection_id"]}
    write_new(output, json.dumps(config, sort_keys=True, indent=2, allow_nan=False).encode("utf-8") + b"\n", durable=True)
    manifest = {"status": "PASS_DURABLE_TRAINING_PACKET_AND_RECONSTRUCTIBLE_JSON_CACHE",
                "collection_id": plan["collection_id"], "packet": pin_json(bank / "RAW_PACK.json"),
                "plan": {"path": str(physical(args.plan)), "sha256": args.plan_sha256},
                "new_configuration": pin_json(output), "base_configuration": config["preserved_audit01_configuration"],
                "files": mapped, "payload_bytes": packet["payload_bytes"],
                "derived_context_is_not_original_preparation_bytes": True,
                "cache_individual_file_durability_claimed": False, "cache_reconstructible_from_durable_packet": True,
                "numerical_or_canonical_scientific_bank_changed": False, "new_jobs": 0,
                "self_CPU_seconds": sum(resource.getrusage(resource.RUSAGE_SELF)[:2])}
    write_new(bank / "MANIFEST.json", json.dumps(manifest, sort_keys=True, indent=2).encode("utf-8") + b"\n", durable=True)
    directories = set((allowed, allowed.parent))
    for leaf in (bank, output.parent):
        directory = leaf
        while below(directory, allowed):
            directories.add(directory)
            if directory == allowed:
                break
            directory = directory.parent
    for directory in sorted(directories, key=lambda x: len(x.parts), reverse=True):
        fd = os.open(str(directory), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    print(json.dumps({"status": manifest["status"], "files": len(files),
                      "new_configuration": manifest["new_configuration"], "bank_manifest": pin_json(bank / "MANIFEST.json")}))

def restore(args):
    """Rebuild missing cache only, under a fresh metadata reconstruction grant."""
    grant_raw, grant, identity = read_json(args.restore_authority, 2 * 1024 * 1024)
    require(sha(grant_raw) == args.restore_authority_sha256
            and grant.get("status") == "ROOT_AUTHORIZED_METADATA_CACHE_RECONSTRUCTION"
            and time.time() < grant["expires_epoch"], "fresh reconstruction authority required")
    bank = physical(args.bank)
    require(grant.get("allowed_bank_root") == str(bank), "wrong reconstruction bank")
    manifest_raw, manifest, identity = read_json(bank / "MANIFEST.json", 16 * 1024 * 1024)
    require(grant.get("bank_manifest") == {"path": str(bank / "MANIFEST.json"), "sha256": sha(manifest_raw)}, "bank manifest not authorized")
    plan_raw, plan, identity = read_json(manifest["plan"]["path"], 2 * 1024 * 1024)
    require(sha(plan_raw) == manifest["plan"]["sha256"], "original collection plan drift")
    validate_plan(plan, require_live=False)
    require(sha(Path(__file__).read_bytes()) == plan["collector_source_sha256"], "reconstruction source drift")
    wire_raw, envelope, identity = read_json(bank / "RAW_PACK.json", 16 * 1024 * 1024)
    require(manifest["packet"] == {"path": str(bank / "RAW_PACK.json"), "sha256": sha(wire_raw)}, "durable packet drift")
    packet, files = unpack_wire(envelope, plan)
    cache = bank / "reconstructible_cache"
    expected = {name: {"path": str(cache / name), "sha256": sha(payload)} for name, payload in files.items()}
    require(expected == manifest["files"] and not cache.exists(), "cache must be missing and exactly reconstructible")
    actual = cache_materialize(cache, files)
    require(actual == manifest["files"], "reconstructed pointers differ")
    receipt = {"status": "PASS_RECONSTRUCTED_METADATA_CACHE_FROM_DURABLE_PACKET", "bank_manifest": grant["bank_manifest"],
               "fresh_authority": {"path": str(physical(args.restore_authority)), "sha256": args.restore_authority_sha256},
               "collection_not_reexecuted": True, "original_manifest_not_changed": True, "file_count": len(actual),
               "canonical_scientific_artifacts_mutated": False, "cache_individual_durability_claimed": False,
               "completed_epoch": time.time()}
    target = bank / ("RESTORE_RECEIPT_%d.json" % time.time_ns()) if hasattr(time, "time_ns") else bank / ("RESTORE_RECEIPT_%d.json" % int(time.time() * 1000000))
    write_new(target, json.dumps(receipt, sort_keys=True, indent=2).encode("utf-8") + b"\n", durable=True)
    fd = os.open(str(bank), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
    print(json.dumps({"status": receipt["status"], "receipt": pin_json(target)}))

def main():
    resource.setrlimit(resource.RLIMIT_CPU, (6, 6))
    signal.alarm(120)
    require(os.sched_getaffinity(0) == set((31,)), "administrativeCPU31 required")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--collect-plan-base64")
    parser.add_argument("--materialize", action="store_true")
    parser.add_argument("--restore-cache", action="store_true")
    parser.add_argument("--restore-authority")
    parser.add_argument("--restore-authority-sha256")
    parser.add_argument("--plan")
    parser.add_argument("--plan-sha256")
    parser.add_argument("--execution-receipt")
    parser.add_argument("--base-config")
    parser.add_argument("--bank")
    parser.add_argument("--output-config")
    args = parser.parse_args()
    if args.collect_plan_base64:
        require(not args.materialize and not args.restore_cache, "one mode required")
        raw = base64.b64decode(args.collect_plan_base64, validate=True)
        plan = loads(raw)
        print(json.dumps(wire(collect(plan), plan), sort_keys=True, separators=(",", ":")), flush=True)
    elif args.restore_cache:
        require(not args.materialize and all((args.bank, args.restore_authority, args.restore_authority_sha256)),
                "one restore mode and fresh authority required")
        restore(args)
    else:
        require(args.materialize and all((args.plan, args.plan_sha256, args.execution_receipt,
                                        args.base_config, args.bank, args.output_config)), "materialize arguments required")
        materialize(args)

if __name__ == "__main__":
    main()
