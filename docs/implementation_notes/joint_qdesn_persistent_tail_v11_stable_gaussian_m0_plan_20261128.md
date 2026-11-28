# Persistent-heavy-tail V11 stable Gaussian exact-M0 correction

V10 introduced exact strictly interior ordered-intercept draws. Its `r8` replay
showed that a uniform-envelope proposal is inefficient for a very wide finite
interval containing the Gaussian mode. This was an implementation-level
proposal choice: the conditional target and bounds remain correct.

V11 keeps the exact tail proposals and uses an adaptive exact central kernel:

- standardized interval width at most two: uniform-envelope rejection;
- wider interval containing the mode: standard-normal rejection;
- intervals wholly in a tail: bounded exponential rejection;
- one-sided bounds: stable one-sided Gaussian rejection.

All outputs remain strictly inside finite bounds. No clipping, projection,
partial-chain scoring, target change, prior change, or architecture change is
allowed. The effective-sampler hash advances to the adaptive interval kernel;
the posterior-target hash remains unchanged.

- [x] Preserve V10 `r8` as immutable negative evidence.
- [x] Add the adaptive exact central-interval proposal.
- [x] Add a wide-interval regression.
- [ ] Pass all focused, inherited, source-guard, and mutation tests.
- [ ] Commit and push the dedicated V11 branch.
- [ ] Complete one clean replay under one V11 commit.
- [ ] Require 36/36 MCMC chains and 12/12 score cells.
- [ ] Freeze final manifests, analysis, and integration handoff.
