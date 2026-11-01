"""Strict metadata preparation for one future NO3 pilot.

This module cannot grant, submit, import a state, inspect scientific binary
values, or certify numerical provenance. It deliberately stays outside the
live TOY_PARITY/ZERO_UPDATE_BRIDGE dispatch. Its contracts make the missing
future compute-owner and independent-verifier work explicit.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat

_contract_path = Path(__file__).resolve().with_name("numerical_stage_contract.py")
_contract_spec = importlib.util.spec_from_file_location("_r190_frozen_contract", _contract_path)
_contract = importlib.util.module_from_spec(_contract_spec)
_contract_spec.loader.exec_module(_contract)
DELIVERY_BYTES = _contract.DELIVERY_BYTES
DELIVERY_HASHES = _contract.DELIVERY_HASHES
LIMITS = _contract.LIMITS
ORIGINAL_MANIFEST_SHA = _contract.ORIGINAL_MANIFEST_SHA
SCIENCE_HASHES = _contract.SCIENCE_HASHES
STOCK_BODY_SHA = _contract.STOCK_BODY_SHA
TARGET = _contract.TARGET

SHA = re.compile(r"[0-9a-f]{64}")
HEAD = re.compile(r"[0-9a-f]{40}")
CASE = dict(
    target=TARGET, n=48576, p=417, tau=.75, tau0=.0022915214919211734,
    maximum_pilot_attempts=1, maximum_optimizer_invocations=1, max_iter=300,
    seed=819509105, tol=1e-5, n_samp=20, n_samp_xi=20,
    max_rhs_iter=20000, units="original_design_and_response",
    prior=dict(family="rhs_ns", center="zero", shrink_intercept=False,
               sigma_a=1.0, sigma_b=1.0, freeze_tau_iters=0,
               freeze_tau_warmup_iters=0),
    acceptance="finite AND (formal OR independent)",
    limits=LIMITS, both_RHS_starts=True, compute_all_seven_even_if_formal=True,
    exact_optimizer_resume=False, official_test_opening_or_selection=False,
    automatic_production_promotion=False,
)
BRIDGE_PROOF_NAMES = {
    "accepted", "outer_accept_guard", "result", "accounting",
    "independent_review", "full_return_manifest", "finalization",
    "bridge_validation", "factor_state", "baseline_certificate",
}
IMPORT_CHECKS = (
    "current_owned_job_lifetime", "current_native_TSYNC_and_parent_ACK",
    "state_hash_length_UID_and_canonical_path",
    "source_provenance_entire_scientific_source",
    "source_provenance_original_failed_bindings",
    "state_schema_kind_origin_and_posterior_target",
    "prior_controls_and_original_units",
    "X_y_hash_length_UID_and_complete_alias_allowlist",
    "unchanged_frozen_factor_validator",
    "unchanged_explicit_factor_objective",
    "no_factor_reconditioning_or_provenance_rewrite",
)
PILOT_CORE = {
    "final_state.rds", "independent_certificate_full_state.rds",
    "terminal_core.json", "beta_mean.bin", "beta_cov.bin",
    "vb_trace.csv", "checkpoint_index.json",
}
PILOT_PROOFS = {
    "proof/owned_guard.json", "proof/owned_tree.json",
    "proof/PARSE_PARENT_GATE.json", "proof/COMPUTE_IMPORT_PROVENANCE.json",
    "proof/SOURCE_RUNTIME_MANIFEST.json", "proof/REPRODUCTION.json",
}
MAX_RETURN_FILE = 16 * 1024**2
MAX_RETURN_TOTAL = 64 * 1024**2


def require(ok, message):
    if not ok:
        raise ValueError(message)


def closed(value, names, label):
    require(type(value) is dict and set(value) == set(names), label + " closed keys")
    return value


def integer(value, lower, upper, label):
    require(type(value) is int and lower <= value <= upper, label + " integer range")
    return value


def digest(value):
    require(type(value) is str and SHA.fullmatch(value) is not None, "SHA256")
    return value


def path(value, absolute):
    require(type(value) is str and "\x00" not in value, "path string")
    p = PurePosixPath(value)
    require(p.is_absolute() is absolute and value == str(p)
            and ".." not in p.parts and value not in {"", ".", "/"},
            "canonical " + ("absolute" if absolute else "relative") + " path")
    return value


def pin(value):
    closed(value, {"path", "sha256"}, "pin")
    path(value["path"], True)
    digest(value["sha256"])
    return value


def scientific_source(value):
    closed(value, {"kind", "head", "branch"}, "scientific source")
    require(type(value["kind"]) is str and 1 <= len(value["kind"]) <= 128,
            "scientific source kind")
    require(type(value["head"]) is str and HEAD.fullmatch(value["head"]) is not None,
            "scientific source commit")
    require(type(value["branch"]) is str and value["branch"].startswith("work/pricefm-")
            and len(value["branch"]) <= 160 and not any(c.isspace() for c in value["branch"]),
            "scientific source branch")
    return value


def controller_source(value):
    closed(value, {"commit", "branch", "files"}, "controller source")
    require(type(value["commit"]) is str and HEAD.fullmatch(value["commit"]) is not None,
            "controller commit")
    require(type(value["branch"]) is str and value["branch"].startswith("work/pricefm-")
            and len(value["branch"]) <= 160 and not any(c.isspace() for c in value["branch"]),
            "controller branch")
    require(type(value["files"]) is dict and 1 <= len(value["files"]) <= 64,
            "finite controller source closure")
    for name, sha in value["files"].items():
        path(name, False)
        require(name.startswith("application/"), "application-only controller path")
        digest(sha)
    return value


def data_references(value):
    closed(value, {"X", "y"}, "data references")
    for name in ("X", "y"):
        row = closed(value[name], {"path", "sha256", "bytes"}, name + " reference")
        path(row["path"], True)
        rel = "design/" + name + ".bin"
        require(row["sha256"] == DELIVERY_HASHES[rel]
                and type(row["bytes"]) is int and row["bytes"] == DELIVERY_BYTES[rel],
                "exact original " + name + " bytes")
    require(value["X"]["path"] != value["y"]["path"], "distinct X/y physical references")
    return value


def fixed_prior(value):
    closed(value, CASE["prior"], "fixed prior")
    require(value["family"] == "rhs_ns" and value["center"] == "zero"
            and value["shrink_intercept"] is False, "fixed prior identity")
    for key in ("sigma_a", "sigma_b"):
        require(type(value[key]) in (int, float) and value[key] == 1,
                "fixed numeric sigma prior")
    for key in ("freeze_tau_iters", "freeze_tau_warmup_iters"):
        require(type(value[key]) is int and value[key] == 0, "no frozen tau iterations")
    return value


def validate_bridge_binding(value):
    """Validate only a future verified-closure descriptor, not its proof bytes.

    A separately reviewed independent verifier must reconcile these pins with
    the actual accepted chain. An object passing this schema earns no gate.
    """
    closed(value, {
        "schema", "accepted_job_id", "scientific_source", "scientific_files",
        "stock_body_sha256", "original_manifest_sha256", "target",
        "posterior_target_sha256", "units", "prior", "data_references",
        "original_failed_bindings", "proof_pins", "acceptance_chain_independently_verified",
    }, "bridge binding")
    require(value["schema"] == "r190_eventual_bridge_binding_metadata_v1", "bridge binding schema")
    require(type(value["accepted_job_id"]) is str
            and re.fullmatch(r"[1-9][0-9]{0,11}", value["accepted_job_id"]) is not None,
            "bridge job identity")
    scientific_source(value["scientific_source"])
    require(value["scientific_files"] == SCIENCE_HASHES
            and value["stock_body_sha256"] == STOCK_BODY_SHA
            and value["original_manifest_sha256"] == ORIGINAL_MANIFEST_SHA,
            "unchanged scientific source/stock/original manifest")
    require(value["target"] == TARGET and value["units"] == CASE["units"],
            "exact target/units")
    fixed_prior(value["prior"])
    digest(value["posterior_target_sha256"])
    data_references(value["data_references"])
    rows = value["original_failed_bindings"]
    require(type(rows) is list and 1 <= len(rows) <= 32, "finite original failed bindings")
    for row in rows:
        pin(row)
    require(len({r["path"] for r in rows}) == len(rows), "unique original failed bindings")
    closed(value["proof_pins"], BRIDGE_PROOF_NAMES, "bridge acceptance closure")
    for item in value["proof_pins"].values():
        pin(item)
    require(value["acceptance_chain_independently_verified"] is False,
            "metadata descriptor cannot assert independent acceptance")
    return copy.deepcopy(value)


def relocation_aliases(bridge, aliases):
    """Require one-to-one byte-equivalent aliases; never rewrite old state."""
    validate_bridge_binding(bridge)
    closed(aliases, {"X", "y"}, "relocation aliases")
    physical = []
    for name in ("X", "y"):
        old = bridge["data_references"][name]
        row = closed(aliases[name], {"logical_path", "physical_path", "sha256", "bytes"},
                     name + " alias")
        path(row["physical_path"], True)
        require(row["logical_path"] == old["path"] and row["sha256"] == old["sha256"]
                and type(row["bytes"]) is int and row["bytes"] == old["bytes"],
                "exact old logical reference and new identical bytes")
        physical.append(row["physical_path"])
    require(len(set(physical)) == 2, "one-to-one physical aliases")
    return copy.deepcopy(aliases)


def import_verification_interface(bridge, aliases):
    validate_bridge_binding(bridge)
    relocation_aliases(bridge, aliases)
    return dict(
        schema="r190_future_compute_import_verification_interface_v1",
        execution_location="CURRENT_OWNED_COMPUTE_AFTER_NATIVE_TSYNC_AND_PARENT_ACK",
        position="BEFORE_FROZEN_FACTOR_IMPORT_AND_OPTIMIZER",
        expected_bridge=copy.deepcopy(bridge),
        aliases=copy.deepcopy(aliases),
        exact_required_checks=list(IMPORT_CHECKS),
        byte_or_RDS_values_verified=False,
        runtime_implementation_and_proof_pending=True,
        must_preserve_old_JSON_RDS_and_hashes=True,
        missing_or_mismatched_check_stops_import=True,
        mathematical_factor_validator_and_objective_unchanged=True,
        grants_import_or_optimizer_authority=False,
    )


def selected_checkpoints(completed_sweeps):
    integer(completed_sweeps, 1, 300, "completed sweeps")
    return sorted({1, (completed_sweeps + 1) // 2, completed_sweeps})


def checkpoint_names(number):
    stem = "checkpoints/sweep_%04d/" % number
    return {stem + "full_state.rds", stem + "completed_evidence.json"}


def retention_plan(files, completed_sweeps, envelope):
    """Check exact descriptor inventories and prospective envelopes only.

    No file content is opened. Complete remote owned byte validation, filesystem
    reservation, bounded pre-write enforcement and return-chain verification
    remain necessary in a separate future pilot owner.
    """
    integer(completed_sweeps, 1, 300, "completed sweeps")
    closed(envelope, {
        "remote_file_bytes", "remote_total_bytes", "next_write_reserve_bytes",
        "reserved_filesystem_bytes", "main_file_bytes", "main_total_bytes",
    }, "retention envelope")
    for key in envelope:
        integer(envelope[key], 1, 64 * 1024**3, key)
    require(envelope["main_file_bytes"] <= MAX_RETURN_FILE
            and envelope["main_total_bytes"] <= MAX_RETURN_TOTAL,
            "existing useful-return caps cannot be enlarged by preparation")
    require(envelope["next_write_reserve_bytes"] >= envelope["remote_file_bytes"]
            and envelope["reserved_filesystem_bytes"] >= envelope["remote_total_bytes"]
            + envelope["next_write_reserve_bytes"],
            "preflight storage must cover full retained budget and next write")
    require(type(files) is list and 1 <= len(files) <= 640, "finite remote descriptor set")
    by_name = {}
    for row in files:
        closed(row, {"relative", "sha256", "bytes"}, "remote file descriptor")
        name = path(row["relative"], False)
        digest(row["sha256"])
        integer(row["bytes"], 1, envelope["remote_file_bytes"], "remote file size")
        require(name not in by_name, "unique remote file")
        by_name[name] = copy.deepcopy(row)
    required = set(PILOT_CORE) | set(PILOT_PROOFS)
    for i in range(1, completed_sweeps + 1):
        required |= checkpoint_names(i)
    require(set(by_name) == required, "all actual sweeps and exact core/proofs retained")
    remote_total = sum(row["bytes"] for row in files)
    require(remote_total <= envelope["remote_total_bytes"], "remote total envelope")
    selected = selected_checkpoints(completed_sweeps)
    main_names = set(PILOT_CORE) | set(PILOT_PROOFS)
    for i in selected:
        main_names |= checkpoint_names(i)
    useful = [by_name[name] for name in sorted(main_names)]
    require(all(r["bytes"] <= envelope["main_file_bytes"] for r in useful)
            and sum(r["bytes"] for r in useful) <= envelope["main_total_bytes"],
            "exact useful main return fits both immutable caps")
    return dict(
        schema="r190_pilot_retention_descriptor_plan_v1",
        status="DESCRIPTORS_VALID_ACTUAL_BYTES_AND_STORAGE_UNVERIFIED",
        completed_sweeps=completed_sweeps, selected_checkpoint_sweeps=selected,
        selection_rule="unique{1,ceil(N/2),N}; completed-count-only",
        remote_retained=[by_name[name] for name in sorted(by_name)],
        main_return=useful, remote_total_bytes=remote_total,
        main_return_total_bytes=sum(r["bytes"] for r in useful),
        envelope=copy.deepcopy(envelope),
        all_remote_checkpoints_retained=True,
        original_checkpoint_index_returned=True,
        complete_remote_inventory_and_terminal_acceptance_chain_still_required=True,
        actual_RDS_sizes_or_storage_price_measured=False,
        automatic_delete_or_optimizer_resume=False,
        grants_execution_or_retention_authority=False,
    )


def prepare(controller, bridge=None, aliases=None, retention=None):
    controller_source(controller)
    if bridge is None:
        require(aliases is None, "aliases require eventual bridge")
        interface = None
    else:
        require(aliases is not None, "exact bridge input aliases required")
        interface = import_verification_interface(bridge, aliases)
    if retention is not None:
        closed(retention, {"files", "completed_sweeps", "envelope"}, "retention input")
        retention = retention_plan(**retention)
    return dict(
        schema="r190_exact_NO3_pilot_preparation_v1",
        status="PREPARED_METADATA_CONTRACTS_PILOT_UNADMITTED",
        case=copy.deepcopy(CASE),
        controller_source=copy.deepcopy(controller),
        scientific_files=copy.deepcopy(SCIENCE_HASHES),
        stock_body_sha256=STOCK_BODY_SHA,
        eventual_bridge_binding=None if bridge is None else copy.deepcopy(bridge),
        compute_import_verification_interface=interface,
        retention_descriptor_plan=retention,
        pending_gates=[
            "actual_accepted_bridge_chain_independently_reconciled",
            "distinct_pilot_owner_worker_controller_and_two_phase_peer",
            "current_post_ACK_RDS_provenance_and_factor_objective_verification",
            "complete_remote_inventory_and_prewrite_storage_enforcement",
            "actual_useful_return_sizes_and_finite_storage_retention_price",
            "applicable_complete_source_context_CPU_wall_memory_price",
            "fresh_source_publication_scope_resource_and_kernel_admission",
            "one_actual_pilot_complete_return_review_acceptance_and_finalize",
        ],
        pilot_launch_ready=False, authorizes_optimizer=False,
        authorizes_target_read_or_state_import=False,
        production_admission=False, exact_optimizer_resume=False,
        source_or_binary_provenance_rewritten=False,
        old_scope_role_fee_or_clock_reused=False,
    )


def read_metadata_json(filename):
    p = Path(path(str(filename), True))
    require(p.suffix == ".json" and not any(x.is_symlink() for x in (p, *p.parents)),
            "regular metadata JSON path only")
    fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                and info.st_size <= 4 * 1024**2, "bounded single-link metadata file")
        with os.fdopen(fd, "rb", closefd=False) as f:
            raw = f.read(4 * 1024**2 + 1)
        after = os.fstat(fd)
        require((info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)
                == (after.st_dev, after.st_ino, after.st_size,
                    after.st_mtime_ns, after.st_ctime_ns), "stable metadata read")
    finally:
        os.close(fd)
    def pairs(rows):
        out = {}
        for key, val in rows:
            require(key not in out, "duplicate JSON keys")
            out[key] = val
        return out
    def reject_constant(value):
        raise ValueError("nonfinite JSON constant: " + value)
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=reject_constant)


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("--input", required=True, help="absolute bounded JSON metadata")
    args.add_argument("--output", required=True, help="new absolute preparation JSON")
    options = args.parse_args()
    value = read_metadata_json(options.input)
    closed(value, {"controller", "bridge", "aliases", "retention"}, "preparation input")
    output = prepare(**value)
    p = Path(path(options.output, True))
    require(p.suffix == ".json" and not any(x.is_symlink() for x in p.parents),
            "new metadata JSON output")
    with p.open("x") as f:
        json.dump(output, f, indent=2, sort_keys=True, allow_nan=False)
        f.write("\n")
    print(json.dumps(dict(status=output["status"],pilot_launch_ready=False,
                         output=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest())))


if __name__ == "__main__":
    main()

