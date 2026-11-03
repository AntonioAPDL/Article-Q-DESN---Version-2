# Integrated forecast quantiles conditional on each parameter draw

## Confirmed scientific target

The owner selected separate integrated forecast quantiles for every retained
parameter draw. The reconstruction must retain the original posterior
membership and weights. It must not replace this analysis with quantiles of a
single pooled posterior-predictive distribution.

Let \(\theta^{(s)}\) be one retained parameter draw, \(D_T\) the observed
history at an origin, and \(z\) the stipulated future covariate path. Define

\[
  F^{(s)}_{T,h}(a)
  = \Pr\{Y_{T+h}\leq a\mid\theta^{(s)},D_T,z\},
  \qquad
  q^{(s)}_{T,h}(p)
  = \inf\{a:F^{(s)}_{T,h}(a)\geq p\}.
\]

The probability integrates over future responses, their recursively generated
features, and any required latent-state uncertainty, while holding the outer
parameter draw fixed. A DQLM reconstruction must integrate the conditional
filtered state distribution and propagate the fitted state-evolution rule;
it must not substitute a fixed filtered-state mean. For a DESN, each simulated
future response updates that trajectory's recurrent states and response lags.
Future feature vectors must not be averaged before evaluating the response
distribution.

An inner simulation approximates this conditional distribution separately for
each \(s\). Where the admitted method permits it, the last response can be
integrated analytically through its conditional CDF rather than sampled. This
does not change the target. Inverting the resulting integrated CDF, rather
than averaging trajectory-specific quantiles, produces
\(q^{(s)}_{T,h}(p)\).

## Distinct uncertainty summaries

A score is computed from each draw's integrated quantile curve using the
frozen origins, horizons, probability levels, scoring weights and reference
distribution. Summaries across \(s\) describe posterior variation in this
conditional forecast functional. Inner numerical error must be assessed
separately; it must not be presented as posterior uncertainty.

In contrast, with retained posterior weights \(w_s\), pooling parameters first
would give

\[
  F^{\mathrm{pool}}_{T,h}(a)=\sum_s w_sF^{(s)}_{T,h}(a),
  \qquad
  q^{\mathrm{pool}}_{T,h}(p)
    =\inf\{a:F^{\mathrm{pool}}_{T,h}(a)\geq p\}.
\]

This pooled quantile is a different functional. Quantile inversion, posterior
averaging and nonlinear scoring do not generally commute. One recursive
future path per parameter draw can approximate the pooled predictive
distribution; it does not by itself estimate a separate integrated quantile
curve for every parameter draw.

## Requirements before a complete reconstruction

1. Authenticate native parameter membership, weights, feature definitions,
   original random-stream identities and independent-model draw assemblies.
2. Preserve the specified AL, exAL or Gaussian response law. For a multiquantile
   grid, preserve the frozen projection, interpolation and tail rules that
   define its recursive response law; do not substitute another law merely
   to accelerate computation.
3. Demonstrate conditional filtering and future-CDF accuracy on a prospectively
   chosen set of representative cases. Exact arithmetic parity and a single
   successful case are not full numerical qualification.
4. Bind the executed source, native libraries, runtime and inputs; preserve
   failed attempts and close execution accounting independently.
5. Measure complete parameter-by-origin costs, including numerical precision,
   scoring, storage, transport and contingency, before admitting a campaign.
   Component timings must not be multiplied into an unsupported campaign ETA.
6. Reconstruct and score coherent complete packets before changing article
   tables, figures, conclusions or the Overleaf projection.

This document records the inferential target and implementation boundaries.
It does not grant authentic-data execution, certify the generated native
candidates, launch a reconstruction or promote a numerical result.
