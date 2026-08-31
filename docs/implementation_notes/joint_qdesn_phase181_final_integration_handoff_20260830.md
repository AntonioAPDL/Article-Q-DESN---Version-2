# Joint QDESN Phase181 Final Integration Handoff

Date: 2026-08-30

Integration state: `READY_FOR_INTEGRATION`

This is the final handoff for the seven-level Phase178--181 JOINT scientific
lane. The integration coordinator owns all merges into `main`, combined-repo
testing, manuscript projection, compilation, and Overleaf publication. This
lane must not perform those actions.

## 1. Lane Identity

| Field | Value |
|---|---|
| Lane | Joint QDESN Phase180 balanced score packet and Phase181 stability extension |
| Transcript | `/home/jaguir26/.codex/sessions/2026/08/13/rollout-2026-08-13T01-40-31-019ff9a2-eb64-7153-b368-05a944eb1220.jsonl` |
| Worktree | `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_phase180_score_plan_20260824` |
| Branch | `work/joint-qdesn-phase181-score-stability-extension-20260826` |
| Upstream | `origin/work/joint-qdesn-phase181-score-stability-extension-20260826` |
| Scientific content HEAD | `4104f696f4410bbcab49f8d3efd6fef0a7532648` |
| Origin main at final audit | `394558264d791816ced71742738d6f988a45780f` |
| Merge base with origin/main | `38caf04c44b2102697db41834484370fd5fd5c59` |
| Ahead/behind before handoff-only commit | 8 ahead, 32 behind |
| Merge-tree preflight | pass; synthetic merge tree `4f5b472805372f8790cb03ff31ca912cdb6b9969` |

The commit containing this handoff follows the scientific content HEAD. After
fetching the branch, obtain the final branch tip with:

```bash
git rev-parse origin/work/joint-qdesn-phase181-score-stability-extension-20260826
```

Do not use the older `3def2d7` HEAD recorded inside the generated runtime
handoff as the merge target. That runtime handoff remains hash-valid for the
Phase181 packet, but the branch now also contains the final closeout and this
tracked coordinator record.

## 2. Unique Commit Sequence

Apply the dedicated branch as one reviewed merge. Its unique scientific
sequence relative to the audited `origin/main` is:

| Commit | Subject |
|---|---|
| `3b2d0672505534a46db17e4996441b36a1da6d55` | Implement Phase180 balanced DGP score packet |
| `092da955440380cd9f7abbed0ac87180dadbd1ef` | Make Phase180 preparation resumable |
| `c0285b373ebe128bf18f889112d35c4d527bf556` | Reuse verified Phase154 independent AL starts |
| `7733630d1418f7fd65b5db6169620e92b7f7f5cf` | Handle rank-deficient Phase180 AL starts |
| `85271016a3ce197e705d93d93790fb615a7cc06f` | Recover Phase180 endpoint-start failures |
| `daa6ad2b9155366638960860fba0b77ac2a183c2` | Preserve parent starts in Phase180 recovery |
| `3def2d70d6cc71b6a7a72c6fc875d557edb54b9a` | Add Phase181 score stability extension |
| `4104f696f4410bbcab49f8d3efd6fef0a7532648` | Close Phase181 seven-level score study |

The final handoff-only commit is intentionally not hard-coded into its own
contents. It is the branch tip returned by the command above.

## 3. Exact Tracked Change Scope

The coordinator should expect these task-owned changes, plus this handoff
file itself:

```text
M  application/R/joint_qdesn_dgp_integrated_acrps.R
A  application/R/joint_qdesn_phase180_balanced_dgp_score_packet.R
A  application/R/joint_qdesn_phase181_score_stability_extension.R
A  application/config/joint_qdesn_phase180_balanced_dgp_score_contract_v1.csv
A  application/config/joint_qdesn_phase181_score_stability_extension_contract_v1.csv
A  application/scripts/268_prepare_joint_qdesn_phase180_balanced_score_packet.R
A  application/scripts/269_run_joint_qdesn_phase180_balanced_score_chain.R
A  application/scripts/270_check_joint_qdesn_phase180_balanced_score_completion.R
A  application/scripts/271_launch_joint_qdesn_phase180_balanced_score_completion.sh
A  application/scripts/272_finalize_joint_qdesn_phase180_balanced_score_packet.R
A  application/scripts/273_stage_joint_qdesn_phase180_article_assets.R
A  application/scripts/274_freeze_joint_qdesn_phase180_integration_handoff.R
A  application/scripts/275_prepare_joint_qdesn_phase180_endpoint_start_recovery.R
A  application/scripts/276_run_joint_qdesn_phase180_endpoint_start_recovery.R
A  application/scripts/277_check_joint_qdesn_phase180_endpoint_start_recovery.R
A  application/scripts/278_launch_joint_qdesn_phase180_endpoint_start_recovery.sh
A  application/scripts/279_prepare_joint_qdesn_phase181_score_stability_extension.R
A  application/scripts/280_run_joint_qdesn_phase181_score_stability_chain.R
A  application/scripts/281_check_joint_qdesn_phase181_score_stability_extension.R
A  application/scripts/282_finalize_joint_qdesn_phase181_score_stability_extension.R
A  application/scripts/283_stage_joint_qdesn_phase181_article_assets.R
A  application/scripts/284_freeze_joint_qdesn_phase181_integration_handoff.R
A  application/scripts/285_launch_joint_qdesn_phase181_score_stability_extension.sh
A  application/scripts/_joint_qdesn_phase180_balanced_score_bootstrap.R
A  application/scripts/_joint_qdesn_phase181_score_stability_bootstrap.R
A  application/tests/test_joint_qdesn_phase180_balanced_dgp_score_packet.R
A  application/tests/test_joint_qdesn_phase180_endpoint_start_recovery.R
A  application/tests/test_joint_qdesn_phase181_score_stability_extension.R
A  docs/implementation_notes/joint_qdesn_phase180_balanced_dgp_score_packet_master_plan_20260824.md
A  docs/implementation_notes/joint_qdesn_phase180_endpoint_start_recovery_20260825.md
A  docs/implementation_notes/joint_qdesn_phase181_score_stability_extension_20260826.md
A  docs/implementation_notes/joint_qdesn_phase181_final_closeout_and_dense_grid_plan_20260830.md
A  docs/implementation_notes/joint_qdesn_phase181_final_integration_handoff_20260830.md
```

No manuscript, PriceFM, GloFAS, TT500, independent-QDESN lane, or Overleaf
file is part of this branch change scope.

## 4. Run and Completion Inventory

| Run | Scope | Complete | Failed | Manifest |
|---|---|---:|---:|---|
| Phase178 exact-M0 ranking | 180 chains, 45 candidate-replicate cells | 180 | 0 | 22/22; `3a9c387abfe2a7b5a471da77b1a690fba76bfcf7f1eaad0c21a74764f9ef6848` |
| Post-Phase178 DGP-score audit | 45 source-complete cells | 45 | 0 | 35/35; `d4d8d126583182736bf0c66bf1dab6b283973f17e70faa4740af163514416a11` |
| Phase179 case-specific confirmation | 384 chains, 24 cases | 384 | 0 | 25/25; `fd9c04316c8fff7f943212a4b4c043b2a5edf32267eedbe2636db3d45f1d73ef` |
| Phase180 balanced completion | 168 new chains, 32 final cells | 168 | 0 | 28/28; `93287a327f1b820e89de0cb4df295e15f6264fd2f96d157931cd17d23558b3e6` |
| Phase181 same-specification extension | 152 chains, 19 extension cells | 152 | 0 | final packet 40/40; `e392c717c060636ec8ebadb51842b7abfe3fb531b99de3659cee8875d26d0292` |

No Phase178, Phase179, Phase180, or Phase181 worker remains active. The old
Phase112 tmux shell has no matching JOINT worker and is out of scope; do not
kill or modify it as part of integration.

## 5. Final Evidence Summary

The final Phase181 packet contains:

- 32/32 finite scenario-model cells;
- eight scenarios and four model/readout classes per scenario;
- 16 paired joint-minus-independent contrasts;
- 13 Phase181 lower-mean source promotions;
- six Phase180 baselines retained after direct extension comparison;
- 13 unaffected Phase180 sources retained;
- zero contract crossings;
- 21 passing and 11 review-level score functionals;
- implementation hard gates `pass` and overall diagnostic gate `review`.

Joint models are numerical score winners in five of eight scenarios. All 16
paired joint-minus-independent 95% score-contrast intervals include zero, so
winner language must remain descriptive. Canonical forecast raw crossings are
1 for Joint QDESN AL, 25 for Independent QDESN AL, and zero for both exAL
rows; all four contract totals are zero.

Exact M0 materially repaired gamma/sigma mixing. The remaining reviews are
mostly alpha/readout and score-functional precision, not an unaddressed
gamma/sigma failure.

## 6. Frozen Evidence Paths

### Final selected packet

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/
joint_qdesn_phase181_score_stability_extension_packet_20260826
```

- size: approximately 35 MB;
- manifest entries: 40/40 verified;
- manifest SHA-256:
  `e392c717c060636ec8ebadb51842b7abfe3fb531b99de3659cee8875d26d0292`.

### Article-safe staging

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/
joint_qdesn_phase181_article_assets_staging_20260826
```

- size: approximately 128 KB;
- manifest entries: 12/12 verified;
- manifest SHA-256:
  `96a54710059002fa1f23aa86b515d6b2f9fc60505888d8f8eb7b79bc7578a69e`.

### Generated runtime handoff

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/
joint_qdesn_phase181_integration_handoff_20260826
```

- size: approximately 68 KB;
- handoff entries: 9/9 verified;
- inherited source entries: 73/73 pass;
- manifest SHA-256:
  `46e5ae840712c1b31b15b0d61fd711523ab7058e33917e8359f92d0a35a3cea0`.

## 7. Article-Safe Files to Project

Only these eight staged payloads are marked article-safe:

| File | SHA-256 |
|---|---|
| `joint_qdesn_phase181_article_scenario_model_summary.csv` | `1fd2078f86c5c2c4daa902971bf9af713b3304bc84566229ba99a96aefd44ca7` |
| `joint_qdesn_phase181_numerical_winner_summary.csv` | `22918ed621ae7288855f4d742a91faac8068663490fcfa7b70889977542e909e` |
| `joint_qdesn_phase181_mean_metric_promotion_decisions.csv` | `ccb931c10d46cf96249ac187c6efc3aa29671ce9d6b806e7a2250a92c9bcdd02` |
| `joint_qdesn_phase181_joint_independent_contrast_summary.csv` | `d84ec89dab227176500ec642ecb6259fa5554809c3f6995e96e0c8a666c8a19c` |
| `joint_qdesn_phase181_supplemental_diagnostics.csv` | `11b9e3d2044b7b3f57309ae74976a1df870c25dedb5ef19c84648f9441f96e17` |
| `joint_qdesn_phase181_crossing_provenance.csv` | `893afccac5dbba192c4cebe9cb85e7db8c889e492ec60e61d413cf6796ff759b` |
| `joint_qdesn_phase181_manuscript_wording_guidance.csv` | `b09ebdb86794b4abccd5b0048c6bb2373ccb762ceb369b4794c49c91e3a7d6da` |
| `joint_qdesn_phase181_dgp_integrated_score_table.tex` | `5daac77760ae739a2167f45efa52972a399ab3a7c52ce1daf1f8ce2e9ff05618` |

The coordinator should copy by verified content, adapt labels and placement to
the latest manuscript, and preserve the source hashes in the article asset
manifest. The staging directory itself remains outside Git.

## 8. Runtime Paths That Must Stay Excluded

Do not commit or publish these generated directories:

```text
application/cache/joint_qdesn_phase181_score_stability_extension_freeze_20260826
application/cache/joint_qdesn_phase181_score_stability_initialization_work_20260826
application/cache/joint_qdesn_phase181_score_stability_extension_chains_20260826
application/cache/joint_qdesn_phase181_score_stability_extension_20260826_orchestration
application/cache/joint_qdesn_phase181_extension_score_work_20260826
application/cache/joint_qdesn_phase181_selected_score_work_20260826
application/cache/joint_qdesn_phase181_score_stability_extension_packet_20260826
application/cache/joint_qdesn_phase181_article_assets_staging_20260826
application/cache/joint_qdesn_phase181_integration_handoff_20260826
```

Their approximate combined Phase181 footprint is 419 MB, dominated by the
349 MB retained chain directory. These are final reproducibility sources, not
legacy losers. Keep them on local storage until article integration and any
dense-grid baseline audit are complete. Do not move them into Git or Overleaf.

## 9. Verification Performed

The following checks passed in the scientific worktree on 2026-08-30:

```bash
Rscript application/tests/test_joint_qdesn_phase181_score_stability_extension.R
# Phase181 score-stability extension tests passed.

Rscript application/tests/test_joint_qdesn_phase180_balanced_dgp_score_packet.R
# Phase180 balanced DGP-score packet tests passed.

git diff --check
# exit 0
```

An independent schema check proved:

- exactly 32 final rows;
- exactly eight scenarios with four models each;
- all posterior means and 95% interval endpoints finite and ordered;
- exactly 16 finite paired contrasts;
- zero contract crossings;
- canonical forecast raw crossing totals `0,25,0,1` when sorted as
  Independent exQDESN, Independent QDESN, Joint exQDESN, Joint QDESN.

All packet, staging, handoff, and inherited source hashes were recomputed from
file contents. They were not accepted from manifest presence alone.

The scientific lane did not compile the manuscript because it made no
manuscript edit. Both manuscripts must be compiled after the coordinator
projects the staged article assets into the current integrated article tree.

## 10. Required Article Interpretation

The article integration must state:

1. the headline metric is the DGP-integrated finite-grid quantile score;
2. entries are posterior means with equal-tailed 95% credible intervals;
3. fit and forecast MAE/RMSE are oracle quantile-path recovery diagnostics;
4. raw crossings measure pre-contract coherence and contract crossings are
   zero;
5. the joint AL/exAL composite objective is not claimed to be a normalized
   scalar predictive density;
6. numerical winners are descriptive because all paired contrast intervals
   include zero;
7. fitted coefficients remain fixed while lagged realized responses become
   sequentially available, so this is a sequential conditional forecast
   evaluation rather than an open-loop 30-step recursive path forecast.

Do not call the new score `Grid CRPS` in article-facing text. Do not retain
forecast MAE as the bolded headline criterion in the joint scenario table.

## 11. Unresolved Risks

- Eleven score functionals remain review-level despite complete finite draws.
- Alpha/readout coordinates remain less well mixed than gamma/sigma.
- All 16 paired score intervals include zero, limiting superiority claims.
- The seven-level grid offers relatively few crossing opportunities.
- The article currently contains a stale forecast-MAE-centered joint table.
- The latest article checkout observed during this audit was on an unrelated
  GloFAS branch, so projection must begin from the coordinator's reconciled
  `origin/main`, not from that checkout's working state.
- The future 19-level design changes fitted models and requires a new
  protected contract; it cannot be generated by interpolating Phase181 paths.

None of these is an implementation failure for the seven-level handoff.

## 12. Recommended Merge and Publication Order

1. Fetch all remotes in the coordinator worktree.
2. Create or update a dedicated integration branch from current
   `origin/main`.
3. Merge
   `origin/work/joint-qdesn-phase181-score-stability-extension-20260826`
   with a reviewed non-fast-forward merge.
4. Confirm the 33-file task scope and resolve only genuine integration drift.
5. Run the Phase180 and Phase181 focused tests in the combined tree.
6. Verify the three Phase181 manifests and 73 inherited source entries.
7. Project the eight article-safe staged files by hash.
8. Replace the stale joint table and revise only the directly related prose,
   captions, labels, and supplemental references.
9. Run focused article-asset tests and scan for stale forecast-MAE bolding or
   `Grid CRPS` wording.
10. Compile `main.tex` and `qdesn-supplement.tex` with halt-on-error.
11. Commit the integration, push authoritative `main` through the coordinator,
    and publish the article-only Overleaf snapshot using command-line Git.
12. Record the resulting main, snapshot, and Overleaf commit/tree hashes.

After integration, create the dense-grid lane from the new `origin/main` and
follow the separately frozen 19-level plan in
`joint_qdesn_phase181_final_closeout_and_dense_grid_plan_20260830.md`.

## 13. Final Declaration

`READY_FOR_INTEGRATION`

All seven-level scientific runs are closed. The packet is finite,
source-complete, hash-verified, and contract-noncrossing. The dedicated branch
contains the reproducibility implementation and final scientific closeout.
No main or Overleaf ref was modified by this lane.
