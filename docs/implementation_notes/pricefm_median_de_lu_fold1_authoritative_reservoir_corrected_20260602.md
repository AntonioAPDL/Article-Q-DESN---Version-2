# PriceFM Median DE_LU Fold-1 Corrected Reservoir Authoritative Run, 2026-06-02

## Status

This note promotes the corrected reservoir-feature PriceFM DESN/Q-DESN run as
the current authoritative local baseline for:

| field | value |
|---|---:|
| region | `DE_LU` |
| fold | `1` |
| quantile | `0.50` |
| horizons | `1:96` |
| target variable | PriceFM market price |
| evaluation split | fold-1 test |

This supersedes:

```text
docs/implementation_notes/pricefm_median_de_lu_fold1_reservoir_winner_20260602.md
docs/implementation_notes/pricefm_desn_authoritative_median_de_lu_20260601.md
```

The earlier reservoir winner remains useful as a pre-fix metric baseline, but
it was affected by the reservoir-control propagation issue documented in:

```text
docs/implementation_notes/pricefm_reservoir_control_propagation_fix_20260602.md
```

The new promoted winner was produced after that fix and passed the corrected
reservoir artifact validator.

## Tracked Reproduction Config

Use this tracked config for a direct rerun of the authoritative specification:

```text
application/config/pricefm_desn_model_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.yaml
```

The full corrected grid that selected this winner is:

```text
application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml
```

## Selected Specification

| field | value |
|---|---:|
| feature map | `window_reservoir_v1` |
| lag window `L` | `96` |
| lead window | `96` |
| reservoir depth | `1` |
| reservoir units | `[120]` |
| reservoir alpha | `0.5` |
| reservoir rho | `0.9` |
| reservoir input scale | `0.5` |
| recurrent sparsity | `0.05` |
| activation | `tanh` |
| state output | `final_layer` |
| seed | `20260601` |
| selected training origins | all available tail origins for fold/window, up to `3000` |
| stacked train rows | `93408` |
| model feature count | `223` |
| prior | `RHS_NS` |
| RHS_NS `tau0` | `1.0e-3` |
| intercept shrinkage | disabled |
| Q-DESN likelihoods | AL and exAL |
| VB iterations | min `50`, max `100` |
| chunking | exact, sequential, chunk size `2048` |
| warm-start chain | normal scaled ridge -> normal RHS_NS -> Q-DESN AL -> Q-DESN exAL |

## Winner

The promoted experiment is:

```text
rc_p1_d1n120_l096_alpha0p5_rho0p9_input_scale0p5
```

The promoted method is:

```text
qdesn_exal_rhs_ns_exact_chunked
```

Original-unit test metrics:

| method | AQL | MAE | RMSE |
|---|---:|---:|---:|
| Q-DESN exAL RHS_NS exact chunked | `6.3105` | `12.6210` | `20.0293` |
| Q-DESN AL RHS_NS exact chunked | `6.3310` | `12.6620` | `20.0538` |
| Normal DESN RHS_NS | `7.9291` | `15.8582` | `22.0868` |
| naive previous day | `14.0090` | `28.0181` | `42.8383` |
| Normal DESN scaled ridge | `14.0114` | `28.0228` | `35.9370` |
| naive previous 3-day average | `14.6444` | `29.2889` | `42.0183` |
| naive previous 7-day average | `14.6940` | `29.3880` | `40.9422` |

Relative to the best naive baseline, `naive1_prev_day`, the promoted Q-DESN
exAL RHS_NS model improves:

| metric | selected | naive1 | relative improvement |
|---|---:|---:|---:|
| AQL | `6.3105` | `14.0090` | `54.95%` |
| MAE | `12.6210` | `28.0181` | `54.95%` |
| RMSE | `20.0293` | `42.8383` | `53.24%` |

## Grid Evidence

The corrected grid completed:

| item | result |
|---|---:|
| priority-0 smoke experiments | `5 / 5` completed |
| priority-1 screen experiments | `92 / 92` completed |
| window builds | `92 / 92` completed |
| failures | `0` |
| metric summaries before cleanup | `97` |
| feature manifests before cleanup | `97` |
| figures before cleanup | `776` |
| `.rds` / `.rda` / `.RData` outputs | `0` |

Best stage groups by original-unit test AQL:

| stage group | cells | best AQL | mean AQL |
|---|---:|---:|---:|
| D1 n120 dynamics | `18` | `6.3105` | `6.4729` |
| D1 n80 dynamics | `18` | `6.3769` | `6.4715` |
| D2 base | `4` | `6.4268` | `6.4894` |
| priority-0 smoke | `5` | `6.4304` | `6.4797` |
| D2 80x80 dynamics | `18` | `6.4403` | `6.5468` |
| D2 40x40 dynamics | `18` | `6.4521` | `6.5804` |
| context neighbor | `6` | `6.4929` | `6.4963` |
| D1 capacity | `6` | `6.4964` | `6.5649` |
| D1 high input | `4` | `6.5810` | `6.6447` |

Method win counts across all `97` completed specs:

| method | wins |
|---|---:|
| Q-DESN exAL RHS_NS exact chunked | `92` |
| Q-DESN AL RHS_NS exact chunked | `5` |

## Validation

Corrected reservoir validation:

- priority `0,1` prelaunch validation passed for `97` selected configs;
- priority-0 real smoke validation passed for all `5` smoke cells;
- the promoted winner has a feature manifest SHA recorded in the local
  promotion manifest;
- no non-winner artifacts are needed to reproduce the selected configuration.

Exact chunking equivalence gate for the promoted winner:

| quantity | max absolute difference | tolerance | result |
|---|---:|---:|---|
| beta mean | `0` | `1.0e-6` | passed |
| beta covariance | `0` | `1.0e-6` | passed |
| train prediction | `0` | `1.0e-6` | passed |

Fit and warm-start diagnostics:

| method | init source | converged | iterations | train seconds |
|---|---|---:|---:|---:|
| normal scaled ridge | closed form | yes | `1` | `4.236` |
| normal RHS_NS | normal scaled ridge | no, max iter hit | `100` | `8.471` |
| Q-DESN AL RHS_NS exact chunked | normal RHS_NS | yes | `50` | `441.196` |
| Q-DESN exAL RHS_NS exact chunked | Q-DESN AL, same tau | yes | `50` | `444.585` |

The normal RHS_NS non-convergence flag means it reached the current
`max_iter = 100` criterion. The downstream Q-DESN AL/exAL models converged
under the current Q-DESN VB gate.

## Local Freeze And Cleanup

Compact local freeze root:

```text
application/data_local/pricefm/authoritative/pricefm_median_de_lu_fold1_reservoir_corrected_20260602
```

Important freeze files:

```text
promotion_manifest.json
summaries/best_by_experiment.csv
summaries/top50_experiments.csv
summaries/stage_group_summary.csv
winner/metric_summary.csv
winner/figures/
```

Post-promotion cleanup:

| item | result |
|---|---:|
| non-winner corrected-grid experiment directories deleted | `96` |
| deleted bytes | `3720417049` |
| corrected run root after cleanup | `38 MB` |
| local freeze root | `2.8 MB` |
| corrected grid metadata root | `2.6 MB` |
| compact experiment summaries preserved in freeze | `97` |
| full winner artifacts preserved in run root | yes |
| full winner artifacts copied to freeze | yes |
| `.rds` / `.rda` / `.RData` outputs after cleanup | `0` |

Only directories under this exact corrected run root were cleaned:

```text
application/data_local/pricefm/runs/pricefm_median_de_lu_reservoir_corrected_20260602
```

No unrelated GloFAS, validation-study, or older PriceFM run roots were removed.

## Figure Paths

Promoted winner figures in the preserved run root:

```text
application/data_local/pricefm/runs/pricefm_median_de_lu_reservoir_corrected_20260602/rc_p1_d1n120_l096_alpha0p5_rho0p9_input_scale0p5/cells/region=DE_LU/fold=1/model/figures
```

Copied winner figures in the local freeze:

```text
application/data_local/pricefm/authoritative/pricefm_median_de_lu_fold1_reservoir_corrected_20260602/winner/figures
```

The figure set includes:

- `test_fit_qdesn_exal_rhs_ns_exact_chunked.png`
- `test_fit_qdesn_al_rhs_ns_exact_chunked.png`
- `test_fit_normal_rhs_ns.png`
- `test_fit_normal_scaled_ridge.png`
- `test_fit_first14_origins.png`
- `trace_elbo.png`
- `trace_parameter_diagnostics.png`
- `final_parameter_summary.png`

## PriceFM Reference Context

The local upstream PriceFM phase-I pretraining result for `DE_LU` is:

| source | AQL | MAE | RMSE |
|---|---:|---:|---:|
| upstream PriceFM phase-I pretraining, `DE_LU` | `5.6752` | `14.2119` | `24.3393` |

This remains useful context, not a direct apples-to-apples benchmark. The
current authoritative DESN/Q-DESN result is single-region, fold-1, median-only,
and uses the local fold/window/metric reducer. A direct comparison requires
running the upstream PriceFM forecast path under the same region, fold, horizon,
quantile, and metric reducer.

## Reproduction Commands

Rerun only the promoted authoritative specification:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/10_run_desn_model_full.py \
  --config application/config/pricefm_desn_model_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.yaml \
  --regions DE_LU \
  --folds 1 \
  --jobs 1 \
  --resume true \
  --force false \
  --dry-run false
```

Regenerate the corrected grid configs:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml \
  --write
```

Validate generated corrected-grid configs:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/14_validate_reservoir_grid_artifacts.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml \
  --priorities 0,1 \
  --write-generated
```

Rerun the full corrected priority-1 screen:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml \
  --priorities 1 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

## Next Step

Use this specification as the local `DE_LU`, fold-1, median authoritative
baseline. The next comparison should be seed robustness or fold robustness for
this exact geometry before expanding to many regions or additional quantiles.
