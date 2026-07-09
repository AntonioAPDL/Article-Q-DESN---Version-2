# PriceFM Reservoir Control Propagation Fix, 2026-06-02

## Status

This note records a critical fix before any new PriceFM reservoir-feature
relaunch. The completed `pricefm_median_de_lu_reservoir_20260601` run produced
valid fitted artifacts, but the intended reservoir controls from each full-run
config were not forwarded into the per-cell adapter config.

The issue is now fixed and tested. The existing completed metrics should be
interpreted as pre-fix/default-reservoir artifacts, not as a valid sweep over
`depth`, `alpha`, `rho`, and `input_scale`.

## What Was Wrong

The experiment-grid generator wrote the intended controls into generated
`pricefm_desn_full.adapter` configs. However, `pricefm_full_run.make_cell_config`
only forwarded this minimal adapter subset into `pricefm_desn_smoke.adapter`:

- `feature_map`
- `feature_dim`
- `seed`
- `include_intercept`
- `row_chunk_size`
- `projection_scale`

The adapter builder reads reservoir controls from `pricefm_desn_smoke.adapter`.
Because the controls below were not forwarded, the adapter silently used
defaults:

| control | default used before fix |
|---|---:|
| `depth` | `1` |
| `units` | `feature_dim` |
| `alpha` | `0.7` |
| `rho` | `0.9` |
| `input_scale` | `0.5` |
| `recurrent_sparsity` | `0.05` |
| `bias_scale` | `0.0` |
| `reservoir_activation` | `tanh` |
| `state_output` | `final_layer` |

This explains why many priority-1 cells tied exactly: distinct run IDs were not
actually distinct reservoir-control designs.

## Impact On Existing Results

The existing winner artifacts are still reproducible model fits, but their
actual feature maps are the ones recorded in the frozen `feature_manifest.json`
files, not necessarily the run-ID labels.

For the current best artifact:

| field | run ID implied | frozen manifest actual |
|---|---:|---:|
| run | `res_smoke_d2n80x80_a0p70_r0p90_in0p50_seed20260601` | same artifact path |
| reservoir depth | `2` | `1` |
| reservoir units | `[80, 80]` | `[80]` |
| alpha | `0.70` | `[0.70]` |
| rho | `0.90` | `[0.90]` |
| input scale | `0.50` | `[0.50]` |
| feature dimension | `80` | `80` |

So the current best metric is best described as a **default single-layer
reservoir with 80 stored features**, not a validated two-layer `[80, 80]`
reservoir.

The priority-1 tie set is similarly pre-fix and should not be used to infer
which `alpha`, `rho`, `input_scale`, or depth is best.

## Code Fix

Updated:

```text
application/scripts/pricefm/pricefm_full_run.py
application/scripts/pricefm/pricefm_desn_adapter.py
```

`make_cell_config()` now forwards all reservoir controls from the full config to
the cell adapter config:

- `depth`
- `units`
- `alpha`
- `rho`
- `input_scale`
- `recurrent_sparsity`
- `recurrent_density`
- `bias_scale`
- `reservoir_activation`
- `state_output`

The adapter manifest also records:

```text
reservoir_config_sha256
```

This matters because `alpha` changes the recurrent state recursion even when
the random input/recurrent matrices are unchanged. The existing
`feature_map_matrix_sha256` is still useful, but it is not sufficient by itself
to identify the complete reservoir feature transformation.

## Regression Tests Added

Updated:

```text
application/tests/test_pricefm_desn_adapter.py
application/tests/test_pricefm_full_run_orchestrator.py
application/tests/test_pricefm_desn_experiment_grid.py
```

New checks cover:

- full-run cell configs forward all reservoir controls;
- generated reservoir-grid configs carry controls into cell configs;
- changing `alpha` changes reservoir states even when matrix hashes are equal;
- reservoir config hashes distinguish dynamic-control changes.

## Validation Commands

Compile check:

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/pricefm_desn_adapter.py \
  application/scripts/pricefm/pricefm_full_run.py \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  application/scripts/pricefm/13_run_desn_experiment_grid.py
```

Focused pytest:

```bash
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_desn_adapter.py \
  application/tests/test_pricefm_full_run_orchestrator.py \
  application/tests/test_pricefm_desn_experiment_grid.py \
  application/tests/test_pricefm_full_run_config.py -q
```

Result:

```text
27 passed
```

Regenerated ignored reservoir-grid configs:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_20260601.yaml \
  --write
```

Priority-0 dry-run after the fix:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_20260601.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --resume false \
  --force false \
  --dry-run true
```

The dry-run rewrote the priority-0 cell configs with the intended reservoir
controls. It did not launch model fits.

## Adapter Bridge Smoke

A temporary ignored adapter-only smoke used two deliberately different
priority-1 D2 reservoir specs, with only `2` train origins and horizons
`[1, 2]`.

| spec | depth | units | alpha | rho | input scale | matrix hash prefix | config hash prefix | train X hash prefix |
|---|---:|---:|---:|---:|---:|---|---|---|
| `alpha0p5_rho0p8_input_scale0p25` | `2` | `[240, 240]` | `[0.5, 0.5]` | `[0.8, 0.8]` | `[0.25, 0.25]` | `7aeab4de` | `db8ac9a3` | `5f49729c` |
| `alpha0p9_rho0p97_input_scale0p5` | `2` | `[240, 240]` | `[0.9, 0.9]` | `[0.97, 0.97]` | `[0.5, 0.5]` | `71e4e10d` | `56cf0fb2` | `96ee07ca` |

The reservoir manifests, reservoir config hashes, matrix hashes, and train
design hashes all differ as expected.

Temporary ignored smoke output:

```text
application/data_local/pricefm/tmp/reservoir_control_bridge_20260602
```

## Relaunch Rule

Before any new large reservoir grid:

1. use only configs generated after this fix;
2. require each completed cell report the intended reservoir controls in
   `feature_manifest.json`;
3. require `reservoir_config_sha256` and split `X_sha256` to differ for specs
   that are supposed to differ;
4. treat the old priority-1 reservoir metrics as pre-fix diagnostics only;
5. run a fresh priority-0 smoke, inspect figures, then run the corrected grid.

## Recommended Next Grid

The corrected relaunch should focus around the genuinely promising area but
avoid an uncontrolled explosion:

- one-layer small reservoirs: `[80]`, `[120]`, `[180]`;
- two-layer compact reservoirs: `[40, 40]`, `[80, 80]`, `[120, 120]`;
- `alpha`: `0.50`, `0.70`, `0.90`;
- `rho`: `0.80`, `0.90`, `0.97`;
- `input_scale`: `0.25`, `0.50`, `1.00`;
- retain `L = 96`, RHS_NS `tau0 = 1.0e-3`, no intercept shrinkage, exact
  chunked AL/exAL, and the existing warm-start chain.

Seed robustness should be applied only after the corrected grid identifies a
stable top region.
