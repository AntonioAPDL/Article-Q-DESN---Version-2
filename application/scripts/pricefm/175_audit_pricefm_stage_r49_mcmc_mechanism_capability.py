#!/usr/bin/env python3
"""Audit MCMC capability for frozen PriceFM R46 candidates without launching."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, write_json

ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
EXDQLM_REPO = Path("/data/jaguir26/local/src/exdqlm__wt__qdesn_0p4p0_integration")
R46 = ARTIFACT_REPO / "application/data_local/pricefm/authoritative/pricefm_stage_r46_full_quantile_confirmation_closeout_20260808"
RUNNER = Path(__file__).with_name("08_run_desn_model_smoke.R")
OUTPUT = ARTIFACT_REPO / "application/data_local/pricefm/authoritative/pricefm_stage_r49_mcmc_mechanism_capability_audit_20260808"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r46-dir", type=Path, default=R46)
    p.add_argument("--runner", type=Path, default=RUNNER)
    p.add_argument("--exdqlm-repo", type=Path, default=EXDQLM_REPO)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def contains(path, *needles):
    text = Path(path).read_text()
    return all(needle in text for needle in needles)


def run(args):
    out = args.output_dir.resolve()
    if out.exists() and any(out.iterdir()) and not args.force:
        raise FileExistsError(f"Output exists: {out}")
    out.mkdir(parents=True, exist_ok=True)

    queue_path = args.stage_r46_dir / "pricefm_stage_r46_frozen_test_audit_queue.csv"
    queue = pd.read_csv(queue_path)
    qdesn = args.exdqlm_repo / "R/qdesn_mcmc.R"
    exal = args.exdqlm_repo / "R/exal_mcmc_fit.R"
    required = [queue_path, args.runner, qdesn, exal]
    for path in required:
        if not path.exists():
            raise FileNotFoundError(path)

    capabilities = pd.DataFrame([
        {"capability": "qdesn_mcmc_dispatch", "supported": contains(qdesn, "qdesn_fit_mcmc", "exal_mcmc_fit("), "evidence": str(qdesn)},
        {"capability": "rhs_ns_prior", "supported": contains(qdesn, '"rhs_ns"', "beta_prior_type"), "evidence": str(qdesn)},
        {"capability": "internal_vb_warm_start", "supported": contains(exal, "if (init_from_vb)", "exal_ldvb_fit("), "evidence": str(exal)},
        {"capability": "explicit_initial_state", "supported": contains(qdesn, 'get_exact(mcmc_args, "init", list())'), "evidence": str(qdesn)},
        {"capability": "posterior_prediction", "supported": contains(exal, "exal_mcmc_posterior_predict", "exal_mcmc_posterior_draws"), "evidence": str(exal)},
        {"capability": "pricefm_shared_mcmc", "supported": contains(args.runner, "qdesn_fit_mcmc"), "evidence": str(args.runner)},
        {"capability": "pricefm_horizon_block_mcmc", "supported": contains(args.runner, "exal_mcmc_fit", "separate_horizon_block"), "evidence": str(args.runner)},
        {"capability": "pricefm_frozen_mcmc_blend", "supported": contains(args.runner, "mcmc", "partial_pool", "posterior"), "evidence": str(args.runner)},
    ])

    cases = []
    for row in queue.itertuples(index=False):
        weights = {block: float(getattr(row, f"weight_{block.replace('-', '_')}")) for block in ["1-24", "25-48", "49-72", "73-96"]}
        active = [block for block, weight in weights.items() if weight > 0]
        n_components = 1 + len(active)
        cases.append({
            "region": row.region,
            "fold": int(row.fold),
            "active_horizon_blocks": ";".join(active),
            "frozen_weights": json.dumps(weights, sort_keys=True),
            "quantiles": 7,
            "component_types": n_components,
            "tau_component_fit_targets": 7 * n_components,
            "selection_status": "conditional_on_r48_dual_reference_gate",
            "mcmc_launch_authorized": False,
        })
    case_frame = pd.DataFrame(cases)

    gaps = pd.DataFrame([
        {"gap": "runner_backend", "severity": "blocking", "finding": "PriceFM runner calls exal_ldvb_fit only; no MCMC branch exists.", "required_action": "Implement and test a dedicated frozen-confirmation runner after R48 promotes a case."},
        {"gap": "component_equivalence", "severity": "blocking", "finding": "No runner fits both shared and selected horizon-block RHS_NS MCMC components on the frozen R46 contract.", "required_action": "Rebuild the identical design and fit one shared plus each nonzero-weight block component per tau."},
        {"gap": "warm_start_provenance", "severity": "important", "finding": "init_from_vb refits an internal VB warm start; cleaned R45 fit objects cannot be reused directly.", "required_action": "Freeze seeds and VB warm-start controls, or materialize an explicit validated init-state contract."},
        {"gap": "blend_semantics", "severity": "important", "finding": "R46 is a convex blend of quantile predictions, not a posterior mixture distribution.", "required_action": "Blend component quantile predictions with frozen weights; do not claim posterior-mixture inference."},
        {"gap": "chain_diagnostics", "severity": "blocking", "finding": "PriceFM has no chain-level convergence, reproducibility, or hash-manifest gate for this mechanism.", "required_action": "Define chain seeds, R-hat/ESS/divergence-equivalent gates, prediction replay, and source hashes before launch."},
    ])

    gates = pd.DataFrame([
        {"gate": "r46_candidates_present", "passed": len(case_frame) > 0, "observed": len(case_frame)},
        {"gate": "exdqlm_core_capable", "passed": bool(capabilities.iloc[:5].supported.all()), "observed": int(capabilities.iloc[:5].supported.sum())},
        {"gate": "pricefm_runner_capable", "passed": bool(capabilities.iloc[5:].supported.all()), "observed": int(capabilities.iloc[5:].supported.sum())},
        {"gate": "r48_promotion_known", "passed": False, "observed": "R47 still running"},
        {"gate": "mcmc_launch_authorized", "passed": False, "observed": "blocked"},
    ])
    decision = "blocked_pending_r48_and_pricefm_mcmc_runner"

    capabilities.to_csv(out / "pricefm_stage_r49_capability_matrix.csv", index=False)
    case_frame.to_csv(out / "pricefm_stage_r49_conditional_component_plan.csv", index=False)
    gaps.to_csv(out / "pricefm_stage_r49_runner_gap_audit.csv", index=False)
    gates.to_csv(out / "pricefm_stage_r49_decision_gates.csv", index=False)
    pd.DataFrame([{"path": str(Path(p).resolve()), "sha256": sha256(p), "bytes": Path(p).stat().st_size} for p in required]).to_csv(out / "source_manifest.csv", index=False)
    summary = {
        "status": "completed_read_only_capability_audit",
        "decision": decision,
        "conditional_cases": len(case_frame),
        "conditional_tau_component_fit_targets": int(case_frame.tau_component_fit_targets.sum()),
        "exdqlm_core_capable": bool(capabilities.iloc[:5].supported.all()),
        "pricefm_runner_capable": bool(capabilities.iloc[5:].supported.all()),
        "launch_yaml_written": False,
        "mcmc_launch_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(out / "summary.json", summary)
    (out / "pricefm_stage_r49_mcmc_mechanism_capability_report.md").write_text(
        "# PriceFM Stage-R49 MCMC mechanism-capability audit\n\n"
        "The exdqlm core can fit RHS_NS Q-DESN readouts with MCMC, initialize through an internal VB refit or explicit state, and produce posterior predictions. The current PriceFM runner cannot reproduce the frozen R46 shared-plus-horizon-block mechanism under MCMC.\n\n"
        "R48 remains the first gate. If no case beats both authoritative Q-DESN and cached PriceFM on frozen test, MCMC stops. If a case passes, a dedicated runner must fit the shared component and only nonzero-weight horizon blocks at all seven quantiles, then blend quantile predictions using the frozen R46 weights. This is prediction pooling, not a posterior-mixture claim.\n\n"
        "No launch YAML, model fitting, registry mutation, or article mutation is authorized by this audit.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
