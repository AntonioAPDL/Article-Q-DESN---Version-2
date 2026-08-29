# Article-Q-DESN Overleaf Snapshot

This project is an article-only, one-way projection of the complete research
repository. The sole manuscript authority is `origin/main` in
`AntonioAPDL/Article-Q-DESN---Version-2`. This snapshot intentionally contains
only the source files, generated tables, and figures needed to compile
`main.tex` and `qdesn-supplement.tex`.

Use the Overleaf browser for compilation and review only. Do not use
Overleaf's **Sync with GitHub** feature or any GitHub extension, do not create
or merge timestamped `overleaf-*` branches, and do not synchronize this project
back into `origin/main`. Browser files and browser edits are not authoritative.
If an edit is made here accidentally, copy it into a normal local Git branch
and integrate it through the command-line Git workflow described in the
repository's `CONTRIBUTING.md`.

Application code, run outputs, implementation notes, audit documents, and
historical article assets remain on `origin/main` and must not be copied into
this project. The snapshot is built from `overleaf/article_files.txt` by
`scripts/publish_overleaf_article_snapshot.sh`. `SOURCE_AUTHORITY.txt` records
the exact `origin/main` commit represented here.

A publication is complete only after command-line Git fetches confirm that
`origin/overleaf/article-snapshot` and `overleaf-direct/main` resolve to this
same snapshot commit and tree. Force-pushes and bidirectional synchronization
are prohibited.

Compile the main article with:

```text
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

Use the same sequence with `qdesn-supplement` for the supplement.
