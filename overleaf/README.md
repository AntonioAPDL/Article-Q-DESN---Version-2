# Article-Q-DESN Overleaf Snapshot

This branch is an article-only projection of the complete research repository
at `AntonioAPDL/Article-Q-DESN---Version-2`. It intentionally contains only the
source files, generated tables, and figures needed to compile `main.tex` and
`qdesn-supplement.tex`.

Application code, run outputs, implementation notes, audit documents, and
historical article assets remain on the authoritative GitHub `main` branch.
They must not be copied into this Overleaf project. Article edits made in
Overleaf should be ported back to GitHub `main` before the snapshot is
regenerated.

Compile the main article with:

```text
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

Use the same sequence with `qdesn-supplement` for the supplement.
