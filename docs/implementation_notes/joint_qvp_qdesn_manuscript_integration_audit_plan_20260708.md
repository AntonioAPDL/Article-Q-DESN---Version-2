# Joint QVP--Q--DESN Manuscript Integration Audit Plan

Date: 2026-07-08

## Objective

Promote the joint quantile-vector Q--DESN work from repository-side validation
assets into the article and supplement while preserving the manuscript's
academic style: careful notation, conditional claims, reproducible validation,
and a clear separation between modeling, computation, and applications.

The implemented manuscript change is scoped to the article source, supplement
source, bibliography, and local planning-workspace ignore rule. It deliberately
does not stage unrelated R/test changes or new Phase 4o development artifacts.

## Audit Inputs

- `main.tex`: article narrative, model, inference, simulations, applications,
  and discussion.
- `qdesn-supplement.tex`: single-quantile derivations, VB--LD details, and
  application supplement.
- `refs.bib`: cited statistical literature.
- `tables/joint_qdesn_article_validation_tables.tex`: main-branch joint
  validation table bundle.
- `figures/joint_qvp_synthetic_dgp/`: frozen joint synthetic-DGP diagnostics.
- Local validation logs from complete LaTeX/BibTeX compilation cycles.

## Diagnosis

### 1. Manuscript Model Gap

The article already gave a coherent single-quantile Q--DESN account: fixed
reservoir features, exAL working likelihood, ridge/RHS priors, MCMC, VB--LD,
posterior prediction, post hoc monotone synthesis, TT500 validation, GloFAS,
and PriceFM. The gap was that joint QVP--RHS modeling was present in the code
and validation assets but not mathematically specified in the manuscript.

The optimal forward move was therefore not a broad production-code rewrite. It
was a manuscript and supplement integration that gives the existing code and
assets a precise published target.

### 2. Joint Quantile-Vector Specification

The article now defines a joint quantile-vector Q--DESN model with:

- a quantile grid and a non-intercept feature design;
- intercept and slope separation;
- an exAL working likelihood at each quantile level;
- baseline slopes plus adjacent quantile-slope innovations;
- a sparse lower-triangular accumulation matrix for the stacked coefficient
  path; and
- regularized-horseshoe shrinkage on both baseline and innovation components.

This choice is preferable to simply describing "multi-quantile Q--DESN" in
words because it identifies the exact object being regularized and the exact
posterior target used by MCMC or VB approximations.

### 3. Non-Crossing Claim Boundary

The joint QVP--RHS prior is a soft non-crossing device, not a hard guarantee.
It shrinks adjacent coefficient-path innovations and can concentrate posterior
mass near coherent quantile curves, but finite-sample quantile crossings can
still occur unless the sampler or prediction step also imposes a hard
constraint, rejection rule, or rearrangement.

The manuscript therefore states the sufficient monotone-gap condition
explicitly and avoids claiming that the prior alone guarantees non-crossing.
This aligns the article with both the repository diagnostics and the broader
non-crossing quantile-regression literature.

### 4. Inference and Supplement Gap

The supplement lacked the stacked joint derivation needed to make the article
reproducible. A new supplement section now derives:

- the stacked exAL likelihood;
- the QVP--RHS prior and difference-matrix representation;
- the complete posterior kernel;
- Gaussian full conditionals for stacked slopes and baseline slopes;
- quantile-level latent-variable full conditionals;
- intercept updates with optional monotone-gap handling;
- scale and asymmetry log kernels;
- RHS scale updates for baseline and innovations;
- MCMC and VB--LD approximations; and
- ELBO and crossing-diagnostic terms.

The derivation keeps exact posterior targets distinct from computational
approximations and applies the generalized Bayes learning rate consistently to
both determinant and residual terms in the exAL Gaussian mixture block.

### 5. Simulation and Application Boundary

The joint validation evidence is presented as evidence under frozen synthetic
protocol assets, not as a universal dominance claim. Application text now
distinguishes:

- independent single-quantile fits with post hoc monotone synthesis, used in
  the GloFAS application;
- a joint QVP--RHS model, validated separately in synthetic experiments; and
- PriceFM heavy-tail diagnostics, which are not evidence for the joint prior
  unless a future joint run is executed.

This prevents the empirical sections from overstating which results validate
which model.

### 6. Bibliography Gap

The bibliography was extended only for works directly used by the new text:

- non-crossing quantile-regression constraints and stepwise fitting;
- joint quantile planes;
- score/generalized-likelihood Bayesian quantile inference;
- composite Bayesian non-crossing quantile regression;
- interquantile shrinkage and composite quantile regression; and
- generalized Bayesian updating.

Bibliographic metadata were checked against primary DOI/arXiv sources before
insertion.

### 7. Merge Hygiene

The feature branch and `origin/main` had substantial unrelated divergence. A
direct branch merge would have brought unrelated history into `main`. The safer
publication path was to cherry-pick the manuscript integration commit onto a
clean `main` worktree, resolve the single manuscript conflict, validate, and
push `main`.

This preserved the article work while leaving pre-existing R/test development
files untouched in the original feature worktree.

## Execution Record

1. Prepared and executed the manuscript integration on
   `application-ensemble-likelihood-redesign`.
2. Committed the feature-branch manuscript patch as:
   `181220a Integrate joint QVP QDESN manuscript extension`.
3. Pushed the feature branch to `origin/application-ensemble-likelihood-redesign`.
4. Compared `origin/main` and the feature branch; because the branch carried
   unrelated divergence, did not merge the whole branch.
5. Cherry-picked the manuscript commit onto a clean `main` worktree.
6. Resolved the `main.tex` conflict by preserving the richer existing
   main-branch validation subsection and adding the joint QVP article,
   supplement, and bibliography material around it.
7. Built and checked both manuscript targets.
8. Committed the `main` article integration as:
   `60dbe21 Integrate joint QVP QDESN manuscript extension`.
9. Pushed `60dbe21` to `origin/main`.

## Reproducibility Checks

The following checks were run in the clean `main` worktree after conflict
resolution:

```sh
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex

pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
bibtex qdesn-supplement
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex

rg -n "undefined|Undefined|Citation.*undefined|Reference.*undefined|There were undefined|Overfull|Fatal|Emergency stop|Label\(s\).*changed|Rerun" main.log qdesn-supplement.log
git diff --check
```

Compilation completed successfully. The final log scan found only the
`rerunfilecheck` package banner, with no unresolved citations, unresolved
references, fatal errors, overfull boxes, or active rerun warnings. The final
source whitespace check was clean.

## Source Trail

The article and bibliography additions were cross-checked against the following
source families:

- Szendrei, Bhattacharjee, and Schaffer, fused adaptive lasso quantile
  regression, arXiv:2403.14036.
- Bondell, Reich, and Wang, non-crossing quantile regression, Biometrika.
- Wu and Liu, stepwise multiple quantile regression estimation.
- Yang and Tokdar, joint estimation of quantile planes.
- Wu and Narisetty, posterior concentration for Bayesian quantile regression.
- Wang and Cai, composite Bayesian non-crossing quantile regression.
- Jiang, Bondell, and Wang, interquantile shrinkage.
- Zou and Yuan, composite quantile regression.
- Bissiri, Holmes, and Walker, generalized Bayesian updating.

## Final Assessment

The implemented path is the optimal article-facing move because it turns an
existing repository capability into a reproducible manuscript contribution
without overclaiming empirical support or mixing unrelated development work into
the article merge. The resulting article now states what the joint model is,
what it buys, what it does not guarantee, how inference targets are defined, and
which validation assets support the claims.
