# PriceFM Stage-R110C target-driver representation diagnosis

Date: 2026-09-21

R110B improved frozen Q-DESN self recursion by 68.09 percent but missed the
fixed R97-proximity gate by four percentage points. Stage R110C tests a narrow
mechanism question without fitting any model: whether stochastic target-path
construction, rather than the saved direct-driver marginal forecast, causes
the remaining propagation loss.

The stage reuses the same R110 analytic quantiles and frozen R103 Q-DESN
readouts. It compares the already materialized raw posterior paths with a
repeated analytic median and rank-coupled paths reconstructed from the seven
analytic quantiles. Fold 1 alone selects one representation; folds 2 and 3
confirm it against the frozen R108 self-recursive and R97 direct-reference
surfaces. Every case retains 500 paths and uses one single-thread process.

## Fixed scientific question

R110B established that an improved future-price driver removes most of the
self-recursion failure, but it remained 14.00 percent above the frozen R97
direct-reference AQL and therefore missed the prospectively fixed 10 percent
gate. R110C asks one narrower question: is the remaining loss caused by how
the already fitted R110 distribution is converted into recursive target-price
paths? It cannot change the DESN, readout, feature policy, likelihood, tau0,
neighbor paths, validation observations, or comparator values.

## Candidate representations

- `raw_posterior_paths` reuses the completed R110B result and is not recomputed.
- `analytic_median` repeats the saved R110 conditional median over 500 paths.
- `analytic_quantile_curve` uses fixed stratified uniforms to construct 500
  rank-coupled paths from the seven saved R110 analytic quantiles.

All candidates replay the same frozen R103 AL/exAL Q-DESN posterior readouts.
The target-region price history is replaced by the candidate path while the
existing R102B Normal-RHS paths for graph neighbors remain unchanged.

## Selection and confirmation

Fold 1 is the only selection fold. It selects one representation by pooled AQL
over BG, EE, and BE, with a deterministic name-based tie break. Folds 2 and 3
are then used once as prospective confirmation. A non-raw candidate authorizes
R111 only if all six confirmation cases exist with 500 paths, improve pooled
AQL by at least 20 percent over R108 self recursion, stay at most 10 percent
above the R97 direct reference, and harm none of the three regions relative to
self recursion. The 10 percent limit is unchanged from R110B.

## Reproducibility and execution

Each case verifies the R110 terminal identity, validation-only split, region,
fold, origin ordering, 96-step horizon geometry, response values, R103 anchors,
and hashes of every source artifact. Case outputs are atomic and resumable.
The closeout validates the complete 18-case surface and writes a top-level
source manifest with hashes. At most 18 single-thread workers are useful even
when `--workers 30` is supplied, because there are only 18 new cases. An
optional explicit CPU list pins each worker to one distinct logical CPU and is
recorded in the closeout summary.

Focused tests cover fold separation, gate behavior, no-refit/test-closed
contracts, parallel execution, source-manifest production, and rejection of a
completed case carrying the wrong mode, region, or fold. Real-data preflight
also validates both new path constructors on BG fold 1 at shape
`500 x 122 x 96` with finite values.

This remains a validation-only, no-refit diagnosis. It does not authorize test,
registry, article, joint-model, MCMC, or all-region work unless the frozen
confirmation gate passes. A failed gate stops at bounded focus-region driver
and readout diagnosis; it does not justify a broader DESN rescreen.

## Materialized result

The full 18-case run completed with one pinned logical CPU per worker. All 867
records in the aggregated source manifest passed an independent hash audit.
No test, registry, article, joint-model, MCMC, or model-fitting path was opened.

| representation | fold-1 AQL | folds 2--3 AQL | all-fold AQL |
|---|---:|---:|---:|
| raw posterior paths | 12.32173 | 11.08728 | 11.49989 |
| analytic quantile curve | 12.38062 | 11.15001 | 11.56134 |
| analytic median | 13.20898 | 11.94215 | 12.36558 |

Fold 1 selected `raw_posterior_paths`. On folds 2--3 it retained a 70.73
percent gain over self recursion and harmed no focus region, but remained 16.24
percent above the R97 direct reference. It therefore failed the unchanged 10
percent proximity gate. The deterministic median was additionally
underdispersed: case-level 10--90 coverage fell as low as 0.25. Rank-coupled
quantile paths preserved dispersion but were slightly worse than the raw paths.

The confirmation gap to R97 was 4.55 percent for BE, 19.65 percent for BG, and
18.99 percent for EE. This localizes the remaining issue to target-driver and
downstream-readout interaction in BG and EE rather than to a universal path
representation problem. R111 is not authorized. The next admissible work is a
bounded, validation-only BG/EE failure atlas that separates target-driver
error by horizon from neighbor-panel and frozen-readout sensitivity before any
additional fit is proposed.
