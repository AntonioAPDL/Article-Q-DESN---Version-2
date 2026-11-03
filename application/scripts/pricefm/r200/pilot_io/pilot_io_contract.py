"""Closed descriptor contract for new compute-owned NO3 I/O.
Validation never opens scientific data and never grants I/O or execution.
Actual native/R qualification remains a separate required gate.
"""
import copy, hashlib, json, math, re
from pathlib import PurePosixPath

TARGET = "iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75"
LIMITS = dict(beta_posterior_sd_rms=1e-4, covariance_whitened_rms=1e-4,
              elbo_relative=1e-8, predictor_rms=1e-6, rhs_joint_log_rates=1e-6,
              rhs_start_log_precision=1e-6, sigma_relative=1e-6)
CASE = dict(target=TARGET, n=48576, p=417, tau=.75, tau0=.0022915214919211734,
            max_iter=300, seed=819509105, max_rhs_iter=20000, tol=1e-5, n_samp=20, n_samp_xi=20,
            maximum_pilot_attempts=1, maximum_optimizer_invocations=1,
            units="original_design_and_response", exact_optimizer_resume=False,
            prior=dict(family="rhs_ns", center="zero", shrink_intercept=False,
                       sigma_a=1.0, sigma_b=1.0, freeze_tau_iters=0, freeze_tau_warmup_iters=0),
            acceptance="finite AND(formal OR independent)", limits=LIMITS,
            both_RHS_starts=True, official_test_selection=False)
MAX_FILE = 16 * 1024**2
MAX_RETURN = 64 * 1024**2
R_OUTPUTS = {"final_state.rds", "independent_certificate_full_state.rds", "terminal_core.json",
             "beta_mean.bin", "beta_cov.bin", "vb_trace.csv", "checkpoint_index.json",
             "proof/COMPUTE_IMPORT_PROVENANCE.json"}
RETURN_OUTPUTS = R_OUTPUTS | {"proof/owned_guard.json", "proof/owned_tree.json",
    "proof/PARSE_PARENT_GATE.json", "proof/SOURCE_RUNTIME_MANIFEST.json", "proof/REPRODUCTION.json"}
BRIDGE_KEYS = {"accepted", "outer_accept_guard", "result", "accounting",
               "independent_review", "full_return_manifest", "finalization",
               "bridge_validation", "factor_state", "baseline_certificate"}

def require(ok, reason):
    if not ok:
        raise ValueError(reason)

def closed(value, keys, label):
    require(type(value) is dict and set(value) == set(keys), label + ": closed keys")

def integer(value, low, high, label):
    require(type(value) is int and low <= value <= high, label + ": typed integer")
    return value

def path(value, absolute):
    require(type(value) is str and len(value) <= 2048 and "\0" not in value, "path text")
    p = PurePosixPath(value)
    require(p.is_absolute() is absolute and str(p) == value and
            ".." not in p.parts and value not in {"", ".", "/"}, "canonical path")
    require(all(re.fullmatch(r"[A-Za-z0-9_.-]+", x) for x in p.parts if x != "/"), "path alphabet")
    return value

def pin(value):
    closed(value, {"path", "sha256"}, "pin")
    path(value["path"], True)
    require(type(value["sha256"]) is str and re.fullmatch("[0-9a-f]{64}", value["sha256"]), "SHA256")
    return value

def exact(value, wanted, label):
    require(type(value) is type(wanted), label + ": exact type")
    if isinstance(wanted, dict):
        closed(value, wanted, label)
        for key in wanted:
            exact(value[key], wanted[key], label + "." + key)
    elif isinstance(wanted, list):
        require(len(value) == len(wanted), label + ": length")
        for i, (a, b) in enumerate(zip(value, wanted)):
            exact(a, b, label + "." + str(i))
    else:
        require(value == wanted, label + ": exact value")

def strict_json(raw):
    require(type(raw) in (str, bytes) and len(raw) <= 4 * 1024**2, "bounded JSON")
    def pairs(xs):
        result = {}
        for k, v in xs:
            require(k not in result, "duplicate JSON key")
            result[k] = v
        return result
    def bad(x):
        raise ValueError("nonfinite JSON")
    def finite_number(text):
        value = float(text)
        require(math.isfinite(value), "nonfinite JSON float")
        return value
    return json.loads(raw, object_pairs_hook=pairs, parse_float=finite_number, parse_constant=bad)

def checkpoint_slots(envelope, metadata_envelope):
    """Only names/counts are generated, never scientific objects."""
    integer(envelope, 1, MAX_FILE, "measured RDS envelope")
    integer(metadata_envelope, 1, MAX_FILE, "measured metadata envelope")
    result = []
    for sweep in range(1, 301):
        base = "checkpoints/sweep_%04d/" % sweep
        for name, cap, kind in (("full_state.rds", envelope, "checkpoint"),
                                ("completed_evidence.json", metadata_envelope, "checkpoint_metadata")):
            result.append(dict(name=base + name, max_bytes=cap, kind=kind, sweep=sweep))
    return result

def validate_request(request):
    keys = {"schema", "purpose", "nonce", "role", "case", "scientific_source",
            "controller_source", "science_source_pins", "accepted_bridge", "proof_aliases", "inputs",
            "expected_state_provenance", "posterior_target_sha256", "original_manifest_sha256",
            "output_root", "storage", "native_boundary", "io_library", "runtime_build", "scientific_context"}
    closed(request, keys, "I/O request")
    require(request["schema"] == "r200_pilot_owned_io_request_v1" and
            request["role"] == "NO3_AL300_PILOT", "exact independent pilot role")
    require(type(request["purpose"]) is str and re.fullmatch("[A-Za-z0-9_]{1,96}", request["purpose"]), "purpose")
    require(type(request["nonce"]) is str and re.fullmatch("[0-9a-f]{32}", request["nonce"]), "nonce")
    exact(request["case"], CASE, "unchanged NO3 case")
    for key in ("controller_source", "native_boundary", "io_library"):
        pin(request[key])
    source = request["scientific_source"]
    closed(source, {"kind", "head", "branch"}, "whole scientific source")
    require(all(type(v) is str and v for v in source.values()) and
            re.fullmatch("[0-9a-f]{40}", source["head"]), "scientific identity")
    require(type(request["science_source_pins"]) is list and len(request["science_source_pins"]) == 5,
            "exact five unchanged scientific files")
    for item in request["science_source_pins"]:
        pin(item)
    require(len({p["path"] for p in request["science_source_pins"]}) == 5, "unique science source paths")
    closed(request["accepted_bridge"], BRIDGE_KEYS, "complete accepted bridge closure")
    for item in request["accepted_bridge"].values():
        pin(item)
    aliases = request["proof_aliases"]
    require(type(aliases) is list and len(aliases) == len(BRIDGE_KEYS), "exact proof-alias sidecar")
    wanted = {(v["path"], v["sha256"]) for v in request["accepted_bridge"].values()}
    seen = set(); physical_seen = set()
    for row in aliases:
        closed(row, {"logical", "physical", "bytes", "uid"}, "proof alias")
        pin(row["logical"]); pin(row["physical"])
        require(row["logical"]["sha256"] == row["physical"]["sha256"], "proof alias preserves exact old bytes")
        key = (row["logical"]["path"], row["logical"]["sha256"])
        require(key in wanted and key not in seen and row["physical"]["path"] not in physical_seen, "one-to-one exact proof aliases")
        seen.add(key); physical_seen.add(row["physical"]["path"])
        integer(row["bytes"], 1, MAX_FILE, "proof alias byte length")
        integer(row["uid"], 0, 2**31 - 1, "proof alias UID")
    require(seen == wanted, "no dropped or foreign proof alias")
    require(request["original_manifest_sha256"] ==
            "aecbee983a05bb4bebbc86b345a8678d1879116c9a273a618ff05dcaaff99af8", "original manifest")
    require(type(request["posterior_target_sha256"]) is str and request["posterior_target_sha256"], "posterior target")
    closed(request["inputs"], {"X", "y", "factor_state"}, "complete input allowlist")
    for name, item in request["inputs"].items():
        closed(item, {"logical", "physical", "bytes", "sha256"}, "input")
        path(item["logical"], True); path(item["physical"], True)
        integer(item["bytes"], 1, 1024**3, "input bytes")
        pin(dict(path=item["physical"], sha256=item["sha256"]))
        if name == "X":
            require(item["bytes"] == 48576 * 417 * 8, "exact X byte count")
        elif name == "y":
            require(item["bytes"] == 48576 * 8, "exact y byte count")
        else:
            require(item["bytes"] <= MAX_FILE, "factor-state original per-file cap")
            require(item["logical"] == request["accepted_bridge"]["factor_state"]["path"] and
                    item["sha256"] == request["accepted_bridge"]["factor_state"]["sha256"], "exact immutable bridge state")
    require(len({v["physical"] for v in request["inputs"].values()}) == 3, "no input aliases collide")
    provenance = request["expected_state_provenance"]
    closed(provenance, {"source", "data_references", "original_failed_bindings",
                        "prior_attempt_iterations", "conditional_RHS_counts_not_AL_sweeps",
                        "exact_optimizer_resume", "old_missing_factors_recovered"}, "entire stored provenance")
    exact(provenance["source"], source, "scientific identity, never controller commit")
    require(provenance["prior_attempt_iterations"] == 300 and
            provenance["exact_optimizer_resume"] is False and
            provenance["old_missing_factors_recovered"] is False, "unchanged initialization semantics")
    require(type(provenance["original_failed_bindings"]) is list and provenance["original_failed_bindings"], "whole original failures")
    for item in provenance["original_failed_bindings"]:
        require(type(item) is dict and {"path", "sha256"} <= set(item) <= {"path", "sha256", "bytes"}, "original failure pin")
        pin(dict(path=item["path"], sha256=item["sha256"]))
    closed(provenance["data_references"], {"X", "y"}, "stored data references")
    for name in ("X", "y"):
        exact(provenance["data_references"][name],
              dict(path=request["inputs"][name]["logical"], sha256=request["inputs"][name]["sha256"]),
              "immutable logical X/y references")
    path(request["output_root"], True)
    storage = request["storage"]
    closed(storage, {"slots", "measured_rds_envelope", "measured_metadata_envelope",
                     "required_output_slots", "headroom_bytes", "max_snapshot_bytes",
                     "measurement", "complete_cost"}, "storage")
    for key in ("measurement", "complete_cost"):
        pin(storage[key])
    integer(storage["headroom_bytes"], 1, 2**53 - 1, "mandatory headroom")
    integer(storage["max_snapshot_bytes"], 1, 1024**3, "sealed input snapshot budget")
    require(storage["max_snapshot_bytes"] >= sum(v["bytes"] for v in request["inputs"].values()) + sum(v["bytes"] for v in aliases), "complete payload and proof snapshot budget")
    factor_alias = next(a for a in aliases if a["logical"] == request["accepted_bridge"]["factor_state"])
    require(factor_alias["physical"]["path"] == request["inputs"]["factor_state"]["physical"] and factor_alias["bytes"] == request["inputs"]["factor_state"]["bytes"], "factor snapshot and explicit proof alias coincide")
    expected = checkpoint_slots(storage["measured_rds_envelope"], storage["measured_metadata_envelope"])
    extras = storage["required_output_slots"]
    require(type(extras) is list and {v.get("name") for v in extras} == R_OUTPUTS and len(extras) == len(R_OUTPUTS), "exact R output inventory including owned import proof")
    for item in extras:
        closed(item, {"name", "max_bytes", "kind", "sweep"}, "slot")
        path(item["name"], False); integer(item["max_bytes"], 1, MAX_FILE, "per-file cap")
        require(item["kind"] == "output" and item["sweep"] == 0 and not item["name"].startswith("checkpoints/"), "noncheckpoint output")
    exact(storage["slots"], expected + extras, "complete physical reservation inventory")
    require(len({v["name"] for v in storage["slots"]}) == len(storage["slots"]), "no duplicate reservations")
    context = request["scientific_context"]
    closed(context, {"original_manifest", "fixedpoint_helper", "project_consumer", "library", "expected_stock_body_sha256"}, "original scientific context")
    for key in ("original_manifest", "fixedpoint_helper", "project_consumer"):
        pin(context[key])
    require(context["original_manifest"]["sha256"] == request["original_manifest_sha256"], "original manifest file pin")
    require(context["fixedpoint_helper"] in request["science_source_pins"] and context["project_consumer"] in request["science_source_pins"], "unchanged helper and525 are original five source pins")
    path(context["library"], True)
    require(type(context["expected_stock_body_sha256"]) is str and re.fullmatch("[0-9a-f]{64}", context["expected_stock_body_sha256"]), "stock body identity")
    build = request["runtime_build"]
    closed(build, {"R_version", "connection_api_version", "connection_header", "compiler_manifest",
                   "source", "build_manifest", "runtime_qualification"}, "new DLL closure")
    require(type(build["R_version"]) is str and build["R_version"] and
            type(build["connection_api_version"]) is int and build["connection_api_version"] == 1, "pinned R ABI")
    for key in ("connection_header", "compiler_manifest", "source", "build_manifest", "runtime_qualification"):
        pin(build[key])
    return dict(status="DESCRIPTORS_CONSISTENT_ACTUAL_NATIVE_R_QUALIFICATION_REQUIRED",
                can_write=False, runtime_admitted=False, measurement_or_bridge_truth_verified=False,
                request_sha256=hashlib.sha256(json.dumps(request, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest(),
                reserved_slot_bytes=sum(v["max_bytes"] for v in storage["slots"]),
                retained_remote_checkpoints=300, new_input_or_optimizer_grant=False)

def validate_return(inventory, completed_sweeps, requested_names):
    integer(completed_sweeps, 1, 300, "completed sweeps")
    require(type(inventory) is list and inventory, "actual remote inventory")
    byname = {}
    for item in inventory:
        closed(item, {"name", "bytes", "sha256", "sweep", "committed"}, "inventory row")
        path(item["name"], False); integer(item["bytes"], 1, MAX_FILE, "return file cap")
        require(item["name"] not in byname and item["committed"] is True and
                re.fullmatch("[0-9a-f]{64}", item["sha256"]), "unique committed return row")
        integer(item["sweep"], 0, completed_sweeps, "committed sweep")
        if item["sweep"] == 0:
            require(item["name"] in RETURN_OUTPUTS, "undeclared noncheckpoint return")
        else:
            require(item["name"] in {"checkpoints/sweep_%04d/%s" % (item["sweep"], n)
                    for n in ("full_state.rds", "completed_evidence.json")}, "exact sweep path")
        byname[item["name"]] = item
    require({name for name, row in byname.items() if row["sweep"] == 0} == RETURN_OUTPUTS, "complete useful proof and core return")
    for sweep in range(1, completed_sweeps + 1):
        for name in ("full_state.rds", "completed_evidence.json"):
            key = "checkpoints/sweep_%04d/%s" % (sweep, name)
            require(key in byname and byname[key]["sweep"] == sweep, "every completed checkpoint retained")
    selected = sorted({1, (completed_sweeps + 1) // 2, completed_sweeps})
    require(type(requested_names) is list and len(set(requested_names)) == len(requested_names), "unique useful return")
    required = {name for name, row in byname.items()
                if row["sweep"] == 0 or row["sweep"] in selected}
    require(set(requested_names) == required, "deterministic useful set, no outcome selection or omission")
    total = sum(byname[name]["bytes"] for name in requested_names)
    require(total <= MAX_RETURN, "64MiB useful return cap")
    return dict(status="RETURN_DESCRIPTORS_CONSISTENT_ACTUAL_OWNED_BYTES_REVIEW_REQUIRED",
                selected_sweeps=selected, total_bytes=total, actual_bytes_verified=False, acceptance=False)
