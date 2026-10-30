# Contributing and Publication Policy

## Sole Git Authority

Only command-line Git is authorized for integrating or publishing this
repository. The complete research and manuscript authority is the freshly
fetched `origin/main` branch.

The following paths are prohibited:

- Overleaf's **Sync with GitHub** feature or any equivalent browser extension;
- GitHub CLI, GitHub web merges, or browser-created merge operations;
- timestamped `overleaf-*` branches created by an external synchronization
  service;
- force-pushes to any integration, authoritative, snapshot, or Overleaf ref;
- treating files visible or edited in the Overleaf browser as authoritative;
- merging or otherwise synchronizing `overleaf-direct/main` back into
  `origin/main`.

The publication flow is one way:

```text
frozen scientific lane
  -> isolated integration branch from fresh origin/main
  -> validated origin/main
  -> manifest-built article snapshot
  -> origin/overleaf/article-snapshot
  -> overleaf-direct/main
```

## Integrating a Frozen Lane

All integrations use a fresh, isolated worktree and the following order.

1. Run `git fetch origin --prune` and record the exact `origin/main` commit.
2. Verify that the source lane resolves to its declared frozen commit, is
   clean, is synchronized with its upstream, and contains only its declared
   file surface.
3. Create a dedicated integration branch and worktree from the fetched
   `origin/main` commit. Do not reuse a worktree occupied by another scientific
   lane.
4. Merge the frozen source branch with `git merge --no-ff`. Do not amend or
   rewrite the frozen lane. Resolve conflicts file by file while preserving
   newer unrelated work from `origin/main`.
5. Run the lane-specific verification, combined repository checks,
   `git diff --check`, manuscript builds when applicable, and an artifact-scope
   audit.
6. Push the tested integration branch first.
7. Fetch `origin` again and require `origin/main` to equal the commit recorded
   in step 1. If it moved, stop and repeat the integration from the new tip.
8. Push the validated integration commit normally to `origin/main`; never
   force-push.
9. Fetch `origin` once more and require the read-back `origin/main` hash to
   equal the tested integration commit. Confirm that the integration worktree
   is clean and synchronized.

The guarded implementation of this procedure is
`scripts/publish_integration_main_git_only.sh`. A successful local merge or
push message is insufficient: the final fresh remote read-back is the
authority. The publisher requires the exact frozen source branch and commit and
verifies that they are the second parent of the two-parent integration merge;
browser-generated `overleaf-*` branches are rejected.

## Publishing the Article to Overleaf

Overleaf is a deployment target for an article-only projection. It is not a
second source repository and is never an integration input.

Publication begins only after the integration above has reached and been read
back from `origin/main`. The publisher must then:

1. authenticate and fetch `origin/main`,
   `origin/overleaf/article-snapshot`, and `overleaf-direct/main` before
   creating a commit or changing a remote ref;
2. require the requested full source commit to equal freshly fetched
   `origin/main` and require the invoking worktree to be clean;
3. materialize `overleaf/article_files.txt` from that exact source commit in a
   disposable clone or worktree;
4. verify the manifest closure and compile both `main.tex` and
   `qdesn-supplement.tex` in isolation;
5. include `SOURCE_AUTHORITY.txt`, recording the exact source commit and the
   hashes needed to verify the projection;
6. create one article-snapshot commit and push that identical commit normally
   to `origin/overleaf/article-snapshot` and `overleaf-direct/main`; and
7. fetch both remotes again and require both refs, commits, and trees to match
   the expected snapshot before reporting completion.

The guarded publisher is
`scripts/publish_overleaf_article_snapshot.sh`. It must use
`scripts/build_overleaf_article_snapshot.sh` and
`overleaf/article_files.txt`; it must never copy the full research repository
into Overleaf or mutate a persistent snapshot worktree in place.

### Explicit Review Draft While GloFAS Refits Continue

Ordinary publication rejects the pending GloFAS correction. The owner may
instead request a review copy with `--review-draft`. This option does not
promote unfinished results: the historical weighted tables and figures remain
historical, with the pending-analysis, results, table-caption, figure-caption,
discussion and supplementary notices retained in the exact committed source.
The source-derived `SOURCE_AUTHORITY.txt` then records
`publication_status=review-draft` and
`glofas_status=historical-weighted-unit-member-refits-pending`.

The builder and checker independently validate those notices and metadata.
The same explicit authorization is required to recover an origin-only draft
publication, even when the newly requested source is no longer a draft.
Authentication, current-main, clean-worktree, allowlist, compilation, history,
atomic-origin and final readback checks are unchanged. No runtime or model
output is copied. A successful review-draft deployment is not final scientific
or journal-submission approval. Corrected GloFAS results require a later,
complete validated packet and coherent manuscript regeneration.

The source-main guard and canonical snapshot update on `origin` are pushed as
one atomic group. Because `origin/overleaf/article-snapshot` and
`overleaf-direct/main` belong to independent remotes, those two refs cannot be
updated atomically. An
interrupted publication may leave one ref one verified publisher commit ahead
of the other. The only accepted retry state is a canonical origin snapshot
exactly one verified publisher commit ahead of direct Overleaf. A subsequent
guarded run validates its parent, subject, source marker, complete projection,
and manuscript builds before advancing the lagging direct ref. A direct-
Overleaf-ahead state, divergent histories, or unverified one-sided changes
require investigation and must not be resolved by force-pushing.

## Browser Edits and Authentication

Use the Overleaf browser for compilation and review only. If an edit is made
there accidentally, copy it into a dedicated local Git branch, review it, and
integrate it through the procedure above. Do not click **Sync with GitHub** and
do not merge a generated `overleaf-*` branch.

This Git-only restriction applies to Article-v2, not to the owner's other
projects. The owner explicitly retains the account-level Overleaf--GitHub
authorization for those projects. Global disconnection or revocation is not
a publication prerequisite and must not be requested or performed merely to
publish this article. Do not use this project's GitHub synchronization controls
or reauthorize them as part of the Article-v2 workflow.

Retained authorization does not relax any scientific, clean-worktree,
source-authority, build, or remote-readback gate. Fetch both publication
references before publishing. Unexpected Overleaf-side changes or divergent
history require investigation and preservation through command-line Git;
they must not be resolved by force-pushing or wholesale browser-branch merges.

The publishers are intentionally noninteractive and explicitly bypass GitHub
CLI and editor credential helpers. Credentials must be placed in Git's
credential cache by a separate interactive command-line Git preflight. Never
place a token in a command argument, remote URL, tracked file, commit, log, or
chat transcript. Authentication and remote fetches occur before any
publication ref is changed, so a missing cache entry fails safely.

For direct Overleaf authentication, run the following from a clean article
worktree and paste the token only at Git's password prompt:

```bash
unset GIT_ASKPASS SSH_ASKPASS
GIT_TERMINAL_PROMPT=1 git \
  -c credential.helper= \
  -c 'credential.helper=cache --timeout=900' \
  -c credential.https://git.overleaf.com.helper= \
  -c 'credential.https://git.overleaf.com.helper=cache --timeout=900' \
  fetch overleaf-direct main
```

If the origin push also requires authentication, prime the same Git cache with
a normal command-line Git dry-run push from the exact integration branch,
using the corresponding `credential.https://github.com.helper` overrides. A
dry-run must complete before either publisher is run.

## Completion Standard

Integration is complete only when a fresh fetch confirms the expected commit
at `origin/main`. Overleaf publication is complete only when a fresh fetch
confirms

```text
origin/overleaf/article-snapshot == overleaf-direct/main
```

at the expected snapshot commit and tree, `SOURCE_AUTHORITY.txt` identifies
the verified `origin/main` source, both manuscripts have passed isolated
builds, and all relevant worktrees are clean. Any failed check is a blocked
publication, not a partial success.
