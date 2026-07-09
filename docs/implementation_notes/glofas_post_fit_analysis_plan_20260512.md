# GloFAS Q-DESN Post-Fit Analysis Stage

This note records the post-fit analysis contract for the GloFAS discrepancy
calibration application. The stage is designed to run after a completed fit or
as a standalone command against an existing run directory. It does not refit any
model.

## Statistical Contract

For each posterior or variational draw, the issued-horizon forecast uses

```text
q_Y^(s)(t+h) = q_G^(s)(t+h) - d_G^(s)(t+h),
```

where `q_Y` is the corrected USGS/reference quantile, `q_G` is the fitted
GloFAS quantile, and `d_G` is the GloFAS discrepancy. The observed
retrospective discrepancy is therefore recorded as `GloFAS - USGS`.

The 95% bands in the path figures are posterior intervals for the conditional
quantile. They are not observation-level predictive intervals. Posterior
predictive intervals require an additional working-likelihood sampling step
using the posterior draws of the quantile, scale, and, for exAL, the asymmetry
parameter.

## Inputs

The post-fit stage reads the completed run directory:

- `manifest/qdesn_discrepancy_fit_manifest.csv`;
- `objects/<fit_id>.rds`;
- `objects/<fit_id>__design.rds`;
- `tables/prediction_quantiles.csv`;
- `tables/posterior_draw_predictions.csv`;
- `application/cache/.../application_panel.rds` from the active config.

The saved design objects are authoritative. The stage does not rebuild
reservoir features and does not create a new prediction design.

## Outputs

The stage writes:

- `tables/post_fit_quantile_history_summary.csv`;
- `tables/post_fit_quantile_recent_summary.csv`;
- `tables/post_fit_forecast_window_summary.csv`;
- `tables/post_fit_discrepancy_history_summary.csv`;
- `tables/post_fit_parameter_summary.csv`;
- `tables/post_fit_trace_summary.csv`;
- `tables/post_fit_rhs_summary.csv`;
- `tables/post_fit_metrics_by_model.csv`;
- `tables/post_fit_metrics_by_horizon.csv`;
- `tables/post_analysis_manifest.csv`;
- figures under `figures/post_fit_analysis/`.

The full-history summaries are stored as CSV files. Full draw arrays are not
written by default because long-history fits can produce very large objects.

## Diagnostics

MCMC and VB diagnostics are intentionally different.

For MCMC fits, trace plots are used for sampled scale parameters and, when
available, exAL asymmetry parameters. For VB fits, the stage reports ELBO,
relative-change, and maximum-parameter-change traces. VB traces omit the first
five iterations in the plotted figures by default, but the full trace remains in
`post_fit_trace_summary.csv`.

Gamma/asymmetry plots are shown only for exAL fits. For AL fits, any stored
gamma column is a fixed placeholder and is not treated as a posterior parameter.

## Metrics

The primary quantile metric is check loss at the fitted quantile level.
RMSE, MAE, and bias are reported as descriptive errors against observations.
Interval scores and empirical coverage are reported only when the fitted grid
contains the requested lower and upper quantile levels. CRPS is reported only
when a quantile grid is available; p50-only runs leave CRPS as missing.

## Command

```sh
hash -r
Rscript -e 'cat(R.version.string, "\n"); cat("R_HOME=", R.home(), "\n", sep = "")'

Rscript application/scripts/07_post_analysis.R \
  --config application/config/glofas_discrepancy_vb_large_dec25_p50_pilot.yaml \
  --run_id vb_large_dec25_p50_pilot_20260512_142839
```

Post-fit analysis should run under the local R 4.6.0 runtime, not an old
R-4.4 user-library prefix.

The same stage can be run automatically by `run_all.R` when
`post_analysis.run_after_outputs: true` is set in the active configuration.
