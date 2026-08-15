# Reader-Focused Revision Log

## Files Changed

- `docs/audits/reader_focused_style_audit.md`
- `docs/revision_logs/reader_focused_revision_log.md`
- `main.tex`
- `qdesn-supplement.tex`
- `tables/qdesn_simulation_runtime.tex`

## Main Prose Edits

- Revised the abstract to replace the generic phrase "scalable nonlinear dynamic features" with a mechanism-level description of fixed random dynamic features and a learned readout.
- Reworked the notation opening so it explains why notation must be fixed across ESN, quantile-likelihood, and shrinkage components.
- Rewrote the DESN subsection opening to state that the DESN construction defines the deterministic feature map used later as the Q-DESN design matrix.
- Replaced generic transition language in the model-selection section with a statement that reservoir hyperparameters determine the fixed feature map used by the readout.

## Anti-AI-Prose Corrections

- Removed generic or mechanically polished phrasing where it did not name a statistical object.
- Replaced "facilitates posterior inference" with a specific statement that the augmented likelihood and shrinkage hierarchy yield a partially Gibbs sampler.
- Replaced generic future-work language about "scalable diagnostics" with the more specific target of diagnosing VB-LD approximation error at reservoir dimensions where MCMC is costly.
- Confirmed that the remaining anti-AI-prose scan found no manuscript prose hits for the main stock phrases in the updated style profile; the only match was the LaTeX macro name `\ensuremath`.

## Notation and Definition Edits

- Changed the synthesis equation label from `synth_quantile` to `eq:synth_quantile` and updated the corresponding reference.
- Replaced an inconsistent Unicode dash in `Q-DESN` with TeX-compatible `Q--DESN`.
- Preserved the distinction between the main article's \(\lambda(\gamma)\) notation and the supplement's \(D_\gamma\) notation.

## Equation-Exposition Edits

- Reframed the exAL stochastic representation as the conditional Gaussian augmentation used for Q-DESN posterior computation.
- Rewrote the VB-LD explanation so the generic nonconjugate block notation is explicitly tied to the Q-DESN \((\sigma,\gamma)\) scale-asymmetry block.
- Clarified that Gaussian, GIG, truncated-Normal, and inverse-gamma variational factors remain closed-form, while smooth expectations involving \((\sigma,\gamma)\) use Laplace-Delta approximations.

## Cross-Reference Edits

- Updated the posterior predictive synthesis equation label and reference.
- Preserved existing article-to-supplement references to Sections S4 and S8 because those hard-coded references match the standalone supplement numbering.
- Added supplement orientation text that links forecasting and synthesis derivations back to the corresponding main-article sections.

## Formatting and Caption Edits

- Revised the runtime table caption to state that the reported runtimes are empirical medians over the fitted validation grid and apply to the fitted reservoir specifications in this design.
- No figure captions were revised because no figure files are present.

## Simulation and Application Reporting Edits

- Preserved the single-root simulation limitation and avoided introducing repeated Monte Carlo language.
- Preserved the draft-status data section and did not add any applied-performance claim.
- Kept calibration language tied to diagnostics or future application reporting rather than presenting calibration as an empirical result from the current tables.

## Supplement Edits

- Added section-level orientation paragraphs for distributional conventions, the DESN feature map, joint distributions, coefficient priors, MCMC, CAVI and VB--LD, and forecasting and synthesis.
- Clarified that the MCMC conditionals are exact conditional on the complete-data joint except for the nonconjugate joint exAL \((\sigma,\gamma)\) sampling step.
- Clarified that the supplement's forecasting synthesis is post-processing for independently fitted quantile levels, not a joint multi-quantile posterior model.

## Mathematical or Technical Changes

- No likelihood, prior, full conditional, variational update, ELBO term, or algorithmic target was changed.
- The edits were prose, orientation, labeling, and caption changes only.

## Unsupported Claims That Remain

- No completed real-data application is included, and the manuscript continues to state this explicitly.
- Simulation claims remain restricted to the controlled single-root dynamic design.
- VB-LD approximation quality remains a diagnostic issue, as stated in the discussion.

## Citations That Appear Missing

- None. The final BibTeX and LaTeX runs resolved citations in both the article and supplement.

## Build Commands and Results

No repository build script, `Makefile`, `latexmkrc`, or `build.sh` was found. The main article was built with:

```text
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

The final extra `pdflatex` pass was run because labels changed after renaming the synthesis equation label. The final warning scan of `main.log` and `main.blg` found no unresolved references, undefined citations, overfull boxes, fatal errors, bibliography issues, multiply defined labels, or hyperref warnings.

The supplement was built with:

```text
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
bibtex qdesn-supplement
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
```

The final warning scan of `qdesn-supplement.log` and `qdesn-supplement.blg` found no unresolved references, undefined citations, overfull boxes, fatal errors, bibliography issues, multiply defined labels, or hyperref warnings.

Generated LaTeX build artifacts were removed after validation.

## Residual Uncertainties

- The manuscript is still labeled as a working draft and does not include a completed real-data application.
- The simulation study does not quantify repeated-data-set Monte Carlo variability.
- The VB-LD approximation should be checked against MCMC in smaller settings when applied to new data or larger reservoir configurations.

## 2026-05-10 Abstract and Introduction Claim Audit Pass

### Files Changed

- `main.tex`
- `refs.bib`

### Main Prose and Factual-Claim Edits

- Replaced the abstract opening claim that probabilistic forecasting "requires conditional quantiles and predictive distributions" with a decision-specific statement about asymmetric loss, tail behavior, and prediction intervals.
- Reframed Q--DESN as a Bayesian quantile readout model conditional on fixed DESN features rather than as a broad forecasting framework.
- Qualified the fixed-reservoir statement by conditioning on the generated reservoir, architecture, random seed, scaling constants, and washout convention.
- Defined exAL in the introduction as the paper's notation for the quantile-fixed generalized asymmetric Laplace construction of Yan, Zheng, and Kottas.
- Added an explicit working-likelihood caveat: exAL defines the Bayesian readout target used for inference but is not assumed to be the true data-generating error distribution.
- Replaced "control the readout coefficients" with "regularize the readout coefficients."
- Changed "develop two posterior computation routes" to "derive two posterior computation schemes" to avoid overclaiming algorithmic novelty.
- Narrowed the simulation claim in the abstract to table-supported findings: regularized horseshoe shrinkage lowers RMSE relative to ridge in matched Q--DESN comparisons, VB--LD has lower empirical runtime for the fitted reservoir sizes, and check-loss comparisons are mixed.

### Literature and Citation Edits

- Added foundational citations for probabilistic forecasting, proper scoring rules, quantile optimality, quantile regression, and the original ESN report.
- Revised the related-work section so each citation group supports a specific methodological role: ESN/reservoir construction, probabilistic reservoir modeling, Bayesian quantile regression, generalized asymmetric likelihoods, quantile ESN methods, and monotone quantile post-processing.
- Replaced the unsupported statement that existing quantile ESN approaches "typically rely on quantile loss functions or working-likelihood formulations" with specific descriptions of quantile-regression ESN ensembles and calibrated DESN forecasts based on penalized quantile regression.
- Replaced "ESNs were introduced by Jaeger (2007)" with a historically safer statement citing Jaeger's 2001 ESN report and the later 2007 summary.

### Technical Changes

- No likelihood, prior, full conditional, variational update, ELBO term, simulation table, or algorithm was changed.
- The edits affect prose, citation support, and claim calibration in the abstract, introduction, and related-work section.

### Build Commands and Results

The main article was built with:

```text
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

The final extra `pdflatex` pass was run because labels changed after the bibliography expansion. The final warning scan of `main.log` and `main.blg` found no unresolved references, undefined citations, overfull boxes, fatal errors, bibliography issues, multiply defined labels, or hyperref warnings.

The supplement was rebuilt because it shares `refs.bib`:

```text
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
bibtex qdesn-supplement
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
```

The final warning scan of `qdesn-supplement.log` and `qdesn-supplement.blg` found no unresolved references, undefined citations, overfull boxes, fatal errors, bibliography issues, multiply defined labels, or hyperref warnings.

### Residual Uncertainties

- The simulation study still uses a single-root dynamic design, so empirical claims remain design-specific rather than repeated-Monte-Carlo claims.
- The manuscript still lacks a completed real-data application.
- The exAL working-likelihood caveat is now explicit, but posterior calibration under misspecification remains a methodological limitation to discuss when broader empirical evidence is added.

## 2026-05-10 Scope Reframing Pass from External Assessment

### Files Changed

- `main.tex`
- `qdesn-supplement.tex`
- `refs.bib`

### Main Scope and Framing Edits

- Changed the title to foreground the primary methodological scope: Q--DESN as Bayesian quantile readouts for fixed deep echo state network features.
- Recentered the abstract and introduction on conditional quantile forecasting and Bayesian quantile readout inference, with probabilistic forecasting retained as motivation and evaluation context rather than the main identity of the paper.
- Revised the contribution paragraph to separate the model, shrinkage prior comparison, computation, multi-quantile synthesis, and controlled simulation evidence.
- Rephrased VB--LD as a practical implementation shorthand based on non-conjugate variational ideas rather than as a newly developed standalone method.

### Working-Likelihood and Uncertainty Edits

- Strengthened the exAL working-likelihood caveat: posterior summaries are conditional on the fixed reservoir and working likelihood, and calibration under misspecification is an empirical diagnostic rather than an automatic consequence of the model.
- Added citations for Gibbs sampling in Bayesian quantile regression and for known coverage and standard-error issues under asymmetric-Laplace working likelihoods.

### Forecasting and Synthesis Edits

- Renamed the forecasting section to emphasize working-likelihood forecasts.
- Replaced broad posterior-predictive wording with model-based forecast distribution wording conditional on the fitted working likelihood.
- Renamed the synthesis section to multi-quantile synthesis.
- Replaced the earlier interpolation of off-target exAL posterior predictive quantiles with interpolation of fitted target-quantile readout summaries \((\tau_i,\hat q_{i,t})\). This keeps synthesis aligned with the quantile-targeting role of the working likelihood.
- Updated the supplement's synthesis description to match the main article and to describe synthesis as a monotone estimated predictive quantile function, not a joint multi-quantile posterior model.

### Simulation and Application Edits

- Added a draft TODO to decide whether to extend the simulation with repeated data-generating roots, multiple reservoir seeds, a simple normal dynamic linear model, and a simple non-Bayesian ESN baseline.
- Replaced promotional simulation language such as "sharply improves" with metric-specific language.
- Updated the data placeholder to state that the planned real-data application will focus on climate or environmental forecasting and should report quantile and interval scores, coverage diagnostics, and sharpness summaries.

### Technical Changes

- The main conceptual technical edit is the multi-quantile synthesis target: synthesis now uses fitted target-quantile summaries instead of off-target quantiles from the exAL working likelihood.
- No MCMC full conditional, VB update, ELBO term, likelihood kernel, or simulation table was changed.

### Build Commands and Results

The main article was built with:

```text
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

The final extra `pdflatex` pass was run because labels changed after
renaming the synthesis and forecasting sections. The final warning scan of
`main.log` and `main.blg` found no unresolved references, undefined
citations, overfull boxes, fatal errors, bibliography issues, multiply
defined labels, or hyperref warnings.

The supplement was rebuilt because the synthesis prose and shared
bibliography changed:

```text
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
bibtex qdesn-supplement
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
```

The final warning scan of `qdesn-supplement.log` and
`qdesn-supplement.blg` found no unresolved references, undefined citations,
overfull boxes, fatal errors, bibliography issues, multiply defined labels,
or hyperref warnings.

### Residual Uncertainties

- The final simulation design still needs a decision on repeated roots, reservoir seeds, and added baselines.
- The planned climate and environmental application remains to be implemented.
- At the time of this pass, the manuscript still carried draft TODO notes and a
  Working Draft title line. A later navigation and title pass removed the title
  line.

## 2026-05-10 Full Style-Profile Pass

### Files Changed

- `main.tex`
- `qdesn-supplement.tex`
- `docs/audits/full_manuscript_style_audit.md`

### Main Style Edits

- Added a focused style audit before the revision pass, following the repository workflow.
- Set the draft-note toggle to `\notesfalse` so source TODOs remain available but do not appear in the compiled manuscript.
- Revised the abstract so it states the problem, limitation, Q--DESN construction, computation, synthesis, and simulation evidence in a restrained sequence.
- Reworked the introduction opening so the statistical target, conditional quantile forecasting, precedes the reservoir construction.
- Replaced broad uncertainty language with conditional, working-likelihood language.
- Replaced remaining generic or promotional phrasing, including "strongest RMSE values," "computational separation," "most useful," and "enforces strong shrinkage."

### Mathematical and Expository Edits

- Improved the notation and DESN sections by breaking dense dimension statements into displayed blocks.
- Qualified the AL and exAL comparison so it describes skewness restrictions rather than making an unsupported calibration claim.
- Clarified that the lack of a closed-form normalized joint posterior is due
  to the non-conjugate exAL scale--asymmetry block, not to the ridge or
  regularized-horseshoe readout prior, whose augmented blocks retain
  closed-form conditional updates.
- Added an MCMC-reporting sentence noting trace plots, effective sample sizes,
  and monitoring of the \((\sigma,\gamma)\) update, while keeping VB--LD
  comparisons separate as approximation checks rather than MCMC diagnostics.

### Simulation and Application Edits

- Rephrased simulation interpretation to stay within the single-root controlled design.
- Replaced leaderboard-style simulation language with metric-specific wording.
- Converted the placeholder data section into a planned climate and environmental application section and removed the empty real-data subsection.
- Split the future-work paragraph into specific directions: joint quantile modeling, layer-structured shrinkage, reservoir sensitivity, VB--LD diagnostics, and the planned application protocol.

### Supplement Alignment

- Updated the supplement roadmap to describe working-likelihood forecast simulation rather than posterior predictive simulation.
- Replaced "controls the high-dimensional readout" with "regularizes the high-dimensional readout" in the coefficient-prior section.

### Technical Changes

- No likelihood, prior, full conditional, variational update, ELBO term, simulation table, or algorithm was changed.
- The changes are style, scope, formatting, and exposition changes, with the previous synthesis correction preserved.

### Build Commands and Results

The main article was built with:

```text
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

The final extra `pdflatex` pass was run because labels changed after the
style edits. The final warning scan of `main.log` and `main.blg` found no
unresolved references, undefined citations, overfull boxes, fatal errors,
bibliography issues, multiply defined labels, or hyperref warnings.

The supplement was rebuilt because its roadmap and coefficient-prior prose
changed:

```text
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
bibtex qdesn-supplement
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
```

The final warning scan of `qdesn-supplement.log` and
`qdesn-supplement.blg` found no unresolved references, undefined citations,
overfull boxes, fatal errors, bibliography issues, multiply defined labels,
or hyperref warnings.

### Residual Uncertainties

- The article is still a working draft because the climate and environmental application is not yet implemented.
- The simulation still has an in-source TODO about repeated roots, reservoir seeds, and added baselines; it is hidden from the compiled PDF by `\notesfalse`.

## 2026-05-10 Reviewer-Read Pass

### Files Changed

- `main.tex`
- `qdesn-supplement.tex`
- `docs/audits/reviewer_reading_audit.md`

### Reader-Proof and Style Edits

- Added a fresh-reader audit focused on reviewer-facing clarity, notation, and
  article-supplement consistency.
- Clarified the abstract by defining the Laplace--Delta variational
  approximation acronym as VB--LD at first use.
- Revised exAL descriptions to name mode, skewness, and tail-shape flexibility
  rather than only skewness and tails.
- Replaced the generic related-work transition about reservoir developments
  with the specific role those developments play in Q--DESN: fixed recurrent
  features with Bayesian modeling on the readout.

### Notation and Definition Edits

- Replaced the variational factorization `q(\Theta,\vect z)` with
  `q(\Theta,\vect a)`, where `\vect a=(\vect v,\vect s)`, to avoid conflict
  with `\vect z_t` for exogenous covariates.
- Replaced the Q--DESN likelihood display placeholder `y_t\mid(\cdot)` with
  explicit conditioning on `\vect\beta,\sigma,\gamma,s_t,v_t,\vect x_t`.
- Clarified that `\vect u_t` contains response lags and exogenous covariates.
- Added a note that `\zeta^2` is omitted from the parameter collection when the
  slab scale is fixed.
- Removed the simulation notation conflict in which `m=50` was used for random
  readout features even though `m` already denotes the number of response lags.

### Formatting and Cross-Reference Edits

- Aligned the supplement title and abstract with the article's current framing:
  Q--DESN as Bayesian quantile readouts for fixed deep ESN features.
- Made thinning optional in both MCMC algorithm descriptions rather than
  implying it is required.

### Technical Changes

- No likelihood, prior, full conditional, variational update, ELBO term, or
  simulation table value was changed.
- The changes are reader-proofing, notation clarification, source-level
  formatting, and article-supplement consistency edits.

### Build Commands and Results

The main article was built with:

```text
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

The supplement was built with:

```text
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
bibtex qdesn-supplement
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
```

Final warning scans of `main.log`, `main.blg`, `qdesn-supplement.log`, and
`qdesn-supplement.blg` found no unresolved references, undefined citations,
overfull boxes, fatal errors, bibliography issues, multiply defined labels, or
hyperref warnings.

## 2026-05-10 Ridge Default and RHS Shrinkage Clarification

### Files Changed

- `main.tex`
- `qdesn-supplement.tex`

### Prior-Specification Edits

- Clarified in the abstract and introduction that ridge is the default
  coefficient prior for Q--DESN readout weights.
- Reframed the regularized horseshoe as the adaptive global-local shrinkage
  alternative rather than the default coefficient prior.
- Added the default ridge slope-prior variance \(\kappa_\beta^2\) to the main
  notation table and stated the default Gaussian ridge prior explicitly in the
  prior section.
- Revised the RHS subsection so the Nishimura--Suchard-style product
  representation is described as the device that preserves efficient
  inverse-gamma updates for the local and global scale parameters.
- Updated the supplement abstract, roadmap, and coefficient-prior section to
  distinguish the default ridge prior from the \texttt{rhs\_ns} shrinkage
  alternative.

### Technical Changes

- No likelihood, posterior target, MCMC full conditional, CAVI update, ELBO
  expression, or simulation value was changed.
- The edits clarify prior roles and computation for the existing ridge and
  RHS specifications.

### Build Commands and Results

- Ran `pdflatex -interaction=nonstopmode -halt-on-error main.tex`, `bibtex main`,
  and three subsequent `pdflatex` passes on `main.tex`. The final pass completed
  successfully and produced a 23-page main article.
- Ran `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex`,
  `bibtex qdesn-supplement`, and two subsequent `pdflatex` passes on
  `qdesn-supplement.tex`. The final pass completed successfully and produced a
  16-page supplement.
- Scanned `main.log`, `main.blg`, `qdesn-supplement.log`, and
  `qdesn-supplement.blg`; no undefined references, undefined citations, overfull
  boxes, fatal errors, bibliography errors, multiply defined labels, or hyperref
  warnings were found.

### Residual Uncertainties

- The manuscript remains a working draft because the planned climate or
  environmental application is not yet implemented.
- Reviewers may still ask for repeated simulation roots, additional reservoir
  seeds, and the proposed simple baselines. The text now keeps the single-root
  scope explicit.

## 2026-05-10 Self-Referential Prose Pass

### Files Changed

- `main.tex`
- `qdesn-supplement.tex`
- `Academic_Writing_Style_Profile_v0.2.md` (gitignored local style-governance file)
- `AGENTS_academic_writing_snippet.md` (gitignored local style-governance file)

### Style-Governance Edits

- Added a new rule to the style profile on self-referential
  "paper-about-paper" framing.
- Added examples that replace phrases such as "the inferential target of this
  paper" and "this supplement records" with sentences that begin from the
  statistical object, model component, or posterior target.
- Added diagnostic checklist items asking whether a sentence or paragraph talks
  about the paper, article, work, supplement, or document when it could instead
  name the modeling problem or statistical object.
- Added the same rule in compact form to the local agent-writing snippet.

### Manuscript Edits

- Replaced the abstract opening with an object-level statement about nonlinear
  dynamic data and conditional quantiles.
- Replaced the introduction opening so it begins from the need for
  distributional summaries beyond the mean rather than from what the paper
  considers.
- Rewrote the contribution paragraph to reduce procedural "we" phrasing while
  preserving the contribution structure.
- Replaced "throughout this paper" in the prior section with a direct reference
  to Q--DESN readout fits.
- Replaced self-conscious supplement openings with statements about the
  Q--DESN posterior target, fixed reservoir design matrix, and derivations.

### Build Commands and Results

The main article was rebuilt with:

```text
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

The supplement was rebuilt with:

```text
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
bibtex qdesn-supplement
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
```

Final warning scans of `main.log`, `main.blg`, `qdesn-supplement.log`, and
`qdesn-supplement.blg` found no unresolved references, undefined citations,
overfull boxes, fatal errors, bibliography issues, multiply defined labels, or
hyperref warnings.

## 2026-05-10 VB--LD Scale--Asymmetry Wording Clarification

### Files Changed

- `main.tex`
- `qdesn-supplement.tex`

### Prose and Notation Edits

- Replaced the phrase "non-conjugate exAL moments" with wording that identifies
  the actual approximation target: smooth expectations involving the
  non-conjugate exAL scale--asymmetry block \((\sigma,\gamma)\).
- Clarified that the shrinkage-scale variational factors retain closed-form
  updates under the product representation, rather than being part of the
  Laplace--Delta block.
- Replaced "Laplace--Delta moments" with "Laplace--Delta approximations to
  smooth expectations" where the older wording could be confused with moments
  of the exAL observation distribution.

### Technical Changes

- No likelihood, prior, posterior target, MCMC update, CAVI update, ELBO
  expression, or simulation value was changed. The edits only clarify which
  variational expectations are approximated by the Laplace--Delta step.

### Build Commands and Results

- Ran `pdflatex -interaction=nonstopmode -halt-on-error main.tex`, `bibtex main`,
  and two subsequent `pdflatex` passes on `main.tex`. The final pass completed
  successfully and produced a 23-page main article.
- Ran `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex`,
  `bibtex qdesn-supplement`, and two subsequent `pdflatex` passes on
  `qdesn-supplement.tex`. The final pass completed successfully and produced a
  16-page supplement.
- Scanned `main.log`, `main.blg`, `qdesn-supplement.log`, and
  `qdesn-supplement.blg`; no undefined references, undefined citations, overfull
  boxes, fatal errors, bibliography errors, multiply defined labels, or hyperref
  warnings were found.

## 2026-05-10 Slash-Shorthand Style Pass

### Files Changed

- `main.tex`
- `qdesn-supplement.tex`
- `Academic_Writing_Style_Profile_v0.2.md` (gitignored local style-governance file)
- `AGENTS_academic_writing_snippet.md` (gitignored local style-governance file)

### Style and Formatting Edits

- Replaced manuscript shorthand that paired terms with slashes, including
  MCMC and VB, AL and exAL, ridge and RHS, DQLM and exDQLM, and CAVI and
  VB--LD constructions, with explicit phrasing.
- Revised the notation-table header to "Dimension and
  support".
- Added a style-governance rule discouraging slash shorthand in prose, headings,
  subtitles, table headers, and roadmap text when a short phrase is clearer.
- Retained slashes only for mathematical ratios, LaTeX commands, file paths,
  URLs, and established notation.

### Technical Changes

- No model definition, likelihood, prior, posterior target, algorithm, ELBO
  term, or simulation value was changed.

### Build Commands and Results

- Ran `pdflatex -interaction=nonstopmode -halt-on-error main.tex`, `bibtex main`,
  and two subsequent `pdflatex` passes on `main.tex`. The final pass completed
  successfully and produced a 23-page main article.
- Ran `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex`,
  `bibtex qdesn-supplement`, and two subsequent `pdflatex` passes on
  `qdesn-supplement.tex`. The final pass completed successfully and produced a
  16-page supplement.
- Scanned `main.log`, `main.blg`, `qdesn-supplement.log`, and
  `qdesn-supplement.blg`; no undefined references, undefined citations, overfull
  boxes, fatal errors, bibliography errors, multiply defined labels, or hyperref
  warnings were found.

## 2026-05-10 Repository Slash-Shorthand Cleanup

### Files Changed

- `docs/revision_logs/initial_style_revision_log.md`
- `docs/audits/initial_style_audit.md`
- `docs/audits/full_manuscript_style_audit.md`
- `docs/audits/reviewer_reading_audit.md`
- `docs/audits/reader_focused_style_audit.md`
- `scripts/build_qdesn_simulation_tables.R`

### Style and Formatting Edits

- Removed remaining slash-paired shorthand from older audit and revision notes.
- Replaced internal R-script diagnostic strings that paired DQLM and exDQLM
  with slash notation, using explicit phrasing for consistency with the
  manuscript style.
- A repository-wide search for the targeted prose shorthand patterns found no
  remaining matches. Mathematical ratios, file paths, URLs, and established
  notation were left unchanged.

### Validation

- Ran `git diff --check`; no whitespace or patch-format issues were found.
- No LaTeX rebuild was needed for this pass because no manuscript `.tex` file,
  bibliography file, or table file was changed.

## 2026-05-10 Redundancy and Compactness Pass

### Files Changed

- `main.tex`
- `qdesn-supplement.tex`
- `Academic_Writing_Style_Profile_v0.2.md` (gitignored local style-governance file)
- `AGENTS_academic_writing_snippet.md` (gitignored local style-governance file)

### Style-Governance Edits

- Added a compactness rule to the style profile: state definitions and caveats
  once in full, then use short reminders or cross-references unless repetition
  serves a new mathematical or interpretive purpose.
- Added a compactness item to the agent-writing snippet so future manuscript
  edits avoid repeated motivation, repeated caveats, and duplicate algorithm
  explanations.

### Manuscript and Supplement Edits

- Compressed the introduction's contribution paragraph while preserving the
  four substantive contributions.
- Replaced the generic non-conjugate VB explanation in the main article with a
  Q--DESN-specific description of the \((\sigma,\gamma)\) Laplace--Delta block.
- Removed repeated exogenous-covariate and teacher-forcing language from the
  forecasting section.
- Shortened the multi-quantile synthesis opening while preserving the caveat
  that synthesis is not a joint multi-quantile Bayesian model.
- Compactly restated supplement orientation paragraphs for the RHS notation,
  complete-data targets, and VB factorization.

### Technical Changes

- No likelihood, prior, posterior target, MCMC update, CAVI update, ELBO term,
  simulation value, or table value was changed.

### Build Commands and Results

- Ran `pdflatex -interaction=nonstopmode -halt-on-error main.tex`, `bibtex main`,
  and additional `pdflatex` passes until references stabilized. The final pass
  completed successfully and produced a 23-page main article.
- Ran `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex`,
  `bibtex qdesn-supplement`, and additional `pdflatex` passes until references
  stabilized. The final pass completed successfully and produced a 16-page
  supplement.
- Scanned `main.log`, `main.blg`, `qdesn-supplement.log`, and
  `qdesn-supplement.blg` for undefined references, undefined citations,
  multiply defined labels, overfull boxes, hyperref warnings, fatal errors, and
  bibliography errors. The final scan found no manuscript build warnings beyond
  harmless package metadata lines.

## 2026-05-10 Introduction and Related-Work Reframing

### Files Changed

- `main.tex`
- `refs.bib`

### Main Prose and Structure Edits

- Reframed the Introduction around conditional quantile forecasting and
  Bayesian quantile readouts, rather than opening from broad probabilistic
  forecasting.
- Moved the DESN discussion into its methodological role: fixed reservoir
  features convert nonlinear temporal dependence into a deterministic
  high-dimensional readout design.
- Clarified that Q--DESN uses the quantile-fixed GAL construction as the exAL
  working likelihood, and that posterior intervals are model-based summaries
  conditional on the fixed reservoir and working likelihood.
- Separated the readout-prior paragraph from the contribution paragraph so that
  ridge is presented as the default dense prior and the regularized horseshoe as
  the adaptive shrinkage alternative.
- Reorganized Related Work into thematic blocks: Bayesian quantile regression
  and working likelihoods, dynamic quantile models, reservoir computing,
  probabilistic reservoir methods, quantile-oriented ESNs, shrinkage priors, and
  monotone multi-quantile post-processing.

### Citation and Literature Edits

- Added `GoncalvesMigonBastos2020DQLM` to `refs.bib` and used it to anchor the
  DQLM baseline discussion.
- Used the DQLM and exDQLM literature to explain why the simulation baselines
  are relevant, rather than introducing them only in the simulation section.
- Kept probabilistic forecasting as background for distributional evaluation,
  not as the primary identity of the paper.

### Technical Changes

- No likelihood, prior, posterior target, algorithm, simulation table, or
  numerical result was changed.

### Build Commands and Results

- Ran `pdflatex -interaction=nonstopmode -halt-on-error main.tex`, `bibtex main`,
  and additional `pdflatex` passes until references stabilized. The final pass
  completed successfully and produced a 23-page main article.
- Ran `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex`,
  `bibtex qdesn-supplement`, and additional `pdflatex` passes until references
  stabilized. The final pass completed successfully and produced a 16-page
  supplement.
- Scanned `main.log`, `main.blg`, `qdesn-supplement.log`, and
  `qdesn-supplement.blg` for undefined references, undefined citations,
  multiply defined labels, overfull boxes, hyperref warnings, fatal errors, and
  bibliography errors. The final scan found no manuscript build warnings beyond
  harmless package metadata lines.

## 2026-05-10 Introduction and Related-Work Precision Pass

### Files Changed

- `main.tex`
- `qdesn-supplement.tex`
- `refs.bib`

### Prose and Style Edits

- Replaced the opening Introduction phrase "validation criteria" with the more
  specific "forecast evaluation criterion" and made the multi-quantile grid
  language explicitly post-processing-based.
- Clarified in the Introduction, main exAL subsection, and supplement that
  "exAL" is the manuscript's name for the quantile-fixed generalized asymmetric
  Laplace construction of \citet{yan2025new}.
- Replaced broad "efficient" and "computationally convenient" scale-update
  language with the more concrete statement that the product representation
  gives closed-form inverse-gamma scale updates.
- Rephrased the contribution paragraph as "contributions and evaluation" so
  the simulation study is not described as a purely methodological
  contribution.
- Shortened the probabilistic reservoir paragraph by removing peripheral
  application examples that did not directly support the Q--DESN gap.

### Citation and Bibliography Edits

- Updated `wang2013nonconjugatevb` from an arXiv placeholder to the published
  Journal of Machine Learning Research citation.
- Verified that the Ji--Lee--Rabe-Hesketh working-likelihood citation is
  already represented as an OnlineFirst journal article with DOI.

### Technical Changes

- No likelihood, prior, posterior target, MCMC update, VB update, simulation
  table, or numerical result was changed.

### Build Commands and Results

- Ran `pdflatex -interaction=nonstopmode -halt-on-error main.tex`, `bibtex main`,
  and additional `pdflatex` passes until references stabilized. The final pass
  completed successfully and produced a 23-page main article.
- Ran `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex`,
  `bibtex qdesn-supplement`, and additional `pdflatex` passes until references
  stabilized. The final pass completed successfully and produced a 16-page
  supplement.
- Scanned `main.log`, `main.blg`, `qdesn-supplement.log`, and
  `qdesn-supplement.blg` for undefined references, undefined citations,
  multiply defined labels, overfull boxes, hyperref warnings, fatal errors, and
  bibliography errors. The final scan found no manuscript build warnings beyond
  harmless package metadata lines.

## 2026-05-10 Full Style-Profile Pass on Main and Supplement

### Files Changed

- `main.tex`
- `qdesn-supplement.tex`

### Prose and Style Edits

- Re-read the academic writing style profile and applied its main criteria to
  both source files: object-level topic sentences, restrained claims,
  compact repetition, exact-target versus approximation separation, and
  avoidance of slash shorthand or self-conscious section openings.
- Revised the main title subtitle from an implementation list to the broader
  phrase "Posterior Computation," while preserving the abstract's explicit
  MCMC and VB--LD description.
- Replaced self-referential or procedural prose in the notation, DESN,
  exAL, model overview, prior, inference, forecasting, synthesis, simulation,
  application-placeholder, and appendix passages with sentences naming the
  relevant statistical object, model component, approximation, metric, or
  design condition.
- Replaced broad words such as "convenient," "flexible," "tractable,"
  and strong "must" phrasing where a more specific statement was available:
  closed-form inverse-gamma scale updates, an added exAL asymmetry parameter,
  conditional Gaussian updates, and empirical calibration under
  misspecification.
- Revised supplement orientation paragraphs so that the supplement supports
  derivations and algorithms without repeating the main article's motivation
  or reading like a second introduction.
- Reflowed the exAL stochastic representation into displayed equations, which
  removed the remaining overfull hbox in the main article.

### Technical Changes

- No likelihood, prior, posterior target, MCMC update, VB update, ELBO term,
  simulation value, or table value was changed.

### Build Commands and Results

- Ran `pdflatex -interaction=nonstopmode -halt-on-error main.tex`, `bibtex main`,
  and additional `pdflatex` passes until references stabilized. The final pass
  completed successfully and produced a 23-page main article.
- Ran `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex`,
  `bibtex qdesn-supplement`, and additional `pdflatex` passes until references
  stabilized. The final pass completed successfully and produced a 16-page
  supplement.
- Scanned `main.log`, `main.blg`, `qdesn-supplement.log`, and
  `qdesn-supplement.blg` for undefined references, undefined citations,
  multiply defined labels, overfull boxes, hyperref warnings, fatal errors, and
  bibliography errors. The final scan found no manuscript build warnings beyond
  harmless package metadata lines.

## 2026-05-10 Compact Abstract Pass

### Files Changed

- `main.tex`

### Prose and Style Edits

- Rewrote the abstract from a feature-by-feature summary into a compact
  statistical argument: quantile target, fixed DESN design, exAL working
  likelihood, ridge and regularized-horseshoe priors, posterior computation,
  monotone quantile post-processing, and bounded simulation evidence.
- Removed extra explanatory scaffolding around reservoir construction, exAL
  shape behavior, Nishimura--Suchard implementation details, and inference
  mechanics while preserving the main methodological claims.
- Kept simulation claims design-specific by referring to controlled
  single-root simulations, matched Q--DESN RMSE comparisons, mixed check-loss
  gains, and lower VB--LD runtime relative to MCMC.

### Technical Changes

- No likelihood, prior, posterior target, MCMC update, VB update, simulation
  value, or table value was changed.

### Build Commands and Results

- Ran `pdflatex -interaction=nonstopmode -halt-on-error main.tex`, `bibtex main`,
  and additional `pdflatex` passes until references stabilized. The final pass
  completed successfully and produced a 23-page main article.
- Ran `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex`,
  `bibtex qdesn-supplement`, and additional `pdflatex` passes until references
  stabilized. The final pass completed successfully and produced a 16-page
  supplement.
- Scanned `main.log`, `main.blg`, `qdesn-supplement.log`, and
  `qdesn-supplement.blg` for undefined references, undefined citations,
  multiply defined labels, overfull boxes, hyperref warnings, fatal errors, and
  bibliography errors. The final scan found no manuscript build warnings beyond
  harmless package metadata lines.

## 2026-05-10 Repository Navigation and Title Pass

### Files Changed

- `README.md`
- `docs/README.md`
- `docs/audits/full_manuscript_style_audit.md`
- `docs/audits/initial_style_audit.md`
- `docs/audits/reader_focused_style_audit.md`
- `docs/audits/reviewer_reading_audit.md`
- `docs/implementation_notes/regularized_horseshoe_update_report.md`
- `docs/revision_logs/initial_style_revision_log.md`
- `docs/revision_logs/reader_focused_revision_log.md`
- `main.tex`
- `qdesn-supplement.tex`
- `scripts/build_qdesn_simulation_tables.R`

### Navigation and Naming Edits

- Changed the manuscript title to the object-first form
  "Bayesian Quantile Readouts for Fixed Deep Echo State Networks."
- Aligned the supplement title with the main manuscript title.
- Renamed documentation directories from insider-facing labels to reader-facing
  categories: `docs/audits`, `docs/revision_logs`, and
  `docs/implementation_notes`.
- Renamed audit and revision files so their names describe their role without
  requiring prior familiarity with the Q--DESN editing history.
- Added a top-level README with build commands, source-file orientation, and
  simulation-table regeneration notes.
- Added `docs/README.md` to explain the documentation map.

### Technical Changes

- No likelihood, prior, posterior target, MCMC update, VB update, simulation
  value, or table value was changed.

## 2026-05-10 Working-Likelihood Coverage Wording Pass

### Files Changed

- `main.tex`

### Literature Check

- Rechecked the working-likelihood language against the cited Bayesian
  quantile-regression literature. The relevant distinction is that AL-style
  likelihoods can define a consistent quantile-targeting posterior under
  misspecification, but model-based posterior standard deviations and credible
  intervals need not have calibrated frequentist coverage without separate
  assessment or adjustment.

### Prose Edits

- Replaced the compressed sentence "calibration under misspecification is an
  empirical question" with explicit wording: posterior intervals for readout
  quantities and forecast bands generated from the fitted likelihood are
  model-based summaries conditional on the fixed reservoir and working
  likelihood.
- Stated that empirical coverage should be evaluated in simulation or
  validation data rather than assumed from the posterior alone.
- Revised the related-work paragraph to say that coverage of model-based
  credible intervals may require separate assessment or adjustment under
  misspecification.

### Technical Changes

- No likelihood, prior, posterior target, MCMC update, VB update, simulation
  value, or table value was changed.

### Build Commands and Results

- Ran `pdflatex -interaction=nonstopmode -halt-on-error main.tex`, `bibtex main`,
  and additional `pdflatex` passes until references stabilized. The final pass
  completed successfully and produced a 23-page main article.
- Scanned `main.log` and `main.blg` for undefined references, undefined
  citations, multiply defined labels, overfull boxes, hyperref warnings, fatal
  errors, and bibliography errors. The final scan found no manuscript build
  warnings beyond harmless package metadata lines.
