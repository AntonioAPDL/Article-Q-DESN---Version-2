# JOINT persistent-heavy-tail v3 closeout

Date: 2026-11-24

## Scope and status

This lane performed case-specific discovery for `persistent_heavy_tail` only.
It did not modify the article, main, Overleaf, another scientific lane, or the
frozen v2 runtime. The terminal status is
`SEALED_Q3_COMPLETE_RECOMMEND_CASE_LEVEL_CONTINUATION`.

| Stage | Complete | Failed | Purpose |
|---|---:|---:|---|
| N0 | 90 / 90 | 0 | Tiny-global-scale equivalence audit |
| A1 | 12,288 / 12,288 | 0 | Broad early-origin ridge screen |
| A2 | 3,072 / 3,072 | 0 | Full-origin ridge screen |
| A3 | 1,152 / 1,152 | 0 | Reservoir-seed robustness |
| H1 | 1,344 / 1,344 | 0 | RHS global-scale screen |
| H2 | 300 / 300 | 0 | RHS slab screen |
| M1 | 288 / 288 | 0 | Median AL screen |
| T1 | 60 / 60 | 0 | Outer-tail AL sentinel |
| Q3 | 18 / 18 | 0 | Seven-level sealed confirmation |

The campaign completed 18,612 atomic workers. Q3 represents 126 quantile
component fits. Every Q3 component converged; scores are finite; warnings,
contract crossings, and protected-row use are all zero.

## Sealed result

| Finalist | Mean score | SD across three fixtures | Difference vs v2 | Raw crossings |
|---|---:|---:|---:|---:|
| Challenger 02 | 0.516373 | 0.053312 | +0.004791 improvement | 8 |
| Challenger 04 | 0.518599 | 0.053964 | +0.002565 improvement | 1 |
| Exact v2 winner | 0.521164 | 0.054717 | reference | 1 |
| Challenger 01 | 0.523186 | 0.056444 | -0.002022 deterioration | 3 |
| Challenger 03 | 0.525807 | 0.056047 | -0.004643 deterioration | 1 |
| Exact authority | 0.615570 | 0.048005 | -0.094406 deterioration | 98 |

The best challenger wins all three matched comparisons by `0.004634`,
`0.002826`, and `0.006912`. Its relative mean improvement over the exact v2
winner is about `0.919%`.

The winner is a one-layer, 48-state pure-reservoir model with eight response
lags, `alpha=0.5743352519`, opted-in `rho=1.16`, input scale `0.15`, recurrent
connection probability `0.02083333333`, and input connection probability
`0.02`. Its selected normal-RHS scale is `100`; the AL multiplier is `10`, so
the quantile RHS scale is `1000`; fixed slab variance is `0.25`.

This is a score improvement, not universal dominance. Its oracle quantile MAE
is `0.494261` versus `0.486921` for the exact v2 winner, and its eight raw
crossings exceed the reference's one. Contract crossings remain zero for both.
Only three sealed replicates were used, so overlapping uncertainty is expected
and does not establish predictive equivalence. The result qualifies a broader
case-level confirmation; it does not qualify direct article promotion.

## Provenance

- Branch: `work/joint-qdesn-persistent-tail-exploration-v3-20261124`
- Runtime: `application/cache/joint_qdesn_persistent_tail_exploration_v3_20261124`
- Numerical execution/finalization HEAD after A1: `ab7a6c976016af0e3a91cf265483d294197457f9`
- Finalist SHA-256: `1c2bb4737f1ec33fb1ebcc49a986b6056b366b3bc3eef0dc3fc15285a856d741`
- Q3 scores SHA-256: `ba344ee5eae263b68997f50a81eb7ac7722c4cde5b17ed0a22ff97d6cea144f0`
- Q3 aggregate SHA-256: `7643f6ff0e154b2a1b475e804f3ecb21361b6314ef16c4cf1fc81202a33e68d6`
- Matched contrast SHA-256: `bbc545b067d8c1fcd3a9d4ad070d827c034a0c34a1b181774b649b8b89472d07`
- Q3 decision SHA-256: `a09be61b8b390ad5d5c676f45d2a077dae9d7611329d0f68c897b30f1e0a6d25`
- Q3 manifest verification SHA-256: `8aa5ba10bb542e5b0f4b12311f8f3265ccefb5065a51ba9eaf38d46aa594ab8e`
- Sealed-fixture manifest SHA-256: `f167edd0798cdb47aa3b4fdc29449edee31c089923cee1382fbe5e67e8ea2e60`

The ignored Jerez runtime occupies approximately 718 MiB and must remain
excluded from Git. It is the authoritative evidence for this exploration and
should not be removed before the separate continuation is frozen and audited.

## Required next action

Freeze a new case-level continuation before running anything else. It should
compare the winning challenger with the exact v2 fallback under independent
and joint AL/exAL VB, then initialize matched MCMC from those VB fits. All exAL
MCMC must use exact M0. Use fresh protected seeds, retain both score and oracle
diagnostics, and treat the winner's additional raw crossings as a review item.

Do not merge this exploratory lane, update article assets, or publish Overleaf.
Integrate once only after the separately frozen four-model continuation closes
and identifies the final scientifically accepted case-level result.
