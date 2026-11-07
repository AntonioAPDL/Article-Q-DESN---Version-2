# GloFAS forecast root-cause closeout

## Scope

This note closes the bounded, truth-free diagnosis of the November GloFAS
same-family future-transition experiment. It does not promote results, modify
the article, refit a model, change a prior, tune against the December 2022
window, or replace the existing Search III authority.

The question was whether the severe p05/p50/p95 forecast crossings came from
poor convergence, Monte Carlo error, the local Gaussian-Delta approximation,
or the statistical target itself. The diagnostic held the retained DESNs,
historical fits, parameter states, scalers, covariates, issued ensemble and
source hashes fixed. Future USGS observations were never read.

## Executed evidence

The retained independent-AL p05, p50 and p95 fits were evaluated under four
fixed complete-path cells:

1. normalized same-family AL future transition with unit member factors;
2. normalized same-family AL transition with a fractional information
   diagnostic;
3. Gaussian path prior with unit member factors;
4. Gaussian path prior with the fractional information diagnostic.

Each tail used 2,048 whole-path importance proposals. A failed importance
gate triggered the preregistered 256-particle, at-most-eight-stage tempering
fallback. The p05 and p95 executions ran independently on one logical CPU
each. Both design and fit payloads passed before/after SHA256 verification.
No fit, parameter update, score, or future-truth read occurred.

The p05 and p95 same-family importance proposals were too concentrated, but
the declared tempering fallback passed with effective sample sizes of 231.44
and 255.88 under the unit-member target. Gaussian-path importance passed
directly. The fallback therefore resolved the Monte Carlo concern without a
post-hoc threshold change.

## Result

| Quantity | Adjacent crossings | Ordered horizons | Maximum crossing |
|---|---:|---:|---:|
| Accepted local Gaussian-Delta marginal response quantiles | 13 | 17/28 | 3.628941 |
| Global same-family/unit marginal response quantiles | 12 | 17/28 | 3.571466 |
| Conditional readout locations | 0 | 28/28 | 0 |

The accepted local approximation is close to the global reference:

| Probability | Local/global MAE | Maximum absolute difference |
|---:|---:|---:|
| 0.05 | 0.017412 | 0.184255 |
| 0.50 | 0.038107 | 0.165033 |
| 0.95 | 0.041486 | 0.194022 |

Global path integration reproduces the large crossings. Consequently, local
Delta error, optimizer convergence and reference Monte Carlo error are not the
material failure mechanism. The zero-crossing conditional readout locations
are not marginal future-response quantiles; reporting them would change the
estimand and conceal the defect.

The decision is:

`STRUCTURAL_INDEPENDENT_TAIL_PATH_TARGET_INCOHERENCE`

Separate tau-specific future-response transition laws do not define one
common predictive response distribution. More VB iterations, broader DESN
screening, more global-path particles, relaxed convergence gates or isotonic
postprocessing cannot repair that target mismatch.

## Authority consequence

The November same-family packet is retained as adverse diagnostic evidence
and rejected as replacement article authority. It was not merged to current
`origin/main`, so no article rollback is required.

The retained Search III workflow already uses the coherent construction:

- Part 1 quantile readouts are evaluated on 500 aligned recursive USGS paths
  from the Part 1 Normal-RHS model;
- Part 2 uses 500 recursive discrepancy paths, with exact probability reversal
  when converting discrepancy quantiles to corrected-USGS quantiles;
- Part 3 uses matched USGS, discrepancy and GloFAS paths from its Normal-RHS
  model;
- Part 4 replaces the future-USGS AL/exAL working likelihood with one joint
  Gaussian prior moment-matched from the truth-free Part 3 Normal-RHS bank,
  while retaining the issued-ensemble likelihood.

Normal Ridge and Normal RHS already define their own recursive response law
and do not receive a second driver prior.

The focused Normal-driver regression passes R/C++ equivalence, 500-path
alignment, Part 2 reversal, matched Part 3 trajectories and analytic Part 4
prior replacement. Retained Search III fits also preserve full coefficient
covariance blocks required for paired parameter/path draws.

The authentic read-only authority audit then passed:

| Contract surface | Passed | Total |
|---|---:|---:|
| Normal-RHS driver banks | 3 | 3 |
| Part 1--3 quantile forecast artifacts | 48 | 48 |
| Part 1--3 quantile fits with full covariance | 48 | 48 |
| Part 4 quantile fit artifacts using the replacement prior | 16 | 16 |
| Part 4 inner fit cores using the replacement prior | 28 | 28 |

Every Part 4 core uses prior contract
`0202bc19e26d84d6cbb55c2256a2071695f9c386c9dc64933005bd4d5acbb357`
and records `future_y_working_likelihood_used = FALSE`. The audit performed
zero model fits and zero scoring-truth reads. Summary SHA256:
`6bb1572d711d8a74eda24a3bcefcc700532e3bb179387d3791e3860b6bcf1b02`.

## Provenance repair

The retained Part 2 and Part 3 driver-bank metadata refer to a retired r3
source path, although hash-identical source fits remain in r4. Source absence
must not be treated as source verification. The driver-bank API now supports a
strict availability gate and a rebinding operation that:

1. requires an existing replacement fit;
2. recomputes its SHA256;
3. rejects any mismatch with the bank's bound source-fit hash;
4. updates the path and contract hash;
5. validates the rebound bank with strict source availability.

This is an administrative provenance correction. It does not alter a path,
fit, prior, seed, DESN or forecast value.

## Minimal forward path

1. Retain the existing Search III authority and the rejected November packet
   as separate immutable evidence.
2. Strictly verify and, where needed, rebind the three Normal-RHS driver banks
   to the hash-identical retained r4 fits.
3. Retain the passed 48-artifact forecast and covariance audit as evidence
   that a broad replay or refit is unnecessary. A future spot replay is an
   optional reproducibility check, not a correction gate.
4. Retain the passed 28-core Part 4 replacement-prior audit. Do not refit the
   Part 4 families for this issue.
5. Keep the method frozen before any new final-window comparison. Use
   training-only
   rainy-season rolling origins for method qualification.
6. Score and regenerate one final comparison packet only after all contracts
   pass. Promotion remains a separate reviewed operation.

Broad screening, longer fits and another 16-model same-family campaign are
not justified by this diagnosis.

## Evidence pointers

- closeout PDF:
  `local_trackers/glofas_forecast_root_cause_reference_20261106/native_global_path_tail_closeout_20261107T0700Z_d2aa1ff4/global_tail_root_cause_closeout.pdf`;
- PDF SHA256:
  `6d52d9131dd6b49280bf9d474d487aa747c246e9f3a60774e8fe94bc90face0c`;
- decision SHA256:
  `7370fbd46ee4c88fdeea35a0ab7f85c98cff95f06a6ecff28bee60b102aa180b`;
- crossing table SHA256:
  `1cf436999662b1454c1ef321d688e3345b7eeddd4fb1e4ab3b8eb78673f09c7b`.
- coherent authority audit:
  `local_trackers/glofas_forecast_root_cause_reference_20261106/coherent_normal_driver_authority_audit_20261107T0715Z_d2aa1ff4`;
- authority audit summary SHA256:
  `6bb1572d711d8a74eda24a3bcefcc700532e3bb179387d3791e3860b6bcf1b02`.
