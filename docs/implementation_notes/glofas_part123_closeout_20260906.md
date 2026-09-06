# GloFAS Parts 1-3 Scientific Closeout

Date: 2026-09-06

## Scope and fixed contract

This closeout freezes the completed GloFAS Part 1, Part 2, and Part 3 work before any Part 4 decision. It does not change article authority, rerun a model, use forecast ensembles, or alter Part 4.

The common final forecast contract is:

- training cutoff and forecast origin: `2022-12-25`;
- forecast window: `2022-12-26` through `2023-01-24`;
- horizon: 30 daily steps;
- realized PRISM/ERA5 covariates are diagnostic oracle inputs;
- no CEFS, rolling origin, crossing correction, synthesis, or Part 4 input;
- future USGS is excluded from fitting and recursive inputs and is used only for post-fit scoring.

## Frozen status

| Part | Scientific role | Fit status | Forecast status | Score status | Closeout decision |
|---|---|---:|---:|---|---|
| 1 | Univariate USGS | Complete | Complete, 30/30 days | Complete against future USGS | Closed |
| 2 | Univariate observed discrepancy, retrospective GloFAS minus USGS | Complete | Computation completed but no observable post-cutoff discrepancy path can be formed | Not scoreable because retrospective GloFAS ends at the cutoff | Closed as a historical fit and initializer; no claim of post-cutoff forecast skill |
| 3 | Joint historical USGS and retrospective GloFAS | Complete | Complete, 30/30 days | USGS/reference component scored; discrepancy and GloFAS components are not scoreable | Closed with target-specific scoring limitation |

## Part 1

The final Part 1 DESN specification is the selected univariate USGS geometry: `D=1`, `n=3000`, `m=360`, `alpha=0.5`, `rho=0.9`, Normal RHS `tau0=1`, with no direct input vector in the readout. The final warm-start quantile chain completed 16/16 jobs: seven independent AL, seven independent exAL, joint AL, and joint exAL, with zero failures.

The final Normal forecast scores on the transformed `log1p` scale are:

| Model | Mean CRPS | MAE | RMSE |
|---|---:|---:|---:|
| Normal Ridge | 0.571571 | 0.695562 | 0.831133 |
| Normal RHS/VB | 0.511827 | 0.626824 | 0.777931 |

Part 1 forecast tables contain exactly the 30 dates from `2022-12-26` through `2023-01-24`.

## Parts 2 and 3 Jerez import

The source Jerez branch is `work/glofas-dec25-final-refit-forecast-20260905` at `66105e397b3b0c33021a20d6c80ca716a884e94a`. The imported runtime is `local_trackers/runtime_configs/glofas_part23_final_dec25_2022_relaunch_jerez_20260905`.

The read-only import retained all reusable outputs while excluding reconstructible design-cache payloads:

- imported files: 895/895;
- imported bytes: 3,752,487,935;
- source hash verification failures: 0;
- retained RDS objects readable on Muscat: 74/74;
- transfer file-list SHA256: `92dad8cfd2dbaa3a948128b488c8e5eeeca4bab72c45cb962ff94a0c30f59d07`;
- source hash-manifest SHA256: `044c2f876108893568cc5d45115e18313d1773f86ef7bae88a510394276585f4`.

The imported DAG has 80/80 completion markers, no failures, and no stale running markers. Its 80 entries comprise, for each Part, one design build, one initializer audit, 18 fits, 18 forecast-stage jobs, and two operator-skipped package placeholders. Thus 76 entries are substantive scientific/audit computations and four are explicit packaging placeholders.

## Part 2

The selected discrepancy geometry is `D=1`, `n=2500`, `alpha=0.8`, `rho=0.7`, with discrepancy Normal RHS `tau0=0.001`. The reference component retains the Part 1 winner and Normal RHS `tau0=1`. All 18 final fits completed using the fixed cutoff.

Part 2 forecasts require future retrospective GloFAS to translate a predicted discrepancy into corrected USGS and to observe the future discrepancy target. Retrospective GloFAS ends on `2022-12-25`; substituting an ensemble, CEFS product, or another transition model would change the scientific experiment. Therefore the forecast-stage jobs correctly retain summaries and fit reuse contracts but do not emit scored future paths. Blank future score fields are structural missingness, not numerical failure.

## Part 3 score repair and result

The Jerez Part 3 forecast objects contain valid 30-day predictions, but their exported score tables left future truth blank. The closeout scorer joins the authoritative future USGS series by exact date after forecasting and on the model's `log1p` scale. It never injects future observations into a fit or recursive input.

| Normal model | USGS mean CRPS | MAE | RMSE | Bias | 95% coverage |
|---|---:|---:|---:|---:|---:|
| Ridge | 0.612788 | 0.697382 | 0.887567 | -0.664618 | 0.333333 |
| RHS/VB | 0.616864 | 0.705969 | 0.906073 | -0.674240 | 0.366667 |

| Joint quantile model | USGS seven-quantile CRPS |
|---|---:|
| Joint AL | 0.715690 |
| Joint exAL | 0.861737 |

The Normal models are the strongest Part 3 forecasts in this diagnostic, but all families materially underpredict the held-out event. The weak coverage and large negative bias are a scientific warning for Part 4, not a reason to invalidate the completed fits.

Part 3 discrepancy and implied GloFAS forecasts cannot be scored without future retrospective GloFAS. Their absence from the score comparison is explicit.

## Reproducibility outputs

The imported runtime and derived score tables remain ignored runtime artifacts. The score-only implementation is:

- `application/R/glofas_part123_closeout.R`;
- `application/scripts/387_score_glofas_part3_dec25_closeout.R`;
- `application/tests/test_glofas_part123_closeout.R`.

Derived runtime tables are under `local_trackers/runtime_configs/glofas_part23_final_dec25_2022_relaunch_jerez_20260905/closeout/`. No original Jerez file was overwritten.

## Decision

Parts 1-3 are frozen for their stated roles. Part 1 is the completed univariate USGS benchmark. Part 2 supplies the selected discrepancy model and initializers but has no defensible final post-cutoff score. Part 3 supplies the completed joint historical fits and 30-day USGS forecast comparison. No additional Part 1-3 fitting is required before discussing Part 4.
