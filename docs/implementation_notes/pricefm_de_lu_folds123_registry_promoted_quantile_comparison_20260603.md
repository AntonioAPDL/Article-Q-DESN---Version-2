# PriceFM DE_LU Fold 1-3 Registry-Promoted Quantile Comparison

Date: 2026-06-03

This note freezes the first fold-robustness comparison for the DE_LU paper-quantile PriceFM experiment after promoting fold-specific median-selected DESN/Q-DESN specifications to all seven paper quantiles.

## Scope

- Region: `DE_LU`
- Folds: `1,2,3`
- Quantiles: `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`
- Split compared: `test`
- Main DESN/Q-DESN methods:
  - `qdesn_exal_rhs_ns_exact_chunked`
  - `qdesn_al_rhs_ns_exact_chunked`
  - `normal_rhs_ns`
  - `normal_scaled_ridge`
- Local paper baseline:
  - `pricefm_phase1_pretraining`

Fold 1 uses the previously promoted fold-1 authoritative quantile run. Folds 2 and 3 use the registry-promoted median winners from the fold-specific registry.

## Registry-Promoted Folds

| fold | selected median run | selected method | selected tau0 | selected context/features |
|---:|---|---|---:|---|
| 2 | `rf_p0_f23_d1n120_l072_a0p50_r0p90_in0p50_seed20260601` | `qdesn_exal_rhs_ns_exact_chunked` | `0.001` | `D=1`, `n=120`, `L=72`, `alpha=0.50`, `rho=0.90`, `input_scale=0.50` |
| 3 | `rf_p0_f23_d1n080_l096_a0p50_r0p90_in0p50_seed20260601` | `qdesn_exal_rhs_ns_exact_chunked` | `0.001` | `D=1`, `n=80`, `L=96`, `alpha=0.50`, `rho=0.90`, `input_scale=0.50` |

## Commands

Folds 2-3 promoted grid launch:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/experiment_grids/pricefm_de_lu_folds23_registry_promoted_quantiles_20260602/launch_logs/priority0_launch.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_registry_promoted_quantiles_20260602.yaml \
  --priorities 0 \
  --experiment-jobs 8 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

Fold summaries:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/15_summarize_paper_quantile_runs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_registry_promoted_quantiles_20260602.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_paper_quantiles_authoritative_20260602 \
  --region DE_LU --fold 2 --require-complete true

application/data_local/pricefm/venv/bin/python application/scripts/pricefm/15_summarize_paper_quantile_runs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_de_lu_folds23_registry_promoted_quantiles_20260602.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_paper_quantiles_authoritative_20260602 \
  --region DE_LU --fold 3 --require-complete true
```

Apples-to-apples fold comparisons:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py \
  --pricefm-output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold2_apples_to_apples_20260602 \
  --desn-output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_paper_quantiles_authoritative_20260602 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold2_20260602 \
  --region DE_LU --fold 2 --split test --max-origins 160

application/data_local/pricefm/venv/bin/python application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py \
  --pricefm-output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold3_apples_to_apples_20260602 \
  --desn-output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_paper_quantiles_authoritative_20260602 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold3_20260602 \
  --region DE_LU --fold 3 --split test --max-origins 160
```

Fold 1-3 aggregation:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/19_summarize_pricefm_phase1_desn_fold_comparisons.py \
  --region DE_LU --folds 1,2,3 \
  --comparison-dir-template application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold{fold}_20260602 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_20260602 \
  --baseline-method pricefm_phase1_pretraining
```

## Run Status

- Folds 2-3 promoted grid cells: `14/14` completed.
- Folds 2-3 metric summaries: `14/14` metric files present.
- Grid launch elapsed wall time: `43:11.19`.
- Grid launch peak RSS: `1,549,372 KB`.
- Fold 2 aligned rows for PriceFM comparison: `413,280` prediction rows, `11,808` response rows.
- Fold 3 aligned rows for PriceFM comparison: `409,920` prediction rows, `11,712` response rows.

## Main Fold Metrics

Tracked snapshot: `docs/implementation_notes/pricefm_de_lu_folds123_registry_promoted_fold_metrics_20260603.csv`

| fold | method_id | AQL | AQCR | MAE | RMSE |
|---:|---|---:|---:|---:|---:|
| 1 | `qdesn_exal_rhs_ns_exact_chunked` | 5.074280 | 0.000391 | 12.621029 | 20.029264 |
| 1 | `qdesn_al_rhs_ns_exact_chunked` | 5.119166 | 0.006004 | 12.662026 | 20.053755 |
| 1 | `pricefm_phase1_pretraining` | 5.323540 | 0.000000 | 13.123400 | 22.066193 |
| 2 | `pricefm_phase1_pretraining` | 5.355079 | 0.000000 | 13.235907 | 20.013961 |
| 2 | `qdesn_exal_rhs_ns_exact_chunked` | 5.627840 | 0.001256 | 14.034639 | 21.203163 |
| 2 | `qdesn_al_rhs_ns_exact_chunked` | 5.674629 | 0.016288 | 14.099082 | 21.222417 |
| 3 | `pricefm_phase1_pretraining` | 6.029767 | 0.000000 | 14.783424 | 25.517975 |
| 3 | `qdesn_exal_rhs_ns_exact_chunked` | 7.015117 | 0.006432 | 17.118508 | 26.954982 |
| 3 | `qdesn_al_rhs_ns_exact_chunked` | 7.135959 | 0.017888 | 17.191822 | 27.019668 |

## Macro Metrics

Tracked snapshot: `docs/implementation_notes/pricefm_de_lu_folds123_registry_promoted_macro_metrics_20260603.csv`

| method_id | AQL_mean | AQL_std | AQL_min | AQL_max | MAE_mean | RMSE_mean |
|---|---:|---:|---:|---:|---:|---:|
| `pricefm_phase1_pretraining` | 5.569462 | 0.398948 | 5.323540 | 6.029767 | 13.714243 | 22.532710 |
| `qdesn_exal_rhs_ns_exact_chunked` | 5.905746 | 0.999818 | 5.074280 | 7.015117 | 14.591392 | 22.729137 |
| `qdesn_al_rhs_ns_exact_chunked` | 5.976585 | 1.041752 | 5.119166 | 7.135959 | 14.650977 | 22.765280 |
| `normal_rhs_ns` | 7.409797 | 0.947713 | 6.690491 | 8.483669 | 17.928499 | 24.780206 |
| `normal_scaled_ridge` | 33.699434 | 6.944285 | 26.601979 | 40.479678 | 28.275408 | 36.646001 |

## Takeaways

1. Q-DESN exAL RHS_NS remains the strongest DESN-family method and wins fold 1 against local PriceFM Phase-I.
2. Local PriceFM Phase-I wins folds 2 and 3 under the current fold-specific median-promoted Q-DESN specs.
3. The fold 2 gap is modest: Q-DESN exAL is `+0.273` AQL over PriceFM, or `1.051x` PriceFM AQL.
4. The fold 3 gap is larger: Q-DESN exAL is `+0.985` AQL over PriceFM, or `1.163x` PriceFM AQL.
5. Q-DESN exAL is consistently better than Q-DESN AL and substantially better than Normal-DESN RHS_NS and all naive baselines.
6. The Normal-DESN scaled ridge baseline remains poor for these paper-quantile runs and should not be treated as a competitive quantile baseline.

## Local Output Paths

Fold paper-quantile summaries:

- `application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602`
- `application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_paper_quantiles_authoritative_20260602`
- `application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_paper_quantiles_authoritative_20260602`

Fold PriceFM comparisons:

- `application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602`
- `application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold2_20260602`
- `application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold3_20260602`

Fold 1-3 aggregate:

- `application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_20260602`

Key aggregate figures:

- `application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_20260602/figures/aql_by_fold_method.png`
- `application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_20260602/figures/aql_delta_vs_pricefm_by_fold.png`

Fold-specific diagnostic figures:

- `application/data_local/pricefm/authoritative/pricefm_de_lu_fold2_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/`
- `application/data_local/pricefm/authoritative/pricefm_de_lu_fold3_paper_quantiles_authoritative_20260602/figures/paper_quantile_diagnostics/`

## Validation

- `application/scripts/pricefm/15_summarize_paper_quantile_runs.py` now resolves multi-fold grid rows by scope before merging quantile cells.
- Focused test: `application/data_local/pricefm/venv/bin/python -m pytest application/tests/test_pricefm_paper_quantile_summary.py -q`
- Result: `6 passed`.

## Next Step

Do not broaden to more regions yet. The right next modeling step is a fold-3 targeted median refresh around the selected fold-3 family, because fold 3 is the dominant gap against PriceFM. Candidate directions are a larger fold-3 feature budget, alternative recent-context windows, and seed robustness for the best fold-3 neighborhood.
