# Persistent-heavy-tail V9 tail-stable exact-M0 correction

## Purpose

This correction closes the numerical failure exposed by the complete V8 `r6`
MCMC campaign without changing the posterior target, reservoir, prior grid,
selection rule, seeds, iteration budgets, score, protected-data boundary, or
article authority. The correction is confined to the numerical realization of
the positive-support Gaussian full conditional for the exAL latent variable
`s`.

## Frozen evidence and diagnosis

The V8 `r6` sentinel, screen, and qualification stages completed under commit
`335b7042267b9e1c9e5fd4cc5862bfd627186961`. The MCMC stage produced 34 finite
chains and failed closed for workers 22 and 24. Both failures were baseline
exAL chains for qualification context 5, and both reported that the external
truncated-normal generator repeatedly violated its declared support. All 18 AL
chains, all nine selected exAL chains, and seven of nine baseline exAL chains
completed. No partial score packet is authorized.

The conditional target is a Gaussian distribution truncated to `[0, Inf)`.
Repeating the same external numerical routine is not a remedy when extreme-tail
cancellation repeatedly produces an invalid floating-point result. Clipping to
zero would create a boundary atom and is prohibited.

## Correct numerical kernel

The first attempt remains the established truncated-normal generator. If that
attempt is nonfinite or outside support, the correction uses an exact
one-sided Gaussian sampler:

1. Standardize the finite truncation boundary.
2. For a nonpositive standardized threshold, use ordinary Gaussian rejection,
   whose acceptance probability is at least one half.
3. For a positive threshold, use Robert's exponential rejection proposal with
   rate `(a + sqrt(a^2 + 4)) / 2`.
4. Sample and retain the excess over the finite boundary directly, then map it
   back as `boundary + sd * excess`. This avoids cancellation in
   `mean + sd * z`.
5. Verify every returned value is finite and inside support. No clipping,
   projection, or boundary replacement is permitted.

The posterior-target hash remains unchanged. A separate effective-sampler hash
records the numerical kernel. MCMC summaries also record support violations,
tail fallbacks, proposal counts, and the maximum standardized tail threshold.
Chains can be combined only when both target and sampler hashes agree.

## Verification and execution

- [x] Freeze the V8 `r6` failures and prohibit partial scoring.
- [x] Derive an exact cancellation-resistant one-sided Gaussian kernel.
- [x] Implement additive sampler diagnostics and sampler-control hashing.
- [ ] Pass deterministic support, reflection, extreme-tail, and moment tests.
- [ ] Pass exact-M0, AL-kernel, recursive-score, RHS, and V8 regression tests.
- [ ] Refresh the exact scoped source manifest and mutation-tested source guard.
- [ ] Commit and push the dedicated correction branch.
- [ ] Prepare a fresh `r7` runtime under one corrected commit.
- [ ] Replay sentinel, screen, qualification, all 36 MCMC chains, and scoring.
- [ ] Require complete manifests, finite draws, zero contract crossings, and
      matched selected-versus-baseline evidence.
- [ ] Freeze the closeout and provide one integration handoff. Do not modify
      article or Overleaf files.

Scalar gamma/sigma mixing remains review-level unless posterior quantile
functionals or forecast scores are pathological. Promotion remains driven by
matched mean fit and forecast performance under the frozen V8 rule.
