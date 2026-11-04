#!/usr/bin/env python3.11
"""Durable, exact-purpose Muscat reference-recovery pilot controller.

Default: audit only. --launch admits only the fixed R reader, never a command
from a contract. Original payloads are neither opened nor hashed here. Each
launch has its own private tmux socket; no default/existing server is queried.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve()
READER = "scripts/glofas_reference_recovery_reader.R"
RSCRIPT = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
CPUS = {20, 21, 22, 23, 26, 27, 28, 29}
PRODUCTION_PATHS = {
    "application/R/00_packages.R", "application/R/model_contract.R", "application/R/feature_contract.R",
    "application/R/covariate_design.R", "application/R/latent_path_design.R",
    "application/R/fit_qdesn_latent_path.R", "application/R/latent_path_vb_al.R",
}
# Must equal grrr_sources(), not merely contain the entrypoint. Tests and
# documentation are covered by the clean committed tree, not runtime closure.
SOURCE_PATHS = PRODUCTION_PATHS | {
    "scripts/glofas_fixed_target_forensic_reader.R", "scripts/glofas_same_family_closeout.R",
    "scripts/glofas_same_family_truth_bridge.R", "scripts/glofas_same_family_fitted_history.R",
    "scripts/glofas_nonlinear_replay_reader.R", "scripts/diagnostics/glofas_nonlinear_replay.R",
    "scripts/glofas_al_conditional_reference_reader.R", "scripts/diagnostics/glofas_al_path_reference.R",
    "scripts/diagnostics/glofas_compiled_value_reference.R", READER,
    "scripts/diagnostics/glofas_reference_recovery_kernels.R", "scripts/run_glofas_reference_recovery.py",
}
GiB = 1024 ** 3
MiB = 1024 ** 2
QUALIFICATIONS = ("reference_qualified", "full_posterior_accuracy_qualified",
                  "production_launch_authorized", "publication_authorized")


def need(ok, message):
    if not ok:
        raise ValueError(message)


def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def regular(path, max_bytes=4 * MiB):
    p = Path(path)
    need(p.is_absolute() and p.resolve() == p and not p.is_symlink(), "canonical nonsymlink path required")
    s = p.stat()
    need(stat.S_ISREG(s.st_mode) and s.st_size <= max_bytes, "bounded regular metadata/software required")
    need(p.suffix.lower() not in (".rds", ".rda", ".rdata"), "controller must not open original or generated R payloads")
    return p


def sha(path, max_bytes=4 * MiB):
    return hashlib.sha256(regular(path, max_bytes).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(regular(path).read_text())


def write_new(path, value):
    p = Path(path)
    need(not p.exists() and not p.is_symlink(), "refusing to overwrite controller evidence: " + str(p))
    # Publish a complete fsynced inode atomically. link(), unlike replace(),
    # cannot overwrite evidence that another actor creates after the check.
    fd, name = tempfile.mkstemp(prefix="." + p.name + ".pending-", dir=p.parent)
    pending = Path(name)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(value, f, indent=2, sort_keys=True)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.link(pending, p, follow_symlinks=False)
    finally:
        pending.unlink()
    directory_fd = os.open(p.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def git(root, *args):
    return subprocess.check_output(["/usr/bin/git", "--no-replace-objects", "-c", "core.fsmonitor=false",
        "-C", str(root), *args], text=True, stderr=subprocess.PIPE).strip()


def pin_source(c):
    root = Path(c["source_root"])
    need(root.is_absolute() and root.resolve() == root, "canonical source root required")
    need(git(root, "rev-parse", "--show-toplevel") == str(root) and
         git(root, "rev-parse", "HEAD") == c["source_commit"] and
         git(root, "rev-parse", "HEAD^{tree}") == c["source_tree"] and
         not git(root, "status", "--porcelain=v1", "--untracked-files=all"), "exact clean committed source required")
    need(re.fullmatch(r"[0-9a-f]{40}", c["source_commit"]) and
         re.fullmatch(r"[0-9a-f]{40}", c["source_tree"]), "full source identities required")
    pins = c["source_files"]
    paths = [Path(p["path"]) for p in pins]
    need(len(paths) == len(set(paths)) and set(paths) == {root / rel for rel in SOURCE_PATHS},
         "complete reader/controller/kernel source closure required")
    need(SCRIPT == root / "scripts/run_glofas_reference_recovery.py", "controller must run from admitted source")
    for p, pin in zip(paths, pins):
        need(p.is_relative_to(root) and p.suffix in (".R", ".py") and
             p.stat().st_size == pin["size_bytes"] and sha(p) == pin["sha256"], "source closure pin changed")
        rel = str(p.relative_to(root))
        need(git(root, "hash-object", "--no-filters", "--", rel) ==
             git(root, "rev-parse", c["source_commit"] + ":" + rel), "source not identical to committed blob")
    for rel in PRODUCTION_PATHS:
        need(git(root, "rev-parse", c["source_commit"] + ":" + rel) ==
             git(root, "rev-parse", "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6:" + rel),
             "production source differs from frozen original producer")


def cpu_set(value):
    result = set()
    for item in value.split(","):
        ends = [int(x) for x in item.split("-")]
        result.update(range(ends[0], ends[-1] + 1))
    return result


def process(pid):
    p = Path("/proc") / str(pid)
    for _ in range(3):
        try:
            text = (p / "stat").read_text()
            fields = text.rsplit(") ", 1)[1].split()
            status = (p / "status").read_text().splitlines()
            rss = next((int(x.split()[1]) * 1024 for x in status if x.startswith("VmRSS:")), 0)
            value = dict(pid=int(pid), comm=text[text.index("(") + 1:text.rindex(")")], state=fields[0],
                ppid=int(fields[1]), pgid=int(fields[2]), session=int(fields[3]), starttime_ticks=fields[19],
                uid=p.stat().st_uid, rss_bytes=rss, cpu_seconds=(int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK"),
                CPUs_allowed_list=next(x.split(":", 1)[1].strip() for x in status if x.startswith("Cpus_allowed_list:")),
                command=(p / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").strip(),
                limits=(p / "limits").read_text())
            end = (p / "stat").read_text()
            last = end.rsplit(") ", 1)[1].split()
            # A PID may disappear/reappear, exec, or change group while the
            # other proc files are read. Never return a mixed identity.
            if fields[19] == last[19] and fields[1:4] == last[1:4] and text.rsplit(") ", 1)[0] == end.rsplit(") ", 1)[0]:
                return value
        except (FileNotFoundError, ProcessLookupError, PermissionError, StopIteration):
            return None
    # A rapidly changing unrelated /proc entry must not abort a healthy job.
    # Owned-leader callers separately refuse an inconclusive live identity.
    return None


def process_table():
    return [row for p in Path("/proc").iterdir() if p.name.isdigit() and (row := process(int(p.name))) is not None]


def freshness(c):
    need(socket.gethostname().split(".")[0].lower() == "muscat", "native admission is Muscat only")
    b = c["limits"]
    available = int(next(x.split()[1] for x in Path("/proc/meminfo").read_text().splitlines()
                         if x.startswith("MemAvailable:"))) * 1024
    need(available >= b["aggregate_memory_bytes"] + b["memory_headroom_bytes"], "fresh aggregate RAM plus headroom gate failed")
    out = Path(c["output_root"])
    ancestor = out.parent
    while not ancestor.exists():
        ancestor = ancestor.parent
    free = shutil.disk_usage(ancestor).free
    need(free >= 80 * GiB, "80 GiB fresh disk headroom required")
    conflicts = [p["pid"] for p in process_table() if p["uid"] == os.getuid() and p["comm"] in ("R", "Rscript")
                 and cpu_set(p["CPUs_allowed_list"]) & CPUS]
    need(not conflicts, "allocated CPU conflict with existing R process: " + str(conflicts))
    return dict(observed_utc=utc(), MemAvailable_bytes=available, disk_free_bytes=free,
                protected_logical_cpus=[25, 30, 31, 48, 50], protected_physical_siblings=[16, 18])


def validate_contract(path, digest, *, launching=False):
    p = regular(Path(path))
    need(re.fullmatch(r"[a-f0-9]{64}", digest or "") and sha(p) == digest, "explicit exact external purpose SHA256 required")
    c = read_json(p)
    root = Path(c["source_root"])
    need(not p.is_relative_to(root), "purpose must be external to committed source")
    need(c["schema_version"] == "glofas_reference_recovery_contract_v1" and
         c["purpose"] == "MEDIAN_AL_FIXED_PARAMETER_TWO_ARM_KERNEL_RECOVERY_PILOT_NO_FULL_REFIT" and
         c["mode"] == "computational_pilot" and c["execution_mode"] == "fork_eight", "only exact nonpromoting eight-worker pilot admitted")
    need(re.fullmatch(r"[a-f0-9]{32,64}", c["nonce"]), "purpose nonce required")
    for key in ("allow_full_parameter_refit", "allow_parameter_updates", "allow_prior_updates", "allow_saved_callbacks",
                "allow_truth_read", "allow_retuning", "allow_scoring", "allow_article_changes", "allow_publication"):
        need(c.get(key) is False, "forbidden permission: " + key)
    b = c["limits"]
    scalar_keys = ("cpu_seconds", "wall_seconds", "memory_bytes", "output_bytes", "logical_cpu", "max_workers",
                   "child_cpu_seconds", "aggregate_cpu_seconds", "aggregate_memory_bytes", "memory_headroom_bytes", "max_draw_memory_bytes")
    need(all(type(b[k]) is int and b[k] > 0 for k in scalar_keys), "finite positive integer native budgets required")
    need(60 <= b["cpu_seconds"] <= 3600 and b["cpu_seconds"] <= b["wall_seconds"] <= 3600 and
         b["child_cpu_seconds"] == b["cpu_seconds"] and b["memory_bytes"] == 16 * GiB and
         b["output_bytes"] <= 64 * MiB and b["logical_cpu"] in (20, 26) and b["max_workers"] == 8 and
         set(b["child_logical_cpus"]) == CPUS and len(b["child_logical_cpus"]) == 8 and
         b["aggregate_cpu_seconds"] >= b["cpu_seconds"] + 8 * b["child_cpu_seconds"] and
         b["aggregate_memory_bytes"] >= 144 * GiB and b["aggregate_memory_bytes"] >= 9 * b["memory_bytes"] and
         b["memory_headroom_bytes"] >= 180 * GiB, "exact protected native pilot allocation required")
    expires = dt.datetime.fromisoformat(c["expires_utc"].replace("Z", "+00:00"))
    need(expires > dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=b["wall_seconds"] + 60), "purpose expires before native closure allowance")
    out = Path(c["output_root"])
    need(out.is_absolute() and out.resolve() == out and not out.is_symlink() and
         out.is_relative_to(root / "local_trackers") and out.parent.is_dir() and
         git(root, "check-ignore", "--", str(out)) == str(out), "canonical exclusive ignored local_trackers output required")
    if launching:
        need(not out.exists(), "output directory already exists; retries require separate authority")
    scratch = Path(c["metadata_scratch_root"])
    need(scratch.is_absolute() and scratch.resolve() == scratch and scratch.is_dir() and not scratch.is_symlink()
         and not list(scratch.iterdir()), "fresh task-owned empty metadata scratch required")
    need(not scratch.is_relative_to(root) or git(root, "check-ignore", "--", str(scratch)) == str(scratch),
         "metadata scratch inside source must be ignored")
    pin_source(c)
    # Only small prerequisite metadata is inspected. Never inspect design,
    # median_model, calibration_draws, or any original RDS in Python.
    metadata = [*c["baseline"].values(), *c["prior_replay"].values(), c["collection"], c["input_manifest"],
                c["diagnostic_dependencies"]["versions"], c["diagnostic_dependencies"]["sources"]]
    for pin in metadata:
        need(Path(pin["path"]).stat().st_size == pin["size_bytes"] and sha(pin["path"]) == pin["sha256"], "baseline metadata pin changed")
    return c, freshness(c)


def private_control(directory, nonce):
    p = Path(directory)
    need(p.is_absolute() and p.resolve() == p and not p.is_symlink(), "canonical private control directory required")
    s = p.stat()
    need(stat.S_ISDIR(s.st_mode) and s.st_uid == os.getuid() and stat.S_IMODE(s.st_mode) == 0o700,
         "private control directory must be owned mode 0700")
    marker = read_json(p / "ownership.json")
    need(marker == dict(nonce=nonce, uid=os.getuid(), directory_device=s.st_dev, directory_inode=s.st_ino), "control directory ownership changed")
    return p


def new_control(nonce):
    p = Path(tempfile.mkdtemp(prefix="qdesn-refrec-" + nonce[:12] + "-"))
    os.chmod(p, 0o700)
    s = p.stat()
    write_new(p / "ownership.json", dict(nonce=nonce, uid=os.getuid(), directory_device=s.st_dev, directory_inode=s.st_ino))
    return p


def launch_tmux(control, nonce, supervisor_argv):
    """Internal primitive; production supplies only this pinned script's argv."""
    p = private_control(control, nonce)
    sock = p / "server.sock"
    need(not sock.exists() and not sock.is_symlink(), "never attach to or mutate an existing tmux socket")
    need(all(isinstance(x, str) and "\0" not in x for x in supervisor_argv), "invalid supervisor argument")
    session = "refrec_" + nonce
    result = subprocess.run(["/usr/bin/tmux", "-S", str(sock), "-f", "/dev/null", "new-session", "-d", "-s", session,
        "exec " + shlex.join(supervisor_argv)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
    need(result.returncode == 0, "private tmux launch failed: " + result.stderr[-2000:])
    return dict(socket=str(sock), session=session, nonce=nonce, initial_launcher_pid=os.getpid(), initial_launcher_return_utc=utc())


def native_command(c, purpose, digest, control):
    b = c["limits"]
    argv = ["/usr/bin/time", "-v", "-o", str(control / "native.time.txt"), "/usr/bin/taskset", "-c", str(b["logical_cpu"]),
        "/usr/bin/timeout", "--signal=TERM", "--kill-after=1s", str(b["wall_seconds"] - 1) + "s", "/usr/bin/prlimit",
        f'--cpu={b["cpu_seconds"]}:{b["cpu_seconds"]}', f'--as={b["memory_bytes"]}:{b["memory_bytes"]}',
        f'--fsize={b["output_bytes"]}:{b["output_bytes"]}', str(RSCRIPT), "--vanilla", READER,
        "--contract", str(purpose), "--sha256", digest, "--execute"]
    return argv


def native_environment(c):
    env = os.environ.copy()
    env.update({x: "1" for x in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
                                "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS")})
    env.update(LD_PRELOAD="", BASH_ENV="", ENV="", R_ENVIRON_USER="/dev/null", R_PROFILE_USER="/dev/null",
               TMPDIR=c["metadata_scratch_root"])
    if "diagnostic_dependencies" in c:
        env["R_LIBS_USER"] = c["diagnostic_dependencies"]["library_root"]
    return env


def owned_rows(identity):
    for _ in range(3):
        leader = process(identity["pid"])
        if leader is not None or not (Path("/proc") / str(identity["pid"])).exists():
            break
        time.sleep(.01)
    else:
        raise ValueError("owned session leader identity remained inconclusive; refusing closure or signal")
    need(leader is None or leader["starttime_ticks"] == identity["starttime_ticks"], "session leader PID reused; refusing signal")
    return [p for p in process_table() if p["session"] == identity["session"] and p["uid"] == os.getuid() and p["state"] != "Z"]


def cleanup_owned(child, identity):
    need(identity and identity["pid"] == identity["session"] == identity["pgid"] == child.pid and
         identity["ppid"] == os.getpid() and identity["uid"] == os.getuid(), "authenticated isolated Popen session required")
    actions = []
    for sig in (signal.SIGTERM, signal.SIGKILL):
        rows = owned_rows(identity)
        for group in sorted({r["pgid"] for r in rows}):
            # Reinspect immediately, including groups timeout created before
            # full capture. Never signal a group with a foreign member.
            members = validated_group(identity, group, rows)
            if not members:
                continue
            try:
                os.killpg(group, sig)
                actions.append(dict(pgid=group, signal=int(sig), pids=[r["pid"] for r in members]))
            except ProcessLookupError:
                pass
        try:
            child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
        if not owned_rows(identity):
            break
    deadline = time.monotonic() + 2
    while owned_rows(identity) and time.monotonic() < deadline:
        time.sleep(.05)
    need(not owned_rows(identity), "native session failed to close")
    return actions


def validated_group(identity, group, rows):
    """Retry a new owned fork; never retry through a foreign group member."""
    for _ in range(4):
        members = [r for r in process_table() if r["pgid"] == group and r["state"] != "Z"]
        need(all(r["session"] == identity["session"] and r["uid"] == os.getuid() for r in members),
             "foreign process group member; refusing signal")
        if all(any(x["pid"] == r["pid"] and x["starttime_ticks"] == r["starttime_ticks"] for x in rows) for r in members):
            return members
        rows = owned_rows(identity)  # reauthenticate leader and new children
        time.sleep(.01)
    raise ValueError("owned process group snapshot remained unstable; refusing signal")


CONTROL_JSON_NAMES = {"ownership.json", "admission.json", "launcher_return.json", "supervisor_started.json",
                      "native_start.json", "terminal.json"}


def expected_pending(path, control, output_root):
    if path.parent == output_root:
        return bool(re.fullmatch(r"progress_worker_0[1-8]\.json\.new", path.name))
    if path.parent == control:
        return any(re.fullmatch(re.escape("." + name + ".pending-") + r"[a-z0-9_]{8}", path.name)
                   for name in CONTROL_JSON_NAMES)
    return False


def scan_output_bytes(control, output_root):
    """Bounded rescan of expected atomic publishers; no payload opens."""
    control, output_root = Path(control), Path(output_root)
    for _ in range(4):
        total = 0
        retry = False
        control_inodes = set()
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
                    need(not stat.S_ISLNK(s.st_mode), "symlink in owned output snapshot")
                    if stat.S_ISDIR(s.st_mode):
                        visit(p)
                    elif stat.S_ISREG(s.st_mode):
                        # Atomic link publication briefly has two names for
                        # one control-metadata inode. Charge its bytes once.
                        atomic_control = p.parent == control and (p.name in CONTROL_JSON_NAMES or expected_pending(p, control, output_root))
                        inode = (s.st_dev, s.st_ino)
                        if not atomic_control or inode not in control_inodes:
                            total += s.st_size
                        if atomic_control:
                            control_inodes.add(inode)
                    else:
                        need(p == control / "server.sock" and stat.S_ISSOCK(s.st_mode), "unexpected special file in owned output snapshot")
        visit(control)
        try:
            visit(output_root)
        except FileNotFoundError as error:
            # Native output is legitimately absent during startup; an entry
            # disappearing inside an existing output directory is not.
            if error.filename != str(output_root):
                raise
        if not retry:
            return total
        time.sleep(.005)
    raise ValueError("output snapshot remained unstable after bounded atomic-publication rescans")


def capture(child, identity, c, purpose, digest):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        rows = owned_rows(identity)
        shell = next((p for p in rows if p["pid"] == child.pid), None)
        timep = next((p for p in rows if p["ppid"] == child.pid and p["comm"] == "time"), None)
        timeout = next((p for p in rows if timep and p["ppid"] == timep["pid"] and p["comm"] == "timeout"), None)
        worker = next((p for p in rows if timeout and p["ppid"] == timeout["pid"] and p["comm"] in ("R", "Rscript")), None)
        if all((shell, timep, timeout, worker)):
            need(timeout["pgid"] == worker["pgid"] == timeout["pid"] and
                 worker["CPUs_allowed_list"] == str(c["limits"]["logical_cpu"]) and
                 str(purpose) in worker["command"] and digest in worker["command"] and READER in worker["command"], "native lineage/affinity/exact-purpose command proof failed")
            for key, value in (("Max cpu time", c["limits"]["cpu_seconds"]),
                               ("Max address space", c["limits"]["memory_bytes"]), ("Max file size", c["limits"]["output_bytes"])):
                fields = next(x for x in worker["limits"].splitlines() if x.startswith(key)).split()
                need(fields[-3:-1] == [str(value), str(value)], "native hard/soft limit differs: " + key)
            return dict(observed_utc=utc(), processes=dict(shell=shell, time=timep, timeout=timeout, R=worker),
                        native_limits_verified=True, source_commit=c["source_commit"], source_tree=c["source_tree"], purpose_sha256=digest)
        need(child.poll() is None, "native exited before full live four-role proof")
        time.sleep(.05)
    raise TimeoutError("live process capture exceeded 15 seconds")


def monitor(child, identity, c, control):
    started = time.monotonic()
    cpu_max = {}
    peak_rss = 0
    while child.poll() is None:
        rows = owned_rows(identity)
        for p in rows:
            key = (p["pid"], p["starttime_ticks"])
            cpu_max[key] = max(cpu_max.get(key, 0), p["cpu_seconds"])
        peak_rss = max(peak_rss, sum(p["rss_bytes"] for p in rows))
        need(peak_rss <= c["limits"]["aggregate_memory_bytes"], "aggregate RSS budget exceeded")
        need(sum(cpu_max.values()) <= c["limits"]["aggregate_cpu_seconds"], "aggregate sampled CPU budget exceeded")
        need(time.monotonic() - started <= c["limits"]["wall_seconds"] + 20, "outer wall deadline exceeded")
        total = scan_output_bytes(control, c["output_root"])
        need(total <= c["limits"]["output_bytes"], "aggregate compact output budget exceeded")
        time.sleep(.25)
    return dict(native_exit_code=child.wait(), sampled_aggregate_cpu_seconds=sum(cpu_max.values()), peak_aggregate_RSS_bytes=peak_rss)


def generated_array_sha(path, output_root, limit):
    """Only exact new pilot export names; never usable for an original input."""
    p = Path(path)
    need(p.parent == Path(output_root) and p.name in
         ("calibrated_random_walk_draws.rds", "mixture_random_walk_student_t_draws.rds") and
         p.is_file() and not p.is_symlink() and p.resolve() == p and p.stat().st_size <= limit,
         "only exact bounded generated pilot exports may be hashed")
    return hashlib.sha256(p.read_bytes()).hexdigest()


def verify_manifest(c):
    out = Path(c["output_root"])
    manifest = regular(out / "artifact_manifest.csv")
    with manifest.open(newline="") as f:
        reader = csv.DictReader(f)
        need(reader.fieldnames == ["relative_path", "size_bytes", "sha256"], "exact generated manifest columns required")
        rows = list(reader)
    names = [r["relative_path"] for r in rows]
    need(len(names) == len(set(names)) and "REFERENCE_RECOVERY_RECEIPT.json" in names, "receipt must be manifest-bound")
    need(all(p.is_file() and not p.is_symlink() for p in out.iterdir()) and
         {p.name for p in out.iterdir()} == set(names) | {"artifact_manifest.csv"}, "manifest must close the complete flat native output directory")
    receipt = read_json(out / "REFERENCE_RECOVERY_RECEIPT.json")
    exports = receipt.get("generated_draw_exports", [])
    expected_exports = {"calibrated_random_walk_draws.rds", "mixture_random_walk_student_t_draws.rds"}
    need(len(exports) == 2 and {e["relative_path"] for e in exports} == expected_exports and expected_exports <= set(names),
         "both exact generated pilot arrays required")
    for e in exports:
        need(e["path"] == str(out / e["relative_path"]) and e["generated_array_only"] is True and
             e["full_parameter_posterior_draws"] is False and e["dimensions"] == [1000, 4, 28] and
             e["missing_values"] >= 0 and e["finite_values"] >= 0 and
             e["finite_values"] + e["missing_values"] == 1000 * 4 * 28,
             "typed all-chain generated export receipt required")
    for row in rows:
        rel = Path(row["relative_path"])
        need(rel.name == str(rel) and rel.name not in (".", "..", "artifact_manifest.csv"), "flat bounded output manifest required")
        p = out / rel
        digest = generated_array_sha(p, out, c["draw_export"]["max_bytes"]) if rel.name in expected_exports else sha(p, c["limits"]["output_bytes"])
        need(p.stat().st_size == int(row["size_bytes"]) and digest == row["sha256"], "generated artifact manifest mismatch")
        if rel.name in expected_exports:
            e = next(e for e in exports if e["relative_path"] == rel.name)
            need(e["size_bytes"] == p.stat().st_size and e["sha256"] == digest, "generated export receipt differs from manifest")
    need(receipt["schema_version"] == "glofas_reference_recovery_receipt_v1" and
         receipt["status"] == "PILOT_COMPLETE_NOT_PRODUCTION_QUALIFICATION" and
         receipt["source_commit"] == c["source_commit"] and receipt["source_tree"] == c["source_tree"], "reader success/source receipt missing")
    need(receipt["original_RDS_deserializations"] == 2 and receipt["generated_numeric_array_deserializations"] == 1 and
         receipt["saved_callback_calls"] == 0 and receipt["full_parameter_refits"] == 0 and receipt["future_truth_read"] is False and
         all(receipt.get(k) is False for k in QUALIFICATIONS), "pilot receipt exceeds admitted no-fit/no-promotion scope")
    reads = receipt["attempted_reads"]
    need(len(reads) == 3, "all three reader before/after hash records required")
    by_role = {r["role"]: r for r in reads}
    need(set(by_role) == {"design", "median_model", "calibration_draws"}, "exact original/generated read roles required")
    for role, r in by_role.items():
        need(r.get("pre_read_sha256", r.get("sha256")) == r.get("post_read_sha256") == c[role]["sha256"] and
             r.get("status") == "DESERIALIZED" and r["path"] == c[role]["path"] and
             r["size_bytes"] == c[role]["size_bytes"], "reader-recorded before/after original hash did not close")
    proofs = receipt["worker_proofs"]
    need(len(proofs) == 8, "eight source-reader worker proofs required")
    # The R reader validates each worker's actual native caps and assignment;
    # controller independently requires exactly the admitted allocation.
    cpus = [int(p.get("logical_cpu", p.get("cpus", p.get("cpu", -1)))) for p in proofs]
    need(set(cpus) == CPUS and len({p.get("pid", p.get("PID")) for p in proofs}) == 8, "worker CPU/PID closure mismatch")
    for p in proofs:
        need(len(p["native_cpu_limits"]) == len(p["native_address_space_limits"]) == 2 and
             all(0 < float(x) <= c["limits"]["child_cpu_seconds"] for x in p["native_cpu_limits"]) and
             all(0 < float(x) <= c["limits"]["memory_bytes"] for x in p["native_address_space_limits"]) and
             0 <= p["CPU_seconds"] <= c["limits"]["child_cpu_seconds"], "worker native cap/CPU receipt differs")
        current = process(p["pid"])
        need(current is None or current["starttime_ticks"] != p["starttime"], "source-reader worker still live")
    return dict(output_manifest_verified=True, output_manifest_sha256=sha(manifest), reader_receipt=receipt,
                original_RDS_deserializations=2, generated_numeric_array_deserializations=1,
                saved_callback_calls=0, full_parameter_refits=0, future_truth_read=False)


def run_owned_job(*, c, control, argv, env, capture_live, verify_after):
    """Supervision core. Tests use generated tiny jobs; CLI never accepts argv."""
    child = None
    identity = None
    report = dict(schema_version="glofas_reference_recovery_native_terminal_v1", started_utc=utc(),
                  source_commit=c.get("source_commit"), source_tree=c.get("source_tree"),
                  computational_closure=False, statistical_qualification=False,
                  original_payload_reads_by_controller=0, original_payload_hashes_by_controller=0,
                  **{k: False for k in QUALIFICATIONS})
    try:
        # Retain assignment after the command: bash must not exec-optimize the
        # final command, since its authenticated session is the cleanup anchor.
        shelltext = shlex.join(argv) + " > " + shlex.quote(str(control / "native.log")) + ' 2>&1\nnative_rc=$?\nexit "$native_rc"\n'
        child = subprocess.Popen(["/usr/bin/bash", "--noprofile", "--norc", "-c", shelltext],
            cwd=c["source_root"], env=env, start_new_session=True, stdin=subprocess.DEVNULL)
        identity = process(child.pid)
        need(identity and identity["pid"] == identity["session"] == identity["pgid"] and
             identity["ppid"] == os.getpid() and identity["uid"] == os.getuid(), "immediate native session authentication failed")
        report["owned_jobshell"] = identity
        proof = capture_live(child, identity)
        write_new(control / "native_start.json", proof)
        report["native_start_sha256"] = sha(control / "native_start.json")
        report.update(monitor(child, identity, c, control))
        need(report["native_exit_code"] == 0, "native job returned nonzero")
        need(not owned_rows(identity), "native session has surviving actors after shell exit")
        report.update(verify_after())
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
    report["finished_utc"] = utc()
    report["supervisor_pid"] = os.getpid()
    report["supervisor_exiting_after_terminal_write"] = True
    write_new(control / "terminal.json", report)
    return 0 if report["computational_closure"] else 1


def supervise(control, script_sha, admission_sha):
    need(sha(SCRIPT) == script_sha, "detached controller script pin changed")
    admission_path = Path(control) / "admission.json"
    need(sha(admission_path) == admission_sha, "detached admission pin changed")
    a = read_json(admission_path)
    control = private_control(control, a["nonce"])
    # Revalidate freshness immediately before native start. Native output must
    # still be absent; the detached controller alone owns its creation by R.
    c, resources = validate_contract(a["purpose"], a["purpose_sha256"], launching=True)
    need(c["nonce"] == a["nonce"] and str(Path(c["output_root"])) == a["output_root"], "admission purpose ownership changed")
    write_new(control / "supervisor_started.json", dict(pid=os.getpid(), start_utc=utc(), script_sha256=script_sha,
        admission_sha256=admission_sha, purpose_sha256=a["purpose_sha256"], resources=resources))
    def verify():
        need(sha(SCRIPT) == script_sha and sha(a["purpose"]) == a["purpose_sha256"], "purpose/controller pin changed after native exit")
        pin_source(c)
        result = verify_manifest(c)
        need(result["reader_receipt"]["purpose_sha256"] == a["purpose_sha256"], "reader purpose receipt differs")
        start = read_json(control / "native_start.json")["processes"]["R"]
        need(all(p["ppid"] == start["pid"] and p["pgrp"] == start["pgid"]
                 for p in result["reader_receipt"]["worker_proofs"]), "source-reader child lineage differs from independent live native proof")
        need("GLOFAS_REFERENCE_RECOVERY_PILOT_CLOSED_NO_PRODUCTION_QUALIFICATION" in
             regular(control / "native.log", c["limits"]["output_bytes"]).read_text(), "native R success marker absent")
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
        need(not args.launch and not args.purpose, "internal supervisor cannot accept a new launch")
        try:
            return supervise(args.supervise, args.script_sha256, args.admission_sha256)
        except BaseException as error:
            # Admission failures also leave durable evidence, before any R read.
            try:
                admission = read_json(args.supervise / "admission.json")
                private_control(args.supervise, admission["nonce"])
                owned_control = True
            except BaseException:
                owned_control = False
            if owned_control and not (args.supervise / "terminal.json").exists():
                write_new(args.supervise / "terminal.json", dict(status="PRE_NATIVE_ADMISSION_FAILED", error=repr(error),
                    computational_closure=False, original_RDS_deserializations=0, finished_utc=utc(),
                    **{k: False for k in QUALIFICATIONS}))
            return 1
    if args.purpose is None:
        need(not args.launch, "--launch requires explicit external --purpose and --purpose-sha256")
        print(json.dumps(dict(status="AUDIT_ONLY_NO_PURPOSE_NO_LAUNCH", original_reads=0, original_payload_hashes=0)))
        return 0
    c, resources = validate_contract(args.purpose, args.purpose_sha256, launching=args.launch)
    if not args.launch:
        print(json.dumps(dict(status="AUDIT_ONLY_NO_LAUNCH", purpose_sha256=args.purpose_sha256, resources=resources,
                              original_reads=0, original_payload_hashes=0), indent=2))
        return 0
    control = new_control(c["nonce"])
    admission = dict(nonce=c["nonce"], purpose=str(args.purpose), purpose_sha256=args.purpose_sha256,
                     output_root=c["output_root"], admitted_utc=utc(), source_commit=c["source_commit"], source_tree=c["source_tree"])
    write_new(control / "admission.json", admission)
    script_sha = sha(SCRIPT)
    proof = launch_tmux(control, c["nonce"], [sys.executable, "-B", str(SCRIPT), "--supervise", str(control),
        "--script-sha256", script_sha, "--admission-sha256", sha(control / "admission.json")])
    write_new(control / "launcher_return.json", proof)
    print(json.dumps(dict(status="DETACHED_LAUNCH_ADMITTED_NOT_COMPLETED", control_dir=str(control),
                          terminal=str(control / "terminal.json"), **proof), indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print("reference-recovery controller refused: " + str(error), file=sys.stderr)
        raise SystemExit(2)
