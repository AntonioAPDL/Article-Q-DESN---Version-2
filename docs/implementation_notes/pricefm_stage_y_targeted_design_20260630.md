# PriceFM Stage-Y Targeted Design

Date: 2026-06-30

## Purpose

Stage Y is a non-launch planning gate after Stage X.  It translates the Stage-X
failure labels into concrete design lanes, estimates the cost of possible future
work, and records which rows are blocked, deferred, or eligible for a later
manual design review.

It does not fit models, write launch grids, mutate the Stage-M surface, or
start background jobs.

## Reproducible Command

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/87_prepare_pricefm_stage_y_targeted_design.py \
  --force true
```

Generated outputs are local and ignored:

```text
application/data_local/pricefm/authoritative/pricefm_stage_y_targeted_design_20260630/
```

The main generated report is:

```text
application/data_local/pricefm/authoritative/pricefm_stage_y_targeted_design_20260630/stage_y_report.md
```

## Inputs

Stage Y consumes only Stage-X artifacts:

| Input | Role |
|---|---|
| `summary.json` | Confirms Stage X is diagnostic-only and forbids immediate fits |
| `stage_x_region_fold_failure_modes.csv` | Source of row-level failure labels |
| `stage_x_selection_rule_audit.csv` | Validation-only rule evidence |
| `stage_x_recommended_actions.csv` | Stage-X no-launch gates |
| `stage_x_horizon_failure_audit.csv` | Horizon weakness ranking |
| `stage_x_candidate_evidence.csv` | Candidate evidence count and provenance |

Hashes and sizes are written to `stage_y_input_manifest.csv`.

## Health

| Check | Result |
|---|---:|
| Diagnostic only | true |
| Fits models | false |
| Writes launch configs | false |
| Stage-M surface changed | false |
| Design rows | 42 |
| Launch-ready rows | 0 |
| Candidate evidence rows read | 1,706 |
| Hypothetical future experiment budget | 80 |
| Budget cap | 120 |

## Design Lanes

| Lane | Rows | Future budget | Decision |
|---|---:|---:|---|
| `exclude_falsified_stage_w_family` | 5 | 0 | Block same-family relaunch |
| `defer_model_class_change` | 1 | 0 | Defer until a model/information change exists |
| `graph_adapter_contract_design` | 6 | 72 | Design a genuinely new graph adapter first |
| `horizon_targeted_design` | 1 | 8 | Possible narrow future design after review |
| `monitor_no_large_launch` | 4 | 0 | Monitor only |
| `no_action_current_qdesn_wins` | 25 | 0 | Keep current row |

No row is launch-ready.  The future budget is an estimate only, not an
authorization to launch.

## Main Row-Level Implications

### Blocked Stage-W Family

The following rows should not relaunch the Stage-W graph/input/geometry family:

| Region | Fold | Reason |
|---|---:|---|
| LT | 1 | Stage-W family falsified |
| SK | 3 | Stage-W family falsified |
| FI | 1 | Stage-W family falsified |
| AT | 3 | Stage-W family falsified |
| SE_4 | 1 | Stage-W family falsified |

Stage-W Priority 0 had zero validation-selected PriceFM wins and zero
test-oracle PriceFM wins, so repeating that family would be inefficient and
scientifically weak.

### Graph Adapter Contract Required

The following target-only underperformance rows are plausible candidates for a
future graph-information design, but not with the current `graph_khop`/summary
adapter alone:

| Region | Fold | Delta vs PriceFM | Worst horizon |
|---|---:|---:|---|
| PL | 3 | 0.7130 | 49-72 |
| LV | 1 | 0.5189 | 49-72 |
| SI | 1 | 0.3185 | 49-72 |
| PL | 1 | 0.3146 | 49-72 |
| LV | 2 | 0.2240 | 49-72 |
| SE_4 | 3 | 0.0950 | 49-72 |

A future graph launch must first define a new adapter contract that is clearly
different from the current partial graph parity approach.

### Horizon-Targeted Candidate

The only immediate horizon-design row is:

| Region | Fold | Delta vs PriceFM | Worst horizon | Lane |
|---|---:|---:|---|---|
| RO | 3 | 0.4331 | 49-72 | `horizon_targeted_design` |

This row is not launch-ready.  It is the cleanest candidate for a later narrow
horizon-targeted design because it is not blocked by Stage-W family falsification.

## Decisions

| Decision | Result |
|---|---|
| Immediate launch | no |
| Relaunch Stage-W Priority 1 | no |
| Relaunch same Stage-W family | no |
| Build runnable grid now | no |
| Manual Stage-Y review needed | yes |

## Recommended Next Step

Do a manual Stage-Y review.  If continuing, choose exactly one narrow direction:

1. **Horizon-targeted Stage Z** for RO fold 3 only, centered on the 49-72
   horizon failure and validation-only horizon-max selection.
2. **Graph adapter contract Stage Z** for the six graph-information-gap rows,
   but only after defining a new adapter that is materially different from
   current `graph_khop` and graph-summary inputs.

Do not launch both directions at once.  Do not relaunch Stage-W Priority 1.

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_y_targeted_design.py -q
```

Result: 2 passed.
