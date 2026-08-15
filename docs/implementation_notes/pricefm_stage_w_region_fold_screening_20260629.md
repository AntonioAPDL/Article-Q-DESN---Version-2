# PriceFM Stage-W Region/Fold Screening Plan

## Purpose

Stage W prepares the next Q-DESN screening wave after the Stage-V diagnostic
showed that a simple global horizon-aware validation rule is not enough.  The
main correction is conceptual: model selection must be local to each
`region, fold` pair.  There should be no single global DESN specification
promoted across Europe.

Stage W is a planner and grid-preparation stage.  It does not launch model
fits and it does not mutate the frozen Stage-M decision surface.  Its outputs
make the next large screening reproducible, targeted, and compatible with the
current PriceFM grid tooling.

## Command

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/84_prepare_pricefm_stage_w_region_fold_screening.py \
  --write-grid true \
  --force true
```

## Inputs

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/current_decision_surface_table.csv
application/data_local/pricefm/authoritative/pricefm_stage_v_horizon_selection_contract_20260629/summary.json
application/data_local/pricefm/authoritative/pricefm_stage_v_horizon_selection_contract_20260629/stage_v_region_fold_rule_matrix.csv
application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml
```

The Stage-V summary is a hard gate.  Stage W refuses to run if Stage V is not
diagnostic-only, if Stage V used test metrics for selection, or if Stage V
recommends another blind capacity launch.

## Outputs

Ignored local planning outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_w_region_fold_screening_plan_20260629/
```

Launch-ready ignored grid config:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_w_region_fold_screening_20260629.yaml
```

Main planning files:

```text
summary.json
stage_w_input_manifest.csv
stage_w_region_fold_audit.csv
stage_w_target_rows.csv
stage_w_deferred_rows.csv
stage_w_experiment_manifest.csv
stage_w_expected_cost.csv
stage_w_selection_contract.csv
stage_w_region_fold_screening_plan.md
stage_w_region_fold_screening_grid.yaml
```

## Targeting Logic

Stage W targets rows by the current Stage-M AQL difference:

| Tier | Rule | Priority | Role |
|---|---|---:|---|
| `severe_loss` | `delta_abs >= 0.75` | 0 | highest-priority rescue |
| `moderate_loss` | `0.25 <= delta_abs < 0.75` | 1 | main rescue |
| `slight_loss` | `0 < delta_abs < 0.25` | 2 | smaller rescue |
| `near_win` | `-0.35 < delta_abs <= 0` | 3 | robustness/stability guard |
| `solid_win` | `delta_abs <= -0.35` | deferred | no current screening compute |

The screen is intentionally region/fold-specific.  Each row receives its own
candidate family:

- target-only losses get `graph_information_conversion`;
- graph-input losses get `graph_geometry_refinement`;
- near wins get `local_stability_guard`;
- solid wins are deferred.

This implements the core lesson from Stage-M/V: graph-input Q-DESN rows are
far stronger than target-only rows, but the graph-input policy is still not a
full PriceFM joint graph model.

## Current Stage-W Plan

Stage W produced 25 targeted rows and 252 experiments.

| Tier | Target rows |
|---|---:|
| `severe_loss` | 6 |
| `moderate_loss` | 9 |
| `slight_loss` | 2 |
| `near_win` | 8 |

| Screening family | Experiments |
|---|---:|
| `graph_information_conversion` | 128 |
| `graph_geometry_refinement` | 92 |
| `local_stability_guard` | 32 |

Priority-0 targets are the highest-loss rows:

| Region | Fold | Tier | Family | Delta AQL | Current information set |
|---|---:|---|---|---:|---|
| LT | 1 | severe loss | graph-information conversion | 1.9907 | target-only |
| HU | 2 | severe loss | graph-geometry refinement | 1.3619 | graph inputs |
| SK | 3 | severe loss | graph-geometry refinement | 1.3029 | graph inputs |
| FI | 1 | severe loss | graph-information conversion | 1.3014 | target-only |
| AT | 3 | severe loss | graph-information conversion | 0.8915 | target-only |
| SE_4 | 1 | severe loss | graph-information conversion | 0.7799 | target-only |

## Launch Contract

The generated grid includes launch blocks but does not launch them:

| Block | Priorities | Experiment jobs | Cell jobs | Role |
|---|---|---:|---:|---|
| `stage_w_dry_run_gate` | 0,1,2,3 | 1 | 1 | config/materialization check |
| `stage_w_priority0_severe_losses` | 0 | 20 | 1 | first real launch after review |
| `stage_w_priority1_moderate_losses` | 1 | 20 | 1 | launch after priority 0 closeout |
| `stage_w_priority2_slight_losses` | 2 | 12 | 1 | optional |
| `stage_w_priority3_near_win_stability` | 3 | 12 | 1 | optional stability guard |

The intended first check is:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_w_region_fold_screening_20260629.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows false \
  --resume true \
  --force false \
  --dry-run true
```

Only after that dry-run gate should priority 0 be launched.

This dry-run gate was run after generating the grid.  It completed with:

| Check | Result |
|---|---:|
| Grid ID | `pricefm_stage_w_region_fold_screening_20260629` |
| Selected priority-0 experiments | 96 |
| Build windows | false |
| Dry run | true |
| Model fits launched | 0 |

## Selection Contract

Stage-W output records the following contract:

1. Select within each `region, fold` pair.  Do not promote a global spec.
2. Rank by validation metrics only.
3. Use horizon-block validation summaries as secondary stability diagnostics.
4. Prioritize graph-information conversion for target-only losses.
5. Preserve metrics, manifests, traces, and figures; remove binary fit
   artifacts after summaries are written.

## Guardrails

- Stage-M remains unchanged.
- Stage-W writes a grid config only; it does not fit models.
- Test metrics remain audit-only.
- The generated grid keeps `shrink_intercept = false`.
- The generated grid keeps Q-DESN AL and exAL RHS/RHS_NS exact-chunked methods
  available through the existing PriceFM launcher conventions.
- Artifact hygiene is enabled and includes `.rds`, `.rda`, `.RData`, and
  `.rdata` cleanup patterns.

## Validation

Stage-W unit tests cover:

- region/fold-local target assignment;
- validation-only and audit-only metadata;
- graph-conversion, graph-refinement, and stability target families;
- optional launch-grid writing;
- Stage-V test-leakage rejection;
- duplicate Stage-M key rejection.

Run:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_w_region_fold_screening.py -q
```
