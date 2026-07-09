# PriceFM Stage-C Priority-1 Green Quantile Decisions

Date: 2026-06-19

This note closes the Stage-C Priority-1 green seven-quantile run for the
local-only DESN/Q-DESN PriceFM comparison. The run used the frozen Priority-1
green registry and compared local model outputs against cached, fold-aligned
PriceFM Phase-I predictions.

## Scope

Registry:

`application/data_local/pricefm/authoritative/pricefm_stage_c_quantile_candidate_registry_20260618/stage_c_quantile_priority1_green_registry.csv`

Local grid:

`application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_priority1_green_paper_quantiles_20260618.yaml`

Local run root:

`application/data_local/pricefm/runs/pricefm_stage_c_priority1_green_paper_quantiles_20260618`

PriceFM Phase-I cache:

`application/data_local/pricefm/authoritative/pricefm_phase1_stage_c_priority1_green_20260618`

Local summary:

`application/data_local/pricefm/authoritative/pricefm_stage_c_priority1_green_paper_quantiles_summary_20260618`

PriceFM comparison:

`application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_c_priority1_green_paper_quantiles_20260618`

Frozen decisions:

`application/data_local/pricefm/authoritative/pricefm_stage_c_priority1_green_quantile_decisions_20260618`

The evaluated regions were `BE`, `NL`, `SE_4`, and `SI`, each on folds 1, 2,
and 3. Each region/fold used seven paper quantiles:

`0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`.

## Health Check

All local quantile cells completed.

| region | fold 1 | fold 2 | fold 3 |
|---|---:|---:|---:|
| BE | 7/7 | 7/7 | 7/7 |
| NL | 7/7 | 7/7 | 7/7 |
| SE_4 | 7/7 | 7/7 | 7/7 |
| SI | 7/7 | 7/7 | 7/7 |

The cached PriceFM Phase-I benchmark was complete for the same 12
region/fold rows. The comparison row-alignment panel had 60 method rows and no
prediction or response row mismatches.

The panel comparison status was fully completed:

| kind | status | count |
|---|---|---:|
| comparison | completed | 12 |

No error signatures were found in the Stage-C Priority-1 green run, summary, or
comparison logs during closeout.

## Commands

The local seven-quantile grid was launched with:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_c_priority1_green_paper_quantiles_20260618.yaml \
  --priorities 1 \
  --experiment-jobs 8 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true
```

The Stage-C PriceFM Phase-I cache was prepared with:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/54_prepare_pricefm_stage_c_benchmark_cache.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_c_quantile_candidate_registry_20260618/stage_c_quantile_priority1_green_registry.csv \
  --output-root application/data_local/pricefm/authoritative/pricefm_phase1_stage_c_priority1_green_20260618 \
  --jobs 4 \
  --resume true
```

The panel comparison and decision freeze used cached PriceFM predictions:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_c_quantile_candidate_registry_20260618/stage_c_quantile_priority1_green_registry.csv \
  --config application/config/pricefm_data_pipeline.yaml \
  --pricefm-root application/data_local/pricefm/authoritative/pricefm_phase1_stage_c_priority1_green_20260618 \
  --desn-root application/data_local/pricefm/authoritative/pricefm_stage_c_priority1_green_paper_quantiles_summary_20260618 \
  --output-root application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_c_priority1_green_paper_quantiles_20260618 \
  --methods pricefm_phase1_pretraining,qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked,normal_rhs_ns,normal_scaled_ridge \
  --quantiles 0.10,0.25,0.45,0.50,0.55,0.75,0.90 \
  --run-pricefm false \
  --dry-run false

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/53_freeze_pricefm_stage_c_quantile_decisions.py \
  --comparison-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_c_priority1_green_paper_quantiles_20260618 \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_c_quantile_candidate_registry_20260618/stage_c_quantile_priority1_green_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_c_priority1_green_quantile_decisions_20260618 \
  --grid-id pricefm_stage_c_priority1_green_quantile_decisions_20260618
```

Note: the panel wrapper produced valid comparison outputs. For two summary
cells, the per-region summary command was rerun directly after the wrapper
stopped emitting output. The generated panel summary files were then assembled
from the completed per-region outputs. The direct reruns used the same grid
configuration, region, fold, and `--require-complete true` gate.

## Macro Metrics

Original-unit test AQL over all 12 region/fold rows:

| method | mean AQL |
|---|---:|
| pricefm_phase1_pretraining | 7.150855 |
| qdesn_al_rhs_ns_exact_chunked | 7.888203 |
| qdesn_exal_rhs_ns_exact_chunked | 7.894583 |
| normal_rhs_ns | 9.206640 |
| normal_scaled_ridge | 41.583257 |

The best local method per region/fold averaged `7.844993` AQL. PriceFM
Phase-I averaged `7.150855` AQL on the same rows. The mean local-minus-PriceFM
delta was `0.694138`, or about `10.21%` relative to PriceFM.

## Frozen Decisions

| region | fold | best local method | local AQL | PriceFM AQL | delta | decision |
|---|---:|---|---:|---:|---:|---|
| BE | 1 | qdesn_al_rhs_ns_exact_chunked | 5.669390 | 5.835216 | -0.165825 | promote local |
| BE | 2 | qdesn_al_rhs_ns_exact_chunked | 6.902659 | 6.496657 | 0.406002 | prefer PriceFM |
| BE | 3 | qdesn_exal_rhs_ns_exact_chunked | 6.195295 | 5.293482 | 0.901813 | prefer PriceFM |
| NL | 1 | qdesn_al_rhs_ns_exact_chunked | 8.442895 | 7.242156 | 1.200740 | prefer PriceFM |
| NL | 2 | qdesn_al_rhs_ns_exact_chunked | 9.321974 | 7.060519 | 2.261456 | prefer PriceFM |
| NL | 3 | qdesn_al_rhs_ns_exact_chunked | 8.391623 | 6.411704 | 1.979920 | prefer PriceFM |
| SE_4 | 1 | qdesn_exal_rhs_ns_exact_chunked | 8.482355 | 7.702406 | 0.779949 | prefer PriceFM |
| SE_4 | 2 | qdesn_exal_rhs_ns_exact_chunked | 7.680881 | 7.959831 | -0.278950 | promote local |
| SE_4 | 3 | qdesn_exal_rhs_ns_exact_chunked | 8.133776 | 8.038824 | 0.094952 | close local loss |
| SI | 1 | qdesn_exal_rhs_ns_exact_chunked | 7.379366 | 7.060912 | 0.318454 | close local loss |
| SI | 2 | qdesn_al_rhs_ns_exact_chunked | 8.663244 | 8.658366 | 0.004877 | close local loss |
| SI | 3 | qdesn_al_rhs_ns_exact_chunked | 8.876458 | 8.050191 | 0.826267 | prefer PriceFM |

Decision counts:

| decision | count |
|---|---:|
| stage_c_confirmed_local_win | 2 |
| stage_c_local_close_to_pricefm | 3 |
| stage_c_pricefm_fallback | 7 |

## Interpretation

The local DESN/Q-DESN stack is materially better than the internal naive and
normal-DESN baselines, but it does not yet beat PriceFM Phase-I on the full
Priority-1 green panel. The useful signal is local and heterogeneous:

- `BE` fold 1 and `SE_4` fold 2 are confirmed local wins.
- `SE_4` fold 3, `SI` fold 1, and `SI` fold 2 are close enough to keep under
  review.
- `NL` remains the weakest region in this panel and should not be promoted
  without richer features or a better local specification.
- `normal_rhs_ns` is useful as a sanity baseline, but the promoted/close local
  candidates are all Q-DESN RHS_NS.
- `normal_scaled_ridge` is not competitive in this gate.

The result supports the local registry design: promotion should stay
region/fold-specific rather than global.

## Recommended Next Plan

1. Treat the two confirmed local wins as promoted Stage-C candidates for the
   current local-only setup.
2. Keep the three close local losses in a targeted review queue. They are the
   best candidates for a richer local input experiment.
3. For the seven fallback rows, keep PriceFM Phase-I as the current reference
   until the local model receives more information or a better specification.
4. Do not broaden blindly. The next scientific experiment should test whether
   adding graph-neighbor or nearby-region covariates narrows the gap on
   close/fallback rows, especially `NL` and `SI`.
5. Keep exact-chunked Q-DESN RHS_NS as the main local quantile model family.
   Do not promote normal scaled ridge, and keep normal RHS_NS as a diagnostic
   baseline.
6. Preserve the generated decision registries and comparison figures under
   `application/data_local/pricefm/authoritative`; commit only scripts, tests,
   and documentation.

## Closeout Artifacts

Important generated outputs:

- `stage_c_quantile_decision_registry.csv`
- `stage_c_quantile_promoted_local_registry.csv`
- `stage_c_quantile_close_registry.csv`
- `stage_c_quantile_pricefm_fallback_registry.csv`
- `stage_c_quantile_horizon_group_diagnostics.csv`
- `stage_c_quantile_decision_report.md`

These are intentionally generated local artifacts and are not tracked by git.
