# PriceFM Stage-R25 Post-R24 Broad Launch Prep

Stage-R25 is the first broad PriceFM launch design after Stage-R24 made the
horizon-weighting mechanism real in the model runner.

## Diagnosis

Stage-R22C/R22D completed with no promotable candidates. The run produced
useful evidence, but it did not beat PriceFM: validation-selected candidates
missed PriceFM in every target case, and even the test-oracle view did not
produce a beat-both row.

Stage-R23 explained why a larger repeat of R22C would be wasteful. The
important horizon-weight/loss fields were metadata at launch time, and postfit
calibration was deferred without prediction paths.

Stage-R24 fixed the launch-time mechanism blocker by wiring
`training.horizon_weighting` through the grid prep and runner, using explicit
integer-frequency replication for Q-DESN training rows. It also added a
validation-only postfit calibration materializer for use after prediction
artifacts exist.

## R25 Design

Script:

```bash
application/scripts/pricefm/149_prepare_pricefm_stage_r25_post_r24_broad_launch.py
```

Focused tests:

```bash
application/tests/test_pricefm_stage_r25_post_r24_broad_launch.py
```

Default output directory:

```text
application/data_local/pricefm/authoritative/pricefm_stage_r25_post_r24_broad_launch_prep_20260709
```

Default launch grid:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_r25_post_r24_broad_20260709.yaml
```

Default run tag/root:

```text
pricefm_stage_r25_post_r24_broad_horizon_weighted_20260709
application/data_local/pricefm/runs/pricefm_stage_r25_post_r24_broad_horizon_weighted_20260709
```

The default design covers all 20 Stage-R22D failed PriceFM target cases with
10 case-specific arms each, for 200 median-only launch experiments. Every arm
uses true R24 horizon weighting and remains validation-selection-only.

The arm families are:

- `true_weight_base`;
- `true_weight_light`;
- `true_weight_heavy`;
- `short_lag_weighted`;
- `long_lag_weighted`;
- `larger_units_weighted`;
- `deeper_units_weighted`;
- `concat_block_weighted`;
- `alt_information_set_weighted`;
- `high_memory_low_input_weighted`.

These arms broaden the actual axes that matter for the next expensive run:
`n/units`, `D/depth`, feature dimension, lag window, state output, feature
policy, alpha, rho, input scale, tau0, and horizon-weight multiplier.

## Gates

Stage-R25 keeps these gates locked:

- no same-family Stage-R4/R19 rescue reuse;
- validation-only selection within each case;
- test metrics audit-only after frozen validation selection;
- registry mutation blocked;
- manuscript mutation blocked;
- Stage-R26 closeout required;
- postfit calibration gate required after predictions exist;
- full-quantile confirmation required before any article-facing mutation.

## Launch Command

After the script materializes the grid and tests pass, the actual background
launch command is:

```bash
application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_r25_post_r24_broad_20260709.yaml \
  --priorities 0 \
  --experiment-jobs 6 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true \
  --force false
```

This is not a dry run or smoke run. It is the full Stage-R25 background launch.
