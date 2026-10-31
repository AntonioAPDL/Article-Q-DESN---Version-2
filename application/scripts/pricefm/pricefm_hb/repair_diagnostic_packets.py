"""Compile immutable mechanism-specific diagnostic specifications, not grants."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import time

from .local_readiness import ReadinessError, pin, read, require, save

LIMITS = {"beta_posterior_sd_rms": 1e-4, "covariance_whitened_rms": 1e-4,
          "elbo_relative": 1e-8, "predictor_rms": 1e-6, "rhs_joint_log_rates": 1e-6,
          "rhs_start_log_precision": 1e-6, "sigma_relative": 1e-6}
SCHEMA = "r178_mechanism_diagnostic_request_v1"


def validate(request):
    require(request.get("schema") == SCHEMA and request.get("purpose") == "MECHANISM_PREPARATION_ONLY", "diagnostic preparation purpose required")
    require(request.get("caps") == {"Normal":2000,"AL":300} and request.get("limits") == LIMITS,
            "unchanged original optimizer caps and all seven limits required")
    require(request.get("both_RHS_starts") is True and request.get("production_acceptance") is False
            and request.get("posterior_fits") == 0 and request.get("old_balance_reused") is False,
            "both starts, no fits/acceptance and no historical balance required")
    require(set(request.get("evidence",{})) == {"LT_scalar_analysis","LT_findings","NO4_saved_diagnosis"}, "exact mechanism evidence surface required")


def validate_original_evidence(lt, no4):
    require(lt.get("schema") == "r154_LT_fixed_state_scalar_analysis_v1" and lt.get("target") == "LT_fold1_al0.90",
            "original exact LT scalar target required")
    gates = lt.get("gates", [])
    require(len(gates) == 7 and {g.get("measure"):g.get("limit") for g in gates} == LIMITS,
            "complete original LT independent limits required")
    require(sum(g.get("component_gate_pass") is False for g in gates) == 1
            and next(g for g in gates if g["measure"] == "elbo_relative")["component_gate_pass"] is False,
            "this mechanism packet describes the original objective-only LT failure")
    training = no4.get("FR_SI_NO4_prior_training_diagnosis", {})
    require(training.get("NO4_failed_targets") == 8 and training.get("NO4_AL_iterations") == [300]
            and training.get("NO4_failure_gate_counts") == {"beta_posterior_sd_rms":8,"covariance_whitened_rms":6,"elbo_relative":4,"predictor_rms":6,"sigma_relative":2}
            and training.get("NO4_paired_tau_gate_sets_identical") is True
            and training.get("NO4_RHS_precision_exclusions_separate") == 144,
            "saved exact NO4 failure classification differs")
    return training


def compile_packets(request, *, now):
    validate(request)
    # Verify every original source/evidence byte without evaluating its target.
    evidence = request["evidence"]
    lt = read(evidence["LT_scalar_analysis"])
    from .local_readiness import verify
    verify(evidence["LT_findings"])
    no4 = read(evidence["NO4_saved_diagnosis"])
    training = validate_original_evidence(lt,no4)
    common = {"schema":"r178_mechanism_packet_v1", "created_epoch":now,
              "source":pin(__file__),"evidence":evidence,"caps":request["caps"],"independent_limits":LIMITS,
              "both_RHS_starts":True,"posterior_fits":0,"scientific_arrays_evaluated":0,
              "production_acceptance":False,"execution_authority":False,"old_balance_reused":False,
              "original_failed_records_and_thresholds_unchanged":True}
    lt_packet = dict(common, region="LT", status="PREPARED_REFERENCE_AND_TARGET_REPRESENTATION_GATES_UNADMITTED",
        original_target="LT_fold1_al0.90", representation_decision={
          "first_question":"Accuracy of moments for the exact stored/reconstructed binary64 precision and RHS, not an implicit higher-precision reconstruction of X/W",
          "source_equivalent_reconstruction_not_original_intermediates":True,
          "full_target_construction_question_separate":True,
          "required_exact_inputs":["source-equivalent fixed state and its source pins","original-unit beta/covariance scaling","original RHS prior semantics","current and next objective terms","exact binary64 P and RHS hashes written only by an admitted numerical child"]},
        original_failed_objective={"raw_increment":lt["objective"]["original_gap"],"raw_threshold":lt["objective"]["original_raw_gap_threshold"],
                                   "raw_excess":lt["objective"]["original_excess_gap"],"half_order_increment":lt["objective"]["reference_gap"],
                                   "relative_gate_ratio":lt["objective"]["original_ratio_to_gate"],"objective_only_rewrite_remains_failed":True},
        reference_precondition={
          "proposal":"Independently reviewed high-precision Cholesky/solve and covariance reference for the same rounded P, with increasing precision/residual stability checks",
          "candidate_implementation":"Boost.Multiprecision cpp_dec_float_100 via existing BH headers; header availability is not a built or validated runtime",
          "full_covariance_required_for_full_gate_claim":True,
          "probe_only_reference_cannot_claim_full_covariance_gate":True,
          "before_any_actual_target":["Pin complete compiled reference and dependencies under the applicable numerical guardian","Benchmark synthetic p8/p16/p32 against an independently known reference and validate the intended norm/units","Measure total startup/build/reference/finalization cost and establish a finite whole-attempt bound","Prove R runtime/source/full-state parity and original-unit objective/prior consistency"]},
        comparison=["All seven unchanged independent measurements on the same fixed state","Both original and half-order objective formulations sharing the exact original RHS prior","Posterior-SD and covariance-whitened errors in their own original norms","Predictor error and componentwise backward error kept distinct from forward covariance accuracy"],
        stop_criteria=["Stop if reference source/runtime/units/prior or whole cost is unproved","Stop if a rounded-P reference is being used to claim full X/W target-construction accuracy","Stop if the error budget or measured correction cannot explain the raw objective excess","Do not run another deterministic AL300/AL600 attempt or publish a certificate overlay from this diagnostic"],
        conditional_fallback="Frozen training-only rank4, requiring its complete quantile/fold confirmation; no bad-fold replacement")
    no4_packet = dict(common, region="NO_4", status="PREPARED_SAVED_FAILURE_CLASSIFICATION_UNADMITTED",
        required_failure_count=training["NO4_failed_targets"], failure_pattern=training["NO4_failure_gate_counts"],
        mechanism_questions=["Does Gaussian posterior/covariance construction explain the shared SD/covariance/predictor gate pattern?","Can a source-equivalent fixed-state independent reference bound the failing normalized errors without changing target, priors or initializer?"],
        controls={"paired_tau_failed_gate_sets_identical":True,"maximum_recorded_gate_ratio_change":training["NO4_max_gate_ratio_change"],"RHS_precision_exclusions_separate":144,"RHS_exclusions_are_owed_new_runs":False},
        required_before_numerical_target=["Select one predeclared original required target based on saved numerical mechanism evidence, not official-test performance","Recover its full target/initializer/source/prior/scaler binding","Use an accepted numerical host and a reviewed independent reference with full cost/stop proof","Compare the unchanged normalized gates and both RHS starts; no acceptance override"],
        stop_criteria=["Stop if no target-preserving mechanism explains the repeated gate pattern","Stop a tau/RHS-only replay unsupported by the saved comparison","Do not automatically replay all eight failures or the144 precision exclusions","A diagnostic cannot release the38 dependent stage units by itself"])
    return {"LT":lt_packet,"NO_4":no4_packet}


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--request",required=True);p.add_argument("--request-sha256",required=True);p.add_argument("--output",required=True)
    args=p.parse_args(argv)
    resource.setrlimit(resource.RLIMIT_CPU,(10,10));signal.alarm(45)
    require(os.sched_getaffinity(0)=={31},"metadata CPU31 required")
    request_pin={"path":args.request,"sha256":args.request_sha256};request=read(request_pin)
    scope=read(request["scope"])
    require(scope["issued_epoch"]<=time.time()<scope["expires_epoch"],"fresh preparation scope required")
    out=Path(args.output)
    require(out.is_absolute() and not out.exists() and out.parent.is_dir(),"new exact output directory required")
    packets=compile_packets(request,now=time.time());out.mkdir(mode=0o700)
    pins={region:save(out/(region+"_DIAGNOSTIC_PACKET.json"),value) for region,value in packets.items()}
    save(out/"MANIFEST.json",{"status":"PREPARED_MECHANISM_PACKETS_NO_NUMERICAL_OR_FIT_AUTHORITY","request":request_pin,"scope":request["scope"],"source":pin(__file__),"packets":pins,"numerical_calls":0})
    print(json.dumps(pins,sort_keys=True))


if __name__=="__main__":
    main()
