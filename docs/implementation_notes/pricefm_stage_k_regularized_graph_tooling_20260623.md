# PriceFM Stage-K Regularized Graph Tooling

Date: 2026-06-23

## Purpose

Stage K follows the Stage-J information-set rescue closeout.  Stage J showed
that raw graph-khop input expansion can produce validation improvements that
are not seed-stable.  Stage K therefore adds a narrower, regularized graph
path before any further promotion:

- preserve the target region's raw local input channels;
- add compact neighbor summaries rather than raw neighbor concatenation;
- require multi-seed validation stability before closeout;
- keep test and cached PriceFM metrics as audit-only fields.

This stage is tooling only.  It does not promote any model and it does not
launch the full median screen automatically.

## New Feature Policies

Implemented in `application/scripts/pricefm/pricefm_desn_adapter.py`.

| policy | Input target | Neighbor information | Degree-zero behavior |
|---|---|---|---|
| `graph_summary_mean` | target raw lag/lead channels | neighbor mean channels | equals target-only |
| `graph_summary_mean_std` | target raw lag/lead channels | neighbor mean and population-SD channels | equals target-only |

Existing policies remain unchanged:

- `target_only`
- `graph_khop`

The summary policies use the released PriceFM graph through
`pricefm_graph.graph_scope_manifest()`.  The adapter manifest records the graph
degree, active regions, source-window hashes, and `neighbor_summary` metadata.

## New Scripts

| script | Role |
|---|---|
| `62_summarize_pricefm_multiseed_median_screen.py` | Summarize a materialized multi-seed median screen.  Validation gates decide whether a geometry can enter closeout; test metrics remain audit-only. |
| `63_summarize_pricefm_stage_k_instability.py` | Consolidate Stage-J closeout and seed-robustness outputs into a Stage-K instability taxonomy. |
| `64_prepare_pricefm_stage_k_regularized_graph_pilot.py` | Generate a compact graph-summary median grid from the Stage-K diagnostics. |

## Generated Ignored Artifacts

Diagnostics:

```text
application/data_local/pricefm/authoritative/pricefm_stage_k_instability_diagnostics_20260623/
```

Prepared grid and dry-run status:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_k_regularized_graph_20260623.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_k_regularized_graph_20260623/
application/data_local/pricefm/authoritative/pricefm_stage_k_regularized_graph_plan_20260623/
```

Summary-smoke output:

```text
application/data_local/pricefm/authoritative/pricefm_stage_k_regularized_graph_multiseed_summary_smoke_20260623/
```

These paths are under ignored `application/data_local/pricefm/` storage.

## Dry-Run Result

The Stage-K preparer generated:

- source rows: `8`
- median experiments: `87`
- feature-policy counts:
  - `graph_summary_mean`: `39`
  - `graph_summary_mean_std`: `24`
  - `target_only`: `24`
- dry-run launch status:
  - experiment rows: `87 planned`
  - window-build rows: `8 planned`

No model fits were launched in this implementation pass.

## Commands

Rebuild Stage-K diagnostics:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/63_summarize_pricefm_stage_k_instability.py
```

Rebuild the Stage-K compact graph-summary grid:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/64_prepare_pricefm_stage_k_regularized_graph_pilot.py
```

Dry-run the generated grid:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_k_regularized_graph_20260623.yaml \
  --priorities 0 \
  --experiment-jobs 2 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run true
```

After a real launch, summarize using the materialized manifest:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/62_summarize_pricefm_multiseed_median_screen.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_stage_k_regularized_graph_20260623/manifest.csv \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_priority0_closeout_20260623/rescue_closeout_decisions.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_k_regularized_graph_multiseed_summary_20260623
```

Use the Stage-J closeout registry as the current median baseline for this
manifest.  The broader Stage-I authoritative quantile registry contains
incomplete median comparison fields for some Stage-K rows.

## Validation

Focused tests run:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_desn_adapter_graph_summary.py \
  application/tests/test_pricefm_stage_k_summarizers.py
```

Result: `9 passed`.

Adjacent regressions run:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_desn_adapter_graph_khop.py \
  application/tests/test_pricefm_graph.py \
  application/tests/test_pricefm_stage_j_information_set_rescue.py
```

Result: `11 passed`.

## Launch Criteria

Before launching the Stage-K grid, confirm:

- no unrelated PriceFM/GloFAS jobs would be harmed by the requested core count;
- generated Stage-K grid still has expected experiment count and policies;
- current registry path is the intended authoritative comparison baseline;
- fit binaries remain disposable after metrics/figures are produced.

After launch, do not promote directly from test performance.  Use
`62_summarize_pricefm_multiseed_median_screen.py` to queue only validation-stable
candidates for a separate closeout.
