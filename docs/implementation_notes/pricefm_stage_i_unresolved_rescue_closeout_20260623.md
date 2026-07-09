# PriceFM Stage-I Unresolved Rescue Closeout

Date: 2026-06-23

## Scope

Stage-I revisited the unresolved PriceFM region/fold cases left after the
Stage-H priority-0 registry:

- 6 close local losses
- 11 PriceFM fallbacks

The goal was conservative: run a broad median rescue grid, seed-check only
validation-clean candidates, promote to seven paper quantiles only after seed
robustness, and merge decisions without blindly replacing the current
authoritative registry.

## Setup Commit

Tracked setup changes were committed before launch:

- Commit: `ead3ded Prepare PriceFM Stage-I unresolved rescue`
- Main setup doc: `docs/implementation_notes/pricefm_stage_i_unresolved_rescue_plan_20260623.md`

## Stage-I Median Rescue Grid

Inputs:

- Current registry:
  `application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_h_priority0_20260623/authoritative_quantile_decision_registry.csv`
- Generated grid config:
  `application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_i_unresolved_median_rescue_20260623.yaml`
- Manifest:
  `application/data_local/pricefm/experiment_grids/pricefm_stage_i_unresolved_median_rescue_20260623/manifest.csv`
- Run root:
  `application/data_local/pricefm/runs/pricefm_stage_i_unresolved_median_rescue_20260623`

Launch:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_i_unresolved_median_rescue_20260623.yaml \
  --priorities 0,1,2 \
  --experiment-jobs 20 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run false
```

Results:

- Experiments: `284/284`
- Window builds: `73/73`
- Exit status: `0`
- Wall time: `6:39:45`
- Max RSS: `1,780,072 KB`
- Run-root size after cleanup discipline: `11G`
- R binary artifacts: `0`

Best median rescue candidates by test AQL included:

| region | fold | best experiment | method | test AQL |
|---|---:|---|---|---:|
| AT | 3 | `stagei_at_f3_graphd2_alpha_low` | `qdesn_exal_rhs_ns_exact_chunked` | 8.8598 |
| BE | 3 | `stagei_be_f3_graphd1_input_low` | `qdesn_exal_rhs_ns_exact_chunked` | 6.9599 |
| FI | 1 | `stagei_fi_f1_graphd1_input_low` | `qdesn_exal_rhs_ns_exact_chunked` | 12.9327 |
| HU | 2 | `stagei_hu_f2_graphd2_input_high` | `qdesn_al_rhs_ns_exact_chunked` | 8.7953 |
| LT | 1 | `stagei_lt_f1_graphd1_input_low` | `qdesn_al_rhs_ns_exact_chunked` | 15.4276 |
| NL | 3 | `stagei_nl_f3_graphd1_input_low` | `qdesn_exal_rhs_ns_exact_chunked` | 7.8671 |
| RO | 3 | `stagei_ro_f3_graphd2_alpha_low` | `qdesn_al_rhs_ns_exact_chunked` | 10.8512 |
| SE_4 | 1 | `stagei_se4_f1_graphd1_input_low` | `qdesn_exal_rhs_ns_exact_chunked` | 9.0365 |
| SK | 3 | `stagei_sk_f3_graphd2_d3_compact` | `qdesn_exal_rhs_ns_exact_chunked` | 10.2832 |

## Median Closeout

Closeout output:

- `application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_median_rescue_closeout_20260623`

Decision counts:

| decision | count |
|---|---:|
| validation_candidate_audit_worse | 6 |
| robustness_candidate | 4 |
| keep_current | 3 |
| test_only_diagnostic | 2 |
| validation_overfit_warning | 2 |

Registry-level audit:

| registry scenario | mean test AQL | mean selection AQL |
|---|---:|---:|
| current authoritative | 10.6500 | 10.6856 |
| hypothetical validation-selected rescue | 10.7084 | 10.4553 |
| hypothetical robustness candidates only | 10.5855 | 10.6369 |

The validation-selected rescue was not promoted as a whole because it worsened
mean test AQL. Four candidates were queued for seed robustness:

- LT fold 1
- NL fold 3
- RO fold 3
- SE_4 fold 1

## Seed Robustness

Seedrob grid:

- Config:
  `application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_i_unresolved_seedrob_20260623.yaml`
- Run root:
  `application/data_local/pricefm/runs/pricefm_stage_i_unresolved_seedrob_20260623`
- Summary:
  `application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_seedrob_summary_20260623`

Launch:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_i_unresolved_seedrob_20260623.yaml \
  --experiment-jobs 12 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run false
```

Results:

- Experiments: `12/12`
- Exit status: `0`
- Wall time: `32:14`
- Max RSS: `1,766,432 KB`
- Run-root size after cleanup discipline: `474M`
- R binary artifacts: `0`

Seedrob gate:

- Minimum validation win rate: `1.0`
- Maximum mean test AQL delta: `0.0`
- Maximum single-seed test relative deterioration: `0.05`

| region | fold | validation win rate | mean test delta | action |
|---|---:|---:|---:|---|
| LT | 1 | 0.3333 | -1.3555 | keep current |
| NL | 3 | 0.3333 | -0.1125 | keep current |
| RO | 3 | 1.0000 | -0.6151 | queue quantile promotion |
| SE_4 | 1 | 0.0000 | -1.1406 | keep current |

Only RO fold 3 passed the strict seedrob gate. The median registry patch was:

- Output:
  `application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_seedrob_patched_registry_20260623`
- Patch rows: `1`
- Patched row: RO fold 3, `qdesn_exal_rhs_ns_exact_chunked`

## Seven-Quantile Promotion

Quantile grid:

- Config:
  `application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_i_unresolved_quantiles_20260623.yaml`
- Run root:
  `application/data_local/pricefm/runs/pricefm_stage_i_unresolved_quantiles_20260623`
- Quantiles: `0.10,0.25,0.45,0.50,0.55,0.75,0.90`
- Experiments: `7`

Launch:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_i_unresolved_quantiles_20260623.yaml \
  --experiment-jobs 7 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run false
```

Results:

- Experiments: `7/7`
- Exit status: `0`
- Wall time: `22:22`
- Max RSS: `1,261,696 KB`
- Run-root size after cleanup discipline: `293M`
- R binary artifacts: `0`

Panel summary:

- `application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_promoted_quantiles_summary_20260623`

Cached PriceFM comparison:

- PriceFM root:
  `application/data_local/pricefm/authoritative/pricefm_phase1_stage_e_full_panel_missing_paper_quantiles_20260619`
- Comparison output:
  `application/data_local/pricefm/authoritative/pricefm_phase1_cached_vs_stage_i_unresolved_promoted_quantiles_20260623`

RO fold 3 seven-quantile result:

| method | test AQL | test RMSE | delta vs PriceFM |
|---|---:|---:|---:|
| `pricefm_phase1_pretraining` | 8.5506 | 32.8421 | 0.0000 |
| `qdesn_exal_rhs_ns_exact_chunked` | 8.9837 | 33.1411 | +0.4331 |
| `qdesn_al_rhs_ns_exact_chunked` | 9.1179 | 33.1863 | +0.5673 |

Decision: local lags PriceFM by about `5.1%` on original-unit test AQL.
Therefore RO fold 3 remains a PriceFM fallback at the paper-quantile gate.

## Final Authoritative Registry

Frozen Stage-I decision output:

- `application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_quantile_decisions_20260623`

Final merged authoritative registry:

- `application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_i_unresolved_20260623`
- Registry id: `pricefm_authoritative_quantile_decisions_stage_i_unresolved_20260623`

Merged counts:

| decision class | count |
|---|---:|
| promoted local | 25 |
| close to PriceFM | 6 |
| PriceFM fallback | 11 |

Aggregate original-unit test AQL over the 42-row registry:

| quantity | value |
|---|---:|
| mean selected local AQL | 8.6322 |
| mean PriceFM AQL | 8.9598 |
| mean delta | -0.3276 |
| mean relative delta | -0.0278 |

## Validation Checks

Commands run during setup:

```sh
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/60_prepare_pricefm_stage_h_targeted_rescue.py \
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
  application/tests/test_pricefm_stage_h_targeted_rescue.py \
  application/tests/test_pricefm_graph_local_rescue_workflow.py -q
```

Final validation commands are repeated after this closeout note is added.

## Interpretation

Stage-I was useful but intentionally conservative:

1. A broad unresolved-case rescue grid found several median improvements.
2. Most apparent gains failed either test-audit discipline or seed robustness.
3. RO fold 3 was the only seedrob-stable median rescue.
4. RO fold 3 did not survive the seven-quantile PriceFM comparison, so no new
   local quantile promotion was added.
5. The final authoritative quantile registry remains essentially the Stage-H
   registry with an explicit Stage-I audit/provenance layer for RO fold 3.

## Next Step

Do not keep repeatedly rescuing the same unresolved set without changing the
information set. The next scientifically useful move is one of:

1. Expand to new region/fold coverage using the same staged median/seedrob/
   quantile-confirmation gates.
2. Add a new, clearly documented information-set variant such as richer graph
   neighbor inputs or horizon-aware features, then compare through the same
   frozen registry machinery.
3. Keep the current Stage-I authoritative registry fixed for reporting while
   planning the next batch separately.
