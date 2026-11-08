# GloFAS Corrected Hybrid Authority Integration Closeout

Date: 2026-11-07

## Decision

The article projection uses a hybrid, source-explicit GloFAS authority:

- Parts 1--3 retain the qualified Search III outputs from source commit
  `e2a3be97853b1af9c8cb269a3e065336ca5590f3`.
- Part 4 uses the qualified October coherent target from source commit
  `60daab261d52eec0ae24060babe186d618303e2b`.
- The November same-family target at
  `fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6` remains preserved as adverse
  root-cause evidence, but it is not an active article authority.

This is a reporting integration. It did not fit, forecast, retune, rescore, or
select a model on the protected forecast window.

## Scientific Contract

The qualified Part 4 target uses a common Gaussian future-path prior
moment-matched from 500 truth-free recursive Part 3 Normal-RHS trajectories.
That prior replaces, rather than multiplies, future-reference AL or exAL
working-likelihood factors. The 51 issued GloFAS members remain ordinary
likelihood factors at each of 28 horizons, for 1,428 factors per quantile
level. Future USGS observations are scoring-only.

The quantile displays report Monte Carlo expectations of each fitted
conditional-quantile readout over the shared driver paths. They are not
Gaussian path-factor quantiles. The active authority retains raw crossings
and applies no clipping, truncation, isotonic projection, or post-hoc ordering
repair.

All 18 corrected Part 4 fit units pass the frozen numerical and quadrature
gates. The common path-prior SHA256 is
`0202bc19e26d84d6cbb55c2256a2071695f9c386c9dc64933005bd4d5acbb357`.

## Descriptive Result

On the protected 28-day issued window, grid aCRPS is 0.8429 for Normal Ridge,
0.9299 for independent AL, 0.9463 for Normal RHS/VB, 0.9544 for MQ AL,
1.0501 for independent exAL, 1.0875 for MQ exAL, and 1.4360 for raw GloFAS.
These are descriptive held-out results and did not select the target, family,
reservoir, priors, or stopping rules.

## Installed Surface

The integration installs four public PDFs and twelve public table/data assets
under the namespace
`glofas_hybrid_part123_search3_part4_october_20261107`. Their exact byte
membership and hashes are recorded in
`tables/glofas_hybrid_part123_search3_part4_october_20261107_article_asset_manifest.csv`.
The active contract is `tables/glofas_hybrid_current_authority.json`.

The main manuscript and supplement both select the namespaced alias file.
Appendix role routing, the Overleaf allowlist, dependency inventory, and
editorial receipts are updated to the same authority. Historical November
assets remain available for provenance but are not selected by either
manuscript.

## Validation

The following checks pass without scientific execution:

- focused hybrid-authority mutation tests;
- forecast-application exposition check and 57 mutation rejections;
- Sections 5--7 presentation check and 36 tests (one environment-dependent
  test skipped);
- statistical-language check and 89 mutation rejections;
- MQ nomenclature check and 22 tests;
- appendix-compression and essential-appendix tests;
- authenticated appendix receipt refresh and check;
- isolated `pdflatex`--BibTeX convergence builds for both documents.

The isolated main build has 37 pages and SHA256
`259119c86e9113940c3513dd3c8be61e4d5409e32ee1c739ac5068d970d3da86`.
The isolated supplement build has 32 pages and SHA256
`7ed041566a26257ef7fb8e21a8a221b698bdfe0c29c3d44425d16dd6ec747195`.
Final log scans report no unresolved references or citations, fatal errors,
multiply defined labels, hyperref warnings, or overfull/underfull boxes.

## Promotion Boundary

This closeout prepares an isolated integration branch for coordinator review.
It does not merge `main`, update an Overleaf branch, or delete the historical
adverse evidence. Promotion should use the committed authority guard and the
article allowlist, not runtime directories or uncommitted source packets.
