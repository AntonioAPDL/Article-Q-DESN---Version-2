# PriceFM Paper-Aligned Article Table, 2026-08-11

## Purpose

This article-only update aligns the primary PriceFM application table with the
model-comparison structure in the latest PriceFM preprint while preserving the
existing region/fold analysis as supplementary evidence. It does not use the
active Stage-R53 campaign, refit a model, or change a PriceFM registry.

## Upstream Audit

The latest arXiv submission available on 2026-08-11 is:

- arXiv `2508.04875v4`, revised 2026-05-08;
- source archive SHA256
  `76fa40e20bb07ccf556eca3ba92fc7e1720fd31ab554151466b546086872be6e`;
- released PriceFM repository commit
  `c72d1228bde80417d5cc782521328e02ab5401c3`.

PriceFM Table II reports full-shot results for naive, time-series, graph, and
PriceFM models. Table III reports leave-one-region-out zero-shot results for
generic foundation models. The present Q-DESN workflow fits and
validation-selects one specification per region/fold using target-region data,
so Table II is the relevant analogue. Table III is not a valid primary ranking
surface for these fits.

## Direct Metric Reconstruction

The frozen full-surface registry contains 114 region/fold decisions but only
retains AQL. AQCR, MAE, and RMSE were reconstructed read-only from the existing
`panel_metric.csv` records by matching:

```text
region, fold, method_id, AQL
```

Only `split = test` and `unit = original` rows were accepted, with AQL
tolerance `1e-8`. All 114 Q-DESN rows and all 114 PriceFM rows matched. Duplicate
matches had identical AQL, AQCR, MAE, and RMSE. Reconstructed AQL agrees exactly
with the frozen registry apart from floating-point roundoff below `4e-15`.

Cell-macro means over 38 regions and three folds are:

| Model | AQL | AQCR (%) | MAE | RMSE |
|---|---:|---:|---:|---:|
| Selected Q-DESN | 6.826019 | 2.644375 | 16.727651 | 25.453092 |
| Released PriceFM checkpoint replay | 7.038685 | 0.000000 | 17.273667 | 26.335538 |

Relative to the released-checkpoint replay, Q-DESN reduces AQL by 3.02%, MAE
by 3.16%, and RMSE by 3.35%, with the tradeoff of nonzero quantile crossing.

## Paper-Reported Context

The lower panel of the new table reproduces the numerical values in PriceFM
version 4, Table II. Those values are cited, labeled paper-reported, and not
presented as a direct rerun. In particular, the paper's optimized full-shot
PriceFM AQL (`5.80`) is distinct from the released-checkpoint fold-aligned
replay AQL (`7.039`). The two values are not interchangeable.

## Article Changes

- `main.tex` now uses the PriceFM-aligned table as the primary comparison and
  explains why Table II, rather than Table III, is applicable.
- `qdesn-supplement.tex` retains the prior fold-level decision table as a
  secondary diagnostic.
- `refs.bib` identifies PriceFM version 4 and its revision date.
- `tables/pricefm_paper_aligned_main_comparison.csv` preserves machine-readable
  values, paper-reported ranks, and panel provenance.
- `tables/pricefm_paper_aligned_main_comparison_manifest.json` records source
  hashes, aggregation rules, and mutation guards.

## Interpretation Guardrails

1. Only the two direct-replay rows are head-to-head comparable.
2. PriceFM Table II values provide full-shot context; they do not create a
   cross-panel statistical rank for Q-DESN.
3. PriceFM Table III is a zero-shot experiment and is not the primary analogue
   for region/fold-specific Q-DESN fits.
4. Stage-R53 remains in progress and is excluded from this update. Any future
   R54 promotion must regenerate the table from a newly frozen registry.
5. No article claim should describe Q-DESN as uniformly superior to PriceFM.

## Overleaf File-Limit Cleanup

The first authenticated Overleaf push was rejected because the project had
reached its 2,000-file limit. A scoped dependency audit identified two obsolete
PriceFM presentation generations: the original `pricefm_application_*` assets
and the later `pricefm_stage_m_*` assets. Both summarize only 42 region/fold
cells from 15 regions, are superseded by the authoritative 114-cell
`pricefm_full_*` surface, and are not referenced by either `main.tex` or
`qdesn-supplement.tex`.

Eighteen legacy presentation outputs were therefore removed from the current
tree: twelve generated table/manifest files and six generated figures. Their
contents remain recoverable from Git commit `652f113`; no source code, model
output, current full-surface asset, or non-PriceFM file was removed. This lowers
the tracked tree from 1,984 to 1,966 files and leaves room for the validated
paper-aligned table on Overleaf.

## Validation

The following checks passed:

- the manifest parses with `jq`;
- all 13 local metric-source hashes and the frozen registry hash match;
- all 228 method-by-region/fold metric rows are recoverable, and all duplicate
  matches agree on AQL, AQCR, MAE, and RMSE;
- all 14 paper rows, including the reported rank column, match the PriceFM
  version 4 source table exactly;
- the machine-readable comparison has 2 direct-replay rows and 14 contextual
  paper rows with finite metrics;
- `git diff --check` passes.

`latexmk` is unavailable on the validation host, so the repository README
fallback was used. The main article was compiled with `pdflatex`, `bibtex`, and
three additional `pdflatex` passes; the supplement used `pdflatex`, `bibtex`,
and two additional `pdflatex` passes. The final PDFs contain 42 and 39 pages,
respectively. Final log scans found no unresolved references, undefined
citations, overfull boxes, fatal errors, or other warnings. The rendered
PriceFM main-table page and the supplementary diagnostic page were also
inspected for clipping and readability.
