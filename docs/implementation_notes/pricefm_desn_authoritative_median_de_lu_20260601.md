# PriceFM DESN Authoritative Median DE_LU Specification, 2026-06-01

## Status

Superseded on 2026-06-02 by:

```text
docs/implementation_notes/pricefm_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.md
```

The superseding corrected reservoir baseline uses reservoir features and
improves the single-region `DE_LU`, fold-1, median test AQL from `10.5046` to
`6.3105`. The intermediate reservoir result documented in
`docs/implementation_notes/pricefm_median_de_lu_fold1_reservoir_winner_20260602.md`
is now treated as a pre-fix metric baseline because a reservoir-control
propagation issue was found and fixed on 2026-06-02; see
`docs/implementation_notes/pricefm_reservoir_control_propagation_fix_20260602.md`.

Before supersession, the PriceFM DESN/Q-DESN median specification selected for
local development was:

```text
application/config/pricefm_desn_model_median_de_lu_fold1_authoritative_20260601.yaml
```

This specification was selected from the completed priority-1 refinement grid:

```text
application/config/pricefm_desn_experiment_grid_median_de_lu_refine_20260601.yaml
```

The winning completed run is:

```text
application/data_local/pricefm/runs/pricefm_median_de_lu_refine_20260601/l096_m480_ps0p5_tau1em3_seed20260601
```

Generated model artifacts remain under ignored `application/data_local` paths.
The tracked authoritative config is the reproducible recipe.

## Selected Specification

| field | value |
|---|---:|
| region | `DE_LU` |
| fold | `1` |
| quantile | `0.50` |
| horizons | `1:96` |
| lag window `L` | `96` |
| DESN feature map | `window_desn_v1` |
| DESN feature count `m` | `480` |
| projection scale | `0.5` |
| random seed | `20260601` |
| train origin limit | `3000` tail origins |
| prior | RHS_NS |
| RHS_NS `tau0` | `1.0e-3` |
| intercept shrinkage | disabled |
| Q-DESN likelihoods | AL and exAL |
| VB iterations | min `50`, max `100` |
| chunking | exact, sequential, chunk size `2048` |
| warm start | normal scaled ridge -> normal RHS_NS -> Q-DESN AL -> Q-DESN exAL |

## Test Metrics

Original-unit test metrics from the winning run:

| method | AQL | MAE | RMSE |
|---|---:|---:|---:|
| Q-DESN exAL RHS_NS exact chunked | `10.5046` | `21.0091` | `30.6258` |
| Q-DESN AL RHS_NS exact chunked | `10.5110` | `21.0220` | `30.6795` |
| Normal DESN RHS_NS | `11.5281` | `23.0562` | `32.4146` |
| Naive previous day | `14.0090` | `28.0181` | `42.8383` |
| Naive previous 3-day average | `14.6444` | `29.2889` | `42.0183` |
| Naive previous 7-day average | `14.6940` | `29.3880` | `40.9422` |
| Normal DESN scaled ridge | `22.2030` | `44.4061` | `56.6233` |

The selected Q-DESN exAL RHS_NS model improves test AQL by about `25.0%`
relative to the best naive baseline in this single-region median setup.

Previous reference points:

| reference | AQL | MAE | RMSE |
|---|---:|---:|---:|
| previous projected winner, `L=96, m=240` | `12.3055` | `24.6110` | `35.3653` |
| previous flat-direct diagnostic winner | `11.2371` | `22.4742` | `32.6197` |
| current authoritative projected winner | `10.5046` | `21.0091` | `30.6258` |

## Validation Artifacts

The winning run produced:

- `metric_summary.csv`
- `metric_by_horizon.csv`
- `metric_by_horizon_group.csv`
- `model_method_summary.csv`
- `model_parameter_summary.csv`
- `model_trace_summary.csv`
- `warm_start_diagnostics.csv`
- `exact_equivalence.csv`
- `report.md`
- eight diagnostic figures

The exact chunking gate passed for AL RHS_NS on the first `1000` training rows:

| quantity | max absolute difference | tolerance |
|---|---:|---:|
| beta mean | `0` | `1.0e-6` |
| beta covariance | `0` | `1.0e-6` |
| train prediction | `0` | `1.0e-6` |

All iterative models converged at the enforced minimum `50` VB iterations.

## Figure Paths

Main diagnostic figures:

```text
application/data_local/pricefm/runs/pricefm_median_de_lu_refine_20260601/l096_m480_ps0p5_tau1em3_seed20260601/cells/region=DE_LU/fold=1/model/figures/test_fit_qdesn_exal_rhs_ns_exact_chunked.png
application/data_local/pricefm/runs/pricefm_median_de_lu_refine_20260601/l096_m480_ps0p5_tau1em3_seed20260601/cells/region=DE_LU/fold=1/model/figures/test_fit_qdesn_al_rhs_ns_exact_chunked.png
application/data_local/pricefm/runs/pricefm_median_de_lu_refine_20260601/l096_m480_ps0p5_tau1em3_seed20260601/cells/region=DE_LU/fold=1/model/figures/test_fit_first14_origins.png
application/data_local/pricefm/runs/pricefm_median_de_lu_refine_20260601/l096_m480_ps0p5_tau1em3_seed20260601/cells/region=DE_LU/fold=1/model/figures/trace_elbo.png
application/data_local/pricefm/runs/pricefm_median_de_lu_refine_20260601/l096_m480_ps0p5_tau1em3_seed20260601/cells/region=DE_LU/fold=1/model/figures/trace_parameter_diagnostics.png
application/data_local/pricefm/runs/pricefm_median_de_lu_refine_20260601/l096_m480_ps0p5_tau1em3_seed20260601/cells/region=DE_LU/fold=1/model/figures/final_parameter_summary.png
```

## Reproduction Commands

Regenerate the refinement-grid configs:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_refine_20260601.yaml \
  --write
```

Rerun only the authoritative config into its dedicated output directory:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/10_run_desn_model_full.py \
  --config application/config/pricefm_desn_model_median_de_lu_fold1_authoritative_20260601.yaml \
  --regions DE_LU \
  --folds 1 \
  --jobs 1 \
  --resume true \
  --force false \
  --dry-run false
```

Rerun the full priority-1 refinement grid:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_refine_20260601.yaml \
  --priorities 1 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

## PriceFM Reference Metric

The local upstream PriceFM clone includes:

```text
application/data_local/pricefm/external/PriceFM/Result/phase1_pretraining.csv
```

That file reports for `DE_LU`:

| source | AQL | MAE | RMSE |
|---|---:|---:|---:|
| upstream PriceFM phase-I pretraining, `DE_LU` | `5.6752` | `14.2119` | `24.3393` |

This is useful context but not a direct benchmark for the current run. The
PriceFM tutorial uses quantiles `[0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]`
and the upstream model is a multi-region foundation model. The current
authoritative DESN run is single-region `DE_LU`, fold `1`, median-only, with a
tail-limited training design. A direct apples-to-apples comparison would require
running the upstream PriceFM forecast code on the same fold, region, horizons,
target quantile, and metric reducer.

## Next Comparison Step

Use this specification as the local projected-feature baseline before expanding
to more regions/folds or additional quantiles. The next scientifically clean
steps are:

1. run seed robustness for the current `L=96, m=480, projection_scale=0.5`
   geometry;
2. run the same authoritative specification over folds `1:3`;
3. only then expand to other regions or quantiles.
