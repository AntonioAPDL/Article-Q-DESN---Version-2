# PriceFM Stage-R32 Large-Capacity/History Launch Prep

Date: 2026-07-14

Stage-R32 prepares an explicit PriceFM DESN capacity/history test for the same
20 region/fold cases targeted by the active Stage-R30 horizon-block readout
launch.  It does not invoke the launcher, fit models, mutate registries, update
manuscript/article files, or touch non-PriceFM work.

## Motivation

Stage-R30 is a readout/mechanism experiment.  Its materialized configs use
single-layer reservoirs only:

- `D = 1`
- `n in {64, 96, 128}`
- `m = lag_window <= 192`

The Stage-R32 hypothesis is that the remaining PriceFM failures may require
substantially more reservoir capacity and longer history:

- `D in {3, 4}`
- same-width layer units with `n in {100, 200, 300}`
- `m = lag_window in {300, 500}`

## Prepared Grid

Script:

```text
application/scripts/pricefm/155_prepare_pricefm_stage_r32_large_capacity_history_launch.py
```

Focused tests:

```text
application/tests/test_pricefm_stage_r32_large_capacity_history_launch.py
```

Authoritative prep outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_r32_large_capacity_history_launch_prep_20260714
```

Launch-ready grid YAML:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_r32_large_capacity_history_20260714.yaml
```

Grid id:

```text
pricefm_stage_r32_large_capacity_history_20260714
```

The materialized grid has:

- 20 cases
- 24 arms per case
- 480 experiments total
- median quantile only
- validation-only selection
- test metrics audit-only
- no registry/manuscript mutation
- no MCMC or article mutation

## Dynamics Profiles

The current Stage-R30 launch uses:

- `alpha in {0.25, 0.30, 0.35, 0.40, 0.45, 0.50}`
- `tau0 in {0.0005, 0.001}`

Stage-R32 makes alpha/tau0 explicit with two profiles:

| profile | state_output | alpha | rho | input_scale | tau0 |
|---|---|---:|---:|---:|---:|
| `balanced_final_layer` | `final_layer` | 0.40 | 0.86 | 0.30 | 0.001 |
| `slow_memory_concat_regularized` | `concat_layers` | 0.25 | 0.95 | 0.20 | 0.0005 |

## Launch Command

Prepared command for later explicit launch:

```bash
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_r32_large_capacity_history_20260714.yaml --priorities 0 --experiment-jobs 2 --cell-jobs 1 --build-windows true --dry-run false --resume true --force false
```

This command is an actual expensive launch command.  It should not be invoked
while another PriceFM launch is consuming the same resources unless explicitly
authorized.

## Validation

Validated with:

```bash
application/data_local/pricefm/venv/bin/python -m py_compile application/scripts/pricefm/155_prepare_pricefm_stage_r32_large_capacity_history_launch.py application/tests/test_pricefm_stage_r32_large_capacity_history_launch.py
application/data_local/pricefm/venv/bin/python -m pytest -q application/tests/test_pricefm_stage_r32_large_capacity_history_launch.py
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/155_prepare_pricefm_stage_r32_large_capacity_history_launch.py --write-grid true
```

Results:

- focused tests passed: `2 passed`
- 480 launch rows materialized
- all launch-prep gates passed
- no `.rds/.rda/.RData/.rdata` artifacts created
- prep did not invoke the launcher

## Promotion Gate

Future Stage-R33 closeout must select winners by validation only, then audit
test performance against both current authoritative Q-DESN and cached PriceFM.
No registry, article, manuscript, figure, table, or MCMC mutation is authorized
unless a candidate beats both baselines and passes full-quantile plus MCMC
confirmation gates.
