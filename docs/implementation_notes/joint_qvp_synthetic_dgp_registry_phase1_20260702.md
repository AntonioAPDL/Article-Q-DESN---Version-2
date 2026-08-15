# Joint-QVP Synthetic DGP Registry Phase 1

Date: 2026-07-02  
Scope: Phase 1 fixture layer for the joint multi-quantile QVP validation
study. This note documents registry and fixture materialization only; it does
not report final fit or forecast validation results.

## Purpose

The joint-QVP validation study needs a source-of-truth synthetic data layer
before adding VB, MCMC, and rolling-origin forecast runners. Phase 1 implements
that layer as a versioned DGP registry plus a deterministic materialization
script.

The registry is intentionally separate from TT500, GloFAS, and PriceFM
workstreams. It does not change article tables or application outputs.

## Registry

Versioned registry:

```text
application/config/joint_qvp_synthetic_dgp_registry_phase1.csv
```

Required schema:

- `registry_version`
- `enabled`
- `scenario_id`
- `scenario_class`
- `distribution_family`
- `dynamics_class`
- `tau_grid`
- `simulated_length`
- `washout_length`
- `train_length`
- `test_length`
- `seed`
- `truth_quantile_method`
- distribution parameters
- dynamics parameters
- `notes`

The Phase 1 registry uses the seven-level tau grid

```text
0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95
```

and contiguous splits where

```text
simulated_length = washout_length + train_length + test_length.
```

The current registry has three bridge scenarios and six stress scenarios:

- `normal_bridge`
- `laplace_bridge`
- `gaussian_mixture_bridge`
- `student_t_location_scale`
- `asymmetric_laplace_tail`
- `heteroskedastic_seasonal`
- `persistent_heavy_tail`
- `regime_shift`
- `nonlinear_reservoir_friendly`

Bridge scenarios preserve continuity with the article families. Stress
scenarios target the joint-QVP behavior that single-quantile validation cannot
fully test: heavy tails, asymmetric tails, heteroskedasticity, persistence,
regime change, nonlinear lag features, and simultaneous extreme quantiles.

## Implementation

Core helpers live in:

```text
application/R/joint_qvp_qdesn.R
```

Main entry points:

- `app_joint_qvp_default_synthetic_dgp_registry_path()`
- `app_joint_qvp_load_synthetic_dgp_registry()`
- `app_joint_qvp_validate_synthetic_dgp_registry()`
- `app_joint_qvp_fixture_from_synthetic_dgp_registry_row()`
- `app_joint_qvp_materialize_synthetic_dgp_registry()`

The simulator uses deterministic location-scale dynamics. For a scenario with
feature vector `Z_t`, location coefficients `beta_location`, scale
coefficients `beta_scale`, and standardized innovation distribution quantile
`q_tau`, the true conditional quantile is

```text
Q_tau(y_t | Z_t) =
  location_intercept + Z_t beta_location
  + (scale_intercept + Z_t beta_scale) q_tau.
```

This keeps the oracle quantile grid exact and compatible with joint-QVP fit
diagnostics. Gaussian-mixture quantiles use numerical inversion of the mixture
CDF; the other implemented families use analytic quantiles.

## Materialization

Command:

```sh
Rscript application/scripts/75_generate_joint_qvp_synthetic_dgp_registry.R
```

Default output:

```text
application/cache/joint_qvp_synthetic_dgp_registry_phase1_20260702/
```

Optional arguments:

```sh
Rscript application/scripts/75_generate_joint_qvp_synthetic_dgp_registry.R \
  --output-dir application/cache/custom_joint_qvp_registry \
  --registry application/config/joint_qvp_synthetic_dgp_registry_phase1.csv
```

The script writes:

- `frozen_registry.csv`
- `registry_validation.csv`
- `scenario_summary.csv`
- `observed_series.csv`
- `design_matrix.csv`
- `true_quantile_wide.csv`
- `true_quantile_long.csv`
- `split_metadata.csv`
- `dgp_parameters.csv`
- `crossing_summary.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

The manifest records SHA-256 hashes for every generated artifact except itself.
The provenance table records repo root, branch, head commit, git-status hash, R
version, and RNG kind.

## Validation Gates

Phase 1 hard-fails malformed fixture inputs:

- missing required registry columns;
- duplicate or empty scenario IDs;
- unsupported family or dynamics labels;
- invalid tau grids;
- invalid split lengths;
- nonpositive scale paths;
- nonfinite observations, features, or true quantiles;
- nonmonotone true quantiles;
- nonzero true crossing pairs;
- invalid Gaussian-mixture numerical quantiles.

The generated `registry_validation.csv` records pass/fail checks per scenario.
Any failure means the fixture layer is not eligible for Phase 2 fit validation.

## Boundary

This is Phase 1 only. It prepares reproducible synthetic fixtures and oracle
truth. It does not fit VB, run MCMC, score forecasts, or make article-level
performance claims.

The next stage should be Phase 2: adapt the existing joint-QVP fit-validation
runner so it consumes `frozen_registry.csv`, honors the washout/train/test
split, validates VB first, and adds selected VB-initialized MCMC references.
