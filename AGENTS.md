# Mandatory Integration and Publication Rules

- Use command-line Git only. Never use Overleaf **Sync with GitHub**, a
  browser/hosting extension, GitHub CLI, web merges, or force-pushes.
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
- Supply credentials only through Git's credential cache, primed separately
  at an interactive Git prompt. Never put a token in a URL, command, file,
  commit, log, or chat message.
- Report completion only after fresh command-line fetches verify all expected
  remote hashes and all relevant worktrees are clean.

See `CONTRIBUTING.md` for the complete procedure and recovery rules.
