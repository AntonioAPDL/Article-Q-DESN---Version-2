# Initial Style Revision Log

## Files Changed

- `docs/audits/initial_style_audit.md`
- `docs/revision_logs/initial_style_revision_log.md`
- `main.tex`
- `qdesn-supplement.tex`
- `tables/qdesn_simulation_pinball.tex`

## Main Structural Edits

- Reworked the abstract to follow problem, gap, Q-DESN construction, computation, simulation evidence, and qualified conclusion.
- Reorganized the introduction around the inferential problem, the remaining gap for Bayesian quantile reservoir readouts, the proposed construction, contributions, and roadmap.
- Rewrote related work thematically around ESNs/reservoir computing, probabilistic reservoir methods, and quantile ESN models.
- Replaced empty Data and Discussion placeholders with honest draft-status language, limitations, and future-work directions without inventing an application.

## Main Notation Edits

- Expanded the notation table to include dimensions and supports for the main response, quantile level, covariates, reservoir states, readout vectors, design matrix, exAL parameters, and shrinkage scales.
- Clarified that the DESN design matrix is fixed after reservoir construction and washout.
- In the supplement, clarified that the main article's \(\RHS\) prior corresponds to the `rhs_ns` Nishimura-Suchard product representation used for closed-form scale updates.
- In the supplement, connected \(D_\gamma=C_\gamma|\gamma|\) to the main article's \(\lambda(\gamma)=C(\gamma)|\gamma|\).

## Equation-Exposition Edits

- Added verbal setup in the model section distinguishing the marginal exAL working likelihood from its latent Gaussian computational augmentation.
- Added interpretation after the Q-DESN augmented likelihood to distinguish model parameters from auxiliary variables.
- Added an explicit augmented posterior target at the beginning of the inference section.
- Clarified in the supplement that the complete-data targets include the AL and exAL latent variables once and that the inverse-gamma variables augment only the shrinkage scales.

## Computation/Inference Edits

- Reframed MCMC and VB-LD as two computational strategies for the same posterior target.
- Clarified that VB-LD is an approximation to the augmented posterior, not a different model.
- Stated that Delta-method expectations are used for smooth functions of the non-conjugate \((\sigma,\gamma)\) block.
- Added supplement orientation before the CAVI and ELBO sections.

## Simulation/Application Edits

- Added a clearer simulation goal statement and limitation that the study is a controlled dynamic readout experiment.
- Clarified that simulation tables report criterion values from one reproducible dynamic root rather than repeated Monte Carlo summaries.
- Revised the simulation conclusion to tie claims to the reported design and avoid universal statements.
- Revised the application section to state that a completed real-data application is not yet included and to list what must be reported before applied-performance claims are made.

## Figure/Table/Caption Edits

- Expanded the notation-table caption to explain the fixed-design role of the reservoir.
- Revised the pinball-loss table caption so it is self-contained and does not rely only on the RMSE table caption.
- No figures were present in the repository.

## Discussion/Limitation Edits

- Added a discussion summarizing the methodological contribution, simulation evidence, limitations, and future work.
- Limitations now include fixed reservoir-feature uncertainty, independent quantile fits, VB-LD approximation error, single-root simulation design, and the missing real-data application.

## Technical Ambiguities Discovered

- The requested `AGENTS.md` and `STYLE_PROFILE.md` files were not present under those names. The available instruction files were `AGENTS_academic_writing_snippet.md` and `Academic_Writing_Style_Profile_v0.2.md`.
- The manuscript currently has no completed real-data application section.
- The simulation design uses one reproducible dynamic root per family and quantile level, so it does not quantify repeated-data-set Monte Carlo variability.
- VB-LD approximation quality remains an empirical diagnostic issue and should be compared with MCMC in smaller settings when possible.

## Unsupported Claims That Remain

- No applied-performance claim is made in the revised draft because the real-data application is not yet included.
- Claims about simulation performance are restricted to the reported controlled simulation design.

## Citations That Appear Missing

- None were identified by the final LaTeX/BibTeX builds. All citations resolved.

## Build Issues And Resolution

- No repository build script, `Makefile`, `latexmkrc`, or `build.sh` was found.
- `main.tex` was built with:
  - `pdflatex -interaction=nonstopmode -halt-on-error main.tex`
  - `bibtex main`
  - `pdflatex -interaction=nonstopmode -halt-on-error main.tex`
  - `pdflatex -interaction=nonstopmode -halt-on-error main.tex`
  - an additional `pdflatex -interaction=nonstopmode -halt-on-error main.tex` pass to settle changed labels
- `qdesn-supplement.tex` was built with:
  - `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex`
  - `bibtex qdesn-supplement`
  - `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex`
  - `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex`
  - an additional `pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex` pass to settle changed labels
- Final warning scans of `main.log`, `main.blg`, `qdesn-supplement.log`, and `qdesn-supplement.blg` found no unresolved references, undefined citations, overfull boxes, fatal errors, or hyperref warnings.

## Reader-Proof Cross-Reference Pass

- Defined first-use acronyms and abbreviations more explicitly in the article and supplement, including exAL, AL, MCMC, VB, VB--LD, RHS, DQLM, exDQLM, RMSE, CRPS, PIT, IG, GIG, CAVI, and ELBO where needed.
- Added concrete article-to-supplement pointers for complete-data joint distributions, AL and exAL derivations under ridge and RHS priors, CAVI, ELBO, forecasting, and multi-quantile synthesis.
- Added concrete supplement-to-article orientation, including where the main article defines the fixed reservoir feature map and where it reports the simulation study.
- Replaced section-symbol shorthand in the article with explicit `Section~\ref{...}` references.
- Clarified that the supplement's \(D_\gamma\) is the same exAL shift coefficient as the main article's \(\lambda(\gamma)\).
- Rebuilt `main.tex` and `qdesn-supplement.tex` with the standard `pdflatex`, `bibtex`, and two-pass `pdflatex` sequence; final log scans again found no unresolved references, undefined citations, overfull boxes, fatal errors, or hyperref warnings.

## Local Style-Governance Update

- Updated the ignored local `Academic_Writing_Style_Profile_v0.2.md` with a new anti-AI-prose section after the existing Avoid List.
- The new guidance defines generic AI-prose failure modes, replacement rules, sentence-level and section-level diagnostics, rewrite examples, and a required anti-AI-prose pass for future manuscript revisions.
- Harmonized the ignored local `AGENTS_academic_writing_snippet.md` so the short agent policy also tells assistants not to replace technical specificity with smoother but less informative prose.
- Kept `Academic_Writing_Style_Profile_v0.2.md` and `AGENTS_academic_writing_snippet.md` ignored and untracked according to the repository ignore policy requested by the user.
