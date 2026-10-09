# PRO-review presentation revision

## Scope

The presentation derivatives address C27 and N09 without refitting, rescoring,
changing numerical authority, smoothing, projecting quantiles, or selecting a
different model. Original scientific summaries, figure wrappers, source PDFs,
and their authority manifests remain unchanged. Distinct presentation wrappers
retain the original figure labels and estimator definitions.

The six active simulation derivatives use ordinary text of 10.4 points in the
native PDFs. At the current insertion widths, their minimum effective ordinary
text is approximately 9.0 points for joint and 9.2 points for independent
figures. Likelihood colors, model symbols, posterior means, intervals, oracle
references, separate panel scales, and crossing-percentage definitions are
preserved. The joint fitting figure still has point diagnostics only: no
unavailable posterior interval has been added.

## GloFAS plotting inputs

The frozen Search III authority ledger identified the truth-free design
`part4_shared_design_truth_free.rds`, SHA-256
`a2fbcec6523802f01c98ec272253e58a598a5adc5c7b0f9063b615b36c07bcf9`,
and scoring-only sidecar `part4_scoring_panel_sidecar.rds`, SHA-256
`24be9fa631bca346a04a7a855bff5ef3ebc7bf5c748fbade7a213d88fdfe63e6`.
Both sizes and hashes were independently verified before read-only extraction.

The compact plotting extracts contain exactly:

- 30 consecutive historical daily dates, 26 November–25 December 2022;
- 51 issued member paths over 28 dates: 1,428 member/date records;
- 28 scoring-only truth records, 26 December 2022–22 January 2023.

The native transformed ordinates are used directly, without a second log
transformation. The source member weights are retained. R `quantile(type=8)`
reconstructs every retained raw-ensemble quantile to within `1e-12`, and the
truth sidecar matches public scoring truth to within the same tolerance.
All seven quantile levels and 196 ordinates for each illustrated model are
preserved. The common vertical limit `[0,6]` contains every plotted historical,
member, truth, and model ordinate; no extreme path was clipped or discarded.

Issued-product release time and exact historical issued-product version were
not authenticated from these fields. They are explicitly marked unavailable
in the provenance record. The plotting context is not represented as the
historical fitting-window length. No credible limits were recovered or added.

The main figure has three vertically stacked panels: data and all issued
members, Independent AL, and Normal Ridge. Historical USGS uses forest-green
filled dots; scoring-only future USGS uses dark-red open dots; GloFAS uses
orange; seven model quantiles use a restrained blue palette with dashed lower
levels and solid upper levels. Thin connecting lines, a common vertical scale,
and explicit panel date ranges retain interpretability in grayscale.

The original full-family figure remains available through
`\GlofasApplicationCurrentFullComparisonFigure`. The main five-column table
removes only the internal status column. Its seven rows, numeric rounding,
negative Normal RHS reduction, and complete scientific comparison are retained.

## Reproduction

The authenticated compact extracts are tracked together with their source
hashes in `tables/glofas_search3_review_plot_input_provenance.json`. Reproducing
the presentation does not require reading the large frozen design:

```bash
Rscript scripts/build_qdesn_pro_review_presentation.R
python scripts/build_glofas_review_figures.py
python application/tests/test_pro_review_presentation.py
python scripts/build_glofas_review_figures.py --check
```

Use R 4.6.0 with `ggplot2`, `jsonlite`, and Cairo, and the pinned PyMuPDF 1.26.5
environment documented by the legacy GloFAS presentation builder. The Python
test is a standalone `unittest` suite and does not require pytest. Generated
PDF creation dates are normalized in place without changing byte lengths or
scientific marks. Asset/source/script hashes are recorded in
`tables/qdesn_pro_review_presentation_manifest.json`.

If authentic extracts must be recreated, the separate read-only extraction
script requires an explicit frozen authority ledger and validates both source
objects before reading them:

```bash
Rscript scripts/extract_glofas_pro_review_plot_inputs.R \
  --authority-ledger FROZEN_AUTHORITY_LEDGER \
  --output-dir tables
```

The extraction does not modify the runtime or import fit/posterior objects.
The production ledger's local paths are not copied into the public extracts
or provenance. Do not use an unrelated or newer design to satisfy the hashes.

## Verification

Five focused presentation tests pass: source/artifact hashes, authenticated
compact inputs and truth, seven-row numeric table preservation, effective PDF
text size/vector/clipping checks, and active presentation aliases. The legacy
six-figure deterministic rebuild checker also passes. Enlarged simulation and
GloFAS previews were visually inspected; the integrated manuscript placement
and clean source closure remain coordinator verification gates.

The independent v14 and current pure-DESN publication checkers now authenticate
the separate presentation manifest before inspecting the active derivatives.
They still verify the unchanged original scientific summaries, authority
manifests, wrappers, and PDFs. The historical corrected-v4 checker recognizes
the active derivative wrapper and delegates its current-reader checks to the
same pure-DESN checker; all historical v4 numerical and provenance checks are
retained. No fit, score, interval, crossing, or posterior-target gate was removed.
The structured scale--shape disclosure assertion now checks the precise
analytic scale integral and one-dimensional bounded-shape quadrature, rather
than requiring the obsolete phrase “numerical quadrature.”

Combined-source checks passed under pinned R 4.6.0:

```bash
Rscript scripts/check_joint_qdesn_pure_desn_article_projection.R
Rscript scripts/check_joint_qdesn_corrected_article_projection_v4.R
Rscript scripts/check_independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.R \
  --validation-root AUTHENTIC_FROZEN_EXDQLM_VALIDATION_WORKTREE
```

The current JOINT checker passed 210 checks, and the independent checker passed
366 checks over 72 point rows and 216 interval roles. Its explicit validation
root is required in an isolated integration worktree because the historical
configuration assumes a sibling validation checkout. That override changes
only the fixture location; the frozen validation HEAD and all source hashes
remain enforced.
