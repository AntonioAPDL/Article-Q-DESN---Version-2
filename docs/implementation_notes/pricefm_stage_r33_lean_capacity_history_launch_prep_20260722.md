# PriceFM Stage-R33 Lean Capacity/History Launch Prep

Date: 2026-07-22

## Scope

Stage-R33 prepares a launch-ready, non-launched PriceFM DESN grid for the same
20 region/fold cases targeted by the Stage-R29/Stage-R30 horizon-block work.
It replaces the stopped Stage-R32 same-design queue with a leaner
memory-normalized design.

This stage does not invoke the launcher, fit models, mutate the PriceFM
registry, update manuscript or article files, start MCMC, or touch non-PriceFM
work.

## Frozen Design

The user-authorized prep axes are:

| axis | value |
|---|---|
| depth `D` | `2, 3` |
| units per layer `n` | `48, 64, 96` |
| lag window `m` | `96, 100` |
| readout | `final_layer` |
| `tau0` | `1e-4, 5e-4` |
| `alpha` | `0.2` |
| `rho` | `0.95` |
| `input_scale` | `0.2` |

The design keeps horizon-block readout and implemented horizon weighting from
the R29/R30 path, but removes concat-layer readout and the large R32
`n=200/300`, `D=4`, `m=300/500` axes.

## Inputs

The prep script reads:

- Stage-R29 case plan:
  `application/data_local/pricefm/authoritative/pricefm_stage_r29_horizon_block_readout_launch_prep_20260711/pricefm_stage_r29_case_plan.csv`
- Stage-R29 gates:
  `application/data_local/pricefm/authoritative/pricefm_stage_r29_horizon_block_readout_launch_prep_20260711/pricefm_stage_r29_launch_prep_gates.csv`
- Stage-R29 launch manifest:
  `application/data_local/pricefm/authoritative/pricefm_stage_r29_horizon_block_readout_launch_prep_20260711/pricefm_stage_r29_stage_r30_launch_manifest.csv`
- Stage-R32 partial closeout:
  `application/data_local/pricefm/authoritative/pricefm_stage_r32_partial_stop_closeout_20260721`
- Template grid:
  `application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml`

The Stage-R32 partial closeout is used as evidence that the old large design
should not be resumed. The Stage-R29 case plan remains the target-set source.

## Outputs

Prep script:

```text
application/scripts/pricefm/157_prepare_pricefm_stage_r33_lean_capacity_history_launch.py
```

Focused tests:

```text
application/tests/test_pricefm_stage_r33_lean_capacity_history_launch.py
```

Authoritative prep output directory:

```text
application/data_local/pricefm/authoritative/pricefm_stage_r33_lean_capacity_history_launch_prep_20260722
```

Launch-ready grid YAML:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_r33_lean_capacity_history_20260722.yaml
```

Generated-config root, if materialized with the non-launching grid preparer:

```text
application/data_local/pricefm/experiment_grids/pricefm_stage_r33_lean_capacity_history_20260722
```

Future run root:

```text
application/data_local/pricefm/runs/pricefm_stage_r33_lean_capacity_history_20260722
```

Expected launch-manifest size:

- 20 cases
- 24 arms per case
- 480 launch experiments
- median quantile only
- AL and exact-chunked AL fit paths during the later real launch

## Gates

The prep gate requires:

- all Stage-R29 launch-prep gates pass;
- Stage-R32 partial closeout recommends a lean redesign;
- Stage-R32 same-design relaunch remains blocked;
- exactly `D={2,3}`;
- exactly `n={48,64,96}`;
- exactly `m={96,100}`;
- exactly `tau0={1e-4,5e-4}`;
- `alpha=0.2`, `rho=0.95`, `input_scale=0.2`;
- final-layer-only readout;
- horizon-block readout and implemented horizon weighting retained;
- validation-only selection and test-audit-only reporting;
- no registry/manuscript mutation;
- prep does not invoke the launcher;
- launch remains unauthorized until an explicit user launch request.

## Future Launch Command

The launch command is prepared for a later explicit user request:

```bash
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_r33_lean_capacity_history_20260722.yaml --priorities 0 --experiment-jobs 16 --cell-jobs 1 --build-windows true --dry-run false --resume true --force false
```

This command is not run by the prep stage.

## Validation

Validated with:

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/157_prepare_pricefm_stage_r33_lean_capacity_history_launch.py \
  application/tests/test_pricefm_stage_r33_lean_capacity_history_launch.py

application/data_local/pricefm/venv/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r33_lean_capacity_history_launch.py

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/157_prepare_pricefm_stage_r33_lean_capacity_history_launch.py \
  --write-grid true

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_r33_lean_capacity_history_20260722.yaml \
  --write
```

Results:

- focused tests passed: `2 passed`
- prep manifest rows: `480`
- launch-grid experiments: `480`
- generated config manifest rows: `480`
- generated data configs: `480`
- generated full configs: `480`
- all prep gates passed
- launch authorization remains `false`
- launcher invocation remains `false`
- no Stage-R33 run directories were created
- no `.rds/.rda/.RData/.rdata` artifacts were created by prep/materialization

## Future Closeout Gate

A future Stage-R34 closeout must select candidates by validation AQL only within
each region/fold case. Test metrics are audit-only after frozen validation
selection. A candidate cannot mutate the registry, article, manuscript, or MCMC
queue unless it beats both:

- the current authoritative Q-DESN registry result; and
- cached PriceFM.

Full-quantile confirmation, reproducibility/hash-manifest checks, and MCMC
confirmation remain separate blocked gates.
