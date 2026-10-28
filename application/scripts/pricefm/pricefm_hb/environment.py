#!/usr/bin/env python3
"""Lock and reconstruct the Python-only HB preparation environment.

Snapshot/seal/audit use only the standard library. Numerical imports occur only
in verify-runtime, after a one-CPU Slurm compute allocation has been checked.
This module never submits jobs, copies a venv, or invokes scientific fitting.
"""
from __future__ import annotations

import argparse
import ast
import email
import hashlib
import importlib.metadata as metadata
import json
import os
from pathlib import Path
import platform
import re
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import zipfile


SCHEMA = "pricefm-hb-environment-v1"
PYTHON_VERSION = "3.11.13"
ROOT_PACKAGES = ("numpy", "scipy", "pandas", "PyYAML", "threadpoolctl")
THREAD_ENV = {
    "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1",
    "MKL_NUM_THREADS": "1", "BLIS_NUM_THREADS": "1",
    "VECLIB_MAXIMUM_THREADS": "1", "NUMEXPR_NUM_THREADS": "1",
    "NUMEXPR_MAX_THREADS": "1",
}
REFERENCE_NUMERICAL_ENV = {
    "OPENBLAS_CORETYPE": "Sandybridge",
    "NPY_DISABLE_CPU_FEATURES": "AVX2,FMA3,F16C,AVX512F,AVX512CD,AVX512_KNL,AVX512_KNM,AVX512_SKX,AVX512_CLX,AVX512_CNL,AVX512_ICL",
}


class EnvironmentError(RuntimeError):
    """A failed preparation contract, reported without a traceback by the CLI."""


def canonical(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def write_new(path, data):
    """Allow an identical retry, but never silently replace prepared evidence."""
    path = Path(path)
    if isinstance(data, str):
        data = data.encode()
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open("xb") as handle:
            handle.write(data)
    except FileExistsError:
        if path.read_bytes() != data:
            raise EnvironmentError("refusing to replace different evidence: " + str(path))


def load_json(path):
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


def reject_symlink_path(path):
    """Inspect each existing ancestor before resolving any caller-supplied path."""
    path = Path(path).absolute()
    for component in reversed((path,) + tuple(path.parents)):
        if component.is_symlink():
            raise EnvironmentError("symlink path is not allowed: " + str(component))


def marker_applies(marker):
    """Evaluate the small PEP 508 marker grammar without importing packaging."""
    values = {
        "extra": "", "python_version": "3.11", "python_full_version": PYTHON_VERSION,
        "sys_platform": "linux", "os_name": "posix", "platform_system": "Linux",
        "platform_machine": "x86_64", "implementation_name": "cpython",
        "platform_python_implementation": "CPython", "implementation_version": PYTHON_VERSION,
    }

    def walk(node):
        if isinstance(node, ast.Expression):
            return walk(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name) and node.id in values:
            return values[node.id]
        if isinstance(node, ast.BoolOp) and isinstance(node.op, (ast.And, ast.Or)):
            results = [bool(walk(item)) for item in node.values]
            return all(results) if isinstance(node.op, ast.And) else any(results)
        if isinstance(node, ast.Compare) and len(node.ops) == 1:
            left, right = walk(node.left), walk(node.comparators[0])
            op = node.ops[0]
            if isinstance(op, ast.In):
                return left in right
            if isinstance(op, ast.NotIn):
                return left not in right
            version_names = {"python_version", "python_full_version", "implementation_version"}
            if any(isinstance(part, ast.Name) and part.id in version_names
                   for part in (node.left, node.comparators[0])):
                left = tuple(int(part) for part in left.split("."))
                right = tuple(int(part) for part in right.split("."))
            if isinstance(op, ast.Eq):
                return left == right
            if isinstance(op, ast.NotEq):
                return left != right
            if isinstance(op, ast.Lt):
                return left < right
            if isinstance(op, ast.LtE):
                return left <= right
            if isinstance(op, ast.Gt):
                return left > right
            if isinstance(op, ast.GtE):
                return left >= right
        raise EnvironmentError("unsupported dependency marker: " + marker)

    return bool(walk(ast.parse(marker.strip(), mode="eval")))


def active_requirements(requirements):
    result = []
    for requirement in requirements or ():
        specification, separator, marker = requirement.partition(";")
        if not separator or marker_applies(marker):
            match = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9_.-]*)", specification)
            if not match:
                raise EnvironmentError("unsupported requirement: " + requirement)
            if "[" in specification or "@" in specification:
                raise EnvironmentError("extras/URLs need explicit review: " + requirement)
            result.append({"name": canonical(match.group(1)), "requirement": requirement})
    return result


def snapshot(bundle):
    if platform.python_version() != PYTHON_VERSION:
        raise EnvironmentError("snapshot requires Python " + PYTHON_VERSION)
    packages, pending = {}, list(ROOT_PACKAGES)
    while pending:
        name = canonical(pending.pop())
        if name in packages:
            continue
        distribution = metadata.distribution(name)
        dependencies = active_requirements(distribution.requires)
        packages[name] = {
            "name": distribution.metadata["Name"], "version": distribution.version,
            "active_dependencies": dependencies,
        }
        pending.extend(item["name"] for item in dependencies)
    record = {
        "schema": SCHEMA, "python_version": PYTHON_VERSION,
        "source_executable": sys.executable, "source_platform": platform.platform(),
        "target": {"implementation": "cp", "python": "311", "abi": "cp311",
                   "platform": "manylinux2014_x86_64", "minimum_glibc": "2.17"},
        "roots": [canonical(name) for name in ROOT_PACKAGES],
        "packages": dict(sorted(packages.items())),
    }
    bundle = Path(bundle)
    write_new(bundle / "source-environment.json", json_bytes(record))
    requirements = "".join(
        item["name"] + "==" + item["version"] + "\n" for item in record["packages"].values())
    write_new(bundle / "requirements.versions.txt", requirements)
    return record


def wheel_identity(path):
    with zipfile.ZipFile(path) as archive:
        names = [name for name in archive.namelist() if name.endswith(".dist-info/METADATA")]
        if len(names) != 1:
            raise EnvironmentError("wheel must contain one METADATA: " + path.name)
        message = email.message_from_bytes(archive.read(names[0]))
    return canonical(message["Name"]), message["Version"]


def pypi_artifact(name, version, filename, expected_hash):
    url = "https://pypi.org/pypi/{}/{}/json".format(
        urllib.parse.quote(name, safe=""), urllib.parse.quote(version, safe=""))
    request = urllib.request.Request(url, headers={"User-Agent": "pricefm-hb-lock/1"})
    with urllib.request.urlopen(request, timeout=20) as response:
        raw = response.read(4 * 1024 * 1024 + 1)
    if len(raw) > 4 * 1024 * 1024:
        raise EnvironmentError("oversized PyPI metadata response")
    record = json.loads(raw)
    artifacts = [item for item in record["urls"] if item["filename"] == filename]
    if len(artifacts) != 1:
        raise EnvironmentError("artifact absent/ambiguous in PyPI metadata: " + filename)
    artifact = artifacts[0]
    parsed = urllib.parse.urlparse(artifact["url"])
    if parsed.scheme != "https" or parsed.hostname != "files.pythonhosted.org":
        raise EnvironmentError("artifact is outside the official PyPI host")
    if artifact["digests"]["sha256"] != expected_hash:
        raise EnvironmentError("official PyPI hash mismatch: " + filename)
    return {"metadata_url": url, "url": artifact["url"],
            "sha256": expected_hash, "size": artifact["size"]}


def seal(bundle):
    bundle = Path(bundle)
    source = load_json(bundle / "source-environment.json")
    packages = source["packages"]
    found, artifacts = set(), []
    for path in sorted((bundle / "wheels").iterdir()):
        if path.is_symlink() or not path.is_file() or path.suffix != ".whl":
            raise EnvironmentError("unexpected wheel-cache entry: " + path.name)
        name, version = wheel_identity(path)
        if name not in packages or name in found or version != packages[name]["version"]:
            raise EnvironmentError("unexpected/duplicate wheel identity: " + path.name)
        sha = digest(path)
        upstream = pypi_artifact(name, version, path.name, sha)
        if path.stat().st_size != upstream["size"]:
            raise EnvironmentError("PyPI size mismatch: " + path.name)
        artifacts.append({"name": name, "version": version, "filename": path.name,
                          "sha256": sha, "size": path.stat().st_size, "upstream": upstream})
        found.add(name)
    if found != set(packages):
        raise EnvironmentError("wheel cache does not cover the exact dependency closure")
    by_name = {item["name"]: item for item in artifacts}
    lock = "".join("{}=={} --hash=sha256:{}\n".format(
        name, packages[name]["version"], by_name[name]["sha256"]) for name in sorted(packages))
    write_new(bundle / "requirements.lock", lock)
    manifest = {"schema": SCHEMA, "python_version": PYTHON_VERSION,
                "source_environment_sha256": digest(bundle / "source-environment.json"),
                "requirements_lock_sha256": digest(bundle / "requirements.lock"),
                "artifacts": artifacts}
    write_new(bundle / "wheel-manifest.json", json_bytes(manifest))
    checksums = [(digest(bundle / "source-environment.json"), "source-environment.json"),
                 (digest(bundle / "requirements.versions.txt"), "requirements.versions.txt"),
                 (digest(bundle / "requirements.lock"), "requirements.lock"),
                 (digest(bundle / "wheel-manifest.json"), "wheel-manifest.json")]
    checksums.extend((item["sha256"], "wheels/" + item["filename"]) for item in artifacts)
    write_new(bundle / "SHA256SUMS", "".join(sha + "  " + name + "\n" for sha, name in checksums))
    return audit_bundle(bundle)


def audit_bundle(bundle):
    bundle = Path(bundle)
    reject_symlink_path(bundle)
    reject_symlink_path(bundle / "wheels")
    for filename in ("source-environment.json", "requirements.versions.txt", "requirements.lock",
                     "wheel-manifest.json", "SHA256SUMS"):
        if (bundle / filename).is_symlink():
            raise EnvironmentError("bundle evidence cannot be a symlink: " + filename)
    manifest = load_json(bundle / "wheel-manifest.json")
    source = load_json(bundle / "source-environment.json")
    if manifest.get("schema") != SCHEMA or manifest.get("python_version") != PYTHON_VERSION:
        raise EnvironmentError("unexpected manifest contract")
    if (source.get("schema") != SCHEMA or source.get("python_version") != PYTHON_VERSION
            or source.get("roots") != [canonical(name) for name in ROOT_PACKAGES]):
        raise EnvironmentError("unexpected source environment contract")
    for key, filename in (("source_environment_sha256", "source-environment.json"),
                          ("requirements_lock_sha256", "requirements.lock")):
        if digest(bundle / filename) != manifest[key]:
            raise EnvironmentError("bundle hash mismatch: " + filename)
    packages, found = source["packages"], set()
    closure, pending = set(), list(source["roots"])
    while pending:
        name = pending.pop()
        if name in closure:
            continue
        if name not in packages or canonical(packages[name]["name"]) != name:
            raise EnvironmentError("missing/noncanonical dependency in source closure")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.!+_-]*", packages[name]["version"]):
            raise EnvironmentError("unsafe dependency version")
        closure.add(name)
        pending.extend(item["name"] for item in packages[name]["active_dependencies"])
    if closure != set(packages):
        raise EnvironmentError("source packages exceed the declared runtime closure")
    for artifact in manifest["artifacts"]:
        filename = artifact["filename"]
        if Path(filename).name != filename or not filename.endswith(".whl"):
            raise EnvironmentError("unsafe wheel path in manifest")
        path = bundle / "wheels" / filename
        if path.is_symlink() or digest(path) != artifact["sha256"]:
            raise EnvironmentError("wheel hash mismatch: " + filename)
        if path.stat().st_size != artifact["size"]:
            raise EnvironmentError("wheel size mismatch: " + filename)
        name, version = wheel_identity(path)
        upstream = urllib.parse.urlparse(artifact["upstream"]["url"])
        if (name in found or name not in packages or artifact["name"] != name
                or artifact["version"] != version or packages[name]["version"] != version
                or artifact["upstream"]["sha256"] != artifact["sha256"]
                or upstream.scheme != "https" or upstream.hostname != "files.pythonhosted.org"):
            raise EnvironmentError("wheel identity/closure mismatch: " + filename)
        found.add(name)
    actual = {path.name for path in (bundle / "wheels").iterdir()}
    expected = {item["filename"] for item in manifest["artifacts"]}
    if found != set(packages) or actual != expected:
        raise EnvironmentError("extra/missing wheel or dependency")
    by_name = {item["name"]: item for item in manifest["artifacts"]}
    expected_lock = "".join("{}=={} --hash=sha256:{}\n".format(
        name, packages[name]["version"], by_name[name]["sha256"]) for name in sorted(packages))
    if (bundle / "requirements.lock").read_text() != expected_lock:
        raise EnvironmentError("requirements lock is not the exact manifest closure")
    expected_versions = "".join(packages[name]["name"] + "==" + packages[name]["version"] + "\n"
                                for name in sorted(packages))
    if (bundle / "requirements.versions.txt").read_text() != expected_versions:
        raise EnvironmentError("plain version list differs from the source closure")
    checksum_names = {"source-environment.json", "requirements.versions.txt", "requirements.lock",
                      "wheel-manifest.json"} | {"wheels/" + name for name in expected}
    seen_checksums = set()
    for line in (bundle / "SHA256SUMS").read_text().splitlines():
        match = re.fullmatch(r"([a-f0-9]{64})  (.+)", line)
        if not match or match.group(2) not in checksum_names or match.group(2) in seen_checksums:
            raise EnvironmentError("unexpected/duplicate SHA256SUMS entry")
        sha, filename = match.groups()
        if digest(bundle / filename) != sha:
            raise EnvironmentError("SHA256SUMS mismatch: " + filename)
        seen_checksums.add(filename)
    if seen_checksums != checksum_names:
        raise EnvironmentError("incomplete SHA256SUMS transfer manifest")
    return {"status": "verified", "schema": SCHEMA, "packages": len(found),
            "wheel_bytes": sum(item["size"] for item in manifest["artifacts"]),
            "manifest_sha256": digest(bundle / "wheel-manifest.json"),
            "requirements_lock_sha256": digest(bundle / "requirements.lock")}


def require_compute(environ=None, hostname=None, affinity=None, runner=subprocess.run):
    environ = os.environ if environ is None else environ
    hostname = socket.gethostname().split(".")[0] if hostname is None else hostname
    affinity = sorted(os.sched_getaffinity(0)) if affinity is None else sorted(affinity)
    job = environ.get("SLURM_JOB_ID", "")
    if not re.fullmatch(r"[0-9]+", job) or environ.get("SLURM_CPUS_PER_TASK") != "1":
        raise EnvironmentError("requires an admitted one-CPU Slurm compute allocation")
    if len(affinity) != 1:
        raise EnvironmentError("compute process must be bound to exactly one allocated CPU")
    nodelist = environ.get("SLURM_JOB_NODELIST", "")
    if not nodelist:
        raise EnvironmentError("missing Slurm allocation node list")
    result = runner(["scontrol", "show", "hostnames", nodelist], text=True,
                    capture_output=True, check=True, timeout=10)
    nodes = [node.split(".")[0] for node in result.stdout.split()]
    if nodes != [hostname] or re.search(r"login|head|submit", hostname, re.IGNORECASE):
        raise EnvironmentError("requires the single allocated compute node, not a login host")
    return {"job_id": job, "node": hostname, "affinity": affinity,
            "cpus_per_task": 1, "allocation_nodes": nodes}


def reference_environment(environ=None):
    """The historical CPU profile is optional, but partial/other profiles fail."""
    environ = os.environ if environ is None else environ
    if not any(key in environ for key in REFERENCE_NUMERICAL_ENV):
        return {}
    if any(environ.get(key) != value for key, value in REFERENCE_NUMERICAL_ENV.items()):
        raise EnvironmentError("reference numerical profile requires both exact historical controls")
    return dict(REFERENCE_NUMERICAL_ENV)


def validate_reference_profile_record(record):
    """Validate a positive, pinned historical dispatch attestation using stdlib."""
    features = record.get("numpy_cpu_features", {})
    dispatch = record.get("numpy_dispatch_targets", [])
    architectures = record.get("openblas_architectures", [])
    disabled = set(REFERENCE_NUMERICAL_ENV["NPY_DISABLE_CPU_FEATURES"].split(","))
    if (record.get("enabled") is not True or record.get("environment") != REFERENCE_NUMERICAL_ENV
            or not isinstance(features, dict) or not isinstance(dispatch, list)
            or not all(isinstance(name, str) for name in dispatch) or not disabled <= set(dispatch)
            or any(features.get(name) is not False for name in disabled)
            or any(features.get(name) is not False for name in dispatch if name.startswith("AVX512"))
            or not architectures or any(name != "Sandybridge" for name in architectures)):
        raise EnvironmentError("actual NumPy/OpenBLAS dispatch differs from the historical reference profile")
    return record


def verify_reference_profile(numpy_module, pools, controls):
    """Check actual native dispatch before performing the tiny numerical solve."""
    if not controls:
        return {"enabled": False, "environment": {}}
    if controls != REFERENCE_NUMERICAL_ENV:
        raise EnvironmentError("unsupported reference numerical profile")
    try:
        module = numpy_module._core._multiarray_umath
        features = dict(module.__cpu_features__)
        dispatch = list(module.__cpu_dispatch__)
    except (AttributeError, KeyError, TypeError) as exc:
        raise EnvironmentError("NumPy actual CPU feature metadata is unavailable") from exc
    blas = [pool for pool in pools if pool.get("internal_api") == "openblas"]
    if not pools or any(pool.get("num_threads") != 1 for pool in pools):
        raise EnvironmentError("actual NumPy/OpenBLAS dispatch differs from the historical reference profile: thread count")
    return validate_reference_profile_record({"enabled": True, "environment": dict(controls),
            "numpy_cpu_features": features, "numpy_dispatch_targets": dispatch,
            "openblas_architectures": [pool.get("architecture") for pool in blas]})


def native_library_hashes(pools):
    """Hash the two actually loaded wheel BLAS ELFs, bounded to 72 MiB total."""
    paths = sorted({pool.get("filepath") for pool in pools if pool.get("internal_api") == "openblas"}, key=str)
    if (len(paths) != 2 or any(not isinstance(path, str) or not Path(path).is_absolute()
                              or not Path(path).is_file() for path in paths)
            or sum(Path(path).stat().st_size for path in paths) > 72 * 1024**2):
        raise EnvironmentError("exact two bounded loaded NumPy/SciPy OpenBLAS library files required")
    return {path: digest(path) for path in paths}


def require_reference_profile(expected_native_library_sha256=None):
    """Live guard for the cost harness before any frozen numerical forecast call."""
    require_compute()
    controls = reference_environment()
    if controls != REFERENCE_NUMERICAL_ENV:
        raise EnvironmentError("the accepted historical reference numerical profile is required")
    if any(os.environ.get(key) != value for key, value in THREAD_ENV.items()):
        raise EnvironmentError("one numerical thread is required before reference imports")
    import numpy as np
    from threadpoolctl import threadpool_info
    verify_reference_profile(np, threadpool_info(), controls)
    import scipy.linalg
    pools = threadpool_info()
    result = verify_reference_profile(np, pools, controls)
    if not pools or any(pool.get("num_threads") != 1 for pool in pools):
        raise EnvironmentError("reference numerical pools must all use one thread")
    native = native_library_hashes(pools)
    if expected_native_library_sha256 is not None and native != expected_native_library_sha256:
        raise EnvironmentError("actual loaded native library bytes differ from accepted parity runtime")
    result["native_library_sha256"] = native
    return result


def verify_runtime(bundle, report):
    allocation = require_compute()
    reference_controls = reference_environment()
    audit = audit_bundle(bundle)
    if platform.python_version() != PYTHON_VERSION or platform.machine() != "x86_64":
        raise EnvironmentError("runtime must be x86_64 CPython " + PYTHON_VERSION)
    if any(os.environ.get(key) != value for key, value in THREAD_ENV.items()):
        raise EnvironmentError("all numerical thread controls must equal one before imports")
    source = load_json(Path(bundle) / "source-environment.json")
    versions = {name: metadata.version(name) for name in source["packages"]}
    expected = {name: item["version"] for name, item in source["packages"].items()}
    if versions != expected:
        raise EnvironmentError("installed versions do not match exact dependency lock")

    # These deliberately tiny operations load NumPy/SciPy's actual BLAS libraries.
    import numpy as np
    from threadpoolctl import threadpool_info
    # Check NumPy's callable dispatch immediately, before importing SciPy/pandas.
    verify_reference_profile(np, threadpool_info(), reference_controls)
    import scipy.linalg
    import pandas as pd
    import yaml
    reference_profile = verify_reference_profile(np, threadpool_info(), reference_controls)
    native_sha256 = native_library_hashes(threadpool_info())
    matrix = np.array([[4.0, 1.0], [1.0, 3.0]])
    vector = np.array([1.0, 2.0])
    answer = scipy.linalg.solve(matrix, vector)
    residual = float(np.max(np.abs(matrix @ answer - vector)))
    if residual > 1e-12 or pd.DataFrame({"value": answer}).shape != (2, 1):
        raise EnvironmentError("tiny numerical/import verification failed")
    if yaml.safe_load("thread_count: 1\n") != {"thread_count": 1}:
        raise EnvironmentError("YAML import verification failed")
    pools = threadpool_info()
    if not pools or any(pool.get("num_threads") != 1 for pool in pools):
        raise EnvironmentError("loaded numerical pools are missing or exceed one thread")
    result = {"schema": SCHEMA, "status": "verified", "allocation": allocation,
              "python_version": platform.python_version(), "executable": sys.executable,
              "platform": platform.platform(), "libc": platform.libc_ver(),
              "versions": versions, "thread_environment": dict(THREAD_ENV),
              "reference_numerical_profile": reference_profile,
              "native_library_sha256": native_sha256,
              "threadpoolctl": pools, "tiny_solve_max_abs_residual": residual,
              "bundle": audit, "scope": "imports and 2-by-2 solve only; no forecast work"}
    write_new(report, json_bytes(result))
    return result


def run_logged(command, log, env):
    with Path(log).open("xb") as handle:
        subprocess.run(command, check=True, stdout=handle, stderr=subprocess.STDOUT,
                       env=env, timeout=900)


def interpreter_artifacts(interpreter, cache, report):
    """Retain and verify the actual official conda artifact closure after solve."""
    interpreter, cache = Path(interpreter), Path(cache)
    reject_symlink_path(interpreter / "conda-meta")
    reject_symlink_path(cache)
    records = []
    for path in sorted((interpreter / "conda-meta").glob("*.json")):
        reject_symlink_path(path)
        package = load_json(path)
        filename = package.get("fn", "")
        sha = package.get("sha256", "")
        url = package.get("url", "")
        parsed = urllib.parse.urlparse(url)
        if (not filename or Path(filename).name != filename
                or not filename.endswith((".conda", ".tar.bz2"))
                or parsed.scheme != "https" or parsed.hostname != "conda.anaconda.org"
                or parsed.username or parsed.password or parsed.query or parsed.fragment
                or parsed.port is not None
                or not any(parsed.path.startswith(prefix) for prefix in
                           ("/conda-forge/linux-64/", "/conda-forge/noarch/"))
                or urllib.parse.unquote(parsed.path.rsplit("/", 1)[-1]) != filename
                or not re.fullmatch(r"[a-f0-9]{64}", sha)):
            raise EnvironmentError("missing/untrusted conda artifact provenance: " + path.name)
        artifact = cache / filename
        reject_symlink_path(artifact)
        if not artifact.is_file() or digest(artifact) != sha:
            raise EnvironmentError("conda cached artifact SHA256 mismatch: " + filename)
        records.append({"name": package["name"], "version": package["version"],
                        "build": package["build"], "filename": filename, "url": url,
                        "sha256": sha, "size": artifact.stat().st_size,
                        "installed_metadata_sha256": digest(path)})
    python = [item for item in records if item["name"] == "python"]
    if len(python) != 1 or python[0]["version"] != PYTHON_VERSION:
        raise EnvironmentError("conda artifact closure lacks exact Python " + PYTHON_VERSION)
    result = {"schema": SCHEMA, "python_version": PYTHON_VERSION,
              "source": "official conda-forge channel via conda.anaconda.org/conda-forge",
              "artifacts": records}
    write_new(report, json_bytes(result))
    return {"manifest_sha256": digest(report), "artifact_count": len(records),
            "artifact_bytes": sum(item["size"] for item in records),
            "python": {key: python[0][key] for key in ("name", "version", "build", "sha256")}}


def build(bundle, prefix, report, conda_executable):
    allocation = require_compute()
    audit = audit_bundle(bundle)
    bundle, prefix, report = Path(bundle).resolve(), Path(prefix), Path(report)
    if not prefix.is_absolute() or not report.is_absolute():
        raise EnvironmentError("prefix/report must be absolute paths")
    if prefix.exists() or report.exists():
        raise EnvironmentError("build requires a new prefix and new report")
    prefix.mkdir(parents=True, exist_ok=False)
    started = time.time()
    env = dict(os.environ, **THREAD_ENV)
    env.update({"PYTHONNOUSERSITE": "1", "PYTHONDONTWRITEBYTECODE": "1",
                "PIP_CONFIG_FILE": os.devnull, "PIP_DISABLE_PIP_VERSION_CHECK": "1",
                "CONDARC": os.devnull, "CONDA_PKGS_DIRS": str(prefix / "conda-pkgs")})
    interpreter, venv = prefix / "interpreter", prefix / "venv"
    try:
        run_logged([str(conda_executable), "create", "--yes", "--no-default-packages",
                    "--override-channels", "--channel", "https://conda.anaconda.org/conda-forge",
                    "--prefix", str(interpreter), "python=" + PYTHON_VERSION, "pip"],
                   prefix / "conda-create.log", env)
        artifact_summary = interpreter_artifacts(
            interpreter, prefix / "conda-pkgs", prefix / "interpreter-artifact-manifest.json")
        python = str(interpreter / "bin/python")
        run_logged([python, "-B", "-m", "venv", "--copies", str(venv)],
                   prefix / "venv-create.log", env)
        runtime_python = str(venv / "bin/python")
        run_logged([runtime_python, "-B", "-m", "pip", "--isolated", "install", "--no-index",
                    "--find-links", str(bundle / "wheels"), "--only-binary=:all:",
                    "--require-hashes", "--no-deps", "--requirement", str(bundle / "requirements.lock")],
                   prefix / "pip-install.log", env)
        run_logged([runtime_python, "-B", "-m", "pip", "--isolated", "check"],
                   prefix / "pip-check.log", env)
        run_logged([str(conda_executable), "list", "--explicit", "--prefix", str(interpreter)],
                   prefix / "conda-explicit.txt", env)
        run_logged([runtime_python, "-B", str(Path(__file__).resolve()), "verify-runtime",
                    "--bundle", str(bundle), "--report", str(prefix / "runtime-verification.json")],
                   prefix / "runtime-verification.log", env)
        result = {"schema": SCHEMA, "status": "verified", "allocation": allocation,
                  "bundle": audit, "runtime_python": runtime_python,
                  "runtime_report": str(prefix / "runtime-verification.json"),
                  "interpreter_artifacts": artifact_summary,
                  "conda_explicit_sha256": digest(prefix / "conda-explicit.txt"),
                  "wall_seconds": round(time.time() - started, 3)}
    except Exception as exc:
        result = {"schema": SCHEMA, "status": "failed", "allocation": allocation,
                  "bundle": audit, "error_type": type(exc).__name__,
                  "error": str(exc), "wall_seconds": round(time.time() - started, 3)}
        write_new(report, json_bytes(result))
        raise
    write_new(report, json_bytes(result))
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("snapshot", "seal", "audit-bundle", "verify-runtime", "build"):
        command = sub.add_parser(name)
        command.add_argument("--bundle", required=True)
        if name in ("verify-runtime", "build"):
            command.add_argument("--report", required=True)
        if name == "build":
            command.add_argument("--prefix", required=True)
            command.add_argument("--conda-executable", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "snapshot":
            result = snapshot(args.bundle)
        elif args.command == "seal":
            result = seal(args.bundle)
        elif args.command == "audit-bundle":
            result = audit_bundle(args.bundle)
        elif args.command == "verify-runtime":
            result = verify_runtime(args.bundle, args.report)
        else:
            result = build(args.bundle, args.prefix, args.report, args.conda_executable)
    except (EnvironmentError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print(json.dumps({"status": "failed", "error_type": type(exc).__name__,
                          "error": str(exc)}), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
