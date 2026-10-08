# GloFAS Search III Parts 1–4 article integration audit

Date: 2026-10-07 (final verification completed 2026-10-08 UTC).

## Authority and review boundary

| Coordinate | Verified value |
|---|---|
| Fresh origin/main base | `e721bfddee81269864febea0eca0bbd0c5eba369` |
| Frozen source branch | `work/glofas-search3-adjacent-tau-recovery-20260930` |
| Frozen source HEAD | `fecc4bd5dbf608cc30e4b38a49e6d8cb08bf92a1` |
| Handoff SHA256 | `b119fac187530819b31c186fe762be86ae6cbc8fe1c72ac10153cbd8d05f2ed4` |
| Reviewed article/code commit before this report | `39ffe899b66191c4ec2337b5888e656d9a517a64` |
| Source reconciliation merge | `f874406b503159ed3539412b4552309743cde43a` |
| Source merge parents | `e721bfddee81269864febea0eca0bbd0c5eba369`, `fecc4bd5dbf608cc30e4b38a49e6d8cb08bf92a1` |
| Coordinator review branch | `work/glofas-search3-article-integration-20261007` |

The source was fetched, its clean synchronized worktree and scientific ancestor
verified, and every source path classified before the non-fast-forward merge.
No scientific branch was rebased, amended, cherry-picked, or force-pushed.
Source history is preserved. Only command-line Git is used for publication.

This report certifies the reviewed tree and local publication gates. It is not
a claim that remote publication has already occurred. The final two-parent
main-promotion commit and the two Overleaf read-back hashes must be reported
after the authorized publishers complete. At report creation, direct Overleaf
authentication is unavailable; no Overleaf ref has been changed.

## Exact source reconciliation

The source delta is 134 paths: 103 additions, 31 modifications, no deletion
or rename. Four files overlap main: the R, scripts, and tests READMEs, and
`application/tests/run_tests.R`. Only the R and scripts READMEs conflict;
both retain main's JOINT material and append the GloFAS source documentation.
The other two shared files were automatically combined and manually reviewed.

The source integration manifest verifies 134/134 final Git blob IDs: 128 exact
source imports and six documented manual dispositions. The latter comprise
the four shared files, one trailing-space-only Python formatting correction,
and one synthetic launcher-fixture repair. Production launcher behavior,
strict source-link guards, and scientific test assertions are unchanged.
Standalone fixtures run in separate pinned-R processes to prevent namespace
and premature-cleanup interference. All 100 existing main registrations
remain; all 34 imported synthetic regressions and the new projection test
are registered. The real-data smoke fit is retained but deliberately not run
under the no-refit boundary.

Manifest:
`docs/implementation_notes/glofas_search3_source_integration_manifest_20261007.csv`

SHA256:
`8270f18d044c82cd88030e9c9d33af9a50a80071d32b17871df7b5913dd9320c`

The companion reconciliation note records direct review of the shared
structured-exAL, latent-path, driver-prior, continuation, and C++ changes.
The discontinuous exAL diagnostic remains recorded but is excluded from the
operative quadrature stopping norm. No posterior-target formula was changed
by that repair.

## Frozen numerical source and deterministic projection

The closeout checker passes all 11 gates. The output manifest remains
`968096fe310b61c4b05423890cad529e7c891e51691cd997ef253753c7c9de9f`.
Canonical Joint AL and Joint exAL fit SHA256 values remain, respectively,
`0ac25ad186fa660d7958484db822c0e2c7ce60ae933928498dfd42180e439274`
and
`0784549437365dc239e123fe0fd660d4212fa0e7a72dc1034765b5ba73e6e823`.
The six-page source PDF remains
`799d05536f7331d80ff534f4198e5977c08344d97d8f83167c52b8534e82ae31`.

Scripts 447 and 448 are new, nonconflicting script numbers. The builder checks
the frozen runtime before producing sanitized derivatives in temporary
staging. The checker works independently from the tracked projection and,
when supplied the runtime explicitly, checks full-precision source equality.
Two complete builds produced identical hashes for all 33 generated files.

The generated surface is 29 versioned files (13 CSVs, nine TeX tables, six
single-page PDFs, one publication manifest) plus four stable aliases.
Verified contents include 18 Part 1–3 family rows, seven Part 4 families,
49 calibration rows, 3,892 scoring quantile rows, 174 executed prior scalars,
24 recursive prior-setting rows, and two strict joint convergence rows.

Publication manifest:
`tables/glofas_search3_part1234_final_20261007_publication_manifest.csv`

SHA256:
`5a7ac4fc1b35f3e7b19c4535e5e5c1cc56c4dfe87927b42f6f66122d49a01335`

| Stable alias | SHA256 |
|---|---|
| `tables/glofas_application_current_outputs.tex` | `57d8ac0430dd2174c700cc6657eb396b6460909f6b9f9055eb4d8f28a69da471` |
| `tables/glofas_application_current_score_summary.csv` | `c15d21cda11c8c8a89742b32b8a0c07b85851176dac29c30076941e32c52c998` |
| `tables/glofas_application_current_score_summary.tex` | `43604de723086dfa1e132715d8d14f624e400969dbe5b3b0ef6a949b8f74f183` |
| `tables/glofas_application_current_selection_manifest.csv` | `25691eddb333d85dbc00de8ec33389d23796499343e0b01500778754e94f2c1c` |

All CSVs preserve round-trip double precision; TeX alone rounds display values.
The six PDF derivatives are vector-only, nonblank, have embedded fonts and
single-page geometry, and preserve the frozen graphical content. The tiny
right-edge source date clipping is corrected through a verified page-bound
expansion during deterministic extraction, without recomputing plot data.

## Article interpretation and limitations

The origin is 2022-12-25 on the log(1 + flow) scale. Parts 1–3 provide 30-day
recursive paths through 2023-01-24; Part 4 uses 28 issued horizons through
2023-01-22, with 51 ensemble members each weighted 1/51. Future USGS truth
is scoring-only; realized PRISM/ERA5 covariates make this a single-origin
retrospective oracle-covariate experiment, not operational validation.

Search III used internal rainy-season development and locked confirmation
folds across reservoir seeds. It retained reference `search3_ref_001`
(depth one, 1500 units) and adopted discrepancy `search3_dis_007`
(depth one, 1000 units). The protected final window did not select reservoirs,
priors, stopping criteria, or model families.

Part 4 Independent AL is the descriptive issued-window leader:
grid aCRPS 0.715603376362904 versus raw GloFAS 1.43597710285616,
a 50.17% reduction. Its nominal-90% interval coverage is 0.750.
Corrected Joint AL and Joint exAL strictly converge at outer sweeps 11 and 28,
with three consecutive full-state passes each. Joint AL has the greatest
modeled 90% coverage, 0.785714, still below nominal. Joint exAL is numerically
qualified but weak in the upper tail, with level-0.95 empirical coverage
0.285714. Normal RHS/VB has worse Part 4 grid aCRPS than raw GloFAS.
No uncertainty analysis of differences supports a superiority claim.

Part 1 Independent AL has three adjacent crossing pairs and Independent
exAL one; joint Part 1 and all Part 3 families have zero. No crossing
correction is applied. Part 2 post-cutoff discrepancy paths are unscored
because retrospective GloFAS ends at the cutoff.

The supplement reports the actual executed priors and learned scales,
distinguishes search specifications from downstream family priors, and
preserves the Gaussian future-path-prior, local Gaussian–Delta, and weighted
augmented-working-likelihood qualifications. No GloFAS MCMC result is claimed.

## Required validation receipts

Pinned R:
`/data/jaguir26/local/opt/R/4.6.0/bin/Rscript`.

Python:
`/usr/bin/python3.11`. Temporary pytest/PyYAML dependencies are confined
to /tmp; no system or scientific environment is modified.

| Gate | Result |
|---|---|
| Frozen closeout script 446 | PASS 11/11 |
| All imported synthetic source tests | PASS 34/34 |
| Source-only full application harness | Exit 0 |
| Source-only IND wrappers with verified external validation authority | Exit 0 each |
| Final integrated full application harness | Exit 0 |
| Changed R syntax | PASS 81/81 |
| Changed Python byte-compilation | PASS 45/45 |
| Projection unit test, public checker, runtime equality checker | PASS |
| Global final manuscript checker | PASS; 19 immutable scientific files |
| IND v14 oracle-figure checker | PASS 132 checks; four active figures |
| JOINT pure-DESN checker | PASS 167 checks; 29 assets, 412 protected application assets |
| PriceFM R98 checker | PASS; 114 rows, 38 regions, 10 unchanged outputs |
| Whole diff whitespace check | PASS |
| Two independent complete projection builds | All 33 hashes identical |
| Clean source bundle | PASS; main 22 pages, supplement 54 pages |
| Committed snapshot at reviewed commit | PASS; 80 source files, 83 snapshot files |

The six minimum source tests are the final-closeout R test, Part 4 inner-audit
R test, Part 4 latent-family R test, exact structured-exAL R test, joint-release
Python test, and Search III dependency-closure Python test. The closeout R
test is suite-loaded with its declared package/module dependencies rather than
incorrectly invoked without bootstrap. All run successfully.

One pre-existing optional discrepancy-engine adapter skips because its
external engine is unavailable. The deliberately excluded real-data smoke
test is not counted as executed. A tiny synthetic plotting fixture emits its
existing axis-range warning. The five IND checker warnings are retained
scientific diagnostics, not LaTeX build warnings. No required gate is skipped.

An initial source-only sandbox run failed the unchanged host-process visibility
guard. Its receipt is retained; the unchanged harness subsequently passes with
normal host visibility. The detached /tmp source-only worktree's two
relative-root IND wrappers were explicitly rerun with the verified frozen
validation authority. No host guard, inference assertion, or scientific
qualification was suppressed.

Final integrated harness log SHA256:
`4eccdec0462003575d7431e68b1cfdaa6e7ab0a4ef1f520d702835e555e8c724`.

Final closeout-check log SHA256:
`63fc5b20b6b8edd8921e6856d5f2a478276992564c0317751ea376e7b95914d1`.

Source-only host-harness log SHA256:
`8a3823934210c31eb4adef35854a159631b8d85674e9cde3f4feecbf5d186a70`.

## Manuscript and publication closure

Main SHA256:
`20174f5e1c60b442a32c70a7cc8e8d27a9a5a4d12f543d46a99ecc51a9a0619c`.

Supplement SHA256:
`7712a23b0db34e83565e8a096254c715dc2438ce584916237a9c7477a9f7e63a`.

Closure SHA256:
`0579971b981047de480949534b6a44d607c6f364f40a5ea1bb79cc1b4d433643`.

Both manuscripts pass BibTeX plus four recorder-enabled LaTeX passes from the
clean 80-file bundle with project search-path overrides cleared. Final logs
contain no warnings, unresolved citations/references, or under/overfull boxes.
All 76 pages are nonblank with in-page text. All six figures and every changed
article/supplement page received visual review. Recorder checks find no
unlisted or external project dependency.

The old September sweep-10 and FR09 assets remain in Git as historical evidence,
but are absent from active aliases, manuscript dependencies, and the source
closure. Every remaining stale token is historical and excluded from upload.
All unrelated scientific assets and prose remain unchanged.

The audit also found seven inherited, unreferenced JOINT/PriceFM CSV companions
containing absolute runtime source paths. They remain byte-identical in Git
but are excluded from the article-only bundle:

- `tables/joint_qdesn_pure_desn_v1_cell_plan.csv`
- `tables/joint_qdesn_pure_desn_v1_frozen_contract.csv`
- `tables/joint_qdesn_pure_desn_v1_manifest_audit.csv`
- `tables/joint_qdesn_pure_desn_v1_review_closeout_receipt.csv`
- `tables/joint_qdesn_pure_desn_v1_source_hashes.csv`
- `tables/pricefm_r98_authoritative_registry.csv`
- `tables/pricefm_r98_authority_transition_ledger.csv`

The JOINT and PriceFM publication checks retain all original asset-hash,
complete-packet, row-count, scientific-value, and manuscript-disclosure checks;
only those explicit upload-inclusion requirements change. The global checker
now rejects local paths and runtime-object references in every textual upload
companion. All 60 other unrelated published assets are unchanged.
The active IND v14 manifest refreshes only its four global publication hashes;
every IND scientific value, figure, renderer, wrapper, and historical v13
manifest remains unchanged.

## Exact article assets and promotion discipline

The complete changed-path and blob/hash inventory is
`docs/implementation_notes/glofas_search3_main_article_promotion_manifest_20261007.csv`.
It includes every changed file except the inventory itself; the full final
Git diff also includes that inventory. Each file records its role and upload
inclusion. There are 181 reviewed changed paths before these two report files.

The principal final tables are:

- `tables/glofas_search3_part1234_final_20261007_part4_scores.tex` (main);
- `tables/glofas_search3_part1234_final_20261007_part123_scores.tex`;
- `tables/glofas_search3_part1234_final_20261007_calibration.tex`;
- `tables/glofas_search3_part1234_final_20261007_convergence.tex`;
- `tables/glofas_search3_part1234_final_20261007_selected_specifications.tex`;
- `tables/glofas_search3_part1234_final_20261007_prior_settings.tex`;
- `tables/glofas_search3_part1234_final_20261007_part123_prior_settings.tex`.

The six figure paths are:

- `figures/glofas_application/glofas_search3_part1234_final_20261007_part1.pdf`;
- `figures/glofas_application/glofas_search3_part1234_final_20261007_part2.pdf`;
- `figures/glofas_application/glofas_search3_part1234_final_20261007_part3.pdf`;
- `figures/glofas_application/glofas_search3_part1234_final_20261007_part4.pdf`;
- `figures/glofas_application/glofas_search3_part1234_final_20261007_convergence.pdf`;
- `figures/glofas_application/glofas_search3_part1234_final_20261007_calibration.pdf`.

No runtime RDS/RData/model object, log, status marker, cache, local tracker,
or scientific process is committed, modified, deleted, transferred, or launched.
Frozen runtime and source worktree remain retained and clean.

Push the reviewed coordinator branch first. Promote it through a new
`integration/glofas-search3-article-authority-20261007` branch created at
fresh origin/main, using a two-parent non-fast-forward merge and the
repository's Git-only main publisher. If main has advanced, stop and repeat
reconciliation and required gates. From the actual promoted main commit,
repeat projection/manuscript checkers, clean builds, and the source-bundle
check before the Git-only Overleaf publisher. Verify origin/main,
origin/overleaf/article-snapshot, and overleaf-direct/main by remote read-back.
No force push, hosting extension, or unreviewed overwrite is permitted.
