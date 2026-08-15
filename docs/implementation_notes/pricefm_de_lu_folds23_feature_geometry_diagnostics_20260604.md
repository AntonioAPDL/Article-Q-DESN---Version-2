# PriceFM DE_LU Fold 2/3 Feature-Geometry Diagnostics

Date: 2026-06-04

## Scope

This note records the first no-fit diagnostic stage after the completed
`DE_LU` fold 2/3 deep targeted median grid. No models were refit. The scripts
reuse completed adapter/model artifacts to diagnose why the previous
authoritative fold-specific median registry remains stronger than the new
P0/P1/P2 deep-grid candidates.

Tracked scripts added:

```text
application/scripts/pricefm/23_audit_desn_feature_geometry.py
application/scripts/pricefm/24_select_median_horizon_blocks.py
```

Focused tests added:

```text
application/tests/test_pricefm_feature_geometry_and_horizon_blocks.py
```

Local ignored output paths:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_feature_geometry_audit_20260604/
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_horizon_block_selection_20260604/
```

## Commands

Feature-geometry audit:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/23_audit_desn_feature_geometry.py \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_feature_geometry_audit_20260604 \
  --max-rows-per-split 3000 \
  --splits train,val,test \
  --compute-rank true \
  --adapter prev_f2=application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_selection_20260602/rf_p0_f23_d1n120_l072_a0p50_r0p90_in0p50_seed20260601/cells/region=DE_LU/fold=2/adapter \
  --adapter prev_f3=application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_selection_20260602/rf_p0_f23_d1n080_l096_a0p50_r0p90_in0p50_seed20260601/cells/region=DE_LU/fold=3/adapter \
  --adapter new_f2=application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_deep_targeted_20260603/rfdeep_p1_input_lag_window96_units120_rho0p9_input_scale0p25/cells/region=DE_LU/fold=2/adapter \
  --adapter new_f3=application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_deep_targeted_20260603/rfdeep_p1_input_lag_window96_units80_rho0p97_input_scale0p35/cells/region=DE_LU/fold=3/adapter \
  --adapter p2_window_f2=application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_deep_targeted_20260603/rfdeep_p2_windowdesn_lag_window72_feature_dim480_projection_scale0p35/cells/region=DE_LU/fold=2/adapter \
  --adapter p2_window_f3=application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_deep_targeted_20260603/rfdeep_p2_windowdesn_lag_window96_feature_dim480_projection_scale0p5/cells/region=DE_LU/fold=3/adapter \
  --adapter p2_flat_f2=application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_deep_targeted_20260603/rfdeep_p2_flat_lag_window48/cells/region=DE_LU/fold=2/adapter \
  --adapter p2_flat_f3=application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_deep_targeted_20260603/rfdeep_p2_flat_lag_window48/cells/region=DE_LU/fold=3/adapter
```

Horizon-block selector:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/24_select_median_horizon_blocks.py \
  --candidate-registry-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_p2_registry_20260603 \
  --baseline-registry-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_selection_registry_20260602 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_horizon_block_selection_20260604 \
  --region DE_LU \
  --folds 2,3 \
  --selection-split val \
  --audit-split test \
  --unit original \
  --metric AQL \
  --horizon-blocks 1-24,25-48,49-72,73-96
```

## Feature-Geometry Results

The P2 feature maps are not failing because of ordinary saturation alone. The
more useful signals are effective-rank loss, feature drift, and poor
conditioning for flat features.

Validation-split geometry:

| label | feature map | features | effective rank | near-zero var | high-corr pairs | condition number |
|---|---|---:|---:|---:|---:|---:|
| `prev_f2` | `window_reservoir_v1` | 223 | 97.873 | 0 | 107 | 2.14e16 |
| `prev_f3` | `window_reservoir_v1` | 183 | 99.543 | 0 | 17 | 1.32e16 |
| `new_f2` | `window_reservoir_v1` | 223 | 95.258 | 0 | 52 | 1.82e16 |
| `new_f3` | `window_reservoir_v1` | 183 | 101.489 | 0 | 2 | 1.34e16 |
| `p2_window_f2` | `window_desn_v1` | 481 | 56.846 | 0 | 0 | 6.58e3 |
| `p2_window_f3` | `window_desn_v1` | 481 | 81.944 | 0 | 0 | 2.73e3 |
| `p2_flat_f2` | `flat_direct` | 580 | 102.499 | 48 | 2038 | 1.54e20 |
| `p2_flat_f3` | `flat_direct` | 580 | 108.637 | 36 | 2012 | 3.29e20 |

Train-to-test drift:

| label | mean standardized shift | median scale ratio | max scale ratio |
|---|---:|---:|---:|
| `prev_f2` | 0.188 | 0.744 | 1.454 |
| `prev_f3` | 0.215 | 0.903 | 1.330 |
| `new_f2` | 0.224 | 0.602 | 1.501 |
| `new_f3` | 0.176 | 0.906 | 1.467 |
| `p2_window_f2` | 0.687 | 0.552 | 1.099 |
| `p2_window_f3` | 0.297 | 0.819 | 1.159 |
| `p2_flat_f2` | 0.562 | 0.646 | 3.458 |
| `p2_flat_f3` | 0.239 | 0.867 | 1.467 |

Activation summary:

- `new_f2` lowers reservoir pre-activation scale a lot relative to `prev_f2`
  (`sd` about `0.342` versus `0.684` on train), which explains why it can help
  short horizons but also changes the representation enough to hurt mid-horizon
  behavior.
- `window_desn_v1` has low saturation but substantially lower effective rank,
  especially fold 2, and worse drift. The problem is not simply tanh saturation.
- `flat_direct` is severely collinear and poorly conditioned. The direct flat
  result should not be used as an upper bound until raw feature conditioning is
  addressed.

Diagnostic figures:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_feature_geometry_audit_20260604/figures/validation_effective_rank.png
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_feature_geometry_audit_20260604/figures/test_feature_drift.png
```

## Horizon-Block Results

The horizon-block selector uses validation AQL only. Test is audit-only.

Validation-selected block winners:

| Fold | Horizon block | Selected experiment | Method | Val AQL |
|---:|---|---|---|---:|
| 2 | 1-24 | `rfdeep_p1_d1core_lag_window72_units60_alpha0p5_rho0p85` | AL RHS_NS | 3.204060 |
| 2 | 25-48 | `rfdeep_p1_d1core_lag_window96_units160_alpha0p6_rho0p85` | exAL RHS_NS | 6.900606 |
| 2 | 49-72 | `rfdeep_p1_d1core_lag_window96_units160_alpha0p4_rho0p85` | exAL RHS_NS | 7.821936 |
| 2 | 73-96 | `rfdeep_p1_d1core_lag_window72_units160_alpha0p4_rho0p85` | exAL RHS_NS | 6.479801 |
| 3 | 1-24 | `rfdeep_p1_d1core_lag_window96_units80_alpha0p4_rho0p97` | exAL RHS_NS | 3.263970 |
| 3 | 25-48 | `rfdeep_p1_input_lag_window72_units80_rho0p85_input_scale0p35` | AL RHS_NS | 7.925711 |
| 3 | 49-72 | `rfdeep_p0_d2_l096_n080x080_a0p50_r0p90_in0p50_seed20260603` | exAL RHS_NS | 8.511188 |
| 3 | 73-96 | `rfdeep_p1_d1core_lag_window96_units160_alpha0p5_rho0p85` | exAL RHS_NS | 7.007010 |

Composite AQL deltas versus retained global median:

| Fold | Split role | Retained AQL | Horizon-block AQL | Delta |
|---:|---|---:|---:|---:|
| 2 | validation | 6.181033 | 6.101601 | -0.079433 |
| 2 | test audit | 7.017320 | 6.925543 | -0.091776 |
| 3 | validation | 6.765381 | 6.676970 | -0.088411 |
| 3 | test audit | 8.559254 | 8.586891 | 0.027637 |

Interpretation:

- Fold 2 horizon-block selection is promising: it improves validation and test
  audit.
- Fold 3 horizon-block selection improves validation but slightly worsens test
  audit. Do not promote it yet.
- The block winners mostly come from D1 reservoir candidates, not P2 flat/window
  candidates. That supports staying near recurrent reservoir features.

Diagnostic figures:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_horizon_block_selection_20260604/figures/validation_selected_horizon_block_aql.png
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_horizon_block_selection_20260604/figures/audit_composite_aql_delta.png
```

## Decision

Do not promote a new fold 2/3 median registry yet.

Do not launch another broad P2 projection or flat-direct grid.

The best next implementation stage is a small, controlled horizon-block
promotion prototype plus seed robustness around the horizon-block winners and
the retained winners. The prototype must remain validation-selected and should
not use test metrics to choose blocks.

## Recommended Next Stage

1. Implement a registry-level horizon-block promotion materializer.
   - It should combine validation-selected horizon specialists into one
     prediction object.
   - It must record the selected experiment/method per block.
   - It must refuse missing or duplicated block coverage.
   - It should support paper-quantile promotion only after median validation
     gates pass.

2. Run seed robustness for:
   - retained fold 2/3 global winners;
   - fold 2 horizon-block winners;
   - fold 3 horizon-block winners, with special attention to blocks `49-72` and
     `73-96`.

3. Only after that, implement a new feature-map family if needed:
   - multi-scale lag summaries;
   - calendar/response-time features;
   - horizon-group interactions.

The current diagnostics say the problem is representation and horizon structure,
not a need for larger random windows.

## Follow-Up Stage

The horizon-block materializer, seed-robustness grid config, and seed-summary
utility were implemented after this diagnostic pass. See:

```text
docs/implementation_notes/pricefm_de_lu_folds23_horizon_block_materialization_seed_stage_20260604.md
```

## Validation

Focused tests:

```text
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_feature_geometry_and_horizon_blocks.py -q
```

Result:

```text
5 passed
```

Compile checks:

```text
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/23_audit_desn_feature_geometry.py \
  application/scripts/pricefm/24_select_median_horizon_blocks.py
```

Result: passed.
