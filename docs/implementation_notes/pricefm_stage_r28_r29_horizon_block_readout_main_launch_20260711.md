# PriceFM Stage-R28/R29 Horizon-Block Readout Main Launch

Date: 2026-07-11

Scope: PriceFM only. Registry, manuscript, article, and MCMC confirmation remain
blocked until a validation-selected VB candidate beats both the current
authoritative Q-DESN row and cached PriceFM on frozen test audit, then passes
full-quantile and MCMC confirmation gates.

## Starting Evidence

Stage-R26 closed out the Stage-R25 broad horizon-weighted run:

- 200/200 experiments completed.
- 400 method rows were audited.
- 2 rows beat the current authoritative Q-DESN row.
- 0 rows beat cached PriceFM.
- 0 rows beat both references.
- 0 promotion or MCMC-confirmation rows were authorized.

Stage-R27 replayed/calibrated existing prediction artifacts:

- 400 candidate rows were ready.
- 6,400 calibration metric rows were produced.
- Baseline replay matched R25 with max AQL difference `1.7763568394002505e-15`.
- 0 full-surface calibrated rows beat PriceFM.
- 0 validation-selected calibrated rows beat PriceFM.
- Best any calibrated PriceFM gap remained positive: `0.29558872959287785`.

This rules out another plain R25-style capacity/weighting expansion as the
best next step.

## Mechanism Decision

The runner still supports AL/exAL VB fitting only. A YAML-only new likelihood or
loss family would be metadata, not a consumed model change.

The implemented mechanism is instead a deterministic adapter/readout change:
`readout_interaction: horizon_block`. The adapter appends horizon-block
interaction columns to the design matrix, so the existing AL/exAL fitter
consumes a genuinely different readout family without changing the R
likelihood code.

Relevant code paths:

- `application/scripts/pricefm/pricefm_desn_adapter.py`
- `application/scripts/pricefm/pricefm_full_run.py`
- `application/scripts/pricefm/12_prepare_desn_experiment_grid.py`
- `application/scripts/pricefm/153_audit_pricefm_stage_r28_objective_model_family.py`
- `application/scripts/pricefm/154_prepare_pricefm_stage_r29_horizon_block_readout_launch.py`

## Validation

Focused validation passed before launch materialization:

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/pricefm_desn_adapter.py \
  application/scripts/pricefm/pricefm_full_run.py \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  application/scripts/pricefm/153_audit_pricefm_stage_r28_objective_model_family.py \
  application/scripts/pricefm/154_prepare_pricefm_stage_r29_horizon_block_readout_launch.py

application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_desn_adapter.py \
  application/tests/test_pricefm_full_run_orchestrator.py \
  application/tests/test_pricefm_desn_experiment_grid.py \
  application/tests/test_pricefm_stage_r28_objective_model_family.py \
  application/tests/test_pricefm_stage_r29_horizon_block_readout_launch.py -q
```

Result: `45 passed`.

`git diff --check` passed for the touched PriceFM files.

## Stage-R28 Outputs

Output directory:

`application/data_local/pricefm/authoritative/pricefm_stage_r28_objective_model_family_audit_20260711`

Key outputs:

- `pricefm_stage_r28_objective_model_capability_matrix.csv`
- `pricefm_stage_r28_likelihood_family_transfer.csv`
- `pricefm_stage_r28_case_target_queue.csv`
- `pricefm_stage_r28_objective_failure_atlas.csv`
- `pricefm_stage_r28_main_launch_recommendations.csv`
- `pricefm_stage_r28_design_gates.csv`
- `pricefm_stage_r28_objective_model_family_audit_report.md`

Stage-R28 status:

`completed_main_launch_path_ready`

## Stage-R29 Outputs

Output directory:

`application/data_local/pricefm/authoritative/pricefm_stage_r29_horizon_block_readout_launch_prep_20260711`

Launch YAML:

`application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_r30_horizon_block_readout_main_20260711.yaml`

Generated root:

`application/data_local/pricefm/experiment_grids/pricefm_stage_r30_horizon_block_readout_main_20260711`

Run root:

`application/data_local/pricefm/runs/pricefm_stage_r30_horizon_block_readout_main_20260711`

Stage-R29 materialized:

- 20 PriceFM target cases.
- 4 arms per case.
- 80 launch experiments.
- All rows use `readout_interaction = horizon_block`.
- All rows use `horizon_block_size = 24`.
- All rows retain validation-only selection and test-audit-only scoring.
- No registry or manuscript mutation is authorized.
- No binary `.rds/.rda/.RData/.rdata` files were created in R28/R29 prep outputs.

Arm families:

- `hb_local_selected_dynamics`: local target-only parity arm.
- `hb_graph_summary_stable`: graph summary mean/std with stable dynamics.
- `hb_neighbor_spread_memory`: neighbor-spread summary with higher-memory dynamics.
- `hb_graph_summary_high_memory`: graph summary mean/std with high-memory dynamics.

## Launch Command

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_r30_horizon_block_readout_main_20260711.yaml \
  --priorities 0 \
  --experiment-jobs 6 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true \
  --force false
```

## Next Closeout Gate

After Stage-R30 completes, implement Stage-R31 closeout:

1. Select one winner per case by validation AQL only.
2. Audit frozen test metrics against current authoritative Q-DESN and cached PriceFM.
3. Promote no row unless it beats both references on test.
4. If a row passes, run full-quantile confirmation.
5. If full-quantile confirmation passes, initialize MCMC from the selected VB winner.
6. Update registry/manuscript/article only after reproducibility and MCMC gates pass.
