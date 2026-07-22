# Joint exQDESN Phase141 Gamma-Redesign Readiness

## Purpose

Phase141 formalizes the next step after the Phase140 fixed-gamma-zero recovery packet.  Phase140 showed that fixing the exAL shape parameter at the AL-like value recovered forecast performance across the five high-priority exAL cases, with zero contract crossings and no worker failures.  This is strong diagnostic evidence that the remaining exAL weakness is concentrated in the gamma layer rather than in the matched DESN/RHS controls.

The fixed-gamma-zero packet is **not** a final exAL article model.  It removes the additional exAL flexibility.  Its role is to justify a targeted gamma-kernel redesign screen before any article-facing exAL MCMC promotion.

## Main Diagnosis

The Phase140 recovery pattern is consistent across all priority cases:

- fixed gamma improved forecast MAE relative to the best prior gamma-sampled packet in every retained case;
- contract forecast quantiles remained monotone;
- sigma diagnostics were stable;
- the previous review gate was partly a fixed-parameter accounting issue, because gamma ESS/Rhat should not be interpreted as sampled-parameter diagnostics when gamma is fixed.

The largest remaining forecast MAE is still the `regime_shift` joint exQDESN case, so that scenario receives the highest priority in the next screen.

## Implemented Changes

Phase141 adds:

- `application/R/joint_exqdesn_phase141_gamma_redesign_readiness.R`;
- `application/scripts/150_prepare_joint_exqdesn_phase141_gamma_redesign_readiness.R`;
- `application/tests/test_joint_exqdesn_phase141_gamma_redesign_readiness.R`;
- manifest-backed Phase141 artifacts under `application/cache/joint_qdesn_phase141_exal_gamma_redesign_readiness_20260719`.

It also extends the Phase136 gamma-kernel registry so named width variants can be launched without ambiguous labels:

- `bounded_w0p5`, `bounded_w1`, `bounded_w2`;
- `logit_w0p5`, `logit_w1`, `logit_w2`;
- existing `bounded_w4`, `logit_w4`, and `fixed_zero` behavior is retained.

The runner now carries the per-variant width into metadata and gamma slice-width construction.

## Phase141 Artifacts

The readiness script writes:

- `run_config.csv`;
- `fixed_gamma_manifest_verification.csv`;
- `phase141_diagnostic_summary.csv`;
- `phase141_case_priority.csv`;
- `phase141_variant_catalog.csv`;
- `phase141_candidate_registry.csv`;
- `phase141_method_feasibility.csv`;
- `phase141_launch_plan.csv`;
- `phase141_decision_summary.csv`;
- `phase141_launch_commands.txt`;
- `provenance.csv`;
- `README.md`;
- `artifact_manifest.csv`.

## Prepared Launches

Phase141 prepares, but does not launch, two follow-up screens:

1. Primary narrow gamma geometry screen:
   - all Phase140 priority cases;
   - variants `bounded_w1` and `logit_w1`;
   - 8 chains per case/variant;
   - 12,000 iterations with 3,000 burn-in.

2. Focus width-sensitivity screen:
   - tier-1 cases only;
   - variants `bounded_w0p5`, `bounded_w2`, `logit_w0p5`, and `logit_w2`;
   - 8 chains per case/variant;
   - 12,000 iterations with 3,000 burn-in.

The primary screen should be run first.  The focus screen should follow only if the primary screen fails to approach the fixed-gamma-zero performance while retaining sampled-gamma flexibility.

## Gates

Hard fail:

- fixed-gamma source manifest failure;
- chain worker failures;
- incomplete requested chains;
- nonzero contract crossings.

Review:

- raw crossings before monotone contract projection;
- sigma diagnostics outside conservative thresholds;
- fixed gamma improves performance but does not itself constitute a final exAL model;
- remaining high forecast MAE in `regime_shift`.

Pass for readiness:

- source manifests verify;
- fixed-gamma packet has no implementation failures;
- contract qhat remains monotone;
- Phase141 writes complete manifest-backed artifacts and exact launch commands.

## Next Step

Run the Phase141 primary narrow gamma geometry screen.  If it recovers fixed-gamma-level performance while sampling gamma, compare it against Phase140 and then decide whether a final exAL MCMC article packet can be launched.  If it does not, implement a stronger gamma prior centered near the AL-like region rather than broad DESN/RHS rescreening.
