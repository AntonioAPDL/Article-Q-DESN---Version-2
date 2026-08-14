# PriceFM DE_LU Folds 2-3 Deep Targeted Median Grid

Date: 2026-06-03

## Why This Relaunch Exists

The registry-promoted paper-quantile comparison showed:

- Q-DESN exAL RHS_NS beats the naive baselines on folds 1-3.
- Q-DESN exAL RHS_NS beats local PriceFM Phase-I on fold 1.
- Q-DESN exAL RHS_NS trails local PriceFM Phase-I on fold 2 by a modest AQL gap.
- Q-DESN exAL RHS_NS trails local PriceFM Phase-I on fold 3 by a larger AQL gap.

The first fold-2/3 median-selection grid was intentionally compact. It was good
enough to produce provisional fold-specific specs, but not broad enough to
claim that the fold-2/3 parameter space is well explored.

## Evidence From The Current Results

Fold 2:

- Validation selected `L=72`, `n=120`, `alpha=0.50`, `rho=0.90`, `input_scale=0.50`.
- Test-audit median performance favored `L=96`, `n=80`, `alpha=0.50`, `rho=0.90`, `input_scale=0.50`.
- Lower input scale and compact D2 were not validation winners, but looked competitive enough to revisit.
- Paper-quantile AQL gap versus local PriceFM Phase-I is `+0.2728`, so this fold is plausibly recoverable.

Fold 3:

- Validation and test-audit median both favored `L=96`, `n=80`, `alpha=0.50`, `rho=0.90`, `input_scale=0.50`.
- Compact D2 was the nearest non-anchor neighbor.
- Horizon-group diagnostics show the largest paper-quantile gap at horizons `1-24`, especially h=1, h=6, and h=12.
- Paper-quantile AQL gap versus local PriceFM Phase-I is `+0.9853`, so this fold needs a serious geometry refresh.

## New Grid

Tracked config:

```text
application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml
```

Ignored generated config root:

```text
application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_deep_targeted_20260603
```

Ignored run root:

```text
application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_deep_targeted_20260603
```

## Scope

| item | value |
|---|---|
| region | `DE_LU` |
| folds | `2`, `3` |
| selection quantile | `0.50` |
| selection split/unit/metric | `val` / `original` / `AQL` |
| audit split | `test` |
| model candidates | Q-DESN AL/exAL RHS_NS, Normal-DESN baselines, naive baselines |
| exact chunking | enabled |
| train origins | tail `3000` |
| VB iterations | inherited min `50`, max `100` |
| intercept shrinkage | disabled |
| heavy artifacts | cleaned after successful cells |

## Grid Shape

| priority | role | experiments | scoped cells |
|---:|---|---:|---:|
| 0 | smoke/anchor gate | 6 | 12 |
| 1 | main targeted reservoir search | 162 | 324 |
| 2 | optional diagnostics only | 21 | 42 |

Priority 0 and 1 are the intended relaunch. Priority 2 is defined for later
diagnostics but should not run before inspecting the main targeted search.

## Main Search Axes

The main grid is broad where the evidence says it should be broad:

- `n`: `60`, `80`, `100`, `120`, `160`
- `L`: `48`, `72`, `96`, `128`, `144`
- `alpha`: `0.40`, `0.50`, `0.60`
- `rho`: `0.85`, `0.90`, `0.97`
- `input_scale`: `0.25`, `0.35`, `0.50`, `0.75`
- compact D2: `[40,40]`, `[60,60]`, `[80,80]`
- small `tau0` check around anchors: `1e-4`, `1e-2`
- one seed replicate for anchor neighborhoods: `20260604`

The main grid is deliberately not broad in low-probability directions:

- It does not launch flat-direct diagnostics in the main pass.
- It does not launch random-projection `window_desn_v1` diagnostics in the main pass.
- It does not tune on test metrics.
- It does not expand to more regions before fold 2/3 are understood.

## Commands

Generate configs:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml \
  --write
```

Prelaunch artifact validation:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/14_validate_reservoir_grid_artifacts.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml \
  --priorities 0,1 \
  --write-generated \
  --output-json application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_deep_targeted_20260603/prelaunch_validation.json \
  --output-csv application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_deep_targeted_20260603/prelaunch_validation.csv
```

Dry run:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true \
  --max-experiments 1
```

Smoke launch:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_deep_targeted_20260603/launch_logs/priority0_launch.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml \
  --priorities 0 \
  --experiment-jobs 4 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

Main launch:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_deep_targeted_20260603/launch_logs/priority1_launch.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml \
  --priorities 1 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

Select winners after completion:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml \
  --priorities 0,1 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_deep_targeted_registry_20260603 \
  --regions DE_LU \
  --folds 2,3 \
  --selection-split val \
  --selection-unit original \
  --selection-metric AQL \
  --require-complete true
```

## Stop/Promotion Criteria

Promote the new grid only if:

1. priority 0 and 1 complete without failed cells;
2. exact chunking gates pass for selected specs;
3. validation selection improves or stabilizes fold 2/3 median AQL;
4. test audit does not expose a large validation/test inversion;
5. the selected specs beat naive baselines and improve over the previous fold-specific registry;
6. only compact snapshots and docs are committed.

After winner selection, regenerate the seven paper-quantile promotion grid and
repeat the fold 1-3 PriceFM comparison.
