# Academic Writing Style Profile for AI-Assisted Statistical Writing

**Version:** 0.2 repo-ready draft  
**Purpose:** This document is the source-of-truth style manual for drafting, revising, auditing, and improving statistics manuscripts with AI assistance. It is designed to be placed in a manuscript repository and read by Codex, ChatGPT, Claude, Gemini, local LLMs, or any other AI assistant before editing a paper.  
**Primary field:** Bayesian statistics, quantile regression, echo state networks, deep echo state networks, spatio-temporal modeling, probabilistic forecasting, MCMC, variational Bayes, regularized shrinkage priors, exAL and GAL likelihoods, calibration, and Q-DESN models.  
**Core voice:** Precise, restrained, mathematically clear, statistically mature, technically rigorous, explanatory, and non-promotional.

---

## How to Use This Document in a Repository

Place this file in a manuscript repository as:

```text
docs/academic-writing-style-profile.md
```

or, for maximum visibility:

```text
STYLE_PROFILE.md
```

For Codex or any repository-based AI agent, also include a short `AGENTS.md` file at the repository root that points to this document. A suggested `AGENTS.md` block appears near the end of this file.

When an AI assistant is asked to revise a manuscript, it should first read this document, then inspect the manuscript files, then produce either a style audit or a controlled revision. The assistant should not rewrite aggressively unless asked. It should preserve technical meaning, mathematical notation, claims, citations, and section intent unless these are inconsistent or unsupported.

This document is not a phrase-copying template. It extracts high-level style principles from admired statistics papers. Do not copy sentences, paragraph structures too closely, or distinctive language from the exemplar articles.

---

## Operating Principles for Any AI Assistant

The assistant must distinguish three categories in all style analysis and manuscript review:

1. **Direct observations from exemplar sources.** These are features observed in the uploaded papers or drafts.
2. **Inferred preferences.** These are style preferences inferred from the exemplar corpus and the user’s stated goals.
3. **Recommendations.** These are actionable rules for drafting, revising, or auditing manuscripts.

The assistant must flag:

- unsupported claims;
- missing citations;
- overstatements;
- technical ambiguity;
- notation inconsistency;
- conflation of model specification and computation;
- conflation of exact inference and approximate inference;
- unexplained likelihoods, priors, latent variables, hyperparameters, or deterministic features;
- simulation designs lacking goals, DGPs, competitors, metrics, or limitations;
- application sections lacking data context, preprocessing, evaluation protocol, interpretation, or limitations.

---

# 1. Executive Style Summary

## 1.1 Target Style

The target style is a modern statistics manuscript style that combines:

- the **Wikle style** of scientific/statistical framing, dynamic spatio-temporal structure, Bayesian hierarchical thinking, and uncertainty quantification;
- the **Cressie style** of definition-first exposition, covariance/process clarity, optimal prediction language, and computational consequences;
- the **Gelman style** of practical Bayesian workflow, weakly informative regularization, model checking, calibration, and modest claims;
- the **MCMC theory style** of stating assumptions, limiting regimes, and computational implications without obscuring the main statistical message.

The manuscript should begin from a concrete statistical, inferential, computational, or scientific limitation. It should not begin from the algorithm as a novelty object. The method should be introduced as a natural response to a well-defined limitation in existing methodology.

## 1.2 Core Writing Formula

Use the following rhetorical sequence throughout the paper:

```text
Problem -> limitation -> statistical gap -> proposed construction -> inferential/computational consequences -> empirical evaluation -> calibrated interpretation -> limitations and future work.
```

For Bayesian methodology:

```text
Data structure -> inferential target -> likelihood -> latent process -> priors/hyperpriors -> posterior target -> computational approximation -> diagnostics -> prediction/calibration.
```

For DESN/Q-DESN methodology:

```text
Forecasting problem -> nonlinear temporal/spatio-temporal dependence -> distributional/quantile target -> reservoir representation -> likelihood or loss construction -> shrinkage/regularization -> inference algorithm -> calibration and scoring.
```

## 1.3 High-Level Voice Rules

Use clear, modest, technically mature language:

- Prefer “We develop,” “We introduce,” “We propose,” “This construction enables,” and “The results indicate.”
- Avoid “revolutionary,” “extremely powerful,” “state-of-the-art” unless directly supported by a fair benchmark.
- Avoid “we solve the problem” unless the result is a theorem with stated assumptions.
- Interpret results as evidence under a design, not universal truth.
- Write as a statistician explaining a model, not as a machine-learning paper advertising an architecture.

---

# 2. Exemplar Corpus Map

This map records the current exemplar corpus. Roles should be updated as new files are added.

| Source file | Title | Authors | Year / venue | Area | Role |
|---|---|---:|---|---|---|
| `Download (4).pdf` | *Weak Convergence and Optimal Scaling of Random Walk Metropolis Algorithms* | Roberts, Gelman, Gilks | 1997, Annals of Applied Probability | MCMC theory, optimal scaling | Technical exemplar |
| `Download (2).pdf` | *Prior distributions for variance parameters in hierarchical models* | Gelman | 2006, Bayesian Analysis | Hierarchical priors | Technical/style exemplar |
| `s11222-013-9416-2.pdf` | *Understanding predictive information criteria for Bayesian models* | Gelman, Hwang, Vehtari | 2014, Statistics and Computing | Bayesian model evaluation | Technical/style exemplar |
| `1-s2.0-S2211675324000472-main.pdf` | *Spatial statistics: Climate and the environment* | Wikle, Hooten, Kleiber, Nychka | 2024, Spatial Statistics | Spatial/environmental statistics | Style exemplar for concise field framing |
| `BF00889887 (1).pdf` / `BF00889887.pdf` | *The Origins of Kriging* | Cressie | 1990, Mathematical Geology | Geostatistics, kriging history | Definition-first exposition exemplar |
| `Download (3).pdf` | *A Weakly Informative Default Prior Distribution for Logistic and Other Regression Models* | Gelman, Jakulin, Pittau, Su | 2008, Annals of Applied Statistics | Weakly informative priors | Practical Bayesian methodology exemplar |
| `jrsssb_70_1_209.pdf` | *Fixed Rank Kriging for Very Large Spatial Data Sets* | Cressie, Johannesson | 2008, JRSSB | Spatial prediction, large data | Primary technical/formatting exemplar |
| `Echo State Networks for Spatio-Temporal Area-Level Data.pdf` | *Echo State Networks for Spatio-Temporal Area-Level Data* | Wang, Holan, Wikle | 2025, Data Science in Science | ESNs, areal spatio-temporal forecasting | Primary Wikle-style ESN exemplar |
| `Statistics in Medicine - 2007 - Gelman - Scaling regression inputs...pdf` | *Scaling regression inputs by dividing by two standard deviations* | Gelman | 2008, Statistics in Medicine | Regression scaling | Short applied-methods exemplar |
| `jrsssb_46_3_440.pdf` | *Multinomial Goodness-of-fit Tests* | Cressie, Read | 1984, JRSSB | Goodness-of-fit, divergence statistics | Theory and recommendation exemplar |
| `Download (1).pdf` | *Inference from Iterative Simulation Using Multiple Sequences* | Gelman, Rubin | 1992, Statistical Science | MCMC diagnostics | Computational workflow exemplar |
| `A Statistician s Overview of Physics-Informed Neural Networks for Spatio-Temporal Data.pdf` | *A Statistician’s Overview of Physics-Informed Neural Networks for Spatio-Temporal Data* | Wikle, North, Gopalan, Yoo | 2026, JASA accepted manuscript | BHM, PINNs, UQ | Primary Wikle-style overview exemplar |
| `Gelman-POSTERIORPREDICTIVEASSESSMENT-1996.pdf` | *Posterior Predictive Assessment of Model Fitness via Realized Discrepancies* | Gelman, Meng, Stern | 1996, Statistica Sinica | Bayesian model checking | Model-assessment exemplar |
| `BF01032109.pdf` | *Fitting Variogram Models by Weighted Least Squares* | Cressie | 1985, Mathematical Geology | Variogram fitting | Workflow and geostatistical modeling exemplar |
| `2507.14336v2.pdf` | *A Statistician’s Overview of Physics-Informed Neural Networks for Spatio-Temporal Data* | Wikle, North, Gopalan, Yoo | 2025, arXiv | BHM, PINNs, UQ | Preprint/formatting duplicate |
| `FRK_intro.pdf` | *Introduction to Fixed Rank Kriging: The R package* | Zammit-Mangion, Cressie | 2026, R package vignette | FRK software | Reproducible software/tutorial exemplar |

No uploaded file has yet been clearly identified as the user’s own draft. When user-authored drafts are added, classify them separately and compare them to this corpus.

---

# 3. Source-Derived Style Principles

## 3.1 Direct Observations from the Wikle-Style Sources

The Wikle sources consistently frame methodology through scientific process structure, uncertainty, and statistical hierarchy. They introduce machine-learning or neural-network components only after explaining the statistical problem and the data structure. They separate the latent process, observations, deterministic/mechanistic components, and parameters before moving to computation.

Key observed features:

- Start with a broad scientific or statistical motivation, then narrow to a precise inferential problem.
- Give historical and methodological context without turning the introduction into a citation list.
- Distinguish data, latent process, deterministic process, parameters, and approximations.
- Use Bayesian hierarchical modeling as the organizing framework for uncertainty quantification.
- Treat neural networks as model components, basis expansions, representations, or approximators, not as self-justifying algorithms.
- Use simulation sections to show how model components interact: latent process, mechanistic component, discrepancy, observation model, and posterior summaries.

## 3.2 Direct Observations from the Cressie-Style Sources

The Cressie sources are definition-first and criterion-driven. They often begin by defining the object of interest, then deriving or explaining the optimality criterion, then connecting the criterion to computation or application.

Key observed features:

- Define the statistical object before reviewing its history or variants.
- Use equations to clarify optimality, prediction, covariance, or variance structure.
- Link model assumptions to practical workflow stages.
- Make computational consequences explicit.
- Prefer exact statements about prediction, BLUP, covariance, variogram, mean squared prediction error, or estimation criteria.

## 3.3 Direct Observations from the Gelman-Style Sources

The Gelman sources often begin with an applied modeling difficulty: separation, unstable priors, coefficient interpretation, model checking, convergence diagnostics, or predictive comparison. They then propose a practical Bayesian solution, explain why the solution is useful, and illustrate it with examples.

Key observed features:

- Begin from a practical modeling failure or interpretability problem.
- Use weakly informative priors as stabilizing defaults, not as universal truths.
- Distinguish model checking from proving a model correct.
- Emphasize graphical and predictive diagnostics.
- Keep claims practical and conditional.
- Explain computational routines in terms of what they enable for routine analysis.

## 3.4 Inferred User Preferences

The user likely prefers writing that:

- is mathematically rigorous but not needlessly dense;
- foregrounds the inferential target rather than the algorithm;
- treats Bayesian modeling as a coherent workflow: model, inference, diagnostics, prediction;
- gives neural-network methods a statistical interpretation;
- uses calibrated, cautious claims;
- presents simulations and applications as evidence for specific properties, not as leaderboard exercises;
- makes notation legible and stable across sections;
- aligns with modern spatio-temporal Bayesian statistics rather than generic deep-learning prose.

## 3.5 Recommendations

For future manuscripts, combine the following:

- Wikle’s statistical framing and BHM clarity;
- Cressie’s formal definitions and computational consequences;
- Gelman’s practical Bayesian workflow and model-checking discipline;
- concise modern formatting with clear algorithms, tables, and figures.

---

# 4. Manuscript Architecture Rules

## 4.1 Default Paper Structure

A strong methods paper in this style should use the following structure unless the target journal dictates otherwise:

```text
Title
Abstract
1. Introduction
2. Background and Related Work
3. Proposed Model
4. Posterior Inference and Computation
5. Simulation Study
6. Data Application
7. Discussion
Appendix A. Derivations
Appendix B. Computational Details
Appendix C. Additional Simulation Results
Appendix D. Additional Application Diagnostics
```

For a shorter paper, combine Sections 2 and 3 or combine Sections 5 and 6 only if clarity is preserved.

For a theory-heavy paper, use:

```text
1. Introduction
2. Setup and Notation
3. Main Results
4. Computational or Inferential Consequences
5. Numerical Experiments
6. Discussion
```

For a software or package paper, use:

```text
1. Introduction
2. Statistical Model
3. Estimation and Prediction
4. Software Implementation
5. Examples
6. Practical Guidance and Limitations
```

## 4.2 Manuscript-Level Narrative Arc

Every manuscript should answer these questions in order:

1. What statistical/scientific problem motivates the work?
2. What limitations of existing methods matter for this problem?
3. What precise gap remains?
4. What construction addresses the gap?
5. What is the inferential target?
6. What are the model components?
7. How is inference performed?
8. What approximations are used?
9. What simulations test the relevant properties?
10. What application demonstrates practical value?
11. What are the limitations?
12. What should future work address?

## 4.3 Contribution Statement Template

Use contributions that are specific and technically meaningful:

```text
The contributions of this work are threefold. First, we formulate [model] for [inferential target] by combining [component A] with [component B]. Second, we develop [inference/computation] that separates [exact posterior/objective] from [approximation]. Third, we evaluate the method through [simulation/application], focusing on [calibration, coverage, sharpness, robustness, computation].
```

Avoid vague contribution lists such as “we propose a novel framework” without saying what is new statistically.

---

# 5. Abstract and Introduction Rules

## 5.1 Abstract Structure

The abstract should contain five moves:

1. **Problem domain.** State the statistical or scientific problem.
2. **Limitation.** Identify what existing methods fail to address.
3. **Method.** Introduce the proposed model or inferential construction.
4. **Computation/evaluation.** State how inference is performed and how the method is evaluated.
5. **Qualified conclusion.** State what the evidence indicates.

Example abstract skeleton:

```text
Spatio-temporal probabilistic forecasting often requires models that represent nonlinear temporal dependence while preserving calibrated uncertainty for distributional functionals such as conditional quantiles. Existing reservoir-based approaches provide scalable nonlinear dynamics, but they do not directly address [gap]. We develop [method], a Bayesian [model class] that combines [likelihood], [latent dynamic representation], and [prior or regularization]. Posterior inference is performed using [MCMC, VB, Laplace-Delta, or a hybrid method], with [diagnostics or approximation checks]. Simulation studies and an application to [data] evaluate [coverage, calibration, sharpness, scoring, computation]. The results indicate that [qualified finding], while also highlighting [limitation].
```

## 5.2 Introduction Opening

The first paragraph should not begin with the algorithm. It should begin with the statistical or scientific problem.

Preferred opening patterns:

- “Probabilistic forecasting for spatio-temporal processes requires models that can represent nonlinear dynamics while quantifying uncertainty in predictive distributions.”
- “Bayesian quantile regression provides a useful framework for distributional inference, but scalable spatio-temporal quantile modeling remains difficult when dependence is nonlinear and high-dimensional.”
- “Many environmental, economic, and official-statistics datasets are observed over space and time, where forecasting requires both temporal dynamics and spatial structure.”

Avoid opening patterns:

- “Deep learning has revolutionized…”
- “Echo state networks are powerful…”
- “In this paper, we propose a novel algorithm…”

## 5.3 Gap Statement

The gap should be precise. It should identify the statistical object that is missing.

Weak gap:

```text
Existing methods do not perform well for complex data.
```

Strong gap:

```text
Existing reservoir-based spatio-temporal forecasting methods provide scalable nonlinear dynamics, but they typically target conditional means or Gaussian predictive summaries and do not directly provide calibrated inference for conditional quantiles under asymmetric likelihoods.
```

## 5.4 Roadmap

End the introduction with a short roadmap. Keep it functional, not formulaic.

```text
Section 2 reviews related Bayesian quantile and reservoir-based forecasting methods. Section 3 introduces the proposed model and prior specification. Section 4 describes posterior computation and approximation diagnostics. Sections 5 and 6 present simulation studies and a data application. Section 7 concludes with limitations and future directions.
```

---

# 6. Related Work Rules

## 6.1 Thematic Organization

Do not write a citation dump. Organize related work by methodological role.

Recommended themes for the user’s field:

1. Bayesian quantile regression and asymmetric likelihoods.
2. exAL and GAL likelihoods and distributional robustness.
3. Reservoir computing, ESNs, DESNs, and random feature representations.
4. Spatio-temporal Bayesian hierarchical models.
5. Shrinkage priors and regularized horseshoe priors.
6. Approximate Bayesian computation, VB, Laplace, Delta method, and MCMC.
7. Forecast calibration, scoring rules, and posterior predictive assessment.

Each theme should answer:

- What does this literature solve?
- What does it not solve for the current manuscript?
- How does the proposed method connect to it?

## 6.2 Citation Tone

Give existing work credit. Do not frame the paper as correcting everyone else. Use formulations such as:

- “These methods provide useful tools for…, but they are not designed for…”
- “A related line of work considers…, whereas our focus is…”
- “The proposed model builds on this literature by…”

Avoid:

- “Existing methods fail…” unless carefully qualified.
- “No work has considered…” unless verified.
- “To the best of our knowledge” overused as a substitute for a precise gap.

---

# 7. Notation and Mathematical Exposition Rules

## 7.1 General Notation Principles

Define notation before using it. State dimensions when useful. Use consistent symbols throughout.

Distinguish:

- observed data;
- covariates and deterministic features;
- latent processes or states;
- parameters;
- hyperparameters;
- priors and hyperpriors;
- likelihood parameters;
- reservoir weights and random features;
- computational approximations;
- posterior or variational distributions;
- predictive quantities.

## 7.1.1 Introduce Target Functionals Before Using Their Symbols

High-quality statistics papers usually do not drop notation for a target
functional before defining the random quantity, observed realization,
conditioning information, and distribution or loss object. The best pattern in
the audited forecasting and quantile-regression papers is:

1. Name the random variable or process being predicted.
2. State what lower-case symbols denote when realized data are used.
3. Define the conditioning information, covariates, or information set.
4. Define the conditional distribution, likelihood, or loss criterion.
5. Define the target functional, such as a mean, quantile, interval, score, or
   posterior quantity.
6. Only then introduce shorthand notation used later.

For conditional quantiles, prefer a definition such as:

```latex
Let \(Y_{t+h}\) denote the future response and let \(\mathcal F_t\) denote
the information available at forecast origin \(t\). Write
\[
F_{t,h}(y)=\Pr(Y_{t+h}\le y\mid\mathcal F_t).
\]
For \(p_0\in(0,1)\), a level-\(p_0\) conditional quantile is
\[
Q_{t,h}(p_0)=\inf\{y:F_{t,h}(y)\ge p_0\}.
\]
```

Then explain how the model parameter, predictor, or readout is connected to
this functional. Avoid writing expressions such as
`\(Q_{p_0}(y_{t+h}\mid\mathcal F_t)\)` in the opening paragraph unless
\(Y_{t+h}\), \(y_{t+h}\), \(\mathcal F_t\), and the quantile convention have
already been defined. This rule is especially important in introductions,
abstracts, notation tables, and supplements because abrupt notation can make a
technically correct manuscript look informal or underdeveloped.

If conditioning is suppressed for readability, state that explicitly:

```text
The conditioning on \(\mathcal F_t\) is suppressed after this point when no
ambiguity arises.
```

## 7.1.2 Distinguish Forecast Origins, Target Dates, and Forecast-System Quantities

In forecast-calibration applications, define the forecast origin, horizon, and
target date before introducing forecast symbols. Do not let one symbol refer
simultaneously to a historical fitted value, an issued forecast, and a
calibrated target.

Use separate notation for:

- the reference process being forecast or calibrated;
- the forecast-system output or ensemble;
- the discrepancy or calibration term;
- the forecast origin \(T\), horizon \(h\), and target date \(T+h\);
- whether a quantity is estimated from the issued ensemble or forecast
  recursively beyond the issued horizon.

For discrepancy models, state the sign convention explicitly. For example, if
the model defines \(q^G=q^Y+d^G\), then the calibrated reference quantile must
be written as \(q^Y=q^G-d^G\). If an application uses issued ensemble forecasts
for \(q^G\), clarify that the model corrects the forecast-system quantile
rather than directly forecasting \(q^Y\) as a separate free path. Forecasts
beyond the issued ensemble horizon require their own recursive construction and
should not be described as part of the same in-window validation protocol
unless that construction has been specified.

## 7.1.3 Inline Versus Displayed Mathematics

Use inline and displayed mathematics deliberately. In the audited statistics
papers, display equations are used when the equation is a definition, model
component, posterior target, algorithmic update, criterion, or derivation that
the reader needs to see as a separate object. Inline mathematics is used for
short symbols, parameter ranges, brief identities, and reminders that are part
of the sentence.

Prefer inline math `\(...\)` when:

- the expression is a short symbol, parameter range, or phrase-level reminder,
  such as `\(p_0\in(0,1)\)`, `\(\sigma>0\)`, or `\(\mat X\)`;
- the expression is not a central definition and fits naturally inside the
  sentence;
- displaying it would create visual interruption without improving
  readability;
- the expression is being mentioned rather than introduced or derived.

Prefer displayed math `\[...\]`, `equation`, or `align` when:

- the equation defines the main target, likelihood, prior, posterior,
  variational factorization, scoring rule, DGP, or algorithmic update;
- the expression is too long for a clean line of prose;
- several related quantities are defined together;
- the equation is interpreted immediately before or after the display;
- the expression will be referenced later, in which case use a numbered
  `equation` or `align` environment with a label.

Avoid the hybrid mistake of placing inline delimiters on their own lines, such
as:

```latex
\(
\rho(\mat A)=\max_i|\lambda_i(\mat A)|
\)
```

If the equation deserves visual emphasis, use a real display:

```latex
\[
\rho(\mat A)=\max_i|\lambda_i(\mat A)|.
\]
```

If it is only a short definition inside a notation paragraph, keep it inline:

```latex
For any square matrix \(\mat A\), the spectral radius is
\(\rho(\mat A)=\max_i|\lambda_i(\mat A)|\).
```

As a practical audit rule, scan every `\[...\]` display and ask whether it is
central, long, multi-part, referenced, or easier to read separately. If not,
convert it to inline math. Then scan every `\(...\)` expression that appears on
its own line; convert it either to a true display or to inline prose. This
keeps the manuscript closer to the polished convention used in published
statistics papers, where display math marks objects the reader should pause
over.

## 7.2 Recommended Symbol Conventions

Use or adapt the following conventions:

| Object | Suggested notation | Notes |
|---|---|---|
| observed response | `y_t(s)` or `y_{it}` | Use one convention consistently. |
| covariates | `x_t(s)`, `\mathbf{x}_{it}` | State dimension. |
| latent process | `\eta_t(s)`, `u_t(s)`, or `\alpha_t` | Avoid reusing for hyperparameters. |
| reservoir state | `\mathbf{h}_t` | State dimension `N_h`. |
| reservoir weights | `\mathbf{W}`, `\mathbf{W}_{\text{res}}`, `\mathbf{W}_{\text{in}}` | Distinguish fixed random weights from learned readout weights. |
| readout coefficients | `\boldsymbol{\beta}` or `\mathbf{W}_{\text{out}}` | Use one notation. |
| quantile level | `\tau` | Avoid conflict with time horizon. |
| asymmetric likelihood parameter | `\theta_y` or likelihood-specific symbols | Define carefully. |
| shrinkage parameters | `\lambda_j`, `\tau_0`, `c` | Distinguish local/global/slab parameters. |
| posterior | `p(\theta \mid y)` | Use exact target before approximations. |
| variational distribution | `q(\theta)` | State factorization. |
| predictive distribution | `p(y_{T+h}\mid y_{1:T})` | Distinguish mean/median/quantiles. |

## 7.3 Equation Introduction and Interpretation

Every displayed equation should be introduced and interpreted.

Before display:

```text
We model the observation at location s and time t through a conditional likelihood whose location parameter depends on a latent reservoir representation:
```

Display:

```latex
 y_t(s) \mid \eta_t(s), \theta_y \sim p_y\{\cdot \mid \eta_t(s), \theta_y\}.
```

After display:

```text
Here, \eta_t(s) is the latent predictor for the distributional functional of interest, and \theta_y collects likelihood parameters that control scale, skewness, or tail behavior. This formulation separates the observation model from the dynamic representation used to construct \eta_t(s).
```

## 7.4 Model Development Sequence

Use this order:

1. Data and indexing.
2. Observation model.
3. Latent process or predictor.
4. Reservoir/dynamic representation.
5. Priors and hyperpriors.
6. Posterior target.
7. Predictive distribution.
8. Computational approximation.

Avoid introducing computation before the model is fully specified.

---

# 8. Model Development Rules for Bayesian Q-DESN-Type Papers

## 8.1 Observation Model

State the inferential target. For quantile regression, identify whether the likelihood is used as:

- an exact generative model;
- a working likelihood;
- a pseudo-likelihood associated with quantile loss;
- an asymmetric likelihood with additional distributional flexibility;
- a computational device for posterior inference.

Example:

```text
For a fixed quantile level \tau \in (0,1), we use an asymmetric likelihood to connect the conditional quantile of the response to the latent predictor. The likelihood is treated as [a working likelihood or a generative model], and its role is to provide a coherent posterior target for the quantile-specific parameters.
```

## 8.2 Reservoir Representation

Explain why the reservoir is used statistically:

- it provides a random nonlinear feature map;
- it captures temporal dependence through recurrent state evolution;
- it reduces training burden by fixing internal weights;
- it permits regularized Bayesian inference on readout weights;
- it can be embedded in hierarchical or probabilistic forecasting models.

Do not describe the reservoir as merely a neural-network architecture.

## 8.3 Shrinkage Priors

When using regularized horseshoe or related priors:

- define global, local, and slab parameters;
- explain what is being shrunk;
- identify why shrinkage is needed for high-dimensional reservoir features;
- state whether shrinkage is applied by quantile level, output dimension, layer, location, or feature group;
- include prior sensitivity if claims depend on shrinkage.

## 8.4 Calibration

For probabilistic forecasting, calibration should be part of the model assessment narrative. Include:

- empirical coverage of predictive intervals;
- interval width or sharpness;
- CRPS or weighted interval score when relevant;
- pinball loss for quantile-specific forecasting;
- calibration plots or reliability diagrams;
- posterior predictive checks when Bayesian model fit is central.

---

# 9. Computation and Algorithm Rules

## 9.1 Separation of Target and Approximation

Always state the exact target first:

```text
The posterior distribution is proportional to the product of the likelihood and prior components,
```

then define the approximation:

```text
Because direct posterior computation is impractical for [reason], we use [MCMC, VB, Laplace-Delta, or a hybrid method] to approximate [specific posterior quantity].
```

Do not write as if the approximation is the model.

## 9.2 MCMC Reporting

For MCMC, report:

- number of chains;
- warmup and retained draws;
- convergence diagnostics;
- effective sample size summaries;
- divergent transitions or mixing problems, if applicable;
- posterior predictive or prior sensitivity checks when relevant.

## 9.3 Variational Bayes Reporting

For VB, report:

- variational family;
- factorization assumptions;
- objective function;
- optimization method;
- convergence criterion;
- uncertainty limitations;
- comparison to MCMC for a smaller problem if feasible.

## 9.4 Laplace–Delta Approximation Reporting

For Laplace–Delta approximations, report:

- parameter mode or expansion point;
- Hessian or curvature approximation;
- transformed quantities receiving Delta-method uncertainty;
- conditions under which the approximation is expected to be adequate;
- diagnostics or comparisons where possible.

## 9.5 Algorithm Boxes

Use algorithm boxes only after symbols are defined.

Algorithm boxes should include:

- inputs;
- initialized quantities;
- iterative steps;
- update equations or references to equations;
- outputs;
- tuning or convergence criteria.

Avoid long algorithm boxes that duplicate the model section.

---

# 10. Simulation Study Rules

## 10.1 Simulation Section Structure

Every simulation study should have this structure:

```text
5. Simulation Study
5.1 Goals
5.2 Data-generating processes
5.3 Competing methods
5.4 Evaluation metrics
5.5 Results
5.6 Sensitivity analysis
5.7 Interpretation and limitations
```

## 10.2 Simulation Goals

Name the goal before the DGP. Examples:

- assess quantile calibration under nonlinear dynamics;
- evaluate robustness to asymmetric or heavy-tailed errors;
- compare computation and accuracy as reservoir dimension increases;
- test sensitivity to shrinkage priors;
- evaluate spatial dependence recovery;
- assess predictive performance under distribution shift.

## 10.3 Data-Generating Process Reporting

For each DGP, state:

- sample size;
- number of locations;
- number of time points;
- forecast horizon;
- covariates;
- latent process;
- observation distribution;
- parameter values;
- quantile levels;
- missingness mechanism if any;
- number of replications.

## 10.4 Competitors

Choose competitors that test the claim. Include:

- simple baseline;
- classical/statistical baseline;
- neural/reservoir baseline;
- ablated version of the proposed model;
- idealized oracle only if clearly labeled.

## 10.5 Metrics

Use metrics aligned with the inferential target.

For quantiles:

- pinball loss;
- empirical coverage;
- interval width;
- calibration curves;
- quantile crossing rate.

For probabilistic forecasts:

- CRPS;
- log score when appropriate;
- weighted interval score;
- coverage and sharpness;
- posterior predictive discrepancies.

For computation:

- runtime;
- memory;
- effective sample size per second;
- optimization convergence;
- approximation accuracy.

## 10.6 Interpretation

Do not simply say “Method A performs best.” Instead write:

```text
The simulation suggests that the proposed model improves calibration at extreme quantile levels under nonlinear temporal dependence. The gain is most pronounced when [condition], whereas the simpler baseline remains competitive when [condition].
```

---

# 11. Data Application Rules

## 11.1 Application Section Structure

Use the following structure:

```text
6. Data Application
6.1 Scientific or applied context
6.2 Data description and preprocessing
6.3 Modeling choices
6.4 Forecasting or validation protocol
6.5 Results
6.6 Diagnostics and calibration
6.7 Interpretation and limitations
```

## 11.2 Data Description

Include:

- source of data;
- spatial and temporal domain;
- response definition;
- covariates;
- missing data;
- preprocessing;
- train/test split;
- forecast horizon;
- whether evaluation is rolling, blocked, random, or out-of-time.

## 11.3 Modeling Choices

Explain why the model is appropriate for the data structure:

- nonlinear dynamics;
- spatial dependence;
- non-Gaussian outcomes;
- quantile-specific inference;
- heavy tails or skewness;
- missingness;
- computational scale.

## 11.4 Results

Present both quantitative and visual summaries.

Recommended visuals:

- forecast trajectories with intervals;
- maps of observed vs predicted fields;
- posterior densities for key parameters;
- calibration plots;
- residual or posterior predictive diagnostics;
- interval coverage by quantile, horizon, or location.

---

# 12. Discussion and Conclusion Rules

## 12.1 Discussion Structure

Use four paragraphs:

1. Main contribution.
2. What the empirical evidence shows.
3. Limitations.
4. Future work.

## 12.2 Limitation Statements

Limitations should be specific:

- computational scaling;
- approximation accuracy;
- prior sensitivity;
- identifiability;
- limited application domain;
- missing data assumptions;
- lack of theoretical guarantees;
- dependence on reservoir hyperparameters;
- calibration under distribution shift.

Avoid generic limitations such as “future work will improve the model.”

## 12.3 Future Work

Future work should name concrete directions:

- multi-output quantile dependence;
- spatially varying shrinkage;
- joint modeling across quantile levels;
- scalable MCMC or structured VB;
- calibration under covariate shift;
- hierarchical pooling across regions or series;
- theoretical study of posterior consistency or approximation error.

---

# 13. Formatting Rules

## 13.1 Tables

Tables should be interpretable without excessive text. Captions should state:

- what is compared;
- what the rows and columns mean;
- the main takeaway when appropriate.

Good table types:

- simulation settings;
- prior specifications;
- competitor descriptions;
- metric summaries;
- posterior summaries;
- ablation studies.

## 13.2 Figures

Figures should support model understanding or evidence.

Good figure types:

- model schematic;
- simulation truth vs estimates;
- posterior distributions;
- forecast intervals;
- spatial maps;
- calibration plots;
- scoring metrics by horizon or quantile.

Captions should not merely name the figure. They should explain the comparison.

## 13.3 Notation Tables

Use a notation table when more than 15 recurring symbols appear.

Recommended columns:

| Symbol | Meaning | Dimension and support |
|---|---|---|
| `y_t(s)` | observed response | scalar, indexed by time and location |
| `\mathbf{h}_t` | reservoir state | `N_h \times 1` |
| `\tau` | quantile level | `(0,1)` |

## 13.4 Appendices

Move the following to appendices unless central to the paper:

- long derivations;
- prior full conditionals;
- ELBO algebra;
- Laplace approximation details;
- extra simulations;
- sensitivity analyses;
- implementation details;
- extended proofs.

## 13.5 Redundancy and Compactness

High-quality statistical writing should be self-contained without becoming
repetitive. Repeat a definition only when the reader needs it to follow a new
argument; otherwise use a short reminder or a cross-reference. The main article
should carry the statistical argument, while the supplement should carry the
recoverable derivations and algorithmic details.

Use the following rules during revision:

- State each major caveat once in full, then refer back to it compactly.
- Avoid repeating the same qualifier in the abstract, introduction, model,
  computation, forecasting, and discussion unless the local claim depends on it.
- Do not restate a complete model layer when a cross-reference and one sentence
  are sufficient.
- Keep roadmap prose short; a roadmap should help the reader navigate, not
  summarize the manuscript twice.
- In the main article, replace long generic derivation templates with the
  specific target, approximation, and supplement reference.
- In the supplement, provide enough orientation to make derivations readable,
  but avoid repeating the motivation and literature review from the article.
- Preserve necessary redundancy for notation, assumptions, and exact versus
  approximate inference distinctions.

---

# 14. Phrase Bank

Use these phrases as flexible patterns, not as mandatory text.
These phrases should not be repeated mechanically. When a phrase begins to sound generic, replace it with a sentence that names the relevant likelihood, prior, latent process, approximation, simulation design, metric, or application protocol.

## 14.1 General Method Phrases

- “We develop a Bayesian framework for…”
- “We introduce a model that separates…”
- “This construction allows…”
- “The resulting model retains… while allowing…”
- “The proposed formulation is designed for…”
- “The method is evaluated through…”
- “The results suggest…”
- “The empirical analysis indicates…”
- “These findings should be interpreted in light of…”

## 14.2 Gap Phrases

- “However, this approach does not directly address…”
- “A remaining limitation is…”
- “Less attention has been given to…”
- “This creates a need for…”
- “The present work focuses on…”

## 14.3 Mathematical Exposition Phrases

- “We first define the observation model.”
- “The latent process is specified as follows.”
- “The prior distribution is chosen to regularize…”
- “The posterior target is proportional to…”
- “This term controls…”
- “This representation separates…”

## 14.4 Simulation Phrases

- “The simulation study is designed to assess…”
- “The first scenario isolates…”
- “The second scenario introduces…”
- “Performance is evaluated using…”
- “The results indicate that…”
- “The improvement is most pronounced when…”

## 14.5 Discussion Phrases

- “The proposed method provides…”
- “A limitation of the current formulation is…”
- “The analysis suggests…”
- “Future work will consider…”
- “These results do not imply…”

---

# 15. Avoid List

Avoid:

- “revolutionary”;
- “extremely powerful”;
- “state-of-the-art” without benchmark evidence;
- “solves the problem”;
- “outperforms” without metric, protocol, and uncertainty;
- “black-box” unless the point is interpretability;
- algorithm-first introductions;
- citation dumping;
- unexplained notation;
- slash shorthand in prose, headings, subtitles, table headers, or roadmap text
  when "and", "or", "with", or a short phrase is clearer; retain slashes only
  for mathematical ratios, file paths, URLs, and established notation;
- equations without interpretation;
- simulation results without stated goals;
- application results without protocol;
- claims about calibration without calibration metrics;
- presenting VB, Laplace, or ensemble intervals as exact posterior intervals unless justified;
- excessive novelty language;
- generic AI-polished prose that improves fluency without adding statistical specificity.

---

# 16. Anti-AI-Prose Rules for Academic Writing

This section gives explicit rules for preventing manuscripts from sounding generic, promotional, over-smoothed, or mechanically polished. The goal is not to reject AI-assisted drafting. AI assistance is useful for auditing structure, checking notation, improving clarity, identifying unsupported claims, and harmonizing manuscript sections. The goal is to prevent prose that sounds as if it was produced by a general-purpose assistant rather than authored by a careful statistician.

The target voice remains precise, restrained, mathematically clear, statistically mature, technically rigorous, explanatory, and non-promotional. Manuscript prose should name the statistical object under study, state the relevant inferential or computational difficulty, and connect each claim to a model component, assumption, simulation design, application protocol, or evaluation metric.

The following principle should guide all revisions:

> Replace generic fluency with statistical specificity.

A sentence should not merely sound smooth. It should do identifiable work in the manuscript.

## 16.1 Purpose

AI-written academic prose often has several surface features: broad openings, inflated claims, stock transitions, overuse of abstract nouns, repetitive rhythm, vague claims about importance, and polished sentences that do not advance the argument. These features are especially damaging in statistics manuscripts because they obscure the inferential target, the model assumptions, the computational approximation, the data structure, and the evidence supporting the claims.

The desired manuscript should instead read as if each paragraph was written by a statistician who knows exactly:

- what data structure is being modeled;
- what latent process, parameter, quantile, forecast distribution, or posterior quantity is of interest;
- what limitation in existing methodology motivates the proposed construction;
- what assumptions are being made;
- what is exact and what is approximate;
- what the simulations are designed to assess;
- what the application does and does not establish.

AI assistance may be used to enforce these standards, but AI-generated generic prose must be revised into statistically grounded prose.

## 16.2 Taxonomy of AI-Prose Patterns to Avoid

### 16.2.1 Generic Openings

Avoid openings that could begin almost any methods paper:

- "In today's data-driven world..."
- "The rapid growth of data has created new challenges..."
- "With the advent of machine learning..."
- "Modern data analysis requires robust and scalable tools..."
- "Spatio-temporal data are increasingly important across many domains..."

These openings are usually too broad. Start instead from the specific statistical problem: conditional quantile forecasting, nonlinear spatio-temporal dependence, posterior computation under asymmetric likelihoods, calibration of predictive intervals, or shrinkage in high-dimensional reservoir readout weights.

### 16.2.2 Vague Importance Claims

Avoid claims that assert importance without naming why the problem matters statistically or scientifically:

- "This is a crucial problem."
- "Accurate forecasting is essential."
- "Uncertainty quantification is important."
- "This task has broad implications."

Replace these with statements that specify the inferential consequence:

- Poorly calibrated forecast intervals can lead to nominal coverage without empirical reliability.
- Ignoring spatial dependence can understate uncertainty in regional forecasts.
- Quantile crossing can make the fitted conditional distribution incoherent.
- Heavy-tailed asymmetric likelihoods may stabilize inference when residual distributions are skewed or contaminated.

### 16.2.3 Inflated Novelty Language

Avoid novelty claims that are not tied to a precise contribution:

- "We propose a novel framework..."
- "This work introduces a groundbreaking method..."
- "Our approach revolutionizes..."
- "This method opens new avenues..."

Prefer restrained language:

- "We develop a Bayesian Q-DESN model for..."
- "We introduce a likelihood specification that..."
- "We use a regularized horseshoe prior to..."
- "We derive a Laplace-Delta approximation for..."

Novelty should be expressed through the construction, not through adjectives.

### 16.2.4 Excessive Framework Language

The word "framework" is often overused in AI prose. Use it only when the manuscript genuinely provides a broad modular system. Otherwise choose the more precise noun:

- model;
- likelihood;
- prior;
- posterior approximation;
- MCMC algorithm;
- VB objective;
- calibration procedure;
- forecast evaluation protocol;
- simulation design;
- sensitivity analysis.

For example, "Bayesian framework" may be appropriate if the manuscript defines a hierarchy of observation, process, prior, and computation layers. It is less appropriate when the contribution is a specific likelihood, prior, or algorithmic approximation.

### 16.2.5 Stock Word Overuse

The following words are not banned, but they often signal generic AI prose when used without technical content:

- robust;
- powerful;
- seamless;
- comprehensive;
- leveraging;
- harnessing;
- unlocking;
- delve;
- crucial;
- pivotal;
- landscape;
- realm;
- underscore;
- highlight;
- foster;
- ensure;
- utilize;
- facilitate;
- enhance;
- demonstrate;
- state-of-the-art;
- real-world;
- cutting-edge;
- scalable;
- flexible.

Use these only when the sentence specifies the technical meaning. For example, "robust" should mean something identifiable: insensitive to outliers, stable under prior perturbation, less sensitive to quantile-level misspecification, or empirically calibrated under a stated simulation design.

### 16.2.6 Formulaic "Not Only... But Also..." Constructions

AI-generated prose often relies on symmetrical constructions:

- "The proposed method not only improves accuracy but also enhances interpretability."
- "This approach not only captures nonlinear dynamics but also provides uncertainty quantification."

These are often vague. Replace them with direct statements of model roles:

- "The reservoir states represent nonlinear temporal dependence, while the Bayesian readout layer propagates uncertainty in the quantile-specific regression coefficients."
- "The graph-filtered input embedding introduces neighborhood information before the reservoir update; posterior uncertainty is then summarized through the fitted readout distribution."

### 16.2.7 Formulaic Paragraph Transitions

Avoid transitions that sound polished but empty:

- "Building upon these insights..."
- "Motivated by the aforementioned challenges..."
- "To this end..."
- "In light of these considerations..."
- "Taken together..."

Use transitions that state the logical step:

- "The preceding models address nonlinear dynamics but do not specify a likelihood for conditional quantiles."
- "The next section defines the asymmetric likelihood used to connect the observed response to the quantile-specific latent mean."
- "This motivates a prior that regularizes the high-dimensional readout weights without shrinking all coefficients equally."

### 16.2.8 Repetitive Sentence Rhythm

AI prose often alternates similarly shaped sentences:

- "X is important because..."
- "Y is challenging because..."
- "Z is useful because..."

Vary sentence length and function. Use short technical sentences for definitions. Use longer sentences only when they connect assumptions, consequences, or comparisons.

### 16.2.9 Vague Summary Sentences

Avoid sentences that summarize without adding information:

- "These results provide valuable insights."
- "This highlights the effectiveness of the proposed approach."
- "The findings underscore the importance of the method."
- "The analysis demonstrates the utility of the framework."

Replace these with a statement of what was learned:

- "In this design, the Q-DESN intervals maintain coverage closer to the nominal level at extreme quantiles, while the Gaussian ESN intervals are too narrow."
- "The improvement is largest when the DGP includes nonlinear temporal dependence and asymmetric errors."
- "The application suggests that the proposed model improves upper-tail calibration, although the result is limited to the observed forecast period."

### 16.2.10 Exaggerated Implications

Avoid extrapolating beyond the study design:

- "This method is broadly applicable to all spatio-temporal forecasting tasks."
- "The proposed approach solves the problem of uncertainty quantification in ESNs."
- "The results establish superiority over existing methods."

Use evidence-bounded claims:

- "The method is applicable to the class of forecasting problems in which the response can be represented through quantile-specific reservoir readout models."
- "The results suggest improved calibration in the simulation designs considered."
- "The comparison indicates better pinball loss and empirical coverage for the evaluated datasets and forecast horizons."

### 16.2.11 Empty Contribution-to-Literature Language

Avoid generic claims:

- "This study contributes to the literature by filling a gap."
- "Our work adds to the growing body of research."
- "This paper bridges machine learning and statistics."

Name the exact gap:

- "Existing ESN-based spatio-temporal forecasting methods typically model conditional means or Gaussian predictive distributions; they do not directly target conditional quantiles with posterior uncertainty."
- "Bayesian quantile regression provides likelihood-based inference for conditional quantiles, but standard linear formulations do not capture nonlinear reservoir dynamics without additional structure."

### 16.2.12 Citation-Dump Prose

Avoid paragraphs where citations replace argument:

- "Several authors have studied quantile regression, Bayesian forecasting, ESNs, and spatio-temporal models [many citations]."

Organize by methodological role:

- one group of citations for asymmetric likelihoods;
- one group for Bayesian quantile regression;
- one group for ESNs and DESNs;
- one group for spatio-temporal forecasting;
- one group for calibration and probabilistic forecast evaluation.

Each citation group should explain what prior work provides and what limitation remains.

### 16.2.13 Generic Equation Introductions

Avoid filler before equations:

- "The model can be written as follows."
- "Mathematically, we have..."
- "The equation below shows the framework."
- "We leverage the following formulation."

Introduce equations by naming their role:

- "The observation model links the response to the \(p\)th conditional quantile through an asymmetric likelihood."
- "The reservoir update maps lagged responses and covariates into a fixed nonlinear state vector."
- "The prior on the readout coefficients induces global-local shrinkage across reservoir features."
- "The variational objective approximates the posterior over the quantile-specific readout parameters."

### 16.2.14 Product-Style Algorithm Descriptions

Avoid writing computation sections as if describing software features:

- "The algorithm efficiently handles large-scale data and seamlessly integrates with the model."
- "The procedure is fast, robust, and easy to deploy."

State the computational target and approximation:

- "The lack of a closed-form normalized joint posterior is due to the non-conjugate exAL scale--asymmetry block, not to the ridge or regularized-horseshoe readout prior. Under the chosen augmentation, the readout and shrinkage-scale blocks retain closed-form conditional updates."
- "The VB algorithm optimizes a mean-field approximation to the joint posterior of the latent scale variables and regression coefficients."

### 16.2.15 Leaderboard-Style Simulation Interpretation

Avoid marketing language:

- "Our method significantly outperforms all competitors."
- "Extensive experiments demonstrate superior performance."

Use design-specific interpretation:

- "Across 100 replications, the proposed method has lower average pinball loss at \(\tau=0.9\) than the linear quantile regression baseline in the nonlinear DGP. The difference is smaller under the linear DGP."
- "The Q-DESN intervals are wider than those of the Gaussian ESN, but their empirical coverage is closer to the nominal level."

### 16.2.16 Application Overclaims

Avoid statements that treat one application as definitive scientific validation:

- "The real-world data demonstrate the effectiveness of the method."
- "The analysis reveals the true drivers of the process."
- "The model provides actionable insights."

Use protocol-specific language:

- "In the held-out period, the model improves upper-tail pinball loss relative to the baseline."
- "The fitted effects suggest temporal asymmetry in the forecast distribution, but causal interpretation is not warranted."
- "The application illustrates how the method can be used for calibrated probabilistic forecasting under the observed sampling structure."

### 16.2.17 Generic Discussion Limitations

Avoid limitations that could apply to any paper:

- "Future work will improve scalability."
- "Future research will explore additional applications."
- "The method has some limitations."

State the exact limitation:

- "The current implementation assumes a fixed reservoir and does not propagate uncertainty in the reservoir weights."
- "The Laplace-Delta approximation may understate posterior uncertainty when the posterior is skewed or multimodal."
- "The simulation study does not assess performance under missing spatial locations or time-varying graph structure."

### 16.2.18 Supplement Derivation Dumps

Avoid supplements that list equations without orientation. Each supplement section should explain:

- what result is being derived;
- where it is used in the main article;
- what notation is inherited from the main text;
- what assumptions are required;
- what approximation, if any, is being made.

A derivation should not begin with unexplained algebra.

### 16.2.19 Self-Referential Paper-About-Paper Framing

Avoid openings and topic sentences that announce what the manuscript is doing
instead of starting from the statistical object, data structure, or modeling
problem. These sentences are often technically accurate but sound self-conscious
because the paper is talking about itself.

Avoid:

- "The inferential target of this paper is..."
- "This paper considers the problem of..."
- "In this paper, we focus on..."
- "The present work studies..."
- "This supplement records..."
- "The purpose of this document is..."

Prefer object-level prose:

- "For nonlinear dynamic data, conditional quantiles are useful targets when
  forecasts are assessed by asymmetric-loss, tail-risk, or interval criteria."
- "Conditional on the fixed reservoir features, the Q-DESN readout is a
  high-dimensional Bayesian quantile regression model."
- "The posterior target includes the readout coefficients, likelihood scale and
  asymmetry, auxiliary mixture variables, and shrinkage parameters."
- "The derivation starts from the complete-data joint distribution and yields
  the full conditional used in the sampler."

Self-reference is acceptable for roadmaps, appendices, and explicit document
navigation, but it should not carry the main motivation or topic sentence of a
section. A reader should first encounter the statistical problem, model
component, assumption, or computational target, not a sentence about the paper's
own organization.

## 16.3 Academic Cliches and Replacement Guidance

| Avoid | Why it sounds generic or AI-written | Better academic alternative | Example in a statistics manuscript |
|---|---|---|---|
| "In today's data-driven world" | Opens too broadly and says nothing about the statistical problem. | Start with the data structure or inferential target. | "Spatio-temporal forecasting problems often require calibrated uncertainty for conditional quantiles rather than only conditional means." |
| "With the advent of..." | Formulaic historical opening. | Name the relevant methodological development and its limitation. | "Reservoir computing provides a computationally efficient way to represent nonlinear temporal dependence, but standard ESN formulations typically target mean forecasting." |
| "The rapid growth of data has led to..." | Vague scale claim; no modeling consequence. | State the computational or inferential bottleneck. | "Large spatio-temporal panels make fully Bayesian recurrent models difficult to fit with conventional MCMC." |
| "This paper presents a novel framework" | Inflated and imprecise. | Name the contribution: model, prior, likelihood, algorithm, diagnostic. | "We develop a Bayesian Q-DESN model with an asymmetric likelihood and global-local shrinkage on the readout weights." |
| "Our method significantly outperforms" | Overclaims unless tied to a test, metric, and design. | State the metric, design, and scope. | "In the nonlinear DGP, the proposed model has lower mean pinball loss at \(\tau=0.9\) across 100 replications." |
| "Extensive experiments demonstrate" | Marketing phrase; "extensive" is often undefined. | Describe the simulation design. | "The simulation study considers three DGPs that isolate linear dynamics, nonlinear reservoir dynamics, and asymmetric errors." |
| "State-of-the-art" | Requires a current and fair benchmark. | Use "baseline," "competitor," or name the method. | "We compare against linear Bayesian quantile regression, a Gaussian ESN, and a frequentist quantile random forest." |
| "Robust and scalable" | Ambiguous unless both terms are defined. | Specify robustness and scaling behavior. | "The shrinkage prior reduces sensitivity to weakly identified reservoir coefficients, and the readout update scales linearly in the number of time points conditional on the reservoir states." |
| "Seamlessly integrates" | Product-style phrasing. | Explain the mathematical connection. | "The likelihood enters the posterior through the observation layer, while the DESN states define the quantile-specific linear predictor." |
| "Harnesses the power of" | Promotional and vague. | State the role of the method. | "The reservoir states provide fixed nonlinear features for the quantile regression layer." |
| "Unlocks new possibilities" | Exaggerated implication. | State the specific extension enabled. | "This construction allows conditional quantiles to vary nonlinearly with lagged spatio-temporal features." |
| "Offers valuable insights" | Empty evaluation. | State what was learned. | "The application suggests improved upper-tail calibration during high-variance periods." |
| "It is crucial to note" | Artificial emphasis. | State the condition directly. | "The likelihood targets the \(\tau\)th conditional quantile only under the assumed asymmetric error representation." |
| "It is worth mentioning" | Filler. | Remove or replace with a logical transition. | "The approximation treats reservoir states as fixed after construction." |
| "This underscores the importance" | Vague significance claim. | State the implication for modeling or inference. | "This suggests that mean-calibrated forecasts may still have poor tail calibration." |
| "A comprehensive approach" | Often means too many things at once. | Specify the components. | "The model combines an asymmetric likelihood, DESN features, and a regularized horseshoe prior." |
| "To address these challenges" | Generic transition. | Name the exact difficulty. | "To regularize the high-dimensional readout layer, we place a global-local prior on the coefficients." |
| "In this work, we propose..." | Acceptable but often formulaic; may encourage algorithm-first framing. | Start with the statistical object when possible. | "We model the \(\tau\)th conditional quantile using a reservoir-based predictor and an asymmetric likelihood." |
| "The remainder of this paper is organized as follows" | Acceptable but often mechanical. | Use a concise roadmap tied to argument flow. | "Section 2 defines the Q-DESN model; Section 3 describes posterior computation; Sections 4 and 5 evaluate calibration in simulations and an application." |
| "Future work will explore..." | Generic unless specific. | Name the extension and why it matters. | "Future work will allow the graph structure to vary over time, which is needed for applications with changing spatial connectivity." |
| "Utilize" | Often an inflated substitute for "use." | Use "use" unless "utilize" has a specific technical meaning. | "We use the reservoir states as predictors in the quantile regression layer." |
| "Leverage" | Often vague. | State the mechanism. | "The method uses lagged observations to construct reservoir states." |
| "Enhance" | Vague direction of improvement. | Name the metric or property. | "The calibration step improves empirical coverage at the 90% nominal level in the held-out period." |
| "Demonstrate" | Too strong when evidence is empirical and design-limited. | Use "suggest," "indicate," or "show in this design." | "The simulation results suggest improved tail calibration under asymmetric errors." |
| "Real-world data" | Vague and promotional. | Name the data source and sampling structure. | "We analyze monthly county-level hospitalization counts observed over 2018-2023." |
| "Landscape" / "realm" | Abstract filler. | Name the literature or problem class. | "Bayesian quantile regression methods..." |
| "Pivotal" / "crucial" | Unnecessary emphasis. | State the role. | "The scale mixture representation is used to derive the Gibbs updates." |
| "Foster" | Usually vague in methods papers. | State the concrete effect. | "The prior induces shrinkage across weakly identified coefficients." |
| "Ensure" | Often too strong. | Use "encourage," "promote," "enforce," or state conditions. | "The monotonicity constraint enforces noncrossing quantile curves under the fitted parameterization." |

## 16.4 Rules for Replacing Generic AI Prose

1. Replace broad claims with the precise statistical object. Do not write "the method improves forecasting." Write what is improved: empirical coverage, pinball loss, CRPS, interval width, log score, posterior calibration, mixing, effective sample size, or computation time.
2. Replace "challenge" with the actual difficulty. Specify whether the difficulty is nonlinearity, high-dimensional coefficients, asymmetric errors, quantile crossing, posterior multimodality, non-Gaussian responses, dependence across locations, missingness, or computational cost.
3. Replace "framework" with the appropriate technical noun. Use "model" for a probabilistic specification, "prior" for a distributional assumption, "likelihood" for the data model, "algorithm" for computation, "approximation" for VB, Laplace, or Delta methods, and "evaluation protocol" for simulations or applications.
4. Replace "robust" with a defined property. Say whether the method is robust to outliers, prior perturbations, skewed errors, heavy-tailed residuals, sparse signals, weak identification, or misspecification. If no such assessment is reported, do not use "robust."
5. Replace "outperforms" with metric-specific language. State the competitor, metric, design, and uncertainty. Prefer: "has lower average pinball loss in this design" or "achieves closer empirical coverage in the held-out period."
6. Replace "demonstrates" with evidence-bounded verbs. For simulation and application results, prefer "suggests," "indicates," "is consistent with," or "in this design." Use "demonstrates" only for mathematical derivations, verified algorithms, or direct empirical facts.
7. Replace "real-world data" with the actual data source. Name the sampling units, temporal frequency, spatial support, response type, and evaluation split.
8. Replace "comprehensive experiments" with the exact simulation design. State the number of scenarios, DGPs, replications, sample sizes, quantile levels, competitors, and metrics.
9. Replace generic contribution language with a technical contribution. Instead of "we contribute to the literature," write "we combine an exAL likelihood with a DESN predictor and a regularized horseshoe prior for quantile-specific readout weights."
10. Replace abstract transitions with logical transitions. Every transition should identify what has been established and what remains unresolved.
11. Replace polished but empty topic sentences with claims that move the argument. A topic sentence should orient the reader to a specific role: motivation, definition, assumption, approximation, diagnostic, result, or limitation.
12. Replace adjective-heavy claims with definitions or evidence. If a method is "scalable," give the computational order, matrix dimension reduction, or empirical runtime context. If it is "flexible," state which model component varies.
13. Replace redundant explanation with one precise statement and, when needed,
    a cross-reference. Repetition is useful for definitions and caveats, but it
    should not make the manuscript restate the same argument in several
    sections.

## 16.5 Sentence-Level Style Rules

### 16.5.1 Avoid Overly Symmetrical Sentences

Symmetry can make prose sound mechanical. Avoid repeated paired structures unless they clarify a real distinction.

Weak:

> The model captures nonlinear dynamics while providing uncertainty quantification.

Better:

> The reservoir states represent nonlinear temporal dependence. Uncertainty enters through the posterior distribution of the quantile-specific readout coefficients.

### 16.5.2 Avoid Serial Intensifiers

Do not stack adjectives:

- "highly robust, powerful, and flexible";
- "comprehensive, scalable, and efficient";
- "important, challenging, and impactful."

Replace them with one precise property or remove the adjectives.

### 16.5.3 Avoid Polished but Empty Topic Sentences

Weak:

> Accurate and reliable forecasting remains a central challenge in modern statistics.

Better:

> For conditional quantile forecasting, accuracy must be assessed separately at each quantile level because a model with good mean prediction can still be poorly calibrated in the tails.

### 16.5.4 Vary Sentence Length and Function

Use short sentences for definitions:

> Let \(y_t(s)\) denote the response at location \(s\) and time \(t\).

Use longer sentences for relationships:

> Conditional on the reservoir state, the \(\tau\)th quantile is modeled through a linear readout, allowing nonlinear temporal dependence to enter through fixed reservoir features while keeping posterior computation in the regression layer.

### 16.5.5 Avoid Excessive Signposting

Do not overuse:

- "First and foremost";
- "As previously mentioned";
- "It should be noted that";
- "In the following subsection";
- "To further elaborate."

Use signposting only when it clarifies structure.

### 16.5.6 Avoid Starting Many Consecutive Sentences with "We"

Repeated "We" creates a procedural rhythm. Vary the subject.

Weak:

> We define the likelihood. We place priors on the coefficients. We derive the posterior approximation.

Better:

> The likelihood connects the response to the target quantile. The coefficient prior regularizes the high-dimensional readout layer. Posterior computation uses a Laplace approximation around the mode.

### 16.5.7 Prefer Active Statistical Subjects over Passive Abstraction

Weak:

> It is shown that uncertainty can be quantified.

Better:

> The posterior distribution of the readout coefficients provides interval estimates for the conditional quantile.

Weak:

> The method is applied to assess performance.

Better:

> The simulation compares empirical coverage, pinball loss, and interval width across four competing models.

### 16.5.8 Keep Technical Nouns Close to Their Definitions

Do not introduce a term and define it several sentences later. Define data, parameters, latent variables, priors, and approximations at first use.

Weak:

> The latent representation is used throughout the model. The vector \(h_t\), introduced below, contains the reservoir states.

Better:

> Let \(h_t \in \mathbb{R}^{n_h}\) denote the reservoir state at time \(t\). This latent representation is used as the predictor in the quantile-specific readout layer.

### 16.5.9 Avoid Abstract Nouns When the Object Is Mathematical

Weak:

> The integration of uncertainty is achieved through the framework.

Better:

> Uncertainty is propagated by sampling from the posterior distribution of \(\beta_\tau\) and transforming the draws through the quantile readout.

### 16.5.10 Do Not Let Fluency Hide Missing Assumptions

Smooth prose must not replace assumptions. If a claim depends on a likelihood, prior, independence assumption, approximation, or DGP, state it.

### 16.5.11 Avoid Self-Conscious Topic Sentences

A topic sentence should usually name the statistical object or logical step, not
the manuscript itself.

Weak:

> Conditional quantile forecasting for nonlinear dynamic data is the inferential target of this paper.

Better:

> For nonlinear dynamic data, conditional quantiles are useful targets when forecasts are assessed by asymmetric-loss, tail-risk, or interval criteria rather than only conditional mean accuracy.

Weak:

> This supplement records the posterior targets and algorithmic details for Q-DESN.

Better:

> Conditional on fixed reservoir features, the Q-DESN posterior target is a high-dimensional static quantile regression model under the AL or exAL working likelihood.

## 16.6 Section-Specific Anti-AI-Prose Rules

### 16.6.1 Abstract

Avoid:

- algorithm-first openings;
- "we propose a novel framework";
- universal superiority claims;
- "extensive experiments demonstrate";
- unqualified "robust and scalable."

Use the structure:

1. problem;
2. limitation or gap;
3. proposed construction;
4. inference or computation;
5. evidence from simulations or application;
6. qualified conclusion.

Preferred abstract logic:

> Probabilistic forecasting for spatio-temporal processes often requires calibrated inference for conditional quantiles. Existing reservoir-based forecasting methods provide nonlinear temporal features, but they typically do not specify a Bayesian likelihood for quantile-specific uncertainty. We develop... The methodology is evaluated through... The results suggest...

### 16.6.2 Introduction

Avoid:

- hype about AI, machine learning, or big data;
- "recent advances have revolutionized...";
- generic importance claims;
- citation lists without synthesis;
- novelty claims before the gap is established.

The introduction should name the exact limitation before the method is introduced. The gap should be stated in terms of an inferential, modeling, or computational object.

Weak gap:

> Existing methods do not fully address these challenges.

Better gap:

> Existing ESN-based forecasting methods typically produce conditional mean forecasts or Gaussian predictive intervals, leaving conditional quantile inference and tail calibration less directly addressed.

### 16.6.3 Related Work

Avoid disconnected citation chains. Organize by methodological role:

- quantile regression and asymmetric likelihoods;
- Bayesian quantile regression and posterior computation;
- ESN and DESN models for nonlinear dynamics;
- spatio-temporal probabilistic forecasting;
- shrinkage priors for high-dimensional readout layers;
- calibration and forecast evaluation.

Each paragraph should answer:

- What does this literature provide?
- What limitation remains for the present problem?
- How does the proposed method use or differ from it?

### 16.6.4 Model Section

Avoid:

- "we leverage X" without specifying how X enters the model;
- presenting computational augmentation as if it were the statistical model;
- equations without verbal setup;
- notation introduced after use;
- vague claims about flexibility.

The model section should distinguish:

- observed data;
- covariates and deterministic inputs;
- reservoir states or latent features;
- parameters;
- hyperparameters;
- latent variables;
- likelihood;
- priors;
- posterior target.

If an auxiliary-variable representation is used for computation, state whether it is part of the generative model, an equivalent representation of the likelihood, or an approximation.

### 16.6.5 Computation

Avoid product-style claims about speed, ease, or scalability. State:

1. the exact posterior target;
2. why it is not analytically tractable;
3. the approximation or sampler used;
4. what quantities are updated;
5. what uncertainty is propagated;
6. what uncertainty is approximated or ignored.

For MCMC, report mixing and convergence diagnostics. For VB, state the
factorization and possible underestimation of posterior uncertainty. For
Laplace-Delta approximations, state the expansion point and the transformation
to which the Delta method is applied. Comparisons between MCMC and VB are
method-comparison or approximation checks; they should not be described as
MCMC convergence diagnostics.

### 16.6.6 Simulation

Avoid:

- "extensive experiments";
- "superior performance";
- "the method is robust" without stress tests;
- results written like a leaderboard.

Each simulation section should contain:

- goal;
- DGP;
- sample size and dimensions;
- quantile levels;
- competitors;
- metrics;
- replications;
- results;
- interpretation;
- limitations.

Claims must be restricted to the simulation design. If only one DGP is considered, do not claim broad robustness.

### 16.6.7 Application

Avoid:

- "real-world data demonstrate...";
- causal language without causal design;
- vague scientific implications;
- application claims without protocol.

State:

- data source;
- spatial and temporal support;
- response and covariates;
- preprocessing;
- training and test periods;
- forecast horizon;
- evaluation metrics;
- uncertainty summaries;
- limitations.

Application conclusions should distinguish statistical performance from scientific explanation.

### 16.6.8 Discussion

Avoid generic limitations and vague future work. A strong discussion states:

- what the method contributes;
- what the evidence supports;
- what assumptions matter;
- what computational approximations may affect inference;
- what data settings were not studied;
- what extensions are technically natural.

Weak:

> Future work will improve scalability and consider more applications.

Better:

> Future work will consider time-varying reservoir weights and spatial graphs, which are needed when the dependence structure changes over the forecast period.

### 16.6.9 Supplement

Avoid derivation dumps. Each supplement section should begin with a short orientation paragraph:

- what is being derived;
- which main-text equation it supports;
- what assumptions are used;
- what notation is inherited;
- what result the reader should expect.

Supplement prose should be concise but not cryptic. A supplement is not a scratchpad; it is part of the scientific argument.

## 16.7 Diagnostic Checklist for AI-Written Prose

Use this checklist during revision. If the answer to several questions is "yes," revise the sentence or paragraph.

### Sentence-Level Checks

- Could this sentence appear in almost any methods paper?
- Does the sentence name a statistical object?
- Does it specify a model component, parameter, likelihood, prior, approximation, metric, or assumption?
- Is an adjective doing work that a definition should do?
- Is the sentence smoother than it is informative?
- Does the sentence contain stock words such as "robust," "powerful," "seamless," or "comprehensive" without defining them?
- Does the sentence claim importance without explaining the inferential consequence?
- Does the sentence use "demonstrate" for evidence that is only design-specific?
- Does the sentence say "outperform" without naming the metric and protocol?
- Does the sentence use "framework" when "model," "prior," "likelihood," or "algorithm" would be more precise?
- Does the sentence talk about the paper, article, work, supplement, or document
  when it could instead name the statistical object or modeling problem?

### Paragraph-Level Checks

- Does the paragraph contain a real logical step?
- Does the paragraph begin and end with vague summary sentences?
- Are citations organized by methodological role?
- Does each cited literature group have a clear connection to the gap?
- Are equations introduced with their purpose?
- Are equations interpreted after display?
- Are exact inference and approximate inference separated?
- Does the paragraph use repeated sentence rhythm?
- Do several consecutive sentences begin with "we"?
- Does the paragraph over-signpost rather than explain?
- Does the paragraph begin with a self-conscious sentence about what the paper
  does rather than the object being modeled or derived?

### Section-Level Checks

- Does the abstract follow problem -> gap -> construction -> inference -> evidence -> qualified conclusion?
- Does the introduction begin with the statistical problem rather than the algorithm?
- Is the gap named precisely?
- Does the model section define notation before using it?
- Does the computation section state the posterior target before the algorithm?
- Are simulation results interpreted under the actual DGPs and metrics?
- Does the application section specify data source, sampling structure, and evaluation protocol?
- Are limitations specific rather than generic?
- Does the supplement orient the reader before derivations?

## 16.8 Rewrite Examples

| Context | AI-generic version | Preferred revision |
|---|---|---|
| Abstract sentence | "In today's data-driven world, accurate and robust forecasting is crucial across many applications." | "Spatio-temporal probabilistic forecasting requires models that can represent nonlinear dependence while maintaining calibrated uncertainty for conditional quantiles." |
| Abstract contribution | "We propose a novel and comprehensive framework that leverages deep echo state networks for robust prediction." | "We develop a Bayesian Q-DESN model in which reservoir states define nonlinear predictors for quantile-specific readout coefficients." |
| Introduction gap | "Despite recent advances, existing methods fail to fully address the challenges of uncertainty quantification." | "Existing ESN and DESN forecasting methods typically focus on conditional means or Gaussian predictive intervals, leaving likelihood-based inference for conditional quantiles less directly developed." |
| Related work | "Many studies have explored quantile regression, Bayesian inference, and neural networks." | "Bayesian quantile regression provides likelihood-based inference for conditional quantiles, while ESN methods provide fixed nonlinear features for temporal dependence. The present work combines these roles by placing an asymmetric likelihood on a reservoir-based quantile predictor." |
| Model description | "We leverage the reservoir representation to enhance the flexibility of the model." | "The reservoir state \(h_t\) is treated as a fixed nonlinear feature vector. Conditional on \(h_t\), the \(\tau\)th quantile is modeled through a linear readout with coefficient vector \(\beta_\tau\)." |
| Equation setup | "Mathematically, the model is written as follows." | "The observation layer links the response to the target conditional quantile through the asymmetric likelihood." |
| Computation | "The algorithm efficiently estimates the model parameters and scales to high-dimensional settings." | "The exAL scale--asymmetry block is non-conjugate, while the readout and shrinkage-scale blocks retain closed-form conditional updates under the chosen augmentation. The sampler therefore uses direct updates for the conditionally tractable blocks and Metropolis--Hastings or slice updates for \((\sigma,\gamma)\)." |
| Simulation result | "Extensive experiments demonstrate that our method significantly outperforms competing approaches." | "In the nonlinear DGP, the proposed model has lower mean pinball loss at \(\tau=0.9\) than the linear quantile regression baseline. The difference is smaller in the linear DGP, where both models are correctly aligned with the conditional quantile structure." |
| Application | "The real-world data demonstrate the practical utility of the proposed framework." | "In the held-out period, the proposed model improves upper-tail pinball loss relative to the Gaussian ESN baseline. This result supports the use of quantile-specific modeling for this dataset, but does not imply causal interpretation of the fitted covariate effects." |
| Discussion limitation | "Future work will explore scalability and broader applications." | "The current implementation treats the reservoir weights as fixed after random generation. Future work will propagate reservoir uncertainty or learn structured reservoir components when the training period is short." |
| Supplement orientation | "We now provide additional derivations." | "This section derives the full conditional distribution used in Algorithm 1. The notation follows Section 3 of the main article, and the derivation assumes the scale-mixture representation of the asymmetric likelihood." |

## 16.9 Editing Procedure for Removing AI-Prose

When revising a manuscript section, use the following procedure:

1. Mark generic sentences. Identify sentences that could appear in any paper.
2. Identify the missing object. Ask what statistical object should replace the generic phrase.
3. Replace adjectives with definitions. Convert "robust," "scalable," or "flexible" into a property, condition, or metric.
4. Localize claims. Tie each empirical claim to a DGP, dataset, forecast horizon, metric, or posterior diagnostic.
5. Reduce novelty language. Let the model construction establish novelty.
6. Check equation prose. Ensure every displayed equation has a role before it appears and interpretation after it appears.
7. Check paragraph logic. Each paragraph should perform one function: motivate, define, compare, derive, report, interpret, or qualify.
8. Check tone. Replace promotional language with evidence-bounded language.
9. Check limitations. Make limitations specific to the model, computation, data, or evaluation protocol.
10. Check redundancy. Remove repeated caveats, repeated motivation, and repeated
    algorithm descriptions unless the repetition serves a new mathematical or
    interpretive purpose.
11. Read aloud for rhythm. Revise repeated sentence patterns and excessive signposting.

## 16.10 Minimal Anti-AI-Prose Rule for Agents

When an AI assistant edits a manuscript, it must apply this rule:

> Do not make the prose merely smoother. Make it more specific, more statistically grounded, and more faithful to the evidence.

A revision that increases fluency but removes assumptions, weakens notation, inflates claims, or hides approximations is a failed revision.

---

# 17. AI Review Workflow

## 17.1 Required AI Workflow

When an AI assistant revises a manuscript, it should follow this workflow:

1. Read this style profile.
2. Inspect the manuscript structure.
3. Identify the manuscript type: methods, theory, application, software, review, or hybrid.
4. Produce a style audit before major rewriting.
5. Perform an anti-AI-prose pass: replace generic claims, stock transitions, and vague adjectives with specific statistical objects, assumptions, metrics, and evidence-bounded statements.
6. Flag technical ambiguities and unsupported claims.
7. Suggest structural edits before sentence-level edits.
8. Preserve notation unless inconsistent.
9. Separate suggested edits by section.
10. Provide a revision summary.
11. Avoid inventing citations or technical claims.

## 17.2 AI Style Audit Template

```text
# Style Audit

## Manuscript type
[methods/theory/application/software/review]

## Main inferential target
[brief description]

## Main style alignment
[how well the draft aligns with the style profile]

## Structural issues
- [issue]

## Mathematical exposition issues
- [issue]

## Computation/inference issues
- [issue]

## Simulation/application reporting issues
- [issue]

## Claims needing support or qualification
- [claim]

## Recommended revision plan
1. [step]
2. [step]
3. [step]
```

## 17.3 AI Revision Constraints

When editing manuscript text, the assistant must:

- not change technical meaning unless requested;
- not invent citations;
- not add results that are not in the manuscript;
- not replace established notation without explanation;
- not replace technically specific prose with smoother but less informative prose;
- not remove limitations;
- not overstate empirical findings;
- not make prose sound promotional;
- not copy wording from exemplar papers.

---

# 18. Reusable AI Prompts

## 18.1 General Manuscript Revision Prompt

```text
Read docs/academic-writing-style-profile.md before editing. Revise the following manuscript section in the target style: precise, restrained, mathematically clear, statistically mature, and non-promotional. Start from the statistical or scientific problem, not the algorithm. Define notation before using it. Introduce equations verbally and interpret them after display. Separate the observation model, latent process, priors, hyperparameters, deterministic features, and computational approximation. Do not make the prose merely smoother; replace generic phrasing with statistical specificity. Keep claims modest and supported. Preserve technical meaning and notation unless inconsistent. After revising, list any unsupported claim, missing citation, notation inconsistency, technical ambiguity, overstatement, generic AI-style phrasing, or conflation of model specification and computation.
```

## 18.2 Introduction Revision Prompt

```text
Revise the introduction using the style profile. The introduction should begin with the inferential or scientific limitation, then give literature context thematically, then state the precise gap, then introduce the proposed method as a natural response, then list contributions and a roadmap. Avoid hype, algorithm-first framing, citation dumping, and unsupported novelty claims.
```

## 18.3 Mathematical Exposition Prompt

```text
Audit the mathematical exposition. Check whether all notation is defined before use, dimensions are stated where helpful, equations are introduced and interpreted, and data/latent variables/parameters/hyperparameters/priors/likelihoods/computational approximations are clearly distinguished. Provide a list of fixes and then revise the text conservatively.
```

## 18.4 Simulation Section Prompt

```text
Revise the simulation section so that it clearly states the goals, DGPs, parameter settings, competitors, metrics, replications, results, interpretation, and limitations. Ensure metrics align with the inferential target, especially calibration, coverage, sharpness, CRPS, pinball loss, or posterior predictive checks when relevant. Avoid leaderboard-style claims.
```

## 18.5 Codex Repository Prompt

```text
Read AGENTS.md and docs/academic-writing-style-profile.md. Then inspect the LaTeX manuscript files. Produce a style audit first; do not edit yet. Focus on structure, notation, mathematical exposition, computation/inference separation, simulation reporting, application reporting, claim support, discussion tone, and generic AI-style prose. Identify specific files and sections needing revision. Do not invent citations, change technical claims, or replace technical specificity with smoother but less informative prose.
```

## 18.6 Controlled Editing Prompt

```text
Using the style audit, revise only the requested section. Preserve LaTeX syntax, labels, citations, equation numbering, and notation. Make minimal but high-impact edits that improve clarity, statistical maturity, and alignment with the style profile. Remove generic AI-style prose only by replacing it with specific statistical objects, assumptions, approximations, metrics, or evidence-bounded statements. After editing, summarize changes and list remaining technical issues.
```

---

# 19. Suggested Repository Setup

Use this structure for manuscript repositories:

```text
repo-root/
  AGENTS.md
  STYLE_PROFILE.md
  manuscript/
    main.tex
    introduction.tex
    model.tex
    computation.tex
    simulation.tex
    application.tex
    discussion.tex
    references.bib
  docs/
    style_audits/
    revision_notes/
    simulation_protocol.md
    notation_table.md
  scripts/
    simulations/
    analysis/
  outputs/
    figures/
    tables/
```

## 19.1 Suggested `AGENTS.md`

```markdown
# Repository Instructions for AI Agents

Before editing any manuscript text, read `STYLE_PROFILE.md`.

This repository contains statistics manuscript materials. All writing and revisions must follow the style profile: precise, restrained, mathematically clear, statistically mature, technically rigorous, explanatory, and non-promotional.

## Manuscript editing rules

- Start from the statistical/scientific problem, not the algorithm.
- Preserve technical meaning, notation, citations, labels, and equation numbering unless the user asks for changes.
- Define notation before use and state dimensions where helpful.
- Introduce equations verbally and interpret them after display.
- Separate model specification from computation.
- Separate exact inference targets from approximate inference methods.
- Keep claims modest and supported by the manuscript evidence.
- Do not invent citations, results, theorems, datasets, or claims.
- Do not make prose merely smoother; replace generic AI-polished language with statistically specific statements about the relevant likelihood, prior, latent process, approximation, metric, assumption, or evidence.
- Do not copy wording from exemplar papers.

## Required workflow

1. Read `STYLE_PROFILE.md`.
2. Inspect the relevant `.tex` files.
3. Produce a style audit before major revisions.
4. Perform an anti-AI-prose pass for generic claims, stock transitions, vague adjectives, inflated novelty language, and evidence-free performance claims.
5. Ask only for necessary technical clarification.
6. Make controlled edits with a summary of changes.
7. Flag remaining unsupported claims, notation inconsistencies, technical ambiguities, and overstatements.
```

---

# 20. Revision Checklist

## 20.1 Whole Manuscript

- [ ] Does the title identify the statistical object without hype?
- [ ] Does the abstract include problem, gap, method, evaluation, and qualified conclusion?
- [ ] Does the introduction begin with the inferential or scientific limitation?
- [ ] Are contributions specific and non-promotional?
- [ ] Is related work organized thematically?
- [ ] Does the manuscript avoid generic AI-style prose by naming specific statistical objects, assumptions, approximations, metrics, and evidence?
- [ ] Is notation defined before use?
- [ ] Are dimensions stated for vectors, matrices, reservoirs, graph objects, or basis functions?
- [ ] Is every important equation introduced and interpreted?
- [ ] Is the observation model separated from the latent process?
- [ ] Are priors and hyperpriors clearly stated?
- [ ] Is computation separated from model specification?
- [ ] Are exact posterior targets distinguished from approximations?
- [ ] Are simulation goals, DGPs, competitors, metrics, and limitations stated?
- [ ] Does the application include data context, preprocessing, protocol, results, diagnostics, and limitations?
- [ ] Are figures and tables interpretable from captions?
- [ ] Are claims proportional to evidence?
- [ ] Are limitations specific?
- [ ] Is repeated explanation serving a new purpose, or should it be replaced by
  a shorter reminder or cross-reference?

## 20.2 Introduction

- [ ] Opens with the statistical/scientific problem.
- [ ] Identifies a precise limitation.
- [ ] Gives literature credit.
- [ ] States a specific gap.
- [ ] Introduces the method as a natural response.
- [ ] Lists contributions by methodological role.
- [ ] Ends with roadmap.

## 20.3 Model Section

- [ ] Defines observed data.
- [ ] Defines covariates/features.
- [ ] Defines latent states/processes.
- [ ] Defines likelihood.
- [ ] Defines priors and hyperpriors.
- [ ] Defines posterior target.
- [ ] Explains each equation.
- [ ] Avoids computation too early.

## 20.4 Computation Section

- [ ] States exact target.
- [ ] Explains why exact inference is difficult.
- [ ] Specifies approximation.
- [ ] Gives algorithm only after notation is defined.
- [ ] Reports diagnostics.
- [ ] States limitations of approximation.

## 20.5 Simulation Section

- [ ] States goals.
- [ ] Defines DGPs.
- [ ] Lists competitors.
- [ ] Lists metrics.
- [ ] Explains replications.
- [ ] Interprets results.
- [ ] States limitations.

## 20.6 Application Section

- [ ] Gives scientific context.
- [ ] Describes data.
- [ ] Describes preprocessing.
- [ ] States validation/forecast protocol.
- [ ] Presents quantitative metrics.
- [ ] Presents visual diagnostics.
- [ ] Interprets findings cautiously.
- [ ] States limitations.

---

# 21. Maintenance Rules for the Living Document

Update this document after each new upload batch.

For each new exemplar paper, add:

- title, authors, year, venue, and area;
- why it is stylistically relevant;
- abstract structure;
- introduction structure;
- related-work organization;
- notation style;
- model-building sequence;
- computation exposition;
- simulation/application reporting;
- figure/table/caption style;
- discussion tone;
- what to imitate structurally;
- what not to imitate.

For each user-authored draft, add:

- strengths to preserve;
- weaknesses to correct;
- comparison to exemplar corpus;
- notation issues;
- structure issues;
- unsupported claims;
- future AI revision rules.

Version updates should record:

```text
Version:
Date:
New sources:
New inferred preferences:
New recommendations:
Changed rules:
Open issues:
```

---

# 22. Compact “Gold Standard” Instruction for Any AI

Use this when context is limited:

```text
Write and revise this statistics manuscript in a precise, restrained, mathematically clear, statistically mature, and non-promotional style. Begin from the inferential/scientific problem, not the algorithm. Give existing literature credit, state the gap precisely, and introduce the method as a natural response. Define notation before use; state dimensions where useful; introduce equations verbally and interpret them after display. Separate data, latent variables, parameters, hyperparameters, priors, likelihoods, deterministic features, and computational approximations. Separate model specification from computation and exact inference from approximate inference. Do not make prose merely smoother; replace generic AI-style phrasing with statistical specificity about model components, assumptions, approximations, metrics, and evidence. Report simulations with goals, DGPs, competitors, metrics, results, interpretation, and limitations. Report applications with data context, preprocessing, evaluation protocol, results, diagnostics, interpretation, and limitations. Keep claims modest and supported. Flag unsupported claims, missing citations, notation inconsistencies, technical ambiguities, generic AI-style prose, and overstatements.
```
