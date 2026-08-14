# Joint-QVP Manuscript Model Subsection Audit

Date: 2026-07-06

## Scope

This note records the manuscript-facing audit for adding a joint
quantile-vector readout subsection to `main.tex`. The edit is scoped to the
joint-QVP synthetic validation material and does not change TT500, GloFAS, or
PriceFM application evidence.

## Files Inspected

- `Academic_Writing_Style_Profile_v0.2.md`
- `AGENTS_academic_writing_snippet.md`
- `docs/audits/full_manuscript_style_audit.md`
- `docs/audits/reader_focused_style_audit.md`
- `docs/implementation_notes/joint_exal_qvp_qdesn_rhs_model_plan_20260630.md`
- `docs/implementation_notes/joint_exal_qvp_qdesn_rhs_derivation_checklist_20260701.md`
- `docs/implementation_notes/joint_qvp_synthetic_dgp_phase4l_manuscript_integration_audit_plan_20260706.md`
- `application/R/joint_qvp_qdesn.R`
- `main.tex`

## Audit Findings

1. The manuscript now reports a joint multi-quantile synthetic validation
   bundle, but the model section previously introduced only the
   single-quantile Q--DESN readout and the post hoc synthesis contract.
2. The related-work paragraph still said Q--DESN fits each quantile level
   separately. That statement is correct for the primary single-quantile model
   and independent-grid applications, but it is incomplete after adding the
   joint-QVP validation section.
3. The implemented joint-QVP lane uses a fixed DESN design, ordered
   quantile-specific intercepts, and an anchor plus adjacent-difference RHS
   prior on non-intercept readout slopes.
4. The fused prior encourages noncrossing and borrows strength across levels,
   but it does not impose deterministic noncrossing constraints for every
   design row. The manuscript therefore must continue to distinguish raw
   quantile diagnostics from the monotone forecast-output contract.
5. The coefficient correlation matrix is an induced variational posterior
   summary from the coupled Gaussian coefficient factor. It is not a separately
   parameterized correlation matrix with its own prior.

## Implemented Manuscript Decisions

- Added `\subsection{Joint Quantile-Vector Readout}` after the
  single-quantile prior specification and before the GP interpretation.
- Defined the joint readout
  `q_{k,t} = alpha_k + z_t' beta_k` for a fixed quantile grid.
- Stated the AL augmented working likelihood used in the reported validation
  and noted that the exAL analogue follows from the existing single-quantile
  augmentation.
- Documented the ordered-intercept prior and fused RHS prior on readout-slope
  increments.
- Defined the induced prior precision
  `P_beta = H' P_Delta H`.
- Clarified that `R_beta` is an induced variational posterior coefficient
  correlation matrix.
- Revised the related-work and post hoc synthesis paragraphs so the
  independent-grid, joint-readout, raw-diagnostic, and monotone-contract roles
  are separated.
- Cross-referenced the joint synthetic validation section back to the new
  model subsection.

## Claim Boundaries

- The new subsection does not claim a global noncrossing theorem.
- The monotone forecast-output contract is described as the scored and reported
  multi-quantile forecast object, not as a hidden change to the likelihood.
- The joint-QVP validation is kept separate from TT500, GloFAS, and PriceFM
  evidence.
- The added text follows the style profile by defining notation before use,
  separating model specification from computation, and labeling approximate VB
  covariance summaries as approximations.
