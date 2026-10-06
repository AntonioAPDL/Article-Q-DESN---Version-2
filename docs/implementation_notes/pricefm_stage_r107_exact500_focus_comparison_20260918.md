# PriceFM Stage-R107 exact-500 focus comparison

## Decision context

R106 was launched across 114 region-fold cases to test whether forcing every
independent AL/exAL VB fit from the previously used 200-iteration budget to
exactly 500 iterations changes the corrected recursive forecasts. After 56
atoms completed, all 56 passed the numerical and formal convergence gates.
Their ELBO, sigma, and exAL gamma values were effectively unchanged between
iterations 200 and 500. At seven workers, completing all 1,596 atoms was
projected to require roughly another 16--18 days.

The scientifically efficient next gate is therefore a matched production-data
forecast comparison before completing the broad campaign. This is not a dry or
smoke run. It finishes four real R106 cases that already have frozen R104
corrected-operator comparators:

- BG Fold 1, AL, `quantile_curve_self`;
- BE Folds 1--3, exAL, with fixed Normal-RHS neighbor paths;
- BE Folds 1--3, exAL, with fixed Ridge neighbor paths.

The resulting comparison contains seven matched family/operator rows and 56
exact-500 atoms. It uses validation data only. Test scoring, joint fitting,
MCMC, registry mutation, and article mutation remain blocked.

## Execution contract

The broad R106 scheduler is stopped without deleting its runtime directory.
Completed atom terminals and their hashed artifacts remain reusable. The four
focus cases are resumed with one case per physical core. The existing R106
worker performs the unchanged exact-500 fits and corrected pathwise
quantile-curve forecasts. A new focus orchestrator writes separate preflight,
progress, logs, and terminal records, then launches the read-only R107 closeout
only after all four case terminals validate.

R107 materializes:

- matched aggregate forecast metrics;
- 96-horizon metric comparisons;
- iteration-200 versus iteration-500 ELBO, sigma, and gamma stability;
- forecast-band and horizon diagnostic PDF;
- raw total-ELBO diagnostic PDF;
- source hashes, gates, JSON summary, and Markdown report.

## Pre-registered decision gate

A matched row is practically equivalent when all hold:

- absolute relative AQL change is at most 1 percent;
- absolute 10--90 percent coverage change is at most 0.02;
- absolute relative 10--90 percent width change is at most 5 percent.

A matched row is materially better when validation AQL improves by at least 2
percent, its distance from nominal 0.80 coverage does not worsen by more than
0.02, and quantile crossing does not exceed both 0.01 and the R104 value plus
0.005.

The broad exact-500 campaign is unsupported when all seven rows are practically
equivalent. A broad resume is supported only when at least five of seven rows
are materially better and no row is materially worse. Every other pattern is a
mixed result requiring focused forecast-mechanism diagnosis. These thresholds
are fixed before R106 focus forecasts are observed.

## Interpretation boundary

R104 and R106 use the same validation windows, quantile surface, corrected
recursive operator, and 500 posterior paths. Their stage-specific random seeds
are not identical, so the decision gate is based on practical rather than
bitwise equivalence. R107 determines whether the extra VB iterations change
forecast behavior. It does not determine article promotion or open outer-test
outcomes.
