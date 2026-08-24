# Independent Validation Posterior Metric Intervals v10

Date: 2026-08-24

## Scope

This integration is restricted to the independent single-quantile Q-DESN/DQLM
simulation study. It does not modify the joint simulation, PriceFM, or GloFAS
scientific workflows. The article change replaces the historical scalar
point-path comparison with posterior distributions of draw-wise fit and
forecast criteria for the fixed 500-observation design.

## Audit And Decision

The production campaign
`independent_metric_intervals_v1_production_20260823_225856` completed 198 of
198 jobs without implementation failures. It reconstructed 90 frozen metric
sources and produced 270 source-metric summaries, 216 article metric roles, and
a complete 72-row inference-by-model-by-family-by-quantile interface. MCMC
sources pool 12,000 metric draws from three chains; VB sources use 10,000 draws
from the variational approximation.

The integration replaces, rather than decorates, the v9 point estimates. For a
retained conditional-quantile draw, fit RMSE, forecast MAE, and forecast check
loss are recomputed over the fixed fitting or rolling-origin grid. Each table
cell reports the posterior mean of that draw-wise metric and its equal-tailed
95% interval. This distinction matters because the metrics are nonlinear: the
posterior mean of a metric need not equal the metric evaluated at a posterior
point path.

The source for each model, family, target level, and criterion remains the
case-specific v9 selection frozen before replay. The resulting intervals are
conditional on the selected source, fixed data set, evaluation grid, and
reservoir realization. They do not represent repeated-simulation,
reservoir-design, or selection uncertainty.

## Evidence Contract

- Validation branch: `validation/independent-metric-intervals-v1-1.0.0`
- Validation handoff: `4790c9814855e06aa34505a9da32533e2748fdf6`
- Scientific execution: `e7479a930f5c9c56fa315ad18cbab9f73016c8b4`
- Promotion: `qdesn_dqlm_500obs_metric_intervals_v10_20260824`
- Promotion manifest SHA-256:
  `b8b6006666a9167d1fea3a2ac76a90d7bde30dcbac5fab6bc21f4b3e716c5798`
- Promotion ledger SHA-256:
  `0a11fde26fe963c91cda7b326ff04211b1bd5e3cad9b083f84b8b38dcfc3d298`
- Interface SHA-256:
  `9d845ad06686b82c5ce57b2762784d92da7a846990843f9e9fd9a0d445b061b4`
- Article asset manifest SHA-256:
  `2c268d5cac16fc151e384a9311a59579276e1dec094a84f0d2421ea956e0a248`
- Rollback authority:
  `qdesn_dqlm_500obs_trainonly_article_v9_canonical_gap_20260821`

The article builder verifies all promotion-level hashes and every file in the
16-file compact ledger before writing any table. The generated article manifest
then hashes every article-facing TeX and CSV artifact. After source-hash
verification, the builder applies a deterministic publication-only style pass
to the six family tables: captions are shortened without changing their
statistical contract, table contents are single-spaced, and explicit page
boundaries combine with here-or-top placement. This prevents adjacent family
panels from being packed together, clipped, or vertically stranded on
float-only pages.

## Statistical Summary

Across the 27 MCMC family-quantile-criterion cells, Q-DESN exAL-RHS has the
lowest posterior mean in 11 cells, Q-DESN AL-RHS in 8, DQLM in 4, and exDQLM
in 4. The two Q-DESN variants therefore account for 19 of 27 cellwise minima.
The lowest and second-lowest equal-tailed intervals overlap in every cell, so
the article reports the rankings as conditional posterior-mean summaries and
does not claim decisive posterior separation.

There are 159 PASS and 3 WARN MCMC source-metric diagnostics. Two warning
sources enter displayed cells and are marked at the metric level. Diagnostic
status is disclosed but is not used as a numerical exclusion rule.

## Article Integration

The builder is:

```sh
Rscript scripts/build_independent_validation_metric_intervals_v10.R
```

Before the validation branch is integrated into the shared validation
authority, the task worktree can be supplied explicitly:

```sh
Rscript scripts/build_independent_validation_metric_intervals_v10.R \
  --validation-root /data/jaguir26/local/src/exdqlm__wt__independent_metric_intervals_v1_1p0p0
```

The checker is:

```sh
Rscript scripts/check_independent_validation_metric_intervals_v10.R
```

The main article now defines the three draw-wise criteria, reports MCMC
posterior metric intervals, and includes a generated, evidence-bounded
interpretation. The supplement reports the approximate VB interval panels and
separates the older five-chain point-path sensitivity from the interval
estimand.

## Verification

The builder and checker both pass against the frozen validation worktree:

```sh
Rscript scripts/build_independent_validation_metric_intervals_v10.R \
  --validation-root /data/jaguir26/local/src/exdqlm__wt__independent_metric_intervals_v1_1p0p0
Rscript scripts/check_independent_validation_metric_intervals_v10.R
```

The check covers the 72-row article grid, all pinned source hashes, draw and
chain counts, interval ordering, diagnostic disclosure, the 27-cell MCMC
winner audit, generated-asset hashes, manuscript wiring, and the family-panel
page contract.

`latexmk` is unavailable in the audited environment, so both manuscripts were
compiled to convergence with the repository's documented
`pdflatex`--`bibtex`--`pdflatex`--`pdflatex` fallback. The main article has 39
pages and the supplement has 41 pages. Main pages 23--25 and supplement pages
22--24 were rasterized and inspected; all six panels are complete, aligned,
and free of clipping or overlap. The final logs contain no unresolved
references or citations. They retain two pre-existing, out-of-scope overfull
boxes: 4.77695 pt in the joint-model prose of `main.tex` and 0.65868 pt in a
supplementary section title.

No campaign process or campaign-named tmux session remains active. The compact
promotion is 636 KB and contains no fitted `.rds`, `.rda`, or `.RData`
payloads. The ignored scientific replay cache is approximately 1.5 GB and the
orchestration evidence is 13 MB; both remain in the validation worktree and
must stay outside the article snapshot.

## Integration Order And Rollback

1. Integrate validation commit `4790c981...` into the shared validation branch.
2. Merge this article branch into current Article-v2 `origin/main`.
3. Run the builder without a validation-root override and run the checker.
4. Compile `main.tex` and `qdesn-supplement.tex` to convergence.
5. Publish the article-only snapshot to Overleaf through command-line Git.

If verification fails, retain the v9 article assets and use the rollback
authority named above. Runtime caches and fitted-model binaries are not article
assets and must not be copied into the article repository or Overleaf snapshot.

At this audit, shared validation is at
`c4f68b86877538ecbb9b090b7dd4edeb45efe257` and does not yet contain the v10
handoff. Article-v2 `origin/main` is
`e688075c3e7950785e1c0ce4ea782130952edccd`, which is the exact base of this
task branch. The required disposition after this branch is pushed is:

`READY_FOR_INTEGRATION`
