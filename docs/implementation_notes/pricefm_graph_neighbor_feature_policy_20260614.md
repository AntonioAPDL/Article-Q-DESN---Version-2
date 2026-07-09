# PriceFM Graph-Neighbor Feature Policy

Date: 2026-06-14

## Purpose

This note documents the first graph-neighbor extension for the Article
PriceFM DESN/Q-DESN workflow. The goal is to compare the existing local-only
Q-DESN baseline against a Phase-II-inspired information set that includes
PriceFM graph neighbors, while leaving the Normal-DESN/Q-DESN fitting engines
unchanged.

## Implemented Scope

- Added `application/scripts/pricefm/pricefm_graph.py`.
- Added `feature_policy: graph_khop` to the DESN adapter path.
- Preserved the existing `feature_policy: target_only` behavior.
- Added metadata propagation through grid generation, selection registry, and
  quantile-promotion helpers.
- Added a reusable graph-neighbor median grid preparer:
  `application/scripts/pricefm/37_prepare_pricefm_graph_neighbor_median_grid.py`.

## Contract

`target_only`:

- Uses the target region's lag and lead windows only.
- Keeps `input_scope = local_target_only`.
- Keeps `spatial_information_set = local_only_not_pricefm_graph`.

`graph_khop`:

- Uses the target region response path.
- Concatenates lag and lead covariates from the target plus k-hop graph
  neighbors.
- Uses the released PriceFM adjacency mirrored in `pricefm_graph.py`.
- Records `graph_degree`, `graph_source`, `graph_hash`, `active_regions`, and
  per-source window hashes in the adapter manifest.
- Keeps `lead_covariate_status = realized_ex_post`, matching the existing
  Article/PriceFM direct-horizon setup.

The feature policy changes the design matrix. It does not change the VB target,
priors, exact chunking semantics, warm starts, or model-fitting engines.

## First Launch Policy

The first launch should be a six-region median A/B grid generated from the
current local-only authoritative median registry:

```text
application/data_local/pricefm/authoritative/pricefm_region_panel_median_local_ar_closeout_20260613/merged_selection_registry.csv
```

Each graph-neighbor experiment clones the selected local-only geometry for its
region/fold and changes only the adapter feature policy to `graph_khop` with
`graph_degree = 1`.

## Validation

Focused tests cover:

- PriceFM graph k-hop ordering and hashing.
- Adapter graph-window concatenation and manifest metadata.
- `degree = 0` target-only-equivalent feature dimensionality.
- Full-run config propagation of `feature_policy` and spatial controls.
- Grid manifest propagation.
- Registry/quantile-promotion metadata propagation.
- Graph-neighbor grid generation from a median registry.

Fresh validation on 2026-06-14:

```text
application/data_local/pricefm/venv/bin/python -m pytest application/tests/test_pricefm*.py -q
141 passed
git diff --check passed
```

One-cell real-data graph smoke:

```text
config: application/data_local/pricefm/configs/pricefm_desn_model_graph_khop_smoke_20260614.yaml
run root: application/data_local/pricefm/runs/pricefm_graph_khop_smoke_20260614
region/fold: DE_LU / 1
feature_policy: graph_khop
graph_degree: 1
active regions: DE_LU, AT, BE, CZ, DK_1, DK_2, FR, NL, NO_2, PL, SE_4
train rows: 400
train features: 162
status: completed
wall time: 0:28.33
max RSS: 1346756 KB
exact chunking gate: passed
heavy artifacts after cleanup: 0 .rds/.rda/.RData/X_*.csv files
```

## Out Of Scope

- Changing Q-DESN or Normal-DESN inference code.
- PriceFM neural Phase-II training.
- All-region tensor gating inside Q-DESN.
- Promotion to seven paper quantiles before the median A/B gate is inspected.
- Scaling to all 38 regions before the six-region gate is positive.

## Reproducibility

All launch configs and large outputs remain under ignored
`application/data_local/pricefm/` paths. The tracked source code records the
feature-policy contract and tests; ignored launch configs record the exact grid
ids, roots, and command-line choices used for each run.
