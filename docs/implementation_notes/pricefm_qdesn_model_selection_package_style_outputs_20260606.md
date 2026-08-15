# PriceFM Q-DESN Package-Style Selection Outputs

Date: 2026-06-06

## Scope

This stage regularizes the article-side PriceFM median selection workflow with
package-style artifacts that mirror the authoritative package selector surface:

```text
exdqlm::qdesn_model_selection()
```

It does not launch new model fits and it does not claim that the generic package
selector is ready to run PriceFM folds. The current PriceFM workflow still uses
article-side direct-horizon adapters and fold-level 1:96 horizon scoring, so the
package bridge remains explicitly blocked for launch.

## Implemented Files

Article-side selector:

```text
application/scripts/pricefm/20_select_pricefm_desn_median_specs.py
```

New package-style outputs written beside the existing median registry:

```text
model_selection_candidate_metrics.csv
model_selection_method_coverage.csv
model_selection_winners.csv
model_selection_contract.json
model_selection_parity_summary.json
```

Bridge runner:

```text
application/scripts/pricefm/31_run_qdesn_model_selection_bridge.py
```

The runner can plan or execute:

1. package-style bridge config generation;
2. optional existing-artifact selection refresh;
3. optional parity validation;
4. optional PriceFM grid launch, only when explicitly enabled.

By default it writes a plan and does not launch fits.

## Contract

The target contract is:

```text
pricefm_direct_horizon_fold_aql
```

Every package-style output records:

- selector surface: `article_pricefm_artifact_registry`;
- package selector: `exdqlm::qdesn_model_selection`;
- package launch readiness: `false`;
- selection split/unit/metric;
- requested methods;
- candidate id and method id;
- validation-only selection and test-audit fields.

The package launch remains blocked because the generic package selector does not
yet encode the PriceFM direct-horizon adapter and fold-level 1:96 scoring
contract.

## Reproducibility Commands

Refresh the DE_LU folds 2/3 registry and package-style outputs:

```sh
python application/scripts/pricefm/20_select_pricefm_desn_median_specs.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --output-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605 \
  --regions DE_LU \
  --folds 2,3 \
  --priorities 0 \
  --selection-split val \
  --selection-unit original \
  --selection-metric AQL \
  --selection-methods qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked \
  --require-complete true \
  --expected-horizons 1:96
```

Plan the full bridge chain without launching fits:

```sh
python application/scripts/pricefm/31_run_qdesn_model_selection_bridge.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --bridge-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_bridge_de_lu_folds23_20260606 \
  --registry-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605 \
  --parity-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_parity_de_lu_folds23_20260606 \
  --regions DE_LU \
  --folds 2,3 \
  --priorities 0 \
  --execute false
```

Execute bridge, selection refresh, and no-refit parity validation:

```sh
python application/scripts/pricefm/31_run_qdesn_model_selection_bridge.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml \
  --bridge-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_bridge_de_lu_folds23_20260606 \
  --registry-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605 \
  --parity-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_parity_de_lu_folds23_20260606 \
  --comparison-dir-template 'application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold{fold}_followup_20260605' \
  --regions DE_LU \
  --folds 2,3 \
  --priorities 0 \
  --select-existing true \
  --validate-parity true \
  --execute true
```

## Validation

Required tests:

```sh
python -m pytest \
  application/tests/test_pricefm_median_selection_registry.py \
  application/tests/test_pricefm_qdesn_model_selection_bridge.py \
  application/tests/test_pricefm_qdesn_model_selection_parity.py \
  application/tests/test_pricefm_qdesn_model_selection_bridge_runner.py
```

The package selector itself remains validated in the shared package repo through:

```text
tests/testthat/test-qdesn-model-selection-authoritative.R
```

## Closeout Criteria

- Package-style selector outputs exist under ignored PriceFM local artifacts.
- The bridge runner plan says `will_launch_model_fits: false` unless a real
  grid launch is explicitly requested.
- The parity validator passes for the completed DE_LU folds 2/3 artifacts.
- No generated PriceFM artifacts are committed.
- No package APIs are changed in this article-side stage.

## Remaining Work

- Port the PriceFM direct-horizon fold scoring contract into a package-native
  model-selection backend if package launch parity becomes necessary.
- Use the current bridge/parity artifacts to drive the next fold/region
  comparison launch.
- Keep divide-and-combine and variational coreset work out of this PriceFM
  selection track.
