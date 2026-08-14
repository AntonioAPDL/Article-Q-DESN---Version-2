# Joint exQDESN Phase147 Hybrid Geometry

Phase146 showed that ridge-aligned joint moves improved Student-t fit and
forecast summaries and reduced runtime, but acceptance and between-chain
diagnostics were inadequate. Phase147 therefore composes, rather than
substitutes, transition kernels: the established conditional sigma, latent-s,
and logit-gamma refresh is followed by smaller joint moves on transformed
log-sigma and logit-gamma coordinates.

The model, prior, DESN specification, tau0, fixture, and validation contract
remain fixed. This is a sampler experiment for one case and does not impose a
common DESN specification across scenarios.

Two hybrid profiles use quantile-specific scales. Moves are tighter at 0.25
and 0.75, where Phase146 found the strongest gamma-sigma ridge. The output
records acceptance by chain and quantile, variant-preserving score summaries,
and qhat differences between two independent halves of the chain set.

The overnight packet contains three variants, eight chains per variant,
15,000 iterations, 3,000 burn-in iterations, and thinning by three. Promotion
requires implementation integrity, noncrossing contract output, reasonable
per-quantile acceptance, posterior qhat stability across chain groups, and
acceptable gamma R-hat/ESS. Forecast MAE is secondary to stable approximation
of the fixed posterior.
