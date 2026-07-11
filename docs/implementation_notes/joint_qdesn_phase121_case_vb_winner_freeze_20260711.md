# Joint QDESN Phase 121 Case-Specific VB Winner Freeze

## Purpose

Phase 121 freezes one VB/VB-LD winner for each high-priority
scenario--model case after the Phase 119 case-specific screens and the Phase
120 targeted follow-up.  The freeze is a reproducible initialization contract
for the next MCMC confirmation stage.  It is not final article evidence.

The final article direction remains:

- VB/VB-LD is used for calibration, screening, and MCMC initialization.
- MCMC is the final article-facing confirmation layer.
- Claims remain quantile-grid claims: oracle quantile MAE/RMSE, check loss,
  grid CRPS, hit-rate/coverage diagnostics, and raw/contract crossing
  diagnostics.

## Audit Diagnosis

The completed Phase 120 targeted follow-up changed the decision problem:

1. The joint exQDESN RHS asymmetric-Laplace-tail convergence issue was solved
   by stronger inner-loop/iteration controls.
2. The remaining AL raw crossings were not removed by stronger sparsity,
   tighter intercept priors, or higher iteration budgets.
3. Contract forecast quantiles remain noncrossing after the declared monotone
   grid policy.
4. Independent single-quantile AL rows continue to show raw crossings because
   they do not share a joint noncrossing readout.
5. The existing Phase 108 MCMC runner is only a joint-AL reference runner and
   does not support all four requested final article rows.

Therefore the optimal next step is not another broad VB screen.  It is to
freeze stable per-case VB winners and then implement a Phase 122 MCMC
confirmation runner that supports the requested final rows.

## Selection Rule

Phase 121 combines candidates from:

```text
application/cache/joint_qdesn_vb_case_specific_screening_phase119_20260709/al_high_priority
application/cache/joint_qdesn_vb_case_specific_screening_phase119_20260709/exal_high_priority
application/cache/joint_qdesn_vb_case_specific_screening_phase120_20260711/targeted_followup
```

For each `case_id`, candidates first pass hard implementation gates:

- source manifests verify;
- no worker failures;
- finite fit and forecast summaries;
- no fit or forecast contract crossings.

Among usable candidates, the primary score is forecast oracle quantile MAE.
However, if candidates are within a small tolerance of the best MAE, Phase 121
prefers stability:

```text
abs tolerance = 5e-4
relative tolerance = 0.5%
effective tolerance = max(abs tolerance, relative tolerance * best MAE)
```

Within this tolerance, selection prefers:

1. no fit/forecast max-iteration flags;
2. fewer raw crossings;
3. smaller monotone adjustment;
4. lower check loss/grid CRPS;
5. lower fit MAE;
6. lower runtime.

This prevents tiny forecast-MAE gains from carrying avoidable convergence
review flags into the MCMC initialization layer.

## Generated Artifacts

The default artifact directory is:

```text
application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711
```

It contains:

- `phase121_run_config.csv`;
- `source_manifest_verification.csv`;
- `source_health_summary.csv`;
- `combined_candidate_audit.csv`;
- `case_winner_selection.csv`;
- `case_winner_controls.csv`;
- `case_winner_metric_summary.csv`;
- `case_winner_gate_audit.csv`;
- `mcmc_readiness_gap_audit.csv`;
- `mcmc_launch_plan.csv`;
- `next_action_plan.csv`;
- `provenance.csv`;
- `artifact_manifest.csv`;
- `README.md`.

## MCMC Readiness Gap

The user-requested final confirmation rows are:

- Joint QDESN RHS under AL;
- Independent QDESN RHS under AL;
- Joint exQDESN RHS under exAL;
- Independent exQDESN RHS under exAL.

The existing Phase 108 MCMC readiness layer is not sufficient for this final
evidence structure.  It supports a joint AL reference check, not a case-specific
MCMC confirmation across joint/independent AL and exAL rows.  Phase 121 records
this explicitly in `mcmc_readiness_gap_audit.csv` and leaves article promotion
blocked until Phase 122 is implemented and audited.

## Commands

Focused test:

```bash
Rscript application/tests/test_joint_qdesn_phase121_case_vb_winner_freeze.R
```

Generate the freeze artifact:

```bash
Rscript application/scripts/124_freeze_joint_qdesn_phase121_case_vb_winners.R
```

Suggested next implementation stage after Phase 121:

```bash
Rscript application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R \
  --phase121-dir application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --output-dir application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711 \
  --n-chains 2 \
  --mcmc-n-iter 1200 \
  --mcmc-burn 600 \
  --mcmc-thin 10 \
  --n-cores 12
```

That command is intentionally a Phase 122 target, not a Phase 121 command.  The
Phase 122 runner must first be implemented and tested.

## Gates

Hard fail:

- missing or failed source manifests;
- worker failures;
- nonfinite fit/forecast summaries;
- fit or forecast contract crossings;
- no usable candidate for a case.

Review:

- raw crossings before the monotone contract;
- nontrivial monotone adjustments;
- VB max-iteration flags;
- incomplete MCMC support for the final article rows.

Pass:

- complete source manifests;
- no worker failures;
- finite summaries;
- zero contract crossings;
- one usable winner per case.

## Next Step

Implement Phase 122: a case-specific MCMC confirmation runner that consumes the
Phase 121 winners, initializes from the selected VB/VB-LD controls, supports
the four final article model rows, preserves raw/contract quantile-grid
diagnostics, and writes reproducible CSV/provenance/SHA-256 artifacts.
