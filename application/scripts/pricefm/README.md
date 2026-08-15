# PriceFM Data Pipeline

This directory contains the article-side PriceFM data-layer pipeline. It is
separate from the GloFAS application model code and does not create manuscript
figures, tables, or Q-DESN model inputs by itself.

Generated data stay under ignored local paths:

```text
application/data_local/pricefm/
application/cache/pricefm/
application/logs/pricefm/
```

Tracked files are limited to configuration, scripts, tests, and documentation.

## Python Environment

Create a local virtual environment outside git-tracked files:

```sh
python3 -m venv application/data_local/pricefm/venv
. application/data_local/pricefm/venv/bin/activate
python -m pip install --upgrade pip
python -m pip install huggingface_hub pandas pyarrow numpy scikit-learn joblib pyyaml pytest matplotlib
```

Use the repository config:

```text
application/config/pricefm_data_pipeline.yaml
```

## Metadata-Only Tests

These tests should run before local PriceFM data exist:

```sh
python -m pytest application/tests/test_pricefm_config.py
```

## Build The DE_LU Fold-1 Pilot

Run stages explicitly:

```sh
python application/scripts/pricefm/00_download_pricefm.py --config application/config/pricefm_data_pipeline.yaml
python application/scripts/pricefm/01_convert_raw_to_parquet.py --config application/config/pricefm_data_pipeline.yaml
python application/scripts/pricefm/02_audit_pricefm.py --config application/config/pricefm_data_pipeline.yaml
python application/scripts/pricefm/03_make_splits.py --config application/config/pricefm_data_pipeline.yaml
python application/scripts/pricefm/04_fit_scalers.py --config application/config/pricefm_data_pipeline.yaml
python application/scripts/pricefm/05_build_windows.py --config application/config/pricefm_data_pipeline.yaml --pilot-only true
```

Or use the orchestrator:

```sh
python application/scripts/pricefm/run_pricefm_data_pipeline.py \
  --config application/config/pricefm_data_pipeline.yaml \
  --stage all \
  --pilot-only true
```

## Data-Present Tests

Once local artifacts have been materialized, require data and run:

```sh
PRICEFM_REQUIRE_DATA=1 python -m pytest \
  application/tests/test_pricefm_audit.py \
  application/tests/test_pricefm_splits.py \
  application/tests/test_pricefm_windows.py \
  application/tests/test_pricefm_eda.py
```

Without `PRICEFM_REQUIRE_DATA=1`, data-present tests skip cleanly when local
artifacts are absent.

## Time Convention

The released file stores the raw timestamp as `time_utc`. Keep it unchanged for
provenance. The pipeline adds:

```text
market_time = time_utc + 1 hour
```

Clean splits and windows use `market_time` with half-open intervals. Every
manifest records this convention.

## Modeling Boundary

The base PriceFM data windows are not Q-DESN model inputs by themselves. The
DESN smoke workflow builds a separate stacked direct-horizon adapter under the
ignored local data root.

Build the DE_LU fold-1 DESN adapter:

```sh
python application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py \
  --smoke-config application/config/pricefm_desn_model_smoke.yaml \
  --force true
```

Run the first Normal DESN / Q-DESN smoke:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/runs/desn_model_smoke_20260530/time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/pricefm/08_run_desn_model_smoke.R \
  --smoke-config application/config/pricefm_desn_model_smoke.yaml \
  --force true

python application/scripts/pricefm/09_summarize_desn_model_smoke.py \
  --smoke-config application/config/pricefm_desn_model_smoke.yaml
```

The smoke uses DE_LU/fold 1, horizons `{1, 24, 48, 72, 96}`, quantiles
`{0.05, 0.25, 0.50}`, target-only features, Normal DESN scaled ridge/RHS_NS,
and Q-DESN-style AL/exAL RHS_NS static readouts with exact chunked VB. Generated
matrices, predictions, fitted summaries, logs, and reports remain under
`application/data_local/pricefm/`.

## Full DESN Comparison

The full comparison is configured by:

```text
application/config/pricefm_desn_model_full.yaml
application/config/pricefm_desn_model_full_median_warmstart.yaml
```

The first production launch should use the median warm-start config. It covers
all configured regions, all three folds, all 96 day-ahead horizons, and quantile
`0.50`. The broader config keeps `{0.05, 0.25, 0.50}` available after the
median run is checked.

The median warm-start chain is:

```text
RHS_NS tau0 = 1.0e-4, shrink_intercept = false
Normal scaled ridge
  -> Normal RHS_NS
    -> Q-DESN AL RHS_NS tau 0.50
      -> Q-DESN exAL RHS_NS tau 0.50
```

Warm starts pass shared beta/covariance, RHS state, and sigma where available;
they do not pass row-level, tau-specific local latent variables by default. The
full launcher is resumable and runs one region/fold cell at a time. First do a
status dry run:

```sh
python application/scripts/pricefm/10_run_desn_model_full.py \
  --config application/config/pricefm_desn_model_full_median_warmstart.yaml \
  --dry-run true
```

Before launching the real model batch, build missing all-region windows:

```sh
python application/scripts/pricefm/05_build_windows.py \
  --config application/config/pricefm_data_pipeline.yaml \
  --pilot-only false \
  --resume true \
  --force false
```

Launch command, to run only after the window and dry-run gates pass:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/runs/desn_model_full_median_warmstart_20260530/full.time.log \
  python application/scripts/pricefm/10_run_desn_model_full.py \
  --config application/config/pricefm_desn_model_full_median_warmstart.yaml \
  --jobs 4 \
  --resume true
```

Aggregate completed cells:

```sh
python application/scripts/pricefm/11_summarize_desn_model_full.py \
  --config application/config/pricefm_desn_model_full_median_warmstart.yaml
```

The launcher writes ignored local artifacts under
`application/data_local/pricefm/runs/desn_model_full_20260530/`. By default it
cleans large per-cell `X_*.csv` adapter matrices after successful cells while
retaining manifests, row metadata, metrics, predictions, and logs.

## Median Registry And Fold Diagnostics

The median experiment-grid workflow is intentionally validation-selected.
Test metrics are audit-only.

Useful scripts:

```text
12_prepare_desn_experiment_grid.py
13_run_desn_experiment_grid.py
20_select_pricefm_desn_median_specs.py
21_prepare_pricefm_quantile_grid_from_median_registry.py
22_summarize_median_grid_diagnostics.py
23_audit_desn_feature_geometry.py
24_select_median_horizon_blocks.py
25_materialize_median_horizon_block_composite.py
26_prepare_median_seed_robustness_grid.py
27_summarize_median_seed_robustness.py
29_prepare_qdesn_model_selection_bridge.py
30_validate_qdesn_model_selection_parity.py
31_run_qdesn_model_selection_bridge.py
32_summarize_pricefm_fold_complete_comparison.py
33_prepare_pricefm_region_panel_median_grid.py
47_closeout_pricefm_stage_b_median_registry.py
```

The current DE_LU fold 2/3 seed-robustness config is:

```text
application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_seed_robustness_20260604.yaml
```

It is prepared but not launched by default. Before launching, inspect:

```text
docs/implementation_notes/pricefm_de_lu_folds23_horizon_block_materialization_seed_stage_20260604.md
```

The launch runner defaults to `--dry-run true`; pass `--dry-run false` only
after confirming the generated configs, storage budget, and CPU budget.

## Q-DESN Model-Selection Bridge

The package-level authoritative Q-DESN selector is:

```text
exdqlm::qdesn_model_selection()
```

The PriceFM median selector remains an article-specific artifact registry until
the package selector fully represents PriceFM direct-horizon windows and
fold-level 1:96 horizon scoring. To keep the two systems aligned, generate a
dry-run bridge from a PriceFM grid:

```sh
python application/scripts/pricefm/29_prepare_qdesn_model_selection_bridge.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_bridge_de_lu_folds23_20260606 \
  --regions DE_LU \
  --folds 2,3 \
  --priorities 0 \
  --quantile 0.50
```

The bridge writes package-v2-style candidate configs plus a compatibility
report. Those configs are deliberately marked `package_launch_ready: false`
until the remaining PriceFM-specific scoring contract is ported.

The median selector also writes package-style compatibility artifacts alongside
the original article registry:

```text
model_selection_candidate_metrics.csv
model_selection_method_coverage.csv
model_selection_winners.csv
model_selection_contract.json
model_selection_parity_summary.json
```

These files use package-facing names and target labels, but they are still
article-side PriceFM artifacts. They keep the direct-horizon fold metric
contract explicit and block package launch until the parity gate passes.

Before treating a bridge/registry pair as apples-to-apples, run the no-refit
parity gate:

```sh
python application/scripts/pricefm/30_validate_qdesn_model_selection_parity.py \
  --bridge-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_bridge_de_lu_folds23_20260606 \
  --registry-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605 \
  --comparison-dir-template 'application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold{fold}_followup_20260605' \
  --output-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_parity_de_lu_folds23_20260606 \
  --regions DE_LU \
  --folds 2,3 \
  --expected-horizons 1:96
```

The validator checks bridge candidate IDs, registry winners, method coverage,
validation-only selection, fold-aligned row identity, and horizon coverage. It
does not launch or refit models.

To plan the full bridge/registry/parity chain without launching fits:

```sh
python application/scripts/pricefm/31_run_qdesn_model_selection_bridge.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --bridge-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_bridge_de_lu_folds23_20260606 \
  --registry-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605 \
  --parity-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_parity_de_lu_folds23_20260606 \
  --regions DE_LU \
  --folds 2,3 \
  --priorities 0 \
  --execute false
```

Pass `--execute true --select-existing true --validate-parity true` only when
the completed fold artifacts already exist. Pass `--run-grid true
--grid-dry-run false` only for an intentional model launch.

## Fold-Complete DE_LU Comparison

After fold-level PriceFM-vs-DESN comparisons exist, produce the current
fold-complete DE_LU report from an explicit fold-to-directory map:

```sh
python application/scripts/pricefm/32_summarize_pricefm_fold_complete_comparison.py \
  --region DE_LU \
  --fold-comparison-dirs '1:application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602,2:application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold2_followup_20260605,3:application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold3_followup_20260605' \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_folds123_followup_authoritative_20260606
```

This summarizer does not launch fits. It combines fold 1's authoritative run
with the improved validation-selected folds 2/3 follow-up runs, writes macro
metrics, deltas against local PriceFM Phase-I, selected-spec metadata, row
alignment audits, and comparison figures.

## Region-Panel Paper-Quantile Promotion

After the local-only region/fold median registry is frozen, promote the selected
median specs to the seven PriceFM paper/tutorial quantiles with:

```sh
python application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  --template-grid-config application/config/pricefm_desn_experiment_grid_de_lu_fold1_paper_quantiles_authoritative_20260602.yaml \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_closeout_20260613/merged_selection_registry.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_region_panel_paper_quantiles_from_local_ar_20260613.yaml \
  --grid-id pricefm_region_panel_paper_quantiles_from_local_ar_20260613 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_region_panel_paper_quantiles_from_local_ar_20260613 \
  --run-root application/data_local/pricefm/runs/pricefm_region_panel_paper_quantiles_from_local_ar_20260613 \
  --quantiles 0.10,0.25,0.45,0.50,0.55,0.75,0.90 \
  --priority 0
```

Then materialize and dry-run before launching:

```sh
python application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_region_panel_paper_quantiles_from_local_ar_20260613.yaml \
  --write

python application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_region_panel_paper_quantiles_from_local_ar_20260613.yaml \
  --priorities 0 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true
```

The generated grid preserves local-only metadata from the median registry in
each experiment, manifest row, and generated full config. This matters because
the immediate fold-aligned benchmark is PriceFM Phase-I target-gated, not the
full graph-neighbor Phase-II system.

For Stage-B expansion batches that add new regions beyond the frozen six-region
registry, use the Stage-B closeout helper instead of the older registry merger.
The previous registry is context only; new region/fold rows are triaged against
their own best naive test baseline:

```sh
python application/scripts/pricefm/47_closeout_pricefm_stage_b_median_registry.py \
  --registry-dir application/data_local/pricefm/authoritative/pricefm_stage_b_median_batch1_registry_20260616 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_b_median_batch1_closeout_20260616 \
  --previous-registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv \
  --grid-id pricefm_stage_b_median_batch1_20260616 \
  --candidate-source stage_b_local_median_batch1_20260616 \
  --selection-methods qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked \
  --naive-methods naive1_prev_day,naive2_prev3_avg,naive3_prev7_avg \
  --diagnostic-methods normal_rhs_ns,normal_scaled_ridge \
  --selection-split val \
  --test-split test \
  --unit original \
  --metric AQL
```

Then promote only the selected median rows to a tau `0.50` comparison grid:

```sh
python application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  --template-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_median_batch1_20260616.yaml \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_b_median_batch1_registry_20260616/median_selection_registry.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_median_tau0p50_20260616.yaml \
  --grid-id pricefm_stage_b_median_tau0p50_20260616 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_stage_b_median_tau0p50_20260616 \
  --run-root application/data_local/pricefm/runs/pricefm_stage_b_median_tau0p50_20260616 \
  --quantiles 0.5 \
  --priority 0
```

This median-only promoted run is the economical apples-to-apples gate before
launching the full seven-paper-quantile promotion for the new Stage-B regions.

Freeze the Stage-B median handoff before launching either paper quantiles or
median rescue grids:

```sh
python application/scripts/pricefm/48_freeze_pricefm_stage_b_decision_registry.py \
  --registry-dir application/data_local/pricefm/authoritative/pricefm_stage_b_median_batch1_registry_20260616 \
  --closeout-dir application/data_local/pricefm/authoritative/pricefm_stage_b_median_batch1_closeout_20260616 \
  --comparison-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_b_median_tau0p50_20260616 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_b_decision_registry_20260616 \
  --grid-id pricefm_stage_b_median_batch1_20260616
```

This writes ignored local CSVs for the canonical next actions:

```text
stage_b_promotion_ready_registry.csv
stage_b_conflict_confirm_registry.csv
stage_b_rescue_needed_registry.csv
stage_b_rescue_scope.csv
stage_b_decision_report.md
```

Use `stage_b_promotion_ready_registry.csv` as the source for seven paper
quantiles. Use `stage_b_rescue_needed_registry.csv` plus
`stage_b_rescue_scope.csv` as the source for the next median rescue grid.

After a targeted graph/local median rescue grid finishes, close it out without
replacing the authoritative registry blindly:

```sh
python application/scripts/pricefm/42_closeout_pricefm_graph_local_rescue.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_graph_local_median_rescue_20260615/manifest.csv \
  --run-root application/data_local/pricefm/runs/pricefm_graph_local_median_rescue_20260615 \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_graph_local_median_rescue_closeout_20260616
```

The closeout writes ignored local artifacts including
`rescue_closeout_decisions.csv`, `robustness_candidate_queue.csv`,
`test_only_diagnostic_queue.csv`, `robustness_seed_plan.csv`, hypothetical
registry audits, and a compact Markdown report. The current registry remains
authoritative unless a queued rescue passes a later seed-robustness gate.

Prepare and summarize the seed-robustness gate for queued rescue candidates:

```sh
python application/scripts/pricefm/43_prepare_pricefm_graph_local_rescue_seed_grid.py \
  --source-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_median_rescue_20260615.yaml \
  --seed-plan-csv application/data_local/pricefm/authoritative/pricefm_graph_local_median_rescue_closeout_20260616/robustness_seed_plan.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_rescue_seedrob_itsici_f3_20260616.yaml \
  --grid-id pricefm_graph_local_rescue_seedrob_itsici_f3_20260616 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616 \
  --run-root application/data_local/pricefm/runs/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616

python application/scripts/pricefm/44_summarize_pricefm_graph_local_rescue_seedrob.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616/manifest.csv \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616

python application/scripts/pricefm/45_patch_pricefm_median_registry_from_seedrob.py \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv \
  --seedrob-decisions-csv application/data_local/pricefm/authoritative/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616/seedrob_decisions.csv \
  --promotion-ready-csv application/data_local/pricefm/authoritative/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616/promotion_ready_queue.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_graph_local_rescue_seedrob_patch_20260616
```

The seed gate is intentionally stricter than a single validation win: by
default every seed must beat the current validation AQL, the mean audit-test
AQL delta must be non-positive, and no seed may exceed the allowed relative
test deterioration threshold. The patch helper fails early when the promotion
queue is empty.

After the 126 cells finish, summarize all region/fold outputs consistently:

```sh
python application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_closeout_20260613/merged_selection_registry.csv \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_region_panel_paper_quantiles_from_local_ar_20260613.yaml \
  --output-root application/data_local/pricefm/authoritative/pricefm_region_panel_paper_quantiles_from_local_ar_20260613 \
  --require-complete true \
  --dry-run false
```

Regenerate fold-aligned PriceFM Phase-I target-gated predictions and compare:

```sh
python application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_closeout_20260613/merged_selection_registry.csv \
  --config application/config/pricefm_data_pipeline.yaml \
  --pricefm-root application/data_local/pricefm/authoritative/pricefm_phase1_region_panel_apples_to_apples_20260613 \
  --desn-root application/data_local/pricefm/authoritative/pricefm_region_panel_paper_quantiles_from_local_ar_20260613 \
  --output-root application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_region_panel_from_local_ar_20260613 \
  --run-pricefm true \
  --dry-run false
```

For a median-only promoted grid, pass the explicit quantile set so the
comparison does not assume the seven-paper-quantile grid:

```sh
python application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_b_median_batch1_registry_20260616/median_selection_registry.csv \
  --config application/config/pricefm_data_pipeline.yaml \
  --pricefm-root application/data_local/pricefm/authoritative/pricefm_phase1_stage_b_apples_to_apples_20260616 \
  --desn-root application/data_local/pricefm/authoritative/pricefm_stage_b_median_tau0p50_outputs_20260616 \
  --output-root application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_b_median_tau0p50_20260616 \
  --split test \
  --methods pricefm_phase1_pretraining,qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked,normal_rhs_ns,normal_scaled_ridge \
  --quantiles 0.5 \
  --run-pricefm true \
  --dry-run false
```

## Region-Panel Median Selection

After DE_LU is closed, prepare a small diverse region-panel median-selection
grid before attempting all 38 regions:

```sh
python application/scripts/pricefm/33_prepare_pricefm_region_panel_median_grid.py \
  --output-grid-config application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml \
  --summary-dir application/data_local/pricefm/authoritative/pricefm_region_panel_median_grid_20260606 \
  --write true
```

The current panel is selected from local PriceFM audit/reference diagnostics:

```text
DE_LU, EE, HU, NO_4, SE_2, IT_SICI
```

Generate configs and do the non-launching dry run:

```sh
python application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml \
  --write

python application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml \
  --priorities 0,1 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true
```

Only after the dry-run manifests are inspected should a real launch use
`--dry-run false`, preferably starting with priority `0`.

## Stage-B New-Region Median Expansion

After the six-region graph/local panel is frozen, prepare the first new-region
median batch with:

```sh
python application/scripts/pricefm/46_prepare_pricefm_stage_b_region_batch.py \
  --write true
```

The default Stage-B batch is local-first and validation-selected. It covers:

```text
PT, BG, ES, FR, FI, IT_NORD, AT, PL
```

Generated configs and manifests stay under ignored local paths:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_median_batch1_20260616.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_b_median_batch1_20260616/
application/data_local/pricefm/runs/pricefm_stage_b_median_batch1_20260616/
```

Materialize and dry-run priority 0:

```sh
python application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_median_batch1_20260616.yaml \
  --write

python application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_b_median_batch1_20260616.yaml \
  --priorities 0 \
  --experiment-jobs 3 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true
```

Launch priority 0 only after the dry-run passes. Do not run priority 1, graph
A/B, or paper-quantile promotion until the priority-0 local median closeout has
been inspected.

## Exploratory Region Figures

After the Parquet/audit stage exists, produce one exploratory figure per region:

```sh
python application/scripts/pricefm/06_make_region_feature_figures.py \
  --config application/config/pricefm_data_pipeline.yaml \
  --regions all
```

Figures and manifests are written under:

```text
application/data_local/pricefm/figures/region_feature_overview/
```

Each figure has five stacked panels for `generation`, `load`, `price`,
`solar`, and `wind`. The plot uses daily summaries over the common
`market_time` window so all 38 regions can be reviewed consistently.
