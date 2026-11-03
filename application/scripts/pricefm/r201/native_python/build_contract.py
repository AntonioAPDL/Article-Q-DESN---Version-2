"""Pure-descriptor, render-only native build contract. Never invokes a compiler.

This source produces an exact single command for a separately granted build-only
compute owner. Rendering is neither a job submission, native qualification nor
authorization to execute the returned argv. Original r157/H/source stay unchanged.
"""
import hashlib
import json
from pathlib import Path
import re

REQUEST_KEYS = {"schema", "purpose", "nonce", "source", "header", "abi", "compiler",
                "working_directory", "output_library", "source_review", "scope",
                "ledger", "price", "owner"}
FLAGS = ["-std=c11", "-O2", "-fPIC", "-Wall", "-Wextra", "-Werror",
         "-shared", "-Wl,-z,relro", "-Wl,-z,now", "-Wl,--no-undefined"]

def require(value, why):
    if not value:
        raise ValueError(why)

def pin(value):
    require(type(value) is dict and set(value) == {"path", "sha256"}
            and type(value["sha256"]) is str and re.fullmatch("[0-9a-f]{64}", value["sha256"]),
            "closed exact pin")
    path(value["path"])
    return value

def path(value):
    require(type(value) is str and value.startswith("/") and "\x00" not in value
            and str(Path(value)) == value and ".." not in Path(value).parts,
            "absolute canonical descriptor path")
    return Path(value)

def strict_json(raw):
    def pairs(items):
        out = {}
        for key, value in items:
            require(key not in out, "duplicate JSON key")
            out[key] = value
        return out
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")))

def render(request):
    require(type(request) is dict and set(request) == REQUEST_KEYS, "closed build request")
    require(request["schema"] == "r201_native_build_request_v1"
            and type(request["purpose"]) is str and 1 <= len(request["purpose"]) <= 128
            and type(request["nonce"]) is str and re.fullmatch("[0-9a-f]{32}", request["nonce"]),
            "versioned one-attempt build purpose")
    for name in ("source", "header", "abi", "compiler", "source_review", "scope", "ledger", "price"):
        pin(request[name])
    owner = request["owner"]
    require(type(owner) is dict and set(owner) == {"pid", "start_ticks", "boot_id"}
            and type(owner["pid"]) is int and owner["pid"] > 1
            and type(owner["start_ticks"]) is int and owner["start_ticks"] > 0
            and type(owner["boot_id"]) is str and re.fullmatch(
                "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", owner["boot_id"]),
            "exact separately granted build owner")
    source, header = path(request["source"]["path"]), path(request["header"]["path"])
    root, output = path(request["working_directory"]), path(request["output_library"])
    require(source.name == "r201_native_boundary.c" and header.name == "r201_native_boundary.h"
            and source.parent == header.parent
            and path(request["abi"]["path"]).name == "native_abi.json"
            and output.parent == root and output.name == "r201_native_boundary.so",
            "fixed new source/ABI and fresh private output namespace")
    argv = [request["compiler"]["path"], *FLAGS, "-o", str(output), str(source), "-lm"]
    return {"schema": "r201_native_build_command_v1", "status": "RENDER_ONLY_NO_EXECUTION",
            "purpose": request["purpose"], "nonce": request["nonce"],
            "request_sha256": hashlib.sha256(json.dumps(request,sort_keys=True,separators=(",",":")).encode()).hexdigest(),
            "argv": argv, "cwd": str(root), "shell": False,
            "requires_new_build_only_compute_scope": True,
            "must_be_new_private_0700_namespace_with_held_owner_FLOCK": True,
            "must_refuse_existing_output_or_attempt_and_retain_all_failures": True,
            "compile_source_and_dependency_pins_require_actual_owner_validation": True,
            "original_tracer_and_owned_exec_allowlist_required": True,
            "target_and_scientific_kernel_access": False,
            "runtime_qualification": False}

def validate_manifest_shape(manifest):
    keys = {"schema", "status", "source", "header", "abi", "compiler", "argv",
            "output_library", "dependencies", "build_guard", "build_accounting",
            "build_source_review", "created_epoch"}
    require(type(manifest) is dict and set(manifest) == keys, "closed evidence manifest")
    require(manifest["schema"] == "r201_native_build_manifest_v1"
            and manifest["status"] == "BUILD_EVIDENCE_ONLY_NOT_RUNTIME_QUALIFIED", "build evidence only")
    for name in ("source", "header", "abi", "compiler", "output_library",
                 "build_guard", "build_accounting", "build_source_review"):
        pin(manifest[name])
    require(type(manifest["dependencies"]) is list and 1 <= len(manifest["dependencies"]) <= 64,
            "bounded dependency evidence")
    expected = [manifest["compiler"]["path"], *FLAGS, "-o",
                manifest["output_library"]["path"], manifest["source"]["path"], "-lm"]
    require(type(manifest["argv"]) is list and manifest["argv"] == expected,
            "exact single compiler command evidence")
    return manifest
