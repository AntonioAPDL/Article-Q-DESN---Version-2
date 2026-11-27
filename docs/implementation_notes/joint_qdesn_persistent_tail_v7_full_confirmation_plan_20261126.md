# JOINT persistent-heavy-tail V7 full-model confirmation

## Decision and scope

V6 completed the intended fit-first and tail-prior calibration and confirmed candidate
`persistent_heavy_tail__fitfirst_v4_2430` on five fresh non-protected seven-level fixtures. V7 is
the one authorized continuation: a protected, matched, complete four-model confirmation. It is not
another screen and does not change the architecture, quantile grid, data split, forecast policy,
likelihoods, sampler kernels, or current authority.

The packet contains independent and joint QDESN under AL and exAL, first under VB and then under
matched MCMC. Every exAL MCMC chain uses exact M0. Three chains per model and the existing
2,000/4,000 AL/exAL budgets match the corrected authority. Scalar mixing is review-level unless
forecast or fit functionals are pathological.

## Prior translation

The independent fits use the V6 level-specific lower, middle, and upper profiles exactly. A joint
RHS prior is defined on the first-quantile anchor and adjacent differences, not on seven unrelated
quantile-specific coefficient vectors. The frozen translation is therefore:

- lower V6 profile for the first-quantile anchor;
- median V6 profile for the shared adjacent-difference prior;
- all seven level-specific independent fits, including the upper profile, initialize the joint fit.

This uses the existing prior family and API. It does not invent level-varying innovation priors or
pretend that independent and joint parameterizations are identical.

## Reused immutable evidence

- V6 decision, finalists, and seven-level aggregate are hash pinned.
- The corrected current-authority selected packet and decision are hash pinned.
- The article fixture and recursive-DGP oracle bank are reused by hash.
- Historical outputs remain immutable and excluded from Git.

## Stages

- [x] Audit V6, current authority, corrected AL kernel, exact-M0 dispatch, forecast policy, and score contract.
- [x] Freeze the V7 contract and source hashes.
- [ ] Prepare one 17-component VB packet and verify the protected design without scoring it.
- [ ] Run and finalize the VB packet.
- [ ] Freeze 12 MCMC workers, three for each of four model cells.
- [ ] Run AL with the corrected unbounded inverse-gamma update and exAL with exact M0.
- [ ] Verify target/kernel identities, finite draws, and zero contract crossings.
- [ ] Produce eight score rows: VB and MCMC for all four models.
- [ ] Compare the four candidate MCMC rows with the four corrected authority rows.
- [ ] Promote only as a complete scenario packet when at least one mean score improves and all four
  candidate means remain within 1% of authority, with no functional pathology.
- [ ] Freeze manifests, transfer inventory, hashes, tests, storage status, and the final handoff.

Interval overlap is not predictive equivalence. Article and Overleaf files remain untouched until
the final packet has closed and a separate integration review accepts it.
