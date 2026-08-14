# PriceFM Graph/Local Rescue Seed Robustness And Expansion Plan

Date: 2026-06-16

## Current Authoritative State

The current authoritative six-region graph/local panel remains:

```text
application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv
```

The graph/local paper-quantile comparison is complete for six regions and
three folds:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_region_panel_graph_local_20260614
```

This covers `18/18` planned region/folds in the exploratory panel. It is not
yet an all-38-region PriceFM benchmark.

## Why The Current Registry Stays Authoritative

The targeted median rescue grid improved validation AQL for several weak
folds, but most validation gains did not transfer to the test audit. Replacing
the current registry with all validation-selected rescue candidates would
worsen the 18-fold mean median test AQL:

| Registry | Mean median test AQL | Mean selection AQL |
|---|---:|---:|
| Current authoritative | `8.338592` | `7.751438` |
| Hypothetical validation-selected rescue | `8.447553` | `7.682242` |
| Robustness-candidates only | `8.314988` | `7.741403` |

Therefore the current registry remains authoritative unless a queued rescue
candidate passes a seed-robustness gate.

## Seed-Robustness Gate

Queued candidate:

| Region | Fold | Source experiment | Method | Geometry |
|---|---:|---|---|---|
| `IT_SICI` | 3 | `rescue_itsici_f3_graphd2_base` | `qdesn_exal_rhs_ns_exact_chunked` | graph degree 2, depth 3, units `[80, 80, 80]`, `alpha=0.35`, `rho=0.9`, `input_scale=0.2`, `tau0=0.001` |

Seed grid:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_rescue_seedrob_itsici_f3_20260616.yaml
```

Seeds:

```text
20260616, 20260617, 20260618
```

Promotion-ready criteria:

1. All seed runs complete with finite metrics.
2. Every seed improves validation AQL against the current median registry row.
3. Mean audit-test AQL delta is non-positive.
4. No seed exceeds the allowed relative test deterioration threshold.

If the gate passes, create a patch median registry for `IT_SICI` fold 3 only,
then promote that patched row to the seven PriceFM paper quantiles. If the gate
fails, keep the current graph/local registry unchanged.

## Seed-Robustness Result

The seed-robustness grid was launched in a detached tmux session:

```text
pricefm_seedrob_itsici_f3_061606
```

It completed successfully for all three seeds. The summary artifacts are:

```text
application/data_local/pricefm/authoritative/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616
```

Decision:

| Region | Fold | Seeds | Validation-improved seeds | Test-improved seeds | Mean validation delta | Mean test delta | Gate |
|---|---:|---:|---:|---:|---:|---:|---|
| `IT_SICI` | 3 | 3 | 2 | 3 | `-0.016591` | `-0.308326` | fail |

Although all three seeds improved audit-test AQL, one seed worsened validation
AQL versus the current authoritative median registry row. The gate therefore
keeps the current registry unchanged. No median-registry patch and no one-row
paper-quantile patch launch were produced from this candidate.

## Commands

Prepare the seed grid:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/43_prepare_pricefm_graph_local_rescue_seed_grid.py \
  --source-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_median_rescue_20260615.yaml \
  --seed-plan-csv application/data_local/pricefm/authoritative/pricefm_graph_local_median_rescue_closeout_20260616/robustness_seed_plan.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_rescue_seedrob_itsici_f3_20260616.yaml \
  --grid-id pricefm_graph_local_rescue_seedrob_itsici_f3_20260616 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616 \
  --run-root application/data_local/pricefm/runs/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616 \
  --summary-output application/data_local/pricefm/authoritative/pricefm_graph_local_median_rescue_closeout_20260616/seedrob_grid_summary.json \
  --priority 0
```

Launch:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_rescue_seedrob_itsici_f3_20260616.yaml \
  --priorities 0 \
  --experiment-jobs 3 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

Summarize after completion:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/44_summarize_pricefm_graph_local_rescue_seedrob.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616/manifest.csv \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616
```

Patch the median registry only if the seed summary writes a non-empty
`promotion_ready_queue.csv`:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/45_patch_pricefm_median_registry_from_seedrob.py \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv \
  --seedrob-decisions-csv application/data_local/pricefm/authoritative/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616/seedrob_decisions.csv \
  --promotion-ready-csv application/data_local/pricefm/authoritative/pricefm_graph_local_rescue_seedrob_itsici_f3_20260616/promotion_ready_queue.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_graph_local_rescue_seedrob_patch_20260616 \
  --candidate-source graph_local_rescue_seedrob_20260616
```

If the patch exists, promote the one-row patch registry to paper quantiles:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  --template-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_promoted_quantiles_20260614.yaml \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_graph_local_rescue_seedrob_patch_20260616/patch_rows_registry.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_graph_local_rescue_quantile_patch_20260616.yaml \
  --grid-id pricefm_graph_local_rescue_quantile_patch_20260616 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_graph_local_rescue_quantile_patch_20260616 \
  --run-root application/data_local/pricefm/runs/pricefm_graph_local_rescue_quantile_patch_20260616 \
  --quantiles 0.10,0.25,0.45,0.50,0.55,0.75,0.90 \
  --priority 0
```

## Broader Expansion Plan

The six-region panel already supports fold/region comparisons to PriceFM
Phase-I. The next expansion should be staged and validation-clean:

### Stage A: Freeze The Six-Region Baseline

- Keep the current graph/local registry as the baseline.
- Add only seed-robustness-passed rescue patches.
- Do not use test metrics to select folds; use them as audit evidence.

### Stage B: Expand Region Coverage In Batches

Use the current six-region panel as the template, then add regions in batches
of roughly 6-10 regions. Each batch should include:

- representative high/low volatility regions,
- different graph degrees in the PriceFM released adjacency,
- regions where naive baselines are strong,
- regions where graph information is expected to help.

Each batch should first run median-only selection. Only selected, stable median
specs should be promoted to seven paper quantiles.

Before launching a batch, write a compact batch manifest with:

- region list and fold list;
- PriceFM Phase-I metric availability for each region/fold;
- graph degree-1 and degree-2 active-region counts;
- local-only and graph-neighbor candidate counts;
- expected experiment count and estimated disk budget;
- artifact cleanup policy;
- exact command lines for prepare, dry-run, launch, summarize, closeout, and
  quantile promotion.

The first expansion batch should deliberately mix graph complexity rather than
only chasing known weak folds. A good candidate pool is:

| Role | Candidate regions | Why |
|---|---|---|
| Low graph degree / edge cases | `PT`, `IT_SARD`, `BG` | Small neighbor sets; tests whether local dynamics dominate. |
| Medium graph degree | `ES`, `FR`, `FI`, `IT_NORD` | Different market blocks with plausible graph benefit. |
| High graph degree / hub-adjacent | `AT`, `NL`, `PL`, `SE_3` | Stress graph-neighbor inputs without jumping to all regions. |

Do not pick the final expansion set by test performance. Use this table to
construct a validation-selection grid, then audit against the already-frozen
PriceFM Phase-I test metrics.

### Stage C: Maintain Apples-To-Apples Comparison

For every promoted region/fold:

- use the same folds and horizons as PriceFM Phase-I,
- keep row alignment checks,
- preserve the target-region output definition,
- clearly label whether inputs are target-only or PriceFM graph-neighborhood
  inputs,
- report against `pricefm_phase1_pretraining` for the same region/fold.

### Stage D: Local Failure Analysis

The current weak spots are `NO_4`, `SE_2`, `DE_LU` fold 3, `HU` fold 2, and
`IT_SICI` fold 3. Before launching an all-region grid, produce a compact
failure analysis for:

- horizon-group deltas,
- graph/local input policy,
- AL versus exAL selected method,
- naive baseline strength,
- validation-to-test transfer stability.

The failure analysis should not block the seed-robustness patch. It is the next
pre-launch artifact for the broader expansion. It should answer:

1. whether failure is concentrated in short, medium, or long horizons;
2. whether graph inputs improve validation but overfit test;
3. whether exAL is consistently better than AL for the same selected geometry;
4. whether the naive baseline is already close to PriceFM and therefore hard to
   beat;
5. whether a fold should receive seed robustness before quantile promotion.

### Stage E: Promotion Policy

Promote a median spec to paper quantiles only when:

1. validation selection is complete,
2. row alignment is clean,
3. seed robustness exists when a fold was introduced through a rescue path,
4. generated heavy artifacts are cleaned,
5. the registry records input information set and target labels.

## Immediate Next Decision

After the seed robustness run finishes:

- if `IT_SICI` fold 3 passes, patch just that fold and run seven quantiles for
  the patch;
- if it fails, keep the six-region panel unchanged and move to the broader
  batch-expansion plan.

The broader expansion can be planned while the seed run is active, but it
should not launch until the seed gate resolves. This keeps the authoritative
six-region registry stable and avoids mixing a rescue-patch decision with a
new-region search.
