# PriceFM Stage-Z Design Contracts

Date: 2026-06-30

## Purpose

Stage Z converts the Stage-Y manual-review lanes into explicit design
contracts.  It is a non-launch gate: it does not fit models, write launch
grids, mutate the Stage-M decision surface, or start background jobs.

The goal is to keep the next PriceFM step scientifically narrow.  Stage-W
Priority 0 already falsified the broad same-family rescue for several rows, and
Stage-X showed that validation-only selection is not reliable enough to justify
another blind grid.  Stage Z therefore records what can be considered next and
what must stay blocked.

## Reproducible Command

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/88_prepare_pricefm_stage_z_design_contracts.py \
  --force true
```

Generated outputs are local and ignored:

```text
application/data_local/pricefm/authoritative/pricefm_stage_z_design_contracts_20260630/
```

The main generated report is:

```text
application/data_local/pricefm/authoritative/pricefm_stage_z_design_contracts_20260630/stage_z_report.md
```

## Inputs

Stage Z consumes only Stage-Y artifacts:

| Input | Role |
|---|---|
| `summary.json` | Confirms Stage Y was diagnostic-only and had zero launch-ready rows |
| `stage_y_design_manifest.csv` | Source of row-level lanes and future budgets |
| `stage_y_lane_contract.csv` | Source of allowed lane semantics |
| `stage_y_cost_estimate.csv` | Cost check for hypothetical future experiments |
| `stage_y_decisions.csv` | No-launch decision audit |
| `stage_y_analysis_by_point.csv` | Lane-level narrative audit |

Hashes, sizes, and row counts are written to `stage_z_input_manifest.csv`.

## Health

| Check | Result |
|---|---:|
| Diagnostic only | true |
| Fits models | false |
| Writes launch configs | false |
| Stage-M surface changed | false |
| Design rows read | 42 |
| Launch-ready rows | 0 |
| Horizon contract rows | 1 |
| Graph-adapter contract rows | 6 |
| Blocked or monitor rows | 35 |
| Hypothetical future budget | 80 |

## Contracts

### Horizon-Targeted Contract

The only current-code future track is the narrow RO fold 3 horizon design:

| Region | Fold | Delta vs PriceFM | Targeted horizon | Selection rule | Budget if approved |
|---|---:|---:|---|---|---:|
| RO | 3 | 0.4331 | 49-72 | `val_max_horizon_min` | 8 |

This is not launch-ready.  It requires explicit approval, and selection must be
validation-only.  Test metrics may be used only after the selected candidate is
frozen.

### Graph-Adapter Contract

Six rows are plausible graph-information candidates, but the current graph
screen is not enough.  A future graph launch must first implement and validate a
new adapter that is materially different from `graph_khop` or graph-summary-only
features.

| Region | Fold | Delta vs PriceFM | Worst horizon |
|---|---:|---:|---|
| PL | 3 | 0.7130 | 49-72 |
| LV | 1 | 0.5189 | 49-72 |
| SI | 1 | 0.3185 | 49-72 |
| PL | 1 | 0.3146 | 49-72 |
| LV | 2 | 0.2240 | 49-72 |
| SE_4 | 3 | 0.0950 | 49-72 |

Required before fitting these rows:

- a concrete neighbor-augmented feature contract;
- feature provenance manifests for every region/fold/horizon;
- leakage tests proving no future covariates are used;
- a smoke test on one row before any grid expansion;
- an explicit comparison against the current target-only Q-DESN and cached
  PriceFM metrics.

## Blocked And Monitor Rows

| Category | Rows | Decision |
|---|---:|---|
| Stage-W family falsified | 5 | Do not relaunch the same family |
| PriceFM far ahead | 1 | Defer until model-class or information-set change |
| Minor underperformance | 4 | Monitor; no large launch |
| Current Q-DESN wins | 25 | No action |

These rows are recorded in `stage_z_blocked_rows.csv`.

## Decision Gates

| Gate | Result |
|---|---|
| Immediate launch | no |
| Launch-ready rows | 0 |
| Relaunch Stage-W Priority 1 | no |
| Launch horizon and graph tracks together | no |
| Graph track requires new adapter code | yes |
| Future budget is authorization | no |

## Recommended Next Step

Choose exactly one future direction before any launch:

1. **Horizon-targeted pilot for RO fold 3.**  This uses existing model
   infrastructure and is the lowest-risk next fit, but it should remain narrow.
2. **Graph-adapter implementation contract.**  This is higher potential for the
   six graph-information-gap rows, but it needs new feature-engineering code and
   leakage tests before any model grid is valid.

Do not launch both tracks together.  Do not relaunch Stage-W Priority 1.

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_z_design_contracts.py -q
```

Result: 2 passed.

Regression tests run with the Stage-Y and Stage-X planners after implementation:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_z_design_contracts.py \
  application/tests/test_pricefm_stage_y_targeted_design.py \
  application/tests/test_pricefm_stage_x_selection_failure_contract.py -q
```

Expected result: all focused planner tests pass.
