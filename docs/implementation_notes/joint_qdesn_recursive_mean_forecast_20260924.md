# JOINT recursive mean-design forecast reconstruction

Date: 2026-09-24

Lane: `work/joint-qdesn-recursive-mean-forecast-jerez-20260924`

Status: implementation verified; Jerez forecast-only campaign launch pending

## Purpose

This lane reconstructs forecasts from the completed corrected-v4 JOINT fits.
It does not rerun screening, VB optimization, or MCMC. For each rolling origin,
posterior quantile-function paths recursively generate future responses and the
complete response-dependent readout design. Those readout rows are averaged by
origin and horizon. A separate posterior sample of readout coefficients then
produces score draws conditional on the mean design.

This implements the requested uncertainty separation: final score intervals
include readout uncertainty but exclude recursive future-input/state-path
dispersion. The latter remains available through the retained design moments.
For hybrid and direct designs, the summary covers nonlinear lag-derived direct
features as well as reservoir coordinates.

## Frozen scientific contract

- Source: corrected-v4 runtime inventory, 2,970 files, 387,506,202 bytes.
- Source inventory SHA-256:
  `e4b98fe89a8a0c2323f8205c1abef608ff733bc5ec323ea6372198caca02191d`.
- Models: 32 cells, each reconstructed under VB and MCMC, for 64 workers.
- Geometry: 33 origins, 30 open-loop horizons, 990 score rows.
- Quantiles: `0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`.
- Weights: `0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025`, without
  renormalization.
- Recursive responses: isotonic quantile contract, piecewise-linear inverse
  CDF, endpoint-clamped tails.
- Truth target: `P(Y[T+h] | F[T])`, approximated by recursive known-DGP oracle
  paths rather than the historical realized-future conditional oracle.
- Primary metric: `origin_marginal_dgp_integrated_acrps`.
- MCMC state summary: 1,000 chain-balanced draws; final score pool: all 750
  retained draws from each of five chains.
- VB state summary: 1,000 Gaussian slope draws; final score pool: 4,000 slope
  draws. Intercepts are fixed at their retained variational means because no
  intercept covariance was retained, so VB intervals are explicitly partial.
- Independent quantiles use a seeded product-posterior coupling. Joint draws
  retain cross-level draw identity.
- Execution: exactly eight one-thread workers on eight distinct physical Jerez
  cores, selected by a live capacity audit.

The mean-design RMS half-sample gate is 0.10 full-sample SD units. The earlier
planning value 0.02 was below the expected Monte Carlo noise floor of two
500-draw means (`sqrt(1/500 + 1/500)`, approximately 0.063) and would reject a
correct sampler by construction. The canonical half-score gate remains 0.5%.

## Dependency-ordered run

1. Verify every source artifact by size and SHA-256 and reproduce all eight
   teacher-forced designs.
2. Run 16 primary DGP oracle shards, two per scenario and 2,048 paths per
   shard. If the frozen split gate fails, run the two predeclared extension
   shards only for that scenario.
3. Freeze eight oracle banks after split-half and horizon-one analytic gates.
4. Run three sentinels spanning direct, hybrid, reservoir, VB, MCMC, joint,
   independent, AL, and exAL adapters.
5. Run all 64 resumable forecast workers through the bounded queue.
6. Verify manifests and contract crossings, then materialize summaries,
   posterior contrasts, winners, and health artifacts.

No partial result can enter article assets. Existing corrected-v4 outputs
remain authoritative until this different open-loop estimand is complete and
scientifically reviewed.

## Verification before launch

- `test_joint_qdesn_recursive_mean_design.R`: pass, including all eight
  teacher-forced designs and real direct/hybrid/reservoir recursive paths.
- `test_joint_qdesn_recursive_dgp_oracle.R`: pass, including brute-force
  expected-check equivalence and recursive oracle aggregation.
- `test_joint_qdesn_recursive_mean_score_packet.R`: pass, including the frozen
  contract, Gaussian moment reconstruction, independent coupling, draw-level
  scoring, and real compact initializers.
- `test_joint_qdesn_corrected_article_comparison_muscat_contract.R`: pass.
- `test_joint_qdesn_post_phase178_dgp_integrated_acrps.R`: pass.
- Full corrected-v4 source-inventory and teacher-forced local preflight: pass.
- `bash -n` and `git diff --check`: pass.

## Boundaries

The lane changes only dedicated JOINT modules, configuration, scripts, tests,
registration documentation, and this note. It does not modify PriceFM, GloFAS,
Phase182, historical JOINT runtimes, fitted posterior objects, article files,
or Overleaf. Runtime output remains ignored. The dedicated branch is pushed
for review but is not merged to `main` by this lane.
