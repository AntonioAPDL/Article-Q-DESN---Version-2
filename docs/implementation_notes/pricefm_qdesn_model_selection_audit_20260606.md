# PriceFM Q-DESN Model Selection Audit

Date: 2026-06-06

## Objective

Audit the current PriceFM/Q-DESN model-selection workflow after the DE_LU fold
2/3 follow-up quantile run and harden it so it remains functional for the
current Q-DESN methods.

This note covers the article-side PriceFM selection pipeline. It does not
change the underlying package-level Q-DESN inference algorithms.

Follow-up consolidation note:

```text
docs/implementation_notes/pricefm_qdesn_model_selection_bridge_20260606.md
```

That note records the updated architecture after the package-level
`exdqlm::qdesn_model_selection()` consolidation: the package function is the
authoritative generic Q-DESN model-selection API, while the PriceFM scripts here
are an article-specific artifact registry/promotion adapter until the full
PriceFM fold/horizon contract is ported into a package-compatible v2 config.

## Relevant Scripts

Current median and promotion workflow:

```text
application/scripts/pricefm/12_prepare_desn_experiment_grid.py
application/scripts/pricefm/13_run_desn_experiment_grid.py
application/scripts/pricefm/20_select_pricefm_desn_median_specs.py
application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py
application/scripts/pricefm/27_summarize_median_seed_robustness.py
application/scripts/pricefm/28_prepare_median_folds23_followup_grid.py
```

Current no-fit diagnostics and horizon-block tooling:

```text
application/scripts/pricefm/22_summarize_median_grid_diagnostics.py
application/scripts/pricefm/23_audit_desn_feature_geometry.py
application/scripts/pricefm/24_select_median_horizon_blocks.py
application/scripts/pricefm/25_materialize_median_horizon_block_composite.py
application/scripts/pricefm/26_prepare_median_seed_robustness_grid.py
```

Current fold-aligned PriceFM comparison workflow:

```text
application/scripts/pricefm/15_summarize_paper_quantile_runs.py
application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py
application/scripts/pricefm/19_summarize_pricefm_phase1_desn_fold_comparisons.py
```

## Current Supported Selection Methods

The current Q-DESN selection target for PriceFM median grids is:

```text
qdesn_exal_rhs_ns_exact_chunked
qdesn_al_rhs_ns_exact_chunked
```

Both are exact-chunked full-data VB targets under the current PriceFM run
configuration. The selector should not select from normal-DESN methods or naive
baselines unless explicitly requested for a separate diagnostic.

## Audit Findings

1. The selection workflow is validation-first and remains conceptually sound.
   The registry selector ranks candidates by validation AQL and writes test
   metrics only as audit fields.

2. The promotion workflow is compatible with current Q-DESN models.
   The selected median geometry is materialized to the seven paper quantiles
   while preserving region/fold scope.

3. The old selector needed a stronger safety check.
   Before this pass, if a requested current Q-DESN method were missing from a
   completed grid, the selector could still choose from the remaining method
   rows. That is risky because a registry might look valid while silently
   comparing an incomplete candidate set.

4. The fold-level PriceFM benchmark had to be distinguished from the external
   region-level PriceFM CSV.
   The paper-quantile summarizer can display the external region-level CSV row
   as context, but the authoritative fold comparison must come from the
   fold-aligned script `18`.

## Changes Made

The median selector now writes and validates:

```text
median_selection_method_coverage.csv
```

Each requested method must have at least one finite selection metric row for
each selected region/fold. For the DE_LU fold 2/3 follow-up registry, coverage
is:

| Region | Fold | Method | Rows | Finite rows | Covered |
|---|---:|---|---:|---:|---|
| DE_LU | 2 | `qdesn_al_rhs_ns_exact_chunked` | 5 | 5 | true |
| DE_LU | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 5 | 5 | true |
| DE_LU | 3 | `qdesn_al_rhs_ns_exact_chunked` | 120 | 120 | true |
| DE_LU | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 120 | 120 | true |

The paper-quantile summarizer now labels the external PriceFM CSV as:

```text
reference_scope = region_level_external_csv
benchmark_role = context_only_not_fold_aligned
```

and points users to `18_compare_pricefm_phase1_desn_quantiles.py` for
fold-aligned benchmarks.

## Validation Commands

Refreshed selector:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605 \
  --regions DE_LU \
  --folds 2,3 \
  --selection-split val \
  --selection-unit original \
  --selection-metric AQL \
  --selection-methods qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked \
  --require-complete true \
  --priorities 0
```

Refreshed fold summaries:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/15_summarize_paper_quantile_runs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_followup_promoted_quantiles_20260605.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_followup_paper_quantiles_authoritative_20260605 \
  --region DE_LU \
  --fold 2 \
  --require-complete true

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/15_summarize_paper_quantile_runs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_followup_promoted_quantiles_20260605.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_followup_paper_quantiles_authoritative_20260605 \
  --region DE_LU \
  --fold 3 \
  --require-complete true
```

Refreshed fold-aligned comparisons:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py \
  --pricefm-output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold2_apples_to_apples_20260602 \
  --desn-output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_followup_paper_quantiles_authoritative_20260605 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold2_followup_20260605 \
  --region DE_LU \
  --fold 2

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py \
  --pricefm-output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold3_apples_to_apples_20260602 \
  --desn-output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_followup_paper_quantiles_authoritative_20260605 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold3_followup_20260605 \
  --region DE_LU \
  --fold 3
```

Aggregate:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/19_summarize_pricefm_phase1_desn_fold_comparisons.py \
  --region DE_LU \
  --folds 2,3 \
  --comparison-dir-template application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold{fold}_followup_20260605 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds23_followup_20260605 \
  --baseline-method pricefm_phase1_pretraining
```

## How This Can Improve The Current Model

The model-selection workflow is now good enough to support the next search,
but the search should be narrower than another broad random grid.

Use validation-only selection for:

1. Fold-3 short-horizon candidates.
2. Horizon-block specialists, especially `1-24`.
3. Candidate feature-map changes that target representation rather than only
   bigger reservoirs.
4. Seed robustness for any candidate that wins validation AQL.

Do not use fold-2/3 test AQL to select the next spec. Test remains an audit
field until a promoted quantile grid is run.

## Recommended Next Implementation

The next high-value workflow improvement is a horizon-block registry promotion
that can:

1. select block-specific median winners by validation metrics;
2. verify complete coverage of horizon groups;
3. materialize block-specialist paper-quantile configs;
4. compare the block composite to PriceFM on fold-aligned rows;
5. keep test metrics audit-only until promotion.

This is more promising than scaling to all regions now, because the latest
diagnostics show that the current global fold-3 spec loses most sharply in the
short-horizon block.

## Stop Gates For Future Model Selection

- Do not select from incomplete method coverage.
- Do not use region-level external PriceFM CSV rows as fold-aligned
  benchmarks.
- Do not promote a horizon-block composite unless every horizon is covered
  exactly once.
- Do not tune on test AQL.
- Do not scale to all regions until DE_LU fold-3 short-horizon behavior is
  either improved or explicitly accepted as the current limitation.
