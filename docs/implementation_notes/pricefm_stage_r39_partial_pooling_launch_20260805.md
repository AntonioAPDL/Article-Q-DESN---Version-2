# PriceFM Stage-R39 Partial-Pooling Qualification

R39 is the bounded implementation-stage qualification authorized by R38. It
freezes the 11 case-specific R34 reservoir anchors used by R36 and changes only
the consumed prediction pooling between paired shared and fully separate
24-hour-block AL/RHS_NS readouts.

Five embargoed rolling inner folds evaluate weights 0, 0.25, 0.5, 0.75, and 1
independently for each region/fold and horizon block. A future closeout must use
median inner-fold AQL, prefer stronger pooling under a one-standard-error rule,
require per-block convergence, and enforce the prospectively declared 0.5%
relative worst-fold noninferiority margin.

R39 is median mechanism qualification. Existing test, registry, article,
full-quantile, and MCMC actions remain blocked. Fresh article confirmation also
remains blocked by the absence of post-2025 observations and comparable PriceFM
forecast artifacts.
