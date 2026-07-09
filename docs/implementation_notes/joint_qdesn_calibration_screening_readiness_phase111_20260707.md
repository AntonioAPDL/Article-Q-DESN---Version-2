# Joint QDESN Phase 111 Calibration-Screening Readiness

This note documents the readiness layer added after the first joint QDESN VB screening and selected-specification freeze. The goal is to prepare the next full calibration screening in a reproducible way before launching another expensive campaign.

## Motivation

The Phase 106/107 evidence selected `rhs_tau0_0p5_alpha0p5` as a stable VB specification, but it also showed that the exQDESN variants remain less well calibrated than the simpler QDESN variants. The main empirical pattern is a compressed exAL quantile fan: the exQDESN models have low raw crossing rates, but the fitted extreme quantiles are too close together, which leads to weaker truth-distance and interval-coverage behavior.

Phase 111 therefore does not promote a final article claim. It audits the current evidence and writes an executable next-screening registry that targets the highest-priority levers.

## Implemented Controls

The validation and screening wrappers now support two additional reproducible controls while preserving previous defaults:

- `alpha_prior_sd` is scalar in the Phase 112 mixed joint/independent screening registry. This keeps joint and independent single-tau comparators under the same launch contract.
- `gamma_init_policy` may be `default`, `zero`, `half_default`, or `quarter_default`. This exposes conservative exAL initialization diagnostics without changing the update equations.

The default remains `gamma_init_policy = default`, so existing artifacts and registries keep the same interpretation.

## Phase 111 Artifacts

The script

```bash
Rscript application/scripts/111_audit_joint_qdesn_calibration_screening_readiness.R
```

writes the default artifact directory

```text
application/cache/joint_qdesn_calibration_screening_readiness_phase111_20260707
```

with:

- `model_calibration_diagnosis.csv`
- `scenario_gap_diagnosis.csv`
- `tau_gap_diagnosis.csv`
- `coverage_width_diagnosis.csv`
- `convergence_crossing_diagnosis.csv`
- `candidate_history_diagnosis.csv`
- `control_feasibility_audit.csv`
- `recommended_screening_registry.csv`
- `deferred_control_extensions.csv`
- `implementation_plan.csv`
- `phase112_launch_command.csv`
- `source_manifest_verification.csv`
- `provenance.csv`
- `artifact_manifest.csv`
- `README.md`

All outputs are CSV/README based and hash-manifested.

## Recommended Next Screening

The generated Phase 112 registry keeps the Phase 107 selected candidate as a no-rerun reference and adds article-scale candidates for:

- wider scalar alpha priors;
- scalar alpha-prior width probes;
- zero and damped exAL gamma initialization;
- moderate RHS shrinkage alternatives;
- finite `zeta2`;
- a higher VB/RHS inner-loop budget.

The generated launch command is recorded in `phase112_launch_command.csv`. This is intended to be a full screening launch, not a smoke pilot.

## Deferred Extensions

The audit explicitly defers tail-specific alpha-prior vectors, gamma damping, gamma-shape priors, and model-specific candidate controls. These changes would alter the optimizer or mixed-comparator launch contract and should be considered only if Phase 112 shows that simpler derivation-compatible scalar controls do not resolve exQDESN tail compression.

## Gates

The next full screening should retain conservative gates:

- fail for missing manifests, nonfinite fit/forecast scores, contract quantile crossings, or worker failures;
- review for raw crossings before monotone projection, high max-iteration rates, large monotone adjustments, or exQDESN undercoverage;
- pass only when the implementation gates pass and fit/forecast calibration is competitive across scenarios and tau levels.

## Next Step

Run the generated Phase 112 command, audit the results with the existing screening audit, and freeze a VB specification only if both QDESN and exQDESN behavior are acceptable. VB-initialized MCMC should remain deferred until that VB specification is stable.
