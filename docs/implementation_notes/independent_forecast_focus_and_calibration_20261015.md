# Independent simulation: forecast focus and empirical quantile frequencies

## Scope and authority

This revision starts from Article main
c18d364d3e9f0cf44cda779e2a2c32fe0d684811
and uses the already-frozen shared-validation authority
94bd95784f413f3edde88a35cb991f2a56b6afef.
It changes presentation and adds postprocessing of retained forecasts. It
does not refit models, simulate new forecasts, change selected specifications,
alter inference, or affect the multiquantile, GloFAS or PriceFM evidence.

The primary evaluation remains 300 targets; the 500-target sensitivity
contains that period and is not an independent replication. Historical
forecast-guided refinement and the retrospective change of reporting period
remain disclosed in the manuscripts.

## Decisions and interpretation

1. Keep average forecast check loss in the main paper. Move the primary
   forecast quantile-path MAE figure and its interpretation to the supplement,
   retaining the existing labels. LaTeX determines the new figure numbers.
2. Preserve every value in the 144-row forecast and 72-row fitting summaries,
   all four forecast PDFs, and both fitting PDFs. The independent-only
   generator reuses the frozen forecast PDFs by default. Its optional
   --render-forecast-figures mode verifies byte-identical reproduction after
   matching creation-date metadata, without replacing a frozen PDF.
3. Explain the linear-dynamics comparison through its criterion: both Q-DESN
   likelihoods have lower mean check loss than both dynamic comparators at
   levels 0.25 and 0.50 in every family and both periods. The AL lower-tail
   weaknesses remain visible. This is evidence of competitive forecast loss,
   not uniform superiority or calibration.
4. Interpret MAE as recovery of the known state-conditional quantile path.
   Its posterior dispersion is not a response prediction interval. Aggregate
   interval widths also reflect the documented model-specific construction
   of draws across forecast targets.
5. Add one supplementary descriptive quantile-frequency figure and table.
   Do not add rolling-window confidence bands, a new selection criterion,
   formal equivalence tests, or a synthesized predictive distribution.

## Calibration extraction fixed before inspection

The policy in application/config/independent_forecast_calibration_v1.json
selects the existing 36 check-loss specifications, each with three balanced
retained chains. At each target, the reported p-quantile is the median of all
pooled quantile-location draws. Its empirical frequency is the fraction of
responses at or below that point forecast, with ties included. The same point
forecasts are used for both evaluation prefixes.

The extractor validates the packet manifest, protected locator, frozen source
manifest and recovery-audit chain, including all 108 immutable payload hashes.
It also checks contracts, source identities, chain budgets, dates/grid,
response alignment and coupling metadata before producing 72 summaries and
a compact 108-row source-hash receipt. No individual response, quantile draw,
model object, runtime filename or private path is published.

These are observed frequencies, not posterior uncertainty bands or a test of
conditional calibration. The ten primary origins and seventeen sensitivity
origins offer limited independent information, especially at the 5% level;
no sampling confidence bands are estimated here. Each quantile level uses
its own quantile-centred response series.

The results are not uniformly favorable. At the median under Gaussian-mixture
errors, Q-DESN frequencies range from 40.7% to 41.6%, versus 49.7% to 51.4%
for the dynamic comparators. Laplace median frequencies are near 50%. Under
Gaussian errors, exAL lower-tail frequencies are 3.3% and 4.8% in the two
periods. Laplace AL can attain a near-nominal lower-tail frequency despite its
worse check loss. Accuracy and empirical calibration are complementary.

## Reproduction

Use pinned R 4.6.0 and an existing, read-only shared-validation checkout.
IND_VALIDATION_ROOT denotes its root; extraction requires the authentic
protected retained-path evidence and fails rather than synthesizing it.

    Rscript application/tests/test_independent_forecast_calibration_v1.R
    Rscript scripts/extract_independent_forecast_calibration_v1.R \
      --validation-root "$IND_VALIDATION_ROOT" --output-dir tables
    Rscript scripts/check_independent_forecast_calibration_v1.R
    Rscript scripts/build_independent_forecast_300_500_v1.R
    python3.11 scripts/audit_qdesn_article_dependencies.py \
      > docs/reproducibility/article_dependency_inventory.csv
    Rscript scripts/check_independent_forecast_300_500_v1.R \
      --validation-root "$IND_VALIDATION_ROOT"
    Rscript scripts/check_qdesn_final_manuscript_revision.R
    python3.11 scripts/check_qdesn_sections5_7_presentation.py
    python3.11 scripts/check_qdesn_mq_nomenclature.py
    bash scripts/build_technometrics_review.sh
    git diff --check

The compact checker and article build do not need protected runtime evidence.
Regeneration of the calibration summaries does. The article manifest records
the active source and output hashes; the extraction manifest records the
immutable evidence chain. The complete evolving plan and build receipts are
kept under ignored local_trackers/ storage rather than the article projection.

## Verification and publication

The synthetic calibration test exercises 47 checks, including 31 expected
mutation rejections. Independently recomputed pooled-median hit counts for a
dynamic lower-tail case and a Q-DESN mixture-median case agree at both cutoffs.
The presentation tests reject misplaced MAE, invented sampling bands and
modified frequency arithmetic even when superficial receipts are refreshed.

Before publishing, require clean identified and anonymous main/supplement
builds, actual TeX-recorder placement checks, scoped combined regression tests,
an article-only closure/build, and unchanged other-study assets. A focused
integration does not certify every historical repository fixture or full
journal-submission readiness.

Integrate with a fresh --no-ff merge from current origin/main and use the
repository's guarded command-line main and article-only Overleaf publishers.
Require fresh remote commit/tree readback; a local build or fetch alone is
not evidence of publication.

## Statistical references

Gneiting (2011), Making and Evaluating Point Forecasts:
https://arxiv.org/abs/0912.0902

Gneiting and Resin (2023), Regression Diagnostics Meets Forecast Evaluation:
Conditional Calibration, Reliability Diagrams, and Coefficient of
Determination. Electronic Journal of Statistics 17(2), 3226-3286:
https://doi.org/10.1214/23-EJS2180

Fosten, Gutknecht and Pohle (2023), Testing Quantile Forecast Optimality:
https://arxiv.org/abs/2302.02747

These references motivate the distinction between consistent scoring,
observed frequencies and conditional calibration. They do not certify the
present forecasts or justify independent-binomial confidence bands.
