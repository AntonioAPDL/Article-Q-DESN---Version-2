# PriceFM Stage-F Graph Rescue Closeout And Quantile Promotion

Date: 2026-06-21

## Scope

This note closes the Stage-F seed-robust graph-rescue median patch and promotes
only the rows that survive paper-quantile comparison against cached,
fold-aligned PriceFM Phase-I predictions. It does not launch new model-selection
grids and does not touch GloFAS or Overleaf outputs.

The validation rule remains deliberately conservative:

- median selection uses validation AQL only;
- test AQL is used only for audit and final local-vs-PriceFM quantile decisions;
- Stage-F patch rows override Stage-E decisions only when explicitly frozen as a
  confirmed local win, close case, or PriceFM fallback;
- generated fit-state binaries are not retained for these runs.

## Inputs

Stage-F median rescue run:

```text
application/data_local/pricefm/runs/pricefm_stage_f_graph_median_rescue_20260620
```

Stage-F full manifest:

```text
application/data_local/pricefm/experiment_grids/pricefm_stage_f_graph_median_rescue_20260620/manifest.csv
```

Previous median registry:

```text
application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_promoted_registry_20260619/patched_selection_registry.csv
```

Previous authoritative quantile registry:

```text
application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_e_20260619/authoritative_quantile_decision_registry.csv
```

## Stage-F Median Closeout

The priority-0 manifest contained 180 Stage-F median experiments. The closeout
found 10 seed-robust candidates, 2 validation candidates with worse test audit,
2 validation-overfit warnings, and 1 keep-current decision across 15 rescue
region/folds.

Closeout output:

```text
application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_closeout_20260621
```

Registry audit:

| item | value |
|---|---:|
| current mean test AQL | 12.193866 |
| validation-selected hypothetical mean test AQL | 11.457817 |
| robustness-candidate hypothetical mean test AQL | 11.362551 |

## Seed-Robust Rerun

The 10 Stage-F robustness candidates were rerun under seeds
`20260616,20260617,20260618`, for 30 total experiments.

Seed-robust grid:

```text
application/data_local/pricefm/configs/pricefm_stage_f_graph_median_rescue_seedrob_20260621.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_f_graph_median_rescue_seedrob_20260621
application/data_local/pricefm/runs/pricefm_stage_f_graph_median_rescue_seedrob_20260621
```

Launch result:

| item | value |
|---|---:|
| experiments | 30 |
| launcher tasks | 40 |
| return codes | all 0 |
| wall time | 1:14:59 |
| max RSS | 1,587,704 KB |
| fit-state binary artifacts | 0 |

All 10 candidates passed the seed-robust promotion gate: 3/3 validation wins and
3/3 test-audit wins.

## Patched Median Registry

The Stage-F median patch replaced 10 region/folds:

| region | fold | promoted median experiment | selected method |
|---|---:|---|---|
| DK_1 | 1 | `stagef_dk1_f1_graphd1_alpha_lo_seedrob20260616` | `qdesn_al_rhs_ns_exact_chunked` |
| DK_2 | 3 | `stagef_dk2_f3_graphd2_input_lo_seedrob20260616` | `qdesn_al_rhs_ns_exact_chunked` |
| EE | 3 | `stagef_ee_f3_graphd2_alpha_hi_seedrob20260617` | `qdesn_al_rhs_ns_exact_chunked` |
| HU | 2 | `stagef_hu_f2_graphd1_rho_lo_seedrob20260618` | `qdesn_exal_rhs_ns_exact_chunked` |
| HU | 3 | `stagef_hu_f3_graphd2_alpha_lo_seedrob20260618` | `qdesn_al_rhs_ns_exact_chunked` |
| LT | 3 | `stagef_lt_f3_graphd1_rho_hi_seedrob20260618` | `qdesn_al_rhs_ns_exact_chunked` |
| LV | 3 | `stagef_lv_f3_graphd2_base_seedrob20260616` | `qdesn_exal_rhs_ns_exact_chunked` |
| RO | 2 | `stagef_ro_f2_graphd1_alpha_lo_seedrob20260617` | `qdesn_exal_rhs_ns_exact_chunked` |
| SK | 2 | `stagef_sk_f2_graphd2_input_lo_seedrob20260617` | `qdesn_exal_rhs_ns_exact_chunked` |
| SK | 3 | `stagef_sk_f3_graphd2_base_seedrob20260617` | `qdesn_al_rhs_ns_exact_chunked` |

Patched median registry:

```text
application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_registry_20260621/patched_selection_registry.csv
```

## Seven-Quantile Promotion Grid

The patched rows were promoted to the paper quantile grid:

```text
0.10,0.25,0.45,0.50,0.55,0.75,0.90
```

Quantile grid:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_f_graph_median_rescue_promoted_quantiles_20260621.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_f_graph_median_rescue_promoted_quantiles_20260621
application/data_local/pricefm/runs/pricefm_stage_f_graph_median_rescue_promoted_quantiles_20260621
```

Launch result:

| item | value |
|---|---:|
| experiments | 70 |
| launcher tasks | 80 |
| return codes | all 0 |
| metric summaries | 70 |
| wall time | 2:43:58 |
| max RSS | 1,554,748 KB |
| run directory size after cleanup | 2.8 GB |
| fit-state binary artifacts | 0 |

Panel summary:

```text
application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_quantiles_summary_20260621
```

All 10 region/folds summarized successfully.

## Cached PriceFM Comparison

The first comparison attempt used the earlier Stage-D cache root and failed
because that cache did not include `DK_1` fold 1. The comparison was rerun
against the broader Stage-E full-panel-missing cache, which covers all 10
Stage-F patch rows:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_stage_e_full_panel_missing_paper_quantiles_20260619
```

Comparison output:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_f_graph_median_rescue_promoted_quantiles_20260621
```

All 10 comparisons completed successfully.

## Stage-F Quantile Decisions

Stage-F patch-only decision freeze:

```text
application/data_local/pricefm/authoritative/pricefm_stage_f_graph_rescue_quantile_decisions_20260621
```

| region | fold | local method | local AQL | PriceFM AQL | delta abs | delta rel | decision |
|---|---:|---|---:|---:|---:|---:|---|
| DK_1 | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 6.139506 | 7.848865 | -1.709359 | -0.217784 | confirmed local win |
| DK_2 | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 7.411013 | 9.368512 | -1.957499 | -0.208944 | confirmed local win |
| EE | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 13.620501 | 16.113867 | -2.493367 | -0.154734 | confirmed local win |
| HU | 2 | `qdesn_al_rhs_ns_exact_chunked` | 9.657750 | 7.322209 | 2.335541 | 0.318967 | PriceFM fallback |
| HU | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 8.853840 | 8.545043 | 0.308797 | 0.036138 | close local loss |
| LT | 3 | `qdesn_al_rhs_ns_exact_chunked` | 12.804693 | 14.103602 | -1.298909 | -0.092098 | confirmed local win |
| LV | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 12.840327 | 13.756953 | -0.916626 | -0.066630 | confirmed local win |
| RO | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 6.757125 | 7.068079 | -0.310954 | -0.043994 | confirmed local win |
| SK | 2 | `qdesn_exal_rhs_ns_exact_chunked` | 6.662191 | 6.815487 | -0.153296 | -0.022492 | confirmed local win |
| SK | 3 | `qdesn_exal_rhs_ns_exact_chunked` | 8.806685 | 7.503739 | 1.302946 | 0.173640 | PriceFM fallback |

Patch-only aggregate:

| item | value |
|---|---:|
| evaluated rows | 10 |
| confirmed local wins | 7 |
| close local losses | 1 |
| PriceFM fallbacks | 2 |
| mean local AQL | 9.355363 |
| mean PriceFM AQL | 9.844636 |
| mean delta abs | -0.489272 |
| mean delta rel | -0.027793 |

## Authoritative Stage-F Registry

The Stage-F decisions were merged over Stage-E decisions with higher
precedence.

Authoritative output:

```text
application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_f_20260621
```

Final registry:

```text
application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_f_20260621/authoritative_quantile_decision_registry.csv
```

Final aggregate:

| item | value |
|---|---:|
| region/folds | 42 |
| confirmed local wins | 17 |
| close local losses | 6 |
| PriceFM fallbacks | 19 |
| mean local AQL | 9.231721 |
| mean PriceFM AQL | 8.959769 |
| mean delta abs | 0.271951 |
| mean delta rel | 0.029936 |

Source contribution:

| source | confirmed local wins | close local losses | PriceFM fallbacks |
|---|---:|---:|---:|
| Stage-E prior authoritative registry | 10 | 5 | 17 |
| Stage-F graph rescue patch | 7 | 1 | 2 |

## Code Fix During Closeout

The authoritative quantile merge script was hardened so prior authoritative
registries can be reused as decision sources. Prior authoritative outputs may
already contain columns named `*_median_registry`; these historical columns are
now dropped from decision sources before merging with the current median
registry. Metadata coalescing also casts feature metadata columns to object
dtype before filling values, avoiding pandas Arrow string assignment failures.

Regression test:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_e_quantile_completion.py
```

Result: 4 passed.

## Reproducibility Commands

Seed-robust median rerun:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_seedrob_20260621_plan/seedrob_launch.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_stage_f_graph_median_rescue_seedrob_20260621.yaml \
  --priorities 0 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run false
```

Seven-quantile patch launch:

```sh
/usr/bin/time -v \
  -o application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_quantiles_20260621_plan/quantile_launch.time.log \
  application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_f_graph_median_rescue_promoted_quantiles_20260621.yaml \
  --priorities 0 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run false
```

Panel summary:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_registry_20260621/patch_rows_registry.csv \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_f_graph_median_rescue_promoted_quantiles_20260621.yaml \
  --output-root application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_quantiles_summary_20260621 \
  --require-complete true \
  --dry-run false \
  --panel-label stage_f_graph_rescue_patch_quantiles \
  --panel-description "Stage-F seed-robust graph rescue patched-row paper quantiles for 10 region/folds."
```

Cached PriceFM comparison:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_registry_20260621/patch_rows_registry.csv \
  --pricefm-root application/data_local/pricefm/authoritative/pricefm_phase1_stage_e_full_panel_missing_paper_quantiles_20260619 \
  --desn-root application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_quantiles_summary_20260621 \
  --output-root application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_f_graph_median_rescue_promoted_quantiles_20260621 \
  --split test \
  --quantiles 0.10,0.25,0.45,0.50,0.55,0.75,0.90 \
  --run-pricefm false \
  --desn-panel-label stage_f_graph_rescue_patch_quantiles \
  --desn-panel-description "Stage-F seed-robust graph rescue patched-row paper quantiles" \
  --comparison-note "Stage-F patch-only comparison: ten seed-robust median rescue rows promoted to seven paper quantiles and compared with cached fold-aligned PriceFM Phase-I from the Stage-E full-panel-missing cache." \
  --dry-run false
```

Decision freeze and authoritative merge:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/53_freeze_pricefm_stage_c_quantile_decisions.py \
  --comparison-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_f_graph_median_rescue_promoted_quantiles_20260621 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_f_graph_rescue_quantile_decisions_20260621 \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_registry_20260621/patch_rows_registry.csv \
  --pricefm-method pricefm_phase1_pretraining \
  --split test \
  --unit original \
  --metric AQL \
  --close-rel-threshold 0.05 \
  --grid-id pricefm_stage_f_graph_median_rescue_promoted_quantiles_20260621 \
  --notes "Stage-F graph rescue patch-only paper-quantile decision freeze after seed robustness and cached PriceFM Phase-I comparison."

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/57_freeze_pricefm_authoritative_quantile_decisions.py \
  --median-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_f_graph_median_rescue_promoted_registry_20260621/patched_selection_registry.csv \
  --decision-source stage_e=application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_e_20260619/authoritative_quantile_decision_registry.csv \
  --decision-source stage_f_graph_rescue=application/data_local/pricefm/authoritative/pricefm_stage_f_graph_rescue_quantile_decisions_20260621/stage_c_quantile_decision_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_f_20260621 \
  --registry-id pricefm_authoritative_quantile_decisions_stage_f_20260621 \
  --notes "Authoritative PriceFM local-vs-benchmark quantile registry after Stage-F seed-robust graph rescue patch."
```

## Checks

- Stage-F quantile launcher: 80/80 tasks completed with return code 0.
- Stage-F quantile metric summaries: 70/70 present.
- Stage-F panel summaries: 10/10 completed.
- Cached PriceFM comparisons: 10/10 completed.
- Generated fit-state binary artifacts under the Stage-F quantile run: 0.
- Focused regression tests for Stage-E/Stage-F authoritative merge: 4 passed.
- No Stage-F launch, summary, or comparison process remained active after
  closeout.

## Takeaways

Stage-F produced a meaningful but selective improvement: 7 of 10 seed-robust
median graph-rescue patches also beat fold-aligned PriceFM at the seven-paper-
quantile level. Two rows (`HU` fold 2 and `SK` fold 3) remain PriceFM fallbacks,
and one (`HU` fold 3) is close but still a local loss under the 5 percent close
threshold. The authoritative Stage-F registry should therefore be used as the
current local-vs-PriceFM decision source, but it is not a global local-model win
over PriceFM.

The next modeling work should use this registry as the frozen baseline and
focus on targeted rescue for remaining PriceFM fallbacks or close losses,
rather than rerunning broad grids for rows already promoted.
