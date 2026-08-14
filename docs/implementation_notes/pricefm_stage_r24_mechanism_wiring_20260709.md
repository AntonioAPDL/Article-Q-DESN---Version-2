# PriceFM Stage-R24 Mechanism Wiring

Stage-R24 implements the mechanism support required before a broad expensive
PriceFM search should be launched. It follows the Stage-R23 finding that
Stage-R22C searched real reservoir/information-set axes, but did not actually
consume the horizon-weighted loss or postfit-calibration fields.

## What Changed

### Horizon Weighting

`application/scripts/pricefm/12_prepare_desn_experiment_grid.py` now supports
explicit experiment-level `training.horizon_weighting` propagation into
generated full configs.

`application/scripts/pricefm/08_run_desn_model_smoke.R` now reads that training
block and supports:

- `mode: integer_frequency_replication`;
- horizon-group or horizon-list focus;
- multiplier-to-integer-frequency conversion, with an expansion guard;
- Q-DESN-only application by default via `apply_to: ["qdesn"]`;
- `training_weight_summary.csv` and `run_manifest.json` audit fields.

This is intentionally explicit. The local `exal_ldvb_engine` does not expose
native arbitrary row weights, so Stage-R24 does not pretend the package accepts
silent fractional weights. Fractional multipliers such as `2.5` are represented
by deterministic integer frequency ratios, for example base frequency `2` and
focused frequency `5`.

### Likelihood Selection

`08_run_desn_model_smoke.R` now honors `qdesn_vb$likelihoods`. Previously the
runner fit both AL and exAL unconditionally even when the grid carried a
likelihood list. This matters for expensive launches because it avoids fitting
unwanted likelihood families.

### Postfit Calibration

New script:

```bash
application/scripts/pricefm/148_materialize_pricefm_stage_r24_postfit_calibration.py
```

It implements a reusable read-only postfit calibration path:

- consumes a candidate manifest with existing prediction paths;
- estimates parameters on validation rows only;
- supports `horizon_block_quantile_shift_on_validation`;
- supports `horizon_block_affine_shift_scale_on_validation`;
- applies calibrated predictions to validation/test;
- writes scaled/original metrics when scalers are available;
- writes no launch YAML and fits no models.

The current default Stage-R22C deferred rows still have blank existing
prediction paths, so the default materialization correctly produces readiness
outputs with zero ready rows. Future expensive runs can feed this materializer
prediction artifacts after fitting.

## Outputs

Default R24 output directory:

```text
application/data_local/pricefm/authoritative/pricefm_stage_r24_postfit_calibration_materialized_20260709
```

Key outputs:

- `pricefm_stage_r24_postfit_readiness.csv`
- `pricefm_stage_r24_postfit_calibration_params.csv`
- `pricefm_stage_r24_postfit_materialized_predictions.csv`
- `pricefm_stage_r24_postfit_metric_summary.csv`
- `pricefm_stage_r24_postfit_metric_by_horizon_group.csv`
- `pricefm_stage_r24_postfit_candidate_gate.csv`
- `pricefm_stage_r24_no_launch_gates.csv`
- `source_manifest.csv`
- `summary.json`
- `pricefm_stage_r24_postfit_calibration_report.md`

## Validation

Commands run:

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/147_audit_pricefm_stage_r23_mechanism_capability.py \
  application/scripts/pricefm/148_materialize_pricefm_stage_r24_postfit_calibration.py

application/data_local/pricefm/venv/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r23_mechanism_capability.py \
  application/tests/test_pricefm_stage_r24_mechanism_wiring.py

Rscript -e "invisible(parse('application/scripts/pricefm/08_run_desn_model_smoke.R')); cat('R parse ok\n')"

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/148_materialize_pricefm_stage_r24_postfit_calibration.py \
  --force true
```

## Current Result

The default R24 postfit materialization completed with:

- candidate rows: `30`;
- ready rows: `0`;
- blocked rows: `30`;
- calibration parameter rows: `0`;
- materialized prediction rows: `0`;
- launches models: `false`;
- fits models: `false`;
- writes launch YAML: `false`.

The blocking condition is expected: the Stage-R22C deferred postfit rows do not
carry existing prediction/metric artifact paths. This does not block the
expensive path; it means postfit calibration should be applied after future
expensive runs produce prediction artifacts or after a separate manifest maps
existing prediction artifacts into the calibration runner.

## Next Gate

Before broad expensive launch prep:

1. Prepare a Stage-R25 launch design that explicitly sets
   `training.horizon_weighting.enabled: true` for horizon-weighted arms.
2. Bound reservoir axes per case, including `n`, `D/depth`, feature dimension,
   lag window, alpha, rho, input scale, tau0, feature policy, and quantile
   scope.
3. Keep postfit calibration as a closeout/materialization step after prediction
   artifacts exist.
4. Keep registry and manuscript mutation blocked until validation-selected
   candidates beat both current Q-DESN and PriceFM on frozen test audit.
