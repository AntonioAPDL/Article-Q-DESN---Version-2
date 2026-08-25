# Joint Phase178 Frozen Integration Handoff

Date: 2026-08-19

Status: `READY_FOR_INTEGRATION` for Phase176-178 implementation and the
original-contract Phase178 closeout. Phase179, Phase180, article promotion, and
the post-Phase178 DGP-integrated score audit are explicitly out of scope.

## Identity

- Scientific lane: JOINT exQDESN Phase176-180 post-M0 recovery.
- Transcript:
  `/home/jaguir26/.codex/sessions/2026/08/18/rollout-2026-08-18T20-37-39-01a01773-ca48-7b52-a4bd-f848be446d74.jsonl`.
- Worktree:
  `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_exqdesn_phase176_180_20260813`.
- Branch: `work/joint-exqdesn-phase176-180-post-m0-recovery-20260813`.
- Upstream:
  `origin/work/joint-exqdesn-phase176-180-post-m0-recovery-20260813`.
- Scientific closeout content HEAD:
  `55947e1584d43f3a5f690aedba042bdd52897f10`.
- This handoff is the next task-owned commit after that content HEAD; verify the
  containing branch tip with `git rev-parse HEAD` during integration.
- Merge base: `3667953e1b9c4e0f5e93112fd0bf1cb3712db5a0`.
- `origin/main` observed before handoff:
  `9559e354e83f0edaf82e3add4c590dbdc378a64e`.

Unique scientific commits through the closeout content HEAD, oldest first:

1. `3df29c6` Add post-M0 case-specific exQDESN recovery workflow.
2. `5953215` Make joint exQDESN worker scheduling completion-aware.
3. `89c2100` Parse joint exQDESN worker plans by schema.
4. `835ef93` Document Phase178 production M0 ranking launch.
5. `51a0b96` Fix Phase178 M0 design identifier contract.
6. `55947e1` Close Phase178 exact-M0 ranking.

## Changed Files

Task-owned tracked files relative to the merge base are:

- `application/R/joint_exqdesn_phase176_180_post_m0_recovery.R`
- `application/config/joint_exqdesn_phase176_180_post_m0_recovery_policy_v1.csv`
- `application/config/joint_exqdesn_phase178_case_specific_neighborhood_v1.csv`
- `application/config/joint_exqdesn_phase178_post_m0_compute_policy_v1.csv`
- `application/config/joint_exqdesn_phase178_prior_screen_authority_v1.csv`
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
- `application/scripts/_joint_exqdesn_cpu_queue.sh`
- `application/scripts/_joint_exqdesn_phase176_180_bootstrap.R`
- `application/tests/test_joint_exqdesn_cpu_queue.sh`
- `application/tests/test_joint_exqdesn_phase176_180_post_m0_recovery.R`
- `docs/implementation_notes/joint_exqdesn_phase176_180_post_m0_recovery_20260813.md`
- `docs/implementation_notes/joint_exqdesn_phase178_post_m0_ranking_closeout_20260819.md`
- `docs/implementation_notes/joint_exqdesn_phase178_integration_handoff_20260819.md`

## Frozen Runtime Evidence

- Run tag: `joint_exqdesn_phase178_post_m0_ranking_20260813`.
- Planned/completed/failed chains: 180/180/0.
- Candidate-replicate cells: 45/45 complete.
- Original target decisions: five scenario/readout cells.
- Original non-parity selections: three.
- Canonical audit:
  `application/cache/joint_exqdesn_phase178_post_m0_ranking_audit_20260813`.
- Canonical manifest SHA-256:
  `3a9c387abfe2a7b5a471da77b1a690fba76bfcf7f1eaad0c21a74764f9ef6848`.
- Ranking-freeze manifest SHA-256:
  `e77a63f66b18a33e10d1950eeff970829a15913fb4a4026ed8c548b9f39dc036`.
- Protected-fixture manifest SHA-256:
  `4f13e37f7acfcdb96b4abf68123934f3088a41c5ebab4ee75e6762beeed1ad2a`.
- Canonical audit entries: 22/22 size and SHA-256 matches.
- Frozen-source verification: 14/14 pass.
- Worker manifest inventory: 180/180 pass.
- Implementation-pass candidate replicates: 45/45.
- Fit/forecast raw crossings: 0/0.
- Fit/forecast contract crossings: 0/0.
- Scalar-mixing status: 45/45 review.
- Chain-partition stability: 95 pass, 85 review.

Storage retained for the next score stage:

- ranking chain/checkpoint results: about 455 MiB;
- canonical audit: about 242 MiB;
- ranking freeze: about 1.9 MiB;
- protected fixtures: about 330 MiB.

The compressed posterior checkpoints are required for the post-Phase178
draw-level score audit and must not be cleaned before that audit is frozen.

## Verification

The following commands passed after closeout documentation was added:

- `Rscript application/tests/test_joint_exqdesn_phase176_180_post_m0_recovery.R`
- `bash application/tests/test_joint_exqdesn_cpu_queue.sh`
- `Rscript application/tests/test_joint_exqdesn_exact_structured_inference.R`
- `Rscript application/tests/test_joint_exqdesn_inference_dispatch.R`
- `Rscript application/tests/test_joint_exqdesn_phase164_166_orchestration.R`
- `Rscript application/tests/test_joint_exqdesn_phase170_default_promotion.R`
- `Rscript application/tests/test_joint_exqdesn_phase171_175_article_confirmation.R`
- `git diff --check`

No manuscript compile is required because this branch does not modify article
TeX, tables, figures, bibliography, or PDFs.

## Article-Safe Publication Set

There is no article table or figure to publish from Phase178. The two tracked
implementation notes may be integrated as scientific provenance. The original
Phase178 selection is not article authority and must not be used to overwrite
the Phase174 packet.

## Runtime Exclusions

Keep the following generated paths ignored and out of Git:

- `application/cache/joint_exqdesn_phase178_post_m0_ranking_20260813/`
- `application/cache/joint_exqdesn_phase178_post_m0_ranking_audit_20260813/`
- `application/cache/joint_exqdesn_phase178_post_m0_ranking_freeze_20260813/`
- `application/cache/joint_exqdesn_phase178_post_m0_protected_fixtures_20260813/`
- `application/cache/joint_exqdesn_phase178_post_m0_ranking_20260813_orchestration/`
- related ignored logs and local tracker documents.

## Risks And Merge Order

Remaining risks are scientific rather than implementation failures:

- all cells have review-level scalar mixing;
- 85/180 partition-stability checks remain review;
- historical MAE-selected challengers are near-tied or sometimes worse on the
  realized finite-grid score;
- the DGP-integrated action score and its posterior uncertainty have not yet
  been computed;
- the existing Phase179 launcher remains MAE-centered and is blocked.

Recommended merge order:

1. integrate this Phase176-178 branch after the Phase174 prerequisite history;
2. create/integrate the separate post-Phase178 score-contract branch;
3. run and freeze the current seven-level DGP-integrated score audit;
4. prepare Phase179 only from the new aCRPS-first decision artifact;
5. defer article promotion and dense-grid fitting until their gates pass.

`READY_FOR_INTEGRATION`
