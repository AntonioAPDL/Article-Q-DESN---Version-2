# Persistent-heavy-tail sealed V5 confirmation

## Decision being tested

V4 completed 31,902 failure-free fits but its frozen six-challenger gate stopped
the original S1 preparation because only two new profiles passed every separate
median, lower-tail, upper-tail, and horizon-one gate. That stop is preserved.
V5 does not reopen the search or reinterpret V4. It asks the narrower question
that remains scientifically useful: do either of the two V4-qualified profiles
retain their small mean score improvement on five untouched matched fixtures?

## Frozen inputs

The source is V4 branch
`work/joint-qdesn-persistent-tail-fitfirst-v4-20261125` at commit
`beedc227c0c40b2f4b77e0130f89c90bf1adc2da`. The source closeout manifest,
terminal decision, qualified-challenger table, and exact-control table are each
SHA-256 pinned in the V5 contract. Preparation fails closed if any byte,
identity, qualification gate, or source Git receipt differs.

The three profiles are fixed before sealed data are created:

- `persistent_heavy_tail__fitfirst_v4_3242`;
- `persistent_heavy_tail__fitfirst_v4_2430`;
- exact V2 control `persistent_heavy_tail__fitfirst_v4_0002`.

Their reservoir architecture, normal RHS scale and slab, AL scale multiplier,
and numerical controls are copied from the verified V4 packet. No tuning,
screening, alternative seed search, or favorable-row substitution is allowed.

## Sealed experiment

Preparation first writes and hashes the finalist table and selection receipt.
Only then does it materialize the five V4-reserved sealed DGP seeds. Each of the
three profiles is fit independently at quantiles 0.05, 0.50, and 0.95 on each
fixture, using all ten internal rolling origins and the already tested V4 S1
worker implementation. This produces 15 atomic workers. Protected evaluation
rows remain absent from every fixture and selection artifact.

Production is restricted to Jerez, pinned R 4.6.0, exactly 15 distinct physical
cores, one numerical thread per worker, at least 80 GiB free under `/data`, and
at least 128 GiB available memory. The launcher never runs the finalizer or a
downstream campaign.

## Decision contract

The primary quantity is the matched known-DGP integrated three-level quantile
score. Eligibility requires finite predictive functionals, zero contract
crossings, and all six exact-V2-relative safeguards:

- median fit MAE within `max(10%, 0.005)`;
- each outer-tail fit MAE within `max(15%, 0.015)`;
- median and each outer-tail horizon-one MAE within `max(15%, 0.015)`.

Scalar convergence warnings are review-level when the fitted and forecast
functionals are finite and stable. A challenger may authorize the next
seven-level independent-AL confirmation if it is eligible and has any strictly
lower mean DGP score than exact V2. The report includes mean, standard
deviation, median, empirical 95% interval, matched challenger-minus-exact
contrasts, and the number of fixtures favoring each challenger.

With five fixtures, intervals and their overlap are descriptive. Overlap does
not establish equivalence; a numerical improvement is not described as a
formal superiority result.

## Boundaries and stopping rule

V5 may authorize a separate seven-level independent-AL confirmation. It does
not fit joint models, exAL, or MCMC; does not update article assets; and does
not promote an article result. Any later exAL MCMC run must use exact M0. The
V5 branch is pushed for scientific review only and is never merged to main by
this lane.

## Reproducible checklist

- [x] Preserve the V4 closeout and its original six-challenger stop.
- [x] Freeze the exact V4 commit and four packet hashes.
- [x] Freeze exactly two challengers plus exact V2.
- [x] Freeze the 3 x 5 worker contract before sealed-fixture materialization.
- [x] Reuse the tested V4 three-quantile worker without changing its target.
- [x] Enforce separate fit and horizon-one gates in the V5 finalizer.
- [x] Report matched contrasts and descriptive intervals without equivalence claims.
- [x] Add atomic workers, plan hashes, capacity gates, and manifest verification.
- [x] Pass focused, inherited V4, posterior-contract, and DGP-score tests under R 4.6.0.
- [x] Commit and push the dedicated V5 branch; create a clean Jerez worktree.
- [x] Verify and materialize the untouched sealed panel.
- [x] Launch exactly 15 workers, monitor startup, and finalize only after 15/15 pass.
- [x] Freeze and push the result handoff without merging main or updating Overleaf.
