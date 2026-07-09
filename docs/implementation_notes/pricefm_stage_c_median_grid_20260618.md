# PriceFM Stage-C Median Grid, 2026-06-18

## Purpose

This note records the Stage-C median-grid implementation. The grid is the first
launchable artifact after the Stage-B seven-quantile confirmation gate and the
Stage-C candidate manifest.

The Stage-C discipline remains:

```text
manifest -> median screen -> closeout -> seed robustness when fragile
-> seven paper quantiles -> cached PriceFM comparison -> freeze decisions
```

Median screening is candidate generation only. It is not a final PriceFM
comparison or promotion gate.

## Code Added

```text
application/scripts/pricefm/51_prepare_pricefm_stage_c_median_grid.py
application/tests/test_pricefm_stage_c_median_grid.py
```

The script reads the ignored Stage-C candidate manifest and writes a normal
PriceFM DESN experiment-grid YAML. Every experiment is scoped to exactly one
region/fold/geometry so queue, caution, and benchmark metadata stay attached
through downstream generated configs and selection artifacts.

## Inputs

Stage-C candidate manifest:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_manifest_20260618/stage_c_candidate_manifest.csv
```

Template grid:

```text
application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml
```

## Output

Ignored grid config:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_median_20260618.yaml
```

Ignored plan root:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_median_grid_plan_20260618
```

Ignored generated grid root:

```text
application/data_local/pricefm/experiment_grids/pricefm_stage_c_median_20260618
```

Ignored run root:

```text
application/data_local/pricefm/runs/pricefm_stage_c_median_20260618
```

## Generated Scope

The script generated:

| Queue | Priority | Region/folds | Geometries | Cells |
|---|---:|---:|---:|---:|
| `completion_folds` | 0 | 6 | 3 | 18 |
| `diverse_new_regions` | 1 | 36 | 3 | 108 |
| total |  | 42 | 3 | 126 |

Completion folds:

```text
AT folds 1,3
FI folds 1,2
PL folds 1,3
```

Diverse new regions:

```text
BE, DK_1, DK_2, EE, HU, LT, LV, NL, RO, SE_4, SI, SK
all folds 1,2,3
```

FI fold 3 is deliberately absent from the generic median grid and remains in
the exception-rescue queue.

## Geometries

The grid keeps the compact Stage-B geometries:

| Geometry | L | Depth | Units | alpha | rho | input_scale | Seed |
|---|---:|---:|---|---:|---:|---:|---:|
| `core` | 96 | 1 | `[120]` | 0.50 | 0.90 | 0.50 | 20260601 |
| `lowinput` | 96 | 1 | `[120]` | 0.50 | 0.90 | 0.25 | 20260603 |
| `d2` | 96 | 2 | `[80,80]` | 0.40 | 0.90 | 0.35 | 20260603 |

The goal is region/fold expansion, not a new deep reservoir search.

## Commands Run

Generate Stage-C median grid:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/51_prepare_pricefm_stage_c_median_grid.py \
  --candidate-manifest-csv application/data_local/pricefm/authoritative/pricefm_stage_c_manifest_20260618/stage_c_candidate_manifest.csv \
  --template-grid-config application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_median_20260618.yaml \
  --grid-id pricefm_stage_c_median_20260618 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_stage_c_median_20260618 \
  --run-root application/data_local/pricefm/runs/pricefm_stage_c_median_20260618 \
  --summary-dir application/data_local/pricefm/authoritative/pricefm_stage_c_median_grid_plan_20260618 \
  --write true
```

Materialize generated configs:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_median_20260618.yaml \
  --write
```

Dry-run completion-fold launch:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_median_20260618.yaml \
  --priorities 0 \
  --experiment-jobs 2 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run true \
  --resume true
```

## Validation

Focused tests:

```text
application/tests/test_pricefm_stage_c_median_grid.py: 4 passed
application/tests/test_pricefm_stage_c_manifest.py: 4 passed
```

Dry-run result:

| Kind | Status | Count |
|---|---|---:|
| `window_build` | `planned` | 6 |
| `experiment` | `planned` | 18 |

No `.rds`, `.rda`, or `.RData` artifacts were created under the new Stage-C
run root by the dry run.

## Next Gate

Before the first real launch:

```sh
application/data_local/pricefm/venv/bin/python -m pytest application/tests/test_pricefm*.py
git diff --check
```

Then launch priority 0 only:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_median_20260618.yaml \
  --priorities 0 \
  --experiment-jobs 6 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true
```

Priority 1 diverse new-region rows should remain unlaunched until the
completion-fold closeout is inspected.

## Priority 0 Closeout

The priority 0 completion-fold launch finished cleanly on 2026-06-18.

Launch command:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/logs/pricefm_stage_c_median_20260618/completion_priority0.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_median_20260618.yaml \
  --priorities 0 \
  --experiment-jobs 6 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true
```

Completion checks:

| Check | Result |
|---|---:|
| Priority 0 experiments | `18 / 18` completed |
| Priority 0 region/fold winners | `6 / 6` selected |
| Log failure scan | `0` hits |
| Heavy `.rds/.rda/.RData` artifacts under run root | `0` |
| Launch exit status | `0` |
| Wall time | `1:37:58` |
| Max RSS | `1,495,560 KB` |

Priority 0 median-selection closeout:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_median_20260618.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_c_completion_median_selection_20260618 \
  --priorities 0 \
  --selection-methods qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked \
  --require-complete true
```

Selected median-screen winners:

| Region | Fold | Method | Geometry | Val AQL | Test AQL |
|---|---:|---|---|---:|---:|
| `AT` | 1 | `qdesn_al_rhs_ns_exact_chunked` | D1 `[120]`, input `0.50` | `10.038379` | `8.316152` |
| `AT` | 3 | `qdesn_exal_rhs_ns_exact_chunked` | D1 `[120]`, input `0.50` | `8.934349` | `9.491751` |
| `FI` | 1 | `qdesn_exal_rhs_ns_exact_chunked` | D2 `[80,80]`, input `0.35` | `12.813144` | `12.953277` |
| `FI` | 2 | `qdesn_exal_rhs_ns_exact_chunked` | D2 `[80,80]`, input `0.35` | `12.499336` | `9.815561` |
| `PL` | 1 | `qdesn_al_rhs_ns_exact_chunked` | D1 `[120]`, input `0.25` | `11.037902` | `8.744733` |
| `PL` | 3 | `qdesn_al_rhs_ns_exact_chunked` | D1 `[120]`, input `0.25` | `9.239266` | `10.123683` |

The priority 0 rows are median-screen candidates only. They still require the
normal seven-paper-quantile synthesis and cached PriceFM comparison before any
promotion claim.

## Priority 1 Launch

Because priority 0 passed the completion, failure-scan, finite-metric, and
artifact-cleanliness gates, the priority 1 diverse-new-region median screen was
launched in the background on 2026-06-18.

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/logs/pricefm_stage_c_median_20260618/diverse_priority1.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_median_20260618.yaml \
  --priorities 1 \
  --experiment-jobs 8 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true
```

The priority 1 launcher writes:

```text
application/data_local/pricefm/logs/pricefm_stage_c_median_20260618/diverse_priority1.launch.log
application/data_local/pricefm/logs/pricefm_stage_c_median_20260618/diverse_priority1.time.log
application/data_local/pricefm/logs/pricefm_stage_c_median_20260618/diverse_priority1.exit
```

Do not run final Stage-C selection across priority 1 until the launcher exits
with status `0`, all `108` priority 1 cells have metric summaries, no failure
signatures appear in logs, and no heavy R binary artifacts remain under the
Stage-C run root.

## Priority 1 Closeout

The priority 1 diverse-new-region median screen finished cleanly on
2026-06-18.

Completion checks:

| Check | Result |
|---|---:|
| Priority 1 experiments | `108 / 108` completed |
| Total Stage-C median experiments | `126 / 126` completed |
| Priority 1 region/fold winners | `36 / 36` selected |
| Combined Stage-C region/fold winners | `42 / 42` selected |
| Log failure scan | `0` hits |
| Heavy `.rds/.rda/.RData` artifacts under run root | `0` |
| Priority 1 launch exit status | `0` |
| Priority 1 wall time | `5:10:09` |
| Priority 1 max RSS | `1,539,656 KB` |

Priority 1 closeout command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_median_20260618.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_c_diverse_median_selection_20260618 \
  --priorities 1 \
  --selection-methods qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked \
  --require-complete true
```

Combined priority 0/1 closeout command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_median_20260618.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_c_all_median_selection_20260618 \
  --priorities 0,1 \
  --selection-methods qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked \
  --require-complete true
```

Combined output roots:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_completion_median_selection_20260618
application/data_local/pricefm/authoritative/pricefm_stage_c_diverse_median_selection_20260618
application/data_local/pricefm/authoritative/pricefm_stage_c_all_median_selection_20260618
```

### Median-Screen Summary

Winner counts:

| Queue | Region/folds | AL RHS_NS winners | exAL RHS_NS winners |
|---|---:|---:|---:|
| `completion_folds` | 6 | 3 | 3 |
| `diverse_new_regions` | 36 | 9 | 27 |
| total | 42 | 12 | 30 |

Geometry winners:

| Queue | D1 input `0.25` | D1 input `0.50` | D2 input `0.35` |
|---|---:|---:|---:|
| `completion_folds` | 2 | 2 | 2 |
| `diverse_new_regions` | 16 | 3 | 17 |

The diverse-new-region median screen strongly favors exAL and splits almost
evenly between the lower-input D1 geometry and the compact D2 geometry. The
original Stage-B completion rows remain more mixed.

### Triage Notes

Best median-screen test AQL rows among the combined Stage-C winners:

| Region | Fold | Queue | Method | Test AQL |
|---|---:|---|---|---:|
| `BE` | 1 | `diverse_new_regions` | `qdesn_exal_rhs_ns_exact_chunked` | `7.0556` |
| `BE` | 3 | `diverse_new_regions` | `qdesn_exal_rhs_ns_exact_chunked` | `7.8562` |
| `AT` | 1 | `completion_folds` | `qdesn_al_rhs_ns_exact_chunked` | `8.3162` |
| `BE` | 2 | `diverse_new_regions` | `qdesn_exal_rhs_ns_exact_chunked` | `8.6455` |
| `PL` | 1 | `completion_folds` | `qdesn_al_rhs_ns_exact_chunked` | `8.7447` |
| `RO` | 2 | `diverse_new_regions` | `qdesn_exal_rhs_ns_exact_chunked` | `8.9024` |

Weakest median-screen test AQL rows:

| Region | Fold | Queue | Method | Test AQL |
|---|---:|---|---|---:|
| `EE` | 1 | `diverse_new_regions` | `qdesn_al_rhs_ns_exact_chunked` | `26.3596` |
| `EE` | 3 | `diverse_new_regions` | `qdesn_exal_rhs_ns_exact_chunked` | `20.6003` |
| `EE` | 2 | `diverse_new_regions` | `qdesn_exal_rhs_ns_exact_chunked` | `18.4653` |
| `HU` | 3 | `diverse_new_regions` | `qdesn_exal_rhs_ns_exact_chunked` | `18.1415` |
| `LV` | 3 | `diverse_new_regions` | `qdesn_exal_rhs_ns_exact_chunked` | `17.6369` |
| `LT` | 1 | `diverse_new_regions` | `qdesn_al_rhs_ns_exact_chunked` | `17.4477` |

The rough cached PriceFM `phase1_AQL` fields in the manifest are useful for
triage context only at this step. They are not a final apples-to-apples
comparison because Stage-C is currently a single-median screen, while promotion
still requires the seven-paper-quantile synthesis and cached PriceFM comparison
gate.

### Next Stage-C Gate

The next safe action is not to promote from the median screen directly. The
recommended sequence is:

1. Freeze the combined median-screen registry as candidate-generation evidence.
2. Select a small priority set for seven-paper-quantile synthesis:
   - promising diverse rows such as `BE` folds 1-3 and `RO` fold 2;
   - completion rows that fill Stage-B holes (`AT`, `FI`, `PL`) if they remain
     useful for panel coverage;
   - optionally one or two weak rows (`EE` or `HU`) only as diagnostics, not
     as promotion candidates.
3. Run the normal seven-quantile synthesis and cached PriceFM comparison on
   that priority set.
4. Keep `FI` fold 3 separate in the short-horizon rescue queue.
5. Do not call any Stage-C row a confirmed win until the seven-quantile
   comparison beats cached PriceFM on original-unit test AQL.
