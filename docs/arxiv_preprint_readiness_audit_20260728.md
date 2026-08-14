# arXiv Preprint Readiness Audit

Date: 2026-07-28

Repository audited:

- Local: `/data/jaguir26/local/src/Article-Q-DESN---Version-2`
- Branch: `main`
- Commit before polish: `fa4c73a7696907fdef200e53d4689f3b66ed6f8d`

## Scope

This audit was limited to article-safe manuscript material:

- `main.tex`
- `qdesn-supplement.tex`
- generated manuscript table `.tex` files included by the article or supplement
- `refs.bib`

The audit did not modify application code, validation code, generated data, or
running validation outputs. Existing dirty/untracked `application/` files in the
repository were treated as unrelated work and left untouched.

## Checks

- Git state and remotes checked before editing.
- Citation key audit found 60 cited keys and 84 bibliography entries, with 0
  missing cited bibliography keys.
- Main included graphics resolved to existing files.
- Reader-facing occurrences of internal validation bookkeeping language were
  reviewed in `main.tex`, `qdesn-supplement.tex`, and manuscript table captions.
- `latexmk` was not available on this system. The main manuscript was compiled
  with `pdflatex`, `bibtex`, `pdflatex`, `pdflatex` into
  `/tmp/qdesn_arxiv_compile_20260728`; the final PDF has 38 pages.
- The supplement was compiled with `pdflatex`, `pdflatex` into
  `/tmp/qdesn_supp_compile_20260728`; the final PDF has 36 pages.
- Targeted log scans found no LaTeX errors, undefined references, undefined
  citations, or overfull/underfull boxes in the final logs.
- A clean arXiv source bundle was built and compiled from
  `/tmp/qdesn_arxiv_source_release_20260728`. The bundle contains only the
  manuscript sources, bibliography, included table files, and the figures
  referenced by the main article.
- A source-only upload bundle with clean filenames was built at
  `/tmp/qdesn_arxiv_upload_source_clean_20260728` and archived as
  `/tmp/qdesn_arxiv_upload_source_clean_20260728.tar.gz`.
- The clean bundle main article compiled with
  `pdflatex`, `bibtex`, `pdflatex`, `pdflatex`, `pdflatex`; the final bundle
  PDF has 38 pages.
- The clean bundle supplement compiled with
  `pdflatex`, `bibtex`, `pdflatex`, `pdflatex`; the final bundle PDF has
  36 pages.
- Final clean-bundle log scans found no LaTeX errors, undefined references,
  undefined citations, or overfull/underfull boxes in either final log.

## Manuscript Polish Applied

The polish keeps all reported numerical results unchanged.

- Retitled the manuscript to emphasize the Bayesian readout construction.
- Replaced visible `VB--LD` table labels and reader-facing prose with `VB` or
  `variational Bayes`, while retaining the technical Laplace--Delta explanation
  in the inference sections where it defines the approximation.
- Replaced internal engineering language such as source hashes, run tags,
  manifests, branch/commit provenance, and phase labels with reader-facing
  reproducibility language.
- Removed local validation source paths from table source comments.
- Added `scripts/build_arxiv_source_bundle.sh`, which creates an isolated
  upload candidate and refuses to overwrite an existing output directory.
- The bundle builder rewrites the upload copy to use clean source names:
  `article.tex`, `supplement.tex`, `references.bib`, concise table names, and
  concise figure names.
- Replaced included-table source comments that exposed local builder script
  paths with neutral article-facing comments.
- Replaced dynamic `\today` dates with a fixed preprint date and removed the
  disabled draft-note macros from the main article source.
- Preserved warning/failure markers in validation tables as diagnostic
  disclosure; no metric values were changed.

## References

The active manuscript has no missing citation keys. No placeholder citation was
added to the compiled article. The bibliography still contains some unused
entries, which is harmless because BibTeX only writes cited entries to `main.bbl`.

## Remaining Manual Checks Before arXiv

- Visually inspect the compiled PDFs for table placement and figure quality.
- Confirm coauthor names, affiliations, acknowledgments, and license choice.
- For arXiv upload, include the TeX source, `refs.bib` or `main.bbl`, included
  table files, and the figure files referenced by `main.tex`; exclude local run
  directories, caches, application scripts, and validation data.
