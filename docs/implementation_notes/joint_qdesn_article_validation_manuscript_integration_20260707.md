# Joint QDESN Article Validation Manuscript Integration

Date: 2026-07-07

## Purpose

This note documents the manuscript integration that follows the Phase 110 article
asset build. Phase 110 generated verified tables and figures from:

- Phase 107 selected VB freeze:
  `application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707`
- Phase 109 article-candidate MCMC launch:
  `application/cache/joint_qdesn_mcmc_article_phase109_20260707`

The present pass wires those assets into `main.tex` and revises the surrounding
simulation-study prose.

## Manuscript Changes

The integration updates:

- the abstract, to mention both the single-quantile TT500 benchmark and the
  separate joint multi-quantile validation;
- the literature/model-framing paragraph on independent quantile fits and joint
  quantile-vector readouts;
- the opening of Section 5, to state that the simulation section has two
  complementary parts;
- the joint multi-quantile subsection, replacing the older Phase 105 VB-only
  evidence with the Phase 110 table wrapper:
  `tables/joint_qdesn_article_validation_tables.tex`;
- figure references, replacing the older Phase 105 diagnostics with Phase 110
  summary and MCMC fit-reference diagnostics.

## Interpretation Policy

The manuscript now makes three distinctions explicit.

1. Rows labeled QDESN use the AL working likelihood, while rows labeled exQDESN
   use the exAL working likelihood. The modifier `joint` or `independent`
   describes the readout structure, not a separate likelihood.
2. Phase 107 is the source for VB fit and held-out forecast validation.
3. Phase 109 is a VB-initialized MCMC fit-reference layer for the primary joint
   QDESN row. It is not described as MCMC forecast validation.

The reported gate is `review`, not `fail`, because implementation gates pass
but Phase 107 and Phase 109 retain review-level VB diagnostics.

## Verification

The manuscript was compiled into a temporary output directory so tracked build
artifacts were not modified:

```bash
mkdir -p /tmp/qdesn_phase110_compile
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=/tmp/qdesn_phase110_compile main.tex
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=/tmp/qdesn_phase110_compile main.tex
```

The second pass completed with no warnings reported by:

```bash
rg -n "Warning|Undefined|Overfull|Underfull|Error|Missing" \
  /tmp/qdesn_phase110_compile/main.log
```

## Remaining Editorial Work

The next editorial step is a full simulation-section polish after the author
decides how many Phase 110 tables should remain in the main article versus move
to the supplement. The current integration is intentionally complete and
reproducible; it favors transparent evidence over brevity.
