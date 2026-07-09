# PriceFM Stage-T Structural Diagnostics

Date: 2026-06-29

## Purpose

Stage T is the post-Stage-S diagnostic gate.  It does not fit models, write
launch grids, or modify the Stage-M article decision surface.  Its role is to
audit whether the remaining PriceFM/Q-DESN gaps are caused by structural
comparability issues rather than by another missing reservoir hyperparameter
screen.

This stage was launched because Stage S completed cleanly but failed
scientifically:

- no validation-selected Stage-S candidate beat Stage-M;
- no validation-selected Stage-S candidate beat cached PriceFM;
- no test-oracle Stage-S candidate beat Stage-M or cached PriceFM;
- the best test-oracle Stage-S row was still 0.716 AQL worse than cached
  PriceFM.

That makes more Stage-S-style graph-parity or local-capacity sweeps a poor next
move without a deeper structural diagnosis.

## Implementation

Tracked implementation:

```text
application/scripts/pricefm/81_diagnose_pricefm_structural_parity.py
application/tests/test_pricefm_stage_t_structural_diagnostics.py
docs/implementation_notes/pricefm_stage_t_structural_diagnostics_20260629.md
```

Ignored reproducible outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_t_structural_diagnostics_20260629/
```

Main command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/81_diagnose_pricefm_structural_parity.py
```

Validation command:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_t_structural_diagnostics.py -q
```

## Inputs

Stage T consumes only already-produced artifacts:

- Stage-M current decision surface;
- Stage-R scorecard, information-set parity, selection-transfer, failure-mode,
  and horizon diagnostics;
- Stage-S closeout summary, validation-selected candidates, test-oracle audit,
  and variant summaries;
- local PriceFM paper text;
- local PriceFM data-pipeline report.

The script writes `stage_t_input_manifest.csv` with paths, SHA-256 hashes, row
counts, and file sizes.

## Health

| Check | Value |
|---|---:|
| Diagnostic only | TRUE |
| Fits models | FALSE |
| Writes launch configs | FALSE |
| Stage-M rows | 42 |
| Stage-M Q-DESN wins | 25 |
| Stage-M PriceFM wins | 17 |
| Stage-M mean AQL delta | -0.3276 |
| Stage-M median AQL delta | -0.1922 |
| Stage-M surface SHA-256 | `dc5d9231a38eb378db9ce62b748f4cfaa767d8e110a00ab31a92a11847a3b3e9` |
| Stage-S run clean | TRUE |
| Stage-S promotion recommended | FALSE |

The script records the repo branch, HEAD, and dirty state in `summary.json`.
The tracked files in this stage are the script, tests, and this note; generated
diagnostic tables remain ignored under `application/data_local/pricefm/`.

## Main Diagnostic Findings

Information-set parity remains the strongest broad signal:

| Information set | Rows | Q-DESN wins | Win rate | Mean Q-DESN minus PriceFM AQL |
|---|---:|---:|---:|---:|
| PriceFM graph inputs | 27 | 20 | 0.741 | -0.719 |
| Target only | 15 | 5 | 0.333 | 0.377 |

Selection-transfer diagnostics remain weak:

| Source | Rows | Region/folds | Test win rate | PriceFM win rate | Mean test delta vs PriceFM |
|---|---:|---:|---:|---:|---:|
| Stage-N validation-selected | 17 | 17 | 0.412 | 0.000 | 3.008 |
| Stage-O selection-rule rows | 68 | 17 | 0.412 | 0.000 | 3.069 |
| Stage-Q validation-selected | 2 | 2 | 0.000 | 0.000 | 2.085 |
| Stage-Q test-oracle audit | 2 | 2 | 0.000 | 0.000 | 1.666 |

Stage S then directly tested the most obvious graph-parity rescue family and
still found no promotion.  Therefore the unresolved rows should be treated as
structural diagnostics, not as a reason for another blind capacity sweep.

## Largest Unresolved Rows

| Region/fold | Stage-M AQL gap | Current information set | Stage-T signal | Next gate |
|---|---:|---|---|---|
| LT fold 1 | 1.991 | target-only | Stage-S family falsified | structural diagnostics before search |
| HU fold 2 | 1.362 | PriceFM graph inputs | large model/data mismatch | parity and target-transform audit |
| SK fold 3 | 1.303 | PriceFM graph inputs | large model/data mismatch | parity and target-transform audit |
| FI fold 1 | 1.301 | target-only | Stage-S family falsified | structural diagnostics before search |
| AT fold 3 | 0.892 | target-only | Stage-S family falsified | structural diagnostics before search |
| SE_4 fold 1 | 0.780 | target-only | Stage-S family falsified | structural diagnostics before search |
| RO fold 1 | 0.729 | PriceFM graph inputs | validation-transfer failure | multi-validation/horizon selection contract |
| PL fold 3 | 0.713 | target-only | Stage-S family falsified | structural diagnostics before search |

## Mechanism Ranking

| Rank | Mechanism | Decision | Gate |
|---:|---|---|---|
| 1 | PriceFM information-set parity audit | implement next diagnostic | no unknown feature/window/scaling fields |
| 2 | Horizon-aware or multi-validation selection contract | design after parity audit | validation-only rule improves historical transfer without test labels |
| 3 | Target scaling and transform audit | implement with parity audit | raw-unit scoring and transform parity documented for all rows |
| 4 | Calendar or market-feature adapter | conditional | exogenous at forecast origin and tracked in manifests |
| 5 | Spatial or multi-output Q-DESN | research extension | mathematical contract and small synthetic tests first |
| 6 | More Stage-S graph-parity/local capacity sweep | reject now | Stage-S already falsified this family |
| 7 | Seven-quantile confirmation of Stage-S candidates | reject now | no median candidate earned confirmation |

## Decision

Do not launch another Stage-S priority or another broad graph-parity/local
capacity sweep.  Preserve Stage-M as the authoritative article surface.

The next implementation should be a parity diagnostic stage that checks:

1. exact PriceFM feature parity: price/load/solar/wind, optional generation
   exclusion, graph neighbor scope, and realized lead-covariate semantics;
2. target transform and scaling parity: RobustScaler use, inverse-transform
   scoring, raw-unit AQL/MAE/RMSE;
3. horizon-level failure structure: whether failures are early/middle/late
   horizon localized;
4. validation/test transfer: whether a multi-validation-block or horizon-aware
   validation rule is justified without using test metrics for selection.

Only after that diagnostic should a new model-fitting grid be designed.

## Validation

Focused tests passed:

```text
application/tests/test_pricefm_stage_t_structural_diagnostics.py: 4 passed
```

The tests cover:

- diagnostic-only output generation;
- no launch-grid or model-fit behavior;
- Stage-S validation-only/list-valued row-key handling;
- rejection of test-metric selection roles;
- rejection of duplicate Stage-M region/fold keys;
- rejection of Stage-S promotion summaries.
