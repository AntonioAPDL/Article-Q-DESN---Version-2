# PriceFM Stage-H Priority-0 Seedrob Quantile Closeout

Date: 2026-06-23

This note closes the Stage-H priority-0 PriceFM local graph-rescue workflow. The goal was to take the completed priority-0 median rescue grid, seed-check the validation-selected median improvements, promote only seed-robust rows into a patched median registry, run the paper-quantile panel for those patched rows, and freeze the apples-to-apples cached PriceFM comparison decisions.

## Repo State

- Article repo: `/data/jaguir26/local/src/Article-Q-DESN`
- Branch: `application-ensemble-likelihood-redesign`
- Starting HEAD for this closeout: `7e6782ddbdb70235a76f2b3983db21f29a4f91a2`
- Remote: `origin https://github.com/AntonioAPDL/Article-Q-DESN.git`

Only one tracked script change was needed: `application/scripts/pricefm/43_prepare_pricefm_graph_local_rescue_seed_grid.py` now accepts `--candidate-source`, so Stage-H seed-robustness grids record their own provenance instead of the older graph-rescue seedrob label.

## Inputs

Priority-0 median rescue run:

- Run root: `application/data_local/pricefm/runs/pricefm_stage_h_targeted_median_rescue_20260622`
- Grid config: `application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_h_targeted_median_rescue_20260622.yaml`
- Manifest: `application/data_local/pricefm/experiment_grids/pricefm_stage_h_targeted_median_rescue_20260622/manifest.csv`
- Completion state: `192/192` experiments, `63/63` window builds, `0` failed, `192` metric summaries, `0` R binary artifacts.

Stage-G authoritative baseline:

- Median registry: `application/data_local/pricefm/authoritative/pricefm_stage_g_seedrob_patched_registry_20260622/patched_selection_registry.csv`
- Quantile decisions: `application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_g_seedrob_20260622/authoritative_quantile_decision_registry.csv`

Cached PriceFM comparison baseline:

- `application/data_local/pricefm/authoritative/pricefm_phase1_stage_e_full_panel_missing_paper_quantiles_20260619`

## Median Rescue Closeout

Command output:

- Output dir: `application/data_local/pricefm/authoritative/pricefm_stage_h_priority0_closeout_20260623`
- Decision counts:
  - `robustness_candidate`: 5
  - `validation_candidate_audit_worse`: 2
  - `test_only_diagnostic`: 1

The five seed-robustness candidates were:

| region | fold | source experiment | method family |
|---|---:|---|---|
| EE | 1 | `stageh_ee_f1_graphd2_rho_low` | Q-DESN exAL/RHS_NS exact-chunked |
| HU | 1 | `stageh_hu_f1_graphd2_input_low` | Q-DESN exAL/RHS_NS exact-chunked |
| LT | 1 | `stageh_lt_f1_graphd1_alpha_high` | Q-DESN exAL/RHS_NS exact-chunked |
| RO | 1 | `stageh_ro_f1_graphd2_input_low` | Q-DESN AL/RHS_NS exact-chunked |
| SK | 1 | `stageh_sk_f1_graphd2_alpha_low` | Q-DESN AL/RHS_NS exact-chunked |

Registry-level median audit:

| scenario | mean median test AQL | mean selection AQL |
|---|---:|---:|
| Current authoritative | 10.9311517 | 10.8819978 |
| Hypothetical validation-selected rescue | 10.6591043 | 10.6616503 |
| Hypothetical robustness candidates only | 10.6445472 | 10.6777640 |

## Seed Robustness

Seedrob grid:

- Grid config: `application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_h_priority0_seedrob_20260623.yaml`
- Run root: `application/data_local/pricefm/runs/pricefm_stage_h_priority0_seedrob_20260623`
- Plan/log dir: `application/data_local/pricefm/authoritative/pricefm_stage_h_priority0_seedrob_plan_20260623`
- Candidate source label: `stage_h_priority0_seedrob_20260623`
- Experiments: `15` (`5` candidates times `3` seeds: `20260623`, `20260624`, `20260625`)
- Launch: `--experiment-jobs 10 --cell-jobs 1 --build-windows true --resume true`
- Exit status: `0`
- Wall time: `38:18.41`
- Max RSS: `1,420,476 KB`
- Metric summaries: `15/15`
- R binary artifacts: `0`
- Run-root size after cleanup discipline: `560M`

Seedrob summary:

- Output dir: `application/data_local/pricefm/authoritative/pricefm_stage_h_priority0_seedrob_summary_20260623`
- Candidates: `5`
- Missing metrics: `0`
- Promotion-ready: `4/5`

| region | fold | validation win rate | mean validation delta | mean test delta | max test relative delta | decision |
|---|---:|---:|---:|---:|---:|---|
| EE | 1 | 1.000 | -3.901300 | -6.697856 | -0.205858 | promote |
| HU | 1 | 1.000 | -0.952803 | -1.419839 | -0.064853 | promote |
| LT | 1 | 0.333 | 0.151677 | -0.697972 | -0.006190 | keep current |
| RO | 1 | 1.000 | -0.287040 | -0.372670 | -0.022594 | promote |
| SK | 1 | 1.000 | -1.451987 | -1.607863 | -0.093047 | promote |

LT was not patched because its validation improvement was not seed-robust, even though the mean test delta was favorable.

## Patched Median Registry

Patch output:

- Output dir: `application/data_local/pricefm/authoritative/pricefm_stage_h_priority0_seedrob_patched_registry_20260623`
- Patch rows: `4`
- Patched median registry rows: `42`
- Patch rows file: `patch_rows_registry.csv`
- Patched registry file: `patched_selection_registry.csv`

The patched median rows are EE-1, HU-1, RO-1, and SK-1. These rows are validation-selected and seed-robust at the median stage. They are not automatically promoted for paper-quantile evaluation until they beat cached PriceFM on the seven-quantile panel.

## Patch Paper-Quantile Run

Seven-quantile patch grid:

- Grid config: `application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_h_priority0_promoted_quantiles_20260623.yaml`
- Run root: `application/data_local/pricefm/runs/pricefm_stage_h_priority0_promoted_quantiles_20260623`
- Plan/log dir: `application/data_local/pricefm/authoritative/pricefm_stage_h_priority0_promoted_quantiles_plan_20260623`
- Quantiles: `0.10,0.25,0.45,0.50,0.55,0.75,0.90`
- Experiments: `28` (`4` patched region/folds times `7` quantiles)
- Launch: `--experiment-jobs 10 --cell-jobs 1 --build-windows true --resume true`
- Exit status: `0`
- Wall time: `1:04:21`
- Max RSS: `1,418,040 KB`
- Metric summaries: `28/28`
- R binary artifacts: `0`
- Run-root size after cleanup discipline: `1.1G`

Panel summary:

- Output root: `application/data_local/pricefm/authoritative/pricefm_stage_h_priority0_promoted_quantiles_summary_20260623`
- Region/folds: `4`
- Status: completed
- Report: `region_panel_quantile_summary_report.md`

Cached PriceFM comparison:

- Output root: `application/data_local/pricefm/authoritative/pricefm_phase1_cached_vs_stage_h_priority0_promoted_quantiles_20260623`
- Region/folds: `4`
- Status: completed
- Report: `pricefm_region_panel_quantile_comparison_report.md`

## Patch Quantile Decisions

Frozen decision output:

- Output dir: `application/data_local/pricefm/authoritative/pricefm_stage_h_priority0_quantile_decisions_20260623`
- Decision registry: `stage_c_quantile_decision_registry.csv`
- Promoted local registry: `stage_c_quantile_promoted_local_registry.csv`
- PriceFM fallback registry: `stage_c_quantile_pricefm_fallback_registry.csv`
- Report: `stage_c_quantile_decision_report.md`

Patch-level comparison against cached fold-aligned PriceFM:

| region | fold | best local method | local AQL | PriceFM AQL | delta | relative delta | decision |
|---|---:|---|---:|---:|---:|---:|---|
| EE | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 15.4833 | 19.2704 | -3.7870 | -0.1965 | promote local |
| HU | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 7.8841 | 8.5003 | -0.6161 | -0.0725 | promote local |
| RO | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 8.2972 | 7.5680 | 0.7293 | 0.0964 | PriceFM fallback |
| SK | 1 | `qdesn_exal_rhs_ns_exact_chunked` | 7.9972 | 8.2128 | -0.2156 | -0.0263 | promote local |

Patch-level aggregate:

- Evaluated region/folds: `4`
- Confirmed local wins: `3`
- Close local losses: `0`
- PriceFM fallbacks: `1`
- Mean local AQL: `9.9154682`
- Mean PriceFM AQL: `10.8878380`
- Mean delta: `-0.9723698`
- Mean relative delta: `-0.0497228`

RO is the important conservative exception: its median seedrob patch improved the median registry, but the full seven-quantile panel lagged cached PriceFM by about `9.6%` on original-unit test AQL, so RO-1 falls back to PriceFM for the authoritative quantile decision.

## Authoritative Quantile Registry Merge

Merged output:

- Output dir: `application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_h_priority0_20260623`
- Registry id: `pricefm_authoritative_quantile_decisions_stage_h_priority0_20260623`
- Authoritative registry: `authoritative_quantile_decision_registry.csv`
- Promoted local registry: `authoritative_quantile_promoted_local_registry.csv`
- PriceFM fallback registry: `authoritative_quantile_pricefm_fallback_registry.csv`
- Source counts: `authoritative_quantile_source_counts.csv`

The merge uses Stage-G seedrob decisions as the base and Stage-H priority-0 patch decisions as the higher-precedence source for the four patch-evaluated region/folds.

Merged summary:

| quantity | value |
|---|---:|
| Region/folds | 42 |
| Local promotions | 25 |
| Close local losses | 6 |
| PriceFM fallbacks | 11 |
| Mean local AQL | 8.6442056 |
| Mean PriceFM AQL | 8.9597694 |
| Mean local minus PriceFM AQL | -0.3155638 |
| Mean relative delta | -0.0263637 |

Source counts:

| source | decision | region/folds |
|---|---|---:|
| Stage-G seedrob | confirmed local win | 22 |
| Stage-G seedrob | close local loss | 6 |
| Stage-G seedrob | PriceFM fallback | 10 |
| Stage-H priority-0 patch | confirmed local win | 3 |
| Stage-H priority-0 patch | PriceFM fallback | 1 |

## Validation Checks

Focused checks run for the tracked script change:

```sh
application/data_local/pricefm/venv/bin/python -m py_compile application/scripts/pricefm/43_prepare_pricefm_graph_local_rescue_seed_grid.py
application/data_local/pricefm/venv/bin/python -m pytest application/tests/test_pricefm_graph_local_rescue_workflow.py -q
```

Earlier checks in the same pass:

```sh
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/42_closeout_pricefm_graph_local_rescue.py \
  application/scripts/pricefm/43_prepare_pricefm_graph_local_rescue_seed_grid.py \
  application/scripts/pricefm/44_summarize_pricefm_graph_local_rescue_seedrob.py \
  application/scripts/pricefm/45_patch_pricefm_median_registry_from_seedrob.py \
  application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py \
  application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py \
  application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py \
  application/scripts/pricefm/53_freeze_pricefm_stage_c_quantile_decisions.py \
  application/scripts/pricefm/57_freeze_pricefm_authoritative_quantile_decisions.py

application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_graph_local_rescue_workflow.py \
  application/tests/test_pricefm_stage_h_targeted_rescue.py -q
```

Artifact checks:

- Stage-H seedrob R binary artifacts: `0`
- Stage-H promoted-quantile R binary artifacts: `0`
- No Stage-H current-pass background jobs remained after the launches completed.

## Interpretation

Stage-H priority-0 did what it was supposed to do:

1. It improved several weak priority-0 median selections without promoting validation-only noise unchecked.
2. It rejected LT at the seedrob gate because validation improvement was not robust across seeds.
3. It promoted EE, HU, and SK at the full paper-quantile gate because the local seven-quantile panel beat cached PriceFM on original-unit test AQL.
4. It retained PriceFM for RO at the paper-quantile gate, despite RO passing median seedrob, because the complete seven-quantile panel was worse than cached PriceFM.
5. It improved the merged 42-row authoritative quantile registry on average, while preserving explicit fallbacks and close-call labels.

## Next Step

The next implementation stage should not overwrite this registry blindly. The safest path is:

1. Treat `pricefm_authoritative_quantile_decisions_stage_h_priority0_20260623` as the current authoritative quantile decision registry.
2. Launch additional rescue only for rows that remain `stage_c_pricefm_fallback` or `stage_c_local_close_to_pricefm`, with separate provenance labels and the same median-seedrob then seven-quantile confirmation gates.
3. Keep RO-1 as a cautionary example: median selection alone is insufficient for paper-quantile promotion.
4. Continue requiring zero R binary artifacts in run roots and compact tracked documentation only.
