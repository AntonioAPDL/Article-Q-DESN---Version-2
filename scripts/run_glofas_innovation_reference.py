#!/usr/bin/env python3.11
"""Exact-purpose, four-chain innovation-reference pilot; default is no launch.

The historical controller is imported for neutral process/atomic-I/O primitives
only. Its scope validator, purpose constants and historical authority are never
modified or invoked. Original R payloads are never opened or hashed in Python.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys
import time

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve()
spec = importlib.util.spec_from_file_location("innovation_neutral_process_utilities",
    SCRIPT.with_name("run_glofas_reference_recovery.py"))
U = importlib.util.module_from_spec(spec)
spec.loader.exec_module(U)
# These helpers do not refer to historical purpose, reader or source constants.
need, utc, regular, sha, write_new, git = U.need, U.utc, U.regular, U.sha, U.write_new, U.git
process, process_table, cpu_set = U.process, U.process_table, U.cpu_set
private_control, new_control, launch_tmux = U.private_control, U.new_control, U.launch_tmux
owned_rows, cleanup_owned, native_environment = U.owned_rows, U.cleanup_owned, U.native_environment
GiB, MiB = 1024 ** 3, 1024 ** 2
READER = "scripts/glofas_innovation_reference_reader.R"
RSCRIPT = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
CPUS = {26, 27, 28, 29}
PRODUCTION_PATHS = {
    "application/R/00_packages.R", "application/R/model_contract.R", "application/R/feature_contract.R",
    "application/R/covariate_design.R", "application/R/latent_path_design.R",
    "application/R/fit_qdesn_latent_path.R", "application/R/latent_path_vb_al.R",
}
SOURCE_PATHS = PRODUCTION_PATHS | {
    "scripts/glofas_fixed_target_forensic_reader.R", "scripts/glofas_same_family_closeout.R",
    "scripts/glofas_same_family_truth_bridge.R", "scripts/glofas_same_family_fitted_history.R",
    "scripts/glofas_nonlinear_replay_reader.R", "scripts/diagnostics/glofas_nonlinear_replay.R",
    "scripts/glofas_al_conditional_reference_reader.R", "scripts/diagnostics/glofas_al_path_reference.R",
    "scripts/diagnostics/glofas_compiled_value_reference.R",
    "scripts/diagnostics/glofas_innovation_coordinates.R", "scripts/diagnostics/glofas_innovation_streaming.R",
    "scripts/diagnostics/glofas_innovation_sampler.R", READER,
    "scripts/run_glofas_innovation_reference.py", "scripts/run_glofas_reference_recovery.py",
}
QUALIFICATIONS = ("reference_qualified", "full_posterior_accuracy_qualified",
    "production_launch_authorized", "publication_authorized")
YES = {"allow_original_reads", "allow_fresh_source_feature_evaluation", "allow_metadata_serialization",
    "allow_fixed_parameter_path_sampling", "allow_raw_draw_export"}
NO = {"allow_generated_numeric_array_read", "allow_proposal_calibration", "allow_saved_callbacks",
    "allow_parameter_updates", "allow_prior_updates", "allow_full_parameter_refit", "allow_truth_read",
    "allow_retuning", "allow_scoring", "allow_article_changes", "allow_publication",
    "allow_derived_context_serialization"}


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            need(key not in result, "duplicate JSON key")
            result[key] = value
        return result
    value = json.loads(regular(path).read_text(), object_pairs_hook=unique)
    need(isinstance(value, dict), "JSON metadata object required")
    return value


def pin_source(c):
    root = Path(c["source_root"])
    need(root.is_absolute() and root.resolve() == root and
        git(root, "rev-parse", "--show-toplevel") == str(root) and
        git(root, "rev-parse", "HEAD") == c["source_commit"] and
        git(root, "rev-parse", "HEAD^{tree}") == c["source_tree"] and
        not git(root, "status", "--porcelain=v1", "--untracked-files=all"), "exact clean committed source required")
    need(SCRIPT == root / "scripts/run_glofas_innovation_reference.py", "new controller must run from admitted source")
    pins = c["source_files"]
    paths = [Path(p["path"]) for p in pins]
    need(len(paths) == len(set(paths)) == 22 and set(paths) == {root / p for p in SOURCE_PATHS},
        "exact 22-file reader/controller/streaming/kernel closure required")
    for path, pin in zip(paths, pins):
        need(path.stat().st_size == pin["size_bytes"] and sha(path) == pin["sha256"], "runtime source pin changed")
        rel = str(path.relative_to(root))
        need(git(root, "hash-object", "--no-filters", "--", rel) ==
            git(root, "rev-parse", c["source_commit"] + ":" + rel), "runtime source differs from committed blob")
    for rel in PRODUCTION_PATHS:
        need(git(root, "rev-parse", c["source_commit"] + ":" + rel) ==
            git(root, "rev-parse", "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6:" + rel),
            "production source differs from frozen producer")


def freshness(c):
    need(U.socket.gethostname().split(".")[0].lower() == "muscat", "native admission is Muscat only")
    available = int(next(x.split()[1] for x in Path("/proc/meminfo").read_text().splitlines()
        if x.startswith("MemAvailable:"))) * 1024
    need(available >= c["limits"]["aggregate_memory_bytes"] + c["limits"]["memory_headroom_bytes"],
        "fresh aggregate RAM plus headroom gate failed")
    free = shutil.disk_usage(Path(c["output_root"]).parent).free
    need(free >= 80 * GiB, "80 GiB fresh disk headroom required")
    conflicts = [p["pid"] for p in process_table() if p["uid"] == os.getuid() and
        p["comm"] in ("R", "Rscript") and cpu_set(p["CPUs_allowed_list"]) & CPUS]
    need(not conflicts, "allocated CPU conflict with existing R process: " + str(conflicts))
    return dict(observed_utc=utc(), MemAvailable_bytes=available, disk_free_bytes=free,
        protected_logical_cpus=[20, 21, 22, 23, 24, 25, 30, 31, 48, 50], protected_physical_siblings=[16, 18])


def validate_contract(path, digest, *, launching=False):
    p = regular(Path(path))
    permissions = p.stat()
    need(permissions.st_uid == os.getuid() and stat.S_IMODE(permissions.st_mode) & 0o077 == 0,
        "external purpose must be private and owned")
    need(re.fullmatch(r"[a-f0-9]{64}", digest or "") and sha(p) == digest, "exact external purpose digest required")
    c = read_json(p)
    root = Path(c["source_root"])
    need(not p.is_relative_to(root), "purpose must be external to source")
    need(c["schema_version"] == "glofas_innovation_reference_contract_v1" and
        c["purpose"] == "MEDIAN_AL_FIXED_PARAMETER_INNOVATION_PCN_PILOT_NO_FULL_REFIT" and
        c["mode"] == "computational_pilot" and c["execution_mode"] == "fork_four",
        "only exact fixed-parameter four-chain innovation pilot admitted")
    need(re.fullmatch(r"[a-f0-9]{32,64}", c["nonce"]), "nonce required")
    need({k for k in c if k.startswith("allow_")} == YES | NO and
        all(c.get(k) is True for k in YES) and all(c.get(k) is False for k in NO), "exact pilot permissions required")
    need(all(re.fullmatch(r"[0-9a-f]{40}", c[k] or "") for k in ("source_commit", "source_tree")),
        "full source identities required")
    b = c["limits"]
    integer_keys = {"cpu_seconds", "wall_seconds", "memory_bytes", "output_bytes", "logical_cpu", "max_workers",
        "child_cpu_seconds", "aggregate_cpu_seconds", "aggregate_memory_bytes", "memory_headroom_bytes", "max_draw_memory_bytes"}
    need(set(b) == integer_keys | {"child_logical_cpus"} and
        all(type(b[k]) is int and b[k] > 0 for k in integer_keys), "finite integer native budgets required")
    need(60 <= b["cpu_seconds"] <= b["wall_seconds"] <= 3600 and b["memory_bytes"] == 16 * GiB and
        b["output_bytes"] <= 64 * MiB and b["logical_cpu"] == 26 and b["max_workers"] == 4 and
        b["child_logical_cpus"] == [26, 27, 28, 29] and b["child_cpu_seconds"] == b["cpu_seconds"] and
        b["aggregate_cpu_seconds"] >= 5 * b["cpu_seconds"] and
        b["aggregate_memory_bytes"] >= 5 * b["memory_bytes"] and b["memory_headroom_bytes"] >= 180 * GiB and
        5 * 1000 * 4 * 28 * 8 <= b["max_draw_memory_bytes"] <= 128 * MiB, "protected four-child native allocation required")
    expires = dt.datetime.fromisoformat(c["expires_utc"].replace("Z", "+00:00"))
    need(expires.tzinfo is not None and expires > dt.datetime.now(dt.timezone.utc) +
        dt.timedelta(seconds=b["wall_seconds"] + 60), "purpose expires before native closure allowance")
    out, scratch = Path(c["output_root"]), Path(c["metadata_scratch_root"])
    need(out.is_absolute() and out.resolve() == out and not out.is_symlink() and
        out.is_relative_to(root / "local_trackers") and out.parent.is_dir() and
        git(root, "check-ignore", "--", str(out)) == str(out), "canonical ignored output required")
    if launching:
        need(not out.exists(), "output already exists; no automatic retry")
    need(scratch.is_absolute() and scratch.resolve() == scratch and scratch.is_dir() and not scratch.is_symlink() and
        scratch.stat().st_uid == os.getuid() and stat.S_IMODE(scratch.stat().st_mode) == 0o700 and
        not list(scratch.iterdir()), "fresh private owned empty metadata scratch required")
    need(not scratch.is_relative_to(root) or git(root, "check-ignore", "--", str(scratch)) == str(scratch),
        "in-source scratch must be ignored")
    # Original paths are declarations only here. No stat/open/hash of RDS inputs.
    for role, size, digest0, basename in (
        ("design", 4014834693, "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3", "shared_truth_free_design.rds"),
        ("median_model", 137820489, "f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881", "fit.rds"),
    ):
        pin = c[role]
        need(pin["size_bytes"] == size and pin["sha256"] == digest0 and Path(pin["path"]).is_absolute() and
            Path(pin["path"]).name == basename, "exact original payload declaration required")
    r = c["read_budget"]
    original_size = c["design"]["size_bytes"] + c["median_model"]["size_bytes"]
    need(r["max_RDS_deserializations"] == 2 and r["max_generated_RDS_deserializations"] == 0 and
        original_size <= r["max_deserialization_bytes"] <= 24 * GiB and
        2 * original_size <= r["max_payload_hash_bytes"] <= 48 * GiB and
        0 < r["max_metadata_bytes"] <= 64 * MiB, "exact two-original and zero-generated read budget required")
    v = c["innovation"]
    s = v["sampler"]
    need(v["likelihood_family"] == "al" and v["tau"] == .5 and
        v["parameter_rule"] == "retained_theta_mean_fixed_coefficient_covariance_zero" and
        v["scale_rule"] == "reciprocal_retained_inverse_scale_means_not_scale_means" and
        s["warmup"] == 500 and s["samples"] == 1000 and s["max_evaluations"] == 1501 and
        s["seeds"] == [2026110501, 2026110502, 2026110503, 2026110504] and
        s["adapt_warmup"] is True and s["rhat_max"] == 1.01 and s["min_ess"] >= 400 and
        s["max_quantile_mcse"] == .001 and s["max_wall_seconds"] == 2400 and
        s["delta_initial"] == .15 and s["delta_min"] == .0001 and s["delta_max"] == .95 and
        s["target_accept"] == .234 and s["progress_every"] == 250 and
        v["minimum_tail_seconds"] == 120 and v["parity_tolerance"] == 1e-10 and
        4 * 1501 <= v["max_total_forward_evaluations"] <= 7000 and
        0 < v["max_total_inverse_evaluations"] <= 16 and 0 < v["max_total_reference_evaluations"] <= 32,
        "fixed four-chain bounded pCN pilot and precision gates required")
    need(c["draw_export"]["filename"] == "innovation_draws.rds" and
        1000 * 4 * 28 * 8 + 1024 <= c["draw_export"]["max_bytes"] <= 4 * MiB,
        "one bounded generated all-chain array required")
    pin_source(c)
    metadata = [c["collection"], c["input_manifest"], c["diagnostic_dependencies"]["versions"],
        c["diagnostic_dependencies"]["sources"]]
    for role in ("baseline", "prior_replay", "prior_recovery"):
        need(set(c[role]) == {"receipt", "manifest", "summary", "terminal"}, "exact four-role prerequisite metadata required")
        metadata.extend(c[role].values())
    for pin in metadata:
        need(regular(pin["path"]).stat().st_size == pin["size_bytes"] and sha(pin["path"]) == pin["sha256"],
            "prerequisite metadata pin changed")
    return c, freshness(c)


def native_command(c, purpose, digest, control):
    b = c["limits"]
    return ["/usr/bin/time", "-v", "-o", str(control / "native.time.txt"), "/usr/bin/taskset", "-c", "26",
        "/usr/bin/timeout", "--signal=TERM", "--kill-after=1s", str(b["wall_seconds"] - 1) + "s", "/usr/bin/prlimit",
        f'--cpu={b["cpu_seconds"]}:{b["cpu_seconds"]}', f'--as={b["memory_bytes"]}:{b["memory_bytes"]}',
        f'--fsize={b["output_bytes"]}:{b["output_bytes"]}', str(RSCRIPT), "--vanilla", READER,
        "--contract", str(purpose), "--sha256", digest, "--execute"]


def check_limits(row, c):
    for key, cap in (("Max cpu time", c["limits"]["child_cpu_seconds"]),
        ("Max address space", c["limits"]["memory_bytes"]), ("Max file size", c["limits"]["output_bytes"])):
        fields = next(x for x in row["limits"].splitlines() if x.startswith(key)).split()
        need(fields[-3:-1] == [str(cap), str(cap)], "native soft/hard limit differs: " + key)


def capture(child, identity, c, purpose, digest):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        rows = owned_rows(identity)
        shell = next((p for p in rows if p["pid"] == child.pid), None)
        timep = next((p for p in rows if p["ppid"] == child.pid and p["comm"] == "time"), None)
        timeout = next((p for p in rows if timep and p["ppid"] == timep["pid"] and p["comm"] == "timeout"), None)
        worker = next((p for p in rows if timeout and p["ppid"] == timeout["pid"] and p["comm"] in ("R", "Rscript")), None)
        if all((shell, timep, timeout, worker)):
            need(timeout["pgid"] == worker["pgid"] == timeout["pid"] and worker["CPUs_allowed_list"] == "26" and
                str(purpose) in worker["command"] and digest in worker["command"] and READER in worker["command"],
                "live four-role native lineage/exact command proof failed")
            check_limits(worker, c)
            return dict(observed_utc=utc(), processes=dict(shell=shell, time=timep, timeout=timeout, R=worker),
                native_limits_verified=True, source_commit=c["source_commit"], source_tree=c["source_tree"], purpose_sha256=digest)
        need(child.poll() is None, "native exited before full four-role proof")
        time.sleep(.05)
    raise TimeoutError("native process capture exceeded fifteen seconds")


CONTROL_JSON_NAMES = U.CONTROL_JSON_NAMES


def expected_pending(path, control, output_root):
    if path.parent == output_root:
        return bool(re.fullmatch(r"progress_chain_[1-4]\.json\.new", path.name))
    if path.parent == control:
        return U.expected_pending(path, control, output_root)
    return False


def scan_output_bytes(control, output_root):
    # Keep local progress-name authority; never widen the historical scanner.
    control, output_root = Path(control), Path(output_root)
    for _ in range(4):
        total, retry, inodes = 0, False, set()
        def visit(directory):
            nonlocal total, retry
            with os.scandir(directory) as entries:
                for entry in entries:
                    p = Path(entry.path)
                    try:
                        s = entry.stat(follow_symlinks=False)
                    except FileNotFoundError:
                        if expected_pending(p, control, output_root):
                            retry = True
                            continue
                        raise
                    need(not stat.S_ISLNK(s.st_mode), "symlink in owned output")
                    if stat.S_ISDIR(s.st_mode):
                        visit(p)
                    elif stat.S_ISREG(s.st_mode):
                        atomic = p.parent == control and (p.name in CONTROL_JSON_NAMES or expected_pending(p, control, output_root))
                        inode = (s.st_dev, s.st_ino)
                        if not atomic or inode not in inodes:
                            total += s.st_size
                        if atomic:
                            inodes.add(inode)
                    else:
                        need(p == control / "server.sock" and stat.S_ISSOCK(s.st_mode), "unexpected special owned file")
        visit(control)
        try:
            visit(output_root)
        except FileNotFoundError as error:
            if error.filename != str(output_root):
                raise
        if not retry:
            return total
        time.sleep(.005)
    raise ValueError("output snapshot remained unstable after bounded atomic-publication rescans")


def monitor(child, identity, c, control, native_r=None):
    started, cpu_max, peak_rss, observed = time.monotonic(), {}, 0, {}
    while child.poll() is None:
        rows = owned_rows(identity)
        for p in rows:
            key = (p["pid"], p["starttime_ticks"])
            cpu_max[key] = max(cpu_max.get(key, 0), p["cpu_seconds"])
            if native_r and p["ppid"] == native_r["pid"] and p["comm"] in ("R", "Rscript"):
                need(p["session"] == native_r["session"] and p["pgid"] == native_r["pgid"] and
                    cpu_set(p["CPUs_allowed_list"]) <= CPUS and len(cpu_set(p["CPUs_allowed_list"])) == 1,
                    "child live lineage/affinity proof failed")
                check_limits(p, c)
                observed[key] = p
                need(len(observed) <= 4, "more than four native workers observed")
        peak_rss = max(peak_rss, sum(p["rss_bytes"] for p in rows))
        need(peak_rss <= c["limits"]["aggregate_memory_bytes"], "aggregate RSS budget exceeded")
        need(sum(cpu_max.values()) <= c["limits"]["aggregate_cpu_seconds"], "aggregate sampled CPU budget exceeded")
        need(time.monotonic() - started <= c["limits"]["wall_seconds"] + 20, "outer wall deadline exceeded")
        need(scan_output_bytes(control, c["output_root"]) <= c["limits"]["output_bytes"], "aggregate compact output budget exceeded")
        time.sleep(.25)
    return dict(native_exit_code=child.wait(), sampled_aggregate_cpu_seconds=sum(cpu_max.values()),
        peak_aggregate_RSS_bytes=peak_rss, independently_observed_workers=list(observed.values()))


def generated_array_sha(path, output_root, limit):
    p = Path(path)
    need(p.parent == Path(output_root) and p.name == "innovation_draws.rds" and p.resolve() == p and
        p.is_file() and not p.is_symlink() and p.stat().st_size <= min(limit, 4 * MiB),
        "only exact bounded newly generated innovation array may be hashed")
    return hashlib.sha256(p.read_bytes()).hexdigest()


def verify_timing(t):
    keys = {"measured_forward_max_seconds", "safety_factor", "projected_chain_seconds", "max_chain_evaluations",
        "sampler_wall_seconds", "minimum_tail_seconds", "remaining_seconds_at_fork"}
    need(set(t) == keys and all(type(t[k]) in (int, float) and 0 < t[k] < float("inf") for k in keys),
        "complete finite measured timing admission required")
    expected = t["measured_forward_max_seconds"] * 2 * 1501
    need(t["safety_factor"] == 2 and t["max_chain_evaluations"] == 1501 and
        abs(t["projected_chain_seconds"] - expected) <= 1e-9 * max(1, expected) and
        t["sampler_wall_seconds"] == 2400 and t["minimum_tail_seconds"] == 120 and
        expected <= 2400 and 2520 < t["remaining_seconds_at_fork"], "measured fork cost gate failed")


def verify_manifest(c):
    out = Path(c["output_root"])
    manifest = regular(out / "artifact_manifest.csv")
    with manifest.open(newline="") as f:
        reader = csv.DictReader(f)
        need(reader.fieldnames == ["relative_path", "size_bytes", "sha256"], "exact manifest columns required")
        rows = list(reader)
    names = [r["relative_path"] for r in rows]
    required = {"INNOVATION_REFERENCE_RECEIPT.json", "innovation_summary.json", "innovation_parity.csv",
        "innovation_draws.rds", *(f"progress_chain_{i}.json" for i in range(1, 5))}
    need(len(names) == len(set(names)) and required <= set(names), "complete receipt/summary/parity/chains/export required")
    need(all(p.is_file() and not p.is_symlink() for p in out.iterdir()) and
        {p.name for p in out.iterdir()} == set(names) | {"artifact_manifest.csv"}, "manifest must close the complete flat output")
    receipt = read_json(out / "INNOVATION_REFERENCE_RECEIPT.json")
    e = receipt["generated_draw_export"]
    need(e["path"] == str(out / "innovation_draws.rds") and e["relative_path"] == "innovation_draws.rds" and
        e["generated_array_only"] is True and e["full_parameter_posterior_draws"] is False and
        e["dimensions"] == [1000, 4, 28] and e["finite_values"] == 112000 and e["missing_values"] == 0,
        "complete finite four-chain generated path export required")
    for row in rows:
        rel = Path(row["relative_path"])
        need(rel.name == str(rel) and rel.name not in (".", "..", "artifact_manifest.csv"), "flat bounded manifest required")
        p = out / rel
        digest = generated_array_sha(p, out, c["draw_export"]["max_bytes"]) if rel.name == "innovation_draws.rds" else sha(p, c["limits"]["output_bytes"])
        need(p.stat().st_size == int(row["size_bytes"]) and digest == row["sha256"], "generated artifact manifest mismatch")
        if rel.name == "innovation_draws.rds":
            need(e["size_bytes"] == p.stat().st_size and e["sha256"] == digest, "export differs from receipt")
    need(receipt["schema_version"] == "glofas_innovation_reference_receipt_v1" and
        receipt["status"] == "PILOT_COMPLETE_NOT_PRODUCTION_QUALIFICATION" and
        receipt["source_commit"] == c["source_commit"] and receipt["source_tree"] == c["source_tree"], "reader success/source receipt missing")
    need(receipt["original_RDS_deserializations"] == 2 and receipt["generated_numeric_array_deserializations"] == 0 and
        receipt["saved_callback_calls"] == 0 and receipt["full_parameter_refits"] == 0 and receipt["future_truth_read"] is False and
        all(receipt.get(k) is False for k in QUALIFICATIONS), "receipt exceeds exact no-refit/no-promotion scope")
    summary = read_json(out / "innovation_summary.json")
    need(summary["schema_version"] == "glofas_innovation_reference_summary_v1" and
        summary["status"] == receipt["status"] and all(summary.get(k) is False for k in QUALIFICATIONS) and
        type(summary["diagnostic_thresholds_passed"]) is bool and
        summary["fixed_point"] == receipt["fixed_point"], "summary must retain the same nonpromoting pilot identity")
    reads = receipt["attempted_reads"]
    need(len(reads) == 2 and {r["role"] for r in reads} == {"design", "median_model"}, "exact two original read roles required")
    for r in reads:
        pin = c[r["role"]]
        need(r["pre_read_sha256"] == r["post_read_sha256"] == pin["sha256"] and r["status"] == "DESERIALIZED" and
            r["path"] == pin["path"] and r["size_bytes"] == pin["size_bytes"], "before/after original hash record did not close")
    proofs = receipt["worker_proofs"]
    need(len(proofs) == 4 and {int(p.get("logical_cpu", p.get("cpus", -1))) for p in proofs} == CPUS and
        len({p["pid"] for p in proofs}) == 4, "four native worker CPU/PID receipts required")
    for p in proofs:
        need(len(p["native_cpu_limits"]) == len(p["native_address_space_limits"]) == 2 and
            all(0 < float(x) <= c["limits"]["child_cpu_seconds"] for x in p["native_cpu_limits"]) and
            all(0 < float(x) <= c["limits"]["memory_bytes"] for x in p["native_address_space_limits"]) and
            0 <= p["CPU_seconds"] <= c["limits"]["child_cpu_seconds"], "worker native cap/CPU receipt differs")
        current = process(p["pid"])
        need(current is None or current["starttime_ticks"] != p["starttime"], "reader worker still live")
    need(type(receipt["aggregate_cpu_seconds"]) in (int, float) and
        sum(p["CPU_seconds"] for p in proofs) <= receipt["aggregate_cpu_seconds"] + 1e-6 and
        receipt["aggregate_cpu_seconds"] <= c["limits"]["aggregate_cpu_seconds"],
        "complete native CPU receipt exceeds cap or omits child CPU")
    for i in range(1, 5):
        progress = read_json(out / f"progress_chain_{i}.json")
        need(progress["schema_version"] == "glofas_innovation_progress_v1" and progress["chain_id"] == i and
            progress["completed_iterations"] == 1500 and progress["retained_iterations"] == 1000 and
            progress["fully_completed"] is True and progress["callback_evaluations"] == 1501,
            "independent terminal progress must close every complete named chain")
    verify_timing(receipt["timing_admission"])
    v = c["innovation"]
    for field, cap in (("forward_evaluations", v["max_total_forward_evaluations"]),
        ("inverse_evaluations", v["max_total_inverse_evaluations"]),
        ("reference_evaluations", v["max_total_reference_evaluations"])):
        need(type(receipt[field]) is int and 0 <= receipt[field] <= cap and summary[field] == receipt[field],
            "evaluation budget or summary/receipt mismatch: " + field)
    need(receipt["forward_evaluations"] >= 4 * 1501, "complete chains require their declared forward evaluations")
    return dict(output_manifest_verified=True, output_manifest_sha256=sha(manifest), reader_receipt=receipt,
        original_RDS_deserializations=2, generated_numeric_array_deserializations=0,
        saved_callback_calls=0, full_parameter_refits=0, future_truth_read=False)


def run_owned_job(*, c, control, argv, env, capture_live, verify_after):
    """Generated process fixtures may call this core; the CLI never accepts argv."""
    child = identity = None
    report = dict(schema_version="glofas_innovation_reference_native_terminal_v1", started_utc=utc(),
        source_commit=c.get("source_commit"), source_tree=c.get("source_tree"), computational_closure=False,
        statistical_qualification=False, original_payload_reads_by_controller=0,
        original_payload_hashes_by_controller=0, **{k: False for k in QUALIFICATIONS})
    try:
        shelltext = shlex.join(argv) + " > " + shlex.quote(str(control / "native.log")) + ' 2>&1\nnative_rc=$?\nexit "$native_rc"\n'
        child = subprocess.Popen(["/usr/bin/bash", "--noprofile", "--norc", "-c", shelltext], cwd=c["source_root"],
            env=env, start_new_session=True, stdin=subprocess.DEVNULL)
        identity = process(child.pid)
        need(identity and identity["pid"] == identity["session"] == identity["pgid"] and
            identity["ppid"] == os.getpid() and identity["uid"] == os.getuid(), "native isolated session authentication failed")
        report["owned_jobshell"] = identity
        proof = capture_live(child, identity)
        write_new(control / "native_start.json", proof)
        report["native_start_sha256"] = sha(control / "native_start.json")
        report.update(monitor(child, identity, c, control, proof.get("processes", {}).get("R")))
        need(report["native_exit_code"] == 0 and not owned_rows(identity), "nonzero native exit or surviving actors")
        report.update(verify_after())
        if "reader_receipt" in report:
            observed = {(p["pid"], p["starttime_ticks"]): p for p in report["independently_observed_workers"]}
            proofs = report["reader_receipt"]["worker_proofs"]
            need(len(observed) == 4 and {(p["pid"], p["starttime"]) for p in proofs} == set(observed),
                "four reader workers must match independent live observations")
            for p in proofs:
                live = observed[(p["pid"], p["starttime"])]
                need(p["ppid"] == live["ppid"] == proof["processes"]["R"]["pid"] and
                    p["pgrp"] == live["pgid"] == proof["processes"]["R"]["pgid"] and
                    int(p.get("logical_cpu", p.get("cpus", -1))) in cpu_set(live["CPUs_allowed_list"]),
                    "worker receipt/live parent-group-affinity mismatch")
        report.update(status="COMPUTATION_CLOSED_UNQUALIFIED_PILOT_NO_FULL_REFIT", computational_closure=True,
            owner_terminated=True, worker_terminated=True, timed_out=False)
    except BaseException as error:
        report.update(status="FAILED_OR_UNCLOSED_NOT_PROMOTABLE", error=repr(error),
            original_RDS_deserializations="UNKNOWN_NO_INDEPENDENT_CLOSED_RECEIPT" if child else 0)
        if child is not None:
            try:
                report["cleanup_actions"] = cleanup_owned(child, identity)
                report.update(owner_terminated=True, worker_terminated=True)
            except BaseException as cleanup_error:
                report["cleanup_error"] = repr(cleanup_error)
    report.update(finished_utc=utc(), supervisor_pid=os.getpid(), supervisor_exiting_after_terminal_write=True)
    write_new(control / "terminal.json", report)
    return 0 if report["computational_closure"] else 1


def supervise(control, script_sha, admission_sha):
    need(sha(SCRIPT) == script_sha and sha(Path(control) / "admission.json") == admission_sha, "detached controller/admission pin changed")
    a = read_json(Path(control) / "admission.json")
    control = private_control(control, a["nonce"])
    c, resources = validate_contract(a["purpose"], a["purpose_sha256"], launching=True)
    need(c["nonce"] == a["nonce"] and c["output_root"] == a["output_root"], "admission ownership changed")
    write_new(control / "supervisor_started.json", dict(pid=os.getpid(), start_utc=utc(), script_sha256=script_sha,
        admission_sha256=admission_sha, purpose_sha256=a["purpose_sha256"], resources=resources))
    def verify():
        need(sha(SCRIPT) == script_sha and sha(a["purpose"]) == a["purpose_sha256"], "purpose/controller changed after exit")
        pin_source(c)
        result = verify_manifest(c)
        need(result["reader_receipt"]["purpose_sha256"] == a["purpose_sha256"], "reader purpose differs")
        need("GLOFAS_INNOVATION_REFERENCE_PILOT_CLOSED_NO_PRODUCTION_QUALIFICATION" in
            regular(control / "native.log", c["limits"]["output_bytes"]).read_text(), "native success marker absent")
        result["purpose_sha256"] = a["purpose_sha256"]
        return result
    return run_owned_job(c=c, control=control, argv=native_command(c, a["purpose"], a["purpose_sha256"], control),
        env=native_environment(c), capture_live=lambda child, identity: capture(child, identity, c, a["purpose"], a["purpose_sha256"]),
        verify_after=verify)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--purpose", type=Path)
    parser.add_argument("--purpose-sha256")
    parser.add_argument("--launch", action="store_true")
    parser.add_argument("--supervise", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--script-sha256", help=argparse.SUPPRESS)
    parser.add_argument("--admission-sha256", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.supervise:
        need(not args.launch and not args.purpose, "supervisor cannot accept another launch")
        try:
            return supervise(args.supervise, args.script_sha256, args.admission_sha256)
        except BaseException as error:
            try:
                a = read_json(args.supervise / "admission.json")
                private_control(args.supervise, a["nonce"])
                if not (args.supervise / "terminal.json").exists():
                    write_new(args.supervise / "terminal.json", dict(status="PRE_NATIVE_ADMISSION_FAILED", error=repr(error),
                        computational_closure=False, original_RDS_deserializations=0, finished_utc=utc(),
                        **{k: False for k in QUALIFICATIONS}))
            except BaseException:
                pass
            return 1
    if args.purpose is None:
        need(not args.launch, "--launch requires explicit external --purpose and --purpose-sha256")
        print(json.dumps(dict(status="AUDIT_ONLY_NO_PURPOSE_NO_LAUNCH", original_reads=0, original_payload_hashes=0)))
        return 0
    c, resources = validate_contract(args.purpose, args.purpose_sha256, launching=args.launch)
    if not args.launch:
        print(json.dumps(dict(status="AUDIT_ONLY_NO_LAUNCH", resources=resources, purpose_sha256=args.purpose_sha256,
            original_reads=0, original_payload_hashes=0), indent=2))
        return 0
    control = new_control(c["nonce"])
    write_new(control / "admission.json", dict(nonce=c["nonce"], purpose=str(args.purpose),
        purpose_sha256=args.purpose_sha256, output_root=c["output_root"], admitted_utc=utc(),
        source_commit=c["source_commit"], source_tree=c["source_tree"]))
    proof = launch_tmux(control, c["nonce"], [sys.executable, "-B", str(SCRIPT), "--supervise", str(control),
        "--script-sha256", sha(SCRIPT), "--admission-sha256", sha(control / "admission.json")])
    write_new(control / "launcher_return.json", proof)
    print(json.dumps(dict(status="DETACHED_LAUNCH_ADMITTED_NOT_COMPLETED", control_dir=str(control),
        terminal=str(control / "terminal.json"), **proof), indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print("innovation-reference controller refused: " + str(error), file=sys.stderr)
        raise SystemExit(2)
