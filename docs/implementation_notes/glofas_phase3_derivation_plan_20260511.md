# GloFAS Application Phase 3 Derivation Plan

Date: 2026-05-11

## Scope

Phase 3 develops the model-specific derivations for the GloFAS
discrepancy-calibration Q--DESN. The derivations belong in the supplement, not
in the main data-application section. The main article should keep only the
scientific data context, the modeling idea, the evaluation protocol, and the
claim boundaries.

The derivation uses the regularized horseshoe, implemented through the
Nishimura--Suchard product representation, as the default coefficient prior.
Ridge may remain a computational baseline elsewhere in the paper, but the
application derivation is written for the RHS default.

## Article Boundary

The main article should not carry the posterior algebra. Its application
section should state the data context, the target, the discrepancy-calibration
idea, the validation design, and the limits of the model. All complete-data
posteriors, full conditionals, MCMC updates, VB updates, and ELBO expressions
belong in the supplement.

The supplement should make the application model readable as a direct extension
of the base Q--DESN derivation. It should not introduce new notation unless the
notation is needed to distinguish reference observations, retrospective GloFAS
values, and issued GloFAS ensemble members.

## Model Factorization

The application uses two source labels:

- \(Y\): transformed reference streamflow;
- \(G\): retrospective and issued-ensemble GloFAS values.

For a fixed quantile level \(p_0\), the augmented readout vector is
\((\beta_{p_0},\alpha_{p_0})\), where \(\beta_{p_0}\) represents the reference
quantile path and \(\alpha_{p_0}\) represents the GloFAS discrepancy at the same
level. The source-specific design vectors encode this relation:

- reference row: \([x_i^\top,0^\top]^\top\);
- GloFAS row: \([x_i^\top,x_i^\top]^\top\).

The ensemble-member likelihood factorization is conditional on the latent
source quantile path and source-specific likelihood parameters. It should be
described as a modeling approximation motivated by the operational ensemble
construction, not as an unconditional independence claim about hydrologic
errors.

## Derivation Order

1. Define the source-indexed data blocks:
   reference observations \(Y\), retrospective GloFAS values, and issued GloFAS
   ensemble members.
2. Stack all contributions into one augmented design with source labels
   \(c\in\{Y,G\}\).
3. State the AL and exAL augmented likelihoods source by source.
4. Specify the RHS prior for the augmented coefficient vector, with weak
   Gaussian priors for intercepts and RHS shrinkage for non-intercept
   coefficients.
5. Write the full complete-data posterior.
6. Derive full conditional posteriors:
   coefficient block, latent \(v\) variables, exAL latent \(s\) variables, AL
   scale updates, exAL source-specific scale--asymmetry kernels, and RHS scale
   updates.
7. State the MCMC algorithm, using slice sampling on transformed coordinates
   for each exAL \((\sigma_c,\gamma_c)\) block.
8. State the mean-field VB family and CAVI updates, using Laplace--Delta only
   for smooth expectations involving the exAL source-specific
   scale--asymmetry blocks.
9. State the ELBO decomposition and identify which terms are exact and which
   are evaluated through the Laplace--Delta approximation.

## Validation Checks

The supplement should include internal checks for the most error-prone
expressions:

- With one source and no discrepancy coefficients, the derivation reduces to
  the ordinary Q--DESN readout derivation.
- With \(\gamma_c=0\) and the \(s\) variables omitted, the exAL expressions
  reduce to the AL expressions.
- The coefficient update is Gaussian because the augmented likelihood is
  conditionally Gaussian and the RHS prior is conditionally Gaussian.
- The RHS hierarchy is not the source of non-conjugacy; its scale updates
  remain inverse-gamma under the product representation.
- The non-conjugate updates are confined to the source-specific exAL
  scale--asymmetry blocks.
- Ensemble members enter as conditionally independent likelihood
  contributions given the forecast-system quantile path and source-specific
  likelihood parameters; this is not an unconditional independence claim about
  hydrologic errors.
- The discrepancy sign convention is \(q_G=q_Y+d_G\); in forecast scoring, the
  reference quantile is recovered as \(q_Y=q_G-d_G\) for horizons covered by an
  issued GloFAS ensemble.
- The final prediction object is posterior-draw based:
  \(q_Y^{(s)}=q_G^{(s)}-d_G^{(s)}\). Point summaries must be computed after
  this subtraction, not used as the primary Bayesian prediction contract.
- Posterior predictive draws, when reported, should be generated from the AL or
  exAL working likelihood using matched posterior draws of the calibrated
  quantile, source scale, and exAL asymmetry parameter.
- Any forecast beyond the issued GloFAS horizon requires a separate recursive
  path construction and should not be conflated with the in-window calibration
  derivation.
- The ELBO terms match the same complete-data joint density used by the MCMC
  sampler.

## Mechanical Checks

After editing:

- compile `qdesn-supplement.tex` at least twice;
- check the LaTeX log for undefined references, missing citations, overfull
  boxes introduced by the new section, and hard errors;
- run `git diff --check`;
- scan for misleading wording such as "exAL moments", "scale-shape", or any
  claim that the RHS hierarchy is the reason the posterior lacks a closed-form
  normalized distribution;
- verify that no long derivations were added to `main.tex`.

## Implementation Boundary

This plan does not implement the fitting code. Code should be written only
after the supplement derivations are reviewed, because the wrappers should
follow the final mathematical factorization exactly.
