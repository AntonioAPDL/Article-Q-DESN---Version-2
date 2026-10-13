# Sections 5–7 reader-centered revision

Editorial base: `021960177769f491fedfd1782cadd007a235293e`.
No scientific authority, fitted model, prior, target, score, or selection
decision is replaced by this revision.

## Implemented allocation of information

- The two simulations now each have design and results subsections. The
  independent design introduces linear state evolution and quantile-centered
  observation errors before its forecast comparison.
- The detailed generating table, disturbance scales, deterministic initial
  states, generation warmup, retained indices, and draw-wise metric equations
  move into the supplement. Forecast figures remain in main; fitting recovery
  remains supplementary.
- The independent comparison retains criterion-specific specifications and
  historical forecast-based refinement. Replaying posterior score summaries
  does not erase that selection history. Training-only preprocessing is not
  represented as protection from evaluation-based selection.
- The package-paper citation is separate from the software manual. Main
  omits execution versions; supplement preserves the scoped exDQLM 1.1.1
  refresh and inherited Q–DESN execution records. Current results are not
  retrospectively relabeled 1.1.2.
- Multiquantile results distinguish posterior-mean-grid ordering from score
  performance. The unchanged rates are 0.021%, 5.488%, 0%, and 0.606% for
  MQ–DESN AL, Q–DESN AL, MQ–DESN exAL, and Q–DESN exAL, respectively,
  using 47,520 adjacent comparisons per model. Posterior score intervals
  remain conditional on averaged future features, not variation between
  origins or repeated generating realizations.
- GloFAS is organized around measurements/products, quantile forecast
  correction, and results. The unknown future reference path, augmented
  ensemble weighting, realized weather, protected selection window, and
  scoring-only future USGS remain explicit. Reference/discrepancy component
  settings, no-score boundary, three/one component crossings, and exact
  convergence information remain supplementary.
- The main GloFAS score display retains seven models and four columns,
  omitting only the reduction-versus-raw column. Its values and the common-
  window Figure 4 are unchanged.
- PriceFM receives a short domain-specific pretraining explanation, matched
  fixed-regional design, and compact results. The higher aggregate Q–DESN
  AQL and unverified covariate issue-time vintages remain. No incomplete old
  horizon analysis is relabeled as a current 114-comparison result.
- Public development-stage names leave the active prose, tables, PDF text,
  captions, and alternative descriptions. Original internal names and
  provenance remain in Git.
- The three abstract findings placeholders and recent model/introductory
  exposition remain unchanged. A page break before the electricity-price
  application keeps the streamflow table and figure with their application.

## Presentation and dependency contract

`tables/qdesn_sections5_7_presentation_manifest.json` pins 26 original sources
and 20 derivative outputs: seven vector PDFs, six tables, five caption
wrappers, and two document-specific overrides. Original scientific and MQ
display manifests remain immutable. The PriceFM vector marks retain their
score coordinates under a documented page-placement transformation, with
9-point lettering at natural manuscript width.

The new builder/checker and mutation tests constrain permitted label, caption,
and administrative-column changes. Existing scientific checkers retain
their hashes and numerical assertions; placement assertions follow the new
effective inputs rather than requiring inactive wrappers. The source upload
contains the selected derivatives, not superseded display copies or private
provenance ledgers. The generated dependency inventory contains 102 approved
files and is checked against the expanded TeX inputs.

## Verification

Passed on the combined editorial tree:

- Four clean manuscript builds: identified main/supplement 33/86 pages;
  anonymous main/supplement 31/85 pages, US Letter review layout retained.
- New presentation checker, deterministic regeneration, and 20 mutation tests.
- Combined Python display/projection tests: 50 tests passed.
- Reader-focused R regression: 53 checks.
- Final manuscript checker: 19 immutable scientific files, 216 independent
  roles, 32 multiquantile forecast and 32 fit comparisons; abstract 142 words.
- Multiquantile projection checker: 534 checks; all 19 mutation cases rejected.
- Original GloFAS scientific projection checker and its focused regression.
- PriceFM original projection check and four isolated mutation tests;
  all 114 cases, 38 regions, and ten original output hashes retained.
- Bibliography/initialization checks, dependency-inventory check, syntax
  checks, and `git diff --check`.

Actual-size inspection covered the state display, reduced GloFAS table,
regional PriceFM plot, and representative GloFAS derivatives. No fit or
score calculation was rerun. These are scoped manuscript and scientific-
invariance checks, not a claim that every historical repository fixture or
every journal submission requirement has been satisfied.

## Publication boundary

Integration and deployment use the existing command-line Git publishers.
Only a fresh main read-back establishes integration. Only matching canonical
snapshot/direct Overleaf commit and tree, with the correct source marker,
establishes publication. Authentication failure leaves publication pending;
the locally compiled revision is not described as already visible in Overleaf.
