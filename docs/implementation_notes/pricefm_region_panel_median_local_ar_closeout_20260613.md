# PriceFM Region-Panel Median Local-AR Closeout

Date: 2026-06-13

## Purpose

This note closes out the completed PriceFM median local-AR D2/D3 exploration
against the previous authoritative region-fold median registry. The closeout is
validation-selected and local-only. Test metrics are audit fields only; they are
not used as hidden selection criteria.

The output is not a global DESN specification. It is a region-fold registry:
each target region and fold keeps or promotes its own median specification.

## Inputs

Completed grid config:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_median_region_panel_depth_local_ar_20260610.yaml
```

Completed grid outputs:

```text
application/data_local/pricefm/experiment_grids/pricefm_median_region_panel_depth_local_ar_20260610
application/data_local/pricefm/runs/pricefm_median_region_panel_depth_local_ar_20260610
```

Previous authoritative registry:

```text
application/data_local/pricefm/authoritative/pricefm_region_panel_median_depth_refine_merged_closeout_20260610/merged_selection_registry.csv
```

New validation-selected registry:

```text
application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_registry_20260613
```

Final closeout:

```text
application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_closeout_20260613
```

## Reproducible Commands

Regenerate the validation-selected registry:

```bash
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_median_region_panel_depth_local_ar_20260610.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_registry_20260613 \
  --priorities 0 \
  --selection-split val \
  --selection-unit original \
  --selection-metric AQL \
  --selection-methods qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked \
  --require-complete true
```

Regenerate the closeout:

```bash
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/34_closeout_pricefm_median_registry.py \
  --new-registry-dir application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_registry_20260613 \
  --previous-registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_depth_refine_merged_closeout_20260610/merged_selection_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_closeout_20260613 \
  --grid-id pricefm_median_region_panel_depth_local_ar_20260610 \
  --candidate-source local_ar_20260610
```

## Run Health

The local-AR run completed cleanly:

| Check | Result |
|---|---:|
| experiments completed | 84 / 84 |
| metric/model/report cells completed | 1512 / 1512 |
| figures present | 12096 |
| heavy `.rds/.rda/.RData` artifacts under run root | 0 |
| run tree size | about 59 GB |
| selector candidate metrics | 42336 rows |
| selector selected winners | 18 region-fold rows |

## Closeout Policy

The closeout compares each local-AR validation-selected candidate against the
current authoritative row for the same `region, fold`.

Promotion is recommended only when:

- validation AQL improves over the current row;
- the selected model reports convergence;
- test AQL and test RMSE do not trigger configured stability warnings.

Rows with validation improvement but test instability or non-convergence are
marked for review and keep the previous authoritative winner in the merged
registry. Rows without validation improvement keep the previous authoritative
winner.

Information-set labels are attached to the final registry:

```text
input_scope = local_target_only
output_scope = target_region_path
lead_covariate_status = realized_ex_post
spatial_information_set = local_only_not_pricefm_graph
```

These labels are required because the current DESN/Q-DESN setup uses only the
target region's own lag and lead covariates, while PriceFM can use graph-neighbor
inputs.

## Decision Summary

| Decision | Count |
|---|---:|
| promote_candidate | 7 |
| keep_previous_no_val_gain | 6 |
| review_val_gain_test_risk | 4 |
| review_val_gain_convergence_risk | 1 |

Aggregate deltas for the 18 local-AR candidates versus the current registry:

| Metric | Mean candidate minus current |
|---|---:|
| validation AQL | -0.074766 |
| test AQL | 0.503401 |
| test RMSE | 5.834232 |

Interpretation: local-AR features are clearly useful for some region-folds, but
the full set is not uniformly stable on the held-out test window. The scripted
merged registry therefore promotes only clean validation wins and quarantines
test-risk or convergence-risk rows.

## Final Region-Fold Registry

| Region | Fold | Method | Experiment | Val AQL | Test AQL | Test RMSE | Source | Decision |
|---|---:|---|---|---:|---:|---:|---|---|
| DE_LU | 1 | qdesn_al_rhs_ns_exact_chunked | localar_d2_u120_alpha_input_scale0p5_alpha0p5 | 7.891220 | 6.617376 | 20.388428 | local_ar_20260610 | promote_candidate |
| DE_LU | 2 | qdesn_exal_rhs_ns_exact_chunked | panel_core_l096_d1_n120_a0p5_r0p9_in0p50_seed20260601 | 6.181049 | 7.017303 | 21.203184 | priorities01 | keep_previous_no_val_gain |
| DE_LU | 3 | qdesn_exal_rhs_ns_exact_chunked | broad_l096_d2_n120x120_a0p4_r0p9_in0p25_seed20260608 | 6.717525 | 8.486939 | 26.936150 | broad20260608 | keep_previous_no_val_gain |
| EE | 1 | qdesn_exal_rhs_ns_exact_chunked | depthcore_d3_units40x40x40_input_scale0p25 | 17.831382 | 21.630667 | 61.270684 | depth_refine_20260610 | review_val_gain_test_risk |
| EE | 2 | qdesn_exal_rhs_ns_exact_chunked | localar_d2_u60_rho_input_scale0p5_rho0p75 | 20.909241 | 17.381593 | 46.849022 | local_ar_20260610 | promote_candidate |
| EE | 3 | qdesn_exal_rhs_ns_exact_chunked | localar_d2_u120_rho_input_scale0p2_rho0p75 | 15.987764 | 20.243141 | 63.447434 | local_ar_20260610 | promote_candidate |
| HU | 1 | qdesn_al_rhs_ns_exact_chunked | depthcore_d2_ultracompact_input_scale0p25 | 14.997207 | 11.588967 | 34.224430 | depth_refine_20260610 | keep_previous_no_val_gain |
| HU | 2 | qdesn_exal_rhs_ns_exact_chunked | localar_d3_u80_alpha_input_scale0p2_alpha0p25 | 11.195743 | 14.505655 | 39.699236 | local_ar_20260610 | promote_candidate |
| HU | 3 | qdesn_exal_rhs_ns_exact_chunked | depthcore_d2_units60x60_input_scale0p2 | 12.587748 | 11.943118 | 37.999981 | depth_refine_20260610 | review_val_gain_test_risk |
| IT_SICI | 1 | qdesn_exal_rhs_ns_exact_chunked | depthcore_d2_units80x80_input_scale0p25 | 6.673238 | 7.268194 | 21.233634 | depth_refine_20260610 | review_val_gain_convergence_risk |
| IT_SICI | 2 | qdesn_exal_rhs_ns_exact_chunked | depthcore_d3_units40x40x40_input_scale0p25 | 6.812223 | 6.809447 | 19.276782 | depth_refine_20260610 | keep_previous_no_val_gain |
| IT_SICI | 3 | qdesn_al_rhs_ns_exact_chunked | depthcore_d3_lowinput_input_scale0p2 | 6.368149 | 6.554387 | 18.928174 | depth_refine_20260610 | review_val_gain_test_risk |
| NO_4 | 1 | qdesn_al_rhs_ns_exact_chunked | depthcore_d2_units120x120_input_scale0p5 | 1.129723 | 2.303810 | 12.029519 | depth_refine_20260610 | review_val_gain_test_risk |
| NO_4 | 2 | qdesn_al_rhs_ns_exact_chunked | depthcore_d2_ultracompact_input_scale0p25 | 1.869315 | 1.532006 | 7.652737 | depth_refine_20260610 | keep_previous_no_val_gain |
| NO_4 | 3 | qdesn_al_rhs_ns_exact_chunked | localar_d3_u40_alpha_input_scale0p25_alpha0p25 | 1.415355 | 3.917034 | 16.505744 | local_ar_20260610 | promote_candidate |
| SE_2 | 1 | qdesn_exal_rhs_ns_exact_chunked | broad_l096_d2_n120x120_a0p4_r0p9_in0p25_seed20260608 | 3.204651 | 6.659843 | 26.418998 | broad20260608 | keep_previous_no_val_gain |
| SE_2 | 2 | qdesn_exal_rhs_ns_exact_chunked | localar_d2_u80_alpha_input_scale0p2_alpha0p5 | 5.360348 | 3.638727 | 13.389260 | local_ar_20260610 | promote_candidate |
| SE_2 | 3 | qdesn_exal_rhs_ns_exact_chunked | localar_d3_u40_alpha_input_scale0p35_alpha0p45 | 3.419850 | 6.293999 | 22.947108 | local_ar_20260610 | promote_candidate |

## Review Rows

| Region | Fold | Candidate | Issue | Val Delta | Test AQL Delta | Test RMSE Delta |
|---|---:|---|---|---:|---:|---:|
| EE | 1 | localar_d2_u60_alpha_input_scale0p2_alpha0p5 | test risk | -0.260760 | 1.867481 | 4.257365 |
| HU | 3 | localar_d2_u40_alpha_input_scale0p25_alpha0p5 | test risk | -0.018953 | 6.808523 | 90.422360 |
| IT_SICI | 1 | localar_d2_u60_alpha_input_scale0p2_alpha0p5 | convergence risk | -0.057398 | -0.032563 | 0.185429 |
| IT_SICI | 3 | localar_d2_u80_rho_input_scale0p25_rho0p75 | test risk | -0.061449 | 0.370929 | 0.703523 |
| NO_4 | 1 | localar_d3_u60_alpha_input_scale0p2_alpha0p25 | test risk | -0.008220 | 0.076200 | 1.441146 |

## Tests And Checks

The closeout helper is covered by
`application/tests/test_pricefm_median_selection_registry.py`.

Fresh checks for this pass:

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/34_closeout_pricefm_median_registry.py \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py

application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_median_selection_registry.py -q
```

Result: `8 passed`.

## Next Step

Use the merged registry as the current local-only median authority for these six
regions and three folds. The next implementation step should prepare quantile
launches from this registry and preserve the information-set labels in every
comparison report.

Before pursuing a broad D4/D5 search, the next modeling question should be
whether local-only performance is enough or whether the adapter should add
PriceFM-style graph-neighbor inputs. That extension would make the comparison
closer to PriceFM's spatial information set while preserving the current
local-only registry as the conservative baseline.
