# Joint QDESN Phase 116 Article-Readiness Audit

## Purpose

Phase 116 is a reproducible decision layer after the completed joint QDESN
validation stages:

- Phase 113 selected the current VB article candidate,
  `zeta2_16_inner10_gamma_zero_alpha0p5_tau0_0p5`;
- Phase 114 froze that candidate and launched the VB-initialized MCMC
  fit-window reference;
- Phase 115 rebuilt the article-facing tables and figures from the frozen VB
  source and the completed MCMC source.

The audit answers one narrow question: whether any joint-validation computation
still needs to finish before manuscript QA, or whether the next work should be
article framing, table/figure polish, and conservative wording.  It does not
rerun VB, MCMC, fixture generation, or forecast validation.

## Diagnosis

The current evidence supports the following diagnosis.

1. The Phase 114 MCMC reference completed.  The MCMC readiness table reports
   pass-level implementation, distance, and chain-status gates for all nine
   synthetic mechanisms.

2. The Phase 115 evidence pack remains `review`, not `pass`, because the
   selected VB forecast source preserves pre-rearrangement crossings as
   diagnostics.  The reported monotone forecast grid has zero contract
   crossings.

3. The MCMC reference is a fit-window posterior check for the primary Joint
   QDESN RHS row.  It should not be described as held-out forecast validation
   unless a separate MCMC forecast campaign is launched.

4. A new broad VB screen is not currently justified.  The remaining risk is
   manuscript framing: avoiding uniform-dominance claims, explaining
   raw-versus-reported quantile grids, and placing the MCMC evidence in the
   correct role.

## Implemented Audit

The new script is:

```sh
Rscript application/scripts/116_audit_joint_qdesn_article_readiness.R
```

Default source directories are:

- `application/cache/joint_qdesn_vb_spec_screening_phase113_20260708`;
- `application/cache/joint_qdesn_phase114_vb_article_candidate_freeze_20260708`;
- `application/cache/joint_qdesn_mcmc_article_phase114_20260708`;
- `application/cache/joint_qdesn_article_validation_assets_phase115_20260708`.

Default output directory:

```text
application/cache/joint_qdesn_phase116_article_readiness_audit_20260709
```

## Outputs

Phase 116 writes only inspectable text artifacts:

- `run_config.csv`;
- `readiness_decision_summary.csv`;
- `health_check_summary.csv`;
- `phase_status_summary.csv`;
- `source_manifest_summary.csv`;
- `gate_rollup.csv`;
- `scenario_sensitivity_summary.csv`;
- `tau_sensitivity_summary.csv`;
- `vb_mcmc_distance_focus.csv`;
- `manuscript_claim_audit.csv`;
- `next_action_plan.csv`;
- `provenance.csv`;
- `README.md`;
- `artifact_manifest.csv`.

The audit verifies top-level cache manifests, nested Phase 113 candidate
manifests, Phase 115 source manifests, and Phase 115 article table/figure asset
hashes.  A missing hash, missing source file, malformed manifest, or mismatched
SHA-256 is a hard failure.

## Gate Policy

Hard failure:

- any source/cache/asset manifest row fails;
- selected VB source is missing;
- Phase 114 MCMC has worker failures or non-pass scenario gates;
- reported MCMC or article contract grids cross.

Review:

- selected VB forecast source has pre-rearrangement crossings;
- comparator rows remain less stable than the primary Joint QDESN RHS row;
- model-comparison evidence does not support a uniform-dominance claim.

Pass:

- reproducibility and implementation gates pass;
- conservative manuscript claims are aligned with the generated evidence.

The expected current global gate is `review`: implementation is clean enough to
move forward, but the paper must retain explicit qualifications about
pre-rearrangement crossings and MCMC scope.

## Recommended Next Step

Do not wait for unrelated GloFAS or PriceFM runs.  Do not launch another broad
VB screen before manuscript QA.  The next joint-validation task should be:

1. keep Phase 113/114/115 artifacts frozen;
2. use `tables/joint_qdesn_article_validation_tables.tex` for the compact main
   article validation display;
3. keep `tables/joint_qdesn_article_validation_provenance_tables.tex` for
   reproducibility/provenance material;
4. polish the joint-validation prose around the reported monotone quantile grid,
   the retained raw-crossing diagnostics, and the fit-window-only MCMC role;
5. compile the manuscript and inspect table placement/readability.

Additional compute should be targeted only if manuscript QA creates a specific
claim that the current evidence does not support.

## Verification

Focused test:

```sh
Rscript application/tests/test_joint_qdesn_article_readiness_audit.R
```

Recommended adjacent tests:

```sh
Rscript application/tests/test_joint_qdesn_calibration_screening.R
Rscript application/tests/test_joint_qdesn_mcmc_readiness.R
Rscript application/tests/test_joint_qdesn_article_validation_assets.R
```
