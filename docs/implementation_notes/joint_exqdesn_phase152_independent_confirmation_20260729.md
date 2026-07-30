# Joint exQDESN Phase152 Independent Confirmation

## Purpose

Phase151 found two case-specific deterministic feature maps that improved the
Joint exQDESN RHS VB forecast quantile-path MAE on the original formal
simulation realization:

- a balanced hybrid map for the Gaussian-mixture bridge;
- a compact hybrid map for the nonlinear reservoir-friendly mechanism.

Those gains were obtained on one DGP realization and one reservoir draw. They
are useful screening evidence, but they are not enough to replace the direct
feature rows in an article table. Phase152 tests whether each fixed map
generalizes across independent DGP and reservoir seeds before spending time on
MCMC.

This is a confirmation stage, not a new specification screen. It does not
change the exAL target, gamma update, posterior summary, RHS controls, VB
controls, scoring contract, or Phase151 feature-map hyperparameters.

## Why This Is the Next Nonredundant Experiment

Phases128--150 already examined gamma slice geometry, chain length and count,
thinning, posterior mean/median/trimmed summaries, RHS and intercept controls,
alternative gamma kernels and priors, target invariance, scenario-specific VB
calibration, and eight-chain MCMC. Phase151 was the first actual reservoir-state
feature-map experiment.

The remaining uncertainty is therefore not another local sampler setting. It
is whether the two Phase151 gains survive:

1. a new response path from the same declared mechanism; and
2. a new sparse reservoir realization with the same frozen geometry.

Phase152 isolates both sources of uncertainty and has an explicit stopping
rule. A rejected map closes this branch rather than launching another broad
screen.

## Frozen Inputs

The source of truth is the completed Phase151 packet:

`application/cache/joint_qdesn_phase151_case_specific_feature_screening_20260728`

and its readiness packet:

`application/cache/joint_qdesn_phase151_case_specific_feature_screening_readiness_20260728`

The preparation step verifies the root and selected-candidate manifests before
copying any controls. The original formal fixture and registry remain unchanged.

The two frozen maps retain their Phase151 settings exactly:

| Mechanism | Map | Width | Alpha | Rho | Sparse recurrent rate | Input scale |
|---|---:|---:|---:|---:|---:|---:|
| Gaussian-mixture bridge | hybrid balanced | 12 | 0.86 | 0.95 | 0.20 | 0.20 |
| Nonlinear reservoir-friendly | hybrid compact | 8 | 0.92 | 0.90 | 0.25 | 0.18 |

The original Phase151 reservoir seeds are retained only for the conditional
MCMC confirmation. They are not used in the fresh VB gate.

## Independent Confirmation Design

The VB layer uses:

- two mechanisms;
- ten new DGP seeds per mechanism;
- the unchanged 12,000-row DGP geometry;
- a 2,000-row DGP warmup;
- the final 2,000-row analysis window;
- a 500-row DESN washout;
- a 500-row fit window;
- a 1,000-row validation window;
- forecast origins every 30 observations;
- horizons 1--30 without refitting;
- one direct-feature control per DGP replicate;
- three independent reservoir seeds for the selected feature map.

This produces 20 fresh fixtures and 80 VB jobs:

`2 scenarios x 10 DGP replicates x (1 direct + 3 reservoir)`.

Within each DGP replicate, the three selected-map results are reduced by their
median before comparison with the paired direct control. This prevents a lucky
reservoir seed from determining the DGP-level decision. Seed-level evidence is
also retained so robustness is inspectable.

The original Phase151 realization is not included in any promotion count.

## VB Promotion Gates

Implementation hard failures are:

- a source or checkpoint hash failure;
- a missing or nonfinite score;
- a nonfinite/nonpositive scale;
- a nonfinite gamma summary;
- a contract quantile crossing;
- an incomplete candidate set.

For each mechanism, the fixed feature map is promoted to MCMC only if all of
the following hold:

- at least 8 of 10 paired DGP medians improve forecast truth MAE;
- the median forecast MAE gain is at least `max(0.0025, 2%)`;
- the median fit-MAE ratio is at most 1.05;
- median forecast check-loss and grid-CRPS ratios are at most 1.02;
- at least 70% of the 30 reservoir-seed comparisons improve forecast MAE;
- at least 5 of 7 quantile levels are nonworse;
- no quantile-level deterioration exceeds `max(0.01, 10%)`.

These gates deliberately distinguish implementation validity from statistical
promotion. A statistically rejected feature map is a valid completed result,
not an implementation failure.

## Conditional MCMC Layer

Only surviving maps receive MCMC. Each survivor is refit by VB on the original
formal Phase151 fixture and then receives:

- 8 chains;
- 8,000 iterations per chain;
- 2,000 burn-in iterations;
- thinning by 4;
- fixed, recorded chain seeds;
- the validated Phase122 exAL/RHS sampler;
- the unchanged original Phase151 reservoir map.

Chains are independent parallel jobs and are checkpointed separately. A
restart verifies every checkpoint hash and runs only missing chains. This
avoids the former sequential-within-case bottleneck and supports exact resume.

The MCMC packet reports gamma, sigma, and exAL-lambda traces, R-hat, rough ESS,
chain-mean gaps, autocorrelations, fit and forecast quantile-grid scores, raw
and contract crossings, monotone adjustments, and comparisons with the
Phase150 direct exAL row and the article Joint QDESN AL anchor.

Mixing is diagnostic rather than the sole optimization target. Performance
confirmation requires improvement over the Phase150 direct exAL forecast MAE,
a fit-MAE ratio no greater than 1.05, and check-loss/grid-CRPS ratios no greater
than 1.02. Gamma or sigma R-hat/ESS can make the result review-level even when
the performance gate passes.

## Reproducibility and Artifacts

Readiness:

`application/cache/joint_qdesn_phase152_independent_confirmation_readiness_20260729`

Fresh fixtures:

`application/cache/joint_qdesn_phase152_independent_confirmation_fixtures_20260729`

VB confirmation:

`application/cache/joint_qdesn_phase152_independent_confirmation_vb_20260729`

Conditional MCMC:

`application/cache/joint_qdesn_phase152_independent_confirmation_mcmc_20260729`

Orchestration:

`application/cache/joint_qdesn_phase152_independent_confirmation_20260729_orchestration`

Every root packet and every VB/MCMC checkpoint has a SHA-256 manifest.
Provenance, seed roles, frozen controls, DGP identities, and reservoir
identities are stored in CSV.

No article asset is modified by Phase152. Any article change is a separate,
article-safe decision after the final MCMC packet is audited.

## Commands

Focused test:

```bash
Rscript --vanilla application/tests/test_joint_exqdesn_phase152_independent_confirmation.R
```

Prepare only:

```bash
bash application/scripts/177_launch_joint_exqdesn_phase152_independent_confirmation.sh
```

Launch or resume the complete conditional workflow:

```bash
PHASE152_WORKERS=16 \
bash application/scripts/177_launch_joint_exqdesn_phase152_independent_confirmation.sh \
  --execute --workers 16
```

Health check:

```bash
Rscript --vanilla \
  application/scripts/176_check_joint_exqdesn_phase152_independent_confirmation.R
```

The launcher constrains BLAS libraries to one thread per worker. The VB layer
uses up to 16 candidate workers. If MCMC is eligible, up to 16 chain jobs run
in parallel. The same command is safe to rerun because both layers verify and
reuse complete checkpoints.

## Decision After Completion

There are only three valid outcomes:

1. No feature map survives: retain the Phase150 direct exAL article rows and
   close the feature-map branch.
2. A map survives VB but not MCMC performance: retain the Phase150 row and
   record the independent confirmation as negative evidence.
3. A map survives VB and MCMC: perform a separate article-safe audit before
   replacing any table row or wording.

This stopping structure prevents another cycle of broad screens while still
giving the two genuinely promising Phase151 maps a rigorous confirmation.
