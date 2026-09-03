# Joint Post-Phase178 DGP Score Integration Handoff

Date: 2026-08-19

Status: `READY_FOR_INTEGRATION` for the Phase178 prerequisite implementation,
original-contract closeout, and separately frozen current-grid DGP-integrated
score audit. Phase179 sampling, Phase180 article promotion, manuscript changes,
and 19-level dense-grid fitting are explicitly out of scope.

## Identity

- Scientific lane: JOINT QDESN post-Phase178 DGP-integrated finite-grid score.
- Transcript:
  `/home/jaguir26/.codex/sessions/2026/08/18/rollout-2026-08-18T20-37-39-01a01773-ca48-7b52-a4bd-f848be446d74.jsonl`.
- Worktree:
  `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_postscore_20260819`.
- Branch: `work/joint-qdesn-post-phase178-dgp-score-20260819`.
- Upstream:
  `origin/work/joint-qdesn-post-phase178-dgp-score-20260819`.
- Scientific score-closeout content HEAD:
  `277a725a3febb3e4e0750049cd89a8088432c292`.
- This handoff and final manifest-digest correction are the next task-owned
  commit after that content HEAD. Verify the containing branch tip with
  `git rev-parse HEAD` during integration.
- Merge base with `origin/main`:
  `9559e354e83f0edaf82e3add4c590dbdc378a64e`.

Unique commits through the scientific content HEAD, oldest first:

1. `8d3045374703f0a771c275d051f507e8a53f08ef` Add post-M0 case-specific exQDESN recovery workflow.
2. `33c07618c55525c84f6aa67b8c232b7115eb0e64` Make joint exQDESN worker scheduling completion-aware.
3. `14e48eaa7773b9dd1928d3a12f35fcd28f58a460` Parse joint exQDESN worker plans by schema.
4. `2c6776e0ffe2de9185a9dc2d9b8a6bdecefc98c8` Document Phase178 production M0 ranking launch.
5. `6d90e3cb1bbe6568e59cee2b2088aadf35aff2d1` Fix Phase178 M0 design identifier contract.
6. `a97f09b5287346308c5a29f19257dd4370fb1c2a` Close Phase178 exact-M0 ranking.
7. `1fbd694e788ad7653a058e2125cea1e216846fa1` Add Phase178 integration handoff.
8. `e69e349faf7dc9d208bf310deae281bf46c0351b` Add post-Phase178 DGP score audit.
9. `277a725a3febb3e4e0750049cd89a8088432c292` Close post-Phase178 DGP score audit.

The first seven commits are audited prerequisite patches cherry-picked onto
the latest `origin/main` available when this branch was created. The last two
commits are unique to the score stage.

## Changed Files

Task-owned tracked files relative to the merge base are:

- `application/R/joint_exqdesn_phase176_180_post_m0_recovery.R`
- `application/R/joint_qdesn_dgp_integrated_acrps.R`
- `application/config/joint_exqdesn_phase176_180_post_m0_recovery_policy_v1.csv`
- `application/config/joint_exqdesn_phase178_case_specific_neighborhood_v1.csv`
- `application/config/joint_exqdesn_phase178_post_m0_compute_policy_v1.csv`
- `application/config/joint_exqdesn_phase178_prior_screen_authority_v1.csv`
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
- `application/scripts/_joint_exqdesn_cpu_queue.sh`
- `application/scripts/_joint_exqdesn_phase176_180_bootstrap.R`
- `application/tests/test_joint_exqdesn_cpu_queue.sh`
- `application/tests/test_joint_exqdesn_phase176_180_post_m0_recovery.R`
- `application/tests/test_joint_qdesn_post_phase178_dgp_integrated_acrps.R`
- `docs/implementation_notes/joint_exqdesn_phase176_180_post_m0_recovery_20260813.md`
- `docs/implementation_notes/joint_exqdesn_phase178_post_m0_ranking_closeout_20260819.md`
- `docs/implementation_notes/joint_exqdesn_phase178_integration_handoff_20260819.md`
- `docs/implementation_notes/joint_qdesn_post_phase178_dgp_integrated_score_audit_20260819.md`
- `docs/implementation_notes/joint_qdesn_post_phase178_dgp_score_integration_handoff_20260819.md`

No PriceFM, GloFAS, unrelated QDESN, manuscript, bibliography, figure, table,
PDF, `main`, or Overleaf file is modified.

## Frozen Score Contract

- Contract directory:
  `application/cache/joint_qdesn_post_phase178_dgp_score_contract_20260819`.
- Contract manifest: 9/9 entries pass size and SHA-256 verification.
- Contract manifest SHA-256:
  `51e5ee7b875e9df3fefe9ae35ecc09f761b5ee8312c2416af64674eb6da5f6c7`.
- Grid: `(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)`.
- Trapezoidal weights on `2 rho_tau`:
  `(0.025, 0.10, 0.20, 0.25, 0.20, 0.10, 0.025)`.
- Weight sum: 0.90; no renormalization.
- Primary metric: `dgp_integrated_acrps`.
- Primary posterior report: mean and equal-tailed 95% credible interval.
- Canonical posterior-mean monotone action and posterior median are retained as
  sensitivity summaries.
- Joint draws preserve cross-tau identity; independent draws use the frozen
  seeded, chain-balanced product-posterior coupling.

The contract was frozen before protected DGP-integrated scores were computed.
Its provenance intentionally points to the pre-score implementation commit
`e69e349faf7dc9d208bf310deae281bf46c0351b`.

## Frozen Production Evidence

- Audit directory:
  `application/cache/joint_qdesn_post_phase178_dgp_score_audit_20260819`.
- Audit manifest: 35/35 entries pass size and SHA-256 verification.
- Audit manifest SHA-256:
  `d4d8d126583182736bf0c66bf1dab6b283973f17e70faa4740af163514416a11`.
- Audit provenance code HEAD:
  `277a725a3febb3e4e0750049cd89a8088432c292`.
- Phase178 workers inherited: 180/180 complete, zero failures.
- Source-complete candidate-replicates: 45/45.
- Case-specific decisions: 5/5.
- Posterior score draws: 180,000.
- Candidate-minus-parity contrast draws: 120,000.
- Available joint-minus-independent contrast draws: 36,000.
- Formula checks: 60/60 analytic and Monte Carlo pass.
- Oracle-minimum checks: 35/35 pass.
- Forecast previsibility checks: 45/45 pass.
- Frozen source-manifest groups: 3/3 pass.
- Contract crossings: zero in all 45 cells.
- Independent coupling sensitivity: pass in every applicable cell.
- Score-functional diagnostics: 28 pass, 17 review.
- Raw crossing rates: 0.01194 to 0.04395.
- Mean normalized monotone adjustment: 0.00076 to 0.00484.
- Final assessment: `review`, with no implementation failure.

The generated audit is about 21 MiB, its resumable per-cell work directory is
about 16 MiB, and the frozen contract is about 52 KiB. Phase178 retained draws,
worker manifests, fixtures, and ranking audit remain under retention hold for
Phase179 reproducibility.

## Scientific Decision

The original Phase178 forecast-oracle-MAE ranking remains immutable and is
stored separately. It selected three non-parity templates and two parity
templates.

The post-Phase178 article-action decision retains parity in all five targeted
cells. Challenger-to-parity DGP-integrated score ratios range from 0.99940 to
1.00123, entirely within the frozen 0.5% practical near-tie margin. No
challenger achieves practical superiority on any protected replicate, and the
median posterior practical-superiority probabilities range from 0.172 to
0.322, far below the required 0.95.

The next scientific stage is therefore not the legacy MAE-selected Phase179
launcher. A new Phase179 freeze should consume the five parity rows in
`phase179_selected_templates.csv`, retain all review diagnostics, assign fresh
protected DGP and MCMC seeds, and compute the exact parity-only worker count.
No Phase179 worker should launch until that freeze is reviewed.

## Verification

The following checks passed on the score-closeout content HEAD:

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
- source parsing for the score module and scripts 261-263;
- `Rscript application/scripts/263_check_joint_qdesn_post_phase178_dgp_scores.R --cache-root /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache`;
- `git diff --check`.

The Phase155 test used temporary read-only symlinks to the retained ignored
Phase150/153/154 cache fixtures and removed them immediately afterward. No
runtime source was copied or modified. No manuscript compile is required
because this branch changes no TeX, table, figure, bibliography, or PDF.

## Article-Safe Publication Set

There are no article-facing tables, figures, captions, or manuscript changes
to publish from this stage. The two post-score implementation/handoff notes
are reproducibility documentation only. The 32-row article packet is explicitly
`source_incomplete` at draw level and must not be fabricated from Phase178's
targeted five-cell evidence.

## Runtime Exclusions

Keep these generated paths ignored and out of Git:

- `application/cache/joint_qdesn_post_phase178_dgp_score_contract_20260819/`
- `application/cache/joint_qdesn_post_phase178_dgp_score_audit_20260819/`
- `application/cache/joint_qdesn_post_phase178_dgp_score_audit_20260819_work/`
- all retained Phase178 chain/checkpoint, fixture, freeze, audit, and
  orchestration directories listed in the Phase178 handoff;
- related ignored logs and local planning documents.

The temporary superseded pre-provenance audit packet was removed after the
committed-code audit verified. No authoritative or unrelated runtime output
was deleted.

## Risks and Integration Order

Remaining risks are scientific, not implementation defects:

- 17/45 score-functionals remain review-level, mainly because bulk ESS is
  below 400;
- all 45 raw-crossing audits exceed the conservative 0.01 review rate, despite
  zero contract crossings and small normalized adjustments;
- Phase178 is targeted evidence and supplies zero of the complete 32
  article-fixture scenario-model rows at the required draw level;
- a parity-only Phase179 still needs a new seed/worker freeze and fresh
  confirmation;
- dense-grid fitting remains deferred.

Recommended integration handling:

1. This branch subsumes the audited Phase178 prerequisite patches. If those
   patches are not already in `main`, integrate this branch directly and do not
   separately merge the older Phase178 branch with duplicate patch content.
2. If the older Phase178 branch has already been integrated, port only the two
   post-score scientific commits plus this handoff, verifying the bootstrap
   source line and patch equivalence.
3. Create the new parity-only Phase179 preparation on a fresh dedicated JOINT
   branch after integration.
4. Do not merge or publish article assets until Phase179 and the complete
   Phase180 packet pass their own gates.
5. Keep the 19-level dense-grid study separate and later.

`READY_FOR_INTEGRATION`
