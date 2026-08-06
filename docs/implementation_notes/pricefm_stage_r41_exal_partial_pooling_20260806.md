# PriceFM Stage-R41 exAL partial-pooling qualification

R40 showed that R39 improved its paired AL shared readout in six cases but
produced no promotion candidate. Six of the eleven authoritative R34 anchors
use exAL, so R39 changed likelihood and readout together for those cases.

R41 removes that confound. It freezes each R34 reservoir, feature policy,
history, seed, regularization, horizon blocks, five nested folds, pooling grid,
one-standard-error preference, and 0.5% harm guard. It changes only the fitting
likelihood from AL to exAL for the six exAL-anchor cases. The five AL-anchor
cases are excluded because R39 already tested the likelihood-matched mechanism.

The runner capability audit verifies that exAL is consumed by shared fitting,
separate horizon-block fitting, gamma warm starts, and partial-pooling metric
materialization. Test, registry, article, full-quantile, and MCMC actions remain
blocked pending the future R42 closeout.
