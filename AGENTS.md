# Mandatory Integration and Publication Rules

- Use command-line Git only. Never use Overleaf **Sync with GitHub**, a
  browser/hosting extension, GitHub CLI, web merges, or force-pushes.
- This restriction applies to Article-v2. The owner may retain the account's
  Overleaf--GitHub authorization for other projects. Do not require global
  disconnection or revocation, or alter other projects' integrations.
- Treat freshly fetched `origin/main` as the sole research and manuscript
  authority. Never merge `overleaf-direct/main` or a generated `overleaf-*`
  branch into it.
- Integrate each frozen lane with `--no-ff` in a fresh isolated worktree from
  the current `origin/main`. Do not switch or reuse a checkout occupied by
  another lane.
- Publish a validated merge with
  `scripts/publish_integration_main_git_only.sh`, including its exact source
  branch and source commit arguments.
- Publish article files only with
  `scripts/publish_overleaf_article_snapshot.sh`. The flow is one way from
  `origin/main` to `origin/overleaf/article-snapshot` and then to
  `overleaf-direct/main`.
- Pending corrected GloFAS results block ordinary publication. An explicit
  `--review-draft` run may deploy the revised text only with all historical-
  result notices intact and source-derived draft metadata. This is not
  scientific result promotion or submission approval; every other publication
  gate remains mandatory.
- Direct-Overleaf-ahead history still blocks ordinary publication. Only the
  publisher's explicit `--reconcile-reviewed-direct` option may reconcile the
  exact tip in its committed audit contract, after confirming that every
  browser edit was captured and dispositioned. Publish a sanitized article-
  only child of that tip; never merge its history into research main. Any
  unreviewed edit, changed source projection or changed remote ref must stop.
- Supply credentials only through Git's credential cache, primed separately
  at an interactive Git prompt. Never put a token in a URL, command, file,
  commit, log, or chat message.
- Report completion only after fresh command-line fetches verify all expected
  remote hashes and all relevant worktrees are clean.

See `CONTRIBUTING.md` for the complete procedure and recovery rules.
