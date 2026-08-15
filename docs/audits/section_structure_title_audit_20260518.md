# Section Structure and Title Audit, 2026-05-18

## Scope

This audit reviews the manuscript and supplement section names for conventional
Bayesian-statistics presentation, with emphasis on quantile regression, dynamic
forecasting models, MCMC, variational Bayes, simulation design, and application
sections. The goal is reader-facing structure, not technical content revision.
Labels were preserved wherever possible.

## Evidence Base

Local writing standards:

- `Academic_Writing_Style_Profile_v0.2.md`
- `AGENTS_academic_writing_snippet.md`

Local comparison articles and extracted section trees:

- Kozumi and Kobayashi (2011): `Posterior inference`, `Gibbs sampler`,
  `Numerical examples`.
- Goncalves, Migon, and Bastos (2020): `Posterior inference for the DQLM`,
  `Efficient MCMC algorithm`, `Applications`.
- Yang, Wang, and He (2016): `Bayesian quantile regression with AL likelihood`,
  `Computation and properties`, `Numerical studies`, `Discussion`.
- Yan et al. (2025): `Bayesian quantile regression with GAL errors`,
  `Simulation settings`, `Criteria for comparison`, `Results`, `Data examples`.
- Wang and Blei (2013): `Mean-field Variational Inference`,
  `Laplace and Delta Method Variational Inference`, `Empirical Study`,
  `Discussion`.
- McDermott and Wikle (2018): `Methodology`, `Inference and Forecasting`,
  `Simulation and Motivating Examples`, `Discussion`.
- Bonas, Wikle, and Castruccio (2024): `Methodology`,
  `Inference and Forecasting`, `Calibration of the Forecasts`,
  `Simulation Study`, `Application`, `Discussion`.

This local corpus was sufficient for the naming audit; no web lookup was needed.

## Main Manuscript Audit

| Current title | Issue | Recommended title | Decision |
| --- | --- | --- | --- |
| `Introduction` | Conventional. | Keep. | Keep |
| `Related Work` | Unnumbered subsection inside the introduction is acceptable for space. | Keep. | Keep |
| `Notation and Preliminaries` | Conventional bridge before model specification. | Keep. | Keep |
| `Deep Echo State Network (DESN)` | Conventional model component title. | Keep. | Keep |
| `Extended Asymmetric Laplace (exAL)` | Appropriate because exAL is manuscript notation for the quantile-fixed GAL construction. | Keep. | Keep |
| `Model Specification` | Conventional Bayesian model section. | Keep. | Keep |
| `Quantile Deep Echo State Network (Q--DESN)` | Clear model name. | Keep. | Keep |
| `Prior Specification` | Conventional. | Keep. | Keep |
| `Posterior Inference` | Conventional parent section for computation. | Keep. | Keep |
| `Augmented MCMC` | Too implementation-specific; comparison papers use `MCMC algorithm`, `Gibbs sampler`, or `Posterior inference`. | `Markov Chain Monte Carlo` | Required |
| `Mean-field VB--LD` | Too idiosyncratic for a section title; VB--LD should be explained inside the section. | `Variational Bayes` | Required |
| `Forecasting and Multi-Quantile Synthesis` | Combines prediction and an optional post hoc device; title should signal posterior prediction first. | `Posterior Prediction and Quantile Synthesis` | Required |
| `$H$--Step Working-Likelihood Forecasts` | Reads like implementation vocabulary. | `Multi-Step Posterior Prediction` | Required |
| `Optional Multi-Quantile Synthesis` | Correct idea, but `Post Hoc` better communicates that synthesis is outside the fitted likelihood. | `Post Hoc Quantile Synthesis` | Required |
| `Reservoir Diagnostics and Specification Selection` | Good content, but title should emphasize model workflow, not just reservoir internals. | `Model Diagnostics and Reservoir Specification` | Required |
| `Simulation Design` | Appropriate because results are intentionally deferred until authoritative tables exist. | Keep. | Keep |
| `Source Design and Forecast Windows` | `Source design` is internal validation language. | `Data-Generating Processes and Forecast Windows` | Required |
| `Model Grid` | Slightly terse; does not communicate baselines/configurations. | `Competing Methods and Model Configurations` | Required |
| `Criteria for Comparison` | Conventional and matches Yan et al. (2025). | Keep. | Keep |
| `GloFAS Streamflow Forecast Calibration` | Professional, but adding `Application:` aligns with applied-statistics articles. | `Application: GloFAS Streamflow Forecast Calibration` | Required |
| `Discussion` | Correctly deferred until results are complete. | Keep. | Keep |

## Supplement Audit

| Current title | Issue | Recommended title | Decision |
| --- | --- | --- | --- |
| Sentence-case supplement titles | Inconsistent with main article and less polished in PDF bookmarks. | Title case for section/subsection names. | Required |
| `Q--DESN likelihoods, priors, and joint distributions` | `Joint distributions` is broad; the section defines computational posterior targets. | `Q--DESN Likelihoods, Priors, and Posterior Targets` | Required |
| `Complete-data joint distributions` | More precise as posterior targets in this Bayesian supplement. | `Complete-Data Posterior Targets` | Required |
| `MCMC full conditionals` | Conventional but should be title case. | `MCMC Full Conditionals` | Required |
| `Mean-field CAVI and Laplace--Delta VB` | Too much acronym load in a section title. | `Variational Bayes and Laplace--Delta Updates` | Required |
| `Q--DESN CAVI and VB--LD` algorithm | Internal naming. | `Q--DESN Variational Bayes Updates` | Required |
| `Forecasting and multi-quantile synthesis` | Should match main terminology. | `Posterior Prediction and Quantile Synthesis` | Required |
| `GloFAS discrepancy-calibration Q--DESN` | Reads like an implementation variant. | `GloFAS Discrepancy-Calibration Model` | Required |
| `Default RHS readout prior` | `RHS` is acceptable in prose but less polished in heading. | `Default Regularized-Horseshoe Readout Prior` | Required |
| `Mean-field VB and CAVI updates` | Acronym-heavy and inconsistent with main. | `Variational Bayes and CAVI Updates` | Required |
| `Internal checks` | Useful supplement component; title-case only. | `Internal Checks` | Required |

## Revised Main Outline

1. Introduction
2. Notation and Preliminaries
   - Deep Echo State Network (DESN)
   - Extended Asymmetric Laplace (exAL)
3. Model Specification
   - Quantile Deep Echo State Network (Q--DESN)
   - Prior Specification
4. Posterior Inference
   - Markov Chain Monte Carlo
   - Variational Bayes
5. Posterior Prediction and Quantile Synthesis
   - Multi-Step Posterior Prediction
   - Post Hoc Quantile Synthesis
6. Model Diagnostics and Reservoir Specification
7. Simulation Design
   - Data-Generating Processes and Forecast Windows
   - Competing Methods and Model Configurations
   - Criteria for Comparison
8. Application: GloFAS Streamflow Forecast Calibration
9. Discussion

## Revised Supplement Outline

1. Scope and Relation to the Main Article
2. Distributional Conventions
3. DESN Feature Map and Static Readout
4. Q--DESN Likelihoods, Priors, and Posterior Targets
5. MCMC Full Conditionals
6. Variational Bayes and Laplace--Delta Updates
7. ELBO Decomposition
8. Posterior Prediction and Quantile Synthesis
9. GloFAS Discrepancy-Calibration Model

## Cross-Reference Impact

- No section labels were changed.
- Existing references to `sec:forecast`, `subsec:forecast_hstep`,
  `sec:synthesis`, `sec:selection`, `sec:simulation`, and `sec:data` remain
  valid.
- Algorithm labels were preserved.
- Only reader-facing titles, captions, roadmap text, and light transition prose
  were changed.

## Deferred Items

- The discussion section remains intentionally blank until final simulation and
  application results are available.
- Simulation result tables and interpretation remain deferred until the
  authoritative shared validation interfaces pass article-side guards.
- Post hoc quantile synthesis remains documented as optional and is not claimed
  as part of the current simulation design.
