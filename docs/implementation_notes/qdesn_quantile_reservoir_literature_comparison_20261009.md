# Quantile-reservoir comparison: source audit and controlled revision

Baseline: `75a5bcf46a56606a10c100803767d55282b6fd2b`.
Scope: the introduction's comparison with Lv et al. (2016) and Bonas et al.
(2024), with no change to empirical conclusions, their placeholders,
statistical targets, inference code, results, tables, figures, or bibliography.

## Primary evidence and access boundaries

- [Lv et al., publisher record](https://www.sciencedirect.com/science/article/pii/S0967066115300307),
  DOI `10.1016/j.conengprac.2015.10.003`: the indexed abstract/introduction
  describe quantile regression of ESN output weights and bootstrap-based
  ensemble confidence/prediction intervals. The
  [Dalian University of Technology article record](https://faculty.dlut.edu.cn/dalianligongdaxuetanzhongheyanjiuyuan/en/lwcg/1170173/content/36979.htm)
  independently reproduces the original abstract. Direct publisher full-text
  access returned an error, and full Section 3 was unavailable. Consequently
  the review does not infer absent regularization, particular bootstrap
  resampling details, absence of joint constraints, or absence of VB.
- [Bonas et al., author preprint](https://arxiv.org/pdf/2308.04391), Sections
  3.2--3.3, pages 11--15: ridge-estimated DESN readouts generate point
  forecasts over reservoir realizations. Residual quantiles are estimated
  using penalized quantile sheets, including simultaneous estimation across
  probability levels, lead-dependent penalties, and an additional interval
  calibration adjustment. Section 3.3, equations (6)--(10) and Algorithm 1
  support this sequence. The
  [publisher record](https://onlinelibrary.wiley.com/doi/10.1002/env.2833)
  authenticates the published 2024 Environmetrics citation; its accessible
  HTML did not expose the methodological body. The detailed account is
  explicitly based on the authors' preprint rather than an invented full-text
  publisher-access claim.
- [Kozumi and Kobayashi, publisher record](https://www.tandfonline.com/doi/full/10.1080/00949655.2010.496117)
  and [author working paper](https://www.b.kobe-u.ac.jp/papers_files/2009_02.pdf):
  the AL normal--exponential representation gives Gaussian and generalized
  inverse-Gaussian conditional distributions. This is established Bayesian
  quantile-regression computation, not a newly invented Q--DESN sampler.

## Comparisons retained and claims rejected

| Dimension | Supported distinction | Necessary qualification |
|---|---|---|
| Estimation target | Q--DESN fits a Bayesian quantile readout directly to the response conditional on DESN features. | Lv already fits ESN quantiles directly; direct estimation alone is not the novelty. |
| Uncertainty | Posterior coefficient, likelihood, and shrinkage inference replaces a requirement for bootstrap uncertainty within this construction. | Posterior uncertainty conditions on a specified reservoir and does not automatically include reservoir-selection or realization uncertainty. |
| Interval construction | Pairs of fitted quantiles define intervals without a separately fitted residual-calibration regression. | This contrast applies specifically to Bonas's point-forecast/residual-calibration sequence. Quantile locations, parameter credible intervals, and marginal predictive quantiles remain distinct. |
| Joint estimation | Adjacent-coefficient priors couple the regression across probability levels. | Bonas already uses simultaneous quantile sheets; the distinction is posterior coefficient sharing, not the first joint quantile analysis. Adjacent shrinkage alone does not enforce noncrossing. |
| Regularization | Ridge and product-RHS coefficient priors operate directly in the quantile regression. | Bonas already regularizes both point forecasts and quantile sheets. Lv's full regularization details were unavailable. No general absence claim is justified. |
| AL computation | Gaussian augmentation gives standard-family, closed-form full-conditional distributions under the stated priors. | This is not a closed-form posterior solution. The current JOINT implementation uses a log-scale slice transition for its GIG latent conditional. Do not describe every executed sampler as pure direct-draw Gibbs. |
| Variational inference | Model-specific deterministic approximations support repeated fitting without running posterior simulation for every fit. | No matched runtime benchmark supports superiority to Lv or Bonas; approximation and partial-uncertainty qualifications remain in the computation section. |
| exAL | Quantile-fixed shape flexibility augments the AL family while preserving the fitted quantile location. | Shape computation is nonconjugate and working-likelihood intervals are not automatically calibrated. |

Avoid calling the method a literal "one-step estimator": VB and MCMC remain
iterative, model selection and feature construction are separate, and
post-estimation monotone projection remains an explicit reporting option.
The supported wording is direct Bayesian quantile regression without a
separate residual-calibration stage. Calibration of interval endpoints is not
the same operation as ordering a quantile grid.

No mathematical or empirical evidence establishes that the other approaches
are slower, less accurate, or less well calibrated. Their bootstrap and
calibration stages address uncertainty goals that differ from this conditional
posterior analysis. Methodological differences, rather than unfavorable
unverified descriptions of earlier papers, carry the contribution statement.

## Internal cross-checks and acceptance gates

The current manuscript's posterior-computation section and supplementary AL
latent/scale and product-RHS derivations support the stated update laws.
`application/R/joint_qvp_qdesn.R`, functions `app_joint_qvp_rgig` and
`app_joint_qvp_rgig_log_slice_one`, document the executed latent transition.
The forecasting section retains isotonic projection and the distinction
between conditional locations and marginal predictive quantiles. Earlier
Bayesian DESN precedent remains credited.

The controlled revision follows the public academic writing profile: related
work is organized by statistical role; established methods receive credit;
model specification is distinct from approximation; no universal efficiency,
novelty, or coverage claim is added. No empirical findings are reinstated
before the results sections.

Acceptance requires the existing manuscript/projection and mathematics
checks, the deterministic dependency inventory, clean manuscript builds,
and an exact results-section suffix comparison against the baseline. Only
the introduction, this source audit, and generated dependency metadata belong
to this revision. Remote integration and any article-only publication follow
the existing guarded command-line Git policy.

Source checks passed: the bibliography/initialization regression,
final-manuscript scientific-invariance checker (including GloFAS projection),
104-file dependency inventory, `git diff --check`, and exact main-text suffix
comparison from the model section onward. Supplement and bibliography are
unchanged. Identified main/supplement proofs remain 36/84 pages; anonymous
main/supplement proofs are 35/83 pages, with clean final logs. Two independent
read-only audits checked the original-method descriptions and the new
inferential/computational claims. These are bounded editorial checks, not new
model fits or a claim of a complete historical runtime-suite rerun.
