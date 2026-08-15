# PriceFM Stage-R49 MCMC capability audit

Stage-R49 is a read-only bridge audit between the frozen R47/R48 test decision and any confirmatory MCMC campaign.

It verifies core exdqlm support for Q-DESN RHS_NS MCMC, internal VB warm starts, explicit initialization, and posterior prediction. It separately verifies the PriceFM runner surface. The distinction is material: core support exists, but the PriceFM runner has no MCMC path for the frozen shared-static plus horizon-block prediction blend.

The audit is conditional on R48. A case that does not beat both authoritative Q-DESN and cached PriceFM on frozen test cannot proceed. For a passing case, the future runner must preserve the R46 specification, fit seven quantiles for the shared component and each nonzero-weight horizon block, and apply the frozen validation-selected weights. The resulting operation is a convex blend of quantile predictions, not a posterior-mixture distribution.

Stage-R49 writes CSV, JSON, Markdown, and source hashes. It writes no launch YAML and authorizes no fitting, registry mutation, or article mutation.
