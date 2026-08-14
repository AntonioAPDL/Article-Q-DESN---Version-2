# GloFAS Discrepancy-Calibration Model Contract

Date: 2026-05-11

## Status

This document freezes the application model to be implemented in the
article-owned GloFAS workflow. It is the bridge between Section 9 of the main
article, Section S9 of the supplement, and the future fitting code. Changes to
this contract should be made deliberately, because the implementation,
simulation checks, scoring tables, and manuscript prose should all refer to the
same model.

## Frozen Model

For each fitted quantile level \(p_0\), the GloFAS application uses a
source-indexed Q--DESN readout with two sources:

- \(Y\): transformed reference gauge streamflow;
- \(G\): transformed GloFAS values, including retrospective GloFAS and issued
  GloFAS ensemble members.

The reservoir feature vector \(\vect x_i\) is fixed after preprocessing,
reservoir construction, reducer construction, and washout. The application
does not propagate uncertainty in the reservoir architecture or random seed.

The augmented readout is

```text
theta_p0 = (beta_p0, alpha_p0)
```

where:

- `beta_p0` is the reference-process quantile readout;
- `alpha_p0` is the GloFAS discrepancy readout at the same quantile level.

The source-specific design rows are:

```text
h_i^Y = (x_i, 0)
h_i^G = (x_i, x_i)
```

and the fitted locations are:

```text
q_Y(i, p0) = h_i^Y' theta_p0 = x_i' beta_p0
q_G(i, p0) = h_i^G' theta_p0 = x_i' beta_p0 + x_i' alpha_p0
```

The calibrated forecast target remains the reference-process quantile
`q_Y(T + h, p0)`. The GloFAS likelihood block informs the forecast-system path
`q_G(T + h, p0)` and the discrepancy `x' alpha_p0`.

## Forecast-Time Quantile Contract

The forecast-time contract follows directly from the sign convention above:

```text
discrepancy = GloFAS quantile - reference quantile
reference quantile = GloFAS quantile - discrepancy
```

For an issued GloFAS ensemble at origin \(T\), horizon \(h\), and quantile
level \(p_0\), the ensemble supplies information about the forecast-system
quantity \(q_G(T+h,p0)\). It is not treated as a direct forecast of the
reference-process quantity \(q_Y(T+h,p0)\). The final Bayesian prediction
contract is posterior-draw subtraction:

```text
q_Y_draw(s, T, h, p0) = q_G_draw(s, T, h, p0) - d_G_draw(s, T, h, p0)
```

where:

- `q_G_draw(s, T, h, p0)` is posterior draw `s` of the GloFAS
  forecast-system quantile for target date `T + h`;
- `d_G_draw(s, T, h, p0)` is the matching posterior draw of the GloFAS
  discrepancy, evaluated from information available at forecast origin `T`;
- `q_Y_draw(s, T, h, p0)` is the resulting posterior draw for the calibrated
  reference-process quantile;
- the feature-construction rule for `d_G_draw(s, T, h, p0)` must be
  pre-specified and recorded in the run outputs.

Draws must be matched by posterior draw index. Do not form the primary
Bayesian prediction object by subtracting posterior means, medians, or other
point summaries. Summaries of the reference quantile are computed after the
draw-level subtraction. If posterior predictive samples of reference
streamflow are needed, they are generated from the AL or exAL working
likelihood using matched posterior draws of the reference quantile, source
scale, and, for exAL, asymmetry.

This is an in-window calibration rule for horizons covered by the archived
GloFAS ensemble. A forecast beyond the issued GloFAS horizon is a different
operation: it requires recursive propagation or another forecast model for both
the GloFAS forecast-system quantile path and the discrepancy path before the
same subtraction can be applied.

The current article-side pilot uses the origin-state bridge

```text
dhat_G(T, h, p0) = x_T' alphahat_p0
```

for every covered horizon. This point bridge is leakage-free and useful for
engine-contract validation, but it is not the final posterior-draw prediction
contract.

The first posterior-draw implementation uses the horizon-indexed origin-state
feature rule. For an issued forecast at origin \(T\) and horizon \(h\), the
prediction row is formed from \((\vect x_T^\top,h/H)^\top\), where \(H\) is the
configured maximum issued horizon. This rule uses only origin-available
information, permits horizon-specific discrepancy corrections, and remains
distinct from a recursive forecast beyond the issued GloFAS horizon.

## Likelihood Contract

The default likelihood family for the article model is exAL. AL is retained as
a simplified implementation and diagnostic variant.

For exAL, each source has its own likelihood parameters:

```text
Y source: sigma_Y, gamma_Y
G source: sigma_G, gamma_G
```

For AL, each source has its own scale:

```text
Y source: sigma_Y
G source: sigma_G
```

The exAL and AL likelihoods are working likelihoods for quantile-targeted
inference. Posterior summaries are conditional on the fixed reservoir and the
working likelihood. Empirical calibration must be assessed through forecast
scores and coverage diagnostics, not asserted from the working likelihood
alone.

## Prior Contract

The regularized horseshoe is the default application prior for non-intercept
entries of `theta_p0`. It should be implemented with the same product
representation used in the supplement and in the Q--DESN engine:

```text
Normal(theta_j | 0, tau^2 lambda_j^2) Normal(0 | theta_j, zeta^2)
```

This representation is equivalent, as a coefficient law, to a Gaussian prior
with variance

```text
V_j = (zeta^{-2} + tau^{-2} lambda_j^{-2})^{-1}
```

conditional on the scales. The reference and discrepancy intercepts receive
weak Gaussian priors and are not shrunk by the RHS hierarchy. Ridge remains a
dense baseline, not the default application prior.

## Ensemble-Member Factorization

GloFAS ensemble members at a common forecast origin and horizon enter the
GloFAS block as conditionally independent likelihood contributions given the
forecast-system quantile path and source-specific likelihood parameters. This
is a modeling factorization motivated by the ECMWF ensemble-generation
construction, where perturbed initial states and model perturbations generate
independent forecast alternatives. It is not an unconditional independence
claim about hydrologic errors.

If diagnostics show that retrospective GloFAS values and issued ensemble
members have materially different residual behavior, the implementation may add
a third source label, for example `G_ret` and `G_ens`, with separate likelihood
parameters. That extension should not change the readout structure.

## Multi-Quantile Contract

Each quantile level is fit separately. A fitted grid is synthesized only by
post-processing target-level summaries:

```text
(p_k, q_Y(T + h, p_k)), k = 1, ..., K
```

The synthesis step produces a monotone estimated predictive quantile function
for the reference streamflow process. It is not a joint multi-quantile Bayesian
model.

## Accepted Comparisons

The first application implementation should support:

- raw GloFAS ensemble quantiles;
- reference-only Q--DESN;
- GloFAS discrepancy-calibration Q--DESN;
- DQLM or exDQLM baselines only after they can be run under the same
  forecast-origin protocol.

The required Q--DESN application fits are the RHS versions. Ridge versions are
enabled as dense baselines but should not be described as the default
application model.

## Non-Negotiable Reproducibility Rules

- All inputs must come from a registered frozen input bundle.
- Every run must record input manifests, configuration files, session
  information, git state, fit status, score tables, and output provenance.
- Final prediction outputs must include posterior draws with
  `q_y_draw = q_g_draw - d_g_draw`. Point prediction tables may be written for
  pilot checks or derived summaries, but they are not the primary Bayesian
  prediction object.
- Final posterior-draw outputs must record `q_g_source =
  posterior_model_quantile`. A raw empirical ensemble quantile can be retained
  as a baseline or pilot bridge, but it should not be labeled as a posterior
  draw of the GloFAS forecast-system quantile.
- Final manuscript launches must not use a prediction contract whose name begins
  with `pilot_`, and discrepancy rows must use `prediction_unit =
  posterior_draw`.
- No manuscript performance claim may be made from a run with unaudited inputs
  or missing provenance.
- The article repo owns the application contract and provenance; the reusable
  fitting engine belongs in the exdqlm/Q--DESN package or in a clearly marked
  vendored module.
