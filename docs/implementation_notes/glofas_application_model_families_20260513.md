# GloFAS Application Model Families

Date: 2026-05-13

## Purpose

The GloFAS application now distinguishes two model families. The distinction is
substantive, not cosmetic: the two families use the issued forecast ensemble in
different ways and have different posterior targets.

## Origin-State Calibration Bridge

The existing implementation is preserved as the origin-state bridge. Its
configs declare:

```yaml
application_model:
  contract: origin_state_bridge
```

This model fits the historical source-stacked discrepancy readout and then uses
origin-available features to correct issued GloFAS forecast quantities. It is
useful for workflow validation, diagnostic plots, and a possible pragmatic
baseline. It is not the joint ensemble-likelihood model.

The bridge should be read as a forecast-correction rule:

```text
reference quantile draw = GloFAS quantile draw - discrepancy draw
```

The current bridge does not treat the future USGS path as a latent state inside
the fit. It does not recursively propagate Q-DESN states through the issued
forecast horizon using sampled future USGS values.

The frozen reference tag is:

```text
origin-state-calibration-bridge-20260513
```

## Latent-Path Ensemble-Likelihood Model

The target model for the redesign branch is:

```yaml
application_model:
  contract: latent_path_ensemble_likelihood
```

Here the future USGS path over the issued horizon is missing data. Issued GloFAS
ensemble members enter the likelihood directly. The posterior target includes
the missing future path, the parameters, and the forecast-window reservoir
states implied by that path.

For a forecast origin \(T\), horizon \(h=1,\ldots,H\), member
\(j=1,\ldots,J\), and fitted quantile level \(p_0\), the GloFAS ensemble rows
inform the GloFAS-side location

```text
q_G(T+h, p0) = q_Y(T+h, p0) + delta_G(T+h, p0).
```

The GloFAS scale parameter is common across retrospective and issued GloFAS
rows. For exAL, the GloFAS asymmetry parameter is also common across
retrospective and issued GloFAS rows. For AL, no asymmetry parameter is
estimated.

The first executable latent-path route is the article-side AL-VB smoke profile
`application/config/glofas_latent_path_al_vb_dec25_smoke.yaml`. It is scoped to
software validation: a short effective horizon, a short tail-history window,
and a small deterministic subset of issued ensemble members. The limits are
recorded in the configuration and design summary so they cannot be confused
with a full application-scale analysis.

## Coding Rule

Article code must not infer model identity from file names. It should read the
config-level `application_model.contract` field and record that contract in run
metadata. Bridge outputs and latent-path outputs may share input bundles and
source diagnostics, but fitted objects and prediction tables should not be
silently interchangeable.
