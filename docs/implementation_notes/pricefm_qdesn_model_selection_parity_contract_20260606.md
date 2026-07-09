# PriceFM Q-DESN Model-Selection Parity Contract

Date: 2026-06-06

## Purpose

This note defines the parity gate that must pass before the PriceFM median
selection workflow can be described as apples-to-apples with the package-level
Q-DESN model-selection interface.

The package selector is:

```text
exdqlm::qdesn_model_selection()
```

It is the authoritative generic Q-DESN model-selection entry point. The
PriceFM workflow remains article-specific because it uses a direct-horizon,
fold-aligned evaluation contract that the generic package selector does not yet
launch natively.

## Current Boundary

The current bridge is:

```text
application/scripts/pricefm/29_prepare_qdesn_model_selection_bridge.py
```

It writes package-v2-style candidate configs and compatibility reports, but
those configs are deliberately marked:

```text
package_launch_ready: false
```

This is the correct state. The bridge preserves candidate geometry and package
metadata, but it does not pretend the package v2 selector can already reproduce
PriceFM's direct-horizon fold scoring.

The new parity validator is:

```text
application/scripts/pricefm/30_validate_qdesn_model_selection_parity.py
```

It performs no refits. It validates existing bridge, registry, and comparison
artifacts.

## PriceFM Selection Target

The parity target is:

```text
region: DE_LU, or explicit future region
fold: explicit PriceFM fold
selection split: val
selection unit: original
selection metric: AQL
selection quantile: median first
evaluation horizons: 1:96
test split: audit only
```

The current model-selection methods are:

```text
qdesn_exal_rhs_ns_exact_chunked
qdesn_al_rhs_ns_exact_chunked
```

Both methods must have finite validation metrics for each selected region/fold.
If either method is missing, the registry is incomplete and must fail.

## Row Identity Contract

Fold-aligned PriceFM comparisons must align rows by:

```text
split
origin_market_time
response_market_time
horizon
tau
```

For a complete paper-quantile comparison, every selected method must share the
same aligned row universe. Every origin must cover exactly the configured
horizon set. For the current PriceFM fold comparison this is `1:96`.

The external `phase1_pretraining.csv` row is not a fold-aligned benchmark. It
may be shown as region-level context, but the authoritative benchmark is the
locally regenerated fold-aligned PriceFM Phase-I output.

## Parity Outputs

The validator writes ignored local outputs under:

```text
application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_parity_de_lu_folds23_20260606/
```

Required files:

```text
parity_bridge_config.csv
parity_candidate_match.csv
parity_method_coverage.csv
parity_selection_match.csv
parity_row_identity.csv
parity_row_alignment.csv
parity_metric_contract.csv
qdesn_model_selection_parity_report.md
summary.json
```

## Acceptance Criteria

The parity gate passes only if:

- bridge configs remain blocked from package launch;
- bridge candidate IDs match the registry candidate IDs by region/fold;
- selected registry winners are present in the bridge candidate universe;
- selection rule is validation/original/AQL;
- all requested Q-DESN methods have finite validation metrics;
- fold-aligned comparison metrics contain the local PriceFM baseline and Q-DESN
  methods;
- aligned prediction rows cover the expected horizon set;
- duplicate method/split/origin/response/horizon/tau rows are absent;
- test metrics are recorded only as audit fields;
- generated outputs remain in ignored local paths.

## Command

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/30_validate_qdesn_model_selection_parity.py \
  --bridge-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_bridge_de_lu_folds23_20260606 \
  --registry-dir application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605 \
  --comparison-dir-template 'application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold{fold}_followup_20260605' \
  --output-dir application/data_local/pricefm/authoritative/pricefm_qdesn_model_selection_parity_de_lu_folds23_20260606 \
  --regions DE_LU \
  --folds 2,3 \
  --expected-horizons 1:96
```

## What This Does Not Do

This parity gate does not:

- launch package model selection;
- refit any PriceFM model;
- replace `20_select_pricefm_desn_median_specs.py`;
- make package v2 direct-horizon aware;
- use test AQL for selection.

## Next Decision

After parity passes, the safest next step is to keep the PriceFM registry as an
article-side scoring adapter while adding package-compatible metadata to its
outputs. A later package-side extension can add a true direct-horizon scorer,
but only after this contract remains stable across more regions/folds.
