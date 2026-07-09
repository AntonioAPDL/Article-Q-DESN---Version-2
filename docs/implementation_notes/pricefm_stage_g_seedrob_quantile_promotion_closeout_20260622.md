# PriceFM Stage-G Seed-Robust Quantile Promotion Closeout

Date: 2026-06-22

## Scope

This note closes the Stage-G seed-robust patch-only quantile promotion pass.
It promotes the six median rows patched by the Stage-G seed-robust rescue
registry to the seven paper quantiles:

`0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`.

The pass deliberately did not relaunch the full 42-row Stage-F panel. It only
reran the six patched rows and then merged the resulting quantile decisions
over the prior Stage-F authoritative registry.

## Inputs

- Patch-row registry:
  `application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/patch_rows_registry.csv`
- Patched full median registry:
  `application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/patched_selection_registry.csv`
- Prior authoritative quantile registry:
  `application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_f_20260621/authoritative_quantile_decision_registry.csv`
- Stage-E cached fold-aligned PriceFM Phase-I benchmark:
  `application/data_local/pricefm/authoritative/pricefm_phase1_stage_e_full_panel_missing_paper_quantiles_20260619`

## Generated Outputs

- Grid config:
  `application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_seedrob_promoted_quantiles_20260622.yaml`
- Grid manifest:
  `application/data_local/pricefm/experiment_grids/pricefm_stage_g_seedrob_promoted_quantiles_20260622/manifest.csv`
- Run root:
  `application/data_local/pricefm/runs/pricefm_stage_g_seedrob_promoted_quantiles_20260622`
- Quantile panel summary:
  `application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_promoted_quantiles_summary_20260622`
- Cached Phase-I comparison:
  `application/data_local/pricefm/authoritative/pricefm_phase1_cached_vs_stage_g_seedrob_promoted_quantiles_20260622`
- Patch decision freeze:
  `application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_quantile_decisions_20260622`
- Merged authoritative registry:
  `application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_g_seedrob_20260622`

## Commands

Generate the patch-only quantile grid:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  --template-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_f_graph_median_rescue_promoted_quantiles_20260621.yaml \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/patch_rows_registry.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_seedrob_promoted_quantiles_20260622.yaml \
  --grid-id pricefm_stage_g_seedrob_promoted_quantiles_20260622 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_stage_g_seedrob_promoted_quantiles_20260622 \
  --run-root application/data_local/pricefm/runs/pricefm_stage_g_seedrob_promoted_quantiles_20260622 \
  --quantiles 0.10,0.25,0.45,0.50,0.55,0.75,0.90 \
  --priority 0
```

Dry-run and launch:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_seedrob_promoted_quantiles_20260622.yaml \
  --priorities 0 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run false
```

Summarize, compare, freeze, and merge:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/patch_rows_registry.csv \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_seedrob_promoted_quantiles_20260622.yaml \
  --output-root application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_promoted_quantiles_summary_20260622 \
  --require-complete true \
  --dry-run false \
  --panel-label stage_g_seedrob_patch_quantiles \
  --panel-description "Stage-G seed-robust graph/local rescue patched-row paper quantiles for six region/folds."

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/patch_rows_registry.csv \
  --config application/config/pricefm_data_pipeline.yaml \
  --pricefm-root application/data_local/pricefm/authoritative/pricefm_phase1_stage_e_full_panel_missing_paper_quantiles_20260619 \
  --desn-root application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_promoted_quantiles_summary_20260622 \
  --output-root application/data_local/pricefm/authoritative/pricefm_phase1_cached_vs_stage_g_seedrob_promoted_quantiles_20260622 \
  --split test \
  --quantiles 0.10,0.25,0.45,0.50,0.55,0.75,0.90 \
  --run-pricefm false \
  --desn-panel-label stage_g_seedrob_patch_quantiles \
  --desn-panel-description "Stage-G seed-robust patched-row local DESN/Q-DESN paper quantiles" \
  --comparison-note "Stage-G patch-only comparison using cached fold-aligned PriceFM Phase-I predictions." \
  --dry-run false

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/53_freeze_pricefm_stage_c_quantile_decisions.py \
  --comparison-dir application/data_local/pricefm/authoritative/pricefm_phase1_cached_vs_stage_g_seedrob_promoted_quantiles_20260622 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_quantile_decisions_20260622 \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/patch_rows_registry.csv \
  --pricefm-method pricefm_phase1_pretraining \
  --split test \
  --unit original \
  --metric AQL \
  --close-rel-threshold 0.05 \
  --grid-id pricefm_stage_g_seedrob_promoted_quantiles_20260622

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/57_freeze_pricefm_authoritative_quantile_decisions.py \
  --median-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/patched_selection_registry.csv \
  --decision-source stage_f=application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_f_20260621/authoritative_quantile_decision_registry.csv \
  --decision-source stage_g_seedrob_patch=application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_quantile_decisions_20260622/stage_c_quantile_decision_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_g_seedrob_20260622 \
  --registry-id pricefm_authoritative_quantile_decisions_stage_g_seedrob_20260622
```

## Launch Validation

The patch-only quantile launch ran 42 experiments:

- 6 region/folds.
- 7 quantiles per region/fold.
- `--experiment-jobs 10`.
- `--cell-jobs 1`.
- Threaded BLAS/OpenMP variables pinned to one thread per process.

Launch timing from `/usr/bin/time -v`:

- Wall time: `1:31:53`.
- CPU utilization: `806%`.
- Max RSS: `1,425,900 KB`.
- Exit status: `0`.

Artifact completeness:

| Artifact | Complete |
|---|---:|
| `metric_summary.csv` | 42 / 42 |
| `report.md` | 42 / 42 |
| `model_predictions_scaled.csv` | 42 / 42 |
| `repo_state.json` | 42 / 42 |

No Stage-G launch failure logs were detected. No Stage-G `.rds`, `.rda`, or
`.rdata` files were present in the run tree after completion.

## PriceFM Benchmark Note

A fresh PriceFM Phase-I rerun was attempted in:

`application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_g_seedrob_promoted_quantiles_20260622`

It failed immediately because the local PriceFM Python environment does not
provide TensorFlow:

```text
ModuleNotFoundError: No module named 'tensorflow'
```

The completed comparison therefore uses the existing cached fold-aligned
Stage-E Phase-I benchmark, which already covers the six patched region/folds:

`application/data_local/pricefm/authoritative/pricefm_phase1_stage_e_full_panel_missing_paper_quantiles_20260619`

This is a reproducible cache-based comparison, not a fresh PriceFM model
execution.

## Patch-Only Results

The six patched region/folds had mean local AQL `8.61947` versus cached
PriceFM Phase-I AQL `9.36114`, for mean delta `-0.74166`
(`-7.81%`). Lower AQL is better.

| Region | Fold | Best local method | Local AQL | PriceFM AQL | Delta | Decision |
|---|---:|---|---:|---:|---:|---|
| DK_1 | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 7.21310 | 7.94329 | -0.73019 | promote local |
| DK_2 | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 6.31483 | 8.06105 | -1.74622 | promote local |
| DK_2 | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 6.33181 | 8.25147 | -1.91966 | promote local |
| EE | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 12.46210 | 13.36456 | -0.90245 | promote local |
| HU | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 8.68414 | 7.32221 | 1.36193 | PriceFM fallback |
| LT | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 10.71085 | 11.22424 | -0.51340 | promote local |

Patch-only freeze counts:

- Promoted local rows: 5.
- Close-to-PriceFM rows: 0.
- PriceFM fallback rows: 1.

## Merged Authoritative Registry

Merged output:

`application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_g_seedrob_20260622/authoritative_quantile_decision_registry.csv`

Merged counts:

| Source | Decision | Region/folds |
|---|---|---:|
| stage_f | `stage_c_confirmed_local_win` | 17 |
| stage_f | `stage_c_local_close_to_pricefm` | 6 |
| stage_f | `stage_c_pricefm_fallback` | 13 |
| stage_g_seedrob_patch | `stage_c_confirmed_local_win` | 5 |
| stage_g_seedrob_patch | `stage_c_pricefm_fallback` | 1 |

Overall merged registry:

- Region/folds: 42.
- Local promotions: 22.
- Close-to-PriceFM rows: 6.
- PriceFM fallbacks: 14.
- Mean local AQL: `8.87820`.
- Mean PriceFM AQL: `8.95977`.
- Mean delta: `-0.08157` (`-0.87%`).

## Validation Checks

Focused checks passed:

```sh
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py \
  application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py \
  application/scripts/pricefm/53_freeze_pricefm_stage_c_quantile_decisions.py \
  application/scripts/pricefm/57_freeze_pricefm_authoritative_quantile_decisions.py

application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_graph_local_rescue_workflow.py -q

git diff --check
```

Result:

- `8 passed`.
- `git diff --check` clean.

## Interpretation

The Stage-G seed-robust patch materially improves the six patched rows: five
of six now beat cached PriceFM Phase-I on the seven-quantile paper grid.
The full 42-row registry improves slightly on average versus PriceFM, but the
margin is modest because the registry intentionally keeps PriceFM fallbacks
where local models are not yet competitive.

The remaining weak patch row is `HU` fold 2, where the local method lags
PriceFM by about 18.6% AQL. It remains a PriceFM fallback in the authoritative
registry.

## Recommended Next Stage

Before any full-paper claim, resolve the PriceFM TensorFlow environment so
fresh Phase-I benchmarks can be regenerated when needed. For modeling, the next
high-value step is not another broad global search; it is a targeted rescue for
the remaining fallback/close rows, especially `HU` fold 2, using the same
cache-aware and binary-clean workflow used here.
