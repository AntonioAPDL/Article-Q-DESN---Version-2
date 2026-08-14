# PriceFM Graph/Local Panel Rescue Plan

Date: 2026-06-15

## Purpose

This note records the completed graph/local PriceFM region-panel comparison and
the next targeted rescue workflow.  The goal is to improve the weak
region/folds without relaunching the entire panel or using test metrics as
hidden selection criteria.

## Current Checkpoint

Tracked code checkpoint:

```text
Article branch: application-ensemble-likelihood-redesign
Article HEAD before this implementation pass: 4b2e379 Prepare GloFAS next candidate gate
```

Completed ignored/local artifacts:

```text
Median graph/local closeout:
application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/

Seven-quantile graph/local run:
application/data_local/pricefm/runs/pricefm_graph_local_promoted_quantiles_20260614/

Seven-quantile graph/local synthesis:
application/data_local/pricefm/authoritative/pricefm_region_panel_paper_quantiles_graph_local_20260614/

Fold-aligned PriceFM comparison:
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_region_panel_graph_local_20260614/
```

Completed status:

```text
graph/local quantile cells: 126 / 126 complete
region/fold synthesis:      18 / 18 complete
PriceFM comparisons:        18 / 18 complete
heavy R artifacts:          0 .rds/.rda/.RData under the graph/local run roots
```

Main comparison result against PriceFM Phase-I:

```text
selected DESN/Q-DESN beats PriceFM: 9 / 18 folds
selected DESN/Q-DESN close:         1 / 18 folds
selected DESN/Q-DESN lags:          8 / 18 folds

selected DESN/Q-DESN mean AQL:      6.8629
PriceFM Phase-I mean AQL:           7.0027
median relative fold delta:        -0.01%
mean relative fold delta:          +3.81%
```

The mean AQL is slightly better than PriceFM, but fold-level robustness is not
yet strong enough to declare a final win.

## Key Diagnosis

Graph-promoted rows are working:

```text
graph-promoted rows: 6 beat / 1 close / 2 lag
local-kept rows:     3 beat / 0 close / 6 lag
```

Therefore, the next work should not be a broad all-panel relaunch.  The
highest-value move is a targeted rescue pass over weak region/folds.

Weak or close region/folds:

```text
SE_2 fold 1
NO_4 fold 1
DE_LU fold 3
HU fold 2
IT_SICI fold 3
SE_2 fold 3
NO_4 fold 2
NO_4 fold 3
HU fold 3
```

The first horizon group is also the weakest part of the panel, so rescue
diagnostics must stay horizon-aware.

## Implemented Workflow Additions

This pass adds or updates:

```text
application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py
application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py
application/scripts/pricefm/39_diagnose_pricefm_graph_local_panel.py
application/scripts/pricefm/40_prepare_pricefm_graph_local_rescue_median_grid.py
application/scripts/pricefm/41_overlay_pricefm_region_panel_quantiles.py

application/tests/test_pricefm_graph_local_rescue_workflow.py
application/tests/test_pricefm_paper_quantile_summary.py
application/tests/test_pricefm_phase1_comparison.py
```

### Labeling Fix

The panel summary and PriceFM comparison wrappers now accept explicit labels for
graph/local selected panels.  Old defaults are preserved for local-only
reproducibility.

### Diagnostic Script

`39_diagnose_pricefm_graph_local_panel.py` reads the completed comparison root
and median registry and writes:

```text
fold_diagnostics.csv
recommended_rescue_scope.csv
region_summary.csv
horizon_group_diagnostics.csv
horizon_group_summary.csv
graph_local_panel_diagnostic_report.md
summary.json
```

The rescue scope is diagnostic only.  PriceFM metrics identify weak folds but
do not select a new model.

### Targeted Median Rescue Grid

`40_prepare_pricefm_graph_local_rescue_median_grid.py` uses the rescue scope and
current median registry to create median-only candidates.  It explores:

- `graph_khop` degree 1 geometry variants;
- `graph_khop` degree 2 geometry variants;
- limited local variants for folds where graph did not help;
- mild alpha/input-scale perturbations;
- capacity nudges for severe weak folds.

It does not run seven quantiles.  Median validation remains the selection gate.

### Quantile Overlay

`41_overlay_pricefm_region_panel_quantiles.py` creates a panel root that uses
patched region/fold quantile summaries when available and otherwise links back
to the existing graph/local summaries.  This lets us refresh only changed
region/folds before rerunning the PriceFM comparison.

## Staged Rescue Checklist

- [x] Freeze the completed graph/local checkpoint.
- [x] Fix stale local-only wording in report wrappers.
- [x] Add horizon-aware graph/local diagnostics.
- [x] Add targeted median rescue grid generation.
- [x] Add overlay tooling for partial quantile refreshes.
- [x] Run focused tests.
- [x] Generate real graph/local diagnostics.
- [x] Generate targeted median rescue grid config.
- [x] Dry-run generated rescue configs.
- [x] Launch targeted median rescue if dry-run passes.
- [ ] Summarize median rescue registry after the run completes.
- [ ] Promote validation winners only.
- [ ] Generate seven-quantile grids only for changed region/folds.
- [ ] Overlay changed region/folds onto the existing panel.
- [ ] Rerun fold-aligned PriceFM comparison.
- [ ] Decide whether the graph/local/rescue panel is authoritative.

## Reproducibility Criteria

Every run must record:

- registry source;
- grid config;
- generated config root;
- run root;
- output root;
- graph degree and graph hash;
- feature policy and spatial information set;
- validation/test split labels;
- selection metric and unit;
- PriceFM comparison root;
- exact command line;
- `/usr/bin/time -v` log when launching long jobs.

## Selection Rules

- Median rescue selection is validation-only.
- Test metrics and PriceFM metrics are audit and diagnosis only.
- PriceFM comparison is only run after seven-quantile synthesis.
- Do not use PriceFM AQL to pick a median model.
- Do not relaunch already-good folds unless the registry overlay requires it.

## Stop Gates

Stop before launching if:

- focused tests fail;
- diagnostics do not reproduce the known weak folds;
- generated rescue grid contains duplicate IDs;
- generated rescue grid includes all 18 folds by mistake;
- graph metadata is missing from graph candidates;
- local candidates carry graph metadata;
- generated config dry-run fails;
- output paths would overwrite prior authoritative roots without an explicit new ID.

## Validation And Launch Record

Focused syntax check:

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py \
  application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py \
  application/scripts/pricefm/39_diagnose_pricefm_graph_local_panel.py \
  application/scripts/pricefm/40_prepare_pricefm_graph_local_rescue_median_grid.py \
  application/scripts/pricefm/41_overlay_pricefm_region_panel_quantiles.py
```

Focused tests:

```text
application/tests/test_pricefm_graph_local_rescue_workflow.py
application/tests/test_pricefm_paper_quantile_summary.py
application/tests/test_pricefm_phase1_comparison.py
application/tests/test_pricefm_graph_neighbor_grid.py
application/tests/test_pricefm_graph_neighbor_closeout.py

27 passed
```

Broader PriceFM tests:

```text
application/tests/test_pricefm*.py

146 passed
```

Generated graph/local diagnostics:

```text
application/data_local/pricefm/authoritative/pricefm_graph_local_panel_diagnostics_20260615/

n_region_folds: 18
n_rescue_rows: 9
```

Generated targeted median rescue grid:

```text
config:
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_median_rescue_20260615.yaml

generated root:
application/data_local/pricefm/experiment_grids/pricefm_graph_local_median_rescue_20260615/

run root:
application/data_local/pricefm/runs/pricefm_graph_local_median_rescue_20260615/

rescue rows: 9
median experiments: 88
priority counts: 48 priority-0, 28 priority-1, 12 priority-2
feature policies: 76 graph_khop, 12 target_only
graph degrees: 47 degree-1, 29 degree-2
duplicate experiment ids: 0
```

Runner dry-run:

```text
planned experiment jobs: 88
planned window-build jobs: 9
```

Background launch:

```bash
setsid bash -lc 'cd /data/jaguir26/local/src/Article-Q-DESN && exec /usr/bin/time -v \
  -o application/data_local/pricefm/experiment_grids/pricefm_graph_local_median_rescue_20260615/background_launch.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_median_rescue_20260615.yaml \
  --priorities 0,1,2 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false'
```

Initial launch health:

```text
PID: 2383352
status: running
active phase: median experiment/adaptor build
early metric files: 0
early error scan: clean
```
