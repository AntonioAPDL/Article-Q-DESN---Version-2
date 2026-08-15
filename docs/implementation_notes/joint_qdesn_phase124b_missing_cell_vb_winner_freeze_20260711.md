# Joint QDESN Phase 124b Missing-Cell VB Winner Freeze

Date: 2026-07-11

## Purpose

Phase 124 completed the missing VB/VB-LD screens needed for a balanced joint
QDESN validation comparison.  The completed screen covers the 15 model-scenario
cells that were absent from the Phase 122 MCMC confirmation artifact.

Phase 124b freezes one VB/VB-LD winner for each of those 15 cells.  This is a
reproducible initialization contract for MCMC completion, not final
article-facing evidence.

The freeze deliberately writes the same core files used by the Phase 121 freeze:

- `case_winner_controls.csv`
- `case_winner_metric_summary.csv`
- `case_winner_gate_audit.csv`
- `artifact_manifest.csv`

That design lets the tested Phase 122 MCMC confirmation runner consume the
Phase 124b artifact unchanged.

## Audit Conclusion

The Phase 124 canonical audit is implementation-clean:

- all 96 candidate rows completed fit and forecast artifacts;
- all worker chunks ended with `EXIT_CODE=0`;
- top-level and nested manifests verify;
- no worker failures were reported;
- all contract quantile grids are noncrossing.

The remaining diagnostics are review-level rather than hard failures.  Review
flags are driven by raw pre-contract crossings and a few VB max-iteration flags.
Those diagnostics should remain visible in the article workflow, but they do not
block MCMC initialization because scoring uses the declared monotone quantile
contract.

## Selection Policy

Phase 124b reuses the Phase 121 local winner-selection policy:

1. Exclude hard implementation failures.
2. Select within each model-scenario cell, not globally.
3. Minimize forecast truth MAE.
4. Within a small tolerance of the best forecast truth MAE, prefer more stable
   candidates with fewer max-iteration flags and raw crossing diagnostics.
5. Preserve review labels for raw crossings, monotone adjustments, and
   max-iteration flags.

This is the correct policy for the balanced-completion stage because the article
goal is not a single specification that works everywhere.  The goal is a fair
per-case optimized comparison among Joint QDESN, Independent QDESN, Joint
exQDESN, and Independent exQDESN.

## Implemented Files

Helpers:

```text
application/R/joint_qdesn_phase124_balanced_completion.R
```

Script:

```text
application/scripts/128_freeze_joint_qdesn_phase124b_missing_cell_vb_winners.R
```

Test:

```text
application/tests/test_joint_qdesn_phase124b_missing_cell_vb_winner_freeze.R
```

Default output:

```text
application/cache/joint_qdesn_phase124b_missing_cell_vb_winner_freeze_20260711
```

## Generated Artifacts

The Phase 124b freeze writes:

- `phase124b_run_config.csv`
- `source_manifest_verification.csv`
- `source_health_summary.csv`
- `phase124_missing_cell_coverage.csv`
- `combined_candidate_audit.csv`
- `case_winner_selection.csv`
- `case_winner_controls.csv`
- `case_winner_metric_summary.csv`
- `case_winner_gate_audit.csv`
- `mcmc_completion_launch_plan.csv`
- `next_action_plan.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

## Phase 124c MCMC Completion

The next stage is a Phase 122-style MCMC confirmation run over only the 15
frozen missing-cell winners:

```bash
Rscript application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R \
  --phase121-dir application/cache/joint_qdesn_phase124b_missing_cell_vb_winner_freeze_20260711 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --output-dir application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711 \
  --n-chains 2 \
  --mcmc-n-iter 1200 \
  --mcmc-burn 600 \
  --mcmc-thin 10 \
  --n-cores 12
```

## Article Promotion Gate

The article should not be updated from Phase 124b alone.  Article promotion
requires:

1. Phase 124c MCMC completion over all 15 frozen missing cells.
2. No implementation failures, finite MCMC draws and scores, and zero contract
   crossings.
3. A merged balanced 32-cell artifact combining the existing Phase 122 rows and
   the new Phase 124c rows.
4. Hash-manifested tables and figures.
5. Manuscript wording that preserves the quantile-grid predictive contract and
   treats raw crossings as diagnostics rather than hidden failures.
