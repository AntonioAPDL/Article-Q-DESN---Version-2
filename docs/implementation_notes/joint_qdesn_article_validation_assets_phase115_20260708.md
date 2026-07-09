# Joint QDESN Phase 115 Article Validation Asset Refresh

Date: 2026-07-08

## Purpose

Phase 115 refreshes the article-facing joint QDESN simulation assets after the
Phase 113 selected-VB screening update and the Phase 114 MCMC article-reference
run. This stage does not fit models, run MCMC, regenerate fixtures, or change the
simulation design. It verifies frozen sources, filters the VB screening bundle to
the selected candidate, regenerates tables and figures, and records hashes for
the generated assets.

The refreshed sources are:

- selected VB source:
  `application/cache/joint_qdesn_vb_spec_screening_phase113_20260708`;
- MCMC reference source:
  `application/cache/joint_qdesn_mcmc_article_phase114_20260708`.

The selected VB candidate is:

```text
zeta2_16_inner10_gamma_zero_alpha0p5_tau0_0p5
```

## Audit Findings

The Phase 115 audit found that the article asset helper needed one important
generalization. The earlier Phase 110 source was already a selected freeze,
whereas the Phase 113 source is a screening bundle with four candidate
specifications. Without an explicit selected-candidate filter, model-level and
scenario-level article summaries could include repeated rows from all screened
candidates. Phase 115 fixes this by filtering every VB metric table with a
`candidate_id` column to the row marked selected in
`selected_spec_recommendation.csv`.

The refreshed evidence is:

| Check | Result |
|---|---:|
| Source manifest rows verified | 218 / 218 |
| Generated cache manifest rows verified | 7 / 7 |
| Article asset manifest rows verified | 23 / 23 |
| Selected VB source gate | review |
| Selected VB forecast raw crossings | 73 |
| Selected VB forecast contract crossings | 0 |
| MCMC reference gate | pass |
| MCMC scenario gates | 9 pass, 0 review, 0 fail |
| MCMC worker failures | 0 |
| MCMC raw crossings | 0 |
| MCMC contract crossings | 0 |

The overall article-asset gate remains `review` because the selected VB source
retains pre-rearrangement raw crossings. This is a diagnostic qualification, not
an implementation failure: the scored monotone contract quantiles are finite and
noncrossing. The MCMC reference layer is pass-level across all nine scenarios and
supports the selected joint QDESN RHS fit as a stable MCMC initializer.

## Implemented Changes

Phase 115 updates:

- `application/R/joint_qdesn_article_assets.R`;
- `application/tests/test_joint_qdesn_article_validation_assets.R`;
- `main.tex`;
- regenerated `tables/joint_qdesn_article_validation_*` assets;
- regenerated `figures/joint_qdesn_simulation/joint_qdesn_article_validation_*`
  diagnostics.

The asset helper now:

- verifies source manifests before table construction;
- identifies the selected VB candidate from `selected_spec_recommendation.csv`;
- filters selected-candidate metric tables before generating article rows;
- uses source-role language, such as selected VB source and MCMC reference source,
  rather than stale phase-number labels in generated readiness outputs;
- records generated table and figure hashes in
  `tables/joint_qdesn_article_validation_asset_manifest.csv`;
- writes a cache-level reproducibility bundle under
  `application/cache/joint_qdesn_article_validation_assets_phase115_20260708`.

The focused test now includes an unselected screening candidate and checks that
the article model summary contains only the selected four VB rows.

## Generated Assets

Main article table wrapper:

```text
tables/joint_qdesn_article_validation_tables.tex
```

The wrapper includes:

- `tables/joint_qdesn_article_validation_protocol.tex`;
- `tables/joint_qdesn_article_validation_vb_model_summary.tex`;
- `tables/joint_qdesn_article_validation_vb_scenario_summary.tex`.

Provenance and diagnostic wrapper:

```text
tables/joint_qdesn_article_validation_provenance_tables.tex
```

The provenance wrapper includes:

- source and computational controls;
- the diagnostic VB model table;
- the scenario-level VB summary;
- the MCMC scenario reference table;
- the gate summary.

Generated figures are stored under:

```text
figures/joint_qdesn_simulation/
```

These figures are diagnostics. The main manuscript currently relies on compact
tables for the primary statistical comparison.

## Command

The Phase 115 asset refresh command is:

```bash
Rscript application/scripts/110_build_joint_qdesn_article_validation_assets.R \
  --phase107-dir application/cache/joint_qdesn_vb_spec_screening_phase113_20260708 \
  --phase109-dir application/cache/joint_qdesn_mcmc_article_phase114_20260708 \
  --output-dir application/cache/joint_qdesn_article_validation_assets_phase115_20260708
```

The script option names retain the historical `phase107` and `phase109` labels
for backward compatibility. The generated outputs use source-role labels.

## Interpretation

The article text should make the following distinctions.

1. The VB table is the held-out fit and forecast validation layer. It compares
   joint and independent QDESN and exQDESN RHS rows under the same synthetic
   registry, quantile grid, fit window, and held-out block.
2. The MCMC table is a fit-window reference layer for the selected joint QDESN
   RHS row. It checks posterior-reference stability and VB initialization; it is
   not rolling-origin forecast MCMC.
3. Raw pre-rearrangement crossings are retained as diagnostics. Scoring uses the
   monotone contract quantile grid.
4. The joint QDESN RHS row has the lowest average held-out MAE among the four VB
   rows, but the margin over independent QDESN RHS is small. The result should be
   presented as evidence of competitive coherent multi-quantile behavior, not as
   a universal dominance claim.
5. The exQDESN rows are numerically stable and useful comparators, but they are
   farther from the oracle conditional quantiles in this validation bundle.

## Verification

The required focused verification is:

```bash
Rscript application/tests/test_joint_qdesn_article_validation_assets.R
```

Recommended manuscript verification is:

```bash
mkdir -p /tmp/qdesn_phase115_compile
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=/tmp/qdesn_phase115_compile main.tex
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=/tmp/qdesn_phase115_compile main.tex
```

Then inspect the log for unresolved references, warnings, overfull boxes, or
errors.

## Recommended Next Step

The next step is a publication-readiness pass over the simulation section, not a
new model launch. The pass should decide which provenance tables remain in the
main manuscript versus the supplement, keep the joint-validation interpretation
modest, and ensure the TT500 and joint multi-quantile studies are presented as
complementary validation designs.

## Main-Branch Reconciliation

After `origin/main` advanced with the Overleaf/GitHub reconciliation commits,
the Phase 115 article assets were rebased onto the current main branch and the
asset builder was rerun. The remote changes mainly removed legacy GloFAS
artifacts and did not overlap with the joint QDESN article-asset files. The
rebased article now keeps the compact joint-validation tables in the main text
and leaves MCMC overlays, distance plots, and provenance tables as diagnostic
assets rather than printed main-text figures.

The reader-facing prose was also tightened to avoid internal phase labels and
local shorthand in the main article. In particular, the main text now describes
the joint model as a joint quantile-vector readout with adjacent RHS shrinkage,
reserving QVP terminology for the literature connection to
\citet{KohnsSzendrei2025QVP}. The Discussion now refers to the joint
multi-quantile synthetic validation study rather than an internal phase label.
