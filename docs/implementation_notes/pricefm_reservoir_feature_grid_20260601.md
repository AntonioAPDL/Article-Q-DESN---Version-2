# PriceFM Reservoir Feature Grid

Date: 2026-06-01

## Purpose

The current authoritative PriceFM median DE_LU fold-1 model uses
`window_desn_v1`, a static Gaussian random projection of the lag/lead/horizon
feature vector. The next screen needs a true recurrent feature map before it is
meaningful to tune leakage, spectral radius, and depth.

This stage adds the recurrent feature map and the launch-ready grid plumbing,
but it does not launch the full reservoir grid.

## New Feature Map

`window_reservoir_v1` lives in:

- `application/scripts/pricefm/pricefm_desn_adapter.py`

It computes one recurrent state per forecast origin by scanning the lag window
through deterministic sparse recurrent layers. The readout row then appends:

- final-layer reservoir state;
- horizon-specific lead covariates;
- scaled/sinusoidal/one-hot horizon features;
- optional intercept.

Supported controls:

- `depth`
- `units`
- `alpha`
- `rho`
- `input_scale`
- `recurrent_sparsity`
- `reservoir_activation: tanh`
- `state_output: final_layer`
- `seed`

The recurrent matrices are deterministic from the seed and are recorded by a
feature-map SHA-256 hash. Existing `flat_direct` and `window_desn_v1` behavior is
unchanged.

## Artifact Hygiene

Full-run configs may now include an `artifact_hygiene` block. After a successful
cell summary, the orchestrator can remove reproducible bulky intermediates such
as adapter `X_*.csv` and model `*.rds` / `*.rda` / `*.RData`, while preserving
manifests, row/y metadata, metrics, predictions, reports, figures, and logs.

The current authoritative winner is not touched by this stage.

## New Grid

Tracked config:

- `application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_20260601.yaml`

Generated ignored outputs:

- `application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_reservoir_20260601/`
- `application/data_local/pricefm/runs/pricefm_median_de_lu_reservoir_20260601/`

The grid expands to 79 concrete experiments:

- priority 0: 2 smoke cells;
- priority 1: 65 main-screen cells;
- priority 2: 12 high-capacity / seed-robustness cells.

## Validation

Commands run:

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/pricefm_desn_adapter.py \
  application/scripts/pricefm/pricefm_full_run.py \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  application/scripts/pricefm/13_run_desn_experiment_grid.py

application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_desn_adapter.py \
  application/tests/test_pricefm_full_run_orchestrator.py \
  application/tests/test_pricefm_desn_experiment_grid.py \
  application/tests/test_pricefm_full_run_config.py -q

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_20260601.yaml \
  --write

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_20260601.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true
```

Results:

- compile check passed;
- focused pytest suite: 25 passed;
- grid generation wrote 79 concrete ignored configs;
- priority-0 launch dry-run selected the two smoke cells;
- one real-data priority-0 D=1 reservoir adapter build completed successfully
  for DE_LU fold 1, all horizons, tau 0.50.

The adapter smoke generated temporary ignored files under the run directory.
They were removed after the check so a later `resume=true` launch will rebuild
the adapter cleanly instead of reusing a partial validation artifact.

## Launch Gate

The next step is a real priority-0 smoke launch. Do not launch priority 1 until
both smoke cells complete and the model summaries/figures look sane.

## 2026-06-02 Control Propagation Fix

The first completed reservoir grid exposed a full-run-to-cell propagation bug:
reservoir controls were written into generated full configs but were not passed
into the per-cell adapter configs. This has been fixed and documented in:

```text
docs/implementation_notes/pricefm_reservoir_control_propagation_fix_20260602.md
```

Any relaunch must use regenerated configs after that fix. Pre-fix priority-1
metrics should not be used to infer optimal `depth`, `alpha`, `rho`, or
`input_scale`.

```bash
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_20260601.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```
