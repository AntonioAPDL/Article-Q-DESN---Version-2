"""Compute-node-only, data-free worker for the two startup qualification roles."""
import argparse
import hashlib
import importlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import resource
import signal
import stat
import subprocess
import sys
import tarfile
import time

FROZEN_RUNTIME_SOURCES = {
    "profile_supervisor.py": "7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1",
    "startup_helper.py": "8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b",
    "startup_helper_fixture.py": "ca44d1b8d14ba9a83d41917dc9deab66915849305e3aa909f2dcb50ed711f277",
    "startup_helper_kernel_tests.py": "b6cabf52572051dd6ebeeb67a07e7e88b96b1bba328ffa23d9caa75815285666",
    "startup_helper_metadata_fixture.R": "f169f05839101de46bdd2282069a31ec08c0aab153e4fb4459b269c853997826",
}


def require(value, message):
    if not value:
        raise ValueError(message)


def read_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate metadata JSON key")
            result[key] = value
        return result
    def bad(_): raise ValueError("nonfinite metadata JSON")
    def floating(value):
        result = float(value); require(math.isfinite(result), "nonfinite metadata JSON float")
        return result
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=bad, parse_float=floating)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_exact(value, maximum=16 * 1024**2):
    path = Path(value["path"])
    require(path.is_absolute() and not any(x.is_symlink() for x in (path, *path.parents)), "canonical metadata path required")
    before = path.stat(); require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1 and before.st_size <= maximum,
                                 "bounded regular metadata required")
    data = path.read_bytes(); after = path.stat()
    key = lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns, x.st_ctime_ns)
    require(key(before) == key(after) and hashlib.sha256(data).hexdigest() == value["sha256"], "exact staged bytes differ")
    return data


def pin(path):
    return dict(path=str(path), sha256=sha(path))


def write_new(path, value):
    path = Path(path)
    with path.open("x") as handle:
        json.dump(value, handle, sort_keys=True, indent=2, allow_nan=False)
        handle.write("\n"); handle.flush(); os.fsync(handle.fileno())
    descriptor = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try: os.fsync(descriptor)
    finally: os.close(descriptor)


def publish_atomic_new(path, value):
    """Publish complete private bytes atomically without replacing any name.

    POSIX hardlink creation has create-only name semantics on the shared
    filesystem. No renameat2 support, overwrite fallback, or retry is assumed.
    A successful return also proves the temporary link was removed and the
    final directory entry was fsynced. Any unsupported operation fails closed.
    """
    path = Path(path); partial = path.with_name(path.name + ".partial")
    require(path.is_absolute() and not any(x.is_symlink() for x in (path, *path.parents)),
            "canonical publication path without links required")
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    owned = None
    try:
        parent = os.fstat(directory)
        require(parent.st_uid == os.getuid() and parent.st_mode & 0o022 == 0,
                "private owned publication directory required")
        descriptor = os.open(partial.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=directory)
        info = os.fstat(descriptor); owned = (info.st_dev, info.st_ino, info.st_uid)
        with os.fdopen(descriptor, "w") as handle:
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_uid == os.getuid(),
                    "new private regular publication temporary required")
            json.dump(value, handle, sort_keys=True, indent=2, allow_nan=False)
            handle.write("\n"); handle.flush(); os.fsync(handle.fileno())
            info = os.fstat(handle.fileno())
            require(info.st_nlink == 1 and info.st_size <= 16 * 1024**2,
                    "bounded single-link publication temporary required")
        os.fsync(directory)
        os.link(partial.name, path.name, src_dir_fd=directory, dst_dir_fd=directory, follow_symlinks=False)
        source = os.stat(partial.name, dir_fd=directory, follow_symlinks=False)
        final = os.stat(path.name, dir_fd=directory, follow_symlinks=False)
        require(all(stat.S_ISREG(x.st_mode) and (x.st_dev, x.st_ino, x.st_uid) == owned
                    and x.st_nlink == 2 for x in (source, final)), "atomic publication link identity differs")
        os.unlink(partial.name, dir_fd=directory); owned = None
        final = os.stat(path.name, dir_fd=directory, follow_symlinks=False)
        require(stat.S_ISREG(final.st_mode) and final.st_nlink == 1
                and (final.st_dev, final.st_ino, final.st_uid) == (source.st_dev, source.st_ino, source.st_uid),
                "published metadata must have exactly one owned link")
        os.fsync(directory)
    finally:
        try:
            if owned is not None:
                current = os.stat(partial.name, dir_fd=directory, follow_symlinks=False)
                require(stat.S_ISREG(current.st_mode)
                        and (current.st_dev, current.st_ino, current.st_uid) == owned,
                        "unowned publication temporary cannot be removed")
                os.unlink(partial.name, dir_fd=directory)
                os.fsync(directory)
        finally:
            os.close(directory)


def bootstrap(spec_pin):
    spec = read_json(read_exact(spec_pin)); root = Path(spec["remote_root"])
    require(spec["schema"] == "pricefm_startup_batch_spec_v1"
            and spec["role"] in {"COMPUTE_RUNTIME_INVENTORY", "EXACT_R46_STARTUP_METADATA"}, "finite metadata-only role required")
    require(Path(__file__).absolute() == Path(spec["sources"]["startup_batch_worker.py"]["path"]), "worker source path differs")
    for value in spec["sources"].values(): read_exact(value)
    require(all(spec["sources"][name]["sha256"] == expected for name, expected in FROZEN_RUNTIME_SOURCES.items()),
            "frozen helper/original guard closure differs")
    require(time.time() + 1200 < spec["expires_epoch"], "whole admitted compute batch wall cannot fit scope")
    scope = read_json(read_exact(spec["scope"]))
    require(scope["status"] == "PROSPECTIVE_TWO_ROLE_HB_RUNTIME_QUALIFICATION_SCOPE"
            and scope["expires_epoch"] == spec["expires_epoch"], "current finite Q scope required")
    require(os.uname().nodename.split(".")[0] == spec["node"] == "node-13"
            and os.environ.get("SLURMD_NODENAME") == spec["node"]
            and os.environ.get("SLURM_CPUS_PER_TASK") == "1" and len(os.sched_getaffinity(0)) == 1,
            "worker cannot execute on a login/local host or outside its one-CPU Slurm allocation")
    job = os.environ.get("SLURM_JOB_ID", ""); require(job.isdigit(), "actual Slurm job id required")
    require(spec["aggregate_CPU_reservation"] == 600 and spec["wall_seconds"] == 1200
            and spec["memory_MiB"] == 8192
            and spec["component_CPU_caps"] == dict(shell_srun=30, worker=30, kernel_or_R_guard=30, launch_reserve=30)
            and spec["new_models"] == 0, "whole batch component/role funding differs")
    actual_python = Path(sys.executable).resolve(strict=True)
    require(sha(actual_python) == spec["cached_python_sha256"], "cached compute Python identity differs")
    package_parent = str(Path(__file__).absolute().parents[1])
    sys.path.insert(0, package_parent)
    helper = importlib.import_module("pricefm_hb.startup_helper")
    kernel = importlib.import_module("pricefm_hb.startup_helper_kernel_tests")
    for key in helper.THREAD_KEYS: require(os.environ.get(key) == "1", "worker thread environment differs")
    root.joinpath("result").mkdir(mode=0o700, exist_ok=True)
    return spec, scope, helper, kernel, job


def runtime_inventory(spec, job):
    affinity = sorted(os.sched_getaffinity(0)); core = affinity[0]
    helpers = {}
    for name in ("which", "uname"):
        logical = Path("/usr/bin") / name
        resolved = logical.resolve(strict=True)
        helpers[name] = dict(logical_path=str(logical), resolved_file=pin(resolved),
                             bytes=resolved.stat().st_size)
    fs = os.statvfs(spec["remote_root"])
    siblings = Path("/sys/devices/system/cpu/cpu%d/topology/thread_siblings_list" % core)
    return dict(status="COMPUTE_RUNTIME_FACTS_NO_R", job_id=job, node=os.uname().nodename.split(".")[0],
        hostname=os.uname().nodename, uname=list(os.uname()), affinity=affinity,
        cpus_per_task=1, python=pin(Path(sys.executable).resolve(strict=True)), python_version=sys.version,
        libc=os.confstr("CS_GNU_LIBC_VERSION"), helpers=helpers,
        thread_siblings_list=siblings.read_text().strip() if siblings.is_file() else None,
        filesystem=dict(path=spec["remote_root"], device=Path(spec["remote_root"]).stat().st_dev,
                        available_bytes=fs.f_bavail * fs.f_frsize),
        scientific_data_access=False, R_executions=0, optimizer_invocations=0)


def safe_member(name):
    value = PurePosixPath(name)
    require(not value.is_absolute() and ".." not in value.parts and value.parts
            and len(name) <= 512 and len(value.parts) <= 16
            and not ({".ssh", ".git", ".codex"} & set(value.parts)), "unsafe carrier member")
    return str(value)


def extract_carrier(spec):
    """All writes precede file fsyncs, then owned directory ancestry is synced."""
    root = Path(spec["remote_root"]); archive = spec["carrier"]
    read_exact(archive, 128 * 1024**2)
    manifest = read_json(read_exact(spec["carrier_manifest"]))
    rows = manifest["files"]
    require(type(rows) is list and 1 <= len(rows) <= 2048
            and all(type(x["bytes"]) is int and 0 <= x["bytes"] <= 64 * 1024**2
                    and type(x["mode"]) is int and 0 <= x["mode"] <= 0o777 for x in rows)
            and sum(x["bytes"] for x in rows) <= 128 * 1024**2, "finite data-free carrier shape required")
    expected = {safe_member(x["relative"]): x for x in rows}
    require(len(expected) == len(rows), "duplicate carrier paths")
    target = root / "runtime_carrier"; target.mkdir(mode=0o700)
    written = []
    with tarfile.open(archive["path"], "r:*") as package:
        seen = set()
        for index, member in enumerate(package):
            require(index < 2048, "carrier archive member bound exceeded")
            relative = safe_member(member.name)
            require(member.isfile() and relative not in seen and relative in expected
                    and member.size == expected[relative]["bytes"] and member.mode == expected[relative]["mode"],
                    "carrier symlink/hardlink/special or unexpected file")
            seen.add(relative)
            output = target / relative; output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            digest = hashlib.sha256(); count = 0
            with package.extractfile(member) as source, output.open("xb") as dest:
                while True:
                    block = source.read(1024 * 1024)
                    if not block: break
                    count += len(block); require(count <= member.size, "carrier file exceeded declared bytes")
                    dest.write(block); digest.update(block)
                os.fchmod(dest.fileno(), expected[relative]["mode"] & 0o777)
            require(count == member.size and digest.hexdigest() == expected[relative]["sha256"], "carrier file hash differs")
            written.append(output)
        require(seen == set(expected), "carrier archive missing declared runtime file")
    for path in written:
        descriptor = os.open(path, os.O_RDONLY)
        try: os.fsync(descriptor)
        finally: os.close(descriptor)
    directories = {target, root}
    for path in written:
        directories.update(x for x in path.parents if x == target or target in x.parents)
    for path in sorted(directories, key=lambda x: len(x.parts), reverse=True):
        descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
        try: os.fsync(descriptor)
        finally: os.close(descriptor)
    return dict(status="DURABLE_BYTE_IDENTICAL_RUNTIME_CARRIER_INSTALLED", root=str(target),
                manifest=spec["carrier_manifest"], file_count=len(rows), total_bytes=sum(x["bytes"] for x in rows),
                all_writes_before_file_sync=True, no_original_runtime_mutation=True,
                files=[dict(path=str(target / x["relative"]), sha256=x["sha256"]) for x in rows])


def validate_release(spec, spec_pin, ready_pin, release_pin):
    release = read_json(read_exact(release_pin))
    ready = read_json(read_exact(ready_pin)); now = time.time()
    require(release["status"] == "ROOT_RELEASED_STARTUP_BATCH_ROLE"
            and release["role"] == spec["role"] and release["scope_id"] == spec["scope_id"]
            and release["job_id"] == ready["job_id"] == os.environ.get("SLURM_JOB_ID")
            and release["node"] == ready["node"] == os.uname().nodename.split(".")[0]
            and release["ready_sha256"] == ready_pin["sha256"] and release["spec_sha256"] == spec_pin["sha256"]
            and release["sources"] == spec["sources"] and release["scope_sha256"] == spec["scope"]["sha256"],
            "actual source/READY/job/node bound root release required")
    require(release["issued_epoch"] <= now and now + 180 < release["expires_epoch"] <= spec["expires_epoch"],
            "complete proof lifecycle does not fit release/root deadline")
    folder = Path(spec["remote_root"]) / "release"
    require(type(release["files"]) is list and len(release["files"]) <= 16, "bounded release metadata set required")
    for row in release["files"]:
        name = safe_member(row["relative"]); require("/" not in name, "flat release metadata required")
        read_exact(dict(path=str(folder / name), sha256=row["sha256"]))
    peer_pin = release["independent_review"]; peer = read_json(read_exact(peer_pin))
    require(Path(peer_pin["path"]).parent == folder and peer["status"] == "PASS_REVIEWED_STARTUP_BATCH_RELEASE"
            and peer["role"] == spec["role"] and peer["job_id"] == ready["job_id"]
            and peer["ready_sha256"] == ready_pin["sha256"] and peer["spec_sha256"] == spec_pin["sha256"]
            and peer["sources"] == spec["sources"] and peer["node"] == ready["node"], "actual independent release review required")
    return release


def run_owned(command, stdout, stderr, *, timeout, kernel):
    import ctypes
    libc = ctypes.CDLL(None, use_errno=True)
    require(libc.prctl(36, 1, 0, 0, 0) == 0, "private worker subreaper unavailable")
    require(not kernel.children(os.getpid()), "worker must have no predecessor children")
    events = []; start = time.monotonic()
    with Path(stdout).open("xb") as out, Path(stderr).open("xb") as err:
        child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=out, stderr=err, close_fds=True, preexec_fn=lambda: None)
        identity = kernel.process_record(child.pid)
        require(identity["ppid"] == os.getpid() and identity["uid"] == os.getuid(), "new direct child identity differs")
        try:
            while time.monotonic() - start < timeout:
                kernel.reap_all(events, child)
                if child.returncode is not None and not kernel.children(os.getpid()): break
                time.sleep(.01)
            require(child.returncode is not None and not kernel.children(os.getpid()), "owned compute stage timed out")
        finally:
            if kernel.children(os.getpid()):
                require(kernel.drain_private(events, child, identity["start_ticks"]), "compute private stage drain failed")
        out.flush(); os.fsync(out.fileno()); err.flush(); os.fsync(err.fileno())
    return dict(returncode=child.returncode, all_private_descendants_reaped=not kernel.children(os.getpid()),
                reaped=events, wall_seconds=time.monotonic() - start)


def seal_return(spec, job, result):
    root = Path(spec["remote_root"]) / "result"
    write_new(root / "RESULT.json", result)
    rows = []
    for path in sorted(root.rglob("*")):
        if path.is_dir(): continue
        require(path.is_file() and not path.is_symlink(), "metadata return cannot contain links/special files")
        relative = safe_member(str(path.relative_to(root)))
        require(path.suffix.lower() not in {".rds", ".rda", ".rdata", ".npz", ".npy"}, "no scientific binary return")
        rows.append(dict(relative=relative, sha256=sha(path), bytes=path.stat().st_size))
    require(len(rows) <= spec["maximum_return_files"] and sum(x["bytes"] for x in rows) <= spec["maximum_return_bytes"],
            "bounded metadata return exceeded")
    write_new(root / "RETURN_MANIFEST.json", dict(schema="pricefm_startup_batch_return_manifest_v1",
        scope_id=spec["scope_id"], job_id=job, files=rows, new_models=0))


def main():
    p = argparse.ArgumentParser(description=__doc__); p.add_argument("--spec", required=True); p.add_argument("--sha256", required=True)
    args = p.parse_args(); resource.setrlimit(resource.RLIMIT_CPU, (30, 30)); resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    signal.alarm(1100)
    spec_pin = dict(path=args.spec, sha256=args.sha256)
    spec, scope, helper, kernel, job = bootstrap(spec_pin)
    root = Path(spec["remote_root"]); result_root = root / "result"
    ready_pin = None; release_pin = None; inventory = None; carrier = None; outcome = None; error = None
    try:
        inventory = runtime_inventory(spec, job); write_new(result_root / "INVENTORY.json", inventory)
        if spec["role"] == "EXACT_R46_STARTUP_METADATA":
            prior = spec["accepted_inventory"]
            require(prior["status"] == "ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE"
                    and prior["role"] == "COMPUTE_RUNTIME_INVENTORY" and prior["kernel_matrix_pass"] is True,
                    "actual accepted compute kernel role required before R")
            carrier = extract_carrier(spec); write_new(result_root / "CARRIER_INSTALL.json", carrier)
        ready = dict(status="READY_SOURCE_BOUND_COMPUTE_METADATA", role=spec["role"], scope_id=spec["scope_id"],
            job_id=job, node=spec["node"], spec_sha256=spec_pin["sha256"], sources=spec["sources"],
            affinity=inventory["affinity"], cpus_per_task=1, models=0, inventory=inventory,
            carrier=carrier, expires_epoch=spec["expires_epoch"])
        publish_atomic_new(root / "READY.json", ready); ready_pin = pin(root / "READY.json")
        release_path = root / "release/RELEASE.json"; until = min(time.monotonic() + spec["release_wait_seconds"],
            time.monotonic() + max(0, spec["expires_epoch"] - time.time() - 180))
        while not release_path.is_file() and time.monotonic() < until: time.sleep(.25)
        require(release_path.is_file(), "finite release wait ended; no payload automatically released")
        release_pin = pin(release_path); release = validate_release(spec, spec_pin, ready_pin, release_pin)
        context = dict(spec=spec_pin, ready=ready_pin, release=release_pin)
        context_path = result_root / "EXECUTION_CONTEXT.json"; write_new(context_path, context)
        if spec["role"] == "COMPUTE_RUNTIME_INVENTORY":
            command = [inventory["python"]["path"], "-I", "-B", spec["sources"]["startup_batch_kernel.py"]["path"],
                       "--context", str(context_path), "--sha256", sha(context_path)]
            stage = run_owned(command, result_root / "kernel_driver.stdout", result_root / "kernel_driver.stderr", timeout=185, kernel=kernel)
            require(stage["returncode"] == 0, "actual compute helper kernel matrix failed")
            outcome = read_json((result_root / "kernel/KERNEL_MATRIX_RESULT.json").read_text())
            require(outcome["status"] == "PASS_COMPUTE_OWNED_HELPER_KERNEL_MATRIX_NOT_R", "actual complete compute kernel PASS required")
            status = "INVENTORY_COMPLETE_KERNEL_PASS_NO_R"
        else:
            plan_pin, authority_pin, review_pin = (release[key] for key in ("startup_plan", "startup_authority", "startup_review"))
            plan = helper.read(plan_pin)
            require(plan["role"] == "R_STARTUP_METADATA_ONLY" and plan["placement"]["job_id"] == job,
                    "exact R metadata-only plan/job required")
            command = [inventory["python"]["path"], "-I", "-B", spec["sources"]["startup_helper.py"]["path"],
                "launch", "--plan", plan_pin["path"], "--authority", authority_pin["path"], "--review", review_pin["path"],
                "--cpu", str(plan["limits"]["CPU"]), "--wall", str(plan["limits"]["wall"])]
            guard = result_root / "R_guard.json"
            stage = run_owned(command, guard, result_root / "R_guard.stderr", timeout=plan["limits"]["wall"] + 5, kernel=kernel)
            require(stage["returncode"] == 0, "actual original R metadata guard failed")
            outcome = helper.finalize(plan_pin, authority_pin, review_pin, pin(guard))
            require(outcome["status"] == "PASS_R_METADATA_STARTUP_UNDER_OWNED_HELPER_GUARD", "actual compute-side R finalize did not pass")
            write_new(result_root / "R_STARTUP_PROOF.json", outcome)
            status = "R46_STARTUP_METADATA_PASS_NOT_NUMERICAL_PARITY"
    except BaseException as exc:
        status = "FAILED_METADATA_ROLE"; error = type(exc).__name__ + ": " + str(exc)
    own = resource.getrusage(resource.RUSAGE_SELF); waited = resource.getrusage(resource.RUSAGE_CHILDREN)
    result = dict(status=status, role=spec["role"], scope_id=spec["scope_id"], job_id=job,
        spec_sha256=spec_pin["sha256"], sources=spec["sources"], node=spec["node"], ready=ready_pin,
        release=release_pin, outcome=outcome, error=error, new_models=0, optimizer_invocations=0,
        worker_SELF_CPU_seconds=own.ru_utime + own.ru_stime, worker_waited_CPU_seconds=waited.ru_utime + waited.ru_stime,
        compute_component_bound_CPU=120, reserved_batch_CPU=600, canonical_sacct_required=True,
        counters_are_attribution_not_additional_charges=True, no_numerical_parity_or_target_bridge_proved=True)
    seal_return(spec, job, result)
    raise SystemExit(0 if error is None else 1)


if __name__ == "__main__":
    main()
