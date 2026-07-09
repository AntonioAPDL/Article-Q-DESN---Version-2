# PriceFM DE_LU Fold 2/3 Follow-Up Quantile Results

Date: 2026-06-06

## Scope

This note freezes the current DE_LU fold 2/3 follow-up paper-quantile
comparison after the fold-specific median-selected Q-DESN specifications were
promoted to the seven PriceFM quantiles.

The comparison is local and apples-to-apples for:

```text
region: DE_LU
folds: 2, 3
split: test
quantiles: 0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90
benchmark: local fold-aligned PriceFM Phase-I predictions
```

The authoritative benchmark for this note is the fold-aligned output from:

```text
application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py
application/scripts/pricefm/19_summarize_pricefm_phase1_desn_fold_comparisons.py
```

The external `phase1_pretraining.csv` row is region-level context only. It is
not fold-aligned and is not used as the decisive benchmark in this note.

## Run State

Promoted quantile grid:

```text
application/config/pricefm_desn_experiment_grid_de_lu_folds23_followup_promoted_quantiles_20260605.yaml
```

Ignored local run roots:

```text
application/data_local/pricefm/experiment_grids/pricefm_de_lu_folds23_followup_promoted_quantiles_20260605/
application/data_local/pricefm/runs/pricefm_de_lu_folds23_followup_promoted_quantiles_20260605/
```

Ignored local authoritative summaries:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_followup_paper_quantiles_authoritative_20260605/
application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_followup_paper_quantiles_authoritative_20260605/
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold2_followup_20260605/
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold3_followup_20260605/
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds23_followup_20260605/
```

Compact tracked snapshots:

```text
docs/implementation_notes/pricefm_de_lu_folds23_followup_quantile_fold_metrics_20260606.csv
docs/implementation_notes/pricefm_de_lu_folds23_followup_quantile_macro_metrics_20260606.csv
docs/implementation_notes/pricefm_de_lu_folds23_followup_quantile_delta_vs_pricefm_20260606.csv
docs/implementation_notes/pricefm_de_lu_folds23_followup_quantile_row_alignment_20260606.csv
docs/implementation_notes/pricefm_de_lu_folds23_followup_quantile_horizon_group_diagnostics_20260606.csv
docs/implementation_notes/pricefm_de_lu_folds23_followup_quantile_quality_audit_20260606.csv
docs/implementation_notes/pricefm_de_lu_folds23_followup_selection_method_coverage_20260606.csv
```

## Selected Median Specs

Selection was validation-only. Test metrics were audit-only.

| Fold | Selected method | Median validation AQL | Promoted geometry |
|---:|---|---:|---|
| 2 | `qdesn_exal_rhs_ns_exact_chunked` | 6.194532 | `L=96`, `D=1`, `units=[120]`, `alpha=0.5`, `rho=0.9`, `input_scale=0.25`, `seed=20260603` |
| 3 | `qdesn_exal_rhs_ns_exact_chunked` | 6.738954 | `L=96`, `D=2`, `units=[80,80]`, `alpha=0.4`, `rho=0.9`, `input_scale=0.35`, `seed=20260603` |

Method coverage for selection is now explicit. The selector saw finite
validation AQL rows for both current Q-DESN candidate methods:

```text
qdesn_exal_rhs_ns_exact_chunked
qdesn_al_rhs_ns_exact_chunked
```

for each requested fold.

## Main Fold Metrics

| Fold | Method | AQL | MAE | RMSE |
|---:|---|---:|---:|---:|
| 2 | `pricefm_phase1_pretraining` | 5.355079 | 13.235907 | 20.013961 |
| 2 | `qdesn_exal_rhs_ns_exact_chunked` | 5.609819 | 14.066582 | 21.263970 |
| 2 | `qdesn_al_rhs_ns_exact_chunked` | 5.648171 | 14.088665 | 21.234694 |
| 2 | `normal_rhs_ns` | 6.798669 | 15.848698 | 22.238173 |
| 3 | `pricefm_phase1_pretraining` | 6.029767 | 14.783424 | 25.517975 |
| 3 | `qdesn_exal_rhs_ns_exact_chunked` | 6.876661 | 17.009112 | 26.900755 |
| 3 | `qdesn_al_rhs_ns_exact_chunked` | 6.905592 | 17.014504 | 26.877349 |
| 3 | `normal_rhs_ns` | 8.337357 | 20.722609 | 28.581826 |

Macro AQL over folds 2 and 3:

| Method | Mean AQL | Mean MAE | Mean RMSE |
|---|---:|---:|---:|
| `pricefm_phase1_pretraining` | 5.692423 | 14.009665 | 22.765968 |
| `qdesn_exal_rhs_ns_exact_chunked` | 6.243240 | 15.537847 | 24.082363 |
| `qdesn_al_rhs_ns_exact_chunked` | 6.276881 | 15.551585 | 24.056022 |
| `normal_rhs_ns` | 7.568013 | 18.285653 | 25.410000 |

## Delta Versus Fold-Aligned PriceFM

| Fold | Method | Delta AQL | AQL ratio | Delta MAE | Delta RMSE |
|---:|---|---:|---:|---:|---:|
| 2 | `qdesn_exal_rhs_ns_exact_chunked` | 0.254740 | 1.047570 | 0.830675 | 1.250009 |
| 2 | `qdesn_al_rhs_ns_exact_chunked` | 0.293091 | 1.054731 | 0.852759 | 1.220733 |
| 3 | `qdesn_exal_rhs_ns_exact_chunked` | 0.846894 | 1.140452 | 2.225688 | 1.382780 |
| 3 | `qdesn_al_rhs_ns_exact_chunked` | 0.875825 | 1.145250 | 2.231080 | 1.359375 |

Q-DESN exAL RHS_NS is the strongest DESN-family method, but local PriceFM
Phase-I remains better on both folds under the fold-aligned comparison.

## Horizon-Group Diagnostics

No new model fitting was done for these diagnostics.

| Fold | Horizon group | PriceFM AQL | Q-DESN exAL AQL | Delta |
|---:|---|---:|---:|---:|
| 2 | 1-24 | 2.519749 | 2.847594 | 0.327845 |
| 2 | 25-48 | 6.296513 | 6.620130 | 0.323617 |
| 2 | 49-72 | 6.411289 | 6.995015 | 0.583726 |
| 2 | 73-96 | 6.192766 | 5.976538 | -0.216228 |
| 3 | 1-24 | 3.226505 | 4.897271 | 1.670766 |
| 3 | 25-48 | 6.879239 | 7.001007 | 0.121769 |
| 3 | 49-72 | 7.509929 | 8.174878 | 0.664950 |
| 3 | 73-96 | 6.503396 | 7.433489 | 0.930093 |

Interpretation:

- Fold 2 is close overall and Q-DESN exAL wins the long horizon block `73-96`.
- Fold 3 is the real bottleneck.
- Fold 3 short horizons `1-24` create the largest single gap.
- A blind global grid is not the best next move. The next model search should
  target fold-3 short-horizon representation and possibly horizon-block
  specialization.

## Quality Gates

| Gate | Result |
|---|---|
| Quantile cells complete | 14 / 14 |
| Quantile coverage | passed for all methods/folds |
| Fold-aligned row identity | passed for all methods/folds |
| AL exact-chunked equivalence checks | passed for all 14 fold/quantile cells |
| Large `.rds/.rda/.RData` artifacts in promoted run | 0 |
| Selector method coverage | passed for AL and exAL Q-DESN candidates |

## Figure Paths

Fold-aligned comparison figures:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold2_followup_20260605/figures/
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold3_followup_20260605/figures/
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds23_followup_20260605/figures/
```

Per-fold paper-quantile diagnostic figures:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_followup_paper_quantiles_authoritative_20260605/figures/
application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_followup_paper_quantiles_authoritative_20260605/figures/
```

## Decision

Freeze this as the current DE_LU fold 2/3 follow-up seven-quantile baseline.
Do not scale to all regions yet. Do not run another broad random reservoir
grid yet.

## Recommended Next Modeling Stage

Use the refreshed model-selection tooling to run a targeted validation-only
fold-3 short-horizon search. Candidate directions:

1. Horizon-block specialists, especially `1-24`.
2. Shorter/recent context variants around fold 3.
3. Multi-scale lag summaries and calendar/time-of-day features.
4. Seed robustness for any fold-3 short-horizon improvement.
5. Promotion to all paper quantiles only after validation-selected median gates
   pass.

Test metrics should remain audit-only during model selection.
