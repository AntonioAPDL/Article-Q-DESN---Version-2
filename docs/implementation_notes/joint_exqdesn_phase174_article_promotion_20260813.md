# Joint exQDESN Phase 174 Article Promotion

Date: 2026-08-13

The integration merged frozen lane commit
`c804028a6b78538ebc788bd7d45ecc19689cc3b5` with an explicit merge commit and
promoted the 14 files authorized by the Phase 174 handoff. Eleven files are
byte-identical to their frozen staging artifacts. Three LaTeX wrappers replace
machine-local absolute staging inputs with `tables/<basename>` inputs so the
article-only deployment is portable. The numerical CSVs and rendered table
bodies are unchanged.

The main-text winner counts and interpretation were reconciled to the frozen
32-row scenario table. The text preserves the declared scope: posterior
quantile-grid summaries rather than a scalar predictive density, raw crossings
as pre-contract diagnostics, uniform fit but selective forecast improvement,
and five historical exAL rows retained for functional instability.

The exact source, published, and rollback hashes are recorded in
`joint_exqdesn_phase174_article_promotion_manifest_20260813.csv`. Rollback is a
normal revert of the promotion commit; no runtime evidence directory is part of
the rollback boundary.

The older
`tables/joint_qdesn_article_validation_asset_manifest.csv` remains a historical
Phase 155 manifest because the frozen Phase 175 allow-list did not authorize a
replacement. It is not in the article or Overleaf dependency closure. A future
lane-authored handoff may replace or rename it if current-manifest semantics are
required.
