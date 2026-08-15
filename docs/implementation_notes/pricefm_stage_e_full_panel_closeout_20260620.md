# PriceFM Stage-E Full-Panel Quantile Closeout

Date: 2026-06-20

This note closes the Stage-E full-panel quantile completion pass for the
PriceFM local DESN/Q-DESN comparison. Stage E filled the seven-paper-quantile
evaluation gap for median-selected region/folds that had not yet been frozen by
Stage C or the Stage-D graph-rescue patch.

## Repo State

- Article repo: `/data/jaguir26/local/src/Article-Q-DESN`
- Branch: `application-ensemble-likelihood-redesign`
- Generated artifacts are under ignored `application/data_local/pricefm/...`
  paths.
- No Overleaf/main edits were made.

## Inputs

Authoritative median registry:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_all_median_selection_20260618/median_selection_registry.csv
```

Frozen decision sources already available before Stage E:

```text
application/data_local/pricefm/authoritative/pricefm_stage_c_priority1_green_quantile_decisions_20260618/stage_c_quantile_decision_registry.csv
application/data_local/pricefm/authoritative/pricefm_stage_c_completion_quantile_decisions_20260618/stage_c_quantile_decision_registry.csv
application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_quantile_decisions_20260619/stage_c_quantile_decision_registry.csv
```

Stage-E missing-row plan:

```text
application/data_local/pricefm/authoritative/pricefm_stage_e_full_panel_quantile_completion_plan_20260619/stage_e_missing_quantile_registry.csv
```

## Commands

Stage-E completion audit:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/56_prepare_pricefm_stage_e_quantile_completion.py \
  --median-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_c_all_median_selection_20260618/median_selection_registry.csv \
  --decision-source stage_c_priority1_green=application/data_local/pricefm/authoritative/pricefm_stage_c_priority1_green_quantile_decisions_20260618/stage_c_quantile_decision_registry.csv \
  --decision-source stage_c_completion=application/data_local/pricefm/authoritative/pricefm_stage_c_completion_quantile_decisions_20260618/stage_c_quantile_decision_registry.csv \
  --decision-source stage_d_graph_rescue=application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_quantile_decisions_20260619/stage_c_quantile_decision_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_e_full_panel_quantile_completion_plan_20260619
```

Stage-E decision freeze after the local and PriceFM comparisons were complete:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/53_freeze_pricefm_stage_c_quantile_decisions.py \
  --comparison-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_e_full_panel_missing_paper_quantiles_20260619 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_e_full_panel_missing_quantile_decisions_20260619 \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_e_full_panel_quantile_completion_plan_20260619/stage_e_missing_quantile_registry.csv \
  --pricefm-method pricefm_phase1_pretraining \
  --split test \
  --unit original \
  --metric AQL \
  --close-rel-threshold 0.05 \
  --grid-id pricefm_stage_e_full_panel_missing_paper_quantiles_20260619 \
  --notes "Stage-E full-panel completion freeze for the 24 median-selected region/folds not yet covered by Stage-C/Stage-D seven-quantile decisions."
```

Authoritative Stage-E merge:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/57_freeze_pricefm_authoritative_quantile_decisions.py \
  --median-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_c_all_median_selection_20260618/median_selection_registry.csv \
  --decision-source stage_c_priority1_green=application/data_local/pricefm/authoritative/pricefm_stage_c_priority1_green_quantile_decisions_20260618/stage_c_quantile_decision_registry.csv \
  --decision-source stage_c_completion=application/data_local/pricefm/authoritative/pricefm_stage_c_completion_quantile_decisions_20260618/stage_c_quantile_decision_registry.csv \
  --decision-source stage_d_graph_rescue=application/data_local/pricefm/authoritative/pricefm_stage_d_graph_median_rescue_quantile_decisions_20260619/stage_c_quantile_decision_registry.csv \
  --decision-source stage_e_full_panel_completion=application/data_local/pricefm/authoritative/pricefm_stage_e_full_panel_missing_quantile_decisions_20260619/stage_c_quantile_decision_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_e_20260619 \
  --registry-id pricefm_authoritative_quantile_decisions_stage_e_20260619
```

## Results

Stage-E missing panel:

| item | value |
|---|---:|
| evaluated region/folds | 24 |
| local wins | 1 |
| local close to PriceFM | 6 |
| PriceFM fallbacks | 17 |
| mean local AQL | 11.8631 |
| mean PriceFM AQL | 10.1931 |
| mean delta AQL | 1.6700 |
| mean relative delta | 0.1847 |

Authoritative 42-row registry after Stage E:

| item | value |
|---|---:|
| region/folds | 42 |
| local wins | 10 |
| local close to PriceFM | 9 |
| PriceFM fallbacks | 23 |
| mean local AQL | 9.8863 |
| mean PriceFM AQL | 8.9598 |
| mean delta AQL | 0.9265 |
| mean relative delta | 0.1019 |

Authoritative output:

```text
application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_e_20260619/authoritative_quantile_decision_registry.csv
```

## Metadata Hardening

The Stage-D graph-rescue rows are now explicitly marked as graph-khop rows in
the authoritative registry. The hardened decision-freeze path preserves and
normalizes:

- `feature_policy`
- `input_scope`
- `output_scope`
- `lead_covariate_status`
- `spatial_information_set`
- `graph_degree`
- `graph_source`
- `graph_hash`

The regenerated authoritative registry has:

| decision source | feature policy | spatial information set | rows |
|---|---|---|---:|
| Stage-C completion | target_only | local_only_not_pricefm_graph | 6 |
| Stage-C priority-1 green | target_only | local_only_not_pricefm_graph | 5 |
| Stage-D graph rescue | graph_khop | pricefm_released_graph_khop | 7 |
| Stage-E completion | target_only | local_only_not_pricefm_graph | 24 |

This matters because graph-khop rows are not apples-to-apples local target-only
models. They use the released PriceFM graph as realized ex-post covariate input
and must be labeled that way in any paper-facing comparison.

## Validation

Focused tests run after the metadata fixes:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_c_quantile_decisions.py \
  application/tests/test_pricefm_stage_e_quantile_completion.py \
  application/tests/test_pricefm_stage_d_graph_rescue.py \
  application/tests/test_pricefm_graph_neighbor_closeout.py \
  application/tests/test_pricefm_graph_neighbor_grid.py \
  application/tests/test_pricefm_graph.py \
  application/tests/test_pricefm_desn_adapter_graph_khop.py \
  application/tests/test_pricefm_stage_f_graph_rescue.py -q
```

The Stage-E and Stage-F tests also check precedence, coverage, and graph
metadata propagation.

## Decision

Stage-E is closed. The authoritative 42-row registry should be treated as the
current local-vs-PriceFM decision freeze until a later graph-informed rescue
stage is explicitly promoted and re-frozen.
