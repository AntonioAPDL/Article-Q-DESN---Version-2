# GloFAS Discrepancy-Calibrated Q--DESN Implementation Spec

Date: 2026-05-11

## Purpose

This spec maps the frozen model contract to code objects in the article
application workflow. The May 15 engine-sync update separates two paths. The
legacy origin-state bridge still expects a package-side
`qdesn_fit_discrepancy()` export and should fail closed when that export is not
available. The current latent-path ensemble-likelihood workflow is
article-side: it uses the engine for Q--DESN feature and readout APIs, then
performs the latent-path AL-VB fit inside the application workflow. The exAL,
MCMC, richer feature strategies, and beyond-horizon forecast variants remain
later gates.

## Recommended Architecture

Use a hybrid architecture.

1. Keep the application workflow in this article repo under `application/`.
   This workflow owns data registration, panel construction, forecast-origin
   protocols, fit grids, scoring, figures, tables, and provenance.
2. Keep reusable Q--DESN fitting machinery in the exdqlm/Q--DESN engine. The
   current configured engine is `exdqlm`, with the pinned local development
   hint:

   ```text
   /data/jaguir26/local/src/exdqlm__wt__qdesn_fitforecast_0p5p0
   ```

   Application configs also record the expected engine branch, commit, minimum
   package version, and disallowed stale paths. Launch readiness should fail if
   an old 0.4.0-era or origin-state-only worktree is active.

3. Add only thin article adapters in `application/R/`. These adapters should
   reshape the audited GloFAS panel into engine-ready objects, call the engine,
   and write run artifacts. They should not become a second Q--DESN package.
4. If the discrepancy-calibration fitter is general enough after testing,
   promote the reusable fitting function into the exdqlm/Q--DESN engine and
   leave only a call wrapper in the article repo.

This keeps the implementation compatible with the existing Q--DESN API style
while preserving article-level reproducibility.

## Existing Engine Style To Preserve

The current Q--DESN engine exposes a small family of user-facing functions:

```text
qdesn_fit(...)
qdesn_fit_vb(...)
qdesn_fit_mcmc(...)
qdesn_build_design(...)
forecast_paths.qdesn_fit(...)
forecast_lattice.qdesn_fit(...)
quantileSynthesis(...)
```

The implementation should preserve this style:

- fitters return list-like objects with classed fit metadata;
- inference method is selected by a `method` argument or by model-grid rows;
- VB and MCMC arguments are passed as named lists;
- RHS-family priors use the engine's `rhs_ns` implementation;
- intercept shrinkage is disabled for RHS-family priors;
- forecast helpers should receive fitted objects, not rebuild data internally.

## Article-Side Function Boundary

The article repo should provide these application adapters:

```text
app_check_qdesn_engine_api(cfg, require_discrepancy, stop_on_failure)
app_build_glofas_qdesn_design(panel, cfg, cutoff_row, model_row)
app_make_glofas_discrepancy_data(panel, cfg, cutoff_row, model_row)
app_discrepancy_design_summary(design)
app_fit_qdesn_reference(panel, cfg, model_row)
app_fit_qdesn_discrepancy(panel, cfg, model_row)
app_predict_qdesn_discrepancy(result, panel, cfg, model_row)
app_predict_qdesn_discrepancy_draws(result, panel, cfg, model_row)
app_validate_glofas_fit_object(fit)
app_write_fit_artifacts(fit, run_dir, model_row)
```

The engine-contract and deterministic retrospective training-design builders
are implemented in the article repo. For posterior-draw configurations,
`app_fit_qdesn_discrepancy()` also includes issued GloFAS ensemble members as
G-source likelihood rows under the frozen forecast-origin protocol. The
prediction adapter then builds horizon-indexed origin-state rows and writes the
draw table before any point summary is computed.

## Engine-Side Function Boundary

The preferred reusable engine function for the legacy origin-state bridge is:

```text
qdesn_fit_discrepancy(
  z,
  H,
  source,
  p0,
  method = c("vb", "mcmc"),
  likelihood_family = c("exal", "al"),
  beta_prior_type = "rhs_ns",
  source_levels = c("Y", "G"),
  intercept_index = integer(),
  vb_args = list(),
  mcmc_args = list(),
  control = list()
)
```

When this export is available, the function should return an object with class:

```text
c("qdesn_discrepancy_fit", "list")
```

The object should inherit from `qdesn_fit` only if the forecast helpers are
made explicitly discrepancy-aware. Until then, use explicit discrepancy
prediction helpers rather than relying on generic `qdesn_fit` methods.

## Object Mapping

The implementation should use the following object names.

| Supplement object | Code object | Description |
| --- | --- | --- |
| \(\vect z\) | `z` | Stacked transformed reference and GloFAS values. |
| \(c_i\) | `source` | Factor with levels `Y` and `G`. |
| \(\vect x_i\) | `X_base` | Fixed Q--DESN readout features before augmentation. |
| \(\mat H\) | `H` | Augmented design with rows `[X_base, 0]` for `Y` and `[X_base, X_base]` for `G`. |
| \(\vect\theta_{p_0}\) | `theta` | Stacked coefficient vector `(beta, alpha)`. |
| \(\vect\beta_{p_0}\) | `beta` | Reference quantile readout coefficients. |
| \(\vect\alpha_{p_0}\) | `alpha` | GloFAS discrepancy coefficients. |
| \(\sigma_Y,\sigma_G\) | `sigma[source]` | Source-specific scale parameters. |
| \(\gamma_Y,\gamma_G\) | `gamma[source]` | Source-specific asymmetry parameters for exAL. |
| \(v_i^c\) | `v` | Positive latent mixture variable, same length as `z`. |
| \(s_i^c\) | `s` | Truncated-normal latent variable for exAL; absent for AL. |
| \(\lambda_j^2,\nu_j,\tau^2,\xi,\zeta^2\) | `rhs` | RHS scale state and hyperparameters. |
| \(q^Y_{p_0,i}\) | `q_y` | Reference-process fitted quantile path. |
| \(q^G_{p_0,i}\) | `q_g` | GloFAS forecast-system fitted quantile path. |
| \(d^G_{p_0,i}\) | `d_g` | Fitted discrepancy path. |

The augmented design should be generated deterministically from `X_base` and
`source`; it should not be read from disk unless it is written as a cached
derived artifact with a hash and provenance row.

## Forecast-Time Quantile Contract

The discrepancy sign convention is:

```text
q_G = q_Y + d_G
```

Thus, for horizons covered by an issued GloFAS ensemble at forecast origin
`T`, the final calibrated reference quantile is obtained draw by draw:

```text
q_Y_draw(s, T, h, p0) = q_G_draw(s, T, h, p0) - d_G_draw(s, T, h, p0)
```

The first term is posterior draw `s` of the GloFAS forecast-system quantile for
target `T + h`. The second term is the matching posterior draw of the estimated
GloFAS discrepancy. The discrepancy feature row must be constructed without
future reference observations. Posterior means, medians, intervals, and
manuscript scoring summaries are derived after this draw-level subtraction.
This rule is the relevant forecast contract for the medium-range application:
during the issued GloFAS horizon, the workflow corrects the forecast-system
quantile rather than forecasting the reference quantile as a separate free
path.

The first posterior-draw implementation uses the feature strategy
`horizon_indexed_origin_state`. For forecast origin `T` and horizon `h`, the
prediction row is built from the fixed reservoir state at `T` augmented with
the scaled horizon `h/H`. This keeps the readout leakage-free and horizon-aware
without introducing recursive forecasts of future reference states.

Posterior predictive draws are a second layer. After
`q_Y_draw(s, T, h, p0)` has been constructed, a model-based reference
streamflow draw can be generated from the AL or exAL working likelihood using
the matched posterior draws of the calibrated quantile, scale, and, for exAL,
asymmetry. These predictive draws should be clearly labeled as model-based
under the working likelihood.

A forecast beyond the issued GloFAS horizon is a distinct extension. It would
require recursive prediction of the GloFAS forecast-system quantile and the
discrepancy path before the same subtraction rule could be used. That extension
should not be mixed with the scoreable in-window calibration experiment.

## Pilot Prediction Contract

The first scoreable bridge uses an origin-state discrepancy correction. For an
issued GloFAS ensemble block at origin \(T\), target \(T+h\), and fitted level
\(p_0\), the article adapter computes the raw ensemble quantile
\(\widehat q^G_{p_0}(T,h)\). It then evaluates the fitted discrepancy readout
at the fixed reservoir feature vector available at the forecast origin,
\(\widehat d_{p_0}(T)=\vect x_T^\top\widehat\vect\alpha_{p_0}\), and reports

```text
qhat = raw_glofas_quantile - discrepancy_hat
```

This bridge records `prediction_contract =
"pilot_origin_state_glofas_quantile_minus_discrepancy"` and `prediction_unit =
"point_bridge"`. It is intentionally conservative. It does not use future
reference observations to construct predictor rows, and it does not propagate
the Q--DESN reservoir recursively through the forecast horizon. It is therefore
an engine-contract and diagnostic prediction rule, not the final posterior-draw
prediction contract.

## Posterior-Draw Dry-Run Contract

The posterior-draw dry run uses
`prediction_unit = "posterior_draw"`,
`q_g_source = "posterior_model_quantile"`, and
`discrepancy_feature_strategy = "horizon_indexed_origin_state"`. The staged
fit script writes two prediction artifacts:

```text
tables/posterior_draw_predictions.csv
tables/prediction_quantiles.csv
```

The first table is the primary Bayesian prediction object and must satisfy
`q_y_draw = q_g_draw - d_g_draw` row by row. The second table contains
posterior-mean summaries derived after the draw-level subtraction so that the
existing scoring scripts can run during the dry run.

## Required Data Objects

The application panel must contain these columns before fitting:

```text
origin_date
target_date
horizon
member
is_retrospective
is_ensemble
y_reference
g_glofas
y_transformed
g_transformed
split
cutoff_id
```

The fitter should create stacked rows as follows:

- one `Y` row for each training reference observation used by the cutoff;
- one `G` row for each retrospective GloFAS value used by the cutoff;
- one `G` row for each issued ensemble member included in training or
  forecast conditioning, according to the cutoff protocol.

Rows used for scoring must not leak target observations into model fitting.

## Prior Mapping

Application model-grid values map to engine priors as follows:

```text
coefficient_prior = "rhs"   -> beta_prior_type = "rhs_ns"
coefficient_prior = "ridge" -> beta_prior_type = "ridge"
```

The application default is `rhs`. Ridge is a dense baseline. The adapter should
reject any discrepancy model row whose `coefficient_prior` is neither `rhs` nor
`ridge`.

For RHS, the adapter must set or verify:

```text
shrink_intercept = FALSE
intercept_index = indices for reference and discrepancy intercepts
```

## Likelihood Mapping

Application configuration exposes:

```text
likelihood_family: exal
diagnostic_likelihood_family: al
```

The AL implementation should be built first because it gives closed-form
source-scale updates. The exAL implementation then adds the source-specific
latent `s` variables and the source-specific \((\sigma_c,\gamma_c)\)
Laplace--Delta or slice-sampling block.

The current pilot configuration is:

```text
application/config/glofas_discrepancy_al_mcmc_pilot.yaml
application/config/model_grid_al_mcmc_pilot.csv
```

It uses the AL working likelihood, MCMC, and the regularized horseshoe prior
for one median GloFAS discrepancy fit. The pilot is an engine-contract and
real-data-design gate; it is not a final performance configuration.

The prelaunch dry-run configuration is:

```text
application/config/glofas_discrepancy_prelaunch_dryrun.yaml
application/config/model_grid_prelaunch_dryrun.csv
```

It runs the same small AL-MCMC bridge and then executes
`application/scripts/06_preflight_launch.R`. The preflight stage verifies the
completed stage logs, registered inputs, model grid, figure manifest, prediction
table, prediction-contract metadata, score table, engine contract, and clean
git state. It is the final workflow gate before a separate manuscript-scale
launch. The current pilot prediction table must contain `q_g_hat`, `d_g_hat`,
`qhat`, and the contract fields written by
`application/R/forecast_contract.R`; discrepancy rows must satisfy
`qhat = q_g_hat - d_g_hat`. A final manuscript-scale run must replace this
point bridge with `tables/posterior_draw_predictions.csv`, whose rows satisfy
`q_y_draw = q_g_draw - d_g_draw`.

If the final run reports `q_g_draw`, that quantity must be generated from the
fitted model or from a documented Bayesian conditioning step. The empirical
ensemble quantile bridge remains a pilot or fixed-input diagnostic rule; it is
not by itself a posterior draw of the GloFAS forecast-system quantile. The
final posterior-draw contract should therefore record
`q_g_source = posterior_model_quantile`.

## Fit Object Contract

A completed discrepancy fit should contain at least:

```text
fit_id
model_id
model_family
quantile_level
method
likelihood_family
coefficient_prior
source_levels
reservoir_seed
X_base_info
H_info
theta_summary
beta_summary
alpha_summary
sigma_summary
gamma_summary
rhs_summary
q_y_fitted
q_g_fitted
d_g_fitted
diagnostics
runtime_seconds
engine_version
engine_git_sha
article_git_sha
input_manifest_sha
config_hash
```

For MCMC, summaries should include posterior means, medians, intervals, and
effective sample size diagnostics where available. For VB, summaries should
include variational means, variational variances, ELBO trace, convergence
status, and final maximum parameter change or equivalent criterion.

## Synthetic Validation Before Real Fitting

Before any GloFAS application claim, implement and pass synthetic tests:

1. AL, one source, `alpha` omitted: recovers ordinary reference-only Q--DESN
   readout behavior.
2. AL, two sources, known `beta` and `alpha`: recovers `q_y`, `q_g`, and
   discrepancy path under a small fixed design.
3. exAL, two sources: recovers the same paths when data are generated from the
   exAL hierarchy.
4. RHS prior sanity: intercepts are not shrunk and RHS scale updates remain
   finite.
5. Source permutation check: reordering stacked rows does not change fitted
   summaries beyond Monte Carlo or optimization tolerance.
6. Ensemble duplication check: repeated ensemble rows affect the GloFAS block
   only through their intended likelihood contribution and are reported in the
   run audit.

## Run Artifact Contract

Each fit should write:

```text
fit_object.rds
fit_summary.csv
fit_diagnostics.csv
fit_config.yaml
fit_session_info.txt
fit_git_state.txt
fit_input_manifest_used.csv
```

The run-level status table should include every model-grid row, including
failed or skipped rows. Failure is acceptable in development; silent omission
is not.

## Implementation Recommendation

Do not make the discrepancy fitter an entirely independent script. It should
blend with the existing Q--DESN conventions because that reduces future
maintenance and makes the article methods easier to audit against the package.

At the same time, do not force the article-specific data workflow into the
package. The clean boundary is:

- package: general Q--DESN fitting, design, forecasting, and synthesis;
- article repo: GloFAS input contracts, panel construction, model grid,
  forecast-origin evaluation, and manuscript provenance.

The next coding step should therefore be a minimal engine-compatible
discrepancy fitter, first for AL and RHS, with synthetic tests. After that
passes, add exAL and then VB--LD. The current article-side prelaunch gate stops
before those larger model launches and records whether the workflow is ready to
run them.
