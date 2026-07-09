# PriceFM Stage-U Parity Audit

## Purpose

Stage U is a diagnostic-only audit of the PriceFM/Q-DESN comparison contract.
It was created after Stage-T concluded that more capacity or graph/local
screening would be premature.  The goal is to verify the boring but crucial
parts of the apples-to-apples setup before designing another model launch:
feature windows, scaling, raw-unit scoring, horizon diagnostics, and the
remaining conceptual mismatch between Q-DESN and PriceFM.

Stage U does not fit models, does not write launch grids, and does not mutate
the frozen Stage-M decision surface.

## Command

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/82_audit_pricefm_parity_contract.py \
  --force true
```

## Inputs

The audit reads the frozen Stage-M decision surface and the Stage-T next-stage
gate:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/current_decision_surface_table.csv
application/data_local/pricefm/authoritative/pricefm_stage_t_structural_diagnostics_20260629/summary.json
application/config/pricefm_data_pipeline.yaml
PRICEFM_DATA_PIPELINE_REPORT.md
application/data_local/pricefm/external/papers/pricefm_arxiv_2508.04875v4_20260508.txt
```

For each Stage-M row, it reads the selected run cell under that row's `run_dir`
and verifies the cell config, adapter manifest, feature manifest, raw/scaled
metric summaries, horizon-group metrics, model method summary, fold scaler
manifest, and fold/region window manifests.

## Outputs

Ignored local outputs are written under:

```text
application/data_local/pricefm/authoritative/pricefm_stage_u_parity_audit_20260629/
```

Main files:

```text
summary.json
stage_u_input_manifest.csv
stage_u_row_parity_matrix.csv
stage_u_window_contract.csv
stage_u_scaling_scoring_contract.csv
stage_u_horizon_gap_by_row.csv
stage_u_mechanism_decisions.csv
stage_u_paper_contract_signals.csv
stage_u_parity_audit_report.md
```

## Result

Stage U completed cleanly.

| Check | Result |
|---|---:|
| Stage-M rows audited | 42 |
| Hard parity failures | 0 |
| Target-only rows passing | 15 |
| Graph-input rows with conceptual warning | 27 |
| Row parity failures | 0 |
| All rows have raw-unit metrics | true |
| All rows have scaled metrics | true |
| All rows have horizon groups | true |
| All rows have window manifests | true |
| All folds have scaling manifests | true |

The audit confirms that the current selected Q-DESN runs use the intended
PriceFM data contract:

- lag features: `price`, `load`, `solar`, `wind`;
- lead features: `load`, `solar`, `wind`;
- label: `price`;
- lag window: 96 steps;
- forecast horizon: 96 steps;
- training boundary: contained half-open;
- validation/test boundary: operational half-open;
- market-time convention: `time_utc + 1 hour`;
- scaling: train-only, per-region separate `RobustScaler` transforms for
  `x = {load, solar, wind}` and `y = price`;
- scoring: original-unit test metrics are present for the selected method.

## Important Caveat

The graph-input Q-DESN rows pass the manifest checks but receive a conceptual
warning:

```text
graph_khop concatenates selected neighbor inputs for one target; it is not the
PriceFM joint multi-region graph-mask architecture
```

This is the key distinction.  Current Q-DESN comparisons are meaningful as
target-region forecasting models with either local or selected graph-neighbor
inputs, but they should not be described as a full replica of the PriceFM joint
graph architecture.

## Horizon Diagnostics

The largest selected-method horizon AQL ranges occur mostly in mid/late horizon
groups.  The top rows by horizon range were:

| Region | Fold | Delta AQL vs PriceFM | Worst horizon group | Horizon AQL range |
|---|---:|---:|---|---:|
| LT | 1 | 1.9907 | 49-72 | 10.2479 |
| DK_1 | 2 | -0.1886 | 49-72 | 9.8254 |
| EE | 3 | -2.4934 | 49-72 | 9.3198 |
| EE | 1 | -3.7870 | 49-72 | 8.8909 |
| EE | 2 | -0.9025 | 25-48 | 8.1887 |

This supports the Stage-R/T diagnosis: the next useful improvement is more
likely to come from a validation-only selection contract that accounts for
horizon structure than from another blind feature-capacity sweep.

## Mechanism Decisions

| Mechanism | Decision |
|---|---|
| Feature/window/scaling contract | pass |
| PriceFM graph-mask parity | partial, not equivalent |
| Horizon-aware selection contract | implement next |
| New blind capacity sweep | reject now |

## Next Stage

The recommended next stage is:

```text
horizon_aware_validation_contract_after_parity
```

That stage should operate on existing candidate rows first.  It should use
validation-only information to define a horizon-aware or multi-validation
selection rule, then retrospectively audit whether that rule would have reduced
the Stage-M/R/S/Q selection-transfer failures.  It should not use test metrics
for selection, and it should not launch a new model grid until the selection
contract is explicit and documented.

## Validation

Stage-U unit tests cover:

- output generation and diagnostic-only flags;
- Stage-T next-stage gate enforcement;
- duplicate Stage-M region/fold rejection;
- missing window manifests surfacing as row parity failures.

Run:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_u_parity_audit.py -q
```
