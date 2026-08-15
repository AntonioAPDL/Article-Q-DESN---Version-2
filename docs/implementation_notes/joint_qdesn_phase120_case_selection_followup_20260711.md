# Joint QDESN Phase 120 Case-Selection Follow-Up

Date: 2026-07-11

## Purpose

Phase 120 is the targeted follow-up after the Phase 119 high-priority
case-specific VB screens.  Phase 119 already ran the high-priority AL and exAL
case grids.  Its artifacts are complete, hash-manifested, and have zero
reported-grid crossings.  The remaining issues are localized:

- a small number of AL winners still have raw pre-rearrangement crossings;
- one exAL winner is review-level because VB reached the iteration budget;
- the moderate/context backlog does not directly address those specific
unresolved winning cases.

Therefore, the next statistically and computationally efficient move is not a
blanket launch of all remaining Phase 119 moderate/context rows.  It is a
targeted per-case follow-up around the unresolved winners.

## Inputs

Default Phase 119 high-priority inputs:

```text
application/cache/joint_qdesn_vb_case_specific_screening_phase119_20260709/al_high_priority
application/cache/joint_qdesn_vb_case_specific_screening_phase119_20260709/exal_high_priority
```

Required source files in each shard:

- `candidate_registry.csv`;
- `screening_health_summary.csv`;
- `fit_model_metric_summary.csv`;
- `forecast_model_metric_summary.csv`;
- `candidate_manifest_verification.csv`;
- `artifact_manifest.csv`.

The Phase 120 preparation layer verifies both top-level artifact manifests and
nested candidate manifests before selecting any winners.

## Implemented Files

Phase 120 adds:

- `application/R/joint_qdesn_calibration_screening.R`;
- `application/scripts/122_prepare_joint_qdesn_phase120_case_selection_followup.R`;
- `application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh`;
- `application/tests/test_joint_qdesn_phase120_case_selection_followup.R`.

The generic `123` launcher is not Phase-119-specific.  It can launch any
screening registry accepted by
`application/scripts/106_run_joint_qdesn_vb_spec_screening.R`.

## Artifact

Default preparation artifact:

```text
application/cache/joint_qdesn_phase120_case_selection_followup_20260711
```

It writes:

- `phase120_run_config.csv`;
- `phase119_source_manifest_verification.csv`;
- `phase119_source_health_summary.csv`;
- `phase119_candidate_score_audit.csv`;
- `phase119_case_winner_audit.csv`;
- `phase120_target_case_audit.csv`;
- `phase120_targeted_followup_registry.csv`;
- `phase120_selection_policy.csv`;
- `phase120_next_action_plan.csv`;
- `phase120_launch_commands.csv`;
- `provenance.csv`;
- `artifact_manifest.csv`;
- `README.md`.

## Selection Logic

Selection is case-local.  A case is a scenario/model pair.  Phase 120 chooses
the best Phase 119 high-priority candidate within each case using forecast
oracle quantile MAE as the primary criterion, with fit oracle quantile MAE, raw
crossings, convergence flags, check loss, grid CRPS, and runtime as diagnostics
and tie-breakers.

Follow-up rows are created only when the selected case winner is still in
review due to:

- raw forecast quantile crossings before the monotone contract; or
- VB max-iteration/convergence review.

Pass cases are retained as provisional VB winners but are not relaunched.

## Targeted Candidate Design

For AL raw-crossing cases, the new rows test stronger RHS coupling/sparsity and
larger VB inner/outer budgets:

- smaller `tau0`;
- smaller scalar `alpha_prior_sd`;
- finite and sometimes smaller `zeta2`;
- more RHS coordinate passes;
- higher adaptive VB iteration ceilings.

For the exAL convergence-review case, the new rows preserve the best Phase 119
tail-fan geometry while increasing the VB inner/outer budgets and testing a
small number of nearby fan-width controls.

This is intentionally narrower than a broad screening campaign.  It tests the
failure modes observed in the completed high-priority evidence.

## Gates

Hard fail:

- missing or unverifiable source manifests;
- worker failures;
- nonfinite fit or forecast metrics;
- reported-grid/contract quantile crossings.

Review:

- raw pre-rearrangement crossings;
- VB max-iteration flags;
- large monotone adjustments;
- material deterioration in check loss, grid CRPS, hit-rate error, or coverage
  error despite better oracle quantile MAE.

Pass:

- complete source artifacts;
- finite metrics;
- zero contract crossings;
- no worker failures;
- stable case-local winner ready for later VB freeze and MCMC initialization.

## Commands

Prepare the Phase 120 artifact:

```bash
Rscript application/scripts/122_prepare_joint_qdesn_phase120_case_selection_followup.R
```

Launch the targeted follow-up rows:

```bash
bash application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh \
  --registry application/cache/joint_qdesn_phase120_case_selection_followup_20260711/phase120_targeted_followup_registry.csv \
  --canonical-output-dir application/cache/joint_qdesn_vb_case_specific_screening_phase120_20260711/targeted_followup \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --workers 10 \
  --n-cores-per-worker 1 \
  --run-id phase120_targeted_20260711
```

After all worker sessions finish:

```bash
Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R \
  --registry application/cache/joint_qdesn_phase120_case_selection_followup_20260711/phase120_targeted_followup_registry.csv \
  --output-dir application/cache/joint_qdesn_vb_case_specific_screening_phase120_20260711/targeted_followup \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --n-cores 1 \
  --reuse-completed true \
  --audit-only true
```

## Next Step

After Phase 120 completes, compare the targeted follow-up rows against the
Phase 119 winners.  Then freeze one VB/VB-LD winner per article-facing
scenario/model case.  Only after that freeze should the final MCMC confirmation
layer be launched for the article-facing rows:

- Joint QDESN RHS under AL;
- Independent QDESN RHS under AL;
- Joint exQDESN RHS under exAL;
- Independent exQDESN RHS under exAL.

VB/VB-LD remains calibration and initialization evidence.  MCMC remains the
article-facing confirmation layer.
