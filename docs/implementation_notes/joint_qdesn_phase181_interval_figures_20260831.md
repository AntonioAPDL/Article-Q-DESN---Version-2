# Joint Q-DESN Phase181 interval figures

Date: 2026-08-31

This note records the article figure update for the joint multi-quantile
simulation. The update adds two main-text figures that visualize the same
model-by-scenario comparison as the Phase181 DGP-integrated score table:

- fit-period RMSE against the known conditional quantile paths;
- forecast-period DGP-integrated finite-grid quantile score, denoted
  \(\aCRPS\).

The figures use the same eight simulation settings and four model classes as
the table. Each cell uses eight MCMC chains and 1,000 retained draws per chain.
For the independent regressions, draws across quantile levels are combined with
the pre-specified chain-balanced product coupling used by the Phase181 scoring
analysis. Quantile grids are monotonically rearranged before computing the
displayed fit RMSE intervals and before reporting the forecast score intervals.

Fit intervals are recomputed from the retained posterior coefficient draws and
the fixed Phase180 article fixtures. Forecast intervals are copied from the
Phase181 DGP-integrated score summary, so the figure values match the main
score table exactly. The crossing labels shown in the figures are canonical
raw adjacent-level crossing counts in the posterior-mean grids before monotone
rearrangement. The totals by model are:

- fit: Joint Q-DESN 0, Independent Q-DESN 7, Joint exQDESN 0, Independent
  exQDESN 0;
- forecast: Joint Q-DESN 1, Independent Q-DESN 25, Joint exQDESN 0,
  Independent exQDESN 0.

All crossing counts after monotone rearrangement are zero. The figures do not
change any numerical tables, fitted models, or scientific rankings. The
forecast figure remains descriptive because all paired joint-minus-independent
contrast intervals include zero.

Reproduction commands:

```bash
Rscript scripts/build_joint_qdesn_phase181_interval_figures.R
Rscript scripts/check_joint_qdesn_phase181_interval_figures.R .
Rscript application/tests/test_joint_qdesn_phase181_interval_figures.R
```

The builder writes:

- `tables/joint_qdesn_phase181_metric_interval_summary.csv`;
- `figures/joint_qdesn_simulation/joint_qdesn_phase181_fit_oracle_rmse_intervals.pdf`;
- `figures/joint_qdesn_simulation/joint_qdesn_phase181_forecast_dgp_score_intervals.pdf`;
- `tables/joint_qdesn_phase181_interval_figures.tex`.

Validation completed during integration:

- `Rscript scripts/check_joint_qdesn_phase181_article_projection.R .`
- `Rscript scripts/check_joint_qdesn_phase181_interval_figures.R .`
- `Rscript application/tests/test_joint_qdesn_phase181_score_stability_extension.R`
- `Rscript application/tests/test_joint_qdesn_phase180_balanced_dgp_score_packet.R`
- `Rscript scripts/finalize_independent_validation_dgp_oracle_figures_v14.R`
- `Rscript scripts/check_independent_validation_dgp_oracle_figures_v14.R .`
- `Rscript application/tests/run_tests.R`
- `git diff --check`
- main article and supplement compilation with the documented
  `pdflatex`--`bibtex`--`pdflatex`--`pdflatex` sequence.

The final compile produced a 41-page main article and a 50-page supplement.
The warning scan found no undefined references, undefined citations, fatal
TeX errors, or BibTeX errors.
