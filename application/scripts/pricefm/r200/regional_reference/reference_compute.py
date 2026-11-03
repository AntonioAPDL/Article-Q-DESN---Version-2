"""Concrete compute-only entrypoint wired to the fixed shared owner boundary.

No caller-supplied validator, fake ACK flag, environment fixture or old R owner
receipt can replace compute_boundary.acquire. Native Python bootstrap qualification
and a fresh separate reference runtime purpose are still required.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat

def _bounded_metadata(pin):
    if type(pin) is not dict or set(pin) != {"path", "sha256"}:
        raise ValueError("closed metadata pin")
    p = Path(pin["path"])
    if not p.is_absolute() or any(x.is_symlink() for x in (p, *p.parents)):
        raise ValueError("physical source-review metadata")
    with os.fdopen(os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as f:
        s = os.fstat(f.fileno())
        if not stat.S_ISREG(s.st_mode) or s.st_nlink != 1 or s.st_uid != os.getuid() or s.st_size > 2**20:
            raise ValueError("bounded single-link owned source metadata")
        raw = f.read(2**20 + 1)
        after = os.fstat(f.fileno())
    if (s.st_dev, s.st_ino, s.st_mtime_ns, s.st_ctime_ns, s.st_size) != (
            after.st_dev, after.st_ino, after.st_mtime_ns, after.st_ctime_ns, after.st_size):
        raise ValueError("metadata changed while reading")
    if hashlib.sha256(raw).hexdigest() != pin["sha256"]:
        raise ValueError("source-review pin mismatch")
    def pairs(items):
        out = {}
        for key, value in items:
            if key in out:
                raise ValueError("duplicate metadata key")
            out[key] = value
        return out
    return json.loads(raw, object_pairs_hook=pairs,
        parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite metadata")))

def _load_fixed_source(relative_name, source_review, module_name):
    # Fixed sibling path; reviewed path AND bytes must match. No search-path import.
    root = Path(__file__).absolute().parent.parent
    target = root / relative_name
    pin = source_review["source_pins"][relative_name]
    if pin["path"] != str(target) or any(x.is_symlink() for x in (target, *target.parents)):
        raise ValueError("fixed exact reviewed source path")
    with os.fdopen(os.open(target, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_uid != os.getuid() or before.st_size > 2**20:
            raise ValueError("bounded single-link owned source")
        raw = stream.read(2**20 + 1)
        after = os.fstat(stream.fileno())
    identity = lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns, x.st_ctime_ns, x.st_uid, x.st_nlink)
    if identity(before) != identity(after) or identity(after) != identity(target.stat()):
        raise ValueError("fixed source changed while reading")
    if len(raw) != before.st_size or hashlib.sha256(raw).hexdigest() != pin["sha256"]:
        raise ValueError("fixed reviewed source bytes")
    spec = importlib.util.spec_from_file_location(module_name, target)
    module = importlib.util.module_from_spec(spec)
    # Execute the exact verified bytes. A loader re-open would introduce a race.
    import sys
    sys.modules[module_name] = module
    exec(compile(raw, str(target), "exec"), module.__dict__)
    return module

def run(spec_pin, authority_pin, source_review_pin, acknowledgement_pin):
    """Acquire real ownership before request/payload parsing or kernel import.

    Returns serializable result data to the owning controller's separately
    admitted bounded writer/return path; this function writes no output file.
    """
    review = _bounded_metadata(source_review_pin)
    owner = _load_fixed_source("owner/compute_boundary.py", review, "_r200_reference_owner")
    boundary = owner.acquire(spec_pin, authority_pin, source_review_pin, acknowledgement_pin)
    boundary.verify_live()
    contract = _load_fixed_source("regional_reference/reference_contract.py", review,
                                 "_r200_reference_contract")
    request_bytes = boundary.read_input("reference_request")
    request = contract.strict_json(request_bytes)
    contract.validate_request(request)
    boundary.verify_live()
    payloads = {}
    for name, alias in request["input_names"].items():
        boundary.verify_live()
        payloads[name] = boundary.read_input(alias)
    for key in ("precision", "rhs"):
        wanted = request["target_construction"]["precision_rhs_identity"][key + "_sha256"]
        if hashlib.sha256(payloads[key]).hexdigest() != wanted:
            raise ValueError("exact P/RHS bytes differ from predetermined request")
    # Importing or calling numeric kernels before actual acquire/verify/read is forbidden.
    kernel = _load_fixed_source("regional_reference/decimal_reference.py", review,
                               "_r200_decimal_reference")
    boundary.verify_live()
    result = kernel._compute(request, payloads)
    boundary.verify_live()
    result["input_sha256"] = {key: hashlib.sha256(raw).hexdigest()
                              for key, raw in payloads.items()}
    result["request_sha256"] = hashlib.sha256(request_bytes).hexdigest()
    result["source_review"] = source_review_pin
    result["runtime_and_native_bootstrap_cannot_be_inferred_from_source_review"] = True
    boundary.verify_live()
    return _encode_return_parts(result)

def run_synthetic(spec_pin, authority_pin, source_review_pin, acknowledgement_pin):
    """Separate owned synthetic request; never an uncounted target fit."""
    review = _bounded_metadata(source_review_pin)
    owner = _load_fixed_source("owner/compute_boundary.py", review, "_r200_reference_owner")
    boundary = owner.acquire(spec_pin, authority_pin, source_review_pin, acknowledgement_pin)
    boundary.verify_live()
    contract = _load_fixed_source("regional_reference/reference_contract.py", review,
                                 "_r200_reference_contract")
    request = contract.strict_json(boundary.read_input("reference_fixture_request"))
    if request != {"schema": "r200_analytic_reference_fixture_request_v1",
                   "sizes": [8, 16, 32], "families": ["diagonal", "rank_one", "paired_ill_conditioned"],
                   "optimizer_updates": 0, "new_posterior_fits": 0}:
        raise ValueError("exact separately admitted analytic fixture set")
    fixtures = _load_fixed_source("regional_reference/analytical_fixtures.py", review,
                                 "_r200_reference_fixtures")
    kernel = _load_fixed_source("regional_reference/decimal_reference.py", review,
                               "_r200_decimal_reference")
    boundary.verify_live()
    result = fixtures._run_compute_only(kernel)
    boundary.verify_live()
    return result


def _encode_return_parts(result):
    """Prepare bounded immutable-file bytes; no writes, cap enlargement or drops.

    The owning separately qualified bounded writer must commit every returned
    part. Numerical covariance entries remain full original-unit binary64 views;
    no selected/probe-only rows substitute for the full covariance.
    """
    summary = dict(result)
    covariance = dict(summary["full_covariance"])
    blocks = covariance.pop("covariance_row_blocks")
    records = []
    descriptors = []
    for index, block in enumerate(blocks):
        name = "reference_covariance_rows_%04d.json" % index
        raw = (json.dumps(block, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode("ascii")
        if len(raw) > 16 * 1024**2:
            raise ValueError("original 16MiB per-file return bound exceeded")
        digest = hashlib.sha256(raw).hexdigest()
        records.append({"relative_path": name, "sha256": digest, "bytes": len(raw), "payload": raw})
        descriptors.append({"relative_path": name, "sha256": digest, "bytes": len(raw),
                            "first_row": block["first_row"], "row_count": len(block["rows"])})
    covariance["complete_covariance_blocks"] = descriptors
    summary["full_covariance"] = covariance
    raw = (json.dumps(summary, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode("ascii")
    if len(raw) > 16 * 1024**2:
        raise ValueError("original 16MiB summary bound exceeded")
    records.append({"relative_path": "reference_summary.json",
                    "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw), "payload": raw})
    total = sum(item["bytes"] for item in records)
    if total > 64 * 1024**2:
        raise ValueError("original 64MiB useful-return bound exceeded")
    return {"schema": "r200_reference_owned_return_parts_v1", "records": records,
            "total_bytes": total, "complete_full_covariance": True,
            "payloads_are_owned_compute_output_not_admin_fixtures": True,
            "scientific_acceptance": False, "runtime_admission_transferred": False}
