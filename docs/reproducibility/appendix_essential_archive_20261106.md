# Extended appendix material and source qualifications

The reader appendix retains implementable posterior updates, the forecast
quantity actually scored, generating specifications, and the additional
results needed to interpret the article. This index locates material omitted
from the printed appendix. It changes no fitted model, forecast, score,
scientific CSV, or original figure. Archived results are not new evidence.

## Immutable accounts and known written corrections

The [56-page preceding appendix](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/qdesn-supplement.tex)
is preserved at `1b249255018715dd3bdc3c95389c80702d26c8c9`. Its identified
article has 37 pages. Page counts include title pages and references.
Two statements in that appendix require the following qualifications:

1. **G01.** Its reservoir-description paragraph incorrectly calls the normalized
   screening gains the executed input and bias gains. The executed reference
   and discrepancy input multipliers are **0.5 and 0.35**, respectively, with
   **bias multiplier one**. The current reader appendix corrects this prose;
   it does not alter a reservoir or a fitted result. The controlled inference
   comparison preserves that executed design.
2. **G02.** In the multiquantile crossing table, posterior-draw crossing percentages
   are **equal-scenario averages across eight mechanisms**, not pooled
   comparisons across all retained draws. The mean and maximum adjustment
   columns concern the **posterior-mean forecast grid**, not the average
   adjustment across posterior draws. The current caption makes this explicit.

The [earlier 70-page appendix](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/qdesn-supplement.tex)
is also retained. **M01:** its written source-specific exAL scale expression omits
`1/B_gamma` in `psi_c`. The executed v-augmentation helper already includes
that divisor. The 56-page account and the current reader account correct the
written expression. The [preceding archive index](appendix_compression_archive_20261106.md)
gives the authenticated producer, target and prior traces. Neither immutable
account should be read as uniformly error-free prose.

## Mathematical details

All line links below refer to the immutable 56-page source, not the current
line numbering. Main-text equations and the current appendix give the live
model and computation.

| Extended material | Preserved source | Retained reader account |
|---|---|---|
| Distributional conventions and repeated single-level hierarchy | [Lines 118–326](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/qdesn-supplement.tex#L118-L326) | Common likelihood notation, NS product mass and its dependence on scales; the main text specifies the coefficient prior |
| Gaussian global-scale reference and centered-feature prior transformation | [Lines 270–313](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/qdesn-supplement.tex#L270-L313) | Main-text reference calibration; extended derivation and coordinate change remain computational material |
| Expanded conjugate VB and transformed Laplace–Delta calculations | [Lines 495–656](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/qdesn-supplement.tex#L495-L656) | Canonical expected-precision updates, covariance and latent moments, plus compact transformed approximation |
| Structured exAL integral, scale moments and monitor | [Lines 657–787](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/qdesn-supplement.tex#L657-L787) | Analytic scale integral, shape quadrature, mixed moments and admissible power moments remain explicit |
| Separate multiquantile sampling algorithm | [Lines 788–947](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/qdesn-supplement.tex#L788-L947) | Anchored difference precision, ordered intercepts, shared sampling schedule and full stacked-slope covariance |
| Expanded forecasting and score exposition | [Lines 948–1049](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/qdesn-supplement.tex#L948-L1049) | Actual averaged-feature and trajectory-specific functionals, recursion, ordering and study-specific weights |

## Additional simulation displays

The current reader appendix retains the primary 300-target forecast-path MAE
figure, empirical-frequency figure, complete generating tables, all 32 MCMC
score-sensitivity comparisons and the crossing summary. Original inputs,
labels and numerical data remain versioned, including the following omitted
displays:

| Material | Preserved source |
|---|---|
| Sequential-initialization illustration | [Appendix lines 1053–1092](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/qdesn-supplement.tex#L1053-L1092) |
| Independent fitting-sample RMSE | [Figure wrapper](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/tables/appendix_compact_20261106_ind_fit_rmse.tex) |
| Complete 500-target forecast MAE and check-loss panels | [Figure wrapper](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/tables/appendix_compact_20261106_ind_sensitivity.tex) |
| Multiquantile fitting-sample RMSE | [Figure wrapper](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/tables/appendix_compact_20261106_mq_fit_rmse.tex) |
| Cell-specific score diagnostics | [Complete table](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/tables/appendix_compact_20261106_score_diagnostics.tex) |

The 300-target period was adopted after inspection of the 500-target period;
these nested windows are not independent replications. Reservoir specifications
vary with the selected criterion and historical refinement used evaluation
performance. These scope statements remain in the reader appendix.

The complete [32-cell score comparison](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/tables/appendix_compact_20261106_mq_scores.tex)
retains primary and trajectory-specific means and intervals. Narrower
primary intervals occur in 28 of 32 cells, not all cells; the four exceptions
are the persistent-heavy-tail mechanism, one per model. Score stability is
not a substitute for assessment of scalar-parameter mixing.

## Streamflow and electricity-price material

The issued-ensemble analysis remains the current streamflow authority.
The reader appendix retains its two reservoir specifications, actual priors,
source-specific updates, latent-design moments, stopping criteria, full-family
empirical-frequency table and full-family figure. It reports unfavorable
crossing, support and coverage findings without clipping the forecasts.

The earlier 30-day historical reference/discrepancy experiment is a separate
analysis, not an alternative issued-window authority:

- [Historical methods and prior catalogue](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/qdesn-supplement.tex#L1595-L1651).
- [Historical component score table](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/tables/appendix_compact_20261106_glofas_historical_scores.tex): 12 scored reference/combined comparisons; six discrepancy-only entries are **unscored**, not zero-loss or zero-crossing results. Retrospective GloFAS ends at the origin, so the discrepancy-only model has no defined post-origin score in that experiment.
- [Issued-fit stopping table](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/tables/appendix_compact_20261106_glofas_convergence.tex).
- [Issued-fit crossing and support table](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/1b249255018715dd3bdc3c95389c80702d26c8c9/tables/appendix_compact_20261106_glofas_diagnostics.tex).

The electricity-price fold-design table remains printed. Complete regional
scores and historical sensitivity analyses remain in the versioned numerical
materials; no PriceFM result is replaced by this editorial revision.

## Verification and rebuilding

The following stable role names connect the public index to the explicit
essential-content contract. They identify omissions, not additional required
reading: `initialization_diagram`, `ind_fit_rmse`, `ind_500_mae`,
`ind_500_check`, `mq_fit_rmse`, `score_diagnostics`, `glofas_convergence`,
`glofas_diagnostics`, `glofas_historical_scores` and `historical_no_score`.
The two longer-period roles share the complete sensitivity wrapper; the
historical no-score boundary is preserved with its original experiment.

Use a separate clean worktree at an immutable source commit to rebuild an
earlier account; do not switch an occupied scientific worktree. The review
entry point is `bash scripts/build_technometrics_review.sh`. It fits no model.

The essential-display builder is
`/usr/bin/python3.11 scripts/build_appendix_essential_displays_20261106.py --check`.
It checks the two new caption derivatives against frozen inputs. The
versioned essential-content contract and semantic validator distinguish
retained reader roles from archives and verify original scientific assets.
The accompanying [revision record](appendix_essential_revision_20261106.md)
states the validation and scope of the new edition. The archive is not a
second compulsory supplement and does not qualify unfinished inference work.
