# PriceFM DESN Full-Run Orchestration

Date: 2026-05-30

## Purpose

This note records the production orchestration layer for the PriceFM DESN
comparison. It prepares the full run but does not launch the full model batch.

The implemented workflow is designed for:

- all 38 PriceFM regions;
- folds 1, 2, and 3;
- all 96 day-ahead horizons;
- quantiles `0.05`, `0.25`, and `0.50`;
- target-only PriceFM features;
- `window_desn_v1` with `m = 30`;
- Q-DESN-style AL/exAL RHS_NS readouts with exact chunked VB;
- Normal DESN scaled ridge and RHS_NS baselines;
- Naive1/Naive2/Naive3 calibrated baselines.

The recommended first production launch is the median-only warm-start run:

```text
application/config/pricefm_desn_model_full_median_warmstart.yaml
```

It keeps the same region/fold/horizon/DESN specification but targets only
quantile `0.50`. The three-quantile config remains available as:

```text
application/config/pricefm_desn_model_full.yaml
```

## Scale

The raw local PriceFM panel has:

| Quantity | Count |
|---|---:|
| 15-minute timestamps | 140,257 |
| Regions | 38 |
| Variables per region | 5 |
| Region-variable series | 190 |
| Region-variable scalar observations | 26,648,830 |
| Price target scalar observations | 5,329,766 |

Full all-horizon stacked modeling scale:

| Fold | Split | DESN origins | Stacked rows per region |
|---:|---|---:|---:|
| 1 | train | 973 | 93,408 |
| 1 | val | 122 | 11,712 |
| 1 | test | 120 | 11,520 |
| 2 | train | 1,095 | 105,120 |
| 2 | val | 120 | 11,520 |
| 2 | test | 123 | 11,808 |
| 3 | train | 1,215 | 116,640 |
| 3 | val | 123 | 11,808 |
| 3 | test | 122 | 11,712 |

The production run is intentionally one region/fold cell per job, not one
monolithic all-region fit.

## Added Files

Tracked configuration:

```text
application/config/pricefm_desn_model_full.yaml
application/config/pricefm_desn_model_full_median_warmstart.yaml
```

Tracked helpers/scripts:

```text
application/scripts/pricefm/pricefm_full_run.py
application/scripts/pricefm/10_run_desn_model_full.py
application/scripts/pricefm/11_summarize_desn_model_full.py
```

The smoke summarizer now also writes:

```text
metric_by_horizon.csv
metric_by_horizon_group.csv
warm_start_diagnostics.csv, when warm starts are enabled
```

## Warm-Start Chain

Warm starts are initialization/workflow aids only. They do not change the model
target if each VB fit is still run to convergence.

The median warm-start config uses:

```text
RHS_NS tau0 = 1.0e-4, shrink_intercept = false
Normal scaled ridge
  -> Normal RHS_NS
    -> Q-DESN AL RHS_NS tau 0.50
      -> Q-DESN exAL RHS_NS tau 0.50
```

The Q-DESN warm start passes only shared quantities:

- beta mean;
- beta covariance;
- RHS/RHS_NS beta-prior state;
- sigma scale, when finite.

It deliberately does not pass local AL/exAL latent variables by default because
those are row-level and tau/likelihood-specific. It also sets
`fallback_to_cold: false`, so a bad warm-start contract fails visibly instead of
silently changing the launch.

Tracked tests:

```text
application/tests/test_pricefm_full_run_config.py
application/tests/test_pricefm_full_run_orchestrator.py
application/tests/test_pricefm_full_run_summary.py
```

## Storage Policy

The existing DE_LU/fold-1 smoke implies that keeping all generated artifacts as
CSV would use roughly 15 GiB for the full comparison. This is affordable on the
current machine, but most of that footprint is avoidable.

The production launcher therefore defaults to:

- keep compressed PriceFM window NPZ files;
- keep per-cell configs, logs, row metadata, predictions, metrics, and compact
  reports;
- remove large per-cell `X_*.csv` adapter matrices after successful model and
  summary completion unless `keep_matrices_after_success: true`.

All generated outputs remain under ignored `application/data_local/pricefm/`.

## Commands

Dry-run the production cell plan:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/10_run_desn_model_full.py \
  --config application/config/pricefm_desn_model_full_median_warmstart.yaml \
  --dry-run true
```

Build missing all-region windows before the real launch:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/05_build_windows.py \
  --config application/config/pricefm_data_pipeline.yaml \
  --pilot-only false \
  --resume true \
  --force false
```

Real launch command, intentionally not run in this implementation pass:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/runs/desn_model_full_median_warmstart_20260530/full.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/10_run_desn_model_full.py \
  --config application/config/pricefm_desn_model_full_median_warmstart.yaml \
  --jobs 4 \
  --resume true
```

Aggregate completed cells:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/11_summarize_desn_model_full.py \
  --config application/config/pricefm_desn_model_full_median_warmstart.yaml
```

## Validation Gates Before Launch

Before launching the full model batch:

1. Run metadata and full-run unit tests.
2. Build all missing PriceFM windows.
3. Run the launcher in `--dry-run true` mode and verify `114` planned cells.
4. Confirm generated outputs are ignored.
5. Confirm no unrelated validation jobs are threatened.
6. Launch with `--jobs 4` first; increase only after observing memory.

## Not Run

This pass deliberately did not:

- build all-region windows;
- run the full 114-cell model batch;
- compare paper-level results;
- introduce Q-DESN ridge;
- introduce stochastic/hybrid PriceFM inference;
- change the GloFAS application workflow.
