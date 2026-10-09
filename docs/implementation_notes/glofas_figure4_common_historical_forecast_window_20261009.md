# GloFAS Figure 4: common fitted and forecast window

## Scope

This presentation revision starts from Article-v2 commit
`b986fd7af03e472b2c5e297be811d2901cc431a1`. All three main-figure panels now
cover 26 November 2022 through 22 January 2023: 30 historical dates through
the 25 December origin and the existing 28 issued target dates. No scientific
fit, initialization, prior, forecast ordinate, score, family selection, or
authority decision changes. The supplementary full-family figure remains
unchanged.

The two model panels repeat historical and held-out USGS observations, with
identical date limits, tick positions, vertical limits, and physically aligned
plotting areas. The shared vertical limits include the negative lower Normal
quantiles rather than clipping them. Raw historical AL quantiles have two small
adjacent-level crossings; these are retained without projection.

## Historical fitted quantiles

The new compact CSV contains exactly 420 ordinates: two families, 30 dates,
and seven levels. Historical features and coefficients come from the same
frozen Part 4 fits as the existing forecast comparison, not from Parts 1 or 3.

- Independent AL: at each level, the fitted conditional quantile is
  `X_beta %*% E_q(beta_tau)`.
- Normal Ridge: the fitted conditional response quantile is
  `X_beta %*% E_q(beta) + qnorm(tau) * E_q(sqrt(sigma_Y))`.

The Normal engine's `sigma_Y` is residual variance. For
`q(sigma_Y) = IG(a,b)`, with density proportional to
`sigma_Y^(-a-1) * exp(-b / sigma_Y)`,
`E_q(sqrt(sigma_Y)) = sqrt(b) * Gamma(a - 1/2) / Gamma(a)`, for `a > 1/2`.
The extractor checks this parameterization and the frozen coefficient names
against the fixed design before evaluating the 30 historical rows.

These are posterior-mean conditional quantile estimates under the variational
approximation, not credible limits or quantiles of a posterior-predictive
mixture. Future curves retain their original estimators: AL uses posterior
means of `q_y_draw`; Normal Ridge uses empirical quantiles of `latent_y_draw`.
The fitted and forecast line segments are drawn separately at the origin.

## Source authentication and public reproduction

`scripts/extract_glofas_part4_historical_quantiles.R` verifies the authority
ledger, shared design, eight fits, eight coefficient summaries, and their
artifact manifests before reading any fit. It reads historical features only
and never reads future USGS truth. Runtime objects remain in their original
ignored locations and are not redistributed.

The public extraction receipt is
`tables/glofas_search3_part4_history_fitted_quantile_provenance.json`.
It records source roles, sizes, hashes, formulas, and the extractor hash,
without private paths. The compact CSV and existing public plotting inputs
suffice to reproduce the figure without the large runtime design or fits:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla \
  scripts/build_glofas_figure4_common_window.R
python application/tests/test_glofas_figure4_common_window.py
python scripts/audit_qdesn_article_dependencies.py \
  --check docs/reproducibility/article_dependency_inventory.csv
bash scripts/build_technometrics_review.sh
```

For a different machine, use an R installation providing `ggplot2` and
`jsonlite`, and Python with PyMuPDF for the vector/font checks. The extraction
script requires an explicitly supplied authenticated `--authority-ledger` and
`--output-dir`; public reproduction does not require re-extraction.

## Article wiring and checks

The new drawing has its own figure filename, alias, and manifest. `main.tex`
loads the new alias after the historical GloFAS aliases. The original
13-output presentation bundle and scientific figures/manifests remain
byte-identical, so historical generators can still be checked independently.

The new regression suite verifies complete historical/forecast grids, source
hashes, the Normal half-moment formula, all unchanged legacy outputs, common
axes and physical panel alignment, manuscript wiring, vector-only output,
label size, and text containment. The frozen forecast source CSV remains
`d4a6c18eac599c66e9e95edda01e98d9f14c8f6a8efc6dd2a54f16544ae7181a`.

Only the article-safe PDF, alias, and presentation manifest are added to the
Overleaf allowlist. The public compact inputs, code, and implementation note
remain in the research repository. Publication requires a reviewed commit,
the normal two-parent integration merge, successful manuscript builds, and
the guarded one-way Git publishers. A locally generated figure is not an
Overleaf publication.
