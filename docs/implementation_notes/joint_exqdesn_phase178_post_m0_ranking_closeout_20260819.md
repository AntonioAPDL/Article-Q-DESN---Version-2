# Joint exQDESN Phase178 Exact-M0 Ranking Closeout

Date: 2026-08-19

## Scope

Phase178 is the protected, case-specific exact-M0 ranking stage in the
Phase176-180 post-M0 recovery lane. It compares three frozen candidate
templates within each of five unresolved scenario/readout cells. Each
candidate is evaluated on three protected DGP replicates with four MCMC chains,
for 45 candidate-replicate fits and 180 chain workers in total.

This closeout preserves the experiment's original ranking contract. Forecast
oracle-quantile MAE is the original primary criterion; fit oracle MAE,
realized check loss, the historical finite-grid realized score, functional
stability, and crossing diagnostics are safeguards. The later
DGP-integrated finite-grid score audit is a separate decision layer and must
not be represented as the criterion that launched or ranked Phase178.

## Completion And Integrity

The original monolithic finalizer completed without recovery or MCMC reruns.
The canonical audit is:

`application/cache/joint_exqdesn_phase178_post_m0_ranking_audit_20260813`

The completed evidence satisfies the following implementation checks:

| Check | Result |
|---|---:|
| Frozen workers | 180 |
| Completed workers | 180 |
| Worker failures | 0 |
| Candidate-replicate rows | 45 |
| Target scenario/readout cells | 5 |
| Top-level audit manifest entries | 22/22 verified |
| Frozen-source manifest entries | 14/14 verified |
| Implementation-pass candidate replicates | 45/45 |
| Fit contract crossings | 0 |
| Forecast contract crossings | 0 |
| Fit raw crossings | 0 |
| Forecast raw crossings | 0 |

Manifest authorities:

- canonical audit manifest SHA-256:
  `3a9c387abfe2a7b5a471da77b1a690fba76bfcf7f1eaad0c21a74764f9ef6848`;
- exact-M0 ranking freeze manifest SHA-256:
  `e77a63f66b18a33e10d1950eeff970829a15913fb4a4026ed8c548b9f39dc036`;
- protected-fixture manifest SHA-256:
  `4f13e37f7acfcdb96b4abf68123934f3088a41c5ebab4ee75e6762beeed1ad2a`.

The 180 worker directories retain compressed posterior parameter draws and
complete worker/checkpoint manifests. They remain under a storage hold because
the post-Phase178 DGP-integrated score audit requires draw-level quantile-path
reconstruction.

## Original Ranking Result

The original oracle-MAE ranking selected the following templates:

| Scenario | Readout | Original selection | Role |
|---|---|---|---|
| Laplace bridge | Independent | `tail_relaxed` | Challenger |
| Normal bridge | Independent | `parity` | Parity retained |
| Persistent heavy tail | Independent | `tau0_upper` | Challenger |
| Regime shift | Independent | `tail_relaxed` | Challenger |
| Regime shift | Joint | `parity` | Parity retained |

These are historical Phase178 decisions, not yet the Phase179 candidates. The
realized finite-grid score ratios are extremely close to one, and some
MAE-selected challengers do not improve that secondary score. A separate
predeclared DGP-integrated score contract must therefore be frozen and applied
before Phase179 is prepared.

## Diagnostic Interpretation

All 45 candidate-replicate fits are finite and noncrossing. Scalar MCMC
diagnostics remain review-level in all 45 rows: the maximum rank-normalized
R-hat is 1.7204, minimum bulk ESS is 6.88, and minimum tail ESS is 14.41.
Quantile-path partition diagnostics are mixed: 95 of 180 checks pass and 85
remain review. This does not invalidate the implementation, but it prevents
automatic promotion based only on favorable point metrics.

The next audit must distinguish scalar parameter mixing from the stability of
the posterior score and reported quantile-path functionals. Review-level
gamma/sigma mixing may be tolerated only if those action-level functionals are
stable across chains, allocations, coupling seeds, and protected replicates.

## Frozen Next Action

Do not execute the existing Phase179 launcher, because it consumes the
historical MAE-centered `selection_decision.csv`. The next stage is a
post-Phase178 current-grid DGP-integrated score audit that:

1. freezes the seven-level tau, quadrature, action, posterior-coupling,
   decision-margin, and source-completeness contracts before protected scores
   are computed;
2. evaluates the known-DGP expected finite-grid quantile score without treating
   the joint AL/exAL composite working likelihood as a scalar predictive
   density;
3. preserves joint within-draw dependence and uses a deterministic,
   chain-balanced product-posterior construction for independent quantiles;
4. reports canonical-action score, posterior mean, posterior median, and a 95%
   credible interval;
5. retains realized check loss, historical realized finite-grid score, oracle
   path MAE/RMSE, crossings, and mixing as supporting diagnostics;
6. produces a new case-specific selected-versus-parity decision for Phase179.

The 19-level dense-grid study remains a separate later refit. It must not be
implemented by interpolating the current seven fitted quantile paths.

## Boundaries

- No article asset is promoted by this closeout.
- No Phase179 worker is launched.
- No `main` or Overleaf branch is modified.
- Runtime caches remain ignored and are not Git artifacts.
- PriceFM, GloFAS, and independent scientific lanes are untouched.
