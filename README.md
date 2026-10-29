# Bayesian Quantile Deep Echo State Networks for Nonlinear Time Series

This repository contains the working manuscript, supplement, bibliography, and
simulation tables for the Q--DESN article.

## Authoritative Git Workflow

`origin/main` is the sole research and manuscript authority. Integration and
publication use command-line Git only. Never use Overleaf's **Sync with
GitHub** feature, a GitHub extension, GitHub CLI or web merges, timestamped
`overleaf-*` branches, bidirectional Overleaf synchronization, or a
force-push.

Every frozen lane is merged with `--no-ff` in a fresh integration worktree
created from freshly fetched `origin/main`. After verification, the tested
integration branch is pushed first; `origin/main` is fetched and checked again
before the guarded normal push to `origin/main`. The final remote hash is then
read back with another fetch.

The corresponding command-line workflow is implemented by:

- `scripts/publish_integration_main_git_only.sh`, for the guarded integration
  branch and `origin/main` update; and
- `scripts/publish_overleaf_article_snapshot.sh`, for the one-way article
  projection from the verified `origin/main` commit.

Overleaf receives only the manifest-defined snapshot. Its deployment refs must
finish at the same commit and tree:

```text
origin/overleaf/article-snapshot == overleaf-direct/main
```

The generated snapshot includes `SOURCE_AUTHORITY.txt`, which identifies its
exact `origin/main` source. The Overleaf browser is for review and compilation,
not for authoritative editing or merging. See [CONTRIBUTING.md](CONTRIBUTING.md)
for the required integration, publication, authentication, and recovery
procedure.

## Main Files

- `main.tex`: main article.
- `qdesn-supplement.tex`: standalone supplementary material.
- `refs.bib`: bibliography database used by both LaTeX files.
- `tables/`: generated simulation tables included by the main article.
- `Academic_Writing_Style_Profile_v0.2.md`: writing and formatting criteria
  used for manuscript revisions.
- `scripts/build_qdesn_simulation_tables.R`: script used to regenerate the
  simulation tables from external validation outputs.
- `application/`: code and configuration for the GloFAS and PriceFM analyses.
  Local data, intermediate calculations, logs, and generated outputs are ignored.
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

Generated auxiliary LaTeX files are intentionally not tracked. The main PDF
may be refreshed when updating the article source on `origin/main`.

## arXiv Source Bundle

Do not upload the whole repository to arXiv. It contains historical
implementation notes, local development records, and application source files
that are not part of the submission source.

Build a clean source bundle with:

```bash
scripts/build_arxiv_source_bundle.sh
```

The script copies the article and supplement files listed in
`overleaf/article_files.txt` to a timestamped directory under `/tmp` while
preserving their relative paths. Compile the main article and supplement from
that directory before upload.

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
supplement. They report the simulation results under the stated fitting and
forecast periods and common scoring rules. Table-generation details are
preserved in `docs/implementation_notes/` and are intentionally excluded from
the preprint source bundle.

The older fit-only table builder,
`scripts/build_qdesn_simulation_tables.R`, is historical and should not be used
for the current fit-and-forecast result tables.

## GloFAS Application

The GloFAS application is organized under `application/`. Start with
`application/README.md`; detailed implementation notes are available in
`docs/implementation_notes/`. The analysis specifies the input data, model
grid, forecast-origin design, scoring rules, and manuscript tables and figures.
Large or private inputs and generated results should remain in ignored local
directories.
