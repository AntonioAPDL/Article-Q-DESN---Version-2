# Command-Line Git Integration and Overleaf Publication

## Audited direct-tip reconciliation

The default direct-Overleaf-ahead rejection remains mandatory. An exact
reviewed tip may be reconciled only through the publisher's explicit option
and committed audit contract, as documented in
`overleaf_reviewed_direct_reconciliation_20261030.md`. The replacement current
tree is manifest-built from main and retains the reviewed tip as publication
history only. No browser history is merged into research main; no force-push,
new-result promotion or unreviewed-edit override is permitted.

## Review-draft clarification (2026-10-29)

The publisher's explicit `--review-draft` option permits the owner-requested
review of revised text while corrected GloFAS fits continue. Default publication
remains blocked. The exact source must retain all historical-result notices;
its snapshot marker records the provisional state. This authorization applies
also to recovery of a pending origin-only draft. It relaxes no authentication,
history, source-main, allowlist, build or readback gate and does not authorize
unfinished numerical results or a submission-ready declaration. See
`CONTRIBUTING.md` for the distinction between review deployment and scientific
result promotion.

## Decision

`origin/main` is the sole research and manuscript authority. All scientific
lanes are integrated with command-line Git in isolated worktrees. Overleaf is
a one-way article deployment target. Its browser synchronization feature,
browser-created `overleaf-*` branches, web merges, command-line hosting-service
clients, and force-pushes are outside the supported workflow.

This decision removes the recurring ambiguity created by two independent
synchronization mechanisms. The previous direct-Git snapshot and browser
synchronization paths did not share the same branch contents or history. The
full repository also exceeds the intended article-only Overleaf surface.

## Authoritative Sequence

For each frozen scientific lane:

1. fetch `origin` and record the exact `origin/main` commit;
2. verify the frozen source commit, upstream synchronization, and declared
   changed-file surface;
3. create a fresh integration branch and worktree from that exact main commit;
4. merge the frozen lane with `--no-ff` and preserve its history;
5. run the lane-specific checks, combined checks, artifact audit, and relevant
   manuscript builds;
6. use `scripts/publish_integration_main_git_only.sh` to push the integration
   branch, verify the exact source branch and merge parents, refetch and guard
   main, push normally to main, and read the result back from the remote.

When article files change, publication continues with
`scripts/publish_overleaf_article_snapshot.sh`. The script accepts one explicit
40-character source commit, which must equal freshly fetched `origin/main`.
It authenticates and fetches both publication refs before creating a commit or
changing a remote ref.

## Snapshot Construction

`scripts/build_overleaf_article_snapshot.sh` validates the sorted, unique,
article-only paths in `overleaf/article_files.txt`. It rejects absolute paths,
parent traversal, backslashes, duplicate entries, unsorted entries, and files
outside the manuscript, bibliography, tables, and figures surface.

The builder adds three support files:

- `.gitignore`, copied from `overleaf/overleaf.gitignore`;
- `README.md`, copied from `overleaf/README.md`; and
- `SOURCE_AUTHORITY.txt`, generated deterministically from the source commit.

The source-authority file records the source commit and tree, manifest blob and
SHA-256, and the SHA-256 values for the main article, supplement, and
bibliography. It contains no timestamp or snapshot commit, so an unchanged
source produces an unchanged snapshot tree.

`scripts/check_overleaf_article_snapshot.sh` verifies the exact file inventory,
source blob identity, source-authority fields, forbidden-path exclusion, and
absence of build or runtime outputs. It then builds both manuscripts with
BibTeX in an isolated temporary directory, checks the final logs, and uses TeX
recorder output to reject undeclared project sources.

## Publication Safety

The publisher uses a repository-wide lock and a disposable temporary Git
repository. It never synchronizes files into a persistent snapshot worktree.
Before pushing, it refetches all three relevant refs and requires that none
moved during the build. The unchanged source-main ref and canonical snapshot
update are negotiated and pushed to `origin` atomically, so a concurrent main
update rejects the complete origin-side operation. The direct Overleaf push is
then performed as an ordinary fast-forward push.

Because refs on two independent remotes cannot change atomically, a network interruption may
leave one publication ref one verified commit ahead of the other. On a retry,
the script permits only a canonical-origin-ahead state of exactly one commit.
It verifies the commit parent and subject, every source marker, the complete
tree rebuilt from the marked source, and both manuscript builds. It then
advances only the lagging direct ref. A direct-Overleaf-ahead state, unrelated
history, or mismatched projection stops the publication and is never repaired
with a force-push.

Completion requires fresh fetches showing:

```text
origin/overleaf/article-snapshot == overleaf-direct/main
```

at the expected commit and tree, with `SOURCE_AUTHORITY.txt` identifying the
unchanged `origin/main` source.

## Verification

The disposable publisher tests cover:

- successful dual publication and source-authority verification;
- idempotent reruns;
- stale source rejection;
- dirty or structurally invalid integration publication;
- divergent publication histories;
- unsafe, duplicate, and unsorted manifest entries;
- an omitted active TeX dependency;
- unavailable direct-remote authentication or transport;
- a synthetic post-push read-back mismatch; and
- safe recovery from a verified one-sided publication without force.

The production snapshot is also built and compiled directly from the current
article authority before publication.

## Project-Scoped Authorization Policy

As clarified by the owner on 2026-10-29, the account-level Overleaf--GitHub
authorization remains enabled for other projects. Disconnection or revocation
is not a release prerequisite for Article-v2 and must not affect those other
projects. This supersedes this note's original account-disconnection condition.

Article-v2 must never use the browser's GitHub synchronization controls. Its
only supported integration and publication path is the command-line Git
sequence above. Existing source-authority, scientific-validation, build,
clean-state and remote-readback gates remain mandatory. If an external action
creates a competing branch or changes the direct Overleaf history, preserve
and investigate it; never force-push or merge a browser-generated branch into
research main wholesale.
