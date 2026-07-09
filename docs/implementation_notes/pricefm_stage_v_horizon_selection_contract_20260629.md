# PriceFM Stage-V Horizon Selection Contract

## Purpose

Stage V is a diagnostic-only selection-contract pass after the Stage-U parity
audit.  It asks whether any validation-only rule over existing Q-DESN candidate
artifacts gives enough evidence to justify another launch.  This is deliberately
not a new model fit and not a promotion stage.

The stage is meant to prevent the failure pattern observed in Stage-Q and
Stage-S: validation AQL improvements that do not transfer reliably to the test
window.  It therefore compares several validation-only total and horizon-aware
selection rules, then attaches test metrics only after each rule has selected a
candidate.

Stage V does not fit models, does not write launch grids, and does not mutate
the frozen Stage-M decision surface.

## Command

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/83_design_pricefm_horizon_selection_contract.py \
  --force true
```

## Inputs

The diagnostic reads the frozen Stage-M surface, the current median
validation/test table, the Stage-U parity gate, the Stage-O selection-rule
precedent, and completed candidate run artifacts:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/current_decision_surface_table.csv
application/data_local/pricefm/authoritative/pricefm_stage_m_validation_test_alignment_20260624/current_median_validation_test.csv
application/data_local/pricefm/authoritative/pricefm_stage_u_parity_audit_20260629/summary.json
application/data_local/pricefm/authoritative/pricefm_stage_u_parity_audit_20260629/stage_u_row_parity_matrix.csv
application/data_local/pricefm/authoritative/pricefm_stage_u_parity_audit_20260629/stage_u_horizon_gap_by_row.csv
application/data_local/pricefm/authoritative/pricefm_stage_o_selection_promotion_hardening_20260626/stage_o_selection_rule_audit.csv
application/data_local/pricefm/runs/pricefm_stage_n_underperformance_broad_20260625/
application/data_local/pricefm/runs/pricefm_stage_q_nearmiss_refinement_20260626/
application/data_local/pricefm/runs/pricefm_stage_s_targeted_rescue_20260628/
```

It also scans the current Stage-M selected run cells, so the current median
surface appears in the same candidate universe as the rescue candidates.

## Outputs

Ignored local outputs are written under:

```text
application/data_local/pricefm/authoritative/pricefm_stage_v_horizon_selection_contract_20260629/
```

Main files:

```text
summary.json
stage_v_input_manifest.csv
stage_v_candidate_universe.csv
stage_v_candidate_health.csv
stage_v_rule_definitions.csv
stage_v_rule_selected_rows.csv
stage_v_rule_audit.csv
stage_v_region_fold_rule_matrix.csv
stage_v_horizon_rule_diagnostics.csv
stage_v_mechanism_decisions.csv
stage_v_horizon_selection_contract_report.md
```

## Contract Checks

Stage V enforces these checks before evaluating rules:

- Stage-U must be diagnostic-only.
- Stage-U must have `hard_parity_failures = 0`.
- Stage-U must recommend `horizon_aware_validation_contract_after_parity`.
- Stage-M must have unique region/fold keys and 42 rows.
- Selection rules must set `selection_uses_test_metrics = false`.
- Test metrics are audit-only and are attached after selection.

## Candidate Universe

The scanner found a complete candidate universe for all 42 region/folds.

| Source | Candidate rows | Region/folds | Horizon-rule eligible rows |
|---|---:|---:|---:|
| Stage-M current cells | 84 | 42 | 84 |
| Stage-N candidate root | 986 | 17 | 986 |
| Stage-Q candidate root | 168 | 2 | 168 |
| Stage-S candidate root | 276 | 13 | 276 |
| All | 1514 | 42 | 1514 |

All scanned Q-DESN candidate rows had validation metrics, test metrics, and the
four validation horizon groups needed for horizon-aware scoring.

## Rules Evaluated

The evaluated rules were:

| Rule | Uses test metrics for selection? | Role |
|---|---|---|
| `val_aql_min` | false | total validation AQL minimum |
| `robust_rank_val_aql_mae_rmse` | false | rank blend of validation AQL, MAE, RMSE |
| `horizon_max_aql_min` | false | minimize worst validation horizon-block AQL |
| `horizon_midlate_mean_min` | false | minimize average validation AQL over horizons 49-96 |
| `horizon_balanced_rank` | false | rank blend of total AQL, worst block, horizon range, and late-block mean |
| `horizon_guarded_val_aql` | false | total validation AQL after validation horizon max/range guardrails |
| `current_safe_horizon_guarded` | false | guarded validation AQL with a current-validation improvement condition |

## Results

The best audit rule by mean test delta versus the current median baseline was
`horizon_max_aql_min`.

| Rule | Mean test delta vs current median | Test improved rows | Mean test delta vs PriceFM | Beats PriceFM rows | Mean regret vs candidate test oracle |
|---|---:|---:|---:|---:|---:|
| `horizon_max_aql_min` | -0.0795 | 12 / 42 | 1.5926 | 6 / 42 | 0.2196 |
| `horizon_guarded_val_aql` | -0.0678 | 14 / 42 | 1.6043 | 6 / 42 | 0.2313 |
| `horizon_balanced_rank` | -0.0672 | 12 / 42 | 1.6049 | 6 / 42 | 0.2319 |
| `current_safe_horizon_guarded` | -0.0664 | 12 / 42 | 1.6057 | 6 / 42 | 0.2326 |
| `robust_rank_val_aql_mae_rmse` | -0.0650 | 10 / 42 | 1.6071 | 6 / 42 | 0.2340 |
| `horizon_midlate_mean_min` | -0.0612 | 11 / 42 | 1.6109 | 6 / 42 | 0.2379 |
| `val_aql_min` | -0.0520 | 10 / 42 | 1.6201 | 6 / 42 | 0.2471 |

The small average improvement versus the current median baseline is not enough
to justify another launch.  The row-level win rate is low, no rule improves the
Stage-M surface metric, and all rules remain far behind PriceFM on average.

## Decision

Stage V does not recommend a new launch from this evidence.

| Mechanism | Decision | Next action |
|---|---|---|
| Horizon-aware validation selection | do not launch from Stage V | Do not run another capacity sweep until selection instability or graph-parity mechanisms change. |
| Candidate artifact health | pass | Keep metric summaries and horizon summaries as the minimal retained artifact for future screens. |
| Test-metric leakage guard | pass | Preserve this validation-only rule contract before any future confirmation launch. |

The recommended next stage is:

```text
do_not_launch_more_capacity_until_selection_or_graph_model_changes
```

## Interpretation

Stage V confirms that a simple horizon-aware validation rule is not enough to
repair the current selection problem.  Worst-horizon scoring slightly reduces
average median test AQL relative to the current median baseline, but it does not
transfer broadly enough across region/folds and does not materially close the
gap to PriceFM.

The correct next move is not another broad reservoir capacity sweep.  The next
useful work should change the mechanism being diagnosed, for example:

- a graph-information adapter closer to the PriceFM information set;
- a multi-validation or stability-based selection contract;
- a fold/region-local model-selection policy that is frozen before any test
  audit; or
- a narrower paper-facing comparison that clearly labels the current Q-DESN
  information set and the remaining PriceFM graph-architecture gap.

## Validation

Stage-V tests cover:

- output generation and diagnostic-only flags;
- validation-only rule declarations;
- horizon-aware selection refusing candidates without full validation horizon
  groups;
- Stage-U hard-parity gate enforcement;
- duplicate Stage-M region/fold rejection.

Run:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_v_horizon_selection_contract.py -q
```
