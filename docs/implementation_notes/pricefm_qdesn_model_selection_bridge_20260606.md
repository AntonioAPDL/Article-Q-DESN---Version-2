# PriceFM Bridge To Authoritative Q-DESN Model Selection

Date: 2026-06-06

## Objective

Clarify how the PriceFM model-selection workflow should align with the package
`qdesn_model_selection()` API after the package consolidation pass.

## Current State

The package now has one authoritative public Q-DESN model-selection entry point:

```text
exdqlm::qdesn_model_selection()
```

The exported function dispatches to:

- v2 staged model selection for current configs with `model_selection$stages`;
- the legacy selector only for old configs with `model_selection$esn_space`.

The article-side PriceFM selector remains:

```text
application/scripts/pricefm/20_select_pricefm_desn_median_specs.py
application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py
```

These scripts are not a second generic Q-DESN model-selection engine. They are a
PriceFM-specific artifact registry and promotion adapter.

This pass added the dry-run bridge:

```text
application/scripts/pricefm/29_prepare_qdesn_model_selection_bridge.py
application/tests/test_pricefm_qdesn_model_selection_bridge.py
```

The bridge materializes package-v2-style candidate configs from PriceFM
experiment-grid rows and writes an explicit compatibility report. It never
launches fits.

## Why The PriceFM Adapter Still Exists

The current PriceFM workflow selects among completed experiment cells. It must
respect article-specific details that the generic package selector does not yet
fully encode:

- region/fold scope;
- generated PriceFM window/config paths;
- validation-only median selection;
- test metrics as audit fields;
- promoted paper-quantile materialization;
- fold-aligned PriceFM benchmark comparison;
- horizon-block diagnostics.

Therefore the correct near-term architecture is:

```text
package qdesn_model_selection()
  authoritative fit-selection API

article PriceFM selector
  thin artifact/registry adapter for completed PriceFM runs
```

## Migration Plan

Use the package selector as the source of truth for new PriceFM searches only
after adding a package-compatible PriceFM configuration bridge.

Checklist:

- Encode current learned candidate spaces:
  - Q-DESN AL RHS_NS exact chunked;
  - Q-DESN exAL RHS_NS exact chunked;
  - median-first selection;
  - promoted quantile follow-up.
- Preserve candidate geometry in package-v2 candidate-list form:
  `D`, `n`, `n_tilde`, `m`, `alpha`, `rho`, and seed.
- Record PriceFM-only geometry as candidate metadata:
  `feature_map`, `feature_dim`, `projection_scale`, `input_scale`,
  `state_output`, and rationale.
- Preserve the current PriceFM selection rule:
  validation AQL on original scale; test AQL is audit only.
- Add horizon-aware scoring or a documented approximation if the package
  selector cannot yet represent the PriceFM 1:96 horizon evaluation exactly.
- Keep generated outputs in ignored `application/data_local/pricefm/...` paths.
- Keep compact tracked snapshots under `docs/implementation_notes/`.

## Stop Gates

- Do not replace `20_select_pricefm_desn_median_specs.py` until package
  selection can reproduce a completed DE_LU fold registry.
- Do not select on test AQL.
- Do not use the external region-level PriceFM CSV as a fold-aligned benchmark.
- Do not drop the current registry/promotion outputs; they are the
  reproducibility surface for the completed PriceFM work.

## Dry-Run Command

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/29_prepare_qdesn_model_selection_bridge.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_bridge_de_lu_folds23_20260606 \
  --regions DE_LU \
  --folds 2,3 \
  --priorities 0 \
  --quantile 0.50
```

Expected outputs:

```text
bridge_manifest.csv
bridge_compatibility.csv
qdesn_model_selection_bridge_report.md
summary.json
configs/de_lu_fold2_qdesn_model_selection_v2_bridge.yaml
configs/de_lu_fold3_qdesn_model_selection_v2_bridge.yaml
```

The DE_LU folds 2/3 dry run was materialized locally under:

```text
application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_bridge_de_lu_folds23_20260606
```

It wrote two bridge configs and 125 candidate rows:

| Region | Fold | Candidate Rows | Launch Ready |
|---|---:|---:|---|
| DE_LU | 2 | 5 | false |
| DE_LU | 3 | 120 | false |

The generated configs must contain:

- `pipeline.profile = pricefm_bridge_dry_run`;
- `pipeline.pricefm_bridge_launch_ready = false`;
- `pricefm_bridge.package_launch_ready = false`;
- `model_selection$stages[[1]]$candidate_grid$candidates`;
- RHS_NS prior metadata with `shrink_intercept = false`.

## Validation

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_qdesn_model_selection_bridge.py \
  application/tests/test_pricefm_median_selection_registry.py -q
```

## Recommended Next Step

Implement the missing package-side PriceFM scoring adapter if we want package
`qdesn_model_selection()` to replace the article registry selector for future
PriceFM searches. That adapter must represent direct-horizon windows, fold
splits, validation-only AQL, and horizon-wise 1:96 evaluation before launch is
allowed.

Before any replacement, run the no-refit parity validator documented in:

```text
docs/implementation_notes/pricefm_qdesn_model_selection_parity_contract_20260606.md
```

The validator is:

```text
application/scripts/pricefm/30_validate_qdesn_model_selection_parity.py
```

It checks that the bridge candidate universe, PriceFM registry winners, method
coverage, fold-aligned row identity, and local PriceFM comparison artifacts
agree under the direct-horizon contract. Passing this gate means the bridge is
valid as a candidate/contract artifact; it does not make the package v2 selector
launch-ready for PriceFM yet.
