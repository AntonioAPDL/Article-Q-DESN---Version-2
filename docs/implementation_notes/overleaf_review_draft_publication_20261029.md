# Advisor review copy while corrected GloFAS fits continue

## Purpose and boundary

The owner requested that the revised text be available in Overleaf before the
unit-member GloFAS reruns finish. Source integration and scientific result
promotion are different operations. Main already contains the advisor revision
and the corrected fitting workflow at
dfa5eeb061fd83b545666d69e10aadd397311466. The existing GloFAS numerical displays
remain historical weighted results, explicitly marked in the manuscripts.
This change supplies a narrowly authorized review deployment; it changes no
manuscript, numerical table, figure, model, runtime input or active worktree.

Ordinary publication remains blocked while the correction is pending.
`--review-draft` authorizes only the visibly qualified review copy. It neither
certifies completed reruns nor makes the paper ready for submission. It does
not require revoking account-wide GitHub authorization used by other projects.
This project's publication uses command-line Git only.

## Checks and provenance

`scripts/overleaf_review_draft_status.py` reads the exact committed main and
supplement. It ignores TeX comments and requires the six historical-result
notices as top-level commands in their document bodies: analysis, results,
table caption, figure caption, discussion and supplementary results. Notices
inside macro arguments or commented/conditionally hidden text are rejected.
This conservative check supports the current source syntax; it is not a
general interpreter proving visibility for arbitrary TeX. Isolated builds and
review of the actual manuscript remain necessary. A pending source requires
explicit draft authorization before any publication fetch or ref mutation.

The article-only builder and checker derive status independently from the
same source. A pending snapshot adds only these two status fields to the
existing source marker:

```text
publication_status=review-draft
glofas_status=historical-weighted-unit-member-refits-pending
```

Ordinary release snapshots retain their earlier marker bytes, preserving
reconstruction of previously published trees. A pending origin-only recovery
also requires explicit authorization, even if the newly requested main source
is no longer pending. Every existing history, authentication, exact-source,
clean-worktree, manifest, isolated-build, atomic-origin and remote-readback
check remains in force. Direct-Overleaf-ahead or divergent histories stop
publication; there is no force-push or unseen-edit override.

## Reproducible verification

Run the publication regression suites in their private temporary repositories:

```bash
bash scripts/tests/test_publish_overleaf_article_snapshot.sh
/usr/bin/python3.11 scripts/tests/test_publish_overleaf_review_draft.py
git diff --check
```

These fixtures use local bare remotes only, not the real origin or Overleaf.
They isolate Git configuration without changing HOME. The draft tests cover
default rejection, explicit opt-in, missing/commented/duplicate notices,
conditional metadata, publication readback, retry and origin-only recovery,
including recovery of an older draft before publishing corrected text.
Production source-bundle checks separately compile both real manuscripts.
Execution receipts and final Git hashes belong in ignored local trackers;
passing a fixture is not evidence that the real Overleaf project changed.

Pre-integration verification passed all sixteen existing publisher cases and
fourteen dedicated review-draft tests, including eighteen individual notice
removal/comment/macro mutations and six metadata mutations. The independent
review found and corrected the macro-concealment gap before freezing the test
surface. The real source at the recorded main checkpoint produced a 107-file
manifest/110-file snapshot and clean 38-page main and 98-page supplement
builds. The reader-focused check passed 78 checks with seven expected mutation
rejections; the statistical-language check passed 81 checks with 38 expected
rejections. The latter retains protection of 352 scientific CSVs and 705
PriceFM files. No real Overleaf publication was part of these tests.

## Interactive publication and completion

After this branch is integrated and read back from main, the owner primes
Git's credential cache at its private password prompt, then invokes the
publisher with the exact new main hash, `--review-draft` and first `--dry-run`.
No token belongs in a URL, command argument, tracked file, log or chat.

Only a successful real publication followed by fresh fetches confirming equal
origin snapshot and direct Overleaf commits/trees can establish deployment.
The resulting marker must identify the requested main source and review-draft
status. Until then, report source integration as complete and Overleaf
publication as awaiting authentication, not as completed.

## Work not completed by a draft deployment

1. Finish all eighteen GloFAS fit units and validate their numerical/convergence
   evidence, score packet and manifests. Replace the six-family tables,
   figures, aliases and interpretation together, retaining adverse results.
2. Obtain authentic inputs for the additional one-step multiquantile comparison
   (E36); no result is inferred from aggregate summaries.
3. Establish matched fit-only VB/MCMC timing (C06), if a numerical speedup is to
   be reported. Combined fitting/forecasting/export times do not establish it.
4. Keep PriceFM provisional and unchanged pending its separate authority update.
5. Review and validate the complete final manuscript before claiming scientific
   or journal-submission readiness.
