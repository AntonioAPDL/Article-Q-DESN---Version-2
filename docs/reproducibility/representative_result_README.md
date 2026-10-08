# Reproduce the joint simulation forecast comparison

This compact example reproduces the current eight-scenario, four-model MCMC
forecast-score table and its interval figure from one authenticated summary
CSV. The supplied script verifies its frozen hash, all 32 MCMC cells and
the crossing denominator before rendering. It preserves every table value,
interval endpoint, model and scenario, including less favorable results.

Run from this directory:

```bash
bash reproduce.sh
```

Requirements: bash, SHA-256 utilities, R (tested with 4.6.0), ggplot2 and its
dependencies, and Cairo PDF support with the same sans-serif fonts as the
published figure, plus Poppler's pdftotext and pdftoppm utilities. No Git checkout,
private path, remote access, runtime cache, model fit, or posterior draw file
is needed. PDF creation timestamps can change bytes without changing content.
The supplied check compares the figure's extracted text and its 150-dpi
rendering, and the TeX table byte for byte. Different font/library versions
can change the rendering; the check reports that difference rather than
silently accepting it.

The main output is
`figures/joint_qdesn_simulation/joint_qdesn_pure_desn_v1_forecast_dgp_acrps.pdf`.
The complete score table is
`tables/joint_qdesn_pure_desn_v1_score_table.tex`.
Its values and interval endpoints are compared with the supplied expected
table; the figure's text and pixels are compared with its expected vector PDF.

This is presentation reproduction, not an independent reconstruction of the
posterior draws, integrated scores, or fitted scientific campaign. The
summary evidence retains its provenance and limitations. Full fit/score
reproduction needs separately retained scientific inputs and substantially
greater computational resources. This example does not certify current
journal-specific code/data submission requirements.
