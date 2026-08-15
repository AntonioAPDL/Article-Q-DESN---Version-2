# Joint exQDESN Phase 167/169 Method Selection

## Purpose

Phase 166 completed the structured variational comparison over all 480 matched
scenario, replicate, fit-structure, and method rows. Phase 167 freezes the
variational method used only to initialize the next exact-MCMC experiment.
Phase 169 then compares three exact samplers at a common computational budget.
Neither phase changes the model, article tables, or article claims.

The scientific objective is functional quantile-path performance. Improved
mixing of the exAL shape and scale parameters is useful insofar as it yields a
more stable approximation to the exact posterior. Perfect scalar-parameter
mixing is not a prerequisite when pooled quantile summaries are stable and all
implementation gates pass.

## Phase 166 Decision

The completed Phase 166 artifact contains 480 verified rows, no implementation
failures, and no contract-grid crossings. Its aggregate evidence supports
`VB1_structured_v` for both fit structures:

- Joint: 80/80 converged rows and no review rows.
- Independent: 75/80 converged rows; the five finite max-iteration cases remain
  review evidence.
- Structured-v is effectively tied with structured-u in fit and forecast
  metrics while being materially faster.
- Structured-u does not show a repeatable practical advantage across scenarios.

This is a variational initialization decision only. It does not reject the
`u = B_gamma v` augmentation for exact MCMC, where the geometry and transition
kernel differ.

## Frozen Model Controls

Phase 169 preserves the selected case-specific DESN and regularized-horseshoe
controls from the Phase 164 registry. It does not search for one specification
that must work across all scenarios. Model-control recalibration is deliberately
deferred while sampler geometry is isolated, because changing both at once
would confound the method comparison.

Fresh `VB1_structured_v` initializations are generated for one frozen replicate
of each selected scenario and fit structure. The compact initialization table,
matched dispersed scale/shape starts, seeds, registry rows, source hashes, and
provenance are frozen before any MCMC worker starts.

## Phase 169 Design

The prespecified scenarios are:

1. persistent heavy tail;
2. asymmetric-Laplace tail;
3. normal bridge;
4. nonlinear reservoir-friendly dynamics;
5. regime shift.

Both Joint and Independent exQDESN are evaluated. Three exact-target methods
are compared:

- `M0_v_collapsed_support_logit`: collapsed-scale baseline in the original
  latent coordinate;
- `M1b_u_collapsed_support_logit`: `u = B_gamma v` augmentation with the
  bounded-support logit coordinate;
- `M1_u_collapsed_p_logit`: `u = B_gamma v` augmentation with the probability
  coordinate.

Every scenario/structure/method cell uses eight matched chains, 12,000
iterations, 3,000 burn-in iterations, and storage thinning by three. This gives
240 chains and 3,000 retained draws per chain. Up to 32 chains run concurrently,
with one numerical thread per chain. Only compact compressed parameter draws are
retained; latent arrays are not serialized.

## Diagnostics And Gates

Hard implementation gates require complete verified manifests, unique seeds,
finite draws and scores, positive scales, and zero crossings after the declared
monotone quantile-grid contract. Raw crossings remain visible diagnostics.

Method assessment reports:

- oracle fit and forecast quantile MAE;
- fit and forecast check loss and grid CRPS;
- raw and contract crossing counts;
- rank-normalized and folded R-hat;
- bulk and tail ESS for gamma, sigma, `p_gamma`, actual response scale, and
  `sigma * lambda_gamma`;
- branch transitions and collapsed-density evaluations;
- first-four versus last-four chain-group quantile-summary sensitivity;
- total runtime and seconds per iteration.

Mixing thresholds are diagnostic review gates, not automatic evidence that a
statistically stable quantile summary must be discarded. An exact method can be
frozen only after implementation gates pass and the pooled quantile paths remain
stable across matched chain groups. Large or systematic functional differences
remain review evidence even if scalar R-hat improves.

## Commands

The production launcher prepares Phase 167 and the Phase 169 freeze, then starts
the committed 240-chain campaign in one background tmux session:

```bash
bash application/scripts/225_launch_joint_exqdesn_phase169_mcmc_method_selection.sh 32
```

Health is inspectable without altering the run:

```bash
Rscript application/scripts/224_check_joint_exqdesn_phase169_mcmc_method_selection.R
```

The launcher finalizes only if every worker exits successfully. The resulting
method-development artifact is not promoted to the manuscript. The next step is
to audit target invariance and functional stability, freeze one exact sampler,
and only then design the balanced article-confirmation campaign.
