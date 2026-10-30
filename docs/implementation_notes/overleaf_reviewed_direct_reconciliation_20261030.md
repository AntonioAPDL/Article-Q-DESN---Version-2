# Reconciliation of the captured advisor edits in direct Overleaf

## Observed failure

The owner's interactive fetch authenticated successfully. Publication then
stopped at `DIRECT_OVERLEAF_AHEAD`; authentication was not the problem. The
canonical snapshot remained 88aa6509693b5cbd7d0bf2c2df2fed97b052905b, while
direct Overleaf had its single child
11b67610f79c0dc0bfee79d2841c86c0f8677b42. The default guard correctly prevented
an unaudited replacement. Research main was
fd6a60f580ba2d22f388cfef97a02f0c9ef3322f.

## Completed content audit

The direct tree has 393 files and 9,059,491 bytes, versus the canonical
snapshot's 110 files and 2,382,356 bytes. It retains the old source marker
unchanged despite changing the manuscript, so that marker cannot certify the
edited tree.

There are exactly three changes to existing article inputs:

| File | Audited disposition |
| --- | --- |
| `main.tex` | Identical to captured advisor review f3ac1146e3e69554a2ba6b9559e9b6b550debf2e; all requests retain dispositions in the 115-item advisor register. |
| `tables/independent_eval300_results_v1.tex` | Captured lowercase sentence correction; E21/E49 address the surrounding results prose. |
| `tables/independent_train500_eval300_mcmc_figures_v1.tex` | Captured red comment about matching panel scales; E50 explicitly explains the common horizontal limits. |

The direct manuscript SHA-256 is
05e37dc49b738d76494b68b7760112105e0548aadb94e1f5ff89651444104b73.
There is no new article edit beyond the captured review. The supplementary
source, bibliography, figures and numerical CSVs have no direct-over-canonical
change. In addition, direct Overleaf introduced 283 nonarticle files (278
application files and five root files) and replaced the README. All added
blobs and modes, and the replacement research README, match historical main
483e6edbec72ec76e48f2259e943e674b76e5041 exactly. These are research-source
contamination, not new model results or new runtime evidence.

The direct tree is ef7c0854cf57fc0f0a113074b7bdafd42c34ea72. The SHA-256 of
the full-index, no-renames raw diff inventory from the canonical base to this
direct tip is
cf9b2caf71bfc89accb5a0053a020740ecd1af602f48a52d5fbb4a04d4d29603.
The committed contract and validator preserve these identities and verify the
content-level comparisons; a commit message alone is not an audit.

## Authorized repair

Keep the ordinary direct-ahead rejection. The explicit
`--reconcile-reviewed-direct` option authorizes only the audited tip under the
committed contract. Authenticate and freshly fetch both remotes, require the
current source to be freshly fetched main, and verify that every article input
and publication-support blob remains identical to the audited main anchor.
Require the captured review, disposition ledger, direct parent, complete tree,
diff inventory and historical-source comparisons to match.

Build and compile the current-main manifest projection. Create one ordinary
publication commit whose sole parent is the audited direct tip and whose tree
contains only that projection. The subject and source marker retain the
normal publisher format. Advancing the canonical snapshot from its ancestor
and advancing direct Overleaf from its immediate parent are both normal
fast-forward pushes. No browser content or history enters research main.
The historical direct commit remains recoverable as the published child's
parent; no edit is erased by rewriting history.

The original ref identities must still hold immediately before pushing. The
origin source guard and snapshot update remain atomic; both remotes must read
back the same final commit, tree and source identity. If origin advances but
the direct push fails, the existing one-commit, one-parent, source-verified
recovery path can finish without a broader drift exception. A new browser
edit, changed prior snapshot, altered contract, or changed article input stops
the repair for another audit.

## Scientific and operational boundaries

This repair changes publication code and records, not manuscript findings,
models, fitting jobs, scientific source files or runtime objects. The GloFAS
correction remains pending; `--review-draft` and all six historical-result
notices remain mandatory for deploying the current text. The advisor register
still has 106 implemented draft dispositions, six awaiting corrected GloFAS
results, one missing one-step comparison input set, one timing-evidence gap,
and one PriceFM item preserved unchanged. Reconciliation does not close those
items or make the paper submission-ready.

Account-wide Overleaf--GitHub authorization remains available for the owner's
other projects. Do not use this project's GitHub synchronization controls.
Credentials belong only at Git's private prompt/cache, never in this contract,
source, URLs, logs or chat. No cleanup or deletion of scientific evidence is
authorized.

## Verification procedure

Run the existing publisher and review-draft fixture suites, then the dedicated
reviewed-reconciliation suite in isolated local bare repositories. Verify
unflagged rejection, exact reviewed success, source/ref/contract mutations,
sanitized final inventory, preserved parent history, dry-run immutability,
idempotence and recovery with the ordinary publisher after an interrupted
direct push. Compile both manuscripts from the exact integrated source bundle.
Verify that the application and article surfaces are unchanged from the main
anchor and retain the prior registered-harness receipt; record any fresh
combined checks separately rather than infer execution.

Only a real successful publication and fresh remote readbacks establish that
Overleaf is updated. A successful authentication, local audit or dry run alone
does not.

The dedicated fixture suite passed fifteen tests, including fourteen contract-
field mutation cases, changed canonical refs, and a concurrent unknown direct
edit preserved by non-fast-forward refusal. The sixteen existing publisher
cases and fourteen review-draft tests also passed. An independent review
authenticated the real three-file advisor surface, 283 historical additions
and 115 ledger items, and rejected eight separate contract mutations. Reader
checks passed 78 checks/seven mutations, statistical-language checks passed
81/38, and the GloFAS source-authorization check passed 68/43. No scientific
run was launched by this verification. The application's tree is unchanged
from the prior fully tested main anchor; that prior full-harness receipt is
not presented as a fresh harness execution here.
