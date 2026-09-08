# Q--DESN editorial compression

## Status and authority

| Field | Value |
|---|---|
| Date | 2026-09-08 |
| Status | `VALIDATED_FOR_INTEGRATION` |
| Source branch | `work/qdesn-editorial-compression-v1-20260908` |
| Starting authority | `origin/main` at `597096492651cc56bff04a365f16fe99a2c5908f` |
| Scientific computations | No model was fitted or rerun |
| Numerical results | Unchanged |
| Deferred correction | `joint_qvp_rhs_deferred_rerun_register_20260908.md` |

This revision implements the audited editorial-compression plan after the
regularized-horseshoe global-scale update was corrected in the source code.
The affected scientific analyses are deliberately not rerun here.  Their
replacement is a mandatory task before final project closeout and is recorded
in the deferred-rerun register.  Until then, the existing numerical results
remain provisional with respect to that correction.

## Editorial result

Clean bibliography-aware builds give the following reproducible comparison.
Raw word counts include LaTeX commands and mathematics and are therefore used
only as a source-level comparison.

| Document | Baseline pages | Revised pages | Baseline raw words | Revised raw words |
|---|---:|---:|---:|---:|
| Main article | 43 | 21 | 11,330 | 5,413 |
| Supplement | 53 | 45 | 10,713 | 8,979 |
| Combined | 96 | 66 | 22,043 | 14,392 |

The main article is shorter than the plan's preliminary 31--34-page range.
The reduction was accepted after visual and contract review because it arose
from removing repeated derivations, repeated definitions, a detached
literature catalogue, and table transcription.  It did not use smaller type,
narrower margins, reduced line spacing, shortened numerical precision, or
deletion of the principal empirical evidence.  The main article remains
self-contained at the level needed to identify the models, posterior targets,
forecast estimands, scoring rules, selection procedure, and limitations.  The
supplement remains at the upper end of its planned 41--45-page range because it
retains the full mathematical and numerical record.

## Structural changes

The revision:

1. integrates the closest literature with the introduction and removes the
   separate survey-style catalogue;
2. presents one compact fixed-feature Q--DESN formulation in the main article,
   including the DESN recursion, AL/exAL working-likelihood interpretation,
   ridge and regularized-horseshoe priors, and the joint adjacent-difference
   model;
3. moves complete posterior products, block calculations, full conditional
   updates, and extended forecasting calculations to the supplement;
4. keeps check loss, integrated-check-loss CRPS, finite-grid aCRPS, monotone
   reporting, and the distinction between quantile-location and response
   simulation explicit in the main article;
5. moves the sequential-initialization diagram, independent fitting-RMSE
   figure, joint fitting-recovery figure, and exact joint score table to the
   supplement;
6. retains the independent forecast-MAE and forecast-check-loss figures and
   the joint forecast-score figure in the main article;
7. places MCMC and variational single-quantile tables in adjacent reading order
   by data-generating family.  They remain separate tables because their
   case-specific selected specifications need not be identical, so a common
   two-panel table could incorrectly suggest a controlled approximation-error
   comparison;
8. consolidates the GloFAS derivation into a compact source-specific model and
   a separately identified latent-future-path extension; and
9. shortens the GloFAS and PriceFM accounts while retaining their denominators,
   retrospective information sets, selection qualifications, undercoverage,
   and heterogeneous results.

The new inclusion wrappers permit each moved figure to appear in exactly one
document without modifying its plotted PDF or source data.  The article-only
file manifest includes every new wrapper.

## Protected scientific statements

The following evidence remains explicit:

- all 16 joint-minus-independent score intervals contain zero;
- the joint posterior-score diagnostics comprise 21 passes and 11 results
  requiring cautious interpretation;
- raw crossing counts are 1 for joint AL Q--DESN, 25 for independent AL
  Q--DESN, and 0 for both exAL models, with zero crossings after the stated
  monotone transformation;
- all independent-validation warning marks and the five-chain sensitivity
  analysis remain in the supplement;
- GloFAS remains a single-origin retrospective study with nominal 90 percent
  coverage of 0.357 for Q--DESN and 0.000 for raw GloFAS;
- PriceFM retains 114 matched region--fold comparisons, 72 lead-specific
  comparisons, the 56-case validation comparison, all 12 test-dependent
  substitutions, and the adverse 6.704 versus 6.608 validation-selected test
  comparison; and
- AL and exAL remain working likelihoods, the joint construction remains an
  untempered composite posterior, and adjacent-difference shrinkage is not
  described as a noncrossing constraint.

No numerical table body, CSV, macro value, figure PDF, forecast origin,
quantile grid, selected specification, score, interval endpoint, or diagnostic
warning was changed.

## Validation

The following checks passed on the revised source:

```text
application/tests/test_qdesn_corrected_reaudit_contracts.R
application/tests/test_rhs_global_scale_reference.R
scripts/check_joint_qdesn_phase181_article_projection.R
scripts/check_joint_qdesn_phase181_interval_figures.R
scripts/check_independent_validation_dgp_oracle_figures_v14.R
scripts/check_independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.R
git diff --check
```

The DGP-oracle checker reports 145 checks, the rolling-state checker reports
329 checks, the joint article checker verifies 32 score rows and 16 contrasts,
and the joint interval checker verifies 64 interval rows.  The corresponding
manifest hashes for the checker and the two manuscript sources were refreshed.

Both manuscripts were built with the repository's documented sequence:

```text
pdflatex -interaction=nonstopmode -halt-on-error <document>.tex
bibtex <document>
pdflatex -interaction=nonstopmode -halt-on-error <document>.tex
pdflatex -interaction=nonstopmode -halt-on-error <document>.tex
pdflatex -interaction=nonstopmode -halt-on-error <document>.tex
```

The final logs contain no undefined citations or references, multiply defined
labels, overfull or underfull boxes, or LaTeX errors.  The rendered documents
were inspected at manuscript size, including the paired numerical tables and
the moved independent and joint figures.

The combined `application/tests/run_tests.R` harness passes through the
corrected RHS global-scale test and then stops in
`test_joint_qvp_qdesn_synthetic_artifacts.R` when data frames with different
column counts are combined.  A clean detached worktree at the unchanged
starting `origin/main` commit reproduces the same failure.  The editorial
branch changes no file below `application/R` or `application/tests`; this is a
documented baseline-harness boundary, not a regression introduced by the
compression.

## Deferred scientific boundary

The editorial revision does not authorize continued use of affected RHS
results at final closeout.  Before the project is declared complete, the owner
must execute every applicable item in
`joint_qvp_rhs_deferred_rerun_register_20260908.md`, freeze corrected outputs,
regenerate any affected article assets, and revalidate the resulting
manuscripts.  No job was launched, stopped, or modified during this revision.
