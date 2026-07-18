# Joint exQDESN Phase140 Gamma-Redesign Readiness

Date: 2026-07-17

## Purpose

Phase139 showed that longer selected exAL MCMC chains improved gamma diagnostics, but did not make the exAL rows competitive with the matched AL rows for the article-facing forecast metric. The correct next step is therefore not another broad brute-force MCMC run. Phase140 prepares a targeted sensitivity that isolates the most likely mechanism: whether the additional exAL skew parameter is hurting quantile-grid performance when it is allowed to move freely.

This stage is a readiness and launch-plan stage only. It does not edit article tables and does not launch new MCMC jobs.

## Audit Diagnosis

The Phase139 synthesis supports these conclusions:

- Implementation gates were clean: no worker failures, finite metrics, zero raw/contract crossings in the selected long-chain packet.
- Gamma-chain diagnostics improved relative to the earlier packet, but remained review-level for some rows.
- The exAL rows improved over the previous exAL VB baseline in most priority cases.
- The exAL rows still did not match or beat the matched AL rows on the forecast MAE comparison used for article-facing promotion.

This pattern suggests that poor mixing is not the only issue. The next diagnostic should ask whether the gamma degree of freedom itself is degrading the quantile-grid summaries. A fixed-gamma-zero packet is the most direct experiment: it keeps the DESN and RHS specification fixed, preserves the exAL code path, but removes gamma movement.

## Implemented Contract

Phase140 adds a fixed-gamma sensitivity hook to the existing exAL MCMC path:

- `gamma_update = "fixed"` is accepted by `app_joint_qvp_fit_exal_mcmc_tiny()`.
- Phase136-style packets now accept `variant_id = "fixed_zero"`.
- Fixed gamma initialization is taken from the matched Phase135 control policy, falling back to zero when no explicit policy is present.
- The generated launch command uses the existing Phase136 runner with `--variant-ids fixed_zero`.

Defaults remain unchanged for existing bounded-slice and logit-slice MCMC paths.

## Generated Artifact

The readiness script writes:

```text
application/cache/joint_qdesn_phase140_exal_gamma_redesign_readiness_20260717
```

Expected files:

- `run_config.csv`
- `phase139_manifest_verification.csv`
- `phase140_case_priority.csv`
- `phase140_method_feasibility.csv`
- `phase140_fixed_gamma_launch_plan.csv`
- `phase140_decision_summary.csv`
- `phase140_launch_commands.txt`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

The fixed-gamma launch is prepared, not run:

- Variant: `fixed_zero`
- Gamma update: `fixed`
- Chains per case: `8`
- Iterations: `12000`
- Burn-in: `3000`
- Thin: `1`
- Maximum cores in launch command: `32`

## Interpretation

If fixed-gamma-zero exAL recovers matched-AL performance, then the main issue is gamma movement, and the next model-design stage should prioritize gamma shrinkage or a more stable gamma parameterization.

If fixed-gamma-zero exAL remains worse than matched AL, then the issue is not only gamma mixing. The stronger conclusion would be that the current exAL specification is not article-ready for promotion, and the article should keep Joint QDESN RHS under AL as the primary validation anchor while treating exAL as a diagnostic extension.

## Verification

Focused tests should include:

```bash
Rscript application/tests/test_joint_qvp_qdesn_exal_mcmc.R
Rscript application/tests/test_joint_exqdesn_phase137_gamma_kernel_readiness.R
Rscript application/tests/test_joint_exqdesn_phase139_long_chain_synthesis.R
Rscript application/tests/test_joint_exqdesn_phase140_gamma_redesign_readiness.R
Rscript application/scripts/149_prepare_joint_exqdesn_phase140_gamma_redesign_readiness.R
```

## Next Step

Review the Phase140 readiness artifact. If the plan is accepted, launch only the prepared fixed-gamma-zero sensitivity packet. Do not promote exAL to article tables until that packet is complete, audited, and compared against both Phase138 exAL MCMC and matched AL rows.
