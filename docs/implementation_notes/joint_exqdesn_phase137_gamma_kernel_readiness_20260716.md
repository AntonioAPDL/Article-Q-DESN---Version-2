# Joint exQDESN Phase137 gamma-kernel readiness

Date: 2026-07-16

Repository: `/data/jaguir26/local/src/Article-Q-DESN---Version-2`

## Purpose

Phase137 is a post-Phase136 decision layer. It does not launch new MCMC jobs and it does not modify
the article. Its role is to turn the completed Phase136 gamma-kernel packet into a reproducible
readiness artifact that answers four questions:

1. Did Phase136 finish cleanly enough to support the next stage?
2. Which gamma update should be retained for each high-priority exAL case?
3. Did Phase136 materially improve the matched exAL rows relative to Phase135 VB, and are they now
   competitive with the matched AL rows?
4. What exact selected long-chain confirmation should be launched next, if approved?

This stage keeps the scientific contract quantile-grid based: fit/forecast MAE to oracle quantiles,
check loss, grid CRPS, coverage/hit diagnostics, and raw/contract crossing diagnostics. It does not
claim scalar posterior predictive density validation.

## Inputs

Default Phase136 source:

```text
application/cache/joint_qdesn_phase136_exal_gamma_kernel_packet_20260715
```

Phase136 compared two gamma updates on five high-priority matched exAL MCMC cases:

- `bounded_w4`, the existing bounded slice update with width multiplier 4;
- `logit_w4`, the transformed logit-scale slice update with eta width 4.

The packet completed with:

- 5 cases;
- 10 case-variants;
- 80 chain jobs;
- 0 preparation failures;
- 0 chain failures;
- 0 raw qhat crossings;
- 0 contract qhat crossings.

All case-variants remain `review`, primarily because gamma lag-1 autocorrelation remains high and
some rows exceed the Rhat review threshold.

## Manifest handling

Phase136 has a bookkeeping issue in its manifest: figure files were written under `figures/`, but
their manifest rows record only the PDF basenames. Phase137 therefore writes two manifest
verification tables:

- `phase136_manifest_strict_verification.csv`, which preserves the strict failure;
- `phase136_manifest_repaired_verification.csv`, which verifies the same hashes after applying a
  transparent `figures/` path repair;
- `phase136_manifest_repair_map.csv`, which lists exactly which rows were repaired.

The Phase136 artifact is not mutated by Phase137.

## Main findings from Phase136

The case-specific winner pattern is mixed:

- `bounded_w4` is selected for three cases:
  - `laplace_bridge__joint_exqdesn_rhs_vb`;
  - `nonlinear_reservoir_friendly__exqdesn_rhs_independent_vb`;
  - `regime_shift__joint_exqdesn_rhs_vb`.
- `logit_w4` is selected for two cases:
  - `nonlinear_reservoir_friendly__joint_exqdesn_rhs_vb`;
  - `student_t_location_scale__joint_exqdesn_rhs_vb`.

The global pattern does not justify replacing the bounded sampler everywhere. The bounded update is
slightly better on average forecast MAE, has better worst-case Rhat behavior, and is faster. The
logit update is still valuable for the two cases where it improves the selected performance.

Relative to Phase135 matched exAL VB, the Phase136 selected MCMC rows improve forecast MAE in most
of the high-priority rows. However, they remain worse than the corresponding matched AL rows in all
five selected cases. This means Phase136 is useful progress, but not article-ready evidence for
claiming that exAL has caught up with AL.

## Decision

The Phase137 decision is:

```text
review_ready_for_selected_long_chain_confirmation
```

This means:

- do not launch a broad 16-row exAL MCMC packet yet;
- do not update article-facing validation tables from Phase136 alone;
- do run one selected long-chain confirmation if the user approves the launch.

The next stage should test whether the selected case-specific gamma kernels stabilize performance
and posterior diagnostics when the same total compute is focused on winners instead of split across
losing variants.

## Recommended next launch

Phase137 prepares a selected long-chain confirmation using the existing Phase136 runner. Because
the current runner accepts a common `variant_ids` value per invocation, the efficient launch is two
selected-kernel packets:

1. selected `bounded_w4` cases;
2. selected `logit_w4` cases.

Recommended controls:

```text
n_chains = 8
mcmc_n_iter = 16000
mcmc_burn = 4000
mcmc_thin = 1
mcmc_seed_offset = 8600
save_rdata = false
```

This keeps the total chain-iteration budget close to Phase136:

```text
Phase136: 10 case-variants x 8 chains x 8000 iterations = 640000 chain-iterations
Phase138 proposal: 5 case-variants x 8 chains x 16000 iterations = 640000 chain-iterations
```

The proposed design is therefore aggressive but not broader than the completed packet. It focuses
the same order of compute on the case-kernel pairs most likely to matter.

## Generated artifacts

Default output:

```text
application/cache/joint_qdesn_phase137_exal_gamma_kernel_readiness_20260716
```

Artifacts:

- `run_config.csv`;
- `phase136_manifest_strict_verification.csv`;
- `phase136_manifest_repaired_verification.csv`;
- `phase136_manifest_repair_map.csv`;
- `phase137_health_summary.csv`;
- `phase137_kernel_variant_summary.csv`;
- `phase137_case_delta_summary.csv`;
- `phase137_phase136_vs_phase135_summary.csv`;
- `phase137_selected_case_kernel_registry.csv`;
- `phase137_next_launch_plan.csv`;
- `phase137_decision_summary.csv`;
- `phase137_launch_commands.txt`;
- `provenance.csv`;
- `README.md`;
- `artifact_manifest.csv`.

## Commands

Focused test:

```bash
Rscript application/tests/test_joint_exqdesn_phase137_gamma_kernel_readiness.R
```

Generate the readiness packet:

```bash
Rscript application/scripts/146_prepare_joint_exqdesn_phase137_gamma_kernel_readiness.R
```

The exact Phase138 commands are written to:

```text
application/cache/joint_qdesn_phase137_exal_gamma_kernel_readiness_20260716/phase137_launch_commands.txt
```

## Gates before article integration

Before any article table is updated, the next long-chain confirmation must satisfy:

- source manifests verified, allowing only documented figure-path repair for Phase136 history;
- no worker failures;
- finite fit and forecast scores;
- zero contract qhat crossings;
- raw crossings reported separately;
- selected exAL rows compared against Phase135 VB and matched AL rows;
- MCMC diagnostics reviewed with emphasis on posterior qhat performance first, and gamma mixing as
  an approximation-quality diagnostic rather than a perfection requirement.

If the selected long-chain run remains worse than matched AL across the main cases, the next step is
not broader confirmation. It is either a more targeted exAL calibration/sampler redesign or a
manuscript decision to keep exAL as a diagnostic extension rather than the primary article-facing
winner.
