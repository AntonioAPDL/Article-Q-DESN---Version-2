# PriceFM DE_LU Fold-Complete Follow-Up Comparison

Date: 2026-06-06

## Scope

This note records the current authoritative DE_LU all-fold, all-paper-quantile
comparison. It combines:

- fold 1: previously promoted authoritative DESN/Q-DESN paper-quantile run;
- folds 2 and 3: validation-selected follow-up median specs promoted to all
  paper quantiles;
- local apples-to-apples PriceFM Phase-I predictions for each fold.

No new model fits were launched in this pass. Existing completed quantile cells
were refreshed through the summarization and comparison scripts.

## Paper Quantiles

```text
0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90
```

## Commands Run

Refresh fold quantile summaries:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/15_summarize_paper_quantile_runs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_fold1_paper_quantiles_authoritative_20260602.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602 \
  --region DE_LU \
  --fold 1 \
  --require-complete true

application/data_local/pricefm/venv/bin/python application/scripts/pricefm/15_summarize_paper_quantile_runs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_followup_promoted_quantiles_20260605.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_followup_paper_quantiles_authoritative_20260605 \
  --region DE_LU \
  --fold 2 \
  --require-complete true

application/data_local/pricefm/venv/bin/python application/scripts/pricefm/15_summarize_paper_quantile_runs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_followup_promoted_quantiles_20260605.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_followup_paper_quantiles_authoritative_20260605 \
  --region DE_LU \
  --fold 3 \
  --require-complete true
```

Refresh fold-aligned PriceFM Phase-I comparisons:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py \
  --pricefm-output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold1_apples_to_apples_20260602 \
  --desn-output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602 \
  --region DE_LU \
  --fold 1

application/data_local/pricefm/venv/bin/python application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py \
  --pricefm-output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold2_apples_to_apples_20260602 \
  --desn-output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_followup_paper_quantiles_authoritative_20260605 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold2_followup_20260605 \
  --region DE_LU \
  --fold 2

application/data_local/pricefm/venv/bin/python application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py \
  --pricefm-output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold3_apples_to_apples_20260602 \
  --desn-output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_followup_paper_quantiles_authoritative_20260605 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold3_followup_20260605 \
  --region DE_LU \
  --fold 3
```

Build the fold-complete report:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/32_summarize_pricefm_fold_complete_comparison.py \
  --region DE_LU \
  --fold-comparison-dirs '1:application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602,2:application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold2_followup_20260605,3:application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold3_followup_20260605' \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_followup_authoritative_20260606
```

## Output Directory

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_followup_authoritative_20260606/
```

Key files:

```text
fold_metric_summary.csv
macro_metric_summary.csv
method_delta_vs_pricefm.csv
selected_spec_summary.csv
fold_row_alignment_audit.csv
pricefm_vs_desn_fold_complete_report.md
figures/fold_complete_aql_by_fold_method.png
figures/fold_complete_aql_delta_vs_pricefm.png
figures/fold_complete_macro_aql.png
figures/fold_complete_aql_by_horizon_block.png
```

## Selected Specs

| fold | selection_source | experiment_id | selected_method_id | lag_window | feature_dim | depth | units | alpha | rho | input_scale | tau0 | seed |
| --- | --- | --- | --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | fold1_authoritative_config | pq_tau0p10_rc_p1_d1n120_l096_alpha0p5_rho0p9_input_scale0p5 | qdesn_exal_rhs_ns_exact_chunked | 96 | 120 | 1 | [120] | 0.5 | 0.9 | 0.50 | 0.001 | 20260601 |
| 2 | folds23_validation_registry | fup_f2_priorp2retest_l96_d1_n120_a0p5_r0p9_in0p25_seed20260603 | qdesn_exal_rhs_ns_exact_chunked | 96 | 120 | 1 | [120] | 0.5 | 0.9 | 0.25 | 0.001 | 20260603 |
| 3 | folds23_validation_registry | fup_f3_fold3localrefine_l96_d2_n80x80_a0p4_r0p9_in0p35_seed20260603 | qdesn_exal_rhs_ns_exact_chunked | 96 | 80 | 2 | [80, 80] | 0.4 | 0.9 | 0.35 | 0.001 | 20260603 |

## Macro Metrics

Original-scale test metrics averaged over folds 1/2/3:

| method_id | AQL_mean | AQL_std | AQL_min | AQL_max | MAE_mean | RMSE_mean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| pricefm_phase1_pretraining | 5.569462 | 0.398948 | 5.323540 | 6.029767 | 13.714243 | 22.532710 |
| qdesn_exal_rhs_ns_exact_chunked | 5.853587 | 0.925587 | 5.074280 | 6.876661 | 14.565574 | 22.731330 |
| qdesn_al_rhs_ns_exact_chunked | 5.890976 | 0.917631 | 5.119166 | 6.905592 | 14.588398 | 22.721933 |
| normal_rhs_ns | 7.275506 | 0.921180 | 6.690491 | 8.337357 | 17.476496 | 24.302260 |
| normal_scaled_ridge | 34.767195 | 8.269410 | 25.284582 | 40.479678 | 35.539806 | 47.689213 |

## Fold Metrics

| fold | method_id | AQL | AQCR | MAE | RMSE |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1 | qdesn_exal_rhs_ns_exact_chunked | 5.074280 | 0.000391 | 12.621029 | 20.029264 |
| 1 | qdesn_al_rhs_ns_exact_chunked | 5.119166 | 0.006004 | 12.662026 | 20.053755 |
| 1 | pricefm_phase1_pretraining | 5.323540 | 0.000000 | 13.123400 | 22.066193 |
| 1 | normal_rhs_ns | 6.690491 | 0.000000 | 15.858182 | 22.086782 |
| 1 | normal_scaled_ridge | 40.479678 | 0.000000 | 28.022764 | 35.936957 |
| 2 | pricefm_phase1_pretraining | 5.355079 | 0.000000 | 13.235907 | 20.013961 |
| 2 | qdesn_exal_rhs_ns_exact_chunked | 5.609819 | 0.001482 | 14.066582 | 21.263970 |
| 2 | qdesn_al_rhs_ns_exact_chunked | 5.648171 | 0.028342 | 14.088665 | 21.234694 |
| 2 | normal_rhs_ns | 6.798669 | 0.000000 | 15.848698 | 22.238173 |
| 2 | normal_scaled_ridge | 38.537326 | 0.000000 | 53.642519 | 74.287775 |
| 3 | pricefm_phase1_pretraining | 6.029767 | 0.000000 | 14.783424 | 25.517975 |
| 3 | qdesn_exal_rhs_ns_exact_chunked | 6.876661 | 0.000285 | 17.009112 | 26.900755 |
| 3 | qdesn_al_rhs_ns_exact_chunked | 6.905592 | 0.003501 | 17.014504 | 26.877349 |
| 3 | normal_rhs_ns | 8.337357 | 0.000000 | 20.722609 | 28.581826 |
| 3 | normal_scaled_ridge | 25.284582 | 0.000000 | 24.954136 | 32.842906 |

## Interpretation

- PriceFM Phase-I is the current fold-complete macro-AQL winner.
- Q-DESN exAL RHS_NS is the best DESN/Q-DESN method and wins fold 1.
- Folds 2 and 3 still favor PriceFM Phase-I after the follow-up DESN search.
- Q-DESN AL and exAL remain close; exAL is slightly better by macro AQL.
- Normal RHS_NS is stable but materially weaker than Q-DESN on this target.
- Normal scaled ridge remains a weak baseline and should not be promoted.

## Validation

- Fold 1, fold 2, and fold 3 quantile summaries each report 7/7 complete cells.
- Fold-aligned comparison rows:
  - fold 1: 403200 prediction rows, 11520 response rows;
  - fold 2: 413280 prediction rows, 11808 response rows;
  - fold 3: 409920 prediction rows, 11712 response rows.
- The fold-complete summary directory is small: about 692 KB.
- No `.rds`, `.rda`, or `.RData` files were produced in the fold-complete
  summary directory.

## Next Recommended Step

Stop trying to tune DE_LU only. The next stage should scale this workflow to a
small diverse region panel with the same package-style selection/parity
discipline:

1. choose 4-6 regions with different load/price behavior;
2. run median selection per region/fold;
3. promote selected median specs to paper quantiles;
4. regenerate local PriceFM Phase-I comparisons;
5. summarize region/fold robustness before any all-38-region launch.
