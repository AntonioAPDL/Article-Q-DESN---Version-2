# PriceFM Region-Panel Paper-Quantile Comparison Closeout

Date: 2026-06-14

## Scope

This note closes the local-only DESN/Q-DESN paper-quantile region-panel run and
the fold-aligned PriceFM Phase-I comparison.

The run covers 6 regions by 3 folds:

```text
DE_LU, EE, HU, IT_SICI, NO_4, SE_2
folds: 1, 2, 3
quantiles: 0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90
horizons: 1:96
```

The comparison is PriceFM Phase-I only. It is not a PriceFM Phase-II
graph-neighbor comparison.

## Final Local Paths

```text
DESN/Q-DESN quantile run root:
application/data_local/pricefm/runs/pricefm_region_panel_paper_quantiles_from_local_ar_20260613

DESN/Q-DESN panel summary:
application/data_local/pricefm/authoritative/pricefm_region_panel_paper_quantiles_from_local_ar_20260613

Fold-aligned PriceFM Phase-I predictions:
application/data_local/pricefm/authoritative/pricefm_phase1_region_panel_apples_to_apples_20260613

Fold-aligned PriceFM-vs-DESN comparison:
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_region_panel_from_local_ar_20260613
```

Generated outputs remain under ignored local paths.

## Collector Fix

The first panel summary failed while concatenating per-region/fold CSVs because
some child summary files already contained `region` and `fold` columns:

```text
ValueError: cannot insert fold, already exists
```

The collector now validates existing scope columns against the enclosing
`region=/fold=` directory and only inserts missing columns. A mismatch raises a
clear error. The same guard was applied to the PriceFM comparison collector.

Changed scripts:

```text
application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py
application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py
```

Focused tests:

```text
application/tests/test_pricefm_paper_quantile_summary.py
application/tests/test_pricefm_phase1_comparison.py
```

## Commands

Panel DESN/Q-DESN summary:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_closeout_20260613/merged_selection_registry.csv \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_region_panel_paper_quantiles_from_local_ar_20260613.yaml \
  --output-root application/data_local/pricefm/authoritative/pricefm_region_panel_paper_quantiles_from_local_ar_20260613 \
  --require-complete true \
  --dry-run false
```

Fold-aligned PriceFM Phase-I comparison:

```bash
application/data_local/pricefm/venv_pricefm_tf/bin/python \
  application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_closeout_20260613/merged_selection_registry.csv \
  --config application/config/pricefm_data_pipeline.yaml \
  --pricefm-root application/data_local/pricefm/authoritative/pricefm_phase1_region_panel_apples_to_apples_20260613 \
  --desn-root application/data_local/pricefm/authoritative/pricefm_region_panel_paper_quantiles_from_local_ar_20260613 \
  --output-root application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_region_panel_from_local_ar_20260613 \
  --run-pricefm true \
  --dry-run false
```

The PriceFM comparison must use `venv_pricefm_tf`, because the lightweight
PriceFM/DESN venv intentionally does not include TensorFlow.

## Validation

Focused tests passed:

```text
test_pricefm_paper_quantile_summary.py: 10 passed
test_pricefm_phase1_comparison.py: 11 passed
```

Panel summary status:

```text
status: completed
n_region_folds: 18
panel_metric.csv rows: 504 data rows
panel_status.csv rows: 126 data rows
panel_runtime.csv rows: 126 data rows
```

PriceFM comparison status:

```text
pricefm_phase1: 18 completed
comparison: 18 completed
panel_metric.csv rows: 180 data rows
panel_horizon.csv rows: 17,280 data rows
local_only_competitiveness_flags.csv rows: 18 data rows
row-alignment mismatches: 0
aligned prediction rows per method/fold: 80,640 to 82,656
```

No `.rds`, `.rda`, or `.RData` files remain under the three current
PriceFM panel run/summary/comparison roots.

## Local-Only DESN/Q-DESN Versus Naive Baselines

Using original-scale test AQL and the best local Q-DESN method per region/fold:

```text
Q-DESN beats best naive: 15 / 18 folds
median relative AQL improvement: 12.95%
mean relative AQL improvement: 15.92%
```

Mean original-scale AQL by method:

| method | mean AQL |
|---|---:|
| `qdesn_exal_rhs_ns_exact_chunked` | 7.513 |
| `qdesn_al_rhs_ns_exact_chunked` | 7.575 |
| `naive3_prev7_avg` | 9.105 |
| `normal_rhs_ns` | 9.239 |
| `naive1_prev_day` | 9.345 |
| `naive2_prev3_avg` | 9.458 |
| `normal_scaled_ridge` | 52.144 |

## Fold-Aligned PriceFM Phase-I Comparison

Using original-scale test AQL and the best local method per region/fold:

```text
local beats PriceFM Phase-I: 5 / 18 folds
local within 5% of PriceFM Phase-I: 2 / 18 folds
local lags PriceFM Phase-I by more than 5%: 11 / 18 folds
median relative AQL delta versus PriceFM: +6.67%
mean relative AQL delta versus PriceFM: +10.52%
```

The best local method was Q-DESN in all 18 folds:

```text
qdesn_exal_rhs_ns_exact_chunked: 15 folds
qdesn_al_rhs_ns_exact_chunked:  3 folds
```

Mean original-scale AQL by method in the fold-aligned comparison:

| method | mean AQL |
|---|---:|
| `pricefm_phase1_pretraining` | 7.003 |
| `qdesn_exal_rhs_ns_exact_chunked` | 7.513 |
| `qdesn_al_rhs_ns_exact_chunked` | 7.575 |
| `normal_rhs_ns` | 9.239 |
| `normal_scaled_ridge` | 52.144 |

Best local method versus PriceFM Phase-I:

| region | fold | best local method | local AQL | PriceFM AQL | relative delta | decision |
|---|---:|---|---:|---:|---:|---|
| DE_LU | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 5.271 | 5.324 | -0.98% | beats |
| DE_LU | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 5.628 | 5.355 | +5.09% | lags |
| DE_LU | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 6.884 | 6.030 | +14.16% | lags |
| EE | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 17.690 | 19.270 | -8.20% | beats |
| EE | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 14.010 | 13.365 | +4.83% | close |
| EE | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 16.351 | 16.114 | +1.47% | close |
| HU | 1 | `qdesn_al_rhs_ns_exact_chunked` | 9.214 | 8.500 | +8.40% | lags |
| HU | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 11.795 | 7.322 | +61.09% | lags |
| HU | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 9.983 | 8.545 | +16.83% | lags |
| IT_SICI | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 5.977 | 6.696 | -10.74% | beats |
| IT_SICI | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 5.450 | 6.414 | -15.03% | beats |
| IT_SICI | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 5.314 | 4.721 | +12.57% | lags |
| NO_4 | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 2.136 | 1.542 | +38.53% | lags |
| NO_4 | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 1.318 | 1.225 | +7.66% | lags |
| NO_4 | 3 | `qdesn_al_rhs_ns_exact_chunked` | 3.321 | 3.143 | +5.67% | lags |
| SE_2 | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 6.446 | 4.214 | +52.97% | lags |
| SE_2 | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 3.028 | 3.638 | -16.77% | beats |
| SE_2 | 3 | `qdesn_al_rhs_ns_exact_chunked` | 5.180 | 4.633 | +11.81% | lags |

## Interpretation

The local Q-DESN family is clearly useful relative to simple local baselines,
but PriceFM Phase-I remains stronger overall on this six-region panel. The
local model is already competitive in several folds despite using local
autoregressive inputs rather than graph-neighbor covariates.

The strongest next modeling direction is not another collector or summary
change. It is feature/input expansion: add controlled neighbor-region inputs or
a spatial covariate adapter, then rerun the same region-panel selection and
paper-quantile comparison pipeline. That would make the comparison closer to
PriceFM's information set while preserving the reproducible evaluation
machinery built here.
