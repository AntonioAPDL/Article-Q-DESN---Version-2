# Article-Q-DESN Local Literature Sync, 2026-07-09

## Scope

This note records the local-only bibliography and PDF sync performed after the
authoritative repository moved to:

`https://github.com/AntonioAPDL/Article-Q-DESN---Version-2.git`

The literature archive is intentionally not tracked. The repository `.gitignore`
keeps `literature/` local so copyrighted PDFs, extracted text, and citation
audit drafts do not move to GitHub or Overleaf.

## Local Archive

The old article checkout contained the active local literature workspace at:

`/data/jaguir26/local/src/Article-Q-DESN/literature`

That archive was linked into the new authoritative checkout at:

`/data/jaguir26/local/src/Article-Q-DESN---Version-2/literature`

Hardlinks were used on the same filesystem, so the heavy PDF payloads were not
duplicated. The original 107-file archive matched exactly by SHA-256 after
linking. Additional BibTeX-key aliases and public/open PDFs were then added
locally to improve current manuscript coverage.

Final local state:

- literature files: 122
- local PDFs: 72
- local literature bytes: 180,763,808
- PDF validation failures: 0

## Bibliography Coverage

Current `refs.bib` contains 83 BibTeX keys. The manuscript and supplements cite
60 unique keys. After aliasing existing PDFs and adding available public/open
PDFs, 55 of the 60 cited keys have local PDF candidates.

The remaining cited keys without local PDF files are:

- `CEMS2026GloFASDocumentation`: web documentation, no PDF expected.
- `ECMWF2026ENSGeneration`: web documentation, no PDF expected.
- `HirpaEtAl2018GloFASCalibration`: open landing page exists, but no direct PDF
  URL was exposed by the checked sources.
- `JiangBondellWang2014InterquantileShrinkage`: PMC exposed an intermediate
  HTML download page to the terminal rather than a stable PDF payload.
- `WangCai2024CompositeBayesianNoncrossing`: Unpaywall reports this DOI as
  closed, so no PDF was added.

## Local Audit Artifacts

Detailed local-only audit files are under:

`.codex_work/audits/literature_local_sync_20260709/`

Key files:

- `ref_pdf_key_coverage_summary.final.txt`
- `cited_keys_without_pdf_candidate.final.txt`
- `refs_keys_without_pdf_candidate.final.txt`
- `pdf_key_aliases.tsv`
- `pdf_validation_counts.txt`
- `pdf_validation_summary.tsv`

These audit files are intentionally ignored and should stay local.
