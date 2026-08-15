# Q-DESN VB Richer Stratified Subset Stage

Date: 2026-05-29

## Purpose

This note documents the richer subset-screening stage for package static/readout
and univariate Q-DESN AL ridge VB. The mode remains a target-changing subset
fit. It is not exact chunking, not stochastic mini-batching, and not a
full-data posterior approximation.

## Repo State

- article branch: `application-ensemble-likelihood-redesign`
- package branch: `validation/shared-fitforecast-v2-1.0.0`
- package commit: `f0d45ea Extend Q-DESN VB comparison and subset modes`

No article application code or config was changed.

## Implemented Scope

The package subset control now supports stratified AL ridge subset targets with:

- `subset_fit$strata = "time_block"`;
- `subset_fit$strata = "response_quantile"`;
- `subset_fit$strata = "design_leverage"`;
- `subset_fit$allocation = "proportional"` or `"equal"`;
- unchunked subset-target VB;
- exact chunked subset-target VB for the selected rows.

Aliases are accepted for convenience:

- `"response"` and `"y_quantile"` map to `"response_quantile"`;
- `"leverage"` maps to `"design_leverage"`.

Response-quantile strata are based on the observed response vector `y` for the
rows being fit. Design-leverage strata are based on QR leverage of the scaled
design matrix, with a finite row-norm fallback if QR leverage cannot be formed
stably.

## Still Forbidden

The following remain gated:

- RHS/RHS_NS subset fitting;
- exAL subset fitting;
- stochastic or hybrid subset fitting;
- rolling, online, or posterior-as-prior subset handoff;
- article GloFAS subset adapters.

## Target Label

Every subset fit records `target_label = "subset_data_vb"` and
`preserves_full_data_target = FALSE`. Exact chunking only preserves the subset
target for the selected rows.

## Validation

Focused package tests:

- `tests/testthat/test-exal-subset-fit.R`: 121 pass, 0 fail.

The D=1, n=300 source-median gate included response and leverage subset rows:

| mode | subset rows | effective rows | pinball_y | rmse_mu | exact max abs | exact max rel |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| response-quantile subset | 180 | 500 | 8.389557 | 17.62928 | 2.295e-10 | 1.093e-12 |
| design-leverage subset | 180 | 500 | 8.416776 | 17.80596 | 5.057e-10 | 2.423e-12 |

Both exact chunked subset fits matched their unchunked subset targets under the
`1e-6` absolute and relative gate used by the source comparison.

## Interpretation

Response-quantile and design-leverage subsets are useful screening and
sensitivity tools. They deliberately change the fitted data target and should
not be compared to full-data VB as if they were full-data approximations.

The next subset extension, if needed, should be custom row IDs or custom strata
metadata with strict leakage checks. RHS/RHS_NS and exAL subset targets should
remain forbidden until their global state semantics are derived.
