# Persistent-heavy-tail V12 adaptive Gaussian exact-M0 correction

## Objective and boundary

Finish the frozen persistent-heavy-tail V8 joint-prior calibration without
changing its posterior target or scientific selection contract. V12 corrects
only the numerical implementation of the ordered-intercept bounded-normal
Gibbs update exposed by immutable V9/V10 replay evidence.

The following remain frozen: DGP and protected seeds, AL and exact-M0 exAL
likelihoods, reservoir architecture, readout, priors, qualification winners,
MCMC budgets, chain allocation, score definitions, promotion rules, and
article boundary. No V9/V10 output may be repaired, spliced, or promoted.

## Audited evidence

- The upstream sentinel, screening, and qualification stages completed with
  complete manifests and reproduced their frozen hashes.
- Qualification selected `v8_prior_098` for AL and `v8_prior_105` for exAL
  against baseline `v8_prior_045`.
- AL reduced worst-band fit error from 0.866718 to 0.059594 and the canonical
  score from 0.573261 to 0.519017.
- exAL reduced worst-band fit error from 0.614227 to 0.191657 and the canonical
  score from 0.547737 to 0.526496.
- V9 corrected cancellation in a one-sided exact-M0 truncated-normal update.
- V10 then exposed wide-central rejection and an ultra-narrow tail interval
  whose truncated-exponential proposal mass was not reliably represented.
- V10 failures are baseline-exAL workers 22, 24, and 34. They are sampler
  failures, not completed score or convergence evidence.

## Exact numerical kernel

For `Z ~ N(0,1)` restricted to `(a, a + w)`, with `w > 0`:

1. If `a > 0` and `lambda * w >= 0.1`, use Robert's exponential proposal with
   `lambda = (a + sqrt(a^2 + 4))/2`, truncated to `(0,w)`, and its exact
   rejection probability.
2. If `a > 0` and `lambda * w < 0.1`, propose the excess uniformly on `(0,w)`
   and accept with `exp(-a e - e^2/2)`. This is the exact Gaussian density
   ratio relative to the lower endpoint and avoids subtractive loss in the
   truncated-exponential mass.
3. Reflect intervals entirely below zero and apply the same right-tail kernel.
4. For intervals containing zero, use direct standard-normal rejection when
   `w > 2`; otherwise use a uniform envelope and accept with `exp(-z^2/2)`.
5. Compute `w = (upper-lower)/sd` directly. Do not obtain it by subtracting
   two very large standardized endpoints.
6. Require every draw to be finite and strictly interior. Exhausted proposal
   limits fail closed; clipping or boundary substitution is forbidden.

These kernels change proposal mechanics only. They do not truncate, clip, or
otherwise change the bounded-normal conditional.

## Alternatives rejected

- Increasing proposal limits alone does not repair an inefficient or
  numerically unresolved proposal.
- Clipping draws to their bounds changes the conditional and is forbidden.
- Reusing successful chains from V9/V10 would combine incompatible effective
  sampler hashes and obscure the replay history.
- Retuning priors, reservoirs, seeds, or budgets would confound a numerical
  correction with a new scientific experiment.
- Scoring partial MCMC output would violate the frozen 36-chain contract.

## Implementation and verification

1. Pin the adaptive backend in the effective sampler hash for both AL and
   exact-M0 exAL.
2. Pin the dedicated V12 execution branch in the frozen contract and launcher.
3. Refresh the exact nine-path source manifest and its independent source
   guard pin.
4. Test extreme one-sided tails, extreme narrow bounded tails, reflected
   tails, narrow central intervals, wide central intervals, strict ordering,
   target/kernel compatibility, and inherited AL/exAL regressions.
5. Require shell syntax, staged-diff, source-guard, and mutation checks to pass.
6. Commit and push only the dedicated V12 task branch and require 0 ahead / 0
   behind before remote execution.

## Production replay

After V10 closes naturally, preserve it as immutable negative evidence. On a
fresh Jerez V12 worktree, rerun preflight under pinned R 4.6.0 and create a
fresh ignored `r9` runtime. Use exactly 15 physical CPUs, affinity 0-14, and
the existing stage gates:

`sentinel_context -> sentinel -> screen_context -> screen ->`
`qualification_context -> qualification -> mcmc -> mcmc_score`.

Expected units are 1 context, 20 sentinel workers, 3 screen contexts, 315
screen workers, 5 qualification contexts, 90 qualification workers, 36 MCMC
workers, and 12 score workers. Each finalizer must verify health, source and
output manifests, hashes, and the frozen decision before the next stage.

## Promotion and failure policy

The replay qualifies only with 36/36 MCMC workers and 12/12 score workers,
zero unresolved numerical failures, finite scores, compatible target and
sampler identities, and complete manifests. Mixing diagnostics are interpreted
with the existing performance-first policy: imperfect scalar mixing is review
level when quantile functionals and scores are stable, but numerical failure or
functional instability cannot be waived.

Any new kernel failure freezes `r9` unchanged and returns to diagnosis. It does
not authorize a local retry, chain substitution, or article update.

## Closeout checklist

- [x] Audit V9/V10 failures and isolate both proposal defects.
- [x] Derive and implement exact adaptive central and tail interval kernels.
- [x] Add wide-central and extreme-narrow-tail regressions.
- [x] Refresh sampler identity, branch pins, manifest, and source guard.
- [x] Pass the complete local inherited and source-guard suite in one run.
- [ ] Commit and push the dedicated V12 branch; verify clean 0/0 status.
- [ ] Preserve V10 after natural closure with its final failure receipt.
- [ ] Pass the complete Jerez preflight from the clean V12 worktree.
- [ ] Reproduce all upstream gates in a fresh `r9` runtime.
- [ ] Complete 36/36 MCMC chains and 12/12 scores.
- [ ] Freeze analysis, manifests, hashes, storage status, and final handoff.

No article, main, Overleaf, or unrelated scientific lane is modified by this
plan.
