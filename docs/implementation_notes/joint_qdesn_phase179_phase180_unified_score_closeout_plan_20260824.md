# Joint QDESN Phase179 Closeout and Phase180 Unified Score Plan

Date: 2026-08-24

Status: Phase179 sampling and finalization are complete. This document freezes
the result interpretation, reconciles the preceding plans, and defines the
only authorized route to a balanced article packet. It does not authorize a
launch from the current branch, modify article assets, merge `main`, or publish
Overleaf.

## 1. Audit Verdict

Phase179 is complete rather than stale:

- 384 of 384 chain workers completed with exit code zero;
- all 24 candidate-replicate cases are present;
- the final 25-file audit manifest verifies by size and SHA-256;
- all forecast score values are finite;
- all reported contract quantile grids are noncrossing;
- five scenario-readout cells have fresh protected evidence;
- three nonparity controls are promoted and two cells retain parity.

No additional case-specific screening should precede article-fixture
confirmation. The next production job is blocked only by repository
integration: this branch is based on a merge base that is 53 commits behind
the current `origin/main`, and its 11 scientific commits are not yet present on
`main`. Launching from this worktree would create another long-lived ancestry
fork and violate the scientific-lane handoff contract.

## 2. Reconciliation of Earlier Plans

The plans are not competing versions of one ranking. They describe successive
estimands and must remain separately reproducible.

1. **Phase178 original authority.** Phase178 was launched and closed under a
   frozen forecast oracle-quantile MAE ranking. That history is immutable.
2. **Post-Phase178 current-grid audit.** The first DGP-integrated score audit
   used a conservative 0.5% practical near-tie margin and retained parity in
   the five targeted cells. This remains useful historical sensitivity
   evidence.
3. **Phase179 prospective authority.** At the user's direction, Phase179 froze
   a separate any-positive-gain rule before using fresh confirmation seeds.
   Promotion required a lower median DGP-integrated score, favorable direction
   on at least two of three replicates, oracle-recovery safeguards, finite
   functionals, verified sources, and zero contract crossings. These fresh
   decisions are the authority for the next article-fixture stage.
4. **Dense-grid plan.** The proposed 19-level grid changes the fitted models.
   It remains a later, separately frozen study and cannot be substituted for
   completing the current seven-level article packet.

The legacy Phase179/180 scripts numbered 257--260 remain MAE-centered. They
must not be run unchanged for the score-centered article workflow.

## 3. Scientific Result Frozen by Phase179

Selection remains specific to each scenario-readout cell. No common DESN
configuration or common `tau0` is selected.

| Scenario/readout cell | Final role | Variant | `tau0` | `zeta2` | Alpha prior SD | Median score gain |
|---|---|---|---:|---:|---:|---:|
| Laplace bridge, independent exQDESN | Retain parity | parity | 0.5000 | 32 | 1.25 | 0 |
| Normal bridge, independent exQDESN | Promote | `tau0_upper` | 0.9975 | 16 | 0.75 | 0.01884% |
| Persistent heavy tail, independent exQDESN | Retain parity | parity | 0.5000 | 16 | 1.00 | 0 |
| Regime shift, independent exQDESN | Promote | `tau0_lower` | 0.3350 | 32 | 1.25 | 0.05229% |
| Regime shift, joint exQDESN | Promote | `tau0_lower` | 0.1005 | 64 | 1.00 | 0.00968% |

The gains are deliberately described as small. They repeat in two of three
fresh replicates and satisfy the predeclared any-gain rule, but they do not
support a broad claim that one control dominates across mechanisms.

## 4. Diagnostic Interpretation

The implementation gates pass, while the overall evidence gate remains
`review`:

- posterior score functionals: 23 pass and 1 review;
- contract crossings: zero;
- selected raw crossing rates: approximately 1.0% to 5.35%;
- independent product-posterior pairing sensitivity: all pass, with maximum
  relative mean shift below `3.5e-5`;
- worker computation: approximately 4,237 core-hours.

The M0 parameterization has addressed the earlier gamma/sigma bottleneck:

- maximum gamma rank R-hat is about 1.007 and minimum bulk ESS about 2,092;
- maximum sigma rank R-hat is about 1.006 and minimum bulk ESS about 2,601.

The remaining scalar review is concentrated in alpha/intercept and trend
geometry, with worst rank R-hat near 1.44 and bulk ESS near 36. These scalar
reviews do not invalidate stable score functionals, but they must remain
visible. No further gamma-focused screen is justified before the article
fixture is evaluated.

## 5. Score Contract

The primary action metric is `dgp_integrated_acrps`, the DGP expectation of the
finite-grid integrated quantile score. It evaluates the issued quantile vector;
it does not construct a scalar posterior predictive density from the joint
AL/exAL composite working likelihood.

The current grid is

```text
0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95
```

The trapezoidal weights applied to `2 * check loss` are

```text
0.025, 0.10, 0.20, 0.25, 0.20, 0.10, 0.025
```

They sum to 0.90 and are not renormalized. Each final row must retain:

- posterior score mean, median, and equal-tailed 95% credible interval;
- canonical monotone-action DGP-integrated score;
- realized finite-grid aCRPS as compatibility evidence;
- check loss and fit/forecast oracle MAE/RMSE as diagnostics;
- raw and contract crossings plus adjustment diagnostics.

Joint draws preserve learned cross-quantile dependence. Independent fits use
the frozen seeded, chain-balanced product-posterior coupling. Score-functional
stability, not perfect scalar mixing, is the relevant computational safeguard.

## 6. Source-Completeness Audit

The balanced article authority has exactly 32 scenario-model rows: eight
scenarios for each of four model/readout combinations.

| Source | Article cells | Retained posterior-draw cells | Decision |
|---|---:|---:|---|
| Joint QDESN under AL | 8 | 0 | Rerun for draw-level score intervals |
| Independent QDESN under AL | 8 | 0 | Rerun for draw-level score intervals |
| Joint exQDESN under exAL | 8 | 8 | Reuse verified Phase172 draws, except promoted replacements |
| Independent exQDESN under exAL | 8 | 8 | Reuse verified Phase172 draws, except promoted replacements |

Both Phase154 AL manifests verify, but those packets are action-summary only
and contain no `posterior_draws.csv.gz`. Phase172 retains all 16 exAL cells,
eight chains per cell; its 128 worker manifests and top-level manifest verify.
Credible intervals must not be fabricated from the AL point summaries.

## 7. Ordered Execution Contract

### Stage A: Close and hand off Phase179

1. Verify the final Phase179 audit manifest.
2. Freeze the five decisions, controls, selected score diagnostics, parameter
   diagnostics, balanced source inventory, provenance, and next-stage contract.
3. Run focused JOINT tests and verify the closeout manifest.
4. Commit and push only the dedicated scientific branch.
5. Leave the worktree clean and exactly synchronized with its upstream.
6. Issue a frozen handoff marked `READY_FOR_INTEGRATION` only if every hard
   gate passes.

### Stage B: Integrate before new production work

The integration coordinator merges the dedicated branch and validates the
combined repository. After integration, create a new JOINT branch from the
latest `origin/main`. Do not cherry-pick ad hoc subsets into an unintegrated
worktree and do not launch from the Phase179 branch.

### Stage C: Matched article-fixture confirmation

Freeze exactly six cases: each of the three promoted challengers and its
matched parity control. Use the already frozen article realization only after
selection is complete. Keep the exact M0 method, current seven-level grid,
frozen case-specific DESN/RHS controls, structured-v initialization, and 16
chains per case. The expected campaign is 96 workers.

This is an evaluation stage, not another specification search. The selected
control is not changed because of a favorable or unfavorable single article
realization. A candidate is withheld only for an implementation, provenance,
finiteness, score-functional, or contract-crossing failure.

### Stage D: Complete the balanced 32-cell posterior-score packet

1. Reuse the 16 hash-verified Phase172 exAL draw cells.
2. Replace the three promoted exAL cells with their verified article-fixture
   confirmations; retain Phase172 controls for the remaining 13 exAL cells.
3. Rerun the 16 AL article cells because posterior draws were not retained.
   Freeze eight chains per cell with the Phase172-equivalent 24,000 iterations,
   4,000 burn-in iterations, and thinning by 4 unless a pre-launch code audit
   finds a model-specific incompatibility. This is 128 chain workers.
4. Recompute all 32 rows under one score contract and one deterministic
   posterior-summary implementation.
5. Verify exactly 32 finite rows, eight per model, zero contract crossings,
   complete hashes, and explicit review flags for raw crossings or weak
   functionals.

### Stage E: Phase180 article packet

Only after Stage D passes should a new Phase180 packet be staged. The table
headline is the DGP-integrated finite-grid quantile score, with posterior mean
and 95% credible interval. Realized aCRPS and check loss are secondary;
fit/forecast MAE and RMSE are oracle path-recovery diagnostics. Numerical
winners remain descriptive when Monte Carlo or replicate uncertainty is
incomplete.

Article assets are staged on the JOINT branch for integration review. This
lane does not merge `main`, publish Overleaf, or directly edit another lane's
runtime state.

### Stage F: Dense 19-level study

The 19-level grid is a later refit campaign, not post-processing. It begins
only after the seven-level packet is frozen. It must have its own grid,
quadrature, seed, case-specific control, crossing-opportunity, and compute
contract. It cannot delay the current-grid article closeout.

## 8. Gates

Hard failure:

- missing, mismatched, or unverifiable sources and manifests;
- missing posterior draws for a claimed score interval;
- nonfinite quantiles or scores;
- train/forecast leakage or row misalignment;
- nonzero contract crossings;
- materially unstable posterior score functionals;
- silent control, seed, grid, or quadrature changes.

Review:

- weak scalar alpha/trend mixing with stable score functionals;
- large or frequent raw crossings or monotone adjustments;
- one score-functional review among otherwise valid replicates;
- small numerical gains, runtime outliers, or incomplete uncertainty support.

Pass:

- all implementation and provenance gates pass;
- score summaries and intervals are source-complete;
- reported contract paths are finite and noncrossing;
- case-specific controls remain frozen and traceable.

## 9. Checklist

- [x] Preserve Phase178 original ranking.
- [x] Freeze the seven-level DGP-integrated score contract.
- [x] Run fresh protected Phase179 confirmation.
- [x] Complete 384/384 workers with zero failures.
- [x] Freeze three promotions and two parity decisions.
- [x] Verify the 25-file Phase179 audit.
- [x] Inventory all 32 article cells and retained draws.
- [x] Freeze and verify the Phase179 closeout packet.
- [x] Commit and push the closeout implementation.
- [x] Issue the clean integration handoff in the containing task commit.
- [ ] Integrate through the integration coordinator.
- [ ] Create a fresh main-based JOINT branch.
- [ ] Freeze and run the 96-worker matched article-fixture confirmation.
- [ ] Freeze and run the 128-worker AL posterior-draw completion.
- [ ] Build and verify the 32-row Phase180 score packet.
- [ ] Stage article-safe assets for integration review.
- [ ] Consider the separate 19-level campaign.

## 10. Immediate Decision

The scientifically optimal immediate action is to freeze and hand off the
completed Phase179 evidence. It is neither necessary nor safe to start another
screen or production launch from the current branch. The next launch is the
96-worker matched article-fixture confirmation, but only after integration and
creation of a fresh branch from current `origin/main`.
