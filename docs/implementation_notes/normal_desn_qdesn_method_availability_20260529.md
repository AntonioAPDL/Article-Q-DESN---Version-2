# Normal DESN And Q-DESN Method Availability

Date: 2026-05-29

## Purpose

This note records the currently implemented Normal DESN tools alongside the
implemented Q-DESN AL/exAL tools. It is an availability matrix for examples
and validation scripts, not a claim that all rows target the same statistical
quantity.

Normal DESN targets the conditional mean under a Gaussian readout. Q-DESN
targets conditional quantiles under AL/exAL working likelihoods.

## Current Package Checkpoint

Package repo:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
branch: validation/shared-fitforecast-v2-1.0.0
latest Normal DESN checkpoint: 0f5d4f6 Fix Normal DESN comparison dirty-state metadata
latest Q-DESN extended-mode checkpoint: f0d45ea Extend Q-DESN VB comparison and subset modes
latest Normal warm-start checkpoint: 9f1c32d Cover RHS Normal warm-start labels
```

Article repo:

```text
/data/jaguir26/local/src/Article-Q-DESN
branch: application-ensemble-likelihood-redesign
```

## Availability Matrix

Status labels:

```text
implemented
implemented exact only
approximate implemented
workflow implemented
gated
not applicable
```

| Method | Target label | Unchunked | Exact chunked | Stochastic/hybrid | Forecast paths | Initializer |
|---|---|---|---|---|---|---|
| Normal DESN scaled ridge | conditional_mean_exact | implemented | implemented | gated | implemented narrow | workflow source with serialized warm-start |
| Normal DESN RHS/RHS_NS VB | conditional_mean_vb_approx | approximate implemented | gated | gated | implemented through fitted readout draws only for standard wrapper settings | workflow source with approximate serialized warm-start |
| Q-DESN AL ridge | quantile_full_data | implemented | implemented | approximate implemented | implemented | can receive Normal init |
| Q-DESN exAL ridge | quantile_full_data | implemented | implemented | hybrid approximate and diagonal covariance diagnostic implemented; pure stochastic still gated | implemented | can receive Normal init |
| Article GloFAS latent-path AL-VB | application AL target | implemented | implemented for fixed historical rows | gated | application-specific | not yet wired to Normal init |

## Normal DESN Implemented Surface

Implemented package API:

```text
normal_desn_fit()
qdesn_fit_normal()
normal_desn_posterior_draws()
normal_desn_posterior_predict()
predict_mu.qdesn_normal_fit()
posterior_predict.qdesn_normal_fit()
forecast_paths.qdesn_normal_fit()
qdesn_normal_to_vb_init()
qdesn_normal_to_mcmc_init()
qdesn_normal_make_warm_start()
qdesn_normal_validate_warm_start()
qdesn_normal_warm_start_to_vb_init()
qdesn_normal_warm_start_to_mcmc_init()
```

Implemented Normal readout modes:

```text
scaled_ridge exact Normal-inverse-gamma
scaled_ridge exact chunked Normal-inverse-gamma
RHS/RHS_NS approximate global VB
```

Implemented Normal comparison infrastructure:

```text
scripts/run_normal_desn_source_median_comparison_20260529.R
scripts/run_normal_desn_init_comparison_20260529.R
```

## Exact Versus Approximate Labels

Normal scaled ridge:

```text
target: conditional_mean
target_label: normal_scaled_ridge_exact
exact_status: exact
preserves_full_data_target: TRUE
```

Normal exact chunked scaled ridge:

```text
target: conditional_mean
target_label: normal_scaled_ridge_exact_chunked
exact_status: exact chunked
preserves_full_data_target: TRUE
```

Normal RHS/RHS_NS:

```text
target: conditional_mean
target_label: normal_rhs_vb_approx or normal_rhs_ns_vb_approx
exact_status: approximate VB
preserves_full_data_target: approximate variational target
```

Q-DESN AL/exAL:

```text
target: tau-specific conditional quantile
exact chunking: full-data equivalent
stochastic/hybrid AL: approximate
stochastic/hybrid exAL: gated unless separately implemented and tested
```

## Current Validation Notes

Normal exact chunking:

```text
docs/implementation_notes/normal_desn_exact_chunked_stage_20260529.md
```

Normal source-median comparison:

```text
docs/implementation_notes/normal_desn_source_median_comparison_20260529.md
```

Normal initialization comparison:

```text
docs/implementation_notes/normal_desn_initialization_comparison_20260529.md
```

Normal warm-start metadata:

```text
docs/implementation_notes/normal_desn_warm_start_contract_20260529.md
```

Normal recursive forecasts:

```text
docs/implementation_notes/normal_desn_recursive_forecast_stage_20260529.md
```

## Gated Work

Still gated for Normal DESN:

- RHS/RHS_NS exact chunking;
- stochastic/hybrid Normal batching;
- exogenous/decomposition-aware Normal forecast paths;
- Normal rolling/online companion;
- Normal posterior-as-prior;
- Normal method integration into article GloFAS application configs.

Still gated for Q-DESN:

- pure stochastic exAL;
- exAL RHS/RHS_NS diagonal covariance;
- stochastic or hybrid diagonal covariance;
- RHS/RHS_NS or exAL subset targets;
- article-side stochastic/hybrid GloFAS batching;
- multivariate Q-DESN batching;
- divide-and-combine VB;
- variational coresets.

## Recommended Next Step

The Normal DESN implementation is ready for the final Normal/Q-DESN unified
source-median comparison. After that, the next coding stage should be
exogenous/decomposition-aware Normal forecast contracts if forecast workflow
parity is the priority.

The implemented warm-start metadata contract is recorded in:

```text
docs/implementation_notes/normal_desn_warm_start_contract_20260529.md
```

The final Normal/Q-DESN unified comparison contract is recorded in:

```text
docs/implementation_notes/normal_qdesn_unified_comparison_contract_20260529.md
```

Do not run the final authoritative unified comparison while the package repo is
dirty from parallel Q-DESN mode work. Use package commit `9f1c32d` or later:

```text
docs/implementation_notes/normal_qdesn_post_wait_resume_prompt_20260529.md
```
