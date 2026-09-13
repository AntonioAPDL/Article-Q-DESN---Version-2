# JOINT crossing-rate and reader-facing figure revision

Date: 2026-09-13

## Scope

This revision changes only the presentation of the frozen corrected JOINT
article comparison. It does not refit a model, alter a posterior draw, recompute
a scientific input, or change the corrected common-posterior target.

The seven staged source CSV files and their recorded SHA-256 hashes remain
unchanged. Canonical-action quantities remain available in those reproducibility
files and continue to be checked internally, but they are no longer displayed
in the manuscript.

## Statistical presentation

The main forecast figure now reports the posterior mean and equal-tailed 95%
interval for DGP-integrated aCRPS. Canonical-action marks and crossing-count
labels were removed because they represented secondary summaries with a
different estimand and obscured the primary comparison.

Crossing summaries distinguish two questions:

- raw crossing rate: the proportion of adjacent-level comparisons that cross
  before monotone rearrangement;
- mean and maximum absolute monotone adjustment: the size of the change induced
  by rearrangement.

Thus the rate measures frequency, not magnitude. Reporting it with the
adjustment summaries avoids interpreting a small number of large crossings as
equivalent to a large number of negligible crossings.

Across the eight forecast settings, each model has 47,520 adjacent-level
comparisons. The raw rates are 2.52% for joint Q--DESN, 7.41% for independent
Q--DESN, 0% for joint exQDESN, and 0.57% for independent exQDESN. All
rearranged grids have zero crossings.

## Article placement

- The main article gives the four aggregate forecast crossing rates and points
  readers to the supplement for magnitude.
- The main forecast figure contains only posterior means and 95% intervals.
- The supplementary fitting-sample figure contains only the oracle-path RMSE
  values.
- The supplementary crossing table gives fit and forecast rates with
  counts/opportunities and the corresponding mean/maximum adjustments.
- The supplementary primary score table retains only posterior means, medians,
  and 95% intervals.

## Reproducibility

Regenerate the article projection with
scripts/build_joint_qdesn_corrected_article_projection_v4.R under the pinned
R 4.6.0 installation.

The dedicated projection checker verifies the immutable source hashes, model
and scenario counts, score rankings, contrast directions, crossing totals and
denominators, reader-facing exclusions, vector-only figures, and article
manifest. The final manuscript checker independently requires the normalized
crossing rates and rejects reader-facing canonical-action marks or
raw/reported count labels.
