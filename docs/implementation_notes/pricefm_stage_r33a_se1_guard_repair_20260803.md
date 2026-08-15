# PriceFM Stage-R33A SE_1 Guard Repair

Date: 2026-08-03

## Decision

Repair only the 24 incomplete `SE_1` fold-3 Stage-R33 experiments. Do not
rerun the 456 successful experiments and do not broaden the scientific search.

The base R33 launcher exited zero, but its experiment ledger records 456
completed rows and 24 failed rows. Every failed model log contains:

```text
horizon_weighting expansion factor 6.5 exceeds max_expansion_factor 6
```

All 24 adapters are complete and reusable, and none has a metric summary. The
failure therefore occurred at the model guard before fitting and does not
constitute evidence against those 24 specifications.

## Minimal Repair Contract

For each of the exact 24 failed IDs, preserve:

- experiment ID and random seed;
- region/fold and data windows;
- feature policy and information set;
- lag window, depth, units, feature dimension, and state output;
- alpha, rho, input scale, tau0, readout, and likelihoods;
- validation-only selection and test-audit roles;
- the original R33 run directory, allowing adapter reuse.

Change only:

```text
training.horizon_weighting.max_expansion_factor: 6 -> 7
```

This raises a resource-safety ceiling enough to admit the already requested
6.5 expansion. It does not change horizon weights, the objective, or any model
hyperparameter.

## Implementation

- Prep script:
  `application/scripts/pricefm/159_prepare_pricefm_stage_r33a_se1_guard_repair.py`
- Focused test:
  `application/tests/test_pricefm_stage_r33a_se1_guard_repair.py`
- Reconciled closeout:
  `application/scripts/pricefm/158_closeout_pricefm_stage_r34_lean_capacity_history.py`
- Closeout test:
  `application/tests/test_pricefm_stage_r34_lean_capacity_history_closeout.py`

The prep script verifies the source grid, manifest, launch ledger, exact error
text, adapter files, absent metrics, target case, and a deep experiment diff.
It refuses to write a launch YAML unless every gate passes.

## Artifact Layout

The authoritative implementation is in the Version-2 repository. The existing
large run artifacts remain in the historical execution clone and are supplied
to the script through absolute paths. This avoids copying approximately 32 GB
of run data or modifying unrelated work.

Repair artifacts use a separate provenance root:

```text
application/data_local/pricefm/authoritative/pricefm_stage_r33a_se1_guard_repair_prep_20260803/
application/data_local/pricefm/experiment_grids/pricefm_stage_r33a_se1_guard_repair_20260803/
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_r33a_se1_guard_repair_20260803.yaml
```

The repair grid points to the original R33 run root. Its launcher ledger is
separate; the original R33 YAML and launch ledger remain immutable.

## Launch Contract

After focused tests and materialization pass, launch from the execution clone:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_r33a_se1_guard_repair_20260803.yaml \
  --priorities 0 \
  --experiment-jobs 16 \
  --cell-jobs 1 \
  --build-windows false \
  --resume true \
  --force false \
  --dry-run false
```

No dry or smoke launch is required because the existing adapters and exact
runner path are reused. Sixteen workers remain bounded below the available
server resources, while each model receives one launcher worker.

## Closeout and Scientific Boundary

R34 may run in health-only mode while R33A is active. Final R34 materialization
requires 480 metric summaries, 960 AL/exAL method rows, exact base/repair ID
reconciliation, and zero exits for both launchers. It then freezes one winner
per region/fold using validation AQL only and audits test AQL against both the
current authoritative Q-DESN result and cached PriceFM.

The partial 456-fit evidence has no PriceFM wins and only sparse current-Q-DESN
wins, so R33A is a completeness repair, not a likely promotion path. Registry,
article, full-quantile, and MCMC actions remain blocked unless a
validation-selected candidate beats both references and passes later
confirmation and reproducibility gates.
