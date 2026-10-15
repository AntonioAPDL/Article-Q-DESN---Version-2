# Independent Forecast Reporting Revision

Primary reporting now uses the first 300 targets; the supplement contains
the 500-target sensitivity. The former 1,000-target numerical reporting is
deprecated and excluded from active TeX inputs and the article-only allowlist.
Its historical sources remain immutable in the research repository. Both
manuscripts disclose the retrospective change and prior forecast-guided
criterion-specific model selection.

Training remains 8501:9000. Primary targets 9001:9300 have ten origins;
sensitivity targets 9001:9500 have 17 origins, with 20 leads at the last origin.
The four model classes, three families, three levels, priors, seeds, explicit
Q-DESN M0 transition and historical runtime versions remain frozen. This
revision launches no fitting or forecasting. Both periods use the same
reconstructed draws; those realizations need not be identical to the earlier
ones. Original MCMC/VB fit values, source identities and fit PDFs are unchanged.

The policy is `application/config/independent_forecast_300_500_v1.json`.
The new forecast CSV contains 144 cells; the separate preserved-fit CSV has
72 cells. The validation packet repools three balanced chains per source and
checks each selected summary within 1e-6, retaining native draw dependence
and quantile rules. Population DGP check references are time-constant and
quadrature-verified; realized oracle references are recomputed by prefix.

All 36 selected VB sources were audited, but retained aggregate draws do not
support prefix intervals. VB fits remain; VB forecast panels are explicitly
omitted rather than relabeled or mixed with MCMC windows. Historical five-chain
point-path and numerical coupling sensitivities are archived, not active.

```sh
Rscript scripts/build_independent_forecast_300_500_v1.R
Rscript scripts/build_independent_forecast_300_500_proofs.R
Rscript scripts/check_independent_forecast_300_500_v1.R \
  --validation-root "$IND_VALIDATION_ROOT" \
  --build-root "$PWD/local_trackers/independent_forecast_300_500_v1/build"
```

The IND-only renderer reads tracked summaries and the existing figure style;
it does not load an inference package. It produces four vector figures,
family-level tables, numerical comparisons, provenance and a four-page ignored
review PDF with matching per-panel scales. The historical shared renderer
delegates IND to the current builder while preserving its other lanes.
This lane does not execute the global renderer. Historical display wrappers
and manifests remain byte-identical; current figure wrappers are included
directly by the manuscripts.

The verifier covers semantic completeness, target weighting, finite balanced
summaries, source stability across windows, preserved fit scores, VB omissions,
DGP references, numerical replay, current routing and disclosure. With proof
paths it also checks actual recorder inputs and reference/box diagnostics.
The source recovery is `bba23c9317a37ee1c0b6ac181c7cc37bbd4e1513`; the
validation publication packet is
`validation/fitforecast_v2/promotions/independent_forecast_300_500_v1/` on
`validation/independent-forecast-300-primary-500-sensitivity-20261015`.

Article preparation is on
`work/independent-forecast-300-primary-500-sensitivity-20261015`, based on
`53e4912387b152a2c78b8f242beff77e42eeac52`. The coordinator integrates
validation first and then article work, rebuilds the combined sources and
publishes the article-only Git snapshot. This branch does not alter live main
or Overleaf. Large posterior payloads, proof PDFs and review PDFs stay ignored.
