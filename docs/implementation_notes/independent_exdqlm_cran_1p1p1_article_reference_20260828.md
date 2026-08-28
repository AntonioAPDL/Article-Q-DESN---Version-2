# Independent exDQLM CRAN 1.1.1 article reference

## Scope

The public software reference for the DQLM and exDQLM comparators is now the
CRAN release of `exdqlm` 1.1.1:

- <https://CRAN.R-project.org/package=exdqlm>
- <https://doi.org/10.32614/CRAN.package.exdqlm>

The bibliography version, main-text software description, and supplementary
validation description were updated. No simulation metric, table value,
figure, model specification, or scientific conclusion changed.

## Provenance

The independent-validation lane separately records the exact locally built
1.1.1 tarball used by the completed campaign. Its additive CRAN compatibility
audit verifies the relevant source paths, public inference defaults, focused
upstream tests, and fixed-seed exDQLM VB/MCMC parity. The article therefore
uses CRAN 1.1.1 as the reader-facing authority without mislabeling the
historical execution artifact.

## Verification

`latexmk` is unavailable in the validation environment. The documented
`pdflatex`--`bibtex`--`pdflatex` convergence sequence was run in ignored
local build directories.

- Main article: 39 pages; no unresolved references or citations, bibliography
  warnings, overfull boxes, or fatal errors.
- Supplement: 48 pages; no unresolved references or citations, bibliography
  warnings, overfull boxes, or fatal errors.
- Both generated bibliographies render `exdqlm` package version 1.1.1.

The article integration coordinator may merge this article-safe patch without
regenerating validation results.
