# Independent Simulation MCMC Visualization Audit

Date: 2026-07-30

## Scope

This audit covers the article-facing independent single-quantile MCMC
comparison only. It does not change validation logic, model fitting,
application code, the joint multi-quantile study, or any reported numerical
value.

The figure is generated from the same frozen 36-row metric envelope used by
Tables 5--7:

`qdesn_dqlm_500obs_mcmc_metric_envelope_20260727_article_envelope.csv`

The source contains four models, three simulation families, three target
quantile levels, and three lower-is-better criteria. The complete display
therefore contains 108 values.

## Structural Findings

- The comparison unit is one family, quantile level, and metric.
- The values are metric-wise calibration minima. Fourteen of the 36
  model-family-quantile rows use different source candidates for at least two
  displayed metrics.
- A connected profile would falsely suggest that one specification or seed
  produced all points in a model trajectory.
- A single additive or weighted score would mix fit RMSE, forecast MAE, and
  forecast check loss without a defensible common scale.
- Raw forecast MAE ranges from about 1.10 to 23.91. Grouped bars on a linear
  scale would compress most competitive values, while a log axis would make
  the other two criteria harder to read.
- Rank-only summaries would hide the magnitude of poor cases. In particular,
  the largest forecast-MAE value is about 11.8 times the best value in its
  comparison cell.
- The source contains 22 PASS, 8 WARN, and 6 FAIL row-level signoffs.
  Diagnostic status must remain visible but is not a metric-exclusion rule.

## Selected Design

The article figure uses a 3-by-3 faceted cell matrix:

- columns: Gaussian, Laplace, and Gaussian-mixture families;
- rows: fit RMSE, forecast MAE, and forecast check loss;
- cell columns: target quantile levels 0.05, 0.25, and 0.50;
- cell rows: DQLM, exDQLM, Q-DESN AL--RHS, and Q-DESN exAL--RHS.

Each cell prints the absolute value reported in the table. Fill intensity is
based on

`log2(value / within-cell minimum)`,

where the minimum is taken over the four models for a fixed family, quantile,
and metric. The normalization permits visual comparison of relative
departures without combining the three statistical criteria. A dark outline
and bold text identify the within-comparison minimum. Metric-source WARN and
FAIL signoffs are marked by a triangle and cross.

This design gives the exact values, preserves the natural comparison unit,
shows practically important multiplicative gaps, and remains interpretable
in print. It deliberately does not use connecting lines, a global model
ranking, win counts, or a composite score.

## Reproducibility Contract

The generator:

`scripts/build_qdesn_mcmc_validation_figure.R`

performs the following checks before plotting:

1. the source path and SHA-256 match the frozen article manifest;
2. the source registry hash matches the article manifest;
3. all 36 model-family-quantile rows are present exactly once;
4. all 108 plotted values are finite and positive;
5. every contributing metric source has PASS, WARN, or FAIL signoff metadata;
6. metric source paths remain inside the shared validation worktree.

It writes:

- `figures/independent_simulation/qdesn_mcmc_metric_envelope_heatmap.pdf`;
- `tables/qdesn_validation_mcmc_figure_data.csv`;
- `tables/qdesn_validation_mcmc_figure_manifest.txt`.

The plotted-data CSV retains the absolute value, within-cell minimum, relative
ratio, winner flag, metric-source candidate, run tag, relative evidence path,
artifact hash, promotion identity, and source registry hash for every cell.

The independent checker:

`scripts/check_qdesn_mcmc_validation_figure.R`

reconstructs all 108 long-form cells directly from the frozen source, verifies
their numerical and provenance fields, recomputes the 27 within-comparison
minima, and checks the generated data and PDF hashes against the figure
manifest.

## Interpretation Limits

- Shading is comparable as a multiplicative departure from a cell-specific
  best, not as an absolute comparison among different metrics.
- The figure summarizes one frozen dynamic source design and does not estimate
  Monte Carlo variability across independently generated data sets.
- A winning cell is a metric-wise minimum, not evidence that the same fitted
  specification jointly minimizes all three criteria.
- WARN and FAIL markers qualify the contributing source diagnostics and must
  remain visible in any article-facing rendering.

## Verification Results

- Frozen authority rows verified: 36.
- Plotted numerical values verified: 108.
- Within-family-quantile-metric minima verified: 27.
- Source registry hash:
  `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`.
- Figure data SHA-256:
  `b30459aa3ac4fb2ec66ab636c50559218a80a9180215227b60d55f44c84043f2`.
- Figure PDF SHA-256:
  `50a06c2e967fc40cfad6465950f266201702409c32cebff3e45ce58377d2b485`.
- Two consecutive figure builds produced identical PDF and CSV hashes.
- The active table checker verified all 108 displayed table values and
  reported `article_numeric_update: FALSE`.
- The main manuscript compiled to 39 pages without unresolved references,
  missing citations, overfull boxes, or fatal errors.
- The isolated arXiv source bundle included the renamed figure asset and
  compiled successfully after cross-reference convergence.

## Reproduction Commands

```sh
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla \
  scripts/build_qdesn_mcmc_validation_figure.R

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla \
  scripts/check_qdesn_mcmc_validation_figure.R

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla \
  scripts/check_qdesn_mcmc_current_best_validation_tables.R
```

The manuscript was checked with `pdflatex`, `bibtex`, and convergence passes
of `pdflatex`. The isolated upload bundle was built with
`scripts/build_arxiv_source_bundle.sh` and compiled independently.
