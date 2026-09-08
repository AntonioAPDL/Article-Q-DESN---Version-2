# Reference Calibration of the Regularized-Horseshoe Global Scale

Date: 2026-09-08
Scope: main article, supplement, and manuscript-facing prior specification
Status: implementation plan and audit record

## Objective

The article defines the regularized-horseshoe hierarchy but does not yet give
the reader an interpretable way to choose the hyperprior scale `tau0`. This
revision adds a compact recommendation to the main article and gives its
derivation, limitations, and likelihood-specific alternatives in the
supplement.

The change is methodological guidance. It does not alter fitted models,
reported scores, selected reservoir specifications, tables, figures, or
scientific conclusions. No analysis is rerun.

## Manuscript and Repository Audit

The audit used `origin/main` at
`6414867e786cc21bef5ae5169f6622ece6b49189`. The relevant findings are:

| Surface | Current state | Required action |
|---|---|---|
| `main.tex`, single-level prior specification | Defines the random global scale `tau` and its half-Cauchy hyperprior scale `tau0`, but gives no calibration rule | Add one scale-aware Gaussian reference and state its limitations |
| `main.tex`, sequential initialization | Correctly distinguishes numerical initialization from model comparison | State that a common reference `tau0` may be retained across likelihoods sharing the same standardized design |
| `main.tex`, GloFAS application | Displays two task-specific numerical `tau0` values | Replace the values by a model-level statement that the two coefficient blocks have separate shrinkage hierarchies |
| `qdesn-supplement.tex`, coefficient priors | Gives the complete product-prior hierarchy and inverse-gamma augmentation | Add the ordinary-horseshoe derivation, finite-slab qualification, AL/exAL information references, and a reproducible specification sequence |
| `application/R/rhs_global_scale_reference.R` | No common implementation existed | Add a side-effect-free implementation of the Gaussian, AL, and exAL reference calculations, with focused tests |
| Generated GloFAS aliases | Retain the frozen numerical settings used to reproduce the current application result | Preserve them as provenance; they cease to be rendered after the prose edit |
| Historical implementation notes and frozen configuration files | Record the settings used by completed experiments | Preserve them unchanged; they are evidence, not manuscript recommendations |

The rendered dependency chain contains no other task-specific `tau0` values.
Several historical, currently unreferenced table fragments contain prior
settings from older scientific stages. They remain untouched because deleting
or rewriting them would erase reproducibility evidence without improving the
rendered article.

## Theoretical Basis

Let `r` be the number of penalized, non-intercept coefficients and let
`N_fit` be the number of observations used for fitting. For standardized
penalized columns in an orthogonal Gaussian linear-model reference problem,
define the coefficient-specific shrinkage factor

\[
\kappa_j=\left(1+\frac{N_{\mathrm{fit}}\tau^2\lambda_j^2}
{\sigma_{\mathrm{ref}}^2}\right)^{-1}.
\]

For ordinary horseshoe local scales, the prior mean of the effective number of
coefficients that escape global shrinkage is

\[
E(m_{\mathrm{eff}}\mid\tau)
=r\frac{a}{1+a},
\qquad
a=\frac{\tau\sqrt{N_{\mathrm{fit}}}}{\sigma_{\mathrm{ref}}}.
\]

Equating this reference quantity to an elicited value `m0`, with
`0 < m0 < r`, gives

\[
\tau_{0,\mathrm{ref}}
=\frac{m_0}{r-m_0}
 \frac{\sigma_{\mathrm{ref}}}{\sqrt{N_{\mathrm{fit}}}}.
\]

This is the prior-scale recommendation developed for sparse Gaussian
regression by Piironen and Vehtari. It supplies an interpretable scale for the
half-Cauchy hyperprior on the random global parameter `tau`; it does not fix
`tau` at `tau0`.

The exact effective-size identity does not carry unchanged to the Q--DESN
prior because:

1. reservoir columns can be strongly correlated;
2. the finite slab changes the coefficient variance for large local scales;
3. AL and exAL working likelihoods have different local information for their
   location parameters; and
4. the joint model contains baseline and adjacent-difference coefficient
   blocks with different prior interpretations.

The formula is therefore described as a **Gaussian reference calibration**,
not as an exact prior expectation for the fitted Q--DESN model. This wording
preserves the useful theory without overstating what it establishes.

## Decision Audit

The following alternatives were considered against the article's goals of
Bayesian interpretability, cross-model comparability, and reproducibility.

| Candidate approach | Statistical advantage | Limitation | Decision |
|---|---|---|---|
| Report one fixed numerical `tau0` as a general default | Simple | Ignores sample size, response scale, and coefficient dimension; encourages application-specific values to be read as universal | Reject |
| Select `tau0` by the same validation score used for reservoir selection | Can improve a particular empirical score | Turns the prior into another tuning axis and uses data twice unless the full selection design is accounted for | Do not recommend as the general prior rule |
| Put a half-Cauchy prior on `tau` but leave its scale unspecified | Formally Bayesian | The hyperprior still requires a scale; omitting it prevents reproduction and can imply unintended prior complexity | Reject |
| Use a separate AL/exAL information match at every probability level | Adjusts for local likelihood curvature | Changes the coefficient-prior scale across probability levels and weakens apples-to-apples comparisons | Retain as an optional sensitivity specification |
| Use one Gaussian reference for models sharing a standardized design | Scales with `N_fit`, `r`, prior activity, and response variation; aligns with the preliminary Gaussian fit and keeps the coefficient prior comparable across likelihoods | Remains an approximation for correlated DESN features and a finite slab | Adopt as the primary recommendation |
| Calibrate every coefficient block with one common numerical value | Minimal bookkeeping | Conflates blocks with different dimensions, scaling, and prior interpretations | Reject; calibrate distinct blocks separately |

The adopted approach is optimal for the intended manuscript role because it
adds a defensible recommendation without changing the empirical estimands or
retroactively redefining completed analyses. It also fits the existing
sequential-initialization discussion: the preliminary Gaussian fit supplies a
response-scale reference, while all destination models retain their own
likelihoods and posterior distributions.

Primary references:

- Piironen, J. and Vehtari, A. (2017), “Sparsity information and regularization
  in the horseshoe and other shrinkage priors,” *Electronic Journal of
  Statistics*, <https://doi.org/10.1214/17-EJS1337SI>.
- Nishimura, A. and Suchard, M. A. (2023), “Shrinkage with shrunken shoulders:
  Gibbs sampling shrinkage model posteriors with guaranteed convergence
  rates,” *Bayesian Analysis*, <https://doi.org/10.1214/22-BA1308>.

## Recommended Specification

For a new Q--DESN analysis:

1. Center the response and standardize every penalized design column using
   only the fitting observations. Keep the intercept outside the global-local
   prior.
2. Elicit `m0` as a prior reference for the number of coefficients expected to
   escape strong global shrinkage. It is not a selected model size and should
   not be inferred from held-out scores.
3. Obtain `sigma_ref` from the preliminary Gaussian fit on the same fitting
   observations and design. If the response has also been standardized to unit
   scale, use `sigma_ref = 1` as the corresponding reference.
4. Compute the Gaussian reference `tau0_ref` from the display above.
5. Use the same reference across Normal, AL, and exAL models when they share
   the same standardized design. This keeps the coefficient-prior scale
   comparable while their likelihoods and posterior shrinkage remain distinct.
6. Calibrate separate coefficient blocks separately when their dimensions,
   standardizations, or prior activity beliefs differ. In a joint quantile
   regression, the baseline block and adjacent-difference blocks may therefore
   use different `m0` values.
7. Record `r`, `N_fit`, `m0`, `sigma_ref`, the scaling sample, and whether the
   Gaussian or a likelihood-information reference was used.

This common-reference rule is especially suitable for the article's
median-centered sequence. The Gaussian fit provides both numerical starting
values and the response-scale reference. Passing starting values to AL and
exAL fits does not transfer the Gaussian posterior and does not impose a shared
inferential objective.

## Optional Likelihood-Information References

For readers who prefer a likelihood-specific local-information match, let
`I_mu,ref` denote the one-observation Fisher information for the location
parameter at a reference likelihood state. Then

\[
\tau_{0,\mathcal L}
=\frac{m_0}{r-m_0}
 \{N_{\mathrm{fit}}I_{\mu,\mathrm{ref}}\}^{-1/2}.
\]

For the AL likelihood at level `p0`,

\[
I_{\mu,\mathrm{AL}}
=\frac{p_0(1-p_0)}{\sigma^2},
\qquad
\tau_{0,\mathrm{AL},p_0}
=\frac{m_0}{r-m_0}
 \frac{\sigma_{\mathrm{ref},p_0}}
 {\sqrt{N_{\mathrm{fit}}p_0(1-p_0)}}.
\]

For a standardized exAL density `g_p0(z; gamma)`, define

\[
J_{p_0}(\gamma)
=E\left[
\left\{\partial_z\log g_{p_0}(Z;\gamma)\right\}^2
\right].
\]

The corresponding local-information reference is

\[
\tau_{0,\mathrm{exAL},p_0}
=\frac{m_0}{r-m_0}
 \frac{\sigma_{\mathrm{ref},p_0}}
 {\sqrt{N_{\mathrm{fit}}J_{p_0}(\gamma_{\mathrm{ref}})}}.
\]

At the nested AL reference `gamma_ref = 0`, this reduces to the AL expression.
These alternatives are suitable for sensitivity analysis, but they alter the
coefficient-prior scale across probability levels. The main recommendation is
therefore the common Gaussian reference when the scientific comparison is
intended to hold the coefficient prior fixed across likelihoods.

## Wording and Notation Decisions

- Use `r`, already defined as the non-intercept regression dimension. The
  symbol `D` remains reserved for reservoir depth.
- Use `N_fit` for the number of fitting observations so the generic guidance
  is not tied to any one simulation's `T_fit` notation.
- Distinguish the posterior random variable `tau` from its fixed hyperprior
  scale `tau0` in every occurrence.
- Refer to the formula as a “reference calibration,” not an “optimal default,”
  “effective sparsity guarantee,” or “fully automatic” rule.
- Use “sequential initialization” only for transfers of starting values. Prior
  calibration and model selection remain separate statistical decisions.
- Avoid task identifiers, run labels, implementation-stage names, and exact
  application hyperparameter values in the manuscript prose.
- Describe the Nishimura--Suchard construction through its conditional
  coefficient variance and retained scale updates; do not call the entire
  complete joint prior identical to the direct regularized horseshoe.

## Validation and Publication Gates

The implementation is accepted only if all of the following hold:

1. `git diff --check` passes.
2. The main article and supplement compile from a clean tree.
3. Cross-references and bibliography entries resolve.
4. No task-specific numerical `tau0` value remains in rendered manuscript
   prose.
5. The frozen GloFAS aliases and historical implementation records remain
   unchanged.
6. Existing article contract checks pass.
7. The focused reference-calibration test passes for the Gaussian, AL, and
   exAL calculations and rejects invalid domains.
8. The article-only manifest closure compiles independently.
9. The final Git integration follows the repository's command-line-only,
   fresh-`origin/main`, non-force workflow.
10. Direct Overleaf publication, if performed, is a one-way projection from the
   verified authoritative main commit.

## Scientific Interpretation After the Revision

The article will offer a reproducible, theory-based way to scale the global
shrinkage prior without claiming that the reported experiments were rerun or
that one value is universally optimal. The recommendation keeps the prior
comparable across the nested Normal, AL, and exAL sequence, while the
supplement makes clear how readers may instead match local likelihood
information. The reported empirical results and all frozen provenance remain
unchanged.

## Validation Record

The source branch was checked with R 4.6.0 and the repository's TeX toolchain.

| Check | Result |
|---|---|
| Gaussian, AL, and exAL reference-scale unit checks | Passed |
| Invalid-domain checks for `m0`, `r`, `N_fit`, scale, probability level, and information factor | Passed |
| Numerical integration of the ordinary-horseshoe effective-size identity at six global-scale values | Passed |
| Changed R files parsed | 2/2 |
| Corrected-manuscript contract | Passed |
| JOINT Phase181 article projection | Passed: 32 rows and 16 contrasts |
| JOINT Phase181 interval-figure contract | Passed: 64 rows |
| Independent-validation v14 article contract | Passed: 328 checks, 72 point rows, 216 interval roles, and 6 figures |
| `git diff --check` | Passed |
| Main article compilation | Passed: 43 pages; no undefined references, missing citations, or box warnings |
| Supplement compilation | Passed: 53 pages; no undefined references, missing citations, or box warnings |
| Rendered task-specific numerical `tau0` values | None |

The complete application harness reaches
`application/tests/test_joint_qvp_qdesn_synthetic_artifacts.R` and then stops
in a pre-existing `rbind` column-count mismatch. The same command fails at the
same boundary in the clean `origin/main` worktree at `6414867e...`; the new
reference-calibration test passes before that boundary. This unrelated baseline
failure is recorded rather than repaired in a manuscript-prior change.
