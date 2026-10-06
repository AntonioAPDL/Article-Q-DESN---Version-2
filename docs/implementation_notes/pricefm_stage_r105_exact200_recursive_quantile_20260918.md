# PriceFM Stage-R105 exact-200 recursive quantile campaign

Stage-R105 is a validation-only relaunch of the frozen region-specific PriceFM
independent quantile surface. It answers one narrow question: does forcing every
AL-RHS and structured exAL-RHS variational fit to complete exactly 200 iterations
materially change the fitted posterior or corrected recursive forecasts?

The campaign preserves the 38 region contracts, three folds, seven quantiles,
DESN specifications, `tau0` values, causal teacher-forced training design, and
Normal driver surfaces inherited by Stage-R103. It changes only:

- `min_iter = max_iter = 200` and convergence patience of one iteration;
- removal of the historical AL retry beyond the configured budget;
- validation scoring by pathwise quantile-curve self recursion;
- paired comparison of Normal-RHS and Ridge neighbor paths for graph cases.

Every completed atom must record exactly 200 iterations. Failure of a terminal
numerical criterion makes the atom ineligible but does not erase or refit the
result. One complete `(likelihood family, forecast policy)` combination is
selected per region using Fold-1 validation only and held fixed for all folds.
No test data, joint model, MCMC, registry, article, or manuscript mutation is
authorized by this stage.

The launch is resumable at atom and case level. It uses one sequential case
queue on each explicitly assigned physical core, with one BLAS/R thread per
model. Completion triggers a validation-only closeout; promotion remains a
separate user decision.
