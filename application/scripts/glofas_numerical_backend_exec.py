#!/usr/bin/env python3
"""Run one GloFAS child process under a hash-pinned numerical backend."""

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys


BACKENDS = {"bundled_rblas", "openblas_serial", "openblas_pthread"}
THREAD_ENV = (
    "OMP_NUM_THREADS",
    "OMP_THREAD_LIMIT",
    "OPENBLAS_NUM_THREADS",
    "GOTO_NUM_THREADS",
    "MKL_NUM_THREADS",
    "BLIS_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS",
    "NUMEXPR_NUM_THREADS",
)


def timestamp():
    return dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds")


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def atomic_json(path, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def normalize_cpu_set(value):
    values = []
    for token in str(value or "").split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lower, upper = (int(part) for part in token.split("-", 1))
            if lower > upper:
                raise ValueError(f"Invalid CPU range: {token}")
            values.extend(range(lower, upper + 1))
        else:
            values.append(int(token))
    if len(values) != len(set(values)) or any(value < 0 for value in values):
        raise ValueError("CPU set must contain distinct nonnegative CPU IDs")
    return values


def prepare_backend(backend, threads, library_path="", library_sha256="", base_env=None):
    if backend not in BACKENDS:
        raise ValueError(f"Unsupported numerical backend: {backend}")
    if threads < 1:
        raise ValueError("Backend thread count must be positive")
    env = dict(base_env or os.environ)
    for name in THREAD_ENV:
        env[name] = str(threads)
    env["QDESN_NUMERICAL_BACKEND"] = backend
    resolved = ""
    observed_hash = ""
    if backend == "bundled_rblas":
        if library_path or library_sha256:
            raise ValueError("Bundled R BLAS cannot declare an external library")
        env.pop("QDESN_BLAS_LIBRARY_PATH", None)
        env.pop("QDESN_BLAS_LIBRARY_SHA256", None)
        preload = env.get("LD_PRELOAD", "")
        if any(name in preload.lower() for name in ("openblas", "mkl", "blis")):
            raise ValueError("Bundled R BLAS inherited an external BLAS preload")
    else:
        if not library_path or not library_sha256:
            raise ValueError("OpenBLAS requires a concrete library path and SHA-256")
        resolved = str(Path(library_path).resolve(strict=True))
        observed_hash = sha256_file(resolved)
        if observed_hash.lower() != library_sha256.lower():
            raise ValueError(
                f"OpenBLAS hash mismatch: expected {library_sha256}, observed {observed_hash}"
            )
        inherited = env.get("LD_PRELOAD", "")
        inherited_parts = [part for part in inherited.split(":") if part]
        conflicting = [
            part for part in inherited_parts
            if any(name in part.lower() for name in ("openblas", "mkl", "blis"))
            and str(Path(part).resolve(strict=False)) != resolved
        ]
        if conflicting:
            raise ValueError(f"Conflicting inherited numerical preload: {conflicting}")
        env["LD_PRELOAD"] = ":".join([resolved] + [
            part for part in inherited_parts if str(Path(part).resolve(strict=False)) != resolved
        ])
        env["QDESN_BLAS_LIBRARY_PATH"] = resolved
        env["QDESN_BLAS_LIBRARY_SHA256"] = observed_hash
    return env, {
        "backend": backend,
        "threads": threads,
        "library_path": resolved,
        "library_sha256": observed_hash,
    }


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", choices=sorted(BACKENDS), default="bundled_rblas")
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--library", default="")
    parser.add_argument("--sha256", default="")
    parser.add_argument("--cpu-set", default="")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("a child command is required after --")
    return args


def main(argv=None):
    args = parse_args(argv)
    cpu_ids = normalize_cpu_set(args.cpu_set)
    if cpu_ids and len(cpu_ids) < args.threads:
        raise ValueError("CPU set is smaller than the requested backend thread count")
    env, backend_manifest = prepare_backend(
        args.backend,
        args.threads,
        args.library,
        args.sha256,
    )
    command = list(args.command)
    if cpu_ids:
        command = ["taskset", "-c", ",".join(str(value) for value in cpu_ids)] + command
    manifest = {
        "schema_version": "glofas_numerical_backend_execution_v1",
        "status": "running",
        "started_at": timestamp(),
        "finished_at": None,
        "return_code": None,
        "pid": os.getpid(),
        "host": platform.node(),
        "working_directory": os.getcwd(),
        "cpu_set": cpu_ids,
        "command": command,
        **backend_manifest,
    }
    atomic_json(args.manifest, manifest)
    try:
        result = subprocess.run(command, env=env, check=False)
        manifest["return_code"] = result.returncode
        manifest["status"] = "completed" if result.returncode == 0 else "failed"
        return result.returncode
    finally:
        manifest["finished_at"] = timestamp()
        atomic_json(args.manifest, manifest)


if __name__ == "__main__":
    sys.exit(main())
