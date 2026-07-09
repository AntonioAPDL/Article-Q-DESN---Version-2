# GloFAS Q-DESN Model-Specification and Covariate Audit

Date: 2026-05-12

## Purpose

This audit reviews the current GloFAS discrepancy-calibration workflow before
choosing the next application model specification. The immediate motivation is
the Dec. 25, 2022 median VB pilot: all software and posterior-draw contract
checks passed, but the fitted corrected median was nearly constant across the
issued forecast horizon. The goal here is to determine whether this behavior is
caused by a data-lineage problem, a forecast-feature problem, a prior problem,
or an expected limitation of the current pilot specification.

The audit focuses on four questions.

1. Which inputs are actually used by the current Q-DESN fit?
2. Are precipitation, soil moisture, and other climate covariates wired into the
   model or only copied for diagnostics?
3. Would using the current covariate file in the forecast window create target
   leakage?
4. What is the best next model-design decision before launching an expensive
   full run?

## Current Decision

**Update on 2026-05-12.** The strict leakage-safe recommendation below has
been superseded for the next model-development pass. The active article-side
contract now uses only precipitation and soil moisture as readout covariates,
excludes GDPC and climate-index features, and uses the upstream GEFS blended
forecast construction for future covariate dates. This blend deliberately uses
realized future precipitation and soil moisture with an observed-weight
component. The choice is recorded as a controlled model-development contract,
not as a claim of operational no-leakage forecasting.

The earlier p50 pilot is healthy as a software contract, but it should not be
used as the scientific model specification. The next model-development step
should not be the full MCMC launch. The active implementation step is now the
article-side feature-contract pass: add direct output lags, add precipitation
and soil lag blocks from the blended GEFS timeline, keep a single readout
intercept, and verify the resulting design before any large fit.

The main reasons are:

- the current fitted Q-DESN design uses only the transformed USGS reference
  history to build reservoir features;
- the current prediction design uses the reservoir state at the forecast origin
  and a scaled horizon feature, so only one prediction feature varies across
  issued horizons;
- the issued GloFAS ensemble values affect the fit as G-source response rows,
  but the forecast design does not condition on raw GloFAS quantiles or
  meteorological forcing summaries as predictors;
- the copied `climate_covariates.csv` file contains realized covariates beyond
  the cutoff and should not be used directly in forecast-window design rows;
- the configured regularized horseshoe global scale is very tight
  (`tau0 = 1e-4`), which is scientifically defensible as a stress test but too
  aggressive to treat as the only candidate prior after the pilot result.

**Implementation update.** The large Dec. 25 profiles now include
`feature_contract.version = "0.2"`. The readout block contains one explicit
intercept, 1,000 fixed reservoir-state features, 180 direct output-lag
features, 122 precipitation and soil lag features, and one scaled-horizon
feature. The reservoir builder is called without a readout bias, so the
reservoir's internal input bias cannot appear as a duplicate intercept in the
Bayesian readout.

## Evidence From the Current Workflow

### Application Panel

The application panel is built in
`application/R/build_application_panel.R`. The loader reads three required
inputs:

- `reference_gauge`;
- `glofas_retrospective`;
- `glofas_ensemble`.

The current panel keeps only:

```text
origin_date, target_date, horizon, member, is_retrospective, is_ensemble,
y_reference, g_glofas, y_transformed, g_transformed, split, cutoff_id
```

The p50 pilot panel has 14,423 rows:

- 12,995 retrospective rows;
- 1,428 issued-ensemble rows;
- no precipitation, soil-moisture, GDPC, or GEFS columns.

This confirms that precipitation and soil moisture are not currently part of
the model panel.

### Q-DESN Feature Construction

The article-side Q-DESN feature adapter is
`application/R/build_qdesn_features.R`. It calls the engine with

```r
qdesn_build_design(y = y, desn_args = ...)
```

The only `y` passed to this call is `panel$y_transformed`, selected from the
retrospective reference rows. No `xreg`, precipitation, soil moisture, GDPC, raw
GloFAS quantile, or issued forecast summary is passed to the reservoir builder.

The engine-side `qdesn_build_design()` is also response-only in the current
branch. Other engine functions support `xreg_all`, `xreg_hist`, and
`xreg_future` for forecasting utilities, but the article-side discrepancy
adapter does not currently expose those capabilities.

### Prediction Design

The current posterior-draw prediction contract uses
`horizon_indexed_origin_state`. For an issued forecast at origin `T` and
horizon `h`, the earlier pilot prediction row was

```text
[reservoir_state_at_T, h / H]
```

where `H` is the configured maximum issued horizon. This is leakage-free because
it does not use future USGS observations, but it is intentionally weak.

Under `feature_contract.version = "0.2"`, the prediction row is richer:

```text
[readout_intercept, reservoir_state_at_T, y_lags_at_T,
 ppt_soil_lags_at_T_plus_h, h / H]
```

The output lags are anchored at `T`, while the precipitation and soil lags are
anchored at `T+h` because their forecast-window values come from the blended
GEFS forecast timeline.

The earlier p50 pilot prediction design confirmed the weak behavior:

- 28 prediction rows;
- 1002 features;
- all 28 rows use the same retrospective feature row, dated 2022-12-25;
- only 1 of 1002 prediction columns has nonzero variation across horizons.

This explains why the fitted posterior-model GloFAS median, discrepancy, and
corrected USGS median were nearly constant across the horizon.

### Posterior-Draw Contract

The posterior-draw table is valid. The p50 pilot produced 56,000 posterior-draw
prediction rows, 2,000 draws for each of 28 forecast dates, and satisfied

```text
q_y_draw = q_g_draw - d_g_draw
```

within numerical tolerance. Therefore, the issue is not the Bayesian prediction
contract. The issue is the information content of the forecast design and, to a
lesser extent, the current prior strength.

### Climate Covariates in the Bundle

The input bundle registers `climate_covariates` as optional. Its notes say that
realized precipitation, soil moisture, and GDPC/PCA covariates were copied for
source diagnostics and provenance checks.

For the Dec. 25, 2022 cutoff, the file

```text
application/data_local/frozen_inputs/authoritative_cutoffs/cutoff_date=2022-12-25/covariates/climate_covariates.csv
```

contains:

```text
date, precipitation_mm, soil_moisture, gdpc1
```

with dates from 1987-05-29 through 2026-02-24. There are 1,157 rows after the
2022-12-25 cutoff. These post-cutoff values are realized covariates, not
forecast-origin covariates. They are useful for diagnostics and retrospective
plots, but they should not be merged into forecast-window design rows unless an
availability rule proves that the value was known at the forecast origin.

### Forecast Covariate Artifacts

The upstream Jerez artifacts include leakage-safe forecast covariate candidates.
The local article-side copy contains GEFS and NWM handoff caches under

```text
application/data_local/upstream_jerez/gefs_nwm_forecast_runs/
```

For the 2022-12-25 issue date, GEFS handoff files include:

- `APCP_surface/gefs_members.csv`;
- `SOILW_0_0_1_m_below_ground/gefs_members.csv`;
- deeper `SOILW` layers.

The GEFS files are indexed by `init_date`, `lead_hours`, `target_time_utc`,
`target_date`, and ensemble member columns. They cover roughly 35 forecast days.
These files are the correct class of source for future precipitation and soil
moisture features. They still need an article-side materialization step that
reduces them into an explicit origin-target covariate panel and records all
reduction choices.

## Interpretation

### What the Current Pilot Has Proven

The current workflow proves that the article repo can:

- register the Dec. 25, 2022 GloFAS input bundle;
- build a leakage-free retrospective and issued-ensemble panel;
- construct the source-indexed discrepancy design;
- fit AL + RHS by VB in the engine;
- return posterior draws compatible with the same prediction contract as MCMC;
- score and plot the resulting posterior-draw predictions.

This is a strong infrastructure result.

### What the Current Pilot Has Not Proven

The current workflow has not proven that the current model specification is a
good scientific calibration model. In particular, it has not shown that the
forecast design contains enough origin-available information to learn
horizon-specific GloFAS quantiles or discrepancies. The p50 result suggests the
opposite: the fitted path is dominated by the origin state and shrinkage, while
raw GloFAS forecast variation is mostly ignored by the posterior-model
prediction.

### Why the Fit Is Poor

The most likely explanation is structural, not computational.

The model is currently asked to estimate

```text
q_G(T, h) = q_Y(T, h) + d_G(T, h)
```

from a prediction row that changes only through `h / H`. The issued GloFAS
ensemble values are included as G-source likelihood contributions, but all
members at a horizon share a simple feature row, and all horizons share the same
origin reservoir state. Under strong RHS shrinkage, the horizon coefficient is
small, so the posterior-model GloFAS quantile is nearly flat.

This does not mean the discrepancy-calibration model is wrong. It means the
current forecast-feature strategy is too austere for the application.

## Risk Audit

### Leakage Risk

The main leakage risk is not in the current fit. The current fit avoids future
USGS observations and does not use future realized climate covariates. The risk
would appear if we naively merged `climate_covariates.csv` by `target_date` for
forecast rows after 2022-12-25. That file contains realized post-cutoff
precipitation and soil moisture, so such a merge would leak future information.

Any new covariate workflow must distinguish:

- historical covariates available up to the forecast origin;
- forecast covariates issued at the origin for future target dates;
- realized future covariates used only for diagnostics after the fact.

### Prior Risk

The p50 pilot uses `rhs_tau0 = 1e-4`. The fitted VB state reports
`tau2 = 1e-8`, which is the square of the configured global scale. This is very
tight global shrinkage. It was already conservative for the earlier
2004-dimensional augmented readout, and the new large feature contract expands
the augmented readout to 2608 columns. The setting is useful as a conservative
pilot, but it should not be the only candidate prior.

The next prior comparison should include:

- the current RHS setting as a conservative reference;
- a looser RHS setting, such as `tau0 = 1e-3` or a calibrated effective-size
  value;
- a ridge baseline to check whether the near-flat path is primarily shrinkage
  induced.

### GloFAS-Anchor Risk

The current contract sets `q_g_source = posterior_model_quantile`. This is
fully model-based, but it can underuse the observed issued ensemble if the
forecast design is weak. For this application, there is a strong case for a
second, explicitly documented contract:

```text
q_g_source = issued_ensemble_quantile_or_bootstrap
```

Under that contract, the issued GloFAS ensemble supplies draw-level or
quantile-level information for `q_G(T,h,p0)`, and the Bayesian discrepancy
readout supplies `d_G(T,h,p0)`. Then

```text
q_Y_draw = q_G_draw - d_G_draw
```

still holds draw by draw, but the GloFAS forecast variation is not forced
through a weak origin-state design. A Bayesian bootstrap over GloFAS members is
a natural way to obtain `q_G_draw` while keeping the posterior-draw table
compatible with the current contract.

This should be treated as an additional contract, not as a silent change to the
current model.

## Recommended Next Specification Work

### Stage 1: Freeze a Covariate-Availability Contract

Create an article-side covariate contract with three tables.

1. `historical_covariates`
   - indexed by `date`;
   - allowed only through the origin date when constructing forecast rows;
   - used for retrospective reservoir states or lagged readout features.

2. `forecast_covariates`
   - indexed by `origin_date`, `target_date`, and `horizon`;
   - built from GEFS or NWM handoff files;
   - records variable, reduction, units, member handling, and source file hash.

3. `diagnostic_realized_covariates`
   - indexed by `date`;
   - may extend beyond the cutoff;
   - explicitly blocked from model-design rows for `target_date > origin_date`.

The schema should fail closed if a forecast row receives a realized
post-cutoff covariate.

### Stage 2: Build a Forecast-Covariate Panel

For the first implementation, keep the reduction simple and reproducible:

- GEFS `APCP` daily accumulation, reduced by ensemble median and upper quantile;
- GEFS `SOILW` top-layer daily value, reduced by ensemble median and upper
  quantile;
- optional NWM soil and precipitation summaries only after the GEFS path is
  stable.

The first pilot does not need the older noisy observed blend. The safer default
is to use direct forecast-issued GEFS summaries and document the reduction. If
the blended input is scientifically needed later, reproduce it as a separate
contract with its own tests and provenance.

### Stage 3: Add Model-Design Variants

Run small VB pilots before any full launch.

1. **Current baseline**
   - origin-state plus horizon;
   - no forecast covariates;
   - current RHS prior.

2. **GloFAS-anchor discrepancy model**
   - `q_G` from issued ensemble quantile or Bayesian bootstrap;
   - discrepancy readout uses origin state plus horizon and optional forecast
     covariates;
   - compare against raw GloFAS and the current posterior-model quantile route.

3. **Forecast-covariate posterior-model route**
   - `q_G` remains posterior-model based;
   - prediction rows include horizon-specific GEFS precipitation and soil
     summaries;
   - check whether the fitted `q_G` path tracks issued ensemble variation.

4. **Prior sensitivity**
   - RHS `tau0 = 1e-4`;
   - RHS `tau0 = 1e-3` or calibrated effective-size value;
   - ridge.

### Stage 4: Add Tests Before Fitting

The next implementation should add tests that explicitly assert:

- current model panel has no climate covariates unless a covariate design mode
  is enabled;
- forecast-window design rows never use realized covariates after the cutoff;
- forecast covariates are indexed by `(origin_date, target_date, horizon)`;
- prediction design has more than one horizon-varying column when forecast
  covariates are enabled;
- the posterior-draw identity remains exact after adding the new `q_g_source`;
- all covariate source file hashes and reduction choices are recorded in the
  run manifest.

### Stage 5: Decide the Main Run

Only after the small pilots pass should we choose the manuscript-scale run.
The decision should be based on:

- whether the fitted `q_G` or issued-ensemble `q_G` path follows the GloFAS
  forecast signal;
- whether the discrepancy term is stable and scientifically interpretable;
- whether the corrected `q_Y` improves check loss by horizon without destroying
  uncertainty calibration diagnostics;
- whether VB agrees with a smaller MCMC reference fit on the same design.

## Recommended Immediate Action

Do not launch the large full MCMC run yet.

The implemented feature-contract pass should be treated as the new baseline for
small and median-only VB pilots. The next concrete work is:

1. Run a median-only VB fit under `feature_contract.version = "0.2"` and inspect
   posterior-draw predictions, discrepancy paths, and post-fit diagnostics.
2. Compare the current tight RHS prior (`tau0 = 1e-4`) with a looser RHS setting
   and a ridge baseline before treating the large specification as final.
3. Keep the posterior-draw identity `q_y_draw = q_g_draw - d_g_draw` as the
   required prediction contract for all scientific runs.
4. Consider an additional, explicitly labeled GloFAS-anchor contract in which
   `q_G` is obtained from the issued ensemble or a Bayesian bootstrap over
   members, while the discrepancy remains Bayesian.
5. Use MCMC only after the VB and design diagnostics identify a defensible model
   specification.

This is the most defensible path because it preserves the Bayesian
posterior-draw contract while letting forecast information enter the model in a
way that is observable, auditable, and reproducible.
