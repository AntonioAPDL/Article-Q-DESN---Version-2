# Q-DESN Inferential Object and Terminology Contract

Date: 2026-08-15
Status: authoritative for the corrected reader-centered revision
Source commit: `60fe289e8586078a9cc6c939ee3877a498acfadf`

## Purpose

This note fixes the vocabulary used by the main article, supplement, tests, and
release tools. It distinguishes the scientific quantity, posterior object, and
reported action before any prose polishing or table relabeling.

## Objects

**Forecast-origin marginal distribution.**
For origin \(T\) and horizon \(h\),
\[
F_{T,h}(y)=P(Y_{T+h}\le y\mid \mathcal F_T)
\]
is the response distribution after integrating over declared future-history and
posterior uncertainty. Its generalized inverse is \(Q_{T,h}(p)\). Use this
notation only when a marginal response distribution is actually formed.

**Path-conditional readout.**
For a quantile level \(p\), parameter draw \(\theta_p^{(m)}\), and propagated
history \(H_{T+h-1}^{(m,p)}\),
\[
\mu_{p,T+h}^{(m)}
=x_{T+h}(H_{T+h-1}^{(m,p)})^\top\beta_p^{(m)}
\]
is the draw-specific quantile readout. This is the primary object in the
readout-focused article route.

**Working-likelihood predictive draw.**
An AL or exAL draw conditional on \(\mu_{p,T+h}^{(m)}\), scale, and shape is a
component working-likelihood response draw. It is not automatically a
forecast-origin marginal predictive draw unless the full response-level
mixture is formed and scored.

**Posterior readout summary.**
A mean, median, or other functional of \(\mu_{p,T+h}^{(m)}\) across posterior
or variational draws. The current GloFAS authority reports the arithmetic mean
of `q_y_draw` before isotonic projection.

**Independent quantile grid.**
Separately fitted quantile levels produce level-specific summaries. Without an
explicit coupling, this is not a joint posterior over a quantile curve.

**Isotonic point-summary grid.**
The reported monotone grid is the isotonic projection of independent
level-specific point summaries. It is a coherent reported action over the
fitted quantile range, not a response-density model and not a tail
extrapolation.

**Joint quantile-vector readout.**
The joint extension defines an untempered composite working posterior over a
quantile-indexed readout path with adjacent-coefficient shrinkage. It is not a
normalized scalar response density and does not automatically guarantee
noncrossing raw draws.

**aCRPS.**
The application and joint-grid score historically labeled grid CRPS is a finite
quantile-grid approximation:
\[
2\sum_{k=1}^{K-1}(p_{k+1}-p_k)
\{\rho_{p_k}(y-q_k)+\rho_{p_{k+1}}(y-q_{k+1})\}/2.
\]
Call it `aCRPS` or "approximate CRPS from the fitted quantile grid." It uses
the fitted probability range and trapezoidal quadrature and should not be
called full CRPS.

## Application Scope

**GloFAS FR09.**
The selected article-facing model is `fr09_persistence_innovation` with
`persistence_anchored_innovation`. The future discrepancy baseline repeats the
last historical discrepancy and the discrepancy readout adds an innovation.
The raw empirical GloFAS ensemble quantile is a comparator, not the selected
future discrepancy-reservoir input. The promoted action is a posterior-mean
readout grid with isotonic projection; response-level posterior-predictive
sampling is disabled.

The GloFAS case has one origin, uses blended realized-future weather
covariates, and obtains 90 percent interval coverage of 0.357 over 28 scored
horizons. It is a retrospective case study, not an operational calibration
claim.

**PriceFM.**
The PriceFM application is an unweighted 114-cell retrospective replay over 38
regions and 3 folds. Target-only and graph-derived policies both use
realized-ex-post target lead covariates; graph-derived policies additionally
use neighbor lead and lag covariates. The result is descriptive over the fixed
cell panel unless a separate uncertainty estimand is approved.

## Banned Shortcuts

- Do not equate a mean of component quantiles with a marginal predictive
  quantile.
- Do not call independent-level isotonic summaries a joint posterior.
- Do not use calibration to mean any discrepancy correction; reserve it for a
  stated calibration procedure or demonstrated empirical calibration.
- Do not call aCRPS full CRPS.
- Do not describe GloFAS or PriceFM evidence as operational unless all future
  covariates are forecast-origin available and the protocol verifies that fact.
- Do not introduce a composite-target learning rate or complete-data tempering
  without a separate approved derivation and experiment.
