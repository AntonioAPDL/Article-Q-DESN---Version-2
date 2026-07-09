# Full Manuscript Style Audit

Date: 2026-05-10

## Manuscript Type

Bayesian methodology article for conditional quantile forecasting with fixed
deep echo state network features, asymmetric working likelihoods, shrinkage
priors, and MCMC and VB computation.

## Main Inferential Target

The primary target is the conditional \(p_0\)-quantile represented by a
Bayesian readout \(\mu_t=\mathbf{x}_t^\top\boldsymbol\beta\), conditional on
the generated reservoir and washout. Multi-quantile synthesis is a
post-processing tool for a fitted grid of quantile levels, not a joint
multi-quantile posterior model.

## Style Alignment

- The current scope is now mostly aligned with the preferred framing:
  Bayesian quantile readouts for fixed DESN features.
- The main article clearly distinguishes fixed reservoir features from the
  Bayesian readout model.
- The exAL and GAL likelihood is described as a working likelihood, with a
  needed caveat about calibration under misspecification.
- Simulation interpretation is mostly design-specific and avoids broad
  claims.

## Issues Requiring Revision

- The abstract needs a clearer limitation/gap sentence before introducing
  Q--DESN.
- The introduction should start from conditional quantile forecasting rather
  than the phrase "This paper considers."
- Visible draft TODO notes should not appear in a clean PDF; they can remain
  in the source if hidden by the draft-note toggle.
- Several paragraphs still use broad or slightly promotional wording:
  "strongest RMSE values," "computational separation is substantial,"
  "strong global-local shrinkage," and "enforces strong shrinkage."
- The exAL section says AL restrictions can hinder tail calibration; this
  should be qualified because calibration is an empirical property, not a
  direct consequence of the likelihood specification.
- The DESN and prior sections contain long, dense paragraphs that can be
  improved with better verbal setup and line-level formatting without
  changing the mathematics.
- The planned data application appears as a placeholder with an empty
  subsection; it should read as a coherent planned climate and environmental
  application section.
- The discussion future-work paragraph is too compressed and should separate
  quantile modeling, reservoir sensitivity, VB diagnostics, and the planned
  application.

## Recommended Revision Plan

1. Hide draft notes in the compiled PDF while preserving source TODOs.
2. Revise the abstract to follow problem, limitation, construction,
   computation, synthesis, and qualified evidence.
3. Tighten the introduction opening and contribution paragraph.
4. Replace broad or promotional language with metric-specific claims.
5. Improve wording around working-likelihood calibration and model-based
   forecast summaries.
6. Convert the data placeholder into a concise planned application section.
7. Update the discussion to match the final scope and remaining draft status.
8. Rebuild the article and supplement, scan logs, remove artifacts, and record
   the pass in the revision log.
