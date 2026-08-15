# Joint QDESN Phase 113 Top-Candidate Verification

Date: 2026-07-08

## Purpose

Phase 112 completed the full VB specification screen for the joint QDESN simulation study. The run was successful at the implementation level: manifests verified, scenario worker failures were absent, and contract forecast quantiles were noncrossing. However, every candidate remained in `review` because raw monotone adjustments and VB max-iteration pressure still need interpretation before article assets or MCMC references are promoted.

Phase 113 is therefore a focused top-candidate verification stage. It is not another broad screen, and it is not yet an MCMC launch. Its purpose is to verify the best Phase 112 accuracy-stability tradeoff under a small number of scientifically motivated hybrid specifications.

## Phase 112 Diagnosis

The Phase 112 scorecard identified two complementary candidates:

- `inner10_iter1440_alpha0p5_tau0_0p5`: best stability-oriented candidate. It had the best aggregate screening score, the lowest raw forecast crossing count, and the lowest max-iteration pressure among the main candidates.
- `zeta2_16_alpha0p5_tau0_0p5`: best accuracy-oriented candidate. It had the best mean forecast truth distance and the strongest max-scenario forecast accuracy, but slightly more raw crossing and convergence review pressure.

The main remaining model-level concern is the exQDESN fan geometry. Joint exQDESN has excellent raw noncrossing behavior, but its forecast truth distances and coverage behavior remain worse than the simpler AL-based QDESN in several tail regions. This argues for one more VB verification layer before any MCMC promotion.

## Implemented Artifacts

The readiness runner is:

```bash
Rscript application/scripts/112_prepare_joint_qdesn_phase113_top_candidate_verification.R
```

Default readiness output:

```text
application/cache/joint_qdesn_phase113_top_candidate_verification_20260708
```

Default Phase 113 screening output:

```text
application/cache/joint_qdesn_vb_spec_screening_phase113_20260708
```

The readiness runner writes:

- `phase113_run_config.csv`
- `source_manifest_verification.csv`
- `phase112_scorecard_audit.csv`
- `phase112_model_tradeoff_audit.csv`
- `phase112_exal_gap_audit.csv`
- `phase113_candidate_selection_rationale.csv`
- `phase113_recommended_registry.csv`
- `phase113_implementation_plan.csv`
- `phase113_launch_command.csv`
- `provenance.csv`
- `artifact_manifest.csv`
- `README.md`

## Recommended Phase 113 Registry

The registry contains four rows when the full Phase 112 artifact is available:

1. Frozen reference: `inner10_iter1440_alpha0p5_tau0_0p5`.
2. Frozen reference: `zeta2_16_alpha0p5_tau0_0p5`.
3. Primary hybrid: `zeta2_16_inner10_iter1440_alpha0p5_tau0_0p5`.
4. Gamma-initialization sensitivity hybrid: `zeta2_16_inner10_gamma_zero_alpha0p5_tau0_0p5`.

The primary hybrid combines the best Phase 112 accuracy lever, finite `zeta2 = 16`, with the best stability lever, `rhs_vb_inner = 10` and the larger VB iteration grid `1440,1920`. The second hybrid keeps those controls and sets the exAL gamma initialization to zero to test whether the exAL tail behavior is sensitive to the starting geometry.

## Decision Rules

Phase 113 should promote a VB candidate only if:

- all manifests verify;
- fit and forecast worker failures are absent;
- final contract quantiles remain noncrossing;
- fit and forecast truth distances are competitive with the Phase 112 references;
- raw monotone adjustments are review-level rather than dominant;
- VB max-iteration pressure is reduced or clearly bounded;
- the candidate improves or preserves the AL QDESN benchmark while not worsening exQDESN behavior enough to undermine the joint comparison.

MCMC remains deferred until a single VB specification satisfies these conditions. This keeps the expensive MCMC reference layer anchored to a stable, reproducible VB target rather than to a moving screening grid.

## Recommended Launch

After regenerating the readiness artifact, run the command stored in:

```text
application/cache/joint_qdesn_phase113_top_candidate_verification_20260708/phase113_launch_command.csv
```

The command uses the existing Phase 106 screening runner with `--reuse-completed true`, so the two Phase 112 references are reused and only the two hybrid candidates are newly fit and forecast-scored.

## Next Step

Run the Phase 113 verification campaign in the background. Once it completes, audit the output directory with the existing screening summaries. If a single VB specification is stable and competitive, freeze the article validation assets and then launch VB-initialized MCMC references.
