# PriceFM Stage-X Selection Failure Contract

Date: 2026-06-30

## Purpose

Stage X is a diagnostic-only consolidation stage after the Stage-W Priority-0
screen.  It asks whether the current evidence supports another model-fitting
launch.  It does not fit models, write launch grids, or mutate the Stage-M
decision surface.

The main conclusion is conservative: do not launch more fits yet.  Stage-W
Priority 0 was clean, but the search family did not rescue the difficult
region/fold rows, and the validation-selected candidates did not beat PriceFM.

## Reproducible Command

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/86_design_pricefm_stage_x_selection_failure_contract.py \
  --force true
```

Generated outputs are local and ignored:

```text
application/data_local/pricefm/authoritative/pricefm_stage_x_selection_failure_contract_20260630/
```

The main generated report is:

```text
application/data_local/pricefm/authoritative/pricefm_stage_x_selection_failure_contract_20260630/stage_x_report.md
```

## Inputs

Stage X freezes the following evidence:

| Input | Role |
|---|---|
| Stage-M decision surface | Current 42 row/fold Q-DESN vs PriceFM surface |
| Stage-U parity audit | Data, scaling, horizon, and graph-parity diagnostics |
| Stage-V candidate universe | Existing validation/test candidate evidence and horizon summaries |
| Stage-V rule audit | Prior validation-only horizon-rule benchmark |
| Stage-W Priority-0 closeout | Most recent severe-row graph/input/geometry screen |

All input paths and hashes are written to:

```text
stage_x_input_manifest.csv
```

## Health

| Check | Result |
|---|---:|
| Diagnostic only | true |
| Fits models | false |
| Writes launch configs | false |
| Stage-M surface changed | false |
| Selection uses test metrics | false |
| Stage-M rows | 42 |
| Candidate evidence rows | 1,706 |
| Validation-only rules | 6 |
| Failure-mode rows | 42 |
| Stage-W run clean | true |
| Stage-W Priority 1 recommended | false |

## Validation-Only Rule Audit

Stage X evaluates validation-only rules and attaches test metrics only after
selection for audit.  These rules are not allowed to use test AQL when selecting
candidates.

| Rule | Test delta vs current | Test delta vs PriceFM | Current wins | PriceFM wins |
|---|---:|---:|---:|---:|
| `val_max_horizon_min` | -0.0795 | 1.5926 | 12 | 6 |
| `val_family_guarded_stability_min` | -0.0628 | 1.6093 | 11 | 6 |
| `val_stability_penalty_min` | -0.0624 | 1.6097 | 11 | 6 |
| `val_midlate_min` | -0.0612 | 1.6109 | 11 | 6 |
| `val_mean_min` | -0.0520 | 1.6201 | 10 | 6 |
| `val_cvar2_horizon_min` | -0.0521 | 1.6200 | 9 | 6 |

The best historical rule remains `val_max_horizon_min`, which is consistent
with Stage V.  However, even the best rule trails PriceFM on average and wins
only 6 of 42 region/fold rows against PriceFM.  This is useful for future
selection, but not enough to justify another broad launch by itself.

## Stage-W Implication

Stage-W Priority 0 remains negative evidence:

| Quantity | Result |
|---|---:|
| Validation-selected PriceFM wins | 0 |
| Validation-selected current-Q-DESN-only wins | 1 |
| Test-oracle PriceFM wins | 0 |
| Test-oracle current-Q-DESN wins | 1 |
| Priority 1 recommended | false |

Therefore Stage-W Priority 1 should not be launched.

## Failure Modes

Stage X assigns every Stage-M region/fold one primary failure mode.  The most
important labels for future work are:

| Failure mode | Role |
|---|---|
| `candidate_family_falsified` | Stage-W tested this search family and it did not rescue the row |
| `graph_information_gap` | Current row is target-only and still trails PriceFM |
| `late_horizon_failure` | Horizon gap is the dominant unresolved pattern |
| `pricefm_far_ahead` | Q-DESN trails PriceFM enough that another small local sweep is unlikely to help |
| `minor_underperformance` | Monitor; no large launch |
| `current_qdesn_wins` | No action |

The generated row-level table is:

```text
stage_x_region_fold_failure_modes.csv
```

Key Stage-W severe-row labels:

| Region | Fold | Failure mode | Recommended action |
|---|---:|---|---|
| LT | 1 | `candidate_family_falsified` | do not relaunch same family |
| FI | 1 | `candidate_family_falsified` | do not relaunch same family |
| AT | 3 | `candidate_family_falsified` | do not relaunch same family |
| SE_4 | 1 | `candidate_family_falsified` | do not relaunch same family |
| SK | 3 | `candidate_family_falsified` | do not relaunch same family |
| HU | 2 | `pricefm_far_ahead` | defer until model-class change |

## Decision

Do not launch new model fits from Stage X.

The next implementation should be a small planning stage for Stage Y that uses
the Stage-X failure labels to decide whether a narrow launch exists at all.  Any
Stage-Y launch must be mechanism-specific, not a repeat of graph/capacity
screening:

1. For `candidate_family_falsified`, do not relaunch the same Stage-W family.
2. For `graph_information_gap`, consider a genuinely new graph adapter only
   after defining how it differs from the current `graph_khop`/summary inputs.
3. For `late_horizon_failure`, consider horizon-targeted candidates or a
   horizon-stability selection rule.
4. For `pricefm_far_ahead`, defer until a model-class change is justified.

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_x_selection_failure_contract.py -q
```

Result: 2 passed.
