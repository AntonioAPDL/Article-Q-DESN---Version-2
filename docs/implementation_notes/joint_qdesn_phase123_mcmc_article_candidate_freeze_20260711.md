# Joint QDESN Phase 123 MCMC Article-Candidate Freeze

Date: 2026-07-11

## Purpose

Phase 123 audits the completed Phase 122 MCMC confirmation run and freezes an
article-candidate evidence packet for the joint multi-quantile QDESN validation
study.

This stage does not run VB, VB-LD, MCMC, fixture generation, or manuscript
edits. It consumes the frozen Phase 122 CSV artifacts and produces an
inspectable cache directory with SHA-256 hashes, pass/review/fail gates,
case-specific MCMC summaries, article-candidate tables, and a precise
integration recommendation.

## Inputs

Default Phase 122 source:

```text
application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711
```

The expected Phase 122 source contains:

- source manifest verification for Phase 121 and simulation fixtures;
- `mcmc_case_summary.csv`;
- `mcmc_case_assessment.csv`;
- fit and forecast truth/check/CRPS/hit/interval summaries;
- raw and contract crossing diagnostics;
- VB/MCMC and chain-to-pooled distance summaries;
- runtime and provenance tables;
- a top-level artifact manifest.

## What Phase 123 Freezes

Phase 123 freezes the following interpretation:

1. Phase 122 completed the MCMC confirmation for all frozen Phase 121
   case-specific winners.
2. The evidence is valid under the quantile-grid/readout predictive contract.
3. Reported/scored quantiles are the monotone contract grid.
4. Raw pre-rearrangement crossings remain diagnostic evidence and are not hidden.
5. The Phase 122 source is not a balanced four-model-by-scenario MCMC grid.

The last point is important. Phase 122 confirms the selected case-specific
winners, but it does not contain every scenario/model cell for:

- Joint QDESN RHS under AL;
- Independent QDESN RHS under AL;
- Joint exQDESN RHS under exAL;
- Independent exQDESN RHS under exAL.

Therefore, a main article table that compares these four model rows over a
common scenario suite requires either:

- a clearly labeled case-specific framing; or
- a Phase 124 completion run for the missing model-scenario cells.

## Gates

Hard-fail gates:

- missing or invalid Phase 122 artifact hashes;
- missing Phase 121 or fixture manifest verification;
- worker failures;
- nonfinite MCMC draw summaries;
- missing VB initialization;
- any contract-grid crossing;
- scalar predictive-density claims.

Review gates:

- raw pre-rearrangement crossings;
- large monotone adjustments;
- review-level VB/MCMC or chain distance diagnostics;
- incomplete balanced four-model-by-scenario MCMC coverage.

Pass gates:

- all source hashes verified;
- no worker failures;
- finite MCMC summaries;
- VB initialization used;
- scored contract quantile grids are noncrossing;
- claims remain scoped to quantile-grid validation.

## Generated Artifacts

Default output:

```text
application/cache/joint_qdesn_phase123_mcmc_article_candidate_freeze_20260711
```

Important files:

- `health_check_summary.csv`;
- `article_gate_summary.csv`;
- `model_confirmation_summary.csv`;
- `case_confirmation_summary.csv`;
- `article_scope_matrix.csv`;
- `article_scope_by_model.csv`;
- `article_scope_decision.csv`;
- `raw_crossing_diagnostic_summary.csv`;
- `vb_mcmc_delta_summary.csv`;
- `chain_stability_summary.csv`;
- `article_candidate_mcmc_model_table.csv`;
- `article_candidate_mcmc_model_table.tex`;
- `article_candidate_mcmc_case_table.csv`;
- `article_candidate_mcmc_case_table.tex`;
- `article_candidate_mcmc_gate_table.csv`;
- `article_candidate_mcmc_gate_table.tex`;
- `article_promotion_recommendation.csv`;
- `article_integration_plan.csv`;
- `artifact_manifest.csv`;
- `README.md`.

The table files are article-candidate assets in the cache directory. They are
not copied into `tables/` and are not included from `main.tex` by this stage.

## Commands

Focused test:

```bash
Rscript application/tests/test_joint_qdesn_phase123_mcmc_article_freeze.R
```

Real Phase 123 freeze:

```bash
Rscript application/scripts/126_freeze_joint_qdesn_phase123_mcmc_article_candidate.R \
  --phase122-dir application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711 \
  --output-dir application/cache/joint_qdesn_phase123_mcmc_article_candidate_freeze_20260711
```

## Interpretation for Manuscript Work

If Phase 123 hard gates pass but the scope gate remains review-level, the
recommended manuscript path is:

1. decide whether the joint validation section should show a case-specific MCMC
   confirmation table or a balanced four-row comparison table;
2. if case-specific, promote the Phase 123 article-candidate table with explicit
   wording that each row is averaged over its confirmed cases;
3. if balanced, launch Phase 124 to complete missing scenario/model MCMC cells
   before updating article tables;
4. keep the claims scoped to oracle quantile paths, check loss, grid CRPS,
   hit/coverage diagnostics, and raw/contract crossings.

No scalar posterior predictive density validation should be claimed unless a
separate inverse-CDF quantile-curve sampling layer is designed and validated.
