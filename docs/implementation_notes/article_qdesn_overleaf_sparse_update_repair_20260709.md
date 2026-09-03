# Article-Q-DESN Overleaf Sparse Update Repair, 2026-07-09

> **Historical record—superseded on 2026-08-29.** Do not reuse the
> browser-based GitHub/Overleaf synchronization or branch-resolution procedure
> described below. The mandatory current workflow is command-line Git only; see
> CONTRIBUTING.md and
> docs/implementation_notes/git_only_integration_overleaf_publication_20260829.md.
> The text below is retained solely as incident history.

## Context

The authoritative Article-Q-DESN repository is:

`https://github.com/AntonioAPDL/Article-Q-DESN---Version-2.git`

The clean synchronized snapshot before this repair was commit
`a2590cd741907a79b83a3f1444a0315b69f12be1`.

After an Overleaf GitHub sync, `origin/main` advanced to
`e2345490027ec89131d30da2110076f2d19e445b`, a merge commit containing
`67273a79` (`Updates from Overleaf`). That remote tree was sparse:

- tracked files dropped from 1,457 to 302;
- `refs.bib` and `main.pdf` were absent;
- `main.tex` was replaced by a 226-byte blank starter article;
- 1,155 tracked project files were deleted relative to `a2590cd`.

## Repair Decision

The repair is a normal forward commit on top of the sparse Overleaf merge.
It restores the tracked tree from `a2590cd` rather than rewriting remote
history. This keeps the evidence of the failed Overleaf sync visible while
making GitHub `main` usable again for Overleaf pulls and Codex work.

Application, validation, PriceFM, GloFAS, QDESN, and joint-QDESN scripts were
not edited by hand. They were restored byte-for-byte from the known-good
authoritative snapshot so the article repository remains complete.

## Reproducibility

The diagnostic files for this incident are local-only under:

`.codex_work/audits/overleaf_remote_sparse_update_20260709/`

The key audit artifacts are:

- `head_to_origin_main.name_status.tsv`
- `deleted_by_origin_main.txt`
- `origin_main_main_tex_snapshot.tex`
- `commit_ids.before_repair.txt`

The historical repair was followed by another browser pull so that Overleaf
received the restored tree. That action must not be repeated; current
publication uses the guarded one-way direct-Git procedure named above.
