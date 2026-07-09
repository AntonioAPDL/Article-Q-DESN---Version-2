# Initial Style Audit

## Manuscript Type

Hybrid Bayesian methodology and computational statistics manuscript for quantile forecasting with fixed deep echo state network features, asymmetric likelihoods, shrinkage priors, MCMC, and variational Bayes.

## Files Inspected

- `main.tex`: main article entry file. It contains the title, abstract, introduction, related work, notation/preliminaries, model, posterior inference, forecasting, posterior predictive synthesis, diagnostics, simulation, data placeholder, discussion placeholder, appendix, and bibliography.
- `qdesn-supplement.tex`: standalone supplement containing Q-DESN posterior targets, AL and exAL likelihoods, ridge and `rhs_ns` priors, MCMC updates, CAVI and VB-LD updates, ELBO terms, and forecasting and synthesis notes.
- `refs.bib`: bibliography database.
- `tables/qdesn_simulation_rmse.tex`, `tables/qdesn_simulation_pinball.tex`, `tables/qdesn_simulation_runtime.tex`: simulation tables included by `main.tex`.
- `scripts/build_qdesn_simulation_tables.R`: table-generation script.
- No `Makefile`, `latexmkrc`, `build.sh`, local class file, or local style file was found.

The repository-level instruction file named in the user request, `AGENTS.md`, was not present. The available instruction file is `AGENTS_academic_writing_snippet.md`, and the available style source is `Academic_Writing_Style_Profile_v0.2.md`.

## Main Article Structure

- Abstract.
- Section 1: Introduction, including an unnumbered related work subsection.
- Section 2: Notation and Preliminaries, with DESN and exAL definitions.
- Section 3: Model Overview, including Q-DESN likelihood and priors.
- Section 4: Posterior Inference, including MCMC and VB-LD.
- Section 5: Forecasting.
- Section 6: Posterior Predictive Synthesis.
- Section 7: Model Selection and Diagnostics.
- Section 8: Simulation.
- Section 9: Data, currently a placeholder.
- Section 10: Discussion, currently a placeholder.
- Appendix: Full conditionals for Q-DESN.

## Supplement Structure

- Abstract.
- Scope and relation to the main article.
- Distributional conventions.
- DESN feature map and static readout.
- Likelihoods, priors, and complete-data joint distributions.
- MCMC full conditionals.
- Mean-field CAVI and Laplace-Delta VB.
- ELBO decomposition.
- Forecasting and multi-quantile synthesis.

## Where the Draft Already Matches the Style Profile

- The model section treats reservoir features as deterministic after construction and separates the learned readout from fixed random reservoir weights.
- The notation section defines most recurring symbols and includes a notation table.
- The prior section gives statistical motivation for the regularized horseshoe readout prior and distinguishes the intercept from shrinkage on reservoir features.
- The inference section separates MCMC from VB-LD and identifies the non-conjugate `(sigma, gamma)` block.
- The simulation section states the DGP, quantile centering, competing model classes, metrics, and runtime comparison.
- The supplement is mathematically explicit and already treats the posterior target, algorithms, and ELBO as derivations rather than implementation notes.

## Deviations From the Style Profile

- The abstract begins from the method need and contains broad phrases such as "demonstrate accuracy and calibration"; it should start from the forecasting problem and state evidence more cautiously.
- The introduction is reasonably close to the target style but still presents contributions in a dense paragraph and can better separate problem, gap, construction, inference, and evaluation.
- The related work subsection is organized partly as a citation sequence. It should be more thematic and should more clearly state the remaining gap after prior work.
- The main model section presents the augmented likelihood immediately; it should first state the posterior/inferential target and distinguish the exAL working likelihood from computation.
- The posterior inference section should state the exact posterior target before discussing MCMC and VB-LD.
- The VB subsection contains a generic Laplace-Delta derivation that is useful but somewhat detached from the Q-DESN target; it needs a stronger bridge between exact target and approximation.
- Forecasting and synthesis sections need slightly more cautious language around post-processing and independent quantile fits.
- The data/application section is empty and cannot support application claims in the abstract or introduction.
- The discussion section is empty and should at least record current limitations if no application has been written.

## Missing Or Weak Problem Motivation

- The first article sentence identifies probabilistic forecasts under asymmetric loss but could more directly connect nonlinear dependence, high-dimensional reservoir readouts, and quantile-specific uncertainty.
- The application motivation is weak because no real-data application is currently described.

## Missing Or Weak Gap Statements

- The current gap is present but can be sharpened: reservoir methods provide scalable nonlinear feature maps, while many quantile ESN approaches do not combine a quantile-anchored asymmetric likelihood, high-dimensional Bayesian shrinkage, and posterior inference for readout uncertainty.
- The difference between Q-DESN and calibrated quantile ESNs should be framed as a modeling and inference distinction, not as a blanket superiority claim.

## Unsupported Or Overstrong Claims

- "Simulation and real-data studies demonstrate accuracy and calibration" is unsupported because the data/application section is not written.
- "Flexible and fast Bayesian framework" is partly supported by runtime tables, but should be qualified as an empirical finding under the simulated grid.
- "Enabling calibration and uncertainty assessment" should be phrased as "providing posterior summaries and calibration diagnostics" unless calibration results are reported.
- "Most reliable specification" in the simulation conclusion is slightly too broad for a single reproducible dynamic root; it should be tied to the reported oracle-path recovery design.

## Notation Inconsistencies

- The main article uses `\lambda(\gamma)=C(\gamma)|\gamma|`; the supplement uses `D_gamma = C_gamma |\gamma|`. This is acceptable but should be verbally connected if both documents are distributed together.
- The main article uses `\RHS{}` for regularized horseshoe, whereas the supplement often uses `\texttt{rhs_ns}`. This distinction is useful because `rhs_ns` denotes the computational construction, but it should be stated explicitly.
- The appendix in `main.tex` duplicates some material from the supplement. It should be kept brief and defer to the supplement where possible.

## Equations Needing Better Verbal Setup Or Interpretation

- The posterior target should be introduced before Algorithm 1 in the inference section.
- The variational factorization should be introduced as an approximation to a named exact posterior.
- The synthesis quantile interpolation should be described as post-processing rather than a jointly coherent multi-quantile posterior.
- The appendix full conditionals are technically useful, but the main article should not read as if the appendix is the primary derivation now that the supplement exists.

## Model Specification And Computation Conflation

- The Q-DESN model subsection uses the latent Gaussian representation directly. This is mathematically valid, but the text should clarify that the augmentation is a computational representation of the exAL likelihood.
- The prior section mixes statistical prior motivation with Gibbs-convenience motivation. The distinction is mostly clear, but it should be sharpened where the Nishimura-Suchard construction is introduced.

## Exact Inference And Approximate Inference Conflation

- The VB section needs clearer language that VB-LD approximates the exact posterior target and uses Delta-method approximations only for smooth functions of `(sigma, gamma)`.
- Posterior predictive summaries from VB-LD should be described as approximate posterior predictive summaries.

## Simulation-Reporting Weaknesses

- The simulation section has DGP, competitors, metrics, and results, but it needs clearer goal statements and a more explicit limitation statement about using one reproducible root rather than repeated Monte Carlo replications.
- Calibration is mentioned elsewhere, but the simulation tables mainly report RMSE, check loss, and runtime. The text should not imply full distributional calibration unless coverage or calibration metrics are reported.
- Table captions are generally good, though the pinball caption relies too much on the RMSE caption.

## Application-Reporting Weaknesses

- The data/application section is empty. The main article should not claim a completed application until data context, preprocessing, validation protocol, metrics, results, and limitations are provided.

## Figure/Table/Caption Weaknesses

- The notation table is helpful but could include dimensions/supports more explicitly.
- Simulation table captions are informative, but the pinball table should explicitly state the metric rather than referring almost entirely to the RMSE table.
- No figures are present, so figure-caption style cannot be assessed.

## Discussion And Limitation Weaknesses

- The discussion section is a placeholder. It should summarize the methodological contribution, interpret what the simulation supports, state limitations, and identify concrete future work.
- Limitations should include fixed random reservoir features, sensitivity to reservoir hyperparameters and seeds, independent quantile-specific fitting, approximation quality of VB-LD, and the absence of a completed application section in the current draft.

## Prioritized Revision Plan

1. Revise the abstract to follow problem, gap, construction, inference, evidence, and modest conclusion, removing unsupported application claims.
2. Revise the introduction and related work to be more thematic, restrained, and explicit about the remaining statistical gap.
3. Add stronger verbal setup around the exact posterior target and the role of augmentation in the model and inference sections.
4. Clarify VB-LD as an approximation to the exact posterior and identify which uncertainty is approximate.
5. Improve simulation framing, table captions, and interpretation, especially the limitation that results are from one reproducible dynamic root.
6. Replace empty Data and Discussion placeholders with honest draft-status text and substantive methodological limitations without inventing an application.
7. Add orientation and cross-references in the supplement where it can better support the main article.
