# Persistent-heavy-tail V10 stable ordered exact-M0 correction

## Scope

V9 corrected the positive-support exAL latent-`s` draw with an exact,
cancellation-resistant one-sided Gaussian fallback. In the complete V9 `r7`
replay, previously failing worker 22 completed. Worker 24 progressed past the
old support failure and then stopped at an ordered-intercept bound collapse.
This is a second floating-point boundary in the same Gaussian sampling layer,
not a posterior-target, architecture, prior, or score change.

## Exact correction

Ordered intercept conditionals remain Gaussian with truncation bounds supplied
by neighboring intercepts. V10 samples them with exact rejection kernels:

- one finite bound: the V9 stable one-sided sampler;
- two finite bounds in a tail: a truncated exponential proposal with the
  Robert acceptance ratio, sampled as excess over the nearer boundary;
- an interval containing the Gaussian mode: uniform-envelope rejection in the
  original interval;
- no finite bounds: an ordinary Gaussian draw.

Every bounded draw must be strictly interior. Endpoint clipping, projection,
chain deletion, and partial score construction remain prohibited. The
posterior-target hash is unchanged; the effective-sampler hash records the
ordered-intercept kernel.

## Gates

- [x] Preserve V9 `r7` as immutable failed-but-informative evidence.
- [x] Implement exact one-sided and bounded Gaussian kernels.
- [x] Add extreme-tail, reflection, strict-interior, and repeated-order tests.
- [ ] Pass exact-M0, AL, RHS, recursive-score, source-guard, and mutation tests.
- [ ] Commit and push a dedicated V10 branch.
- [ ] Replay the complete campaign under one V10 commit.
- [ ] Require 36/36 MCMC chains and 12/12 scores with verified manifests.
- [ ] Decide promotion from matched mean fit and forecast evidence, treating
      scalar mixing as review-level unless functionals are pathological.
- [ ] Freeze one final handoff without modifying article or Overleaf files.
