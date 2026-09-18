# PriceFM Stage-R106 exact-500 recursive quantile campaign

Stage-R106 replaces the user-stopped Stage-R105 run with an isolated
validation-only campaign. R105 was interrupted before any atom or case
completed, and its runtime directory remains preserved as non-authoritative
provenance. No R105 fit artifact is reused by R106.

R106 preserves the frozen 38-region, three-fold, seven-quantile scientific
surface and corrected pathwise quantile-curve forecast operator. It fits seven
AL-RHS and seven structured exAL-RHS atoms per region-fold case. The sole
inference-budget change is an exact iteration contract:

- `min_iter = 500`;
- `max_iter = 500`;
- convergence patience is one iteration;
- no retry may extend a fit beyond 500 iterations;
- every installed atom and raw ELBO trace must contain exactly 500 iterations.

The RHS global scale remains frozen for the first 50 iterations, leaving 450
iterations under the full variational objective. Numerical failures are retained
as evidence and marked ineligible rather than silently retried.

Training remains causal and teacher forced. Validation recursively samples the
target price from its rearranged seven-quantile curve. Graph cases compare fixed
Normal-RHS and Ridge neighbor paths with paired random uniforms. Fold 1 selects
one complete family/operator combination per region, which is then frozen across
all three folds. Test access, joint fitting, MCMC, registry mutation, and article
mutation remain blocked.
