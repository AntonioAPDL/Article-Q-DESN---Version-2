# Joint QDESN Phase 117 Manuscript QA Polish

## Purpose

Phase 117 applies the Phase 116 article-readiness audit to the manuscript text
and generated joint-validation table captions.  The objective is not to launch
new validation runs.  The objective is to make the completed evidence readable,
modest, and reproducible in the main article.

## Sources Audited

- `Academic_Writing_Style_Profile_v0.2.md`;
- `main.tex`, Section `Simulation Validation Study`;
- `tables/joint_qdesn_article_validation_tables.tex`;
- `tables/joint_qdesn_article_validation_protocol.tex`;
- `tables/joint_qdesn_article_validation_vb_model_summary.tex`;
- `tables/joint_qdesn_article_validation_vb_scenario_summary.tex`;
- `application/cache/joint_qdesn_phase116_article_readiness_audit_20260709`;
- `application/R/joint_qdesn_article_assets.R`.

## Audit Findings

1. The section already had the correct evidence hierarchy: VB supplies the
   held-out fit/forecast comparison, and MCMC supplies a fit-window reference
   for the selected Joint QDESN RHS row.

2. The prose needed a clearer separation between raw quantile outputs and the
   reported monotone grid.  Phase 116 records 73 raw pre-rearrangement crossings
   in the selected-candidate VB bundle and zero reported-grid crossings; the
   model-level table attributes 2 of those raw crossings to the primary Joint
   QDESN RHS row and 71 to the Independent QDESN RHS comparator.  Readers should
   not have to infer which grid is scored.

3. The scenario table shows heterogeneity.  Joint QDESN RHS has the lowest
   displayed forecast MAE in five of nine mechanisms, but not all nine.  The
   manuscript should describe the result as fixed-design competitive evidence,
   not as uniform dominance.

4. The exQDESN rows are stable in the raw-crossing diagnostic but farther from
   the oracle quantile paths in this validation bundle.  The article should
   present them as likelihood extensions/comparators requiring additional
   calibration, not as superior alternatives.

5. The MCMC evidence passes the implementation and diagnostic gates, but it is
   fit-window evidence.  It should not be described as held-out forecast
   validation.

6. Table captions should define QDESN/exQDESN and raw crossings without using
   internal phase labels or cache-specific language.

## Implemented Edits

- Revised the joint multi-quantile validation subsection in `main.tex`.
- Expanded the RHS prior at the start of the joint-validation subsection.
- Defined raw and reported quantile grids before interpreting the tables.
- Rephrased the average result as a fixed-design comparison rather than a
  leaderboard claim.
- Added the scenario-level result that Joint QDESN RHS is lowest in five of
  nine mechanisms.
- Clarified that exQDESN is a likelihood extension in this validation bundle,
  not evidence of exAL dominance.
- Clarified that the MCMC run is a fit-window reference under recorded controls,
  not rolling-origin forecast validation.
- Updated source table captions in `application/R/joint_qdesn_article_assets.R`
  so regenerated Phase 115 tables preserve the polish.

## Reproducibility Plan

After editing the table builder, regenerate the article-validation assets:

```sh
Rscript application/scripts/110_build_joint_qdesn_article_validation_assets.R \
  --phase107-dir application/cache/joint_qdesn_vb_spec_screening_phase113_20260708 \
  --phase109-dir application/cache/joint_qdesn_mcmc_article_phase114_20260708 \
  --output-dir application/cache/joint_qdesn_article_validation_assets_phase115_20260708
```

Then refresh the readiness audit:

```sh
Rscript application/scripts/116_audit_joint_qdesn_article_readiness.R
```

Focused verification:

```sh
Rscript application/tests/test_joint_qdesn_article_validation_assets.R
Rscript application/tests/test_joint_qdesn_article_readiness_audit.R
git diff --check
```

If a local TeX toolchain is available, compile the manuscript after the asset
refresh.  The expected global evidence gate remains `review`, because the raw
crossing diagnostics are retained; the implementation and reproducibility gates
should remain pass-level.

## Next Step

After this polish, the next joint-validation task is a manuscript-level
read-through and compile check.  Additional compute should be launched only for a
specific claim that the polished manuscript still cannot support.
