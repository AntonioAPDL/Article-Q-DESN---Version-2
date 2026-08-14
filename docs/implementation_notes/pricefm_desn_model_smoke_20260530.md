# PriceFM DESN Model Smoke

Date: 2026-05-30

This note records the first end-to-end PriceFM-to-DESN modeling smoke. It is a
readiness gate, not a full PriceFM-paper comparison.

## Scope

Data:

```text
region: DE_LU
fold: 1
feature policy: target_only
layout: stacked origin-by-horizon rows
horizons: 1, 24, 48, 72, 96
quantiles: 0.05, 0.25, 0.50
```

Adapter output:

```text
application/data_local/pricefm/processed/model_adapters/desn_direct_horizon/de_lu_fold1_h5_window_desn_v1/
```

Run output:

```text
application/data_local/pricefm/runs/desn_model_smoke_20260530/
```

Both output roots are ignored local artifacts.

## Implementation

Tracked files added:

```text
application/config/pricefm_desn_model_smoke.yaml
application/scripts/pricefm/pricefm_metrics.py
application/scripts/pricefm/pricefm_baselines.py
application/scripts/pricefm/pricefm_desn_adapter.py
application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py
application/scripts/pricefm/08_run_desn_model_smoke.R
application/scripts/pricefm/09_summarize_desn_model_smoke.py
application/tests/test_pricefm_metrics.py
application/tests/test_pricefm_baselines.py
application/tests/test_pricefm_desn_adapter.py
application/tests/test_pricefm_desn_model_smoke_config.py
```

The adapter creates one row per `(forecast origin, delivery horizon)`. The
first smoke has:

| Split | Origins | Horizons | Rows | Features |
|---|---:|---:|---:|---:|
| train | 973 | 5 | 4865 | 31 |
| val | 122 | 5 | 610 | 31 |
| test | 120 | 5 | 600 | 31 |

The feature map is `window_desn_v1`, a compact deterministic tanh random-feature
map over the scaled lag window, scaled lead window, and horizon features. The
readout engines are the package static readout APIs:

- `normal_desn_fit(X, y, ...)` for Normal DESN scaled ridge and Normal RHS_NS;
- `exal_ldvb_fit(y, X, p0, ...)` for AL/exAL RHS_NS quantile readouts.

The smoke intentionally does not call `qdesn_fit_vb()` directly on PriceFM 3D
windows. PriceFM window-to-design mapping is application-side.

## Methods

The report includes seven methods:

- `naive1_prev_day`;
- `naive2_prev3_avg`;
- `naive3_prev7_avg`;
- `normal_scaled_ridge`;
- `normal_rhs_ns`;
- `qdesn_al_rhs_ns_exact_chunked`;
- `qdesn_exal_rhs_ns_exact_chunked`.

Q-DESN ridge is intentionally not included. The Q-DESN-style readouts use
RHS_NS with `tau0 = 0.01`, `shrink_intercept = false`, and exact chunked VB.

## Commands

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py \
  --smoke-config application/config/pricefm_desn_model_smoke.yaml \
  --force true

mkdir -p application/data_local/pricefm/runs/desn_model_smoke_20260530

/usr/bin/time -v \
  -o application/data_local/pricefm/runs/desn_model_smoke_20260530/time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/pricefm/08_run_desn_model_smoke.R \
  --smoke-config application/config/pricefm_desn_model_smoke.yaml \
  --force true

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/09_summarize_desn_model_smoke.py \
  --smoke-config application/config/pricefm_desn_model_smoke.yaml
```

## Results

Original-unit test metrics:

| Method | AQL | AQCR | MAE | RMSE |
|---|---:|---:|---:|---:|
| naive1_prev_day | 10.2568 | 0 | 27.7257 | 43.0705 |
| naive3_prev7_avg | 10.5590 | 0 | 28.1502 | 40.7129 |
| naive2_prev3_avg | 10.6428 | 0 | 28.4067 | 41.9968 |
| qdesn_al_rhs_ns_exact_chunked | 11.4369 | 0.00167 | 31.6960 | 46.0914 |
| qdesn_exal_rhs_ns_exact_chunked | 11.5691 | 0 | 31.6998 | 45.9995 |
| normal_rhs_ns | 12.6253 | 0 | 33.5016 | 47.1199 |
| normal_scaled_ridge | 75.4518 | 0 | 49.4036 | 66.2071 |

Exact chunking gate:

| Likelihood | Prior | Tau | Rows | Max beta mean diff | Max beta cov diff | Max prediction diff | Tolerance | Passed |
|---|---|---:|---:|---:|---:|---:|---:|---|
| AL | RHS_NS | 0.25 | 600 | 6.95e-13 | 2.57e-14 | 3.33e-13 | 1e-6 | true |

Model fit summary:

| Method | Converged | Iter | Train seconds |
|---|---:|---:|---:|
| normal_scaled_ridge | true | 1 | 0.105 |
| normal_rhs_ns | true | 20 | 0.673 |
| qdesn_al_rhs_ns_exact_chunked | true | 55 | 5.132 |
| qdesn_exal_rhs_ns_exact_chunked | true | 64 | 8.253 |

Runtime:

```text
R smoke elapsed wall time: 0:34.50
Max RSS: 563600 KB
```

The naive baselines are strong on this tiny selected-horizon gate. That is an
empirical smoke result, not a model-selection conclusion. The important
readiness result is that the adapter, metrics, inverse scaling, Normal DESN
readouts, Q-DESN-style AL/exAL RHS_NS readouts, exact chunked VB, and report
generation all ran together without nonfinite states.

## Tests

Metadata/unit tests:

```text
application/tests/test_pricefm_config.py
application/tests/test_pricefm_metrics.py
application/tests/test_pricefm_baselines.py
application/tests/test_pricefm_desn_model_smoke_config.py
16 passed
```

Data-present tests:

```text
application/tests/test_pricefm_audit.py
application/tests/test_pricefm_splits.py
application/tests/test_pricefm_windows.py
application/tests/test_pricefm_eda.py
application/tests/test_pricefm_desn_adapter.py
25 passed
```

`git diff --check` passed.

## Next Step

The next scientific expansion should be DE_LU/fold-1 all-96-horizon
`window_desn_v1` with the same method set. Keep exact chunked VB for Q-DESN
readouts and measure runtime/memory before adding any approximate batching.
