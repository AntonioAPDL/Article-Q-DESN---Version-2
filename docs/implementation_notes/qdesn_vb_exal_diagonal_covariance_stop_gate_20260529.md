# Q-DESN VB exAL Diagonal Covariance Stop Gate

Date: 2026-05-29

## Purpose

This note records the exAL diagonal beta covariance stop gate and its later
narrow resolution. The first attempted path was backed out after it failed the
exact chunking equivalence gate. A later pass reopened only the exAL ridge
case, added practical equivalence gates, and left exAL RHS/RHS_NS diagonal
covariance forbidden.

## Attempted Scope

The attempted stage was intentionally narrow:

- likelihood: exAL;
- beta prior: ridge;
- covariance approximation: diagonal beta covariance;
- static/readout and Q-DESN routing;
- exact chunked equivalence against unchunked diagonal exAL.

No RHS/RHS_NS exAL diagonal covariance, stochastic exAL, article adapter,
low-rank covariance, divide-and-combine, or coreset work was attempted.

## Historical Stop Gate Result

Allowing exAL ridge diagonal covariance produced finite fits, but exact chunked
diagonal exAL did not match unchunked diagonal exAL after the LD sigma/gamma
feedback loop. The mismatch affected qbeta, gamma/sigma traces, and the
objective trace. Because exact chunking must preserve the same target as the
unchunked path, this is a hard stop gate.

At that time the code was restored so that exAL diagonal covariance failed
early:

```text
diagonal beta covariance approximation is currently supported only for
likelihood_family = 'al'
```

The focused covariance regression returned to the AL-only supported state:

- `test-exal-beta-covariance-approx.R`: 75 pass, 0 fail.

## Interpretation

The failure is not a reason to distrust AL diagonal covariance. It is specific
to exAL because exAL couples qbeta, qv, qs, sigma/gamma LD state, and xi
expectations. A diagonal beta covariance approximation changes beta second
moments, and those moments feed back into exAL local and sigma/gamma updates.
The unchunked and chunked paths must therefore be re-derived and tested
together before the mode is enabled.

## Contract That Was Required Before Reopening Ridge

Before exAL ridge diagonal covariance could be implemented, the derivation had
to define:

- how diagonal qbeta second moments enter qv and qs updates;
- how diagonal qbeta second moments enter sigma/gamma LD sufficient statistics;
- whether xi refreshes are full-data only or can be chunked exactly;
- how exact chunking accumulates all row-additive exAL terms before every
  global update;
- whether RHS/RHS_NS priors are forbidden or separately supported;
- tolerances for exact chunked diagonal exAL equivalence.

Required tests before enabling ridge:

- unchunked exAL diagonal finite-state test;
- exact chunked exAL diagonal equivalence against unchunked diagonal exAL;
- qv, qs, sigma/gamma, xi finite-state tests;
- stochastic/hybrid exAL diagonal fail-early tests;
- Q-DESN routing only after static/readout tests pass.

## Resolution Addendum

Package commit `f0d45ea` implements exAL ridge diagonal covariance for
package static/readout and univariate Q-DESN routing. Exact chunked exAL ridge
diagonal matched unchunked exAL ridge diagonal in the D=1, n=300 source gate:

| comparison | max abs | max rel | passed |
| --- | ---: | ---: | --- |
| exAL ridge diagonal exact chunking | 9.288e-06 | 2.044e-09 | yes |

The same source gate showed poor predictive diagnostics for this covariance
approximation:

| method | pinball_y | rmse_mu |
| --- | ---: | ---: |
| exAL ridge diagonal | 166.227109 | 332.79075 |

Current decision:

- exAL ridge diagonal covariance is supported as an explicit covariance
  approximation, not as a recommended predictive default;
- exAL RHS/RHS_NS diagonal covariance remains gated;
- stochastic/hybrid exAL diagonal covariance remains forbidden.
