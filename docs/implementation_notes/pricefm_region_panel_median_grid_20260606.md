# PriceFM Region-Panel Median Grid

Date: 2026-06-06

## Scope

This stage prepares the next PriceFM comparison step after the DE_LU
fold-complete pilot. It does not launch model fits. It selects a small,
diagnostically diverse region panel and creates a median-only DESN/Q-DESN grid
that can be launched in staged priorities.

## Region Panel

The panel was selected from the local PriceFM audit table and the local
PriceFM Phase-I reference metrics.

| rank | region | selection_role | Phase-I AQL | median price | p99-p01 spread | negative rate |
| ---: | --- | --- | ---: | ---: | ---: | ---: |
| 1 | DE_LU | anchor_required | 5.675211 | 99.575 | 544.2518 | 0.039228 |
| 2 | EE | hardest_phase1_aql | 15.448769 | 94.940 | 491.0986 | 0.014794 |
| 3 | HU | widest_price_spread | 7.544218 | 114.080 | 583.8604 | 0.017803 |
| 4 | NO_4 | narrowest_price_spread | 3.001586 | 14.665 | 129.0351 | 0.019692 |
| 5 | SE_2 | highest_negative_price_rate | 4.262765 | 20.150 | 270.8858 | 0.052988 |
| 6 | IT_SICI | highest_median_price | 4.191535 | 126.800 | 565.0000 | 0.000000 |

This gives one anchor region plus high-difficulty, high-spread, low-spread,
high-negative-price, and high-median-price cases.

## Grid

Tracked config:

```text
application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml
```

Ignored local planning output:

```text
application/data_local/pricefm/authoritative/pricefm_region_panel_median_grid_20260606/
```

Grid scope:

```text
regions: DE_LU, EE, HU, NO_4, SE_2, IT_SICI
folds: 1, 2, 3
quantile: 0.50
target: validation AQL on original scale
methods: Q-DESN AL/exAL RHS_NS exact chunked, plus Normal DESN baselines from the full runner
```

Planned median cells:

| experiment_id | priority | cells | description |
| --- | ---: | ---: | --- |
| `panel_core_l096_d1_n120_a0p5_r0p9_in0p50_seed20260601` | 0 | 18 | corrected DE_LU fold-1 anchor |
| `panel_lowinput_l096_d1_n120_a0p5_r0p9_in0p25_seed20260603` | 0 | 18 | fold-2 low-input winner geometry |
| `panel_d2_l096_d2_n080x080_a0p4_r0p9_in0p35_seed20260603` | 0 | 18 | fold-3 compact D=2 winner geometry |
| `panel_compact_l096_d1_n080_a0p5_r0p9_in0p50_seed20260603` | 1 | 18 | compact D=1 diagnostic |
| `panel_short_l072_d1_n120_a0p5_r0p9_in0p50_seed20260603` | 1 | 18 | short-context diagnostic |
| `panel_long_l128_d1_n120_a0p5_r0p9_in0p50_seed20260603` | 1 | 18 | slightly longer-context diagnostic |

Total planned cells: `108`.

## Commands Run

Prepare the panel grid:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/33_prepare_pricefm_region_panel_median_grid.py \
  --config application/config/pricefm_data_pipeline.yaml \
  --template-grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --phase1-reference-csv application/data_local/pricefm/external/PriceFM/Result/phase1_pretraining.csv \
  --output-grid-config application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml \
  --summary-dir application/data_local/pricefm/authoritative/pricefm_region_panel_median_grid_20260606 \
  --grid-id pricefm_median_region_panel_20260606 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_median_region_panel_20260606 \
  --run-root application/data_local/pricefm/runs/pricefm_median_region_panel_20260606 \
  --required-regions DE_LU \
  --folds 1,2,3 \
  --panel-size 6 \
  --write true
```

Generate ignored per-experiment configs:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml \
  --write
```

Dry-run launch gate:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml \
  --priorities 0,1 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true
```

Dry-run result:

```text
n_selected_experiments: 6
status: planned for all 6 experiments and all 6 window-build steps
no model fits launched
```

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_region_panel_grid.py \
  application/tests/test_pricefm_desn_experiment_grid.py \
  application/tests/test_pricefm_full_run_config.py
```

Expected checks:

- selected panel is role-based and deduplicated;
- grid contains 6 experiments and 108 region/fold cells;
- shrink-intercept is false;
- median quantile is 0.50 only;
- Q-DESN likelihoods are AL and exAL;
- generated configs remain under ignored local paths;
- dry-run launch status is `planned`, not executed.

## Launch Recommendation

Do not launch all priorities at once first. If compute/storage is approved:

```sh
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml \
  --priorities 0 \
  --experiment-jobs 6 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

Then select by validation AQL, inspect region/fold diagnostics, and only then
decide whether to launch priority 1.

## Next Stage After Launch

After priority 0 completes:

1. run `20_select_pricefm_desn_median_specs.py` on the region-panel grid;
2. create package-style selector artifacts and parity-style checks where
   applicable;
3. promote each region/fold median winner to paper quantiles;
4. run local PriceFM Phase-I comparisons;
5. summarize region-panel robustness before any all-38-region run.
