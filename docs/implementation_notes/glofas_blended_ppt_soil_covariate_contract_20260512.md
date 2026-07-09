# GloFAS Blended Precipitation and Soil-Moisture Covariate Contract

Date: 2026-05-12

## Purpose

This note records the active covariate contract for the Dec. 25, 2022 GloFAS
Q-DESN discrepancy application. The model-development pass uses only
precipitation and soil moisture as exogenous readout covariates. GDPC, PCA, and
climate-index features are excluded from the model design.

## Data Contract

The model-facing realized covariate table is
`ppt_soil_covariates.csv`. It contains exactly:

```text
date, ppt, soil
```

The legacy `climate_covariates.csv` file remains available for source
diagnostics and provenance, but the Q-DESN readout uses only the model-facing
`ppt` and `soil` columns. The input manifest now records both files when the
local materialized bundle contains them.

For retrospective rows through the forecast origin, the covariate timeline uses
realized precipitation and realized soil moisture. For the issued forecast
window, the covariate timeline uses a deterministic blended forecast built from
the upstream GEFS handoff cache:

- precipitation source: `APCP_surface/gefs_members.csv`;
- soil source: `SOILW_0_0_1_m_below_ground/gefs_members.csv`;
- reduction: GEFS member daily `q85`; subdaily GEFS APCP values are summed by
  target date before the member reduction, while subdaily GEFS SOILW values are
  averaged by target date before the member reduction;
- precipitation blend: observed weight 0.50, normal noise with standard
  deviation 30, floor at zero, and dry-day zero persistence probability 0.90;
- soil blend: observed weight 0.50 and absolute-normal noise with standard
  deviation 0.05.

The blend intentionally uses realized future precipitation and soil moisture in
the observed-weight component. This is a controlled model-development choice.
The resulting application should not be described as a strict operational
forecast unless the covariate contract is replaced by an origin-available
forecast-only version.

## Readout Design

The reservoir remains a fixed nonlinear feature map of the transformed
reference streamflow history. The article-side feature contract now separates
the reservoir input bias from the readout intercept. The reservoir builder may
use an internal input bias, but the fitted readout receives only one explicit
intercept column, named `readout_intercept`. Direct input features appended to
the readout never include the reservoir's internal bias column.

The precipitation and soil covariates enter the Bayesian readout through
standardized lag blocks. For the large Dec. 25 profiles, the configured
covariate lags are \(0,\ldots,60\), giving 122 covariate lag features:

```text
ppt_lag_0, ..., ppt_lag_60, soil_lag_0, ..., soil_lag_60
```

The same large profiles also include direct transformed-streamflow lags
\(1,\ldots,180\) in the readout:

```text
y_lag_1, ..., y_lag_180
```

These output lags are anchored at the forecast origin when prediction rows are
constructed. Future reference observations are therefore not used to form
forecast-window output-lag features. Covariate lags are anchored at the target
date because future precipitation and soil features come from the deterministic
GEFS blended forecast timeline described above.

The standardization constants are estimated from the retrospective training
period through the cutoff. Forecast-window rows use the same constants.

For a GloFAS prediction at origin \(T\), target date \(T+h\), and horizon
\(h\), the readout row now combines:

```text
[readout intercept, reservoir state at T, output lags at T,
 ppt/soil lag features at T+h, h / H]
```

This retains the posterior-draw prediction contract
`q_y_draw = q_g_draw - d_g_draw`, but gives the model horizon-specific forcing
information instead of relying only on the origin reservoir state and a scaled
horizon index.

## Verification

The staged check

```sh
Rscript application/scripts/00_register_input_bundle.R \
  --config application/config/glofas_discrepancy_vb_large_dec25_p50_pilot.yaml

Rscript application/scripts/00_check_inputs.R \
  --config application/config/glofas_discrepancy_vb_large_dec25_p50_pilot.yaml \
  --run_id covariate_contract_check

Rscript application/scripts/01_build_panel.R \
  --config application/config/glofas_discrepancy_vb_large_dec25_p50_pilot.yaml \
  --run_id covariate_contract_check

Rscript application/scripts/02_make_input_figures.R \
  --config application/config/glofas_discrepancy_vb_large_dec25_p50_pilot.yaml \
  --run_id covariate_contract_check

Rscript application/scripts/03_check_model_design.R \
  --config application/config/glofas_discrepancy_vb_large_dec25_p50_pilot.yaml \
  --run_id covariate_contract_check
```

completed successfully. The design preflight recorded:

- 12,495 base feature rows after washout;
- 1,304 base readout features;
- 1 readout intercept;
- 1,000 reservoir-state features;
- 180 direct output-lag features;
- 122 precipitation and soil lag features;
- 1 scaled-horizon feature;
- 2,608 augmented discrepancy-design columns;
- 28 issued prediction rows;
- 1,304 prediction features.

The input figure stage also writes
`cutoff_covariate_diagnostic_dec25_2022.pdf`, which shows the retrospective
realized and forecast-blended covariate segments around the cutoff.

## Implication

The previous p50 pilot fit was scientifically weak because only the scaled
horizon feature varied across prediction rows. The new design gives the
posterior model a richer, date-specific forecast covariate block while keeping
the rest of the posterior-draw discrepancy workflow unchanged.
