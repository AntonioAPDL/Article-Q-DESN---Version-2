# PriceFM Median Warm-Start Chain

Date: 2026-05-30

## Purpose

This note documents the PriceFM median-only warm-start chain prepared before
the full production launch. Warm starts are initialization aids only; they do
not change the target when the downstream VB fits are still run to convergence.

## Configuration

Primary config:

```text
application/config/pricefm_desn_model_full_median_warmstart.yaml
```

Scope:

```text
regions: all 38 PriceFM regions
folds: 1, 2, 3
horizons: 1:96
quantiles: 0.50 only
feature map: window_desn_v1
feature dimension: m = 30
prior: RHS_NS
tau0: 1.0e-4
exact chunking: enabled for Q-DESN AL/exAL
```

## Warm-Start Chain

For each region/fold cell:

```text
Normal scaled ridge
  -> Normal RHS_NS
    -> Q-DESN AL RHS_NS tau 0.50
      -> Q-DESN exAL RHS_NS tau 0.50
```

The Q-DESN warm start passes:

- beta posterior mean;
- beta posterior covariance;
- RHS/RHS_NS beta-prior state;
- sigma scale, when finite.

It does not pass local AL/exAL latent states by default. These are
row-level and tau/likelihood-specific. They can only be safely reused when the
training rows, row order, likelihood family, tau, and local-variable semantics
match exactly, so they should stay disabled for the first production gate and
only be enabled after a separate A/B validation gate.

The median config has:

```text
fallback_to_cold: false
```

so incompatible warm starts fail visibly.

## Validation Smoke

An ignored DE_LU/fold-1 median smoke was run with the existing five selected
horizons:

```text
application/data_local/pricefm/runs/desn_model_median_warmstart_smoke_20260530/
```

Results:

| Method | Init source | Components | Converged | Iter |
|---|---|---|---:|---:|
| Normal RHS_NS | Normal scaled ridge | internal package default | true | 20 |
| Q-DESN AL RHS_NS tau 0.50 | Normal RHS_NS | beta + beta_state + sigma | true | 21 |
| Q-DESN exAL RHS_NS tau 0.50 | Q-DESN AL tau 0.50 | beta + beta_state + sigma | true | 27 |

Exact chunking gate:

| Likelihood | Prior | Tau | Rows | Max beta mean diff | Max beta cov diff | Max prediction diff | Tolerance | Passed |
|---|---|---:|---:|---:|---:|---:|---:|---|
| AL | RHS_NS | 0.50 | 600 | 5.21e-13 | 3.14e-14 | 7.60e-13 | 1e-6 | true |

Runtime:

```text
elapsed wall time: 0:25.60
max RSS: 566604 KB
```

## Launch Readiness

Before launching the median warm-start production run:

1. Build all missing PriceFM windows with `--resume true`.
2. Rerun the median full launcher dry run.
3. Confirm all 114 cells are either `planned` or `skipped_complete`.
4. Launch with conservative parallelism, starting at `--jobs 4`.

Commands:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/05_build_windows.py \
  --config application/config/pricefm_data_pipeline.yaml \
  --pilot-only false \
  --resume true \
  --force false

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/10_run_desn_model_full.py \
  --config application/config/pricefm_desn_model_full_median_warmstart.yaml \
  --dry-run true

/usr/bin/time -v \
  -o application/data_local/pricefm/runs/desn_model_full_median_warmstart_20260530/full.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/10_run_desn_model_full.py \
  --config application/config/pricefm_desn_model_full_median_warmstart.yaml \
  --jobs 4 \
  --resume true
```
