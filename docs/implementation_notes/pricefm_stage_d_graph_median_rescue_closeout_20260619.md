# PriceFM Stage-D Graph Median Rescue Closeout

Date: 2026-06-19

This note closes the Stage-D graph-informed median rescue pass for the PriceFM
single-region local DESN/Q-DESN workflow. The pass is patch-only: it targets
region/fold rows where the Stage-C local registry had clear gaps, runs
graph-khop median rescue candidates, requires seed robustness before promotion,
then promotes only robust candidates to the seven PriceFM paper quantiles.

## Repo State

- Article repo: `/data/jaguir26/local/src/Article-Q-DESN`
- Branch: `application-ensemble-likelihood-redesign`
- Planning commit before this closeout: `133ef74 Plan PriceFM Stage-D graph median rescue`
- Generated artifacts are under ignored `application/data_local/pricefm/...` paths.
- No Overleaf/main edits were made.

## Stage-D Median Rescue Grid

Preparation command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/55_prepare_pricefm_stage_d_graph_median_rescue.py
```

Launch command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_d_graph_median_rescue_20260619.yaml \
  --experiment-jobs 8 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true
```

Outputs:

- Grid config: `application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_d_graph_median_rescue_20260619.yaml`
- Manifest root: `application/data_local/pricefm/experiment_grids/pricefm_stage_d_graph_median_rescue_20260619`
- Run root: `application/data_local/pricefm/runs/pricefm_stage_d_graph_median_rescue_20260619`
- Closeout root: `application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_closeout_20260619`

The prepared rescue grid contained 10 region/fold rows and 80 experiments:
3 close local losses and 7 PriceFM fallbacks. Graph degree counts were 50
degree-1 experiments and 30 degree-2 experiments. Priority counts were
24 priority-0, 24 priority-1, and 32 priority-2 experiments.

The final median rescue run completed all 80 experiments. No failed
`cell_status.csv` rows were found. The rescue run root contained no `.rds`,
`.rda`, or `.rdata` files after cleanup.

Closeout decision counts:

| label | count |
|---|---:|
| robustness_candidate | 8 |
| validation_candidate_audit_worse | 1 |
| validation_overfit_warning | 1 |

Registry-level median test AQL audit from the closeout:

| registry | rows | mean median test AQL | mean selection AQL |
|---|---:|---:|---:|
| current authoritative | 42 | 12.5657 | 12.3239 |
| hypothetical validation-selected rescue | 42 | 12.1843 | 11.8639 |
| hypothetical robustness-candidates only | 42 | 12.1545 | 11.9291 |

## Seed Robustness

Seed grid command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/43_prepare_pricefm_graph_local_rescue_seed_grid.py \
  --source-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_d_graph_median_rescue_20260619.yaml \
  --seed-plan-csv application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_closeout_20260619/robustness_seed_plan.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_d_graph_median_rescue_seedrob_20260619.yaml \
  --grid-id pricefm_stage_d_graph_median_rescue_seedrob_20260619 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_stage_d_graph_median_rescue_seedrob_20260619 \
  --run-root application/data_local/pricefm/runs/pricefm_stage_d_graph_median_rescue_seedrob_20260619 \
  --summary-output application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_closeout_20260619/seedrob_grid_summary.json
```

Launch command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_d_graph_median_rescue_seedrob_20260619.yaml \
  --experiment-jobs 6 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true
```

Summary command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/44_summarize_pricefm_graph_local_rescue_seedrob.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_stage_d_graph_median_rescue_seedrob_20260619/manifest.csv \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_c_all_median_selection_20260618/median_selection_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_seedrob_summary_20260619
```

The seed robustness grid ran 24 experiments: 8 candidates times seeds
`20260616`, `20260617`, and `20260618`. Seven candidates passed the gate:

| region | fold | mean val delta | mean test delta | action |
|---|---:|---:|---:|---|
| BE | 2 | -0.8506 | -0.7581 | patch median registry |
| BE | 3 | -1.0089 | -0.8121 | patch median registry |
| NL | 1 | -2.8709 | -3.8113 | patch median registry |
| NL | 2 | -3.7266 | -4.5631 | patch median registry |
| NL | 3 | -4.5205 | -2.4301 | patch median registry |
| SI | 2 | -1.2075 | -1.0286 | patch median registry |
| SI | 3 | -1.7448 | -1.8232 | patch median registry |
| SE_4 | 1 | 1.6083 | -1.1846 | keep current registry |

Patch command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/45_patch_pricefm_median_registry_from_seedrob.py \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_c_all_median_selection_20260618/median_selection_registry.csv \
  --seedrob-decisions-csv application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_seedrob_summary_20260619/seedrob_decisions.csv \
  --promotion-ready-csv application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_seedrob_summary_20260619/promotion_ready_queue.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_promoted_registry_20260619 \
  --candidate-source stage_d_graph_median_rescue_seedrob
```

Patched registry outputs:

- Full patched registry: `application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_promoted_registry_20260619/patched_selection_registry.csv`
- Patch-only registry: `application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_promoted_registry_20260619/patch_rows_registry.csv`

An earlier local alias, `pricefm_stage_d_graph_median_registry_patched_20260619`,
also exists in `application/data_local/pricefm/authoritative/`, but the freeze
metadata and this note treat the `median_rescue_promoted_registry` directory as
canonical.

## Seven-Quantile Promotion

The seven robust patch rows were promoted to PriceFM paper quantiles
`0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`.

Grid preparation:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  --template-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_priority1_green_paper_quantiles_20260618.yaml \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_promoted_registry_20260619/patch_rows_registry.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_d_graph_rescue_patch_paper_quantiles_20260619.yaml \
  --grid-id pricefm_stage_d_graph_rescue_patch_paper_quantiles_20260619 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_stage_d_graph_rescue_patch_paper_quantiles_20260619 \
  --run-root application/data_local/pricefm/runs/pricefm_stage_d_graph_rescue_patch_paper_quantiles_20260619 \
  --priority 0
```

Launch:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_d_graph_rescue_patch_paper_quantiles_20260619.yaml \
  --experiment-jobs 6 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true
```

Summary:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_promoted_registry_20260619/patch_rows_registry.csv \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_d_graph_rescue_patch_paper_quantiles_20260619.yaml \
  --output-root application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_promoted_quantiles_summary_20260619 \
  --require-complete true \
  --dry-run false \
  --panel-label stage_d_graph_median_rescue_promoted_quantiles \
  --panel-description "Stage-D graph-khop median rescue candidates promoted to seven PriceFM paper quantiles after seed robustness"
```

The promoted quantile grid ran 49 experiments: 7 region/folds times
7 quantiles. All 49 completed with no failed cell-status rows. The run root
contained no `.rds`, `.rda`, or `.rdata` files after cleanup. The execution
grid id is `pricefm_stage_d_graph_rescue_patch_paper_quantiles_20260619`; the
human-facing panel label and summary directory use
`stage_d_graph_median_rescue_promoted_quantiles`.

## Cached PriceFM Comparison And Decision Freeze

Comparison command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_promoted_registry_20260619/patch_rows_registry.csv \
  --pricefm-root application/data_local/pricefm/authoritative/pricefm_phase1_stage_c_priority1_green_20260618 \
  --desn-root application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_promoted_quantiles_summary_20260619 \
  --output-root application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_d_graph_median_rescue_promoted_quantiles_20260619 \
  --split test \
  --quantiles 0.10,0.25,0.45,0.50,0.55,0.75,0.90 \
  --run-pricefm false \
  --desn-panel-label stage_d_graph_median_rescue_promoted_quantiles \
  --desn-panel-description "Stage-D graph-khop median rescue paper-quantile promotion after seed robustness" \
  --comparison-note "Stage-D patch-only comparison: seven robust median rescue rows promoted to seven paper quantiles and compared with cached fold-aligned PriceFM Phase-I." \
  --dry-run false
```

## Metadata Addendum

On 2026-06-20 the Stage-D patch and decision-freeze scripts were hardened so
graph-khop rescue rows preserve explicit graph metadata all the way into the
authoritative quantile decision registry. The regenerated Stage-D graph rows
now carry:

- `feature_policy = graph_khop`
- `input_scope = pricefm_graph_khop_degree1` or
  `pricefm_graph_khop_degree2`
- `spatial_information_set = pricefm_released_graph_khop`
- `graph_source = PriceFM.graph_adj_matrix`
- a 64-character `graph_hash`

The numerical Stage-D closeout counts did not change; the update corrects
provenance so graph-informed rows are not mislabeled as target-only local rows.

Decision freeze:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/53_freeze_pricefm_stage_c_quantile_decisions.py \
  --comparison-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_d_graph_median_rescue_promoted_quantiles_20260619 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_quantile_decisions_20260619 \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_promoted_registry_20260619/patch_rows_registry.csv \
  --grid-id pricefm_stage_d_graph_median_rescue_promoted_quantiles_20260619 \
  --notes "Stage-D graph-khop median rescue patch-only paper-quantile decision freeze after seed robustness and cached PriceFM Phase-I comparison."
```

The comparison used cached fold-aligned PriceFM Phase-I outputs rather than
rerunning the TensorFlow benchmark. The decision freeze evaluated original-unit
test AQL.

Overall patch-only comparison:

| metric | value |
|---|---:|
| evaluated region/folds | 7 |
| local wins | 5 |
| PriceFM fallbacks | 2 |
| close local losses | 0 |
| mean local AQL | 6.4189 |
| mean PriceFM AQL | 7.0304 |
| mean local minus PriceFM AQL | -0.6116 |
| mean relative delta | -0.0782 |

Decision registry:

| region | fold | best local method | local AQL | PriceFM AQL | delta | decision |
|---|---:|---|---:|---:|---:|---|
| BE | 2 | qdesn_exal_rhs_ns_exact_chunked | 6.3969 | 6.4967 | -0.0997 | promote local |
| BE | 3 | qdesn_exal_rhs_ns_exact_chunked | 5.5669 | 5.2935 | 0.2734 | PriceFM fallback |
| NL | 1 | qdesn_exal_rhs_ns_exact_chunked | 5.3703 | 7.2422 | -1.8719 | promote local |
| NL | 2 | qdesn_exal_rhs_ns_exact_chunked | 5.7708 | 7.0605 | -1.2897 | promote local |
| NL | 3 | qdesn_exal_rhs_ns_exact_chunked | 6.7853 | 6.4117 | 0.3736 | PriceFM fallback |
| SI | 2 | qdesn_al_rhs_ns_exact_chunked | 7.9816 | 8.6584 | -0.6768 | promote local |
| SI | 3 | qdesn_exal_rhs_ns_exact_chunked | 7.0602 | 8.0502 | -0.9900 | promote local |

## Interpretation

- Stage-D successfully rescued several Stage-C weak rows, especially NL folds.
- The seed gate correctly filtered `SE_4` fold 1: it had better test AQL but
  lost on validation under every robustness seed.
- The paper-quantile gate further filtered `BE` fold 3 and `NL` fold 3: their
  median rescue specs were robust, but the seven-quantile synthesis lagged
  PriceFM on original-unit test AQL.
- The local graph-informed Q-DESN candidate is now preferred for 5 of the
  7 robust patch rows. Existing non-patch rows remain governed by the Stage-C
  decisions.
- Selection remains validation-first. PriceFM/test comparisons are used only
  for benchmark auditing and the explicit quantile-decision freeze.

## Validation And Hygiene

- Focused tests for the Stage-D planner and graph utilities passed before the
  Stage-D planning commit: 17 tests passed.
- All three Stage-D run roots have zero `.rds`, `.rda`, or `.rdata` files.
- Generated run outputs remain under ignored `application/data_local/pricefm`
  paths and should not be committed.
- `application/scripts/pricefm/10_run_desn_model_full.py` now exits nonzero
  when a full-run `cell_status.csv` contains any failed status; the associated
  helper is tested in `application/tests/test_pricefm_full_run_orchestrator.py`.

## Next Step

Use `stage_c_quantile_decision_registry.csv` from
`application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_quantile_decisions_20260619`
as the patch-only Stage-D decision source. The next implementation pass should
merge the Stage-D patch decisions with the broader Stage-C region/fold decision
registry, preserving PriceFM fallbacks for `BE` fold 3 and `NL` fold 3, and then
decide whether to expand graph-khop rescue to additional PriceFM-fallback rows.
