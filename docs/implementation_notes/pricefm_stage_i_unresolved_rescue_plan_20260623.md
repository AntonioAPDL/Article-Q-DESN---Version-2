# PriceFM Stage-I Unresolved Rescue Plan

Date: 2026-06-23

## Objective

Stage I starts from the current authoritative quantile decision registry:

`application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_h_priority0_20260623/authoritative_quantile_decision_registry.csv`

The purpose is to rescue only the rows that still do not have a confirmed local
DESN/Q-DESN paper-quantile win against cached fold-aligned PriceFM Phase-I.
This is not a global retune. It is an unresolved-row rescue layer with separate
provenance and the same strict promotion gates used in Stage H.

## Current Baseline

The Stage-H priority-0 registry contains 42 region/folds:

| decision | rows |
|---|---:|
| `stage_c_confirmed_local_win` | 25 |
| `stage_c_local_close_to_pricefm` | 6 |
| `stage_c_pricefm_fallback` | 11 |

The strict operational policy is:

- use the local model only for `stage_c_confirmed_local_win`;
- use cached PriceFM for fallbacks and close losses unless a later stage
  confirms a local replacement on the full paper-quantile panel.

Under that strict policy, mean original-unit test AQL is approximately `8.3481`
versus `8.9598` for pure cached PriceFM.

## Stage-I Target Rows

Close local losses:

| region | fold | relative gap |
|---|---:|---:|
| `SE_4` | 3 | 0.0118 |
| `LV` | 2 | 0.0214 |
| `HU` | 3 | 0.0361 |
| `LV` | 1 | 0.0401 |
| `SI` | 1 | 0.0451 |
| `PL` | 1 | 0.0475 |

PriceFM fallbacks:

| region | fold | relative gap |
|---|---:|---:|
| `BE` | 3 | 0.0517 |
| `NL` | 3 | 0.0583 |
| `PL` | 3 | 0.0927 |
| `RO` | 1 | 0.0964 |
| `SE_4` | 1 | 0.1013 |
| `RO` | 3 | 0.1096 |
| `AT` | 3 | 0.1320 |
| `FI` | 1 | 0.1406 |
| `LT` | 1 | 0.1594 |
| `SK` | 3 | 0.1736 |
| `HU` | 2 | 0.1860 |

## Why This Scope Is Optimal Now

The current registry already has a large confirmed local block. Launching a
new broad all-row grid would spend most compute on rows that already beat
PriceFM. The remaining weak rows show a clear pattern:

- wins are mostly `graph_khop` (`20/25`);
- nonwins are mostly `target_only` (`11/17`);
- Q-DESN exAL/RHS_NS exact-chunked dominates the best local method list;
- all currently selected rows use `L=96`, so lag should remain a controlled
  perturbation rather than a new global axis;
- RO-1 proved that median improvement alone is not enough, so seven-quantile
  confirmation remains mandatory.

Therefore Stage I uses median-only validation selection as a cheap screen,
then requires seed robustness and paper-quantile comparison before promotion.

## Generated Median Grid

Generator:

`application/scripts/pricefm/60_prepare_pricefm_stage_h_targeted_rescue.py`

The generator now accepts custom stage labels so Stage I can reuse the proven
Stage-H mechanics without mislabeling provenance.

Command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/60_prepare_pricefm_stage_h_targeted_rescue.py \
  --template-grid-config application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml \
  --median-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_h_priority0_seedrob_patched_registry_20260623/patched_selection_registry.csv \
  --authoritative-decision-registry-csv application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_h_priority0_20260623/authoritative_quantile_decision_registry.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_i_unresolved_median_rescue_20260623.yaml \
  --grid-id pricefm_stage_i_unresolved_median_rescue_20260623 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_stage_i_unresolved_median_rescue_20260623 \
  --run-root application/data_local/pricefm/runs/pricefm_stage_i_unresolved_median_rescue_20260623 \
  --summary-dir application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_median_rescue_plan_20260623 \
  --include-close true \
  --include-fallback true \
  --priority0-delta-abs 1.0 \
  --priority1-delta-abs 0.25 \
  --max-variants-priority0 28 \
  --max-variants-priority1 16 \
  --max-variants-priority2 10 \
  --candidate-source stage_i_unresolved_median_rescue_20260623 \
  --stage-name stage_i_unresolved_median_rescue \
  --experiment-id-prefix stagei \
  --target-label stage_i_unresolved_median_rescue_validation \
  --launch-key stage_i_unresolved_median_rescue \
  --summary-prefix stage_i_unresolved_rescue \
  --write true
```

Generated counts:

| quantity | count |
|---|---:|
| Unresolved region/folds | 17 |
| Median experiments | 284 |
| Priority 0 severe fallback experiments | 112 |
| Priority 1 moderate fallback experiments | 112 |
| Priority 2 close-row experiments | 60 |
| Graph-khop experiments | 274 |
| Target-only guardrails | 10 |

## Validation And Launch Discipline

Dry-run command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_i_unresolved_median_rescue_20260623.yaml \
  --priorities 0,1,2 \
  --experiment-jobs 20 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run true
```

The dry-run selected all 284 experiments and produced:

`application/data_local/pricefm/experiment_grids/pricefm_stage_i_unresolved_median_rescue_20260623/launch_status.csv`

Live launch command:

```sh
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

/usr/bin/time -v \
  -o application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_median_rescue_plan_20260623/stage_i_all_launch.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_i_unresolved_median_rescue_20260623.yaml \
  --priorities 0,1,2 \
  --experiment-jobs 20 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run false \
  > application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_median_rescue_plan_20260623/stage_i_all_launch.console.log \
  2>&1
```

## Closeout And Promotion Gates

After the median launch completes:

1. Run graph/local rescue closeout with the Stage-H priority-0 median registry
   as the current median registry.
2. Keep only validation-clean median improvements as seedrob candidates.
3. Run three seedrob seeds for each queued candidate.
4. Patch the median registry only for seed-robust candidates.
5. Promote only patched rows to the seven paper quantiles:
   `0.10,0.25,0.45,0.50,0.55,0.75,0.90`.
6. Compare against cached fold-aligned PriceFM Phase-I.
7. Freeze decisions and merge over
   `pricefm_authoritative_quantile_decisions_stage_h_priority0_20260623`.

No row may become authoritative from median evidence alone.

## Stop Gates

Stop before promotion if:

- any Stage-I median experiment fails;
- any expected `metric_summary.csv` is missing;
- any R binary artifacts remain in the Stage-I run tree;
- graph metadata is missing from graph-khop candidates;
- median selection uses anything other than validation/original/AQL;
- a candidate is not seed-robust across the requested seeds;
- a seven-quantile panel does not beat cached PriceFM;
- the merged strict selected AQL worsens versus the current Stage-H registry.

## Expected Next Decision

If Stage-I produces a small number of seed-robust median candidates, run the
same patch-only seven-quantile confirmation path as Stage H. If Stage-I does
not produce robust candidates, keep the current Stage-H authoritative registry
and move to a different modeling lever rather than widening this grid blindly.
