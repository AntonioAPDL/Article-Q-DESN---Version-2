# Normal DESN Warm-Start Stage

Date: 2026-05-29

## Scope

This note records the implemented Normal DESN warm-start stage. The goal was to
regularize Normal DESN with the Q-DESN reproducibility and initialization
ecosystem without adding unnecessary batching algorithms to the closed-form
Gaussian ridge readout.

Normal DESN remains a conditional-mean Gaussian readout. The warm-start state
is a workflow artifact for initializing downstream AL/exAL Q-DESN VB or MCMC
fits; it is not a new posterior target.

## Package Commits

Package repo:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
branch: validation/shared-fitforecast-v2-1.0.0
52ea0b0 Add Normal DESN warm-start states
9f1c32d Cover RHS Normal warm-start labels
```

## Implemented API

Package file:

```text
R/qdesn_normal_warm_start.R
```

Exported helpers:

```text
qdesn_normal_make_warm_start()
qdesn_normal_validate_warm_start()
qdesn_normal_warm_start_to_vb_init()
qdesn_normal_warm_start_to_mcmc_init()
```

The implementation accepts `qdesn_normal_fit` objects and
`normal_desn_readout` objects when the design matrix is available. It records
beta moments, omega2 moments, prior metadata, target labels, design hashes,
feature-setting hashes, package provenance, and exact/chunked/approximate
status.

## Target Labels

The warm-start state preserves the source model label:

```text
normal_scaled_ridge_exact        -> exact
normal_scaled_ridge_exact_chunked -> exact_chunked
normal_rhs_vb_approx             -> approximate_vb
normal_rhs_ns_vb_approx          -> approximate_vb
```

Approximate Normal RHS/RHS_NS warm starts are allowed as initialization
sources, but they are not relabeled as exact Gaussian conjugate posterior
states.

## Validation

Focused package tests:

```text
test-qdesn-normal-warm-start.R: 36 pass
test-qdesn-normal.R: 144 pass
test-qdesn-normal-init-comparison.R: 9 pass
test-qdesn-vb-warm-start.R: 39 pass
test-qdesn-vb-batching-modes.R: 42 pass
focused total: 270 pass, 0 fail
```

The warm-start tests cover:

- exact scaled-ridge state creation;
- exact-chunked scaled-ridge labels;
- RHS/RHS_NS approximate labels;
- Q-DESN feature hash validation;
- `saveRDS()` / `readRDS()` round trip;
- design hash mismatch failures;
- feature-setting hash mismatch failures;
- strict package SHA mismatch failures;
- covariance positive-definite validation;
- omega2 state validation;
- VB and MCMC initializer conversion metadata.

## Real Source Initialization Gate

The Normal initialization comparison harness now validates serialized
warm-start states before converting them into AL/exAL initializers.

Command:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/usr/bin/time -v -o results/normal_desn_init_comparison_20260529/time_warm_start.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_normal_desn_init_comparison_20260529.R \
  --output-dir results/normal_desn_init_comparison_20260529 \
  --seed 20260529 \
  --D 1 \
  --n 5 \
  --m 1 \
  --washout 25 \
  --max-iter 15
```

Result:

```text
package_head: 9f1c32d
package_dirty: FALSE
source: fit_input_lastTT500 Gaussian median source
all finite: TRUE
elapsed wall time: 0:39.63
max RSS: 514984 KB
```

Warm-start rows written by the harness:

| Warm Start | Normal Target | Exact Status | Prior | Beta Dim |
|---|---|---|---|---:|
| normal_scaled_ridge | normal_scaled_ridge_exact | exact | scaled_ridge | 6 |
| normal_rhs_ns_vb | normal_rhs_ns_vb_approx | approximate_vb | rhs_ns | 6 |

## Files Changed

Package:

```text
R/qdesn_normal_warm_start.R
NAMESPACE
man/qdesn_normal.Rd
scripts/run_normal_desn_init_comparison_20260529.R
tests/testthat/test-qdesn-normal-warm-start.R
```

Article docs:

```text
docs/implementation_notes/normal_desn_warm_start_contract_20260529.md
docs/implementation_notes/normal_desn_qdesn_method_availability_20260529.md
docs/implementation_notes/normal_desn_initialization_comparison_20260529.md
docs/implementation_notes/normal_qdesn_regularization_checklist_20260529.md
docs/implementation_notes/normal_desn_warm_start_stage_20260529.md
```

## Remaining Gates

Normal DESN still does not need stochastic or hybrid batching for scaled-ridge
readouts because the ridge path is exact closed form. The remaining Normal-side
future work is:

- exogenous/decomposition-aware Normal forecast contracts;
- Normal rolling/online companion only if a distinct Normal workflow need
  appears;
- article application adapters only after a concrete application use case is
  selected.

## Next Step

Run the final Normal/Q-DESN unified source-median comparison from package commit
`9f1c32d` or later and write:

```text
docs/implementation_notes/normal_qdesn_unified_source_median_comparison_20260529.md
```

Generated comparison outputs should remain under ignored package `results/`.
