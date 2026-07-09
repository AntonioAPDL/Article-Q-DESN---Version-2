# Article-Q-DESN Post-Sync Deep Audit, 2026-07-09

## Scope

This note records the follow-up audit after moving the authoritative article
repository to:

`https://github.com/AntonioAPDL/Article-Q-DESN---Version-2.git`

The audit checked the GitHub/Overleaf-facing tracked tree, the local-only
literature archive, ignored import candidates recovered from the old checkout,
and the compiled article PDF. It did not modify QDESN, joint-QDESN, PriceFM, or
GloFAS application or validation scripts.

## Repository State

The audit started from:

- local `main`: `55748fd274247624dae24e1f608d8235395cf970`
- `origin/main`: `55748fd274247624dae24e1f608d8235395cf970`
- ahead/behind relative to `origin/main`: `0 0`
- tracked files in `HEAD`: 1,459
- tracked files in `origin/main`: 1,459
- non-ignored untracked files: 0

The stale remote-tracking branch
`origin/overleaf-2026-07-09-0225` was pruned locally after GitHub reported that
the remote branch no longer existed. The remaining remote branches are
`origin/HEAD -> origin/main` and `origin/main`.

Compared with the old article checkout's local `main` and old `origin/main`,
the Version 2 tracked tree contained every old tracked path with matching blob
hashes before the PDF refresh. The only tracked additions at that point were
the three repository-sync notes:

- `docs/implementation_notes/article_qdesn_authoritative_repo_sync_20260709.md`
- `docs/implementation_notes/article_qdesn_local_literature_sync_20260709.md`
- `docs/implementation_notes/article_qdesn_overleaf_sparse_update_repair_20260709.md`

## Local-Only Literature

The new local literature archive at:

`/data/jaguir26/local/src/Article-Q-DESN---Version-2/literature`

is intentionally ignored by Git. It contains the old local archive plus
additional local-only bibliography assets:

- old local literature files: 107
- new local literature files: 122
- local PDFs: 72
- local literature bytes: 180,763,808
- SHA-256 removals relative to the old archive: 0
- SHA-256 additions relative to the old archive: 15
- PDF validation failures: 0

Current `refs.bib` has 83 keys. The TeX files cite 60 unique keys. The local
PDF archive has candidates for 55 cited keys. The five remaining cited keys
without local PDF candidates are documented as web documentation, closed-access,
or no-stable-PDF cases in the local audit artifacts.

## Local Import Candidates

Local-only material recovered from the old checkout is kept under:

`.codex_work/import_candidates/`

The recovered files are hash-matched copies of the old local files and are not
tracked:

- `old_top_level_reports_20260709/AGENTS_academic_writing_snippet.md`
- `old_top_level_reports_20260709/PRICEFM_DATA_PIPELINE_REPORT.md`
- `old_top_level_reports_20260709/QDESN_Batched_VB_Implementation_Report.md`
- `old_application_branch_docs_20260709/joint_qvp_synthetic_dgp_phase4n_health_next_plan_20260706.md`
- `old_application_branch_docs_20260709/joint_qvp_synthetic_dgp_phase4o_feature_candidate_launch_20260706.md`
- `old_application_branch_docs_20260709/joint_qvp_synthetic_dgp_phase4o_feature_candidate_launch_audit_plan_20260706.md`

Old untracked application scripts and tests were intentionally not imported or
edited in this article repository.

## Article Link And Compile Checks

The direct `\input`, `\includegraphics`, and bibliography checks found no
missing bibliography files. The apparent missing figure/table paths were
LaTeX macros defined in:

- `tables/glofas_application_current_outputs.tex`
- `tables/pricefm_full_current_outputs.tex`

Those six macro-resolved paths all exist. The tracked `figures/` and `tables/`
trees also match the filesystem:

- tracked figure/table files: 407
- filesystem figure/table files: 407
- untracked figure/table files: 0

A clean four-pass build was run under:

`local_trackers/post_full_sync_deep_audit_compile_20260709_final/`

The final build produced:

- `main.pdf`: 39 pages, 638,502 bytes
- LaTeX warning lines: 0
- overfull/underfull box lines: 0
- unresolved citation/reference messages: 0

The tracked `main.pdf` was stale relative to `main.tex`; extracted text differed
around the joint multi-quantile validation section. The PDF was refreshed from
the clean build so the committed PDF matches the current article source.

## Local Audit Artifacts

Detailed local-only audit files are under:

`.codex_work/audits/post_full_sync_deep_audit_20260709/`

Important files include:

- `final_audit_summary.txt`
- `old_vs_new_tracked_tree_summary.txt`
- `literature_old_vs_new_summary.txt`
- `macro_resolved_path_summary.tsv`
- `tracked_vs_fresh_main_pdf_text.diff`
- `fresh_compile_pdfinfo.txt`

These files are intentionally ignored and should stay local.
