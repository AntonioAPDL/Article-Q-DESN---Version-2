# PriceFM Median DE_LU Fold-1 Reservoir Winner Freeze, 2026-06-02

## Status

Superseded on 2026-06-02 by the corrected reservoir-control run:

```text
docs/implementation_notes/pricefm_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.md
```

This note freezes the current authoritative local PriceFM median baseline for
single-region `DE_LU`, fold `1`, quantile `0.50`, horizons `1:96`.

Important correction, 2026-06-02: after this freeze, a reservoir-control
propagation bug was found and fixed. The completed run artifacts are valid
model fits, but they should be interpreted using the frozen feature manifests,
not the run-ID labels. In particular, the selected run ID contains
`d2n80x80`, but the frozen manifest shows the actual fitted feature map was a
single-layer default reservoir with `units = [80]`. See:

```text
docs/implementation_notes/pricefm_reservoir_control_propagation_fix_20260602.md
```

The selected run is the best completed result from the reservoir feature grid:

```text
application/data_local/pricefm/runs/pricefm_median_de_lu_reservoir_20260601/res_smoke_d2n80x80_a0p70_r0p90_in0p50_seed20260601
```

The selected method is:

```text
qdesn_al_rhs_ns_exact_chunked
```

This supersedes the projected-feature baseline documented in:

```text
docs/implementation_notes/pricefm_desn_authoritative_median_de_lu_20260601.md
```

Scope caveat: this is an authoritative local baseline for the current
single-region/single-fold median PriceFM exploration. It is not yet a final
paper-level claim across all PriceFM regions, folds, or quantiles.

## Reproducibility Pointers

Grid config:

```text
application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_20260601.yaml
```

Ignored local run root:

```text
application/data_local/pricefm/runs/pricefm_median_de_lu_reservoir_20260601
```

Ignored local freeze root:

```text
application/data_local/pricefm/authoritative/pricefm_median_de_lu_fold1_20260602
```

The freeze root contains compact summaries, a machine-readable promotion
manifest, and full copied artifacts for the three preserved reference runs.

## Selected Specification

| field | value |
|---|---:|
| region | `DE_LU` |
| fold | `1` |
| quantile | `0.50` |
| horizons | `1:96` |
| feature map | `window_reservoir_v1` |
| lead/lag window | `96` |
| reservoir depth | `1` actual, despite `d2n80x80` in run ID |
| reservoir units | `[80]` actual, despite `[80, 80]` in run ID |
| stored feature dimension | `80` |
| leakage `alpha` | `[0.70]` |
| spectral radius `rho` | `[0.90]` |
| input scale | `[0.50]` |
| seed | `20260601` |
| selected training origins | `3000` tail origins |
| prior | `RHS_NS` |
| RHS_NS `tau0` | `1.0e-3` |
| intercept shrinkage | disabled |
| VB iterations | minimum `50`, maximum `100` |
| chunking | exact, sequential, chunk size `2048` |
| warm start chain | normal scaled ridge -> normal RHS_NS -> Q-DESN AL -> Q-DESN exAL |

## Main Metrics

Original-unit test metrics for the selected run:

| method | AQL | MAE | RMSE |
|---|---:|---:|---:|
| Q-DESN AL RHS_NS exact chunked | `6.4964` | `12.9929` | `20.2575` |
| Q-DESN exAL RHS_NS exact chunked | `6.4974` | `12.9947` | `20.2913` |
| Normal DESN RHS_NS | `8.2182` | `16.4365` | `22.7749` |
| naive previous day | `14.0090` | `28.0181` | `42.8383` |
| Normal DESN scaled ridge | `14.5922` | `29.1844` | `38.2804` |
| naive previous 3-day average | `14.6444` | `29.2889` | `42.0183` |
| naive previous 7-day average | `14.6940` | `29.3880` | `40.9422` |

Relative to the best naive baseline, `naive1_prev_day`, the selected Q-DESN AL
RHS_NS model improves:

| metric | selected | naive1 | relative improvement |
|---|---:|---:|---:|
| AQL | `6.4964` | `14.0090` | `53.63%` |
| MAE | `12.9929` | `28.0181` | `53.63%` |
| RMSE | `20.2575` | `42.8383` | `52.71%` |

## Preserved Full Runs

The cleanup policy keeps full artifacts for these three runs:

| label | run | representative method | AQL | MAE | RMSE | reason |
|---|---|---|---:|---:|---:|---|
| overall winner | `res_smoke_d2n80x80_a0p70_r0p90_in0p50_seed20260601` | `qdesn_al_rhs_ns_exact_chunked` | `6.4964` | `12.9929` | `20.2575` | best completed result |
| best exAL / normal reference | `res_smoke_d1n120_a0p70_r0p90_in0p50_seed20260601` | `qdesn_exal_rhs_ns_exact_chunked` | `6.4973` | `12.9946` | `20.3540` | best exAL and best normal RHS_NS source |
| P1 representative winner | `res_p1_d2n240x240_l096_alpha0p5_rho0p8_input_scale0p25` | `qdesn_exal_rhs_ns_exact_chunked` | `6.8550` | `13.7101` | `20.9087` | representative of the tied priority-1 winners |

The priority-1 grid had `18` tied Q-DESN exAL RHS_NS winners at AQL `6.8550`.
After the reservoir-control propagation audit, this tie set should be treated
as pre-fix diagnostic evidence only. It is not valid evidence that the intended
`alpha`, `rho`, `input_scale`, or depth choices are equivalent.

## Iteration And Convergence Summary

Across the `67` completed cells in the reservoir grid:

| method | cells | iteration range | converged cells | median train seconds | max train seconds |
|---|---:|---:|---:|---:|---:|
| normal scaled ridge | `67` | `1` | `67` | `26.662` | `61.528` |
| normal RHS_NS | `67` | `100` | `0` | `64.745` | `157.890` |
| Q-DESN AL RHS_NS exact chunked | `67` | `50-68` | `67` | `3867.178` | `10923.648` |
| Q-DESN exAL RHS_NS exact chunked | `67` | `50` | `67` | `3817.129` | `7797.120` |

The normal RHS_NS non-convergence flag means it exhausted the current
`max_iter = 100` criterion, not that the downstream Q-DESN fits failed. The
Q-DESN AL/exAL fits converged under the current convergence gate.

## PriceFM Reference Context

The local upstream PriceFM clone reports for `DE_LU` phase-I pretraining:

| source | AQL | MAE | RMSE |
|---|---:|---:|---:|
| upstream PriceFM phase-I pretraining, `DE_LU` | `5.6752` | `14.2119` | `24.3393` |

This is useful context but not a direct apples-to-apples benchmark. The upstream
PriceFM reference is a multi-region neural model with its own quantile set and
training/evaluation protocol. The current DESN/Q-DESN run is single-region,
fold-1, median-only, and tail-limited. A direct comparison requires running the
upstream PriceFM forecast code under the same region, fold, horizon, quantile,
and metric reducer.

## Diagnostic Figures

The freeze keeps figure copies under:

```text
application/data_local/pricefm/authoritative/pricefm_median_de_lu_fold1_20260602/overall_winner/figures
application/data_local/pricefm/authoritative/pricefm_median_de_lu_fold1_20260602/exal_normal_best_smoke/figures
application/data_local/pricefm/authoritative/pricefm_median_de_lu_fold1_20260602/p1_representative_winner/figures
```

The selected run includes:

- `test_fit_qdesn_al_rhs_ns_exact_chunked.png`
- `test_fit_qdesn_exal_rhs_ns_exact_chunked.png`
- `test_fit_normal_rhs_ns.png`
- `test_fit_normal_scaled_ridge.png`
- `test_fit_first14_origins.png`
- `trace_elbo.png`
- `trace_parameter_diagnostics.png`
- `final_parameter_summary.png`

## Artifact Hygiene

The local freeze was created before cleanup. Its promotion manifest records:

| item | count / size |
|---|---:|
| completed metric summaries | `67` |
| priority-1 metric summaries | `65` |
| cleanup candidates | `704` files |
| cleanup candidate size | `1585.21 MB` |

Cleanup policy:

- preserve all metrics, method summaries, trace summaries, logs, configs,
  manifests, and compact documentation;
- preserve all full artifacts for the three selected reference runs;
- remove only loser heavy adapter rows, prediction CSVs, figures, and R binary
  model artifacts listed in the dry-run manifest;
- do not touch unrelated ongoing validation or GloFAS work.

Post-cleanup validation on 2026-06-02:

| item | result |
|---|---:|
| deleted files | `704` |
| deleted size | `1585.21 MB` |
| missing dry-run paths at deletion time | `0` |
| run-root size after cleanup | `904 MB` |
| metric summaries retained | `67` |
| method summaries retained | `67` |
| trace summaries retained | `67` |
| figures retained in original run root | `24` |
| figures retained in local freeze | `24` |
| PriceFM `.rds` / `.RDS` / `.rda` / `.RData` files under run root | `0` |

Each preserved full run retained its original prediction CSV and its `8`
diagnostic figures in both the original run root and the local freeze copy.

## Reproduction Commands

Regenerate grid configs:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_20260601.yaml \
  --write
```

Rerun the reservoir grid with the same workflow:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_20260601.yaml \
  --priorities 0 1 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

## Next Scientific Step

Use this as the local DE_LU fold-1 median pre-fix metric baseline. The next
clean comparison stage is a corrected reservoir relaunch:

1. run a corrected priority-0 smoke and inspect the manifests/figures;
2. run a corrected focused reservoir grid around the promising small-reservoir
   region;
3. then do seed/fold robustness for the corrected winner;
4. only then expand to more regions or additional quantiles.
