# Joint QDESN Phase179 DGP-Score Integration Handoff

Date: 2026-08-24

Status: `READY_FOR_INTEGRATION`

This handoff closes the JOINT Phase179 case-specific DGP-integrated score
confirmation. It authorizes integration review only. It does not authorize a
new production launch from this branch, a merge by this scientific lane,
article mutation, `main` publication, or Overleaf publication.

## Identity

- Lane: JOINT QDESN/exQDESN synthetic multi-quantile validation.
- Transcript:
  `/home/jaguir26/.codex/sessions/2026/08/18/rollout-2026-08-18T20-37-39-01a01773-ca48-7b52-a4bd-f848be446d74.jsonl`.
- Worktree:
  `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_phase179_dgp_score_20260819`.
- Branch:
  `work/joint-qdesn-phase179-dgp-score-confirmation-20260819`.
- Upstream:
  `origin/work/joint-qdesn-phase179-dgp-score-confirmation-20260819`.
- Scientific closeout content HEAD:
  `ff10d39027a6ed5c6257a6bff167b83ee8e220d5`.
- The containing handoff commit is the pushed branch tip; integration must
  record it with `git rev-parse HEAD` rather than relying on an impossible
  self-referential hash inside that commit.
- Merge base with `origin/main`:
  `9559e354e83f0edaf82e3add4c590dbdc378a64e`.
- `origin/main` at closeout audit:
  `e688075c3e7950785e1c0ce4ea782130952edccd`.
- Divergence before this handoff commit: 53 commits on `origin/main`, 13 commits
  on this branch.

Unique task commits through the closeout content HEAD, oldest first:

1. `7b13f9cb72f4ccc4fa88f450c72fccee450eb9ed` Add post-M0 case-specific exQDESN recovery workflow.
2. `e830d25a3530b0e5f18b2ea186801a3fa494641e` Make joint exQDESN worker scheduling completion-aware.
3. `236b5b54c93844a94a4f4cc13893471f70faac17` Parse joint exQDESN worker plans by schema.
4. `f271af37e3b0c0d48db88396a6bdd668657d5c22` Document Phase 178 production M0 ranking launch.
5. `a37ab7c73f6464ef998ea70342b57e6e9f037dfe` Fix Phase 178 M0 design identifier contract.
6. `d193bce6aca00e5370c77ee08dc28fee971d8096` Close Phase 178 exact-M0 ranking.
7. `ae6c57265eb3f3f6dbdf5afee0bf06485d8b8a84` Add Phase 178 integration handoff.
8. `88edc9c76827a1c57b1ebedb6496c49052da0916` Add post-Phase178 DGP score audit.
9. `5e309aee8ca31331f57cdc2b76cb0e3614046ede` Close post-Phase178 DGP score audit.
10. `408e04d142afd53337f2b82a17a5c6b5bc43db6a` Add post-Phase178 score handoff.
11. `1bc9d6e0d3b9cde9f61a56aa4da79b25b57deb1c` Add case-specific Phase 179 score confirmation.
12. `3fc422d98f148d36085b3e44e8955bb95a61b01f` Close Phase179 DGP score confirmation.
13. `ff10d39027a6ed5c6257a6bff167b83ee8e220d5` Distinguish joint score pairing audit.

## Exact Tracked Files

Relative to the merge base, the branch adds only these JOINT-owned files:

- `application/R/joint_exqdesn_phase176_180_post_m0_recovery.R`
- `application/R/joint_qdesn_dgp_integrated_acrps.R`
- `application/R/joint_qdesn_phase179_dgp_score_confirmation.R`
- `application/config/joint_exqdesn_phase176_180_post_m0_recovery_policy_v1.csv`
- `application/config/joint_exqdesn_phase178_case_specific_neighborhood_v1.csv`
- `application/config/joint_exqdesn_phase178_post_m0_compute_policy_v1.csv`
- `application/config/joint_exqdesn_phase178_prior_screen_authority_v1.csv`
- `application/config/joint_qdesn_phase179_dgp_score_confirmation_policy_v1.csv`
- `application/config/joint_qdesn_post_phase178_dgp_score_contract_v1.csv`
- `application/scripts/240_audit_joint_exqdesn_phase176_post_m0_functionals.R`
- `application/scripts/241_prepare_joint_exqdesn_phase177_same_spec_m0.R`
- `application/scripts/242_run_joint_exqdesn_phase177_same_spec_m0_chain.R`
- `application/scripts/243_check_joint_exqdesn_phase177_same_spec_m0.R`
- `application/scripts/244_launch_joint_exqdesn_phase177_same_spec_m0.sh`
- `application/scripts/245_finalize_joint_exqdesn_phase177_same_spec_m0.R`
- `application/scripts/246_prepare_joint_exqdesn_phase178_post_m0_screen.R`
- `application/scripts/247_run_joint_exqdesn_phase178_vb_rows.R`
- `application/scripts/248_check_joint_exqdesn_phase178_vb_screen.R`
- `application/scripts/249_launch_joint_exqdesn_phase178_vb_screen.sh`
- `application/scripts/250_prepare_joint_exqdesn_phase178_m0_ranking.R`
- `application/scripts/251_run_joint_exqdesn_post_m0_chain.R`
- `application/scripts/252_check_joint_exqdesn_phase178_m0_ranking.R`
- `application/scripts/253_launch_joint_exqdesn_phase178_m0_ranking.sh`
- `application/scripts/254_prepare_joint_exqdesn_phase179_protected_confirmation.R`
- `application/scripts/255_check_joint_exqdesn_phase179_protected_confirmation.R`
- `application/scripts/256_launch_joint_exqdesn_phase179_protected_confirmation.sh`
- `application/scripts/257_prepare_joint_exqdesn_phase179_article_confirmation.R`
- `application/scripts/258_check_joint_exqdesn_phase179_article_confirmation.R`
- `application/scripts/259_launch_joint_exqdesn_phase179_article_confirmation.sh`
- `application/scripts/260_build_joint_exqdesn_phase180_recovery_handoff.R`
- `application/scripts/261_freeze_joint_qdesn_post_phase178_dgp_score_contract.R`
- `application/scripts/262_audit_joint_qdesn_post_phase178_dgp_scores.R`
- `application/scripts/263_check_joint_qdesn_post_phase178_dgp_scores.R`
- `application/scripts/264_prepare_joint_qdesn_phase179_dgp_score_confirmation.R`
- `application/scripts/265_check_joint_qdesn_phase179_dgp_score_confirmation.R`
- `application/scripts/266_launch_joint_qdesn_phase179_dgp_score_confirmation.sh`
- `application/scripts/267_freeze_joint_qdesn_phase179_dgp_score_closeout.R`
- `application/scripts/_joint_exqdesn_cpu_queue.sh`
- `application/scripts/_joint_exqdesn_phase176_180_bootstrap.R`
- `application/tests/test_joint_exqdesn_cpu_queue.sh`
- `application/tests/test_joint_exqdesn_phase176_180_post_m0_recovery.R`
- `application/tests/test_joint_qdesn_phase179_dgp_score_confirmation.R`
- `application/tests/test_joint_qdesn_post_phase178_dgp_integrated_acrps.R`
- `docs/implementation_notes/joint_exqdesn_phase176_180_post_m0_recovery_20260813.md`
- `docs/implementation_notes/joint_exqdesn_phase178_integration_handoff_20260819.md`
- `docs/implementation_notes/joint_exqdesn_phase178_post_m0_ranking_closeout_20260819.md`
- `docs/implementation_notes/joint_qdesn_phase179_case_specific_dgp_score_confirmation_20260819.md`
- `docs/implementation_notes/joint_qdesn_phase179_phase180_unified_score_closeout_plan_20260824.md`
- `docs/implementation_notes/joint_qdesn_post_phase178_dgp_integrated_score_audit_20260819.md`
- `docs/implementation_notes/joint_qdesn_post_phase178_dgp_score_integration_handoff_20260819.md`
- this handoff document.

No PriceFM, GloFAS, unrelated single-quantile QDESN, manuscript, bibliography,
table, figure, PDF, `main`, or Overleaf file is changed.

## Production Run and Result

Run tag:
`joint_qdesn_phase179_dgp_score_confirmation_20260819`.

Completion:

- 384/384 chain workers complete;
- 0 worker failures;
- 24/24 candidate-replicate cases complete;
- 5/5 target scenario-readout cells decided;
- 3 nonparity controls promoted;
- 2 cells retain parity;
- 0 contract crossings;
- 23 score functionals pass and 1 is review-level;
- no Phase179 process or tmux session remains active.

The promoted controls are:

- independent normal bridge: `tau0_upper`, `tau0 = 0.9975`, `zeta2 = 16`,
  alpha prior SD `0.75`;
- independent regime shift: `tau0_lower`, `tau0 = 0.3350`, `zeta2 = 32`,
  alpha prior SD `1.25`;
- joint regime shift: `tau0_lower`, `tau0 = 0.1005`, `zeta2 = 64`, alpha
  prior SD `1.00`.

Independent Laplace bridge and independent persistent heavy tail retain parity.
No global specification is selected.

Gamma and sigma mixing are healthy under M0. The remaining review is driven by
alpha/intercept and trend mixing, raw crossing rates up to about 5.35%, and one
review-level score functional. Every scored monotone contract remains finite
and noncrossing. Total worker computation is approximately 4,237 core-hours.

## Frozen Artifacts and Hashes

All paths are under the authoritative runtime cache:
`/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache`.

| Artifact | Size | Manifest SHA-256 |
|---|---:|---|
| `joint_qdesn_phase179_dgp_score_selection_freeze_20260819` | 124 KiB | `bfec8b34f855fe5a8732d597cc5a7283d52aa509062ff1814dd44fc6ed7f4621` |
| `joint_qdesn_phase179_dgp_score_confirmation_freeze_20260819` | 2.6 MiB | `dc1cf81d89715ec5f693c3b9089366b0a2ae6f98d41a851ec650be220e94a13c` |
| `joint_qdesn_phase179_dgp_score_confirmation_20260819` | 992 MiB | worker manifests retained |
| `joint_qdesn_phase179_dgp_score_confirmation_20260819_orchestration` | 3.1 MiB | completion metadata retained |
| `joint_qdesn_phase179_dgp_score_confirmation_audit_20260819` | 36 MiB | `fd9c04316c8fff7f943212a4b4c043b2a5edf32267eedbe2636db3d45f1d73ef` |
| `joint_qdesn_phase179_dgp_score_confirmation_closeout_20260824` | 68 KiB | `db0f35483b479c0e15ac21dbe4127612cff4f640a333e9873f557573b3418675` |

The final audit verifies 25/25 files. The closeout verifies 10/10 files and its
provenance records the committed code HEAD
`ff10d39027a6ed5c6257a6bff167b83ee8e220d5`.

## Balanced Source Completeness

The Phase174 article authority contains exactly 32 rows, eight for each of four
model/readout combinations.

- Phase172 retains and verifies all 16 exAL posterior-draw cells and all 128
  worker manifests.
- Phase154 verifies both AL source manifests but retains no posterior-draw
  tables for its 16 AL cells.
- The final 32-row packet therefore reuses verified exAL draws, replaces the
  three promoted exAL cells after matched article-fixture evaluation, and
  reruns only the 16 AL cells needed for posterior score intervals.

## Verification

Passed:

- `Rscript application/tests/test_joint_qdesn_phase179_dgp_score_confirmation.R`
- `Rscript application/tests/test_joint_qdesn_post_phase178_dgp_integrated_acrps.R`
- `Rscript application/tests/test_joint_exqdesn_phase176_180_post_m0_recovery.R`
- `bash application/tests/test_joint_exqdesn_cpu_queue.sh`
- `Rscript application/tests/test_joint_exqdesn_exact_structured_inference.R`
- `Rscript application/tests/test_joint_exqdesn_inference_dispatch.R`
- `Rscript application/tests/test_joint_exqdesn_phase164_166_orchestration.R`
- `Rscript application/tests/test_joint_exqdesn_phase170_default_promotion.R`
- `Rscript application/tests/test_joint_exqdesn_phase171_175_article_confirmation.R`
- `Rscript application/tests/test_joint_qdesn_article_validation_assets.R`
- `Rscript application/tests/test_joint_qdesn_phase155_article_promotion.R`
- source parsing for script 267;
- `git diff --check`;
- production closeout manifest verification, 10/10 pass.

The Phase155 test used temporary read-only links to the retained Phase150,
Phase153, and Phase154 cache fixtures; all links were removed immediately. No
TeX compile was run because this branch modifies no article-facing file.

## Article-Safe Publication Set

There are no manuscript, table, figure, caption, bibliography, or PDF changes
to publish from this branch. The implementation notes are scientific
reproducibility records for integration review, not a Phase180 article packet.

## Runtime Exclusions

Keep the following ignored and out of Git:

- all Phase178 freezes, workers, checkpoints, audits, and score workspaces;
- `application/cache/joint_qdesn_phase179_dgp_score_selection_freeze_20260819/`;
- `application/cache/joint_qdesn_phase179_dgp_score_confirmation_freeze_20260819/`;
- `application/cache/joint_qdesn_phase179_dgp_score_confirmation_20260819/`;
- `application/cache/joint_qdesn_phase179_dgp_score_confirmation_20260819_orchestration/`;
- `application/cache/joint_qdesn_phase179_dgp_score_confirmation_audit_20260819/`;
- `application/cache/joint_qdesn_phase179_dgp_score_confirmation_audit_20260819_work/`;
- `application/cache/joint_qdesn_phase179_dgp_score_confirmation_closeout_20260824/`;
- ignored launch logs and local planning documents.

These are authoritative reproducibility sources for the next stage and should
not be cleaned until the balanced 32-row packet is frozen.

## Risks and Required Integration Order

1. The branch is substantially behind `origin/main`; the integration
   coordinator must merge and test it rather than launching from this worktree.
2. The legacy scripts 257--260 are MAE-centered and must not be used unchanged
   for the DGP-score article workflow.
3. The three gains are small. They are promoted under the frozen any-gain rule,
   not described as broad practical dominance.
4. Scalar alpha/trend mixing and raw crossings remain review evidence.
5. The 16 AL cells require new retained draws before a 32-row posterior-score
   table can be claimed.
6. Dense 19-level fitting remains a separate later study.

Required order:

1. integrate this dedicated branch through the integration coordinator;
2. create a new dedicated JOINT branch from the integrated latest `main`;
3. freeze and run the 96-worker matched article-fixture confirmation for the
   three promoted challenger/parity pairs;
4. freeze and run the 128-worker AL draw-completion campaign;
5. build and verify the 32-row DGP-integrated score packet;
6. stage Phase180 article assets for integration review;
7. consider the separate 19-level campaign only afterward.

`READY_FOR_INTEGRATION`
