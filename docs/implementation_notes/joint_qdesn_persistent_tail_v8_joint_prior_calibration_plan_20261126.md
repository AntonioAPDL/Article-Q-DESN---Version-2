# JOINT persistent-heavy-tail V8 joint-prior calibration

## Decision

V7 demonstrated that the V6 reservoir architecture supports strong independent AL and exAL fits,
while both joint models fit every quantile poorly. The failure is therefore not evidence for another
DESN search. V8 changes only the joint anchor and adjacent-difference regularized-horseshoe scales
and slabs. It uses fresh non-protected stronger-window fixtures and cannot alter article authority.

## Frozen design

- Scenario: `persistent_heavy_tail` only.
- Architecture: V6 candidate 2430, unchanged.
- Data: 500 reservoir washout rows, 1,000 fitting rows, and 300 internal rolling-origin rows.
- Forecast: teacher forcing between ten origins and recursive 30-step prediction within each origin.
- Readout: intercept plus every retained reservoir layer; no raw inputs.
- Quantiles: `0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`.
- Selection score: DGP-integrated finite-grid quantile score, after fit eligibility.
- exAL: structured VB and exact M0 MCMC only.

The 105-arm design crosses five anchor scales (`1e-11` through `1e-3`), seven innovation scales
(`1e-13` through `1e-1`), and three slab profiles. The exact V7 prior is an explicit baseline.
This is broad enough to test the over-shrinkage diagnosis while remaining a bounded, interpretable
experiment.

## Stages

1. A ten-arm, two-likelihood sentinel verifies finite joint fits, scoring, and source isolation.
2. The full 105-arm AL-VB screen runs on three fresh matched fixtures.
3. The 16 best worst-band fits form the fit frontier; forecast score chooses at most eight arms.
4. Those arms plus baseline run under AL and exAL on five new fixtures with full VB budgets.
5. One arm per likelihood is frozen using fit-first then forecast ranking.
6. Selected-versus-baseline joint-only MCMC uses three chains on three qualification fixtures.
7. Functional score stability, fit, forecast, crossings, manifests, and hashes determine whether a
   separately frozen protected confirmation is justified.

Mild scalar mixing is review-level. Nonfinite output, contract crossings, uniformly poor quantile
fit, unstable quantile functionals, or score-chain pathology remain disqualifying. Interval width
alone is never optimized.

## Boundaries

Independent models are not refitted. The protected article fixture is neither loaded nor scored.
No architecture, DGP, split, score definition, sampler kernel, article file, or Overleaf file may
change. Completed V6 and V7 runtime remains immutable.

## Checklist

- [x] Audit V6/V7 evidence and older fixed-backbone prior experiments.
- [x] Reject another architecture screen and an MCMC-first factorial campaign.
- [x] Freeze prior axes, seeds, budgets, fit-first selection, and resource gates.
- [x] Implement preparation, context, VB, MCMC, score, and closeout stages.
- [x] Add focused cardinality, leakage, target-identity, AL-kernel, exact-M0, recursive-design,
      and DGP-oracle tests.
- [ ] Commit and push the dedicated branch; mirror the exact HEAD on Jerez.
- [ ] Run the sentinel and stop on any source, fit, score, or capacity defect.
- [ ] Complete screen, qualification, and MCMC only through frozen stage decisions.
- [ ] Produce a frozen handoff without changing article authority.

## Implemented execution graph

The preparation stage verifies the frozen V6 decision, finalist, and aggregate hashes before it
copies any source evidence. It then freezes one sentinel context, three full-screen contexts, five
qualification contexts, the complete 105-arm prior registry, and immutable worker-plan receipts.
Every context is generated from a fresh non-protected seed and contains the fixed V6 reservoir,
independent AL/exAL warm starts, the recursive forecast map, and a converged DGP oracle. Context,
fit, draw, score, and decision artifacts are published atomically with SHA-256 manifests.

The launcher is Jerez-only, requires pinned R 4.6.0, a clean branch synchronized with its upstream,
distinct physical cores, at least 80 GiB free under `/data`, and at least 128 GiB available memory.
It enforces predecessor completion and never finalizes or starts a downstream scientific stage.
Finalization remains an explicit audited action after every stage.

The AL MCMC confirmation uses the corrected positive-unbounded scale update. The exAL confirmation
uses only `M0_v_collapsed_support_logit`. Complete target hashes include likelihood identity,
fixed design identity, all four joint-prior coordinates, hierarchy, and scale support. The final
decision uses fit, forecast score, crossings, and posterior quantile-functional stability; scalar
mixing remains review-level unless it accompanies functional pathology.

## Verified prelaunch checks

The following pinned-R checks passed before the source freeze:

- `test_joint_qdesn_persistent_tail_v8.R`
- `test_joint_qdesn_persistent_tail_v7.R`
- `test_joint_qdesn_al_kernel_correction.R`
- `test_joint_exqdesn_inference_dispatch.R`
- `test_joint_qdesn_recursive_mean_design.R`
- `test_joint_qdesn_recursive_dgp_oracle.R`
- `test_joint_qdesn_fixed_backbone_prior_screen.R`
- `bash -n application/scripts/launch_joint_qdesn_persistent_tail_v8_stage.sh`
- `git diff --check`

A real-source preparation smoke also passed using the frozen V6 runtime: 105 prior arms, 20
sentinel workers, 315 AL-screen workers, zero protected rows, and verified source/preparation
manifests. This smoke performed no model fit and produced no article asset.

The first Jerez context attempt stopped before publishing a context because its selector design did
not yet carry the explicit 10-by-30 internal forecast map required by the DGP oracle. The failure
occurred after warm-start fitting and before every prior-arm worker. The correction adds an exact
map constructor with cardinality, contiguity, origin, and horizon tests. The failed runtime remains
frozen as negative evidence; execution resumes from a separately prepared runtime root at a newly
pinned source commit.

The first corrected-map attempt then exposed an original-index boundary: the selector design keeps
full-series time indices while its compact fixture is reindexed to 1,800 rows. V8 now carries a
separate original-index oracle fixture truncated exactly at the end of internal calibration. This
supports recursive lags and DGP scoring while excluding all 1,000 protected rows. Unit checks and
the context worker both fail closed if the forecast map exceeds this boundary or a `validation` row
is retained. No prior arm had run when this second context-only defect was found.

All three full-screen contexts then reached oracle construction. Two passed with two shards; the
third did not meet the unchanged `0.003` split-half tolerance within the original four-shard cap.
Because this is Monte Carlo integration precision rather than model evidence, the cap is increased
to eight paired shards while preserving paths per shard, seeds, tolerances, DGP, and score. The
oracle still stops at the first passing even-shard checkpoint. A failed oracle now reports its path
count and achieved split-half and horizon-one errors. No prior-screen worker had started.

The first complete broad screen found 54 deterministic singularities: 18 extreme arms failed in all
three matched fixtures, while 261 workers completed. These are valid negative screening results,
not candidates for jitter or partial-replicate rescue. V8 now publishes such screen failures as
manifested `DISQUALIFIED` receipts. Any arm with one receipt is excluded wholesale, and every arm
remaining eligible must have all three matched replicates. Failures in sentinel, qualification, or
MCMC stages remain fatal. The original 261/54 runtime remains frozen; the corrected terminal-state
contract is replayed in a fresh runtime at a newly pinned source commit.

The corrected `r5` replay completed the sentinel, 315-worker screen, and 90-worker qualification
without failure. It selected `v8_prior_098` for AL and `v8_prior_105` for exAL against the explicit
`v8_prior_045` V7 baseline. The first MCMC confirmation then stopped fail-closed after exact-M0
worker 22 reported `s must be nonnegative`. Eighteen AL chains had completed, one exAL chain had a
manifested failure, and no score stage was authorized. The executed path showed that the external
truncated-normal generator can rarely return a floating-point value outside its declared support.

The correction does not clip or project the latent variable. It rejects any nonfinite or
out-of-support numerical result and redraws that coordinate from the same truncated-normal
conditional, with a finite retry ceiling and a hard failure if the generator repeatedly violates
support. Each exAL MCMC artifact records its support-redraw count. A focused injected-generator test
proves that a negative draw is replaced by a fresh interior draw rather than by a boundary value;
the exact-M0 dispatch and collapsed gamma-scale regressions also pass. Because this touches the
shared exAL sampler, the source guard now authorizes exactly that one modified core file in addition
to the eight V8 files. The failed `r5` runtime remains immutable negative evidence. Production
resumes as a complete `r6` replay from preparation under one corrected commit; no `r5` fit or chain
is eligible for final scoring.
