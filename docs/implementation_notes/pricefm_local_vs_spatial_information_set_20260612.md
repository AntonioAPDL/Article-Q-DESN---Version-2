# PriceFM Local Versus Spatial Information Set

Date: 2026-06-12

## Purpose

This note records a key interpretation point for the PriceFM comparison work:
the current DESN/Q-DESN runs match PriceFM's local covariate types, but they do
not yet match PriceFM's spatial information set.

This distinction matters when comparing our local Bayesian readout models to the
PriceFM paper/model results. If the local DESN/Q-DESN is competitive, that is a
strong result because it uses less information. If it falls short, one natural
next step is to add graph-neighbor inputs before drawing broad conclusions about
the Q-DESN modeling family.

## Current Local DESN/Q-DESN Setup

The current PriceFM DESN/Q-DESN adapter fits one target region at a time and
forecasts that same target region.

For target region `r`, the current input includes:

- lagged `r-price`,
- lagged `r-load`,
- lagged `r-solar`,
- lagged `r-wind`,
- lead/future `r-load`,
- lead/future `r-solar`,
- lead/future `r-wind`,
- horizon encoding.

The current input does not include:

- neighboring regions' price histories,
- neighboring regions' load/solar/wind histories,
- neighboring regions' lead load/solar/wind paths,
- PriceFM graph gates,
- a joint multi-region output distribution.

For `window_reservoir_v1`, the row-level feature vector is:

```text
intercept
+ reservoir_state(target-region lag window)
+ target-region lead covariates at horizon h
+ horizon features
```

The current runs are therefore best described as local target-region DESN/Q-DESN
baselines.

## PriceFM Information Set

PriceFM is spatial in its inputs and representation. It constructs tensors:

```text
X_lag_all
X_lead_all
graph_gate
```

where `X_lag_all` and `X_lead_all` can contain multiple input regions. The
graph gate restricts or weights which regions are active for a target region.

In the Phase II target-region setup, PriceFM still forecasts a target region's
future price path, but it can use information from graph-neighbor regions when
forming that forecast.

For a target region `r`, PriceFM is conceptually closer to:

```text
forecast target: r price path
inputs: r plus graph-neighbor lag/lead covariates
spatial mechanism: graph gate / graph-constrained pooling
```

This is not the same as a fully joint multivariate probabilistic output over all
regions. The spatial component is primarily in the input representation and
pooling, not necessarily in a joint output covariance over all markets.

## Comparison Interpretation

Use the following labels in future reports.

| Model family | Input scope | Output scope | Interpretation |
|---|---|---|---|
| Current DESN/Q-DESN | local target region only | target region path | Local Bayesian baseline |
| PriceFM Phase I/II | target plus selected graph-neighbor regions | target region path | Spatial-input target-region model |
| Future neighbor DESN/Q-DESN | target plus selected neighbors | target region path | Closer apples-to-apples spatial-input baseline |
| Future multi-output Q-DESN | multiple regions | multiple region paths | Separate research extension |

The current local comparison is still valuable, but it should not be described
as fully matching PriceFM's spatial information set.

## Why The Current Local Baseline Is Useful

The local-only baseline is useful because:

- it is simpler and easier to audit;
- it avoids graph-neighbor design decisions while DESN/Q-DESN behavior is being
  tuned;
- it gives a conservative benchmark for what the Bayesian readout can do using
  less information;
- if it beats or approaches PriceFM, the result is stronger than a spatially
  matched comparison would be;
- it provides a clean foundation for later neighbor-input extensions.

## Future Spatial Extension

The first spatial extension should not be a fully joint multi-output model. The
lowest-risk extension is a target-region model with neighbor covariates:

```text
For target region r:
  lag block  = lagged price/load/solar/wind for r and selected neighbors
  lead block = lead load/solar/wind for r and selected neighbors
  output     = target-region r price quantiles over horizons
```

Candidate neighbor policies:

- PriceFM graph degree 0: target region only; current local baseline.
- PriceFM graph degree 1: direct neighbors plus target.
- PriceFM graph degree 2: second-order neighbors plus target, if not too large.
- Custom energy-market neighbor set, if documented separately.

Candidate feature encodings:

- simple neighbor concatenation;
- graph-degree weighted concatenation;
- graph-mask weighted pooling before the reservoir;
- separate local and neighbor reservoir states;
- neighbor summary features, such as mean or graph-weighted mean over neighbors.

The first implementation should prefer simple concatenation or graph-weighted
summary features before attempting a larger architectural change.

## Required Documentation For Future Reports

Every PriceFM comparison report should state:

- whether the run is local-only or spatial-input;
- whether lead covariates are realized/oracle lead paths or operationally
  forecast-available covariates;
- which features are lagged and which are lead;
- which regions are used as inputs for each target region;
- whether the output is one target region or multiple regions;
- whether the comparison is local-baseline, spatial-input, or fully
  apples-to-apples with PriceFM's graph setting.

Recommended labels:

```text
input_scope = local_target_only
input_scope = graph_neighbor_inputs
input_scope = all_region_inputs

output_scope = target_region_path
output_scope = multi_region_path

lead_covariate_status = realized_ex_post
lead_covariate_status = operational_forecast_available
lead_covariate_status = unavailable
```

## Implementation References

Current local feature configuration:

- `application/config/pricefm_data_pipeline.yaml`
  - lag features: `price`, `load`, `solar`, `wind`
  - lead features: `load`, `solar`, `wind`
  - label: `price`

Current local window construction:

- `application/scripts/pricefm/05_build_windows.py`
  - constructs target-region `X_lag`, `X_lead`, and `Y`
  - uses lag rows before the forecast anchor
  - uses lead rows from the forecast anchor forward

Current local DESN/Q-DESN adapter:

- `application/scripts/pricefm/pricefm_desn_adapter.py`
  - for `window_reservoir_v1`, combines the target-region reservoir state,
    target-region lead covariates at horizon `h`, and horizon features.

PriceFM spatial references:

- `application/data_local/pricefm/external/PriceFM/PriceFM/model.py`
  - model inputs include `X_lag_all`, `X_lead_all`, and `graph_gate`.
- `application/data_local/pricefm/external/PriceFM/PriceFM/pipeline.py`
  - Phase II uses graph-neighbor knowledge for the target region.
- `application/data_local/pricefm/external/PriceFM/PriceFM/evaluation.py`
  - one-forecast evaluation loads lag/lead windows for multiple input countries
    and predicts the target country.

## Checklist Before Adding Neighbor Inputs

- [x] Finish the current local-only median grid.
- [x] Freeze a local region-fold median registry.
- [x] Document which local region-fold winners are competitive with PriceFM.
- [ ] Define the graph-neighbor policy to mimic PriceFM as closely as possible.
- [ ] Add adapter support for target plus neighbor lag/lead covariates.
- [ ] Preserve the existing local-only path as `input_scope =
      local_target_only`.
- [ ] Add no-leakage checks for neighbor lead windows.
- [ ] Add feature-manifest fields for input regions, graph degree, and
      neighbor policy.
- [ ] Run a small spatial smoke test for one region/fold.
- [ ] Compare local-only versus neighbor-input DESN/Q-DESN before promoting the
      spatial extension.

Current closeout reference:

- `docs/implementation_notes/pricefm_region_panel_median_local_ar_closeout_20260613.md`
- ignored local outputs:
  `application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_closeout_20260613`
