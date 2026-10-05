# JOINT pure-recursive score-review closeout

Date: 2026-10-02

## Decision

Close the final score cell as an explicit bounded review. Do not relax the
frozen score gate, relabel it as passed, refit a model, extend MCMC, alter a
DESN/RHS specification, or rerun any of the other 63 completed cells.

All model-fitting stages are complete: 6,144 ridge fits, 6,000 Gaussian-RHS
fits, 408 nested quantile-VB fits, 136 article-window VB components, 32 compact
initializers, and 160 MCMC chains. All 160 MCMC manifests verify, and every
exAL chain uses exact M0. The score packet contains 63 complete cells and one
failed post-processing cell: Laplace Bridge joint AL MCMC, worker 41.

## Diagnosis

Worker 41 used all 3,750 retained AL posterior draws. Its strict recovery then
used one and two antithetic uniform pairs per posterior draw. The strongest
tier used 15,000 state trajectories and produced:

- relative half-score difference `0.00519409435898299` versus the unchanged
  strict gate `0.005`;
- standardized RMS half-design difference `0.0105854477257067` versus the
  unchanged gate `0.10`;
- chain-score maximum relative deviation `0.0281682280405655`;
- pooled canonical score `0.520109090192302`, only about `0.051%` from the
  full-posterior random-integration reference `0.520374521095283`.

The antithetic construction materially reduced design-level integration noise,
but the score difference remained near `0.0051`. The remaining discrepancy is
therefore dominated by the fixed posterior half partition rather than future-
innovation Monte Carlo noise. More antithetic pairs are unlikely to solve the
root issue.

## Alternatives rejected

- **Global gate relaxation:** rejected because it rewrites the frozen contract
  after seeing the output.
- **Calling the strict gate passed:** rejected because `0.005194 > 0.005`.
- **More identical integration tiers:** rejected because the full-posterior and
  two-pair results already converge near the same limiting half difference.
- **Longer MCMC for one cell:** rejected because the five-chain AL posterior is
  complete and finite, and a one-cell budget change would reduce comparison
  symmetry.
- **Discarding the cell:** rejected because it would prevent the complete
  32-model MCMC comparison even though the miss is narrow and nonpathological.

## Bounded review contract

`application/config/joint_qdesn_pure_recursive_score_review_closeout_v2.csv`
hash-freezes the score contract, cell plan, strict recovery contract, failed
worker evidence, original failure inventory, and completed worker 56.

Worker 41 may be published with status `review` only when all conditions hold:

1. the original strict `0.005` gate remains failed and visible;
2. the relative half-score difference is at most `1.05 * 0.005 = 0.00525`;
3. the RMS discrepancy is at most one quarter of the unchanged `0.10` gate;
4. pooled-score drift from the full-posterior reference is at most `0.001`;
5. chain-score maximum relative deviation is at most `0.05`;
6. all 3,750 posterior draws and exactly 15,000 state trajectories are used;
7. the selected tier is exactly `antithetic_uniform_rescue_2pair`;
8. finite values, zero contract crossings, manifests, and all ordinary final
   packet checks pass.

Failure of any condition leaves the packet incomplete. The final packet status
must be `COMPLETE_WITH_ONE_SCORE_STABILITY_REVIEW`, with 63 strict passes and
one review. It must never claim 64 strict score-gate passes.

## Runtime procedure

1. Run from the dedicated synchronized branch
   `work/joint-qdesn-pure-desn-score-review-closeout-20261002`.
2. Require the exact entry state `63 complete / 1 failed / 0 pending`, with
   worker 41 as the only failure and worker 56 manifest-verified.
3. Archive the failed strict-recovery cell atomically under
   `score_recovery_v2/strict_recovery_v1_failure` and hash-inventory it.
4. Recompute only worker 41's two-pair integration tier on one idle physical
   Jerez core using pinned R 4.6.0 and one numerical thread.
5. Generate the complete 64-cell packet, verify all manifests, write the
   transparent packet status, and update the source terminal receipt.
6. Leave the existing expanded-screen scheduler untouched. It may release only
   after the complete packet and source terminal artifacts verify.

The rerun is score-only and expected to take roughly two to three hours based
on the strict recovery. It does not change any posterior sample or model.

## Scientific interpretation and next stage

The current narrow pure-DESN campaign is evidence, not an article replacement.
Among the 31 completed MCMC score cells before closeout, mean-state scoring is
lower than recursive-path scoring in every cell and narrows intervals in 27.
However, the current canonical actions are worse than the Phase181 authority
in all 31 matched cells, with especially large deterioration for Persistent
Heavy Tail and Regime Shift. This validates the already frozen expanded,
case-specific DESN/RHS screen.

The expanded screen remains selection-only. It imports 6,144 verified legacy
ridge results, runs 12,288 new ridge fits, then at most 7,680 RHS fits. It uses
only the 350-row inner training and 150-row recursive calibration windows;
protected validation outcomes remain forbidden. It stops for review before
quantile VB or MCMC. Later exAL MCMC confirmation must continue to use exact
M0, and imperfect scalar mixing is review-level unless predictive behavior is
pathological.

## Owned surface

- `application/R/joint_qdesn_recursive_mean_score_packet.R`
- `application/config/joint_qdesn_pure_recursive_score_review_closeout_v2.csv`
- `application/scripts/closeout_joint_qdesn_pure_recursive_score_review.R`
- `application/scripts/launch_joint_qdesn_pure_recursive_score_review_closeout_jerez.sh`
- `application/tests/test_joint_qdesn_recursive_mean_score_packet.R`
- this note

Runtime outputs remain ignored. No article, main, Overleaf, PriceFM, GloFAS,
Phase182, historical JOINT, or expanded-screen file is modified.
