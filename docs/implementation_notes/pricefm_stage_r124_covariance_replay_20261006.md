# PriceFM R124: covariance-preserving replay

## Diagnosis and mathematical correction

The frozen R123 forecast engine's `_draw_gaussian` unconditionally samples from
`N(m, V + j I)`, with `j = sqrt(eps) max(1, mean(diag(V)))`, instead of `N(m,V)`.
For a readout z, the added coefficient contribution to predictive variance is
exactly `j ||z||^2`. This differs from residual variance and is not itself a
96-step forecast comparison. B's tiny fourth-layer features and large
coefficients make its covariance particularly anisotropic; nine split-3
training readouts showed roughly 42% extra total one-step Normal variance.
This is an executed forecast-sampler issue, not a demonstrated prior or fit
target error. The deterministic Normal selection scorer does not call it.

Use a diagonal congruence, `D=diag(sqrt(diag(V)))`, `C=D^-1 V D^-1`, and
`L=D chol(C)`. Then `L L' = V`; `m + epsilon L'` has the intended covariance.
No jitter, eigenvalue clipping, shrinkage or prior change is allowed. Invalid
or inaccurate covariance blocks. Matrix and long-double projected residuals
are checked independently. All 72 actual frozen covariances passed the initial
read-only check, maximum projected relative error 4.48e-11 and reconstruction
relative error 1.63e-15.

## Scope and executed source

R123 scientific owner remains `40d42d15a477c2f9d50dbc69b4eb9885da91ec29`.
The nine R124 cells reuse its three structures, fixed tau0 values, three
training-internal chronological origin sets, 63 AL VB fits and nine certified
Normal parents. H=96 quarter-hourly steps means 24 hours. Historical source
files and runtime evidence are not edited. A private process-local sampler is
the sole change to the frozen `recursive_quantile_forecast` implementation.

Three outputs are retained from each single simulation: primary `mean_feature`,
diagnostic `path_specific`, and `normal_driver`. Each uses the same origins,
500 paths, source reservoir, stochastic seeds and fitted posterior packets.
Quantile paths remain AL fitted conditional quantile readouts, not draws from
seven AL likelihoods. Averaged conditional quantiles are not generally marginal
mixture quantiles. No alternative mixture operator is silently selected.

The original three-split mean-AQL ranking rule is retained. Legacy metrics are
kept as historical comparisons, not overwritten or mislabeled corrected. A
new corrected internal choice is not an article authority. All 21 B quantile
fits remain capped at 1,000, externally eligible, and not formally converged;
full RHS/latent variational stationarity is unavailable from compact exports.

## Reproducibility and operations

`445_run_pricefm_stage_r124_covariance_replay.py` provides prepare, smoke,
controller, cell and closeout modes. Preparation verifies exact owner source,
parent completion ledgers, all fit contracts/targets, nine design packets,
covariance projection checks, protocol and release-test identity. Preparation
is immutable. Source and parent hash ledgers are verified again at closeout.
No fit command exists; guards deny historical fit/scoring entrypoints that
could write into the parent. Cells use private temporary output followed by
atomic installation. Existing partial evidence is preserved and blocks.

Jerez runs at most 15 workers on distinct idle physical cores, one BLAS/OMP
thread each; the nine panel tasks require at most nine cores. Reserve 200 GiB
RAM and disk, respect other-lane affinity, and update per-origin heartbeats.
Controller recovery adopts only recorded PID/start-tick/argument identities
or reuses verified completed cells. It never kills or duplicates a worker.
Outputs are compact predictions, truth/origins, per-operator metrics,
covariance audits, convergence labels and a diagnostic report. Do not save
path-by-path reservoir tensors or repeat model fitting.

All generated paths remain under ignored `application/data_local/pricefm/`;
the evolving master plan remains under ignored `local_trackers/`. Commit and
push only the dedicated task branch. No main, article or Overleaf changes.

The first real two-origin smoke completed its numerical forecast but failed
before terminal serialization because `posterior_paths` was supplied twice
to `dict`. Preserve that first namespace, including its partial prediction
files and failure receipt. The corrected execution uses
`pricefm_stage_r124_covariance_preserving_replay_v2_20261006`, a new immutable
preparation and freshly matched release evidence. End-to-end cell tests cover
both smoke and full-output serialization and verified reuse. No full replay
workers were launched before this failure, and no model fit was repeated.

## Next-stage gate

After replay, compare matched-origin driver calibration, primary AQL, late AQL,
crossing and coverage. Preserve the separate capped-fit limitation. Additional
fitting needs a demonstrated need and a bounded full-state diagnostic, not
another broad screening. Official-fold evaluation is launch-prep only and
requires separate authorization; do not use official outcomes for tuning.
Authoritative scientific/article promotion remains NOT_READY_FOR_INTEGRATION.
