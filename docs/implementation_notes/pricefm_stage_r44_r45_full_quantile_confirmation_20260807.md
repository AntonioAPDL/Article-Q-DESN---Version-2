# PriceFM Stage-R44/R45 full-quantile confirmation

## Decision

Stage-R43 is complete. Stage-R44 must reproduce the validation-only horizon-block selector, verify the restored R33 data/reservoir/training contract and consumed normal-to-AL-to-exAL warm chain, and freeze only cases that beat both paired shared exAL and the frozen R34 validation anchor under the 0.5% inner-fold harm guard.

The expected queue is case-specific: `NO_3` fold 2 uses weight `0.75` for horizons 1--24 and zero elsewhere; `NO_3` fold 3 uses `0.25` for horizons 1--24 and zero elsewhere.

## R45 design

R45 confirms those two frozen mechanisms at quantiles `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`. It restores the exact R43/R33 case contracts, uses paired shared and horizon-separate AL/exAL readouts, and retains the normal-to-AL-to-exAL initialization chain. The warm order starts at the median and moves outward.

Nested pooling-weight selection is disabled. R45 materializes the shared and separate prediction surfaces; the subsequent closeout applies the R44 weights. This prevents quantile-specific reselection and keeps the experiment confirmatory.

Only train and validation data are in scope. Test metrics, registry mutation, manuscript changes, and MCMC remain blocked until a future validation closeout passes aggregate, per-quantile, horizon-harm, convergence, quantile-crossing, and reproducibility gates.
