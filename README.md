# Bayesian Conditional-Quantile Forecasting with Fixed Deep Echo State Network Features

This repository contains the working manuscript, supplement, bibliography, and
simulation tables for the Q--DESN article.

## Main Files

- `main.tex`: main article.
- `qdesn-supplement.tex`: standalone supplementary material.
- `refs.bib`: bibliography database used by both LaTeX files.
- `tables/`: generated simulation tables included by the main article.
- `Academic_Writing_Style_Profile_v0.2.md`: writing and formatting criteria
  used for manuscript revisions.
- `scripts/build_qdesn_simulation_tables.R`: script used to regenerate the
  simulation tables from external validation outputs.
- `application/`: reproducible GloFAS and PriceFM application workflows. The
  current article includes a completed one-origin GloFAS reference case and a
  PriceFM-aligned transfer benchmark. Source-controlled files define their
  reproducibility contracts; local data, caches, runs, logs, and generated
  outputs are ignored.
- `docs/`: audit notes, revision logs, and implementation notes.

## Build

Build the main article with:

```bash
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

Build the supplement with:

```bash
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
bibtex qdesn-supplement
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
```

Generated auxiliary LaTeX artifacts are intentionally not tracked. The main
PDF may be refreshed when syncing a manuscript-facing change to `origin/main`.

## arXiv Source Bundle

Do not upload the whole repository to arXiv. The repository contains historical
implementation notes, local workflow documentation, and application source files
that are useful for reproducibility but are not part of the submission source.

Build a clean source bundle with:

```bash
scripts/build_arxiv_source_bundle.sh
```

The script reads the same recorder-verified source allowlist used by the
article-only Overleaf projection, then copies those sources with their
repository-relative names into a timestamped directory under `/tmp`. Compile
checks for both `main.tex` and `qdesn-supplement.tex` must be run from that
isolated bundle before upload.

For the arXiv web form, the likely primary archive is `stat` and the likely
primary class is `stat.ME`. The license choice is an author decision; use the
more conservative arXiv perpetual license if journal-policy uncertainty is a
concern, or a Creative Commons license if that matches the intended reuse policy
and funder requirements.

## Documentation Map

- `docs/audits/`: manuscript-quality audits from different reading passes.
- `docs/revision_logs/`: chronological records of prose, notation, and build
  changes.
- `docs/implementation_notes/`: technical implementation notes that support
  particular modeling or computation choices.

For a first read of the repository, start with `main.tex`, then
`qdesn-supplement.tex`, and use `docs/README.md` only when you need the history
behind the current draft.

## Simulation Tables

The checked-in simulation tables are already included by `main.tex` and the
supplement. They report the current article-facing validation summaries using
fixed source identities, declared fit and forecast windows, and common scoring
rules. Table-regeneration details are preserved in `docs/implementation_notes/`
and in the external validation records; they are intentionally not part of the
preprint source bundle.

The older fit-only table builder,
`scripts/build_qdesn_simulation_tables.R`, is historical and should not be used
for the current fit-and-forecast result tables.

## GloFAS Application

The application workflow is organized under `application/`. Start with
`application/README.md`. The current article-facing authority is the completed
2026-08-11 FR09 reference case documented in
`docs/implementation_notes/glofas_fr09_authoritative_full7_promotion_20260811.md`.
It covers one reference gauge, the 25 December 2022 forecast origin, seven
independently fitted quantile levels, and 28 held-out horizons. This is a
focused retrospective reference analysis, not multi-origin or basin-wide
operational validation: future responses are blinded, while the selected
configuration declares a blend containing realized future precipitation and
soil-moisture covariates. Large or private inputs and generated runs remain in
ignored local directories; tracked manifests and stable aliases preserve the
publication provenance.
