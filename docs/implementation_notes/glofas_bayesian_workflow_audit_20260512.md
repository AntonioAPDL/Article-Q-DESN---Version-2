# GloFAS Bayesian Workflow Audit

Date: 2026-05-12

## Purpose

This note records the current status of the GloFAS discrepancy-calibration
workflow and the conditions required before the application can be treated as a
fully Bayesian analysis. It separates the existing pilot bridge from the final
posterior-draw prediction contract.

## Current Status

After the May 15 engine-sync update, the configured 0.5.0-compatible engine
supplies Q--DESN feature construction and readout APIs. The older package-side
`qdesn_fit_discrepancy()` export is treated as a legacy origin-state bridge and
is not required for the current latent-path ensemble-likelihood workflow. The
target AL-VB latent-path fitter is article-side and must continue to write
posterior-draw predictions with explicit provenance for the engine branch and
commit used to construct DESN features.

The article-side workflow now contains two explicit prediction paths. The
legacy pilot bridge uses `theta_mean` for the discrepancy readout and the
empirical GloFAS ensemble quantile for the forecast-system term. This remains
useful for testing the input bundle, engine API, design construction, scoring
path, and provenance. The posterior-draw path includes issued GloFAS ensemble
members as G-source likelihood rows, builds horizon-indexed forecast design
rows, and writes matched draws of `q_g_draw`, `d_g_draw`, and `q_y_draw`.

The posterior-draw dry run is still a wiring and reproducibility check because
it uses a deliberately small DESN and a short AL-MCMC chain. It should not be
used for manuscript performance claims.

## Bayesian Analysis Criteria

A final application run should satisfy the following criteria.

1. The statistical model is defined conditional on the frozen input bundle,
   preprocessing choices, fixed reservoir construction, reducer construction,
   washout convention, and forecast-origin protocol.
2. The posterior target includes the readout coefficients, source-specific
   likelihood parameters, latent augmentation variables when needed, and
   shrinkage parameters under the chosen prior.
3. Prediction is a posterior-draw transformation. For draw `s`, origin `T`,
   horizon `h`, and quantile level `p0`, the primary calibrated quantile draw is
   `q_y_draw(s,T,h,p0) = q_g_draw(s,T,h,p0) - d_g_draw(s,T,h,p0)`.
4. Posterior means, medians, intervals, monotone quantile-grid summaries, and
   scores are computed only after the draw-level subtraction.
5. Posterior predictive streamflow draws, if used, are a second layer generated
   from the AL or exAL working likelihood using matched draws of the calibrated
   quantile, source scale, and, for exAL, asymmetry.
6. Calibration and coverage are empirical diagnostics under the validation
   protocol. They are not implied by the working likelihood alone.

## Final Prediction Contract

For a final manuscript-scale run, `prediction_unit = posterior_draw` must
use `q_g_source = posterior_model_quantile` and produce a table such as

```text
tables/posterior_draw_predictions.csv
```

with at least the columns

```text
draw_id
fit_id
model_id
model_family
quantile_level
origin_date
target_date
horizon
q_y_draw
q_g_draw
d_g_draw
prediction_contract
contract_version
forecast_scope
q_g_source
discrepancy_feature_strategy
prediction_unit
posterior_draw_contract
posterior_predictive_sampling
beyond_issued_horizon
```

The table must satisfy

```text
q_y_draw = q_g_draw - d_g_draw
```

row by row. Point prediction tables may still be written as derived summaries,
but they cannot replace the draw table in a final launch.

## GloFAS Quantile Source

The final Bayesian contract should not be confused with the pilot empirical
quantile bridge. If the workflow reports a posterior draw
`q_g_draw(s,T,h,p0)`, that draw should come from the fitted model or from a
documented Bayesian conditioning step. If the raw empirical GloFAS ensemble
quantile is used directly, the output should remain labeled as a fixed-input
point bridge or as a fixed-input correction, not as a posterior draw of the
forecast-system quantile.

The strongest final version is therefore:

- include issued GloFAS ensemble members as G-source likelihood contributions
  under the pre-specified forecast-origin protocol;
- construct forecast-design rows using information available at origin `T`;
- compute `q_g_draw`, `d_g_draw`, and `q_y_draw` from the same posterior draw
  of the augmented readout and source-specific likelihood parameters.

## Forecast-Feature Strategy

The posterior-draw dry run fixes the first final-candidate strategy:
`horizon_indexed_origin_state`. For an issued forecast at origin `T` and
horizon `h`, the prediction row uses the reservoir state available at `T`
augmented with the scaled horizon `h/H`, where `H` is the configured maximum
issued horizon. This is leakage-free, reproducible from the frozen input
bundle, and horizon-aware without recursively simulating future reference
values.

Acceptable final strategies must satisfy three requirements.

1. They use only information available at the forecast origin.
2. They define one deterministic design row, or a documented set of design
   rows, for each origin, horizon, and quantile level.
3. They are reproducible from the frozen input bundle and configuration files.

The origin-state pilot remains available only as an engine-contract check. A
manuscript-scale posterior-draw launch should use
`horizon_indexed_origin_state` unless a richer feature strategy is explicitly
defined, documented, tested, and frozen before evaluation.

## Reproducibility Gates

The final launch should not start until these gates pass.

1. All authoritative source audits pass for the selected cutoffs.
2. The configured 0.5.0-compatible engine passes source-policy and Q--DESN
   feature API checks, and the article-side latent-path fitter passes synthetic
   recovery tests.
3. The article workflow writes posterior-draw prediction tables and validates
   the draw-level identity.
4. The preflight report records clean article and engine git states, engine SHA,
   input manifest hash, config hash, design hash, session information, and
   stage-completion logs.
5. MCMC diagnostics are available for selected fits. VB-LD, when added, is
   checked against MCMC on smaller or selected configurations before being used
   for production-scale fits.
6. Score tables and manuscript figures are promoted only from final run
   directories with complete provenance.

## Decision

The current architecture is the right direction: the article repo owns the
application contract, input provenance, figures, scoring, and manuscript
outputs, while the reusable sampler belongs in the Q--DESN engine branch. The
next implementation step should not be a real GloFAS launch. It should be the
posterior-draw prediction adapter and its validation tests, followed by a
documented choice of forecast-feature strategy.
