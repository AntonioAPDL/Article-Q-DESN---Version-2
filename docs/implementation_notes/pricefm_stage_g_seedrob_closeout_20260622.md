# PriceFM Stage-G Seed Robustness Closeout

Date: 2026-06-22

## Scope

This note closes the Stage-G median rescue seed-robustness pass. The goal was to
take the eight priority-0 rescue candidates from the graph/local Stage-G recovery
closeout, rerun each candidate under three independent DESN seeds, and patch the
median selection registry only for candidates that remain consistently better
than the current authoritative median registry.

This pass does not launch seven-quantile promotion runs. It prepares the
seed-stable median registry needed for that next stage.

## Inputs

- Source grid config:
  `application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_targeted_median_rescue_20260621.yaml`
- Seed plan:
  `application/data_local/pricefm/authoritative/pricefm_stage_g_targeted_median_rescue_closeout_20260621/robustness_seed_plan.csv`
- Current registry:
  `application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_registry_20260621/patched_selection_registry.csv`

## Generated Ignored Outputs

- Seed grid config:
  `application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_seedrob_20260622.yaml`
- Generated grid:
  `application/data_local/pricefm/experiment_grids/pricefm_stage_g_seedrob_20260622/`
- Run root:
  `application/data_local/pricefm/runs/pricefm_stage_g_seedrob_20260622/`
- Plan summary:
  `application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_plan_20260622/`
- Robustness summary:
  `application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_summary_20260622/`
- Patched registry:
  `application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/`

These outputs are local/ignored artifacts and should not be committed wholesale.

## Commands

Prepare seed grid:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/43_prepare_pricefm_graph_local_rescue_seed_grid.py \
  --source-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_targeted_median_rescue_20260621.yaml \
  --seed-plan-csv application/data_local/pricefm/authoritative/pricefm_stage_g_targeted_median_rescue_closeout_20260621/robustness_seed_plan.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_seedrob_20260622.yaml \
  --grid-id pricefm_stage_g_targeted_median_rescue_seedrob_20260622 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_stage_g_seedrob_20260622 \
  --run-root application/data_local/pricefm/runs/pricefm_stage_g_seedrob_20260622 \
  --summary-output application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_plan_20260622/prepare_summary.json \
  --priority 0
```

Dry run:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_seedrob_20260622.yaml \
  --priorities 0 \
  --experiment-jobs 8 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run true
```

Launch:

```sh
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

/usr/bin/time -v \
  -o application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_plan_20260622/seedrob_launch.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_g_seedrob_20260622.yaml \
  --priorities 0 \
  --experiment-jobs 8 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run false
```

Summarize:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/44_summarize_pricefm_graph_local_rescue_seedrob.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_stage_g_seedrob_20260622/manifest.csv \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_registry_20260621/patched_selection_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_summary_20260622 \
  --split-select val \
  --split-audit test \
  --unit original
```

Patch registry:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/45_patch_pricefm_median_registry_from_seedrob.py \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_registry_20260621/patched_selection_registry.csv \
  --seedrob-decisions-csv application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_summary_20260622/seedrob_decisions.csv \
  --promotion-ready-csv application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_summary_20260622/promotion_ready_queue.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622 \
  --candidate-source graph_local_rescue_seedrob_20260622
```

## Launch Validation

- Manifest rows: 24
- Candidate groups: 8
- Seeds per group: 3
- Window builds: 8/8 completed
- Experiments: 24/24 completed
- Metric summaries: 24/24 present
- Reports: 24/24 present
- Prediction files: 24/24 present
- Repo snapshots: 24/24 present
- Missing metric files: 0
- Launch wall time: 54:17.37
- Launch max RSS: 1,428,844 KB
- Launch exit status: 0

No seed-robustness worker process remained after launch closeout.

## Seed-Robustness Gate

A candidate was promotion-ready only if:

- validation win rate was 1.0 across the three seed repeats;
- mean test AQL delta versus current was at most 0.0;
- worst single-seed relative test deterioration was at most 0.05.

Negative deltas mean lower AQL than the current registry entry.

## Candidate Decisions

| region | fold | source candidate | validation wins | test wins | mean val delta | worst val delta | mean test delta | worst test delta | decision |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| DK_1 | 3 | `stageg_dk1_f3_graphd1_input_lo` | 3/3 | 3/3 | -4.108 | -4.052 | -2.376 | -2.326 | promote |
| DK_2 | 1 | `stageg_dk2_f1_graphd1_d1_units_hi` | 3/3 | 3/3 | -2.917 | -2.788 | -3.533 | -2.919 | promote |
| DK_2 | 2 | `stageg_dk2_f2_graphd1_d3_compact` | 3/3 | 3/3 | -3.883 | -3.758 | -4.003 | -3.899 | promote |
| EE | 1 | `stageg_ee_f1_graphd2_base` | 2/3 | 3/3 | -2.334 | 0.194 | -5.884 | -5.287 | hold |
| EE | 2 | `stageg_ee_f2_graphd2_alpha_lo` | 3/3 | 3/3 | -3.195 | -2.877 | -2.886 | -2.717 | promote |
| HU | 2 | `stageg_hu_f2_graphd1_d3_compact` | 3/3 | 3/3 | -0.367 | -0.273 | -1.017 | -0.547 | promote |
| LT | 1 | `stageg_lt_f1_graphd1_alpha_hi` | 2/3 | 3/3 | -0.246 | 0.283 | -0.639 | -0.477 | hold |
| LT | 2 | `stageg_lt_f2_graphd1_input_lo` | 3/3 | 3/3 | -0.745 | -0.461 | -2.948 | -2.679 | promote |

The two held candidates, EE fold 1 and LT fold 1, improved test AQL for every
seed but failed the stricter validation win-rate gate because one seed was worse
than the current registry on validation. They should not be promoted without a
separate policy decision.

## Patched Registry

The patch step wrote:

- `application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/patched_selection_registry.csv`
- `application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/patch_rows_registry.csv`

The patched registry keeps 42 rows and replaces six region/fold median entries:

| region | fold | selected experiment | method | validation AQL | test AQL |
| --- | ---: | --- | --- | ---: | ---: |
| DK_1 | 3 | `stageg_dk1_f3_graphd1_input_lo_seedrob20260617` | `qdesn_al_rhs_ns_exact_chunked` | 7.024 | 8.802 |
| DK_2 | 1 | `stageg_dk2_f1_graphd1_d1_units_hi_seedrob20260616` | `qdesn_al_rhs_ns_exact_chunked` | 9.077 | 7.786 |
| DK_2 | 2 | `stageg_dk2_f2_graphd1_d3_compact_seedrob20260616` | `qdesn_exal_rhs_ns_exact_chunked` | 7.525 | 7.980 |
| EE | 2 | `stageg_ee_f2_graphd2_alpha_lo_seedrob20260616` | `qdesn_exal_rhs_ns_exact_chunked` | 18.575 | 15.447 |
| HU | 2 | `stageg_hu_f2_graphd1_d3_compact_seedrob20260618` | `qdesn_exal_rhs_ns_exact_chunked` | 9.047 | 10.108 |
| LT | 2 | `stageg_lt_f2_graphd1_input_lo_seedrob20260618` | `qdesn_exal_rhs_ns_exact_chunked` | 15.895 | 13.409 |

## Decision

Use the Stage-G seed-robustness patched registry as the next median-authoritative
registry for these six entries. Do not promote EE fold 1 or LT fold 1 from this
pass because their validation improvements were not seed-stable.

## Recommended Next Stage

Launch seven-quantile promotion only for the six seed-stable patched entries,
using the patched registry as the median source of truth. Keep the two held
candidates as documented near-misses, and only revisit them through a separate
validation-policy or model-selection pass.
