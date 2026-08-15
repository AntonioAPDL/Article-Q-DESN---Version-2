# PriceFM Stage-S Targeted Rescue Closeout

Date: 2026-06-29

## Purpose

Stage S was the targeted follow-up after Stage R diagnosed two unresolved
failure modes in the PriceFM application panel:

- target-only Q-DESN rows that were competing against PriceFM graph-input
  models without comparable neighbor information;
- a small set of graph-input rows with horizon-block weakness.

The goal was deliberately narrow.  Stage S was allowed to test a bounded
graph-parity rescue and a small horizon-block pilot, but it was not allowed to
mutate the current Stage-M decision surface or use test metrics for selection.

## Commands

The closeout was generated from the ignored Stage-S run outputs with:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/80_closeout_pricefm_stage_s_targeted_rescue.py
```

Closeout outputs are ignored and reproducible from the run directory:

```text
application/data_local/pricefm/authoritative/pricefm_stage_s_targeted_rescue_closeout_20260629/
```

The tracked closeout script is:

```text
application/scripts/pricefm/80_closeout_pricefm_stage_s_targeted_rescue.py
```

## Repo State

The closeout summary was generated on:

| Field | Value |
|---|---|
| Branch | `application-ensemble-likelihood-redesign` |
| Recorded HEAD | `991f8d0` |
| Recorded dirty state | `true` |

The dirty state reflects local working-tree files at closeout time.  The
Stage-S closeout script is intentionally conservative and records that state;
the Stage-M surface itself was separately hash-checked and was unchanged.

## Run Health

| Check | Value | Status |
|---|---:|---|
| Window builds completed | 33 | pass |
| Experiments completed | 138 | pass |
| Non-completed statuses | 0 | pass |
| Metric summary files | 138 | pass |
| Binary fit artifacts retained | 0 | pass |
| Stage-M rows | 42 | pass |
| Wall time | `4:03:37` | info |
| Max RSS | 1,982,712 KB | info |

No `.rds`, `.rda`, `.RData`, or `.rdata` files remained in the Stage-S run tree
after the metric and figure products were written.

## Stage-M Preservation

| Field | Value |
|---|---|
| Stage-M surface changed | `false` |
| Stage-M rows | 42 |
| Stage-M surface SHA-256 | `dc5d9231a38eb378db9ce62b748f4cfaa767d8e110a00ab31a92a11847a3b3e9` |

Stage S did not promote any row and did not rewrite the article decision
surface.

## Selection Results

Validation metrics selected one Stage-S candidate per target row.  Test metrics
were audit-only.

| Candidate family | Rows | Beat Stage-M | Beat PriceFM | Median test minus Stage-M | Median test minus PriceFM | Best test minus PriceFM |
|---|---:|---:|---:|---:|---:|---:|
| Graph-parity rescue | 10 | 0 | 0 | 1.696 | 2.749 | 1.406 |
| Horizon-block pilot | 3 | 0 | 0 | 2.334 | 2.642 | 1.703 |

Overall validation-selected candidates:

| Check | Value |
|---|---:|
| Beat Stage-M | 0 |
| Beat cached PriceFM | 0 |
| Median test AQL minus cached PriceFM | 2.662 |

## Test-Oracle Audit

The test-oracle audit asks whether Stage S contained any candidate that would
have been worth confirming if test labels had been allowed for selection.  This
is diagnostic only and cannot be used for article-surface selection.

| Check | Value |
|---|---:|
| Target rows | 13 |
| Test-oracle candidates beating Stage-M | 0 |
| Test-oracle candidates beating cached PriceFM | 0 |
| Best test-oracle AQL minus cached PriceFM | 0.716 |

Best test-oracle rows still failed to beat PriceFM:

| Region/fold | Best Stage-S test AQL | Stage-M AQL | PriceFM AQL | Best Stage-S minus PriceFM | Candidate family |
|---|---:|---:|---:|---:|---|
| SI fold 1 | 7.777 | 7.379 | 7.061 | 0.716 | graph-parity rescue |
| SE_4 fold 3 | 9.327 | 8.134 | 8.039 | 1.289 | graph-parity rescue |
| SE_4 fold 1 | 9.153 | 8.482 | 7.702 | 1.450 | graph-parity rescue |
| BE fold 3 | 6.887 | 5.567 | 5.293 | 1.593 | horizon-block pilot |

This rules out the simple explanation that Stage S merely chose the wrong
candidate by validation AQL.  Even its best audit-only test candidates were
worse than the existing article surface and cached PriceFM comparison.

## Decision

Stage S is closed as negative evidence.

- Do not promote any Stage-S row.
- Do not launch Stage-S priority 1.
- Do not continue graph-parity rescue or small horizon-pilot variants from this
  same family.
- Preserve the current Stage-M article decision surface.
- Move the next discussion to structural diagnostics before any new search.

## Interpretation

The targeted graph-parity rescue did not close the gap to PriceFM.  The
horizon-block pilot also failed to improve the current surface.  The consistent
failure of both validation-selected and test-oracle rows suggests that the
remaining gaps are not just local tuning failures.

The next likely issues are structural:

- the Q-DESN input construction may still not match the information set used by
  PriceFM closely enough;
- the validation block may not represent the test block for these rows;
- some regions may need exogenous calendar or market features not currently in
  the Q-DESN screen;
- horizon-specific behavior may require a different selection objective, not
  another capacity sweep.

## Discussion Gate For Stage 5

Before implementing any new mechanism, the next stage should diagnose the
source of the remaining mismatch.  Candidate mechanisms to discuss are:

1. PriceFM-parity input adapter: audit exact covariates, graph neighbors,
   transforms, and window alignment before adding new reservoir capacity.
2. Calendar and market features: add only if the source audit shows they are in
   PriceFM or are defensible exogenous predictors available at forecast time.
3. Horizon-aware selection: use multiple validation blocks or horizon-weighted
   validation only after documenting why the current validation/test transfer
   fails.
4. Multi-output or spatial Q-DESN: consider later if input-parity adapters are
   insufficient and the paper needs an explicitly spatial competitor.
5. Target transforms and scaling: audit whether PriceFM uses transforms that
   materially change the learning problem.

The immediate recommendation is not another overnight reservoir sweep.  The
best next work is a structural diagnostic stage that explains what information
or selection mechanism is missing.
