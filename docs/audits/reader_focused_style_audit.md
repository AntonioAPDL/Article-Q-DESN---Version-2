# Reader-Focused Style Audit

## Scope

This audit was prepared before manuscript edits for the reader-proof pass requested after the anti-AI-prose update to `Academic_Writing_Style_Profile_v0.2.md`. I inspected the local style-governance files, the main article, the supplement, the bibliography, and the simulation tables.

## Files Inspected

- `Academic_Writing_Style_Profile_v0.2.md`
- `AGENTS_academic_writing_snippet.md`
- `docs/audits/initial_style_audit.md`
- `docs/revision_logs/initial_style_revision_log.md`
- `main.tex`
- `qdesn-supplement.tex`
- `refs.bib`
- `tables/qdesn_simulation_rmse.tex`
- `tables/qdesn_simulation_pinball.tex`
- `tables/qdesn_simulation_runtime.tex`

No `Makefile`, `latexmkrc`, or `build.sh` was present in the repository root.

## Main Article Structure

- Abstract.
- Section 1: Introduction, with an unnumbered related-work subsection.
- Section 2: Notation and Preliminaries, including the DESN feature map and exAL representation.
- Section 3: Model Overview, including the Q-DESN readout likelihood and priors.
- Section 4: Posterior Inference, including MCMC and VB-LD.
- Section 5: Forecasting.
- Section 6: Posterior Predictive Synthesis.
- Section 7: Model Selection and Diagnostics.
- Section 8: Simulation.
- Section 9: Data, currently a draft-status placeholder.
- Section 10: Discussion.
- Appendix: compact full conditionals.

## Supplement Structure

- Abstract.
- Scope and relation to the main article.
- Distributional conventions.
- DESN feature map and static readout.
- Q-DESN likelihoods, priors, and complete-data joint distributions.
- MCMC full conditionals.
- Mean-field CAVI and Laplace-Delta VB.
- ELBO decomposition.
- Forecasting and multi-quantile synthesis.

## Where the Draft Already Matches the Updated Style Profile

- The manuscript starts from conditional quantile forecasting rather than from a generic neural-network claim.
- DESN features are repeatedly described as fixed after construction and washout.
- The model and supplement distinguish observed responses, deterministic reservoir features, readout parameters, likelihood parameters, auxiliary variables, shrinkage scales, and computational approximations.
- The simulation section states the DGP, target quantiles, competitors, metrics, effective training sizes, and the single-root limitation.
- The application section avoids unsupported empirical claims because no real-data application is currently included.
- The supplement is mathematically organized around posterior targets, MCMC, CAVI and VB-LD, ELBO, and forecasting.

## Remaining Prose and Anti-AI-Prose Issues

- `main.tex:88`: "scalable nonlinear dynamic features" is acceptable but slightly generic. The sentence should state the mechanism: fixed recurrent random features that reduce the fitted parameter burden to the readout layer.
- `main.tex:210` and `main.tex:260`: the repeated "Nevertheless" transitions read mechanically and can be replaced by direct logical transitions.
- `main.tex:260`: the DESN subsection opening is split awkwardly across sentences and does not fully state that the section defines a deterministic feature map used later as a design matrix.
- `main.tex:382`: the phrase "conditional Normal form used for inference in Q-DESN is as follows" is a generic equation introduction and contains a Unicode dash in `Q-DESN`. It should name the role of the representation and use consistent TeX dash notation.
- `main.tex:647--658`: the VB-LD description turns into a generic nonconjugate-VB sketch. It should be tied more directly to the Q-DESN scale-asymmetry block and should state that the displayed updates define the approximation used by the algorithm.
- `main.tex:936--948`: runtime and performance language is mostly evidence-bounded, but phrases such as "substantial" and "more practical" should remain tied to the reported validation grid and reservoir size.
- `main.tex:1001--1004`: "scalable diagnostics" is generic future-work language and should be replaced by a more specific diagnostic target for VB-LD approximation error at large reservoir dimensions.

## Unsupported or Overstrong Claims

- No current article text claims a completed real-data application. This should be preserved.
- The simulation interpretation is appropriately restricted to the controlled single-root design, but the prose should continue to avoid implying repeated Monte Carlo evidence.
- "Calibration" appears in the abstract and diagnostics discussion as a model-assessment objective. The simulation tables do not report empirical coverage or PIT diagnostics, so any calibration claim must remain prospective or diagnostic rather than a reported result.

## Notation and Definition Issues

- Important acronyms are mostly expanded at first use. The remaining issue is local: in the VB subsection, CAVI and ELBO are expanded after the algorithmic discussion begins, so the prose should make their role clear before the algorithm caption.
- The main article uses `\lambda(\gamma)` for the exAL shift coefficient and the supplement uses `D_\gamma`; this is already explained in the supplement. The main text can continue to refer to the supplement by section number rather than trying to define both symbols in the article.
- The synthesis equation uses label `synth_quantile`; the label should be made consistent with the `eq:` convention because the surrounding manuscript uses equation-style references.

## Equation Exposition Issues

- The DESN hierarchy is introduced with useful dimensional detail, but the opening can better tell the reader that Eq. (2.1) defines a deterministic feature map conditional on reservoir draws.
- The exAL stochastic representation should be introduced as the augmentation that yields the conditional Gaussian likelihood, not merely as a conditional Normal "form."
- The generic Laplace-Delta equations in the VB subsection should be introduced as the block approximation for nonconjugate coordinates, with the CAVI update interpreted immediately after display.
- The supplement's major mathematical sections are clear, but Section S3 and Section S4 can benefit from short orientation sentences stating exactly what is inherited from the main article and what is being derived.

## Model Specification vs. Computation

- The main article generally separates the marginal exAL working likelihood from the latent Gaussian augmentation. Minor improvement is needed in the exAL subsection so the augmentation is framed as computational.
- The supplement complete-data targets correctly avoid double-counting latent variables and inverse-gamma scale augmentation. No mathematical correction is indicated from this style pass.

## Exact Inference vs. Approximate Inference

- MCMC is presented as an augmented sampler for the posterior target.
- VB-LD is described as an approximation, but the general explanation should explicitly name which expectations are exact under conjugate factors and which are approximated with Laplace-Delta moments.
- Forecasting language should continue to distinguish posterior predictive draws from variational predictive approximations.

## Cross-Reference Issues

- Article-to-supplement references exist, but some are hard-coded as "Section S4" or "Section S8." This is acceptable for a standalone supplement, but wording should be specific about what the reader will find there.
- Supplement-to-article references are useful in the scope section. The forecasting section can also mention that it supports the article's posterior predictive synthesis section.
- The main synthesis equation label should be changed from `synth_quantile` to `eq:synth_quantile`.

## Figure, Table, and Formatting Issues

- No figure files are present.
- Table captions are already self-contained. The runtime caption can be slightly more explicit that the values are medians over the fitted validation grid, not theoretical complexity.
- This earlier pass found a "Working Draft" title line. A later navigation and
  title pass removed that line from the manuscript title.
- The article contains draft note macros with `\notestrue`; no `\TODO` or `\NOTE` instances were found in manuscript text during inspection, so this is not currently a visible issue.

## Simulation and Application Reporting

- Simulation reporting is unusually clear for the current draft: it states the DGP, model grid, metrics, and single-root limitation.
- The main remaining risk is claiming calibration without coverage/PIT results. The current application placeholder and discussion are appropriately cautious.
- The application section should remain explicit that the real-data analysis has not yet been added.

## Prioritized Revision Plan

1. Tighten the abstract and opening paragraphs where "scalable" or "uncertainty quantification" could sound generic, replacing them with mechanism-level statements.
2. Improve the Notation/DESN and exAL subsection openings so equations are introduced by their statistical role.
3. Rewrite the VB-LD explanatory paragraph to be Q-DESN-specific and to distinguish exact conjugate updates from Laplace-Delta approximations.
4. Make synthesis and future-work language more precise, especially around independent quantile fits, monotone post-processing, and VB-LD diagnostics.
5. Add short orientation paragraphs to the supplement sections that currently move quickly into equations.
6. Update table captions or notes only where they can add evidence-bounded context without verbosity.
7. Compile both `main.tex` and `qdesn-supplement.tex`, inspect warnings, clean generated artifacts, and document the result.
