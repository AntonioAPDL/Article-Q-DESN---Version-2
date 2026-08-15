# Overleaf Article-Projection Audit, 2026-08-11

## Decision

The authoritative GitHub `main` branch remains the complete research
repository. Overleaf receives a separate article-only snapshot branch. This is
safer than deleting application code or reproducibility documentation from
`main`, and it removes the source of the 2,000-file-limit failures.

## Evidence

At source commit `029fad10bde8ac4dcdb5754a3a68c40d2202ef46`, the complete tree
contained 1,966 tracked files:

| Area | Tracked | Required by TeX |
|---|---:|---:|
| `application/` | 1,054 | 0 |
| `docs/` | 392 | 0 |
| `tables/` | 333 | 24 |
| `figures/` | 169 | 3 |
| `scripts/` | 9 | 0 |
| Root and metadata | 9 | 3 |

Fresh `pdflatex -recorder` builds of `main.tex` and
`qdesn-supplement.tex`, augmented with the BibTeX database, identify an exact
30-file source closure. Those files total 363,566 bytes (0.347 MiB). The
projection adds only `.gitignore` and `README.md`, giving 32 files before TeX
build products.

A blob-identity audit found 19 duplicate blob groups and 29 redundant tracked
entries in the complete repository. Most are historical generated tables. They
remain on GitHub for provenance but are absent from the Overleaf projection.

## Scope Policy

The Overleaf snapshot keeps:

- `main.tex`, `qdesn-supplement.tex`, and `refs.bib`;
- all active TeX table dependencies;
- the three figures read by the current compiled documents;
- a deployment README and restrictive `.gitignore`.

It excludes:

- application, validation, launch, and fitting code;
- local or historical run outputs;
- implementation notes and audit documents;
- unused historical tables and figures;
- standalone legacy manuscripts and tracked compiled PDFs.

Excluded files are not deleted from GitHub `main`; they remain versioned and
recoverable there. This is especially important for PriceFM, GloFAS,
joint-QDESN, and validation workstreams that share the repository.

## Reproducible Wiring

- `overleaf/article_files.txt` is the sorted source allowlist.
- `scripts/build_overleaf_article_snapshot.sh` materializes a snapshot from an
  explicit Git commit without deleting or modifying the source worktree.
- `overleaf/overleaf.gitignore` blocks accidental reintroduction of code,
  documentation, unregistered tables, figures, and build products.
- `.gitignore` excludes local snapshot workspaces from the full branch.

The publication branch is named `overleaf/article-snapshot` on GitHub and is
pushed to `main` on the direct Overleaf remote. It may intentionally differ in
tree contents from GitHub `main`; the manifest and source commit preserve the
relationship.

## Validation Results

The projection builder materialized 30 allowlisted article sources and added
the deployment `.gitignore` and `README.md`, for 32 files and 364,985 bytes in
total before compilation. An isolated BibTeX build converged successfully for
both documents:

| Document | Pages | Final log audit |
|---|---:|---|
| `main.tex` | 42 | no errors, unresolved references/citations, box warnings, or other warnings |
| `qdesn-supplement.tex` | 39 | no errors, unresolved references/citations, box warnings, or other warnings |

The projection contains no `application/`, `docs/`, `scripts/`, unused article
asset, or root-level compiled PDF. The GitHub source branch still contains the
complete research tree; only the dedicated publication branch is pruned.

## Acceptance Gates

1. Every allowlisted path exists at the declared source commit.
2. The snapshot contains exactly 32 files before compilation.
3. No `application/`, `docs/`, `scripts/`, historical manuscript, or compiled
   root PDF is present.
4. Main and supplement compile in isolation with BibTeX and converged
   cross-references.
5. Final logs contain no unresolved references, undefined citations, overfull
   boxes, or fatal errors.
6. GitHub `main` remains complete and clean.
7. GitHub `overleaf/article-snapshot` and Overleaf `main` resolve to the same
   snapshot commit.
