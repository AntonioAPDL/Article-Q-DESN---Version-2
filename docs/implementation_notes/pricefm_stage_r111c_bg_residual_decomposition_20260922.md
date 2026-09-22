# PriceFM Stage-R111C: BG residual decomposition

## Purpose

Stage-R111B completed all 51 tasks without failure. Its mixed-exposure AL readout reduced pooled BG AQL from 12.21527 to 11.11211, beat the cached PriceFM surface at 11.49281, and improved every fold relative to R110. It nevertheless remained 2.63% above the R97 direct reference at 10.82717 and narrowly missed the preregistered 10% R110-improvement gate by 0.97 percentage points.

The gate must not be weakened after observing the result. R111C therefore performs no fitting and no additional selection. It decomposes the exact residual using frozen prediction arrays to decide whether another recursive-model experiment is scientifically justified.

## Evidence contract

The audit uses four fold-aligned BG validation surfaces:

| Surface | Role |
|---|---|
| R97 direct reference | Current valid Q-DESN authority |
| R110 frozen-readout replay | Pre-exposure-alignment recursive comparator |
| R111B mixed exposure | Completed candidate under diagnosis |
| PriceFM quantile-path surface | External model comparator |

For each of three folds, all surfaces must share exactly the same validation anchors, truth values, seven quantiles, and 96 horizons. R108, R110, and R111B terminal records and their prediction artifacts are hash-verified. The response scaler is recovered from the R111B source manifest and independently hash-verified before predictions are transformed to the original price scale.

No test split, model runner, optimizer, launcher, registry, or manuscript file is touched.

## Decomposition

For truth `y`, quantile forecast `q_tau`, and quantile level `tau`, R111C recomputes

```text
L_tau(y, q_tau) = max(tau (y - q_tau), (tau - 1) (y - q_tau)).
```

It aggregates the same loss by:

1. fold;
2. each of the seven quantiles;
3. exact horizon;
4. 24-hour horizon blocks;
5. forecast origin;
6. fold-by-block-by-quantile cells.

It also recomputes interval coverage, interval width, crossing, median MAE, and median RMSE. Gap-attribution columns are weighted by their exact number of loss atoms and must sum back to the pooled R111B-minus-R97 AQL difference.

## Audited diagnosis

The frozen predictions show a coherent pattern:

- R111B beats PriceFM in every fold and by 3.31% pooled.
- R111B beats R97 in fold 1 but loses in folds 2 and 3.
- R111B beats R97 over horizons 1--24 by about 1.05 AQL points.
- R111B loses to R97 over horizons 25--48, 49--72, and 73--96.
- Every quantile has a positive pooled R111B-minus-R97 gap.
- The largest residual cells concentrate in fold 3 at horizons 49--72 and fold 2 at horizons 73--96.

This rules against a single tail, crossing, or simple interval-calibration explanation. Exposure alignment repaired a real mismatch, but recursive target-driver error continues accumulating after the first forecast day. R97 avoids that recursive state-transfer burden and remains the stronger valid authority.

## Frozen decision

R111C must produce:

```text
residual_classification = late_horizon_recursive_transfer_not_single_quantile_calibration
recommended_action = stop_recursive_redesign_retain_R97
article_classification = diagnostic_only_no_promotion
```

Accordingly:

- do not launch a broad R112 recursive campaign;
- do not tune another BG exposure arm on these validation results;
- do not promote R111B to the registry or article;
- retain R97 as the BG authority;
- preserve R111B/R111C as reproducible diagnostic evidence;
- hand the frozen PriceFM lane to integration only when the broader valid R97 authority is ready for publication.

Future PriceFM work should address weak regions through preregistered, training-only Normal Ridge/Normal RHS screening rather than further post-hoc optimization of this BG validation surface.

## Outputs

The script materializes CSV, JSON, Markdown, and source-manifest outputs under:

```text
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/
pricefm_stage_r111c_bg_residual_decomposition_20260922
```

The output is deterministic and contains no model objects or duplicated heavy prediction arrays.
