# JOINT Laplace architecture article-fixture confirmation

Date: 2026-10-08

## Audited decision

The completed quantile-aware architecture campaign exhausted its declared
screen and confirmation stages: 180/180 tracked units and 96/96 MCMC chains
completed with zero failures. All exact exAL chains used
`M0_v_collapsed_support_logit`; all frozen and closeout manifests verified.
The selected `arch_02` reduced mean fresh-seed score by 36.50% for joint AL and
20.08% for joint exAL relative to the current `arch_00` backbone. Mean joint
score-interval widths fell by 95.41% and 94.08%, respectively. This addresses
the Laplace overspread symptom without another prior, sampler, or broad DESN
screen.

The result remains fresh-seed evidence rather than article authority. The
optimal next experiment is therefore one matched protected-fixture
confirmation, not another search. The preselected candidate and baseline are
both refit so any difference cannot be attributed to historical code paths,
MCMC budgets, seeds, score coupling, or numerical fixes.

## Frozen scientific contract

- Scope: Laplace Bridge only.
- Architectures: current `arch_00` and preselected `arch_02`; no alternatives.
- Protected fixture: exact archived article fixture, seed `202607202`, SHA-256
  `53e33187...ceb01a`.
- Oracle: exact archived 4,096-path Laplace bank, SHA-256
  `f1df687c...e520e`.
- Baseline parity: the rebuilt `arch_00` design must be byte-equivalent in all
  scientific fields to the archived article design.
- Models: joint/independent crossed with AL/exAL, one shared architecture and
  RHS `tau0` within each architecture.
- Initialization: Gaussian RHS, median-outward independent AL, paired
  independent exAL, then joint AL/exAL.
- MCMC: five chains per model cell; AL 4,000/1,000/thin 4; exAL
  8,000/2,000/thin 4; exactly 40 chains.
- exAL: exact M0 only; structured-VB initialization only.
- Forecast and score: unchanged teacher-forced origins, recursive 30-step
  paths, posterior-mean reservoir state integration, seven-level
  DGP-integrated finite-grid aCRPS.
- Hard validity: complete manifests, finite scores, zero contract crossings,
  and no gross predictive-score instability.
- Mixing: review-level unless predictive behavior is pathological.
- Confirmation rule: any strict mean improvement is meaningful, but the
  shared candidate confirms only if both joint means and the equal-weight
  four-model mean improve over the matched baseline.
- The article fixture evaluates a preselected specification; it cannot tune or
  select another architecture.
- No article, `main`, Overleaf, PriceFM, GloFAS, Phase182, or historical JOINT
  artifact is modified.

## Implementation surface

- `application/config/joint_qdesn_laplace_architecture_article_confirmation_contract_v1.csv`
- `application/R/joint_qdesn_laplace_architecture_article_confirmation.R`
- `application/scripts/_joint_qdesn_laplace_architecture_article_confirmation_bootstrap.R`
- `application/scripts/joint_qdesn_laplace_architecture_article_confirmation.R`
- `application/scripts/launch_joint_qdesn_laplace_architecture_article_confirmation.sh`
- `application/tests/test_joint_qdesn_laplace_architecture_article_confirmation.R`

Preparation verifies and copies the architecture decision, article fixture,
baseline design, and oracle bank into a self-contained ignored runtime. It
then freezes 2 datasets, 2 joint-VB warmups, 8 score cells, and 40 independently
seeded MCMC chains. Workers cannot begin until the source hashes, protected
fixture status, current score-packet status, plan manifest, Git state, disk
gate, physical-core uniqueness, and CPU-affinity gate pass.

Finalization writes the complete eight-cell score packet, matched
candidate-versus-baseline table, candidate joint-versus-independent table,
decision receipt, comparison PDF, hashes, and integration handoff. It never
edits an article asset. A coordinator must review and integrate the result
before any authoritative table or narrative changes.

## Checklist

- [x] Audit the completed architecture campaign and verify all source hashes.
- [x] Reject another broad screen, prior screen, and sampler experiment.
- [x] Bind the exact protected fixture and DGP oracle bank.
- [x] Freeze matched five-chain budgets and the no-selection rule.
- [x] Implement isolated preparation, workers, health, closeout, and launcher.
- [ ] Pass focused unit, shell, source-gate, and baseline-parity tests.
- [ ] Commit and push the dedicated JOINT branch.
- [ ] Mirror the exact branch HEAD into a clean Jerez execution worktree.
- [ ] Pass fresh capacity preflight and launch with at most 15 physical cores.
- [ ] Complete 2/2 datasets, 2/2 warmups, 40/40 chains, and 8/8 scores.
- [ ] Freeze the result and provide `READY_FOR_INTEGRATION` or
  `NOT_READY_FOR_INTEGRATION` to the coordinator.
