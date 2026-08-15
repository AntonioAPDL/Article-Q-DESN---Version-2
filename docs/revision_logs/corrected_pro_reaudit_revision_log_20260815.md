# Corrected PRO Reaudit Revision Log

Date: 2026-08-15
Branch: `integration/corrected-pro-reader-revision-20260815`
Starting commit: `60fe289e8586078a9cc6c939ee3877a498acfadf`
Starting tree: `1a308c1a4ba9fda1542d0cb4d2b3888f9dc47494`

## Baseline

The branch starts from the recovered 1,990-file Article-v2 authority. A fresh
fetch confirmed local `main` and `origin/main` were synchronized before the
integration worktree was created. The corrected PRO deliverables were verified
by SHA-256 in ignored local trackers.

No simulation, application campaign, MCMC chain, VB refit, GloFAS run, PriceFM
run, or Overleaf publication was launched for this revision.

## Author Decision

The implementation uses the readout-focused route recommended by the corrected
audit. Forecast-origin marginal predictive quantiles remain deferred scientific
work. The article is revised around Bayesian quantile readouts on fixed DESN
features.

## Change Ledger

Entries below record the implemented claim groups. Proposed new scientific
work remains explicitly deferred; this pass corrects source, terminology,
evidence scope, documentation, and packaging without launching new campaigns.

| Claim group | Status | Files | Verification |
|---|---|---|---|
| TGT/SYN | source corrected | main, supplement, score code, semantic tests | corrected contract test; isolated TeX builds; source-bundle build |
| JNT/SIM | scoped to frozen evidence | main, supplement, joint tables, generators | joint focused suite; article-asset test; independent train-only check |
| EXA/VB | source corrected and scoped | supplement, main, semantic tests | exact structured inference test; corrected contract test |
| GLO | source corrected and scoped | main, supplement, output registry, current tables, docs | GloFAS context test; corrected contract test; refreshed manifest hashes |
| PFM | scoped to retrospective replay | main, supplement, docs | corrected contract test; source review; pytest unavailable in environment |
| REP/WRT | revised and packaged | README/docs, arXiv builder, main.pdf, claim ledger | isolated builds; manifest-closure check; source-bundle compile; `git diff --check` |

## Protected Runtime Boundary

Read-only process audit showed active GloFAS, PriceFM, and JOINT scientific
runs. This revision must not touch their worktrees, caches, tmux sessions,
output roots, or old-repository runtime roots.

## Verification Summary

- Corrected semantic contract test:
  `Rscript application/tests/test_qdesn_corrected_reaudit_contracts.R` passed.
- Joint focused tests passed:
  `test_joint_exqdesn_phase171_175_article_confirmation.R`,
  `test_joint_exqdesn_inference_dispatch.R`,
  `test_joint_exqdesn_phase167_169_mcmc_method_selection.R`,
  `test_joint_exqdesn_phase169r_recovery.R`, and
  `test_joint_exqdesn_phase170_default_promotion.R`.
- Additional focused tests passed:
  `test_joint_qdesn_article_validation_assets.R`,
  `test_joint_exqdesn_exact_structured_inference.R`,
  `scripts/check_independent_validation_trainonly_article.R`, and
  `application/tests/test_glofas_context_figures.R`.
- Known unavailable checks were not faked:
  `test_joint_qdesn_phase155_article_promotion.R` requires the compacted legacy
  Phase154 cache, and PriceFM pytest checks require a Python environment with
  `pytest` installed.
- Isolated TeX builds passed for both entry points: `main.tex` produced a
  43-page PDF and `qdesn-supplement.tex` produced a 39-page PDF.
- The recorder-derived closure was covered by `overleaf/article_files.txt`;
  `refs.bib` remains an intentional source-portability entry.
- The manifest-driven arXiv/source bundle built successfully, passed its
  SHA-256 manifest, and compiled both entry points in isolation.

## Deferred Scientific Work

The seven corrected-PRO rows classified as proposed new scientific work remain
outside this source-correction pass. They include marginal response-level
posterior-predictive construction, new coupling/tempering studies, broader
reservoir-root simulations, multi-origin GloFAS validation, and additional
PriceFM uncertainty analyses.
