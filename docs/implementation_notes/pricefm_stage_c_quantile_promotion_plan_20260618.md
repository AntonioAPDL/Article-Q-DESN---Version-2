# PriceFM Stage-C Quantile Promotion Plan, 2026-06-18

## Purpose

This note refines the Stage-C plan after the completed median screen. It is a
planning artifact for the next implementation pass. It does not launch models.

The central correction is:

```text
Median-screen winners are candidate-generation evidence only.
They are not promotion decisions.
```

A Stage-C row may be called a confirmed local DESN/Q-DESN win only after:

1. the row has a frozen median-screen winner selected using validation metrics;
2. the selected specification has been run on the seven paper quantiles;
3. cached or regenerated PriceFM Phase-I predictions exist for the same
   region/fold/test window;
4. row alignment is exact;
5. original-unit test AQL beats PriceFM.

## Current State

Tracked code/documentation checkpoint:

```text
Article branch: application-ensemble-likelihood-redesign
Latest tracked Stage-C commit: 1fe0de9 Document PriceFM Stage-C median closeout
```

Completed ignored/local artifacts:

```text
Stage-C manifest:
application/data_local/pricefm/authoritative/pricefm_stage_c_manifest_20260618/

Stage-C median grid:
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_median_20260618.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_c_median_20260618/
application/data_local/pricefm/runs/pricefm_stage_c_median_20260618/

Stage-C median selections:
application/data_local/pricefm/authoritative/pricefm_stage_c_completion_median_selection_20260618/
application/data_local/pricefm/authoritative/pricefm_stage_c_diverse_median_selection_20260618/
application/data_local/pricefm/authoritative/pricefm_stage_c_all_median_selection_20260618/
```

Stage-C median-screen completion:

| Queue | Region/folds | Median cells | Completed | Winners |
|---|---:|---:|---:|---:|
| `completion_folds` | 6 | 18 | 18 | 6 |
| `diverse_new_regions` | 36 | 108 | 108 | 36 |
| total | 42 | 126 | 126 | 42 |

Health checks:

| Check | Result |
|---|---:|
| Priority 0 exit status | `0` |
| Priority 1 exit status | `0` |
| Log failure signatures | `0` |
| Heavy `.rds/.rda/.RData` artifacts | `0` |
| Combined median-selection rows | `42 / 42` |

## Critical Audit

### 1. Do Not Select Using Test Or PriceFM Metrics

The median-screen registry contains validation metrics, test metrics, and
cached PriceFM context fields. Only validation metrics should be used to choose
which local specification gets promoted to seven-quantile synthesis.

Allowed for candidate selection:

- `selection_split = val`;
- `selection_unit = original`;
- `selection_metric = AQL`;
- median-screen method coverage and finite-state checks;
- queue/caution labels from the manifest;
- reproducibility and artifact-completeness checks.

Allowed for audit only:

- `test_AQL`, `test_MAE`, `test_RMSE`;
- `phase1_AQL`, `phase1_MAE`, `phase1_RMSE`;
- rough deltas versus PriceFM.

This is important because the final test window and PriceFM benchmark are the
promotion gate. They should not choose candidates before the seven-quantile
run.

### 2. Completion Folds And New Regions Are Different Problems

The cached PriceFM Phase-I root currently covers the Stage-C completion rows
but not the new diverse-region rows.

Cached benchmark root:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_stage_b_apples_to_apples_20260616
```

Coverage audit:

| Queue | Rows needing PriceFM | Rows already cached | Missing |
|---|---:|---:|---:|
| `completion_folds` | 6 | 6 | 0 |
| `diverse_new_regions` | 36 | 0 | 36 |

Therefore, the next implementation should not treat all 42 rows the same.
Completion folds can go straight to seven-quantile synthesis and cached
comparison. Diverse new-region rows first need a PriceFM benchmark-cache
sentinel, or a deliberate `run-pricefm` step in the comparison wrapper.

### 3. Median AQL Is Not The Paper Metric

The median screen targets `tau = 0.50`. The paper comparison uses:

```text
0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90
```

Median performance is useful for candidate generation, but final promotion must
use the seven-quantile panel metrics.

### 4. The Information Set Must Stay Explicit

The current Stage-C median grid is:

```text
feature_policy: target_only
input_scope: local_target_only
spatial_information_set: local_only_not_pricefm_graph
```

This is intentionally narrower than the full PriceFM spatial information set.
Any future graph/local or neighbor-aware Stage-C variant must carry a different
information-set label so comparisons remain interpretable.

## Validation-Ranked Median Evidence

### Completion Folds

These rows fill partially evaluated Stage-B regions and already have cached
PriceFM benchmarks.

| Region | Fold | Winner | Val AQL | Geometry | Caution |
|---|---:|---|---:|---|---|
| `AT` | 3 | `qdesn_exal_rhs_ns_exact_chunked` | `8.9343` | D1 input `0.50` | `narrow_existing_win` |
| `PL` | 3 | `qdesn_al_rhs_ns_exact_chunked` | `9.2393` | D1 input `0.25` | `short_horizon_fragile_existing_win` |
| `AT` | 1 | `qdesn_al_rhs_ns_exact_chunked` | `10.0384` | D1 input `0.50` | `narrow_existing_win` |
| `PL` | 1 | `qdesn_al_rhs_ns_exact_chunked` | `11.0379` | D1 input `0.25` | `short_horizon_fragile_existing_win` |
| `FI` | 2 | `qdesn_exal_rhs_ns_exact_chunked` | `12.4993` | D2 input `0.35` | `existing_fold_exception` |
| `FI` | 1 | `qdesn_exal_rhs_ns_exact_chunked` | `12.8131` | D2 input `0.35` | `existing_fold_exception` |

Recommendation: promote all six to the next seven-quantile gate. The purpose is
panel completion, and the benchmark cache already exists.

### Diverse New Regions

Region-level validation summary:

| Region | Folds | Mean Val AQL | Min Val AQL | Max Val AQL | exAL Wins | D2 Wins | Tier |
|---|---:|---:|---:|---:|---:|---:|---|
| `BE` | 3 | `7.7933` | `6.9031` | `8.4211` | 3 | 0 | green |
| `SE_4` | 3 | `10.5005` | `9.5891` | `11.6844` | 2 | 2 | green |
| `SI` | 3 | `10.6291` | `8.7429` | `12.2584` | 1 | 1 | green |
| `NL` | 3 | `10.8275` | `10.0487` | `11.5063` | 2 | 0 | green |
| `RO` | 3 | `11.4210` | `8.5807` | `15.6718` | 3 | 2 | mixed |
| `DK_2` | 3 | `11.7216` | `11.3654` | `12.2417` | 2 | 2 | yellow |
| `SK` | 3 | `11.8490` | `10.5413` | `13.7552` | 3 | 1 | yellow |
| `DK_1` | 3 | `11.8871` | `11.1994` | `12.5995` | 3 | 1 | yellow |
| `HU` | 3 | `13.2905` | `11.5942` | `15.2908` | 2 | 0 | rescue |
| `LV` | 3 | `15.4502` | `13.1021` | `16.9447` | 3 | 3 | rescue |
| `LT` | 3 | `15.9173` | `14.9212` | `16.8049` | 1 | 3 | rescue |
| `EE` | 3 | `19.7272` | `16.5951` | `22.0203` | 2 | 2 | rescue |

Recommended tier definitions:

| Tier | Rule | Rows | Next action |
|---|---|---:|---|
| `green_full_region` | all folds reasonably strong by validation; max Val AQL roughly `<= 12.3` | `BE`, `SE_4`, `SI`, `NL` = 12 rows | benchmark sentinel, then seven quantiles |
| `yellow_region_or_fold` | moderate validation strength or one weak fold | `DK_1`, `DK_2`, `SK`, selected `RO` folds | hold until green/completion results are known |
| `rescue_needed` | high validation AQL or unstable folds | `EE`, `LT`, `LV`, most `HU`, `RO` fold 1 | do not promote; design a new median rescue/grid |

This tiering is intentionally validation-first. Test AQL and PriceFM context
may confirm risk, but do not define the tier.

## Recommended Implementation Stages

### Stage C2.0: Freeze A Quantile Candidate Registry

Create a small script, for example:

```text
application/scripts/pricefm/52_freeze_pricefm_stage_c_quantile_candidate_registry.py
application/tests/test_pricefm_stage_c_quantile_candidate_registry.py
```

Inputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_all_median_selection_20260618/median_selection_registry.csv
application/data_local/pricefm/authoritative/pricefm_stage_c_manifest_20260618/stage_c_candidate_manifest.csv
```

Outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_quantile_candidate_registry_20260618/
  stage_c_quantile_candidate_registry.csv
  stage_c_quantile_priority0_completion_registry.csv
  stage_c_quantile_priority1_green_registry.csv
  stage_c_quantile_hold_registry.csv
  stage_c_benchmark_cache_requirements.csv
  stage_c_quantile_candidate_report.md
  summary.json
```

Script requirements:

- fail if median-selection rows are not unique by `region,fold`;
- fail if method coverage is incomplete;
- fail if any required validation metric is missing or non-finite;
- join manifest queue/caution metadata;
- assign `quantile_gate_priority`;
- mark whether cached PriceFM benchmark exists;
- never use `test_AQL` or PriceFM deltas to assign promotion priority;
- keep `FI` fold 3 out of the generic Stage-C registry.

Suggested priority labels:

| Priority | Rows | Reason |
|---:|---|---|
| 0 | all six completion folds | closes existing partial Stage-B regions; cached PriceFM exists |
| 1 | green full-region rows: `BE`, `SE_4`, `SI`, `NL` | best new-region validation evidence |
| 2 | yellow rows | optional later expansion |
| hold | rescue rows | require median rescue before quantiles |

Why this is optimal:

- It preserves the Stage-B discipline.
- It prevents accidental test/benchmark leakage.
- It creates a stable registry that every later grid/summarizer/comparison can
  reference.
- It lets us run completion and new-region promotion as separate resource and
  benchmark-cache problems.

### Stage C2.1: Seven-Quantile Completion-Fold Gate

Use only:

```text
stage_c_quantile_priority0_completion_registry.csv
```

This should contain six region/folds:

```text
AT fold 1, AT fold 3, FI fold 1, FI fold 2, PL fold 1, PL fold 3
```

Prepare a seven-quantile grid:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  --template-grid-config application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_c_quantile_candidate_registry_20260618/stage_c_quantile_priority0_completion_registry.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_completion_paper_quantiles_20260618.yaml \
  --grid-id pricefm_stage_c_completion_paper_quantiles_20260618 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_stage_c_completion_paper_quantiles_20260618 \
  --run-root application/data_local/pricefm/runs/pricefm_stage_c_completion_paper_quantiles_20260618 \
  --quantiles 0.10,0.25,0.45,0.50,0.55,0.75,0.90 \
  --priority 0
```

Expected size:

```text
6 region/folds x 7 quantiles = 42 cells
```

Then:

1. materialize with `12_prepare_desn_experiment_grid.py`;
2. dry-run with `13_run_desn_experiment_grid.py`;
3. launch only if dry-run plans exactly 42 cells;
4. summarize with `35_summarize_pricefm_region_panel_quantiles.py`;
5. compare with `36_compare_pricefm_region_panel_quantiles.py` against:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_stage_b_apples_to_apples_20260616
```

Why this is optimal:

- It is small.
- It uses already-cached PriceFM predictions.
- It completes the known Stage-B partial-region gap.
- It produces immediate apples-to-apples evidence before spending compute on
  new regions.

### Stage C2.2: Benchmark Sentinel For Green New Regions

Use:

```text
stage_c_quantile_priority1_green_registry.csv
```

Initial green full-region rows:

```text
BE folds 1-3
SE_4 folds 1-3
SI folds 1-3
NL folds 1-3
```

Before launching local seven-quantile comparison, run a sentinel that verifies
whether PriceFM cached predictions exist for every row. Current audit says they
do not exist for these diverse regions.

The implementation should either:

1. call the existing comparison wrapper with `--run-pricefm true` in a dry-run
   and then real mode; or
2. add a small cache-materialization wrapper if the current interface is too
   coarse for selected region/folds.

Required benchmark-cache outputs:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_stage_c_green_paper_quantiles_20260618/
```

Required checks:

- all selected `region,fold` pairs have PriceFM predictions;
- prediction rows align exactly to local DESN/Q-DESN rows after synthesis;
- all seven quantiles are present;
- `split = test` and `unit = original` metrics are available;
- row-audit files exist for every region/fold;
- no PriceFM regeneration is run for completion folds unless explicitly
  requested.

Why this is optimal:

- It avoids launching a full local panel only to discover missing benchmarks.
- It keeps PriceFM as the benchmark, not a hidden selector.
- It lets us expand to new regions without weakening the apples-to-apples
  contract.

### Stage C2.3: Seven-Quantile Green New-Region Gate

After the benchmark sentinel passes, prepare a seven-quantile grid from the
green registry.

Expected size:

```text
12 region/folds x 7 quantiles = 84 cells
```

Recommended launch:

```text
experiment_jobs: 8
cell_jobs: 1
build_windows: true
resume: true
```

Summarize and compare exactly as in Stage C2.1, but write to new roots:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_green_paper_quantiles_summary_20260618/
application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_c_green_paper_quantiles_20260618/
```

Why this is optimal:

- It tests the strongest new-region candidates first.
- It has manageable compute size.
- It gives a high-quality signal before expanding to yellow or rescue rows.

### Stage C2.4: Freeze Stage-C Quantile Decisions

After C2.1 and C2.3 comparisons finish, use a decision-freeze script following
the Stage-B pattern:

```text
application/scripts/pricefm/53_freeze_pricefm_stage_c_quantile_decisions.py
application/tests/test_pricefm_stage_c_quantile_decisions.py
```

Outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_quantile_decisions_20260618/
  evaluated_stage_c_panel.csv
  confirmed_stage_c_panel.csv
  stage_c_quantile_exceptions.csv
  horizon_group_diagnostics.csv
  stage_c_quantile_decision_report.md
  summary.json
```

Decision labels:

| Label | Meaning |
|---|---|
| `confirmed_win` | local seven-quantile model beats cached PriceFM on original-unit test AQL |
| `evaluated_loss` | local seven-quantile model loses to cached PriceFM |
| `needs_short_horizon_rescue` | loss primarily in horizon group `1-24` |
| `needs_geometry_rescue` | loss across multiple horizon groups |
| `benchmark_missing` | PriceFM cache or row alignment missing |

Why this is optimal:

- It keeps median-screen, quantile synthesis, and final promotion distinct.
- It makes the next launch list data-driven and reproducible.
- It prevents multiple inconsistent local registries.

### Stage C2.5: Decide Yellow/Rescue Follow-Up

Only after C2.4:

- If green rows confirm well, expand to yellow rows.
- If green rows mostly fail, prioritize graph/local or neighbor-aware feature
  variants before adding more local-only rows.
- Keep `FI` fold 3 short-horizon rescue separate.
- Keep `EE`, `LT`, `LV`, and weak `HU` rows out of seven-quantile promotion
  until a new median rescue grid improves validation AQL.

## Required Tests

Before launching new grids:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_c_manifest.py \
  application/tests/test_pricefm_stage_c_median_grid.py
```

After adding the candidate-freeze script:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_c_quantile_candidate_registry.py
```

After adding the decision-freeze script:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_c_quantile_decisions.py
```

Before each launch:

```sh
git diff --check
application/data_local/pricefm/venv/bin/python -m pytest application/tests/test_pricefm*.py
```

## Reproducibility Checklist

Every new run must record:

- source registry path and hash;
- generated grid config path;
- generated config root;
- run root;
- output summary root;
- cached or regenerated PriceFM benchmark root;
- quantile grid;
- regions/folds;
- model methods allowed;
- information-set labels;
- exact command lines;
- `/usr/bin/time -v` logs;
- launch status;
- row-alignment status;
- artifact-cleanliness status;
- git commit hash.

Keep generated local outputs ignored by git. Track only scripts, tests, and
implementation notes.

## Stop Gates

Stop before launch if:

- any selected row lacks a median-screen winner;
- any selected row was chosen using test or PriceFM metrics;
- the filtered registry contains duplicate `region,fold`;
- the quantile-grid dry run does not match the expected cell count;
- PriceFM benchmark predictions are missing and `run-pricefm` was not
  explicitly authorized;
- row alignment is imperfect;
- generated output roots would overwrite prior authoritative roots;
- heavy binary artifacts would need to be committed;
- `FI` fold 3 appears in the generic Stage-C flow.

## Recommended Immediate Next Step

Implement Stage C2.0 only:

```text
52_freeze_pricefm_stage_c_quantile_candidate_registry.py
test_pricefm_stage_c_quantile_candidate_registry.py
```

Then run the priority-0 completion seven-quantile dry-run. Do not launch the
green diverse-region quantile panel until the benchmark-cache sentinel is
implemented and checked.
