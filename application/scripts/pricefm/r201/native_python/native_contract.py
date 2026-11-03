"""Actual compute-only Python binding for the separately qualified native ABI.

No fixture callback, environment ACK flag or descriptor can create an earned
handle. prepare is not admission. reacquire loads the exact immutable library
and asks its process-local singleton for the actual earned/live receipt.
"""
import ctypes
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import stat
import time

INITIAL = "INITIAL_NATIVE_REFERENCE_QUALIFICATION"
PRODUCTION = "LT_NO4_REFERENCE"
ROLES = {INITIAL: 1, PRODUCTION: 2}
SOURCE_KEYS = {
    "native_python/r201_native_boundary.c",
    "native_python/r201_native_boundary.h",
    "native_python/python_bootstrap.py",
    "native_python/native_contract.py",
    "native_python/build_contract.py",
    "native_python/native_abi.json",
}
BUILD_KEYS = {
    "schema", "status", "source", "header", "abi", "compiler", "argv",
    "output_library", "dependencies", "build_guard", "build_accounting",
    "build_source_review", "created_epoch",
}
ORIGINAL_POLICY_SHA = "b3ed6ab30ca2e3aa2b777044e502576c3e323ee25f653ba8046113124b104b53"
_SEAL = object()

def require(value, why):
    if not value:
        raise ValueError(why)

def closed(value, keys, label):
    require(type(value) is dict and set(value) == set(keys), "closed " + label)
    return value

def strict_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate JSON key")
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")))

def descriptor(pin):
    closed(pin, {"path", "sha256"}, "pin")
    require(type(pin["path"]) is str and type(pin["sha256"]) is str
            and re.fullmatch("[0-9a-f]{64}", pin["sha256"]), "exact pin shape")
    physical(pin["path"])
    return pin

def physical(text):
    require(type(text) is str and text.startswith("/") and "\x00" not in text,
            "absolute physical path")
    p = Path(text)
    require(str(p) == text and ".." not in p.parts and "." not in p.parts
            and not any(x.is_symlink() for x in (p, *p.parents)), "no path aliases")
    return p

def _identity(s):
    return (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns, s.st_uid, s.st_nlink)

def read_regular(path, limit, expected_sha=None):
    p = physical(path)
    fd = os.open(p, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        before = os.fstat(stream.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid()
                and before.st_nlink == 1 and before.st_size <= limit, "bounded owned regular file")
        raw = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
    require(len(raw) == before.st_size and _identity(before) == _identity(after)
            == _identity(p.stat()), "stable exact captured file")
    if expected_sha is not None:
        require(hashlib.sha256(raw).hexdigest() == expected_sha, "captured bytes differ from pin")
    return raw

def linked(pin):
    descriptor(pin)
    return strict_json(read_regular(pin["path"], 1024**2, pin["sha256"]))

def pin_file(path):
    raw = read_regular(str(path), 1024**2)
    return {"path": str(path), "sha256": hashlib.sha256(raw).hexdigest()}

def _proc(pid):
    root = Path("/proc") / str(pid)
    text = (root / "stat").read_text()
    tail = text[text.rindex(")") + 2:].split()
    fields = {}
    for line in (root / "status").read_text().splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            fields[key] = value.strip()
    return {"pid": pid, "start_ticks": int(tail[19]), "ppid": int(tail[1]),
            "tracer": int(fields["TracerPid"]), "uid": [int(x) for x in fields["Uid"].split()],
            "seccomp": int(fields["Seccomp"]), "nnp": int(fields["NoNewPrivs"]),
            "cgroup": (root / "cgroup").read_text()}

def job_before_records():
    """First actual-runtime gate; supplied records and libraries are not opened."""
    job = os.environ.get("SLURM_JOB_ID", "")
    require(re.fullmatch("[1-9][0-9]{0,19}", job), "actual Slurm job required")
    child, parent = _proc(os.getpid()), _proc(os.getppid())
    require(child["tracer"] == parent["pid"] == child["ppid"]
            and child["cgroup"] == parent["cgroup"]
            and "slurm" in child["cgroup"]
            and re.search(r"(?:^|/)job_" + re.escape(job) + r"(?:/|\n|$)", child["cgroup"])
            and child["uid"] == parent["uid"] == [os.getuid()] * 4
            and len(os.sched_getaffinity(0)) == 1, "actual native traced Slurm child required")
    return job, child, parent

def readonly_backing(path):
    p = physical(path)
    mounts = []
    for row in Path("/proc/self/mountinfo").read_text().splitlines():
        parts = row.split()
        split = parts.index("-")
        point = parts[4]
        for old, new in ((r"\040", " "), (r"\011", "\t"), (r"\012", "\n"), (r"\134", "\\")):
            point = point.replace(old, new)
        mount = Path(point)
        if p.is_relative_to(mount):
            mounts.append((len(mount.parts), set(parts[5].split(",")),
                           set(parts[split + 3].split(","))))
    require(mounts, "actual mounted source/runtime backing")
    _, options, super_options = max(mounts, key=lambda x: x[0])
    require("ro" in options and "ro" in super_options,
            "actual readonly mount AND readonly superblock; writable alias not accepted")

def source_bytes(review, relative):
    require(type(relative) is str and relative in review["source_pins"]
            and not Path(relative).is_absolute() and ".." not in Path(relative).parts
            and str(Path(relative)) == relative and "\x00" not in relative, "closed source key")
    root = Path(__file__).absolute().parent.parent
    target = root / relative
    pin = descriptor(review["source_pins"][relative])
    require(pin["path"] == str(target), "fixed installed source key")
    return read_regular(pin["path"], 2 * 1024**2, pin["sha256"])

def load_fixed(review, relative, module_name):
    """Execute only captured verified source; no loader path re-open."""
    raw = source_bytes(review, relative)
    code = compile(raw, review["source_pins"][relative]["path"], "exec")
    spec = importlib.util.spec_from_file_location(module_name, review["source_pins"][relative]["path"])
    module = importlib.util.module_from_spec(spec)
    import sys
    sys.modules[module_name] = module
    exec(code, module.__dict__)
    return module

def validate_abi(value):
    closed(value, {"schema", "version", "platform", "roles", "return_convention",
                   "symbols", "receipt_fields", "original_policy_source",
                   "original_traced_guard", "handshake_token"}, "native ABI")
    require(value["schema"] == "r201_native_python_boundary_abi_v1"
            and value["version"] == 1 and type(value["version"]) is int
            and value["platform"] == "linux-x86_64"
            and value["roles"] == ROLES
            and value["return_convention"] == "0_SUCCESS_MINUS1_TERMINAL_REFUSAL"
            and value["symbols"] == ABI_SYMBOLS
            and value["receipt_fields"] == RECEIPT_FIELDS
            and value["handshake_token"] == "R157_TSYNC_FORK_DENIAL_READY_V1", "exact native ABI")
    for name in ("original_policy_source", "original_traced_guard"):
        descriptor(value[name])
    require(value["original_policy_source"]["sha256"] == ORIGINAL_POLICY_SHA,
            "unchanged original native policy source")
    require(value["original_traced_guard"]["sha256"] ==
            "914d7d369d68579b7149c5130e3bba5d59f3b8f09a5bf691e1557ccbcd40c963",
            "unchanged original tracer source")
    return value

def validate_build(manifest, launch, review):
    closed(manifest, BUILD_KEYS, "native build manifest")
    require(manifest["schema"] == "r201_native_build_manifest_v1"
            and manifest["status"] == "BUILD_EVIDENCE_ONLY_NOT_RUNTIME_QUALIFIED"
            and manifest["source"] == review["source_pins"]["native_python/r201_native_boundary.c"]
            and manifest["header"] == review["source_pins"]["native_python/r201_native_boundary.h"]
            and manifest["abi"] == launch["native_abi"]
            and manifest["output_library"] == launch["native_library"], "exact new build evidence")
    for name in ("source", "header", "abi", "compiler", "output_library",
                 "build_guard", "build_accounting", "build_source_review"):
        descriptor(manifest[name])
    require(type(manifest["argv"]) is list and manifest["argv"]
            and all(type(x) is str and "\x00" not in x for x in manifest["argv"]),
            "exact recorded compiler argv")
    require(type(manifest["dependencies"]) is list and 1 <= len(manifest["dependencies"]) <= 64,
            "complete bounded native dependency closure")
    seen = set()
    for dep in manifest["dependencies"]:
        closed(dep, {"path", "sha256", "bytes"}, "dependency")
        descriptor({k: dep[k] for k in ("path", "sha256")})
        require(type(dep["bytes"]) is int and 0 < dep["bytes"] <= 64 * 1024**2
                and dep["path"] not in seen, "unique dependency identity")
        seen.add(dep["path"])
    require(type(manifest["created_epoch"]) in (int, float)
            and math.isfinite(manifest["created_epoch"]), "build time")
    return manifest

def _deployment_prerequisites(spec, launch, manifest, review):
    # Exact accepted-build/deployment/H5/candidate/accounting/review semantics
    # belong to one fixed verified Root source, shared by both closed roles.
    # This is metadata-only and runs BEFORE any newly built library is loaded.
    prerequisites = load_fixed(review, "qualification/qualification_contract.py",
                               "_r201_native_prerequisites")
    prerequisites.validate_native_prerequisites(spec, launch, review)
    if spec["role"] == INITIAL:
        require(spec["build_acceptance"] == launch["native_build_acceptance"]
                and spec["deployment_acceptance"] == launch["native_deployment_acceptance"],
                "initial purpose uses same accepted build/deployment")
    else:
        qualification = linked(spec["runtime_qualification"])
        result = linked(qualification["result"])
        require(result.get("native_build_acceptance") == launch["native_build_acceptance"]
                and result.get("native_deployment_acceptance") == launch["native_deployment_acceptance"],
                "production actual qualification pins accepted build/deployment")
    # Present RO backing, the real kernel transition, post-ACK authority and
    # role-specific live capability are separate required checks.

def preflight(spec_pin, authority_pin, review_pin):
    job, child, parent = job_before_records()
    require(os.uname().sysname == "Linux" and os.uname().machine == "x86_64",
            "qualified Linux x86_64 native ABI only")
    spec, authority, review = linked(spec_pin), linked(authority_pin), linked(review_pin)
    role = spec.get("role")
    require(role in ROLES and spec.get("schema") ==
            ("r201_native_reference_qualification_spec_v1" if role == INITIAL
             else "r200_owned_compute_spec_v1"), "separate exact native role")
    require(authority.get("spec") == spec_pin and authority.get("source_review") == review_pin
            and review.get("spec") == spec_pin, "same independently granted source/spec pins")
    require(authority.get("schema") ==
            ("r201_qualification_authority_v1" if role == INITIAL else "r200_compute_authority_v1"),
            "role-specific authority schema")
    now = time.time()
    for record in (spec, authority, review):
        require(all(record.get(k) == spec.get(k) for k in
                    ("purpose", "nonce", "role", "job_id", "node")), "same native purpose identity")
    require(type(spec["expires_epoch"]) in (int, float) and math.isfinite(spec["expires_epoch"])
            and now < authority["expires_epoch"] <= spec["expires_epoch"], "independent runtime deadline")
    owner = closed(spec["owner"], {"pid", "start_ticks", "boot_id"}, "owner")
    require(owner["pid"] == parent["pid"] and owner["start_ticks"] == parent["start_ticks"]
            and owner["boot_id"] == Path("/proc/sys/kernel/random/boot_id").read_text().strip()
            and spec["uid"] == os.getuid() and spec["job_id"] == job
            and spec["node"] == os.uname().nodename.split(".")[0], "actual native purpose lifetime")
    require(type(spec["resource_lock_fd"]) is int and spec["resource_lock_fd"] >= 3
            and os.environ.get("R154_GLOBAL_PERMIT_LOCK_FD") == str(spec["resource_lock_fd"]),
            "same inherited permit FD")
    pins = review.get("source_pins")
    require(type(pins) is dict and SOURCE_KEYS <= set(pins) and len(pins) <= 128
            and pins == spec["source_pins"], "complete same reviewed installed source map")
    require(review.get("source_map_sha256") == spec["source_map_sha256"], "same publication source map")
    captured, compiled = {}, {}
    for relative in pins:
        raw = source_bytes(review, relative)
        readonly_backing(pins[relative]["path"])
        captured[relative] = raw
        if relative.endswith(".py"):
            compiled[relative] = compile(raw, pins[relative]["path"], "exec")
    launch = linked(spec["owner_launch"])
    closed(launch, {"schema", "purpose", "nonce", "role", "job_id", "node",
                    "bootstrap", "native_executable", "native_library",
                    "native_build_manifest", "native_abi", "native_build_acceptance",
                    "native_deployment_acceptance", "traced_guard", "baseline_files",
                    "environment", "bootstrap_exec_allowlist", "stdout_path",
                    "stderr_path", "owned_tree_path", "owned_guard_path", "output_root"},
           "native launch")
    require(launch["schema"] == "r201_owned_reference_launch_v1"
            and all(launch[k] == spec[k] for k in ("purpose","nonce","role","job_id","node")),
            "same closed native launch")
    for key in ("native_library", "native_build_manifest", "native_abi",
                "native_build_acceptance", "native_deployment_acceptance",
                "native_executable", "traced_guard", "bootstrap"):
        descriptor(launch[key])
    require(launch["bootstrap"] == pins["native_python/python_bootstrap.py"]
            and launch["traced_guard"]["sha256"] ==
            "914d7d369d68579b7149c5130e3bba5d59f3b8f09a5bf691e1557ccbcd40c963"
            and launch["native_abi"] == pins["native_python/native_abi.json"],
            "fixed new bootstrap ABI and unchanged tracer")
    validate_abi(linked(launch["native_abi"]))
    manifest = validate_build(linked(launch["native_build_manifest"]), launch, review)
    _deployment_prerequisites(spec, launch, manifest, review)
    for pin in [launch["native_library"], launch["native_executable"],
                *launch["baseline_files"],
                *({k: d[k] for k in ("path", "sha256")} for d in manifest["dependencies"])]:
        descriptor(pin)
        readonly_backing(pin["path"])
        read_regular(pin["path"], 64 * 1024**2, pin["sha256"])
    require(str(Path("/proc/self/exe").resolve()) == launch["native_executable"]["path"],
            "actual exact Python native ELF")
    return {"spec": spec, "authority": authority, "review": review, "launch": launch,
            "manifest": manifest, "captured": captured, "compiled": compiled,
            "spec_pin": spec_pin, "review_pin": review_pin,
            "authority_pin": authority_pin, "child": child}

RECEIPT_FIELDS = [
    ["abi_version", "uint32"], ["state", "uint32"], ["role", "uint32"], ["uid", "uint32"],
    ["child_pid", "int64"], ["owner_pid", "int64"], ["child_start_ticks", "uint64"],
    ["owner_start_ticks", "uint64"], ["permit_device", "uint64"], ["permit_inode", "uint64"],
    ["expires_epoch", "double"], ["boot_id", "char[37]"], ["job_id", "char[21]"],
    ["node", "char[256]"], ["cgroup", "char[8192]"],
]
ABI_SYMBOLS = {
    "r201_prepare_v1": "int(int64,uint64,int,int,double)",
    "r201_scientific_boundary_v1": "int(void)",
    "r201_validate_live_v1": "int(void)",
    "r201_rename_noreplace_v1": "int(int,const_char*,const_char*)",
    "r201_receipt_v1": "int(receipt_v1*)",
    "r201_receipt_size_v1": "uint64(void)",
    "r201_last_error_v1": "const_char*(void)",
}
class _Receipt(ctypes.Structure):
    _fields_ = [
        ("abi_version", ctypes.c_uint32), ("state", ctypes.c_uint32),
        ("role", ctypes.c_uint32), ("uid", ctypes.c_uint32),
        ("child_pid", ctypes.c_int64), ("owner_pid", ctypes.c_int64),
        ("child_start_ticks", ctypes.c_uint64), ("owner_start_ticks", ctypes.c_uint64),
        ("permit_device", ctypes.c_uint64), ("permit_inode", ctypes.c_uint64),
        ("expires_epoch", ctypes.c_double), ("boot_id", ctypes.c_char * 37),
        ("job_id", ctypes.c_char * 21), ("node", ctypes.c_char * 256),
        ("cgroup", ctypes.c_char * 8192),
    ]

def _library(context):
    # Actual native loading occurs only after real Slurm/trace, accepted build,
    # accepted deployment and current immutable backing checks in preflight.
    lib = ctypes.CDLL(context["launch"]["native_library"]["path"],
                      mode=os.RTLD_LOCAL | os.RTLD_NOW, use_errno=True)
    signatures = {
        "r201_prepare_v1": ([ctypes.c_int64, ctypes.c_uint64, ctypes.c_int, ctypes.c_int, ctypes.c_double], ctypes.c_int),
        "r201_scientific_boundary_v1": ([], ctypes.c_int),
        "r201_validate_live_v1": ([], ctypes.c_int),
        "r201_rename_noreplace_v1": ([ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p], ctypes.c_int),
        "r201_receipt_v1": ([ctypes.POINTER(_Receipt)], ctypes.c_int),
        "r201_receipt_size_v1": ([], ctypes.c_uint64),
        "r201_last_error_v1": ([], ctypes.c_char_p),
    }
    for name, (args, result) in signatures.items():
        function = getattr(lib, name)
        function.argtypes, function.restype = args, result
    require(lib.r201_receipt_size_v1() == ctypes.sizeof(_Receipt), "actual built receipt ABI size")
    return lib

class _NativeHandle:
    __slots__ = ("_lib", "_context", "_crossed", "_seal")
    def __init__(self, lib, context, seal, crossed=False):
        require(seal is _SEAL, "no caller-created native handle")
        self._lib, self._context, self._crossed, self._seal = lib, context, crossed, seal

    def _call(self, name, *args):
        require(self._seal is _SEAL, "actual native handle seal")
        if getattr(self._lib, name)(*args) != 0:
            message = self._lib.r201_last_error_v1()
            raise RuntimeError("actual native refusal: " + (message or b"unknown").decode("ascii", "replace"))

    def cross_once(self):
        require(not self._crossed, "one actual native kernel transition")
        self._call("r201_scientific_boundary_v1")
        self._crossed = True
        return self.verify_live()

    def commit_noreplace(self, directory_fd, partial, final):
        self.verify_live()
        require(type(directory_fd) is int and type(partial) is str and type(final) is str,
                "fixed writer commit arguments")
        self._call("r201_rename_noreplace_v1", directory_fd,
                   partial.encode("ascii"), final.encode("ascii"))
        self.verify_live()

    def verify_live(self):
        require(self._crossed, "preparation alone never earns capability")
        self._call("r201_validate_live_v1")
        value = _Receipt()
        self._call("r201_receipt_v1", ctypes.byref(value))
        spec = self._context["spec"]
        held = os.fstat(spec["resource_lock_fd"])
        require(value.abi_version == 1 and value.state == 3 and value.role == ROLES[spec["role"]]
                and value.child_pid == os.getpid() and value.uid == os.getuid()
                and value.child_start_ticks == _proc(os.getpid())["start_ticks"]
                and value.owner_pid == spec["owner"]["pid"]
                and value.owner_start_ticks == spec["owner"]["start_ticks"]
                and value.permit_device == held.st_dev and value.permit_inode == held.st_ino
                and value.expires_epoch == spec["expires_epoch"]
                and value.boot_id.decode("ascii") == spec["owner"]["boot_id"]
                and value.job_id.decode("ascii") == spec["job_id"]
                and value.node.decode("ascii").split(".")[0] == spec["node"],
                "actual native receipt differs from exact current purpose")
        return {"schema": "r201_actual_native_receipt_v1", "role": spec["role"],
                "child_pid": value.child_pid, "owner_pid": value.owner_pid,
                "child_start_ticks": value.child_start_ticks,
                "owner_start_ticks": value.owner_start_ticks,
                "expires_epoch": value.expires_epoch,
                "native_library": self._context["launch"]["native_library"],
                "native_build_manifest": self._context["launch"]["native_build_manifest"],
                "native_abi": self._context["launch"]["native_abi"]}

def prepare(spec_pin, authority_pin, review_pin):
    context = preflight(spec_pin, authority_pin, review_pin)
    lib = _library(context)
    spec = context["spec"]
    handle = _NativeHandle(lib, context, _SEAL)
    handle._call("r201_prepare_v1", spec["owner"]["pid"], spec["owner"]["start_ticks"],
                 spec["resource_lock_fd"], ROLES[spec["role"]], spec["expires_epoch"])
    return handle

def reacquire(spec_pin, review_pin):
    """Independent fixed loader asks the same actual CDLL singleton for ACK.

    The caller supplies no handle or callback. Full role-specific authority is
    authenticated separately by the fixed Root/production boundary.
    """
    job_before_records()
    spec = linked(spec_pin)
    # Authority pin is immutable in the real parent gate, not an environment override.
    ack_pin = pin_file(spec["acknowledgement_path"])
    ack = linked(ack_pin)
    require(ack.get("spec") == spec_pin and ack.get("source_review") == review_pin,
            "same actual parent gate")
    context = preflight(spec_pin, ack["authority"], review_pin)
    handle = _NativeHandle(_library(context), context, _SEAL, crossed=True)
    handle.verify_live()
    return handle
