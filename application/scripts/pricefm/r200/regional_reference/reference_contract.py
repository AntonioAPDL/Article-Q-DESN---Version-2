"""Closed metadata contract for separate LT/NO4 reference compute.

Importing this module performs no numeric reference work or payload access.
Descriptor consistency is never native owner admission or scientific acceptance.
"""
import json
import math
import re

PROTOCOL_SHA256 = "720f7ba5ffb886866f807a4a7ae63c8a99acc56bf194688144dc5a19df022118"
PRECISIONS = [80, 120, 160]
LIMITS = {"beta_posterior_sd_rms": 1e-4, "covariance_whitened_rms": 1e-4,
          "elbo_relative": 1e-8, "predictor_rms": 1e-6,
          "rhs_joint_log_rates": 1e-6, "rhs_start_log_precision": 1e-6,
          "sigma_relative": 1e-6}
CASES = {
    "LT": {"target": "LT_fold1_al0.90", "n": 90240, "p": 337,
           "seed": 710583720, "tau": "0.9", "tau0": "2.5682335211342966e-05"},
    "NO4_PRIMARY": {"target": "iq_NO_4_r134_20feba695ede3ad5_t9.653643731923e-05_s1_al0.50",
           "n": 48576, "p": 961, "seed": 1149227177,
           "tau": "0.5", "tau0": "9.653643731923241e-05"},
    "NO4_CONTROL": {"target": "iq_NO_4_r134_20feba695ede3ad5_t9.653643731923e-06_s1_al0.50",
           "n": 48576, "p": 961, "seed": 1149227177,
           "tau": "0.5", "tau0": "9.653643731923241e-06"},
}
PRIOR = {"family": "rhs_ns", "center": "zero", "shrink_intercept": False,
         "sigma_a": 1, "sigma_b": 1, "freeze_tau_iters": 0,
         "freeze_tau_warmup_iters": 0}
REQUIRED_INPUTS = {"precision", "rhs", "candidate_beta", "candidate_covariance"}
OBJECTIVE_INPUTS = {"design", "response", "factor_snapshot"}

def require(ok, why):
    if not ok:
        raise ValueError(why)

def exact(actual, expected, label):
    require(type(actual) is type(expected), label + ": exact type")
    if isinstance(expected, dict):
        require(set(actual) == set(expected), label + ": exact keys")
        for key in expected:
            exact(actual[key], expected[key], label + "." + key)
    elif isinstance(expected, list):
        require(len(actual) == len(expected), label + ": length")
        for a, b in zip(actual, expected):
            exact(a, b, label)
    else:
        require(actual == expected, label + ": value")

def strict_json(raw):
    require(type(raw) is bytes and len(raw) <= 16 * 1024**2, "bounded bytes JSON")
    def pairs(items):
        out = {}
        for key, value in items:
            require(key not in out, "duplicate JSON key")
            out[key] = value
        return out
    def number(text):
        value = float(text)
        require(math.isfinite(value), "nonfinite JSON")
        return value
    return json.loads(raw, object_pairs_hook=pairs, parse_float=number,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")))

def validate_request(value):
    keys = {"schema", "case", "target", "n", "p", "seed", "tau", "tau0",
            "protocol_sha256", "precision_schedule", "units", "prior",
            "input_names", "objective_mode", "binary_layout", "optimizer_updates",
            "original_limits", "both_RHS_starts", "original_failed_states_unchanged",
            "target_construction"}
    require(type(value) is dict and set(value) == keys, "closed reference request")
    require(value["schema"] == "r200_regional_reference_request_v2", "request schema")
    require(value["case"] in CASES, "predetermined LT/NO4 case only")
    for key, expected in CASES[value["case"]].items():
        exact(value[key], expected, key)
    exact(value["precision_schedule"], PRECISIONS, "precision schedule")
    exact(value["prior"], PRIOR, "prior")
    exact(value["original_limits"], LIMITS, "original limits")
    exact(value["optimizer_updates"], 0, "zero optimizer updates")
    exact(value["both_RHS_starts"], True, "both RHS starts required")
    exact(value["original_failed_states_unchanged"], True, "original state unchanged")
    require(value["protocol_sha256"] == PROTOCOL_SHA256, "exact original protocol")
    require(value["units"] == "original_design_and_response", "original units")
    exact(value["binary_layout"], {"dtype": "IEEE754_binary64", "endian": "little",
                                   "precision_matrix_order": "column_major",
                                   "candidate_covariance_order": "column_major",
                                   "design_matrix_order": "row_major"}, "per-input binary layout")
    require(value["objective_mode"] in {"GAUSSIAN_ONLY", "EXPLICIT_IMPORTED_FULL_FACTORS"},
            "closed objective mode")
    names = value["input_names"]
    wanted = REQUIRED_INPUTS | (OBJECTIVE_INPUTS if value["objective_mode"] ==
                                "EXPLICIT_IMPORTED_FULL_FACTORS" else set())
    require(type(names) is dict and set(names) == wanted, "exact input alias set")
    require(all(type(v) is str and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,63}", v)
                for v in names.values()), "bounded input aliases")
    require(len(set(names.values())) == len(names), "one-to-one input names")
    construction = value["target_construction"]
    require(type(construction) is dict and set(construction) ==
            {"arithmetic", "precision_rhs_identity", "source_recipe_sha256",
             "independent_error_bound_earned"}, "closed target construction")
    require(construction["arithmetic"] == "EXACT_EXISTING_OR_OWNED_RECONSTRUCTED_BINARY64",
            "higherprecision X/W construction is a separate question")
    require(type(construction["precision_rhs_identity"]) is dict and
            set(construction["precision_rhs_identity"]) == {"precision_sha256", "rhs_sha256"},
            "separate P/RHS byte identities")
    for digest in [construction["source_recipe_sha256"],
                   *construction["precision_rhs_identity"].values()]:
        require(type(digest) is str and re.fullmatch("[0-9a-f]{64}", digest),
                "complete construction source/hash identity")
    # This source has no independently established target-construction bound.
    # A descriptor must not mint one, even if Gaussian component bounds are earned.
    exact(construction["independent_error_bound_earned"], False,
          "target construction bound remains held")
    return {"status": "PASS_REFERENCE_METADATA_NOT_EXECUTION_OR_ACCEPTANCE",
            "case": value["case"], "runtime_admitted": False,
            "all_seven_measure_acceptance": False,
            "numerical_execution_requires_fresh_owned_boundary": True}
