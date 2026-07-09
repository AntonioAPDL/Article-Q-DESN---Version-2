# PriceFM Modeling and Evaluation Audit

Date: 2026-05-30

This note audits the local PriceFM data layer and maps the related PriceFM
paper protocol to the Normal DESN and Q-DESN tools now available in this
workspace. It is a planning and readiness document only. No PriceFM model run
is launched here.

## Local Paper Snapshot

The referenced paper was downloaded locally:

```text
application/data_local/pricefm/external/papers/pricefm_arxiv_2508.04875v4_20260508.pdf
application/data_local/pricefm/external/papers/pricefm_arxiv_2508.04875v4_20260508.txt
```

Local hashes:

```text
PDF SHA256:  c3572435b65625179fb0d3e4c656b488942a8faae7f36f647934967b997ea8b7
Text SHA256: b685e025ca07dcfe685d020b5a1e5e7c9cc696f038fd1c1f400c84a96c6a4281
```

The paper is PriceFM: Foundation Model for Probabilistic Electricity Price
Forecasting, arXiv:2508.04875v4, dated 2026-05-08 in the downloaded version.

The PDF and extracted text live under ignored local PriceFM data paths. They
are local reference artifacts, not tracked source files.

## Paper Protocol Summary

The paper studies probabilistic day-ahead electricity price forecasting across
European bidding regions.

Core data and task:

- 24 countries and 38 bidding regions;
- date span labeled 2022-01-01 to 2026-01-01;
- 15-minute resolution;
- target is a 96-step next-day price trajectory;
- default quantile set is `{0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90}`;
- historical price window length `L = 96` in the main setting;
- exogenous variables are day-ahead forecasts of load, solar, and wind;
- wind is the sum of onshore and offshore wind in the paper abstraction.

The forecasting origin is day `D`; the delivery target is day `D + 1`, with
96 quarter-hour prices. The setup uses prices known before the forecast origin
plus forward-looking exogenous forecasts for the delivery day.

Rolling evaluation:

| Fold | Train | Validation | Test |
|---:|---|---|---|
| 1 | 2022-01-01 to 2024-09-01 | 2024-09-01 to 2025-01-01 | 2025-01-01 to 2025-05-01 |
| 2 | 2022-01-01 to 2025-01-01 | 2025-01-01 to 2025-05-01 | 2025-05-01 to 2025-09-01 |
| 3 | 2022-01-01 to 2025-05-01 | 2025-05-01 to 2025-09-01 | 2025-09-01 to 2026-01-01 |

The three test windows jointly cover one year.

Scaling:

- robust scaling via Scikit-Learn `RobustScaler`;
- scalers are fit on the training split only;
- validation and test splits are transformed by the fitted train scalers.

Metrics:

- Average Quantile Loss, `AQL`;
- Average Quantile Crossing Rate, `AQCR`;
- median-based `MAE`;
- median-based `RMSE`.

The paper also reports leave-one-region-out evaluation against generic
foundation models, and ablations over backward-looking window size, number of
experts, graph cutoff, graph mask, and quantile-head design.

## Local PriceFM Data Snapshot

The current local data layer is under:

```text
application/data_local/pricefm/
```

Source manifests:

```text
Hugging Face repo:       RunyaoYu/PriceFM
Dataset revision:        68b032a923e518bcf88edde906035ea223870aee
PriceFM GitHub commit:   c72d1228bde80417d5cc782521328e02ab5401c3
FINAL.csv SHA256:        98f596deba7ffaf0edd21e78e1a779256ab24dda5463d445f081e1ee4ab3a54a
License:                 cc-by-4.0
```

Raw/interim shape:

```text
raw file:       application/data_local/pricefm/raw/FINAL.csv
rows:           140257
raw columns:    191
interim columns:192, including derived market_time
regions:        38
raw features:   generation, load, price, solar, wind
```

Timestamp audit:

```text
time_utc range:     2021-12-31 23:00:00+00:00 to 2025-12-31 23:00:00+00:00
market_time:        time_utc + 1 hour
market_time range:  2022-01-01 00:00:00+00:00 to 2026-01-01 00:00:00+00:00
frequency:          15min
missing timestamps: 0
extra timestamps:   0
duplicate stamps:   0
```

The `market_time = time_utc + 1 hour` convention is the local bridge from the
released UTC timestamp to the paper calendar labels. All splits and windows
must record this convention.

Column/range audit:

```text
region-feature records:       190
present columns:              190
max nan_rate:                 0
nonzero missingness columns:  0
constant columns:             10
price min across regions:    -500
price max across regions:     4000
```

Constant or all-zero columns are expected for unavailable solar or wind in some
regions. They should be retained and documented, not silently removed.

Current local split row counts:

| Fold | Split | Rows |
|---:|---|---:|
| 1 | train | 93504 |
| 1 | val | 11712 |
| 1 | test | 11520 |
| 2 | train | 105216 |
| 2 | val | 11520 |
| 2 | test | 11808 |
| 3 | train | 116736 |
| 3 | val | 11808 |
| 3 | test | 11712 |

The split counts match half-open market-time intervals.

Current local windows:

Only the DE_LU fold-1 pilot windows are materialized:

| Split | Origins | X_lag | X_lead | Y | Context |
|---|---:|---|---|---|---|
| train | 973 | `[973, 96, 4]` | `[973, 96, 3]` | `[973, 96]` | train |
| val | 122 | `[122, 96, 4]` | `[122, 96, 3]` | `[122, 96]` | train+val |
| test | 120 | `[120, 96, 4]` | `[120, 96, 3]` | `[120, 96]` | train+val+test |

The lag features are `price`, `load`, `solar`, and `wind`. The lead features
are `load`, `solar`, and `wind`. The response is `price`. The raw
`generation` feature is preserved and audited but excluded from default model
windows to match the paper's core feature abstraction.

Exploratory figures:

```text
application/data_local/pricefm/figures/region_feature_overview/
```

There are 38 region-level PNG overview figures plus manifest/index files.

## Local Tests Run During This Audit

Metadata-only PriceFM tests:

```text
application/tests/test_pricefm_config.py: 7 passed
```

Data-present PriceFM tests:

```text
application/tests/test_pricefm_audit.py:   passed
application/tests/test_pricefm_splits.py:  passed
application/tests/test_pricefm_windows.py: passed
application/tests/test_pricefm_eda.py:     passed
Total data-present tests: 23 passed
```

These tests verify config contracts, raw/interim audit artifacts, split
boundaries, pilot window shapes, context/no-leakage metadata, and EDA outputs.

## What Is Already Ready

The data layer is ready for a narrow modeling-adapter design pass:

- raw source is pinned by revision and SHA;
- all 38 regions and 5 raw features are present;
- no timestamp gaps, duplicates, or schema holes were found;
- paper-style rolling folds are materialized;
- train-only per-region scalers exist for all three folds;
- DE_LU fold-1 L96/H96 pilot windows are built and tested;
- region-feature exploratory figures exist for all 38 regions;
- upstream adjacency metadata is available in the pinned PriceFM Git clone;
- the paper PDF and extracted text are locally archived.

## What Is Not Yet Ready

The current PriceFM windows are not yet Q-DESN or Normal DESN model inputs.
They are data-layer windows only.

Missing pieces before model runs:

1. A formal PriceFM-to-DESN modeling adapter.
2. A metric implementation that exactly matches the paper's AQL/AQCR/MAE/RMSE
   definitions and can inverse-transform scaled outputs.
3. Naive baselines matching the paper's Naive1/Naive2/Naive3 definitions.
4. Multi-quantile orchestration for Q-DESN AL/exAL.
5. A decision about direct-horizon versus recursive forecasting.
6. A decision about target-region-only versus graph-neighborhood versus
   all-region input features.
7. All-region and all-fold window or on-demand window construction.
8. A reproducible run manifest for every model, fold, region, quantile, and
   horizon policy.

## Mapping PriceFM To Our Models

### Normal DESN

The Normal DESN scaled-ridge readout is a conditional-mean Gaussian baseline.
On PriceFM, it can serve three roles:

1. A strong point-forecast baseline for the median trajectory.
2. A Gaussian predictive distribution baseline if posterior predictive draws
   are calibrated enough for AQL across multiple quantiles.
3. An informed initializer for Q-DESN AL/exAL readouts when design matrices are
   identical.

Current limitations:

- Normal DESN recursive forecast paths currently support raw-y-lag reservoir
  designs and fail early for exogenous/decomposition forecast controls.
- For PriceFM, the clean first stage should use a fixed-design direct-horizon
  adapter rather than the existing recursive Normal forecast path.
- Normal RHS/RHS_NS remains approximate and should be reported separately from
  exact scaled-ridge.

### Q-DESN AL/exAL

Q-DESN AL/exAL already supports:

- fixed DESN feature maps;
- ridge/RHS/RHS_NS beta priors;
- full-data and exact-chunked VB;
- stochastic/hybrid AL;
- supported hybrid exAL rows;
- Normal DESN warm-start initialization;
- posterior predictive sampling for fitted readouts.

Current limitations for PriceFM:

- `qdesn_fit_vb()` is scalar-response and quantile-specific.
- A paper-style output is a 96-step by 7-quantile trajectory.
- Therefore the adapter must orchestrate many scalar fits or define a stacked
  fixed-design problem with explicit horizon and quantile metadata.
- Independent quantile fits may cross; AQCR must be reported. A monotonic
  post-processing option may be useful, but must be labeled.

## Recommended Modeling Adapter Design

Use a direct-horizon fixed-design adapter first.

For each target region `r`, fold `f`, forecast origin `i`, horizon `h`, and
quantile `tau`, create a supervised row:

```text
response: y_{r, i, h}
features: DESN map built from available lag and forward exogenous windows
target metadata: region r, fold f, origin i, horizon h, tau
```

This avoids recursive leakage and matches the paper's day-ahead setup more
directly than a recursive one-step forecaster. It also lets the adapter use
the known day-ahead load/solar/wind forecast path for all 96 delivery steps.

Initial feature policies:

1. `target_only`: use only the target region's price/load/solar/wind lag window
   plus its load/solar/wind lead window.
2. `k_hop`: use target region plus graph neighbors within cutoff `delta`.
3. `all_regions`: use all regions, mainly as a stress/comparison row.

For Q-DESN, fit independent readouts for:

```text
tau in {0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90}
h in 1:96
```

For the first smoke, reduce scope:

```text
region: DE_LU
fold: 1
horizons: {1, 24, 48, 72, 96} or a contiguous small block
taus: {0.10, 0.50, 0.90}
feature policy: target_only
models: Normal DESN ridge, Q-DESN AL ridge, Q-DESN exAL ridge
```

Only after the smoke passes should we expand to all 96 horizons and all 7
quantiles.

## Paper-Comparable Evaluation Plan

### Stage 0: Audit Lock

Track a small audit note and keep the downloaded PDF in ignored local storage.
Do not commit raw PriceFM data, Parquet, NPZ, scalers, figures, or PDFs.

### Stage 1: Metrics and Baselines

Implement small, tested metric helpers:

- AQL over `(origin, region, horizon, quantile)`;
- AQCR over adjacent sorted quantiles;
- MAE and RMSE at the median quantile;
- optional per-region and per-fold breakdowns.

Implement naive baselines:

- `Naive1`: previous day price path;
- `Naive2`: average of previous 3 daily price paths;
- `Naive3`: average of previous 7 daily price paths;
- empirical quantile construction per delivery horizon for probabilistic naive
  outputs, matching the paper's intent.

Validation gates:

- metric parity against simple hand-computed examples;
- no quantile crossing for constructed monotone examples;
- inverse scaling restores original price units;
- naive forecasts use only historical prices before the origin.

### Stage 2: Adapter Shape Smoke

Add an adapter script or module that reads the existing PriceFM scaled splits
and builds model-ready fixed-design rows for one region/fold.

Required outputs:

```text
application/data_local/pricefm/processed/model_adapters/desn_direct_horizon/
```

Suggested ignored artifacts:

- design matrix shards;
- row manifest CSV;
- feature manifest JSON;
- no-leakage audit JSON.

Validation gates:

- lag price times are strictly before origin;
- lead exogenous times are within the delivery day;
- response times equal the requested horizon within the delivery day;
- train/val/test origins remain inside the paper fold windows;
- design row count matches manifest;
- deterministic under fixed seed and config.

### Stage 3: DE_LU Fold-1 Model Smoke

Run a tiny paper-style comparison:

- DE_LU only;
- fold 1 only;
- target-only features;
- horizons `{1, 24, 48, 72, 96}`;
- quantiles `{0.10, 0.50, 0.90}`;
- small DESN settings;
- Normal DESN ridge;
- Q-DESN AL ridge;
- Q-DESN exAL ridge;
- exact chunking equivalence for one row.

Validation gates:

- all fits finite;
- predictions inverse-scaled to EUR/MWh;
- AQL/AQCR/MAE/RMSE written;
- exact chunked equals unchunked where tested;
- no generated result files are committed.

### Stage 4: Full DE_LU Fold-1

Expand to:

- all 96 horizons;
- all 7 paper quantiles;
- target-only features;
- Normal DESN ridge;
- Q-DESN AL/exAL ridge;
- optional RHS_NS sensitivity.

This gives the first meaningful paper-like result without claiming all-Europe
coverage.

### Stage 5: All Regions, Three Folds

Only after Stage 4 passes:

- expand to all 38 regions;
- run all three folds;
- aggregate metrics exactly as the paper does;
- produce per-region maps/tables if needed.

This is the first stage that can be described as paper-protocol comparable,
though still comparing different model classes rather than reproducing
PriceFM's neural architecture.

### Stage 6: Graph/Spatial Experiments

Use the pinned PriceFM adjacency list to compare:

- target-only inputs;
- `delta = 1` graph neighbors;
- `delta = 2` graph neighbors;
- region-specific validation-selected `delta`;
- all-region inputs.

This is the DESN analogue of the paper's graph cutoff and sparse-mask study.
It should not be bundled into the first modeling smoke.

## Model Scope Recommendations

Recommended first model set:

1. Naive1/2/3 baselines.
2. Normal DESN scaled ridge.
3. Q-DESN AL ridge full-data/exact-chunked.
4. Q-DESN exAL ridge full-data/exact-chunked.
5. Q-DESN RHS_NS only as a regularization sensitivity after ridge is stable.

Do not start with:

- stochastic/hybrid modes;
- diagonal covariance modes;
- rolling/online/PAP;
- full all-region graph neighborhoods;
- all three folds and all regions in the same first implementation.

Those modes are implemented elsewhere, but they add interpretation burden before
the PriceFM adapter itself is validated.

## Important Differences From The PriceFM Paper

These must be stated in any future report:

- PriceFM is a neural multi-region, multi-quantile, graph-masked foundation
  model. Our Q-DESN/Normal DESN tools are fixed-feature Bayesian readout models.
- PriceFM jointly produces all quantiles with a hierarchical non-crossing head.
  Independent Q-DESN quantile fits can cross unless a monotone correction is
  added and labeled.
- PriceFM jointly uses regional embeddings and graph masks. Our first adapter
  should start target-only, then add graph neighborhoods as explicit feature
  policies.
- PriceFM's full-shot table averages across all 38 regions and all test folds.
  A DE_LU/fold-1 smoke is only a readiness gate, not a paper-comparable result.
- PriceFM's leave-one-region-out setting is a foundation-model generalization
  test. Our current models do not yet have a shared multi-region training
  mechanism that makes this comparison natural.

## Recommended Next Implementation Prompt

The next safe task should be:

```text
Implement PriceFM Stage 1 and Stage 2 only:
metrics, naive baselines, and a fixed-design direct-horizon adapter smoke for
DE_LU fold 1. Do not fit full Q-DESN models yet except optional tiny adapter
smoke tests. Keep all outputs ignored and add tests for metrics, inverse
scaling, split/window leakage, and design metadata.
```

After that passes, run the DE_LU fold-1 model smoke.
