# GloFAS Latent-Path VB-First Implementation Plan

Date: 2026-05-13

## Purpose

The target GloFAS application model treats the future USGS path over the issued
forecast horizon as missing data and lets issued GloFAS ensemble members enter
the likelihood. The implementation priority is now:

1. AL working likelihood with VB.
2. AL working likelihood with MCMC.
3. exAL working likelihood with VB.
4. exAL working likelihood with MCMC.

This order is deliberate. VB is the active development route because it is
cheaper to run, easier to iterate during model-specification work, and better
suited to repeated cutoff and specification checks. MCMC remains necessary as a
posterior simulation reference, but it should not be the first expensive path
used for application development.

## Effective Horizon Rule

The requested horizon in a config is a maximum requested window. The effective
analysis horizon is the largest contiguous issued GloFAS horizon available
after filtering by forecast origin, target dates, and requested horizon range.
For example, if the config requests horizons 1 through 30 but the archived
issued ensemble contains horizons 1 through 28, then the latent-path object
uses \(H=28\) and records the requested maximum separately. Missing internal
horizons are not silently skipped; they are a data-contract error.

This rule keeps the application aligned with the archived forecast record
rather than forcing artificial rows for unavailable horizons.

## AL Latent-Path Posterior Target

For a quantile level \(p_0\), let \(L_{p_0}^{\mathrm{AL}}\) denote the AL
working likelihood. The unknowns are

```text
theta = (beta, alpha)
sigma_Y, sigma_G
v_Y, v_G_ret, v_G_ens
Y_future = Y_{T+1:T+H}
future reservoir states X_future(Y_future, C_future)
RHS scales for theta
```

Here \(C_future\) denotes origin-available forecast-window covariates, such as
blended precipitation and soil-moisture covariates. The historical reservoir
states are fixed after preprocessing and washout. Forecast-window states are
deterministic functions of the stored state at \(T\), output lags, covariates,
and the proposed future reference path.
The output lags are strictly lagged: the row for \(T+h\) may depend on earlier
future reference values, but not on \(Y_{T+h}\) itself.

The AL hierarchy is

```text
Y_t                     ~ AL_p0(q_Y,t, sigma_Y),              t <= T
G_ret,t                 ~ AL_p0(q_Y,t + delta_t, sigma_G),    t <= T
G_ens,T+h,j             ~ AL_p0(q_Y,T+h + delta_T+h, sigma_G)
q_Y,t                   = x_t' beta
delta_t                 = z_t' alpha
```

For the first latent-path implementation, \(x_t\) and \(z_t\) should be allowed
to include the same reservoir state block with different coefficients, plus the
same audited output-lag and covariate feature construction. A two-reservoir
variant can be added later, after this one-state model is validated.

## VB Approximation

The nonlinear state recursion prevents a simple fixed-design CAVI derivation.
The VB implementation should therefore be explicit about its approximation.
The recommended first implementation is a model-specific coordinate scheme:

```text
q(theta) q(RHS scales) q(sigma_Y) q(sigma_G)
q(v_Y) q(v_G_ret) q(v_G_ens) q(Y_future)
```

The forecast-window design is evaluated under a Laplace--Delta approximation
to `q(Y_future)`. The future-path factor is a Gaussian Laplace approximation
to its expected log target, and Delta-method moments of the nonlinear
reservoir map are used to update the readout, scale, mixture, and shrinkage
factors. The implementation must label the monitored objective as a
Laplace--Delta ELBO approximation, not as the exact ELBO of the original
nonlinear latent-path model.

The first version should prefer stability and auditability over aggressive
optimization:

- diagonal, banded, or low-rank plus diagonal Gaussian `q(Y_future)`, with the
  covariance structure recorded in the fit object;
- a documented Hessian construction for the future-path Laplace factor,
  including any regularization added to keep the precision positive definite;
- first-order Delta-method moments for the high-dimensional forecast-window
  state recursion, using the same derivative convention throughout the
  coefficient updates and ELBO;
- closed-form updates whenever the design is conditionally fixed;
- explicit convergence traces for the Laplace--Delta ELBO approximation,
  readout norms, `sigma_Y`, `sigma_G`, and future-path summaries.

## Covariates and Output Lags

Output lags and forecast-window covariates must be implemented in the same
latent-path move. Separating them would produce a prototype that is too far
from the intended application. The implementation should distinguish:

- output lags, which may depend on latent future USGS values after the cutoff;
- strict exclusion of contemporaneous \(Y_{T+h}\) from the row for target
  \(T+h\);
- covariate lags, which must be built from origin-available retrospective and
  forecast covariate timelines;
- direct readout covariates, which can be appended after state construction;
- reservoir-input covariates, which require a covariate-aware continuation
  kernel.

No post-cutoff realized USGS value may enter a model input except through the
latent future path. Held-out USGS values are validation oracles only.

## Synthetic Validation

The synthetic generator should support known truth for:

- `beta`, `alpha`, `sigma_Y`, and `sigma_G`;
- output lags;
- precipitation and soil-moisture covariates;
- a finite future path;
- retrospective GloFAS rows and issued GloFAS ensemble rows sharing
  `sigma_G`.

Required checks before a real GloFAS fit:

1. The effective horizon equals the largest contiguous available issued
   horizon.
2. Future-state continuation matches a direct full-history recursion when the
   true future path is supplied.
3. AL-VB recovers the synthetic reference and GloFAS quantile paths within
   pre-specified tolerances.
4. AL-MCMC agrees with AL-VB on small synthetic cases.
5. The implementation records article git SHA, engine git SHA, config hash,
   input manifest hash, design hash, synthetic truth seed, and fit status.

## Implementation Stages

## Current Executable Status

The article repo now contains a first AL-VB latent-path implementation for
smoke testing:

- `application/R/latent_path_design.R` continues the future DESN state
  recursively and can return strict-lag Jacobians for the forecast-window
  reservoir state rows.
- `application/R/latent_path_vb_al.R` implements the article-side AL-VB
  approximation with Gaussian \(q(\theta)\), inverse-gamma source-scale
  factors, GIG mixture factors, a Gaussian Laplace factor for the latent future
  path, and ridge or regularized-horseshoe coefficient regularization.
- `application/R/fit_qdesn_latent_path.R` builds the latent-path design from
  audited GloFAS inputs, records requested and effective horizons, and writes
  posterior-draw prediction rows compatible with the existing application
  output contract.
- `application/config/glofas_latent_path_al_vb_dec25_smoke.yaml` is a small
  Dec. 25, 2022 reproducibility smoke profile. It limits history length,
  horizon length, and ensemble members per horizon so the dense prototype can
  run quickly. These limits are explicit config fields and are not used for
  application-scale inference.

The smoke profile validates wiring only. Before application claims, the dense
prototype needs a scale-up pass for the full available issued horizon, all
members, and the selected DESN/readout specification, followed by synthetic
recovery checks and MCMC comparison.

### Stage 1: Data Contract

- Keep `application_model.contract = latent_path_ensemble_likelihood`.
- Record requested and effective horizons.
- Fail on missing internal issued horizons.
- Record source-parameter ownership:
  `sigma_G` is shared across retrospective and issued GloFAS rows.

### Stage 2: Synthetic Engine Fixture

- Generate AL data with output lags and ppt/soil covariates.
- Return a panel compatible with `app_make_glofas_latent_path_data()`.
- Return truth objects for path, quantile, discrepancy, and parameters.
- Add unit tests for row counts, horizon adjustment, and held-out oracle use.

### Stage 3: AL-VB Prototype

- Implement the latent future path factor and conditional fixed-design updates.
- Use a Gaussian Laplace factor for `Y_future` and first-order Delta-method
  moments for future-state expectations.
- Emit fit object, convergence traces, posterior draws or approximate draws,
  and posterior predictive contracts compatible with existing post-analysis.

### Stage 4: AL-MCMC Reference

- Reuse the same data contract and feature construction.
- Update only the \(H\) future state rows when the latent path changes.
- Compare against AL-VB on synthetic and small real-data smoke runs.

### Stage 5: exAL Extension

- Add source-specific asymmetry parameters.
- Share `gamma_G` across retrospective and issued GloFAS rows by default.
- Validate exAL-VB against exAL-MCMC before using exAL for application claims.

## Stopping Rule

No application performance claim should use the latent-path model until the
AL-VB synthetic checks pass and the AL-MCMC reference agrees on a small case.
The origin-state bridge remains available as a workflow diagnostic and pragmatic
baseline, not as the intended joint ensemble-likelihood model.
