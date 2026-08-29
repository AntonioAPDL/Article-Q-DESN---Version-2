# Independent Validation DGP Oracle References: v13 Plan and Implementation

## Scope

This change adds deterministic data-generating-process (DGP) reference lines to
the six posterior-metric interval figures for the independent single-quantile
validation study. It does not change model fits, metric estimates, posterior
intervals, winner identities, tables, or scientific promotion decisions.

The work is split across two dedicated scientific surfaces:

- the validation branch freezes and verifies the oracle ledger;
- this article branch projects that ledger into versioned v13 figures.

Neither branch merges itself into shared validation, Article-v2 `main`, or an
Overleaf remote. Integration remains the coordinator's responsibility after
visual review.

## Scientific Audit

The three plotted metric roles do not share the same oracle value.

For the true conditional quantile path `q_p(t)` and a candidate path
`q_hat_p(t)`, fit RMSE and forecast MAE are path-recovery errors:

```text
fit RMSE = sqrt(mean_t (q_hat_p(t) - q_p(t))^2)
forecast MAE = mean_(origin,lead) |q_hat_p(origin,lead) - q_p(origin+lead)|
```

The true DGP path therefore has exact reference value zero for both metrics.
These lines are genuine lower bounds, not empirical benchmark-model scores.

Forecast check loss instead scores the realized response:

```text
rho_p(y - q) = (y - q) * (p - I[y - q < 0]).
```

Its population minimum is attained at the true conditional `p`-quantile but is
positive for nondegenerate innovations. The plotted check-loss reference is
therefore `E[rho_p(Y - q_p)]`, evaluated under each frozen innovation law.
The realized held-out oracle score is retained in the validation ledger as a
finite-sample diagnostic, but it is not plotted as a second line. Plotting both
would obscure the intended population benchmark and add visual ambiguity.

The frozen DGP audit covers:

- Gaussian innovations with standard deviation 10;
- Laplace innovations with scale 10;
- the Gaussian mixture with weights 0.1 and 0.9, component means 0 and 1,
  and component standard deviations 0.5 and 15;
- target levels 0.05, 0.25, and 0.50;
- 34 forecast origins, maximum lead 30, origin stride 30, and 1,000 unique
  held-out targets.

Analytic expected check-loss calculations were cross-checked against
independent numerical integration. Their maximum absolute discrepancy was
approximately `1.4e-12`. The DGP source-series quantile-centering check was
approximately `2.8e-17` at worst.

## Design Decision

The existing v12 interval summary is already article-authoritative. Rebuilding
the complete v12 projection would also regenerate point tables, interval
tables, winner ledgers, and unrelated diagnostics. That would add risk without
changing the scientific object under review.

The optimal implementation is therefore a figure-only v13 projection:

1. Hash-pin the 72-row v12 interval summary.
2. Hash-pin the 27-row validation oracle asset and its validation commit.
3. Expand the summary into a 216-row plotting ledger.
4. Join one oracle reference to every inference/model/family/quantile/metric
   plotting row.
5. Generate six deterministic one-page PDFs.
6. Replace only the MCMC and VB figure-wrapper inputs in the article and
   supplement.
7. Preserve all v12 tables and numerical values unchanged.

This provides a small review surface, exact provenance, and a simple rollback:
restore the two v12 wrapper inputs and remove the v13-only assets.

## Figure Contract

Each figure retains the established display:

- horizontal interval: equal-tailed 95 percent posterior interval, or the
  corresponding approximate variational interval;
- cross: posterior mean of the metric;
- color: model class;
- panel: simulation family and target quantile;
- free horizontal scale by panel;
- black dashed vertical line: DGP oracle reference.

For fit RMSE and forecast MAE, the dashed line is exact zero. For forecast
check loss, it is the population expected score at the true conditional
quantile. Captions explicitly state that finite-sample posterior check-loss
summaries may cross the population reference because the intervals condition
on one simulated series.

## Reproducibility Contract

The article config pins:

- minimum Article-v2 ancestry;
- validation worktree and full validation commit;
- validation oracle path and SHA-256;
- v12 interval-summary path and SHA-256;
- expected models, families, quantiles, inference methods, and metric roles;
- exact output paths and row counts.

The builder renders one figure per fresh R process directly to a 300-dpi Cairo
PNG and wraps that verified raster in a one-image PDF. This choice was made only
after a visual and repeated-render audit found that the legacy host font stack
could omit text groups from otherwise valid vector PDFs in some viewers. Direct
rasterization resolves the font-subsetting ambiguity without changing any
plotted value or layout. The R finalizer verifies one embedded 300-dpi image per
page, renders every completed PDF twice in separate `pdftocairo` processes,
requires identical raster hashes, rejects blank pages, verifies one-page PDF
integrity and the embedded 300-dpi image contract, and then emits the file-level
SHA-256 manifest. This gate tests the observed failure mode instead of assuming
that a syntactically valid PDF is visually sound. The host's legacy `pdftoppm`
renderer is not used for this gate because it was independently shown to clip
valid pages that both `pdftocairo` and Ghostscript render correctly.

The final manifest covers the config, builder, R finalizer, checker, pipeline,
inputs, projected oracle asset, 216-row figure ledger, six PDFs, both TeX
wrappers, and the two manuscript entry points. Numerical content and layout are
deterministic. The 300-dpi image-PDF container is an explicit portability
choice for this legacy graphics environment. PDF metadata timestamps remain
build-specific, so artifact identity is provided by the frozen committed hashes
rather than claimed as byte-for-byte reproducibility across independent rebuilds.

The checker validates source and projected hashes, complete joins, row/key
cardinality, nonnegative oracle values, the zero/positive role distinction,
the 34-origin and 1,000-pair protocol, PDF integrity, wrapper labels, manuscript
inputs, and every file hash in the generated manifest.

## Review Packet

The six visually verified v13 PDFs are concatenated into one local review PDF under:

```text
local_trackers/independent_dgp_oracle_figures_v13_20260829/
```

`local_trackers/` is already covered by the repository `.gitignore`; the
combined packet is intentionally not an article asset and must not be committed.

## Acceptance Gates

Integration should proceed only if all of the following hold:

1. The validation oracle verifier passes.
2. The article v13 builder, finalizer, and checker pass through the frozen
   pipeline script.
3. The focused article test passes.
4. `git diff --check` passes.
5. `main.tex` and `qdesn-supplement.tex` compile without unresolved references.
6. The six figure pages and combined packet pass visual inspection.
7. The article task branch is clean, pushed, and synchronized with its upstream.

No metric or model result is promoted by this change. The coordinator should
integrate only the oracle evidence and figure presentation after user approval.
