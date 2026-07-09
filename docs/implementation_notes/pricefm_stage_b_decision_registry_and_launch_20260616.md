# PriceFM Stage-B Decision Registry And Launch Prep

Date: 2026-06-16

## Purpose

Freeze the completed Stage-B median-only tau `0.50` comparison into one
authoritative handoff before launching the next grids:

- paper-quantile promotion for region/folds whose selected Q-DESN median
  specification beats PriceFM Phase-I on every fold;
- targeted graph/local median rescue for region/folds that still lag PriceFM.

Generated model outputs and launch artifacts remain under ignored
`application/data_local/`.

## New Tracked Helper

`application/scripts/pricefm/48_freeze_pricefm_stage_b_decision_registry.py`

The helper joins:

- `pricefm_stage_b_median_batch1_registry_20260616/median_selection_registry.csv`
- `pricefm_stage_b_median_batch1_closeout_20260616/stage_b_selection_registry_with_triage.csv`
- `pricefm_stage_b_median_batch1_closeout_20260616/stage_b_region_summary.csv`
- `pricefm_phase1_vs_stage_b_median_tau0p50_20260616/panel_metric.csv`
- `pricefm_phase1_vs_stage_b_median_tau0p50_20260616/region_panel_comparison_status.csv`

It validates that all comparison statuses completed successfully before writing
promotion and rescue queues.

## Frozen Decision Outputs

Ignored output root:

```text
application/data_local/pricefm/authoritative/pricefm_stage_b_decision_registry_20260616/
```

Key outputs:

```text
stage_b_decision_registry.csv
stage_b_region_decisions.csv
stage_b_promotion_ready_registry.csv
stage_b_conflict_confirm_registry.csv
stage_b_rescue_needed_registry.csv
stage_b_rescue_scope.csv
stage_b_decision_report.md
summary.json
```

Decision counts:

| Decision | Regions | Rows |
|---|---:|---:|
| `paper_quantile_ready` | 3 | 9 |
| `paper_quantile_ready_with_naive_conflict` | 1 | 3 |
| `median_rescue_needed` | 4 | 12 |

Promotion regions: `ES`, `FR`, `PT`, and `IT_NORD`.

Rescue regions: `AT`, `BG`, `FI`, and `PL`.

`IT_NORD` is included in the paper-quantile promotion queue with an explicit
naive-conflict label because it beats PriceFM Phase-I on every fold but loses to
simple local naive baselines in the Stage-B closeout.

## Prepared Grids

Paper-quantile promotion grid:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_promotion_ready_paper_quantiles_20260616.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_b_promotion_ready_paper_quantiles_20260616/
application/data_local/pricefm/runs/pricefm_stage_b_promotion_ready_paper_quantiles_20260616/
```

Scope: 12 promoted region/folds times seven PriceFM paper quantiles
`0.10,0.25,0.45,0.50,0.55,0.75,0.90` = 84 experiments.

Median rescue grid:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_rescue_median_20260616.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_b_rescue_median_20260616/
application/data_local/pricefm/runs/pricefm_stage_b_rescue_median_20260616/
```

Scope: 12 rescue region/folds times four targeted graph/local variants = 48
experiments. Priorities are `0` for folds that lag PriceFM and `1` for already
winning folds in otherwise rescue-needed regions.

## Validation

Focused tests:

```text
application/tests/test_pricefm_stage_b_decision_registry.py
application/tests/test_pricefm_stage_b_closeout.py
application/tests/test_pricefm_region_panel_grid.py
application/tests/test_pricefm_graph_local_rescue_workflow.py
```

Result: `17 passed`.

Dry-run launch checks passed for:

- 84 promotion experiments, priority `0`;
- 48 rescue experiments, priorities `0,1`.

## Launch Commands

Promotion:

```sh
tmux new-session -d -s pricefm_stageb_promote7q_0616 \
  'cd /data/jaguir26/local/src/Article-Q-DESN && \
   /usr/bin/time -v -o application/data_local/pricefm/experiment_grids/pricefm_stage_b_promotion_ready_paper_quantiles_20260616/tmux.time.log \
   application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py \
     --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_promotion_ready_paper_quantiles_20260616.yaml \
     --priorities 0 \
     --experiment-jobs 8 \
     --cell-jobs 1 \
     --build-windows true \
     --resume true \
     --force false \
     --dry-run false \
     > application/data_local/pricefm/experiment_grids/pricefm_stage_b_promotion_ready_paper_quantiles_20260616/tmux.log 2>&1; \
   echo $? > application/data_local/pricefm/experiment_grids/pricefm_stage_b_promotion_ready_paper_quantiles_20260616/tmux.exit'
```

Rescue:

```sh
tmux new-session -d -s pricefm_stageb_rescue_median_0616 \
  'cd /data/jaguir26/local/src/Article-Q-DESN && \
   /usr/bin/time -v -o application/data_local/pricefm/experiment_grids/pricefm_stage_b_rescue_median_20260616/tmux.time.log \
   application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py \
     --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_rescue_median_20260616.yaml \
     --priorities 0,1 \
     --experiment-jobs 8 \
     --cell-jobs 1 \
     --build-windows true \
     --resume true \
     --force false \
     --dry-run false \
     > application/data_local/pricefm/experiment_grids/pricefm_stage_b_rescue_median_20260616/tmux.log 2>&1; \
   echo $? > application/data_local/pricefm/experiment_grids/pricefm_stage_b_rescue_median_20260616/tmux.exit'
```

## Next Closeout

After the launched jobs complete:

1. summarize the paper-quantile promotion queue;
2. close out the median rescue grid;
3. run seed robustness only for rescue candidates that beat the current median
   registry on validation without unacceptable test degradation;
4. compare completed promoted paper quantiles against the fold-aligned PriceFM
   Phase-I benchmark.

Promotion summary:

```sh
python application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_b_decision_registry_20260616/stage_b_promotion_ready_registry.csv \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_promotion_ready_paper_quantiles_20260616.yaml \
  --output-root application/data_local/pricefm/authoritative/pricefm_stage_b_promotion_ready_paper_quantiles_summary_20260616 \
  --require-complete true \
  --dry-run false \
  --panel-label "Stage-B promoted local DESN/Q-DESN" \
  --panel-description "Stage-B promoted local DESN/Q-DESN seven-quantile cells"
```

Promotion PriceFM comparison:

```sh
python application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_b_decision_registry_20260616/stage_b_promotion_ready_registry.csv \
  --config application/config/pricefm_data_pipeline.yaml \
  --pricefm-root application/data_local/pricefm/authoritative/pricefm_phase1_stage_b_promotion_ready_paper_quantiles_20260616 \
  --desn-root application/data_local/pricefm/authoritative/pricefm_stage_b_promotion_ready_paper_quantiles_summary_20260616 \
  --output-root application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_b_promotion_ready_paper_quantiles_20260616 \
  --split test \
  --methods pricefm_phase1_pretraining,qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked,normal_rhs_ns,normal_scaled_ridge \
  --quantiles 0.10,0.25,0.45,0.50,0.55,0.75,0.90 \
  --run-pricefm true \
  --dry-run false \
  --desn-panel-label "Stage-B promoted local DESN/Q-DESN" \
  --desn-panel-description "Stage-B promoted local DESN/Q-DESN seven-quantile cells" \
  --comparison-note "Stage-B promoted local-only comparison; IT_NORD has an explicit naive-conflict label."
```

Median rescue closeout:

```sh
python application/scripts/pricefm/42_closeout_pricefm_graph_local_rescue.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_stage_b_rescue_median_20260616/manifest.csv \
  --run-root application/data_local/pricefm/runs/pricefm_stage_b_rescue_median_20260616 \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_b_decision_registry_20260616/stage_b_decision_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_b_rescue_median_closeout_20260616 \
  --split-select val \
  --split-audit test \
  --unit original \
  --metric AQL \
  --model-methods qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked,normal_rhs_ns,normal_scaled_ridge
```
