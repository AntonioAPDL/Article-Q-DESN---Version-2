# Phase128 Joint exQDESN exAL-RHS Gamma-Mixing Pilot

Date: 2026-07-12

## Purpose

Phase127 reran the balanced Joint exQDESN exAL-RHS MCMC confirmation cases with retained
VB and MCMC traces. The VB initialization was healthy across the eight mechanisms, but the
MCMC diagnostics showed that the exAL skew parameter gamma can mix poorly, especially in the
Laplace bridge case. The worst Phase127 cell was:

- case: `laplace_bridge__joint_exqdesn_rhs_vb`;
- model: Joint exQDESN RHS under the exAL working likelihood;
- tau grid: `0.05,0.10,0.25,0.50,0.75,0.90,0.95`;
- worst gamma Rhat: about `3.53` at `tau = 0.75`;
- worst gamma rough ESS: below `10`;
- sigma bound hits: `0`;
- VB-LD: converged.

This pattern points to transition/mixing problems in the gamma block rather than burn-in failure
or scale-bound clipping. Phase128 is therefore a single-case sampler pilot before propagating any
change to the full eight-scenario article packet.

## Design

Phase128 keeps the validation model and selected VB controls fixed, then screens only the gamma
slice sampler behavior:

- source controls: Phase122 `case_winner_controls.csv`;
- case: `laplace_bridge__joint_exqdesn_rhs_vb`;
- source fixture: `joint_qdesn_simulation_dgp_fixtures_20260706`;
- VB step: refit the selected AL initialization and exAL VB-LD state once;
- MCMC step: run multiple chains from deterministic VB-based starts;
- gamma update: bounded slice sampler with per-tau width multipliers;
- default width multipliers: `1,2,4,8`;
- default chains per width: `8`;
- default iterations/burn/thin: `6000/1500/1`;
- default chain starts: `vb_jittered`, which perturbs the VB gamma state across chains inside the
  exAL support;
- raw `.RData`: not saved by default.

The core sampler remains the same Gibbs/slice implementation used by the article confirmation
runner. The only code-path extension is that `app_joint_qvp_fit_exal_mcmc_tiny()` now accepts a
scalar or per-tau `gamma_slice_width`, which preserves the previous default when the argument is
omitted.

## Artifacts

The runner is:

```bash
Rscript application/scripts/133_run_joint_exqdesn_exal_gamma_mixing_pilot.R
```

The default full output directory is:

```text
application/cache/joint_qdesn_phase128_laplace_bridge_gamma_mixing_pilot_20260712
```

Key outputs:

- `run_config.csv`;
- `phase122_source_manifest_verification.csv`;
- `fixture_source_manifest.csv`;
- `selected_case_control.csv`;
- `width_experiment_registry.csv`;
- `chain_initialization.csv`;
- `chain_worker_failures.csv`;
- `vb_gamma_sigma_lambda_trace.csv`;
- `vb_al_init_sigma_trace.csv`;
- `vb_objective_trace.csv`;
- `vb_monitor_terms.csv`;
- `mcmc_gamma_sigma_lambda_trace.csv`;
- `mcmc_rhat_ess_summary.csv`;
- `chain_mean_gap_summary.csv`;
- `autocorrelation_summary.csv`;
- `variant_assessment.csv`;
- `variant_ranking.csv`;
- `runtime_summary.csv`;
- `figures/00_phase128_gamma_mixing_dashboard.pdf`;
- one trace PDF per width variant;
- `artifact_manifest.csv`.

## Gates

Phase128 uses conservative diagnostic gates:

- hard fail: source hash failure, worker failure, nonfinite gamma/sigma traces, or missing required
  diagnostics;
- review: Rhat above `1.2`, rough ESS below `100`, gamma lag-1 autocorrelation above `0.98`, or
  any sigma bound hit;
- pass: finite traces, no worker failures, stable scale behavior, and acceptable chain diagnostics.

A review outcome is expected for short smoke tests and may still be acceptable for a bounded
diagnostic pilot. Promotion to the full article packet requires a clear improvement relative to
Phase127, especially in gamma Rhat, gamma rough ESS, lag-1 autocorrelation, and chain mean gaps.

## Smoke Verification

The smoke command used during implementation was:

```bash
Rscript application/scripts/133_run_joint_exqdesn_exal_gamma_mixing_pilot.R \
  --output-dir local_trackers/joint_exqdesn_phase128_gamma_pilot_smoke_20260712 \
  --width-multipliers 1,2 \
  --n-chains 2 \
  --mcmc-n-iter 8 \
  --mcmc-burn 4 \
  --mcmc-thin 1 \
  --n-cores 2 \
  --vb-max-iter-override 2 \
  --adaptive-vb-max-iter-grid-override 2 \
  --save-rdata false
```

The smoke run completed with zero worker failures and a complete SHA-256 artifact manifest. Its
review gate is expected because the chains are deliberately too short for statistical diagnostics.

## Full Pilot Launch

The full background launch should use:

```bash
tmux new-session -d -s joint_exqdesn_phase128_gamma_laplace_20260712 \
"cd /data/jaguir26/local/src/Article-Q-DESN---Version-2 && \
Rscript application/scripts/133_run_joint_exqdesn_exal_gamma_mixing_pilot.R \
  --output-dir application/cache/joint_qdesn_phase128_laplace_bridge_gamma_mixing_pilot_20260712 \
  --width-multipliers 1,2,4,8 \
  --n-chains 8 \
  --mcmc-n-iter 6000 \
  --mcmc-burn 1500 \
  --mcmc-thin 1 \
  --n-cores 16 \
  --gamma-init-mode vb_jittered \
  --gamma-jitter-fraction 0.10 \
  --save-rdata false \
  > application/cache/joint_qdesn_phase128_laplace_bridge_gamma_mixing_pilot_20260712_tmux.log 2>&1; \
echo EXIT_CODE=\\$? >> application/cache/joint_qdesn_phase128_laplace_bridge_gamma_mixing_pilot_20260712_tmux.log"
```

## Next Step

After Phase128 finishes:

1. verify the manifest and worker-failure table;
2. compare `variant_ranking.csv` against Phase127;
3. inspect the dashboard and per-width trace PDFs;
4. select a sampler configuration only if the gamma diagnostics improve materially;
5. propagate the selected sampler policy to the remaining seven Joint exQDESN exAL-RHS cases;
6. only after the full exAL packet is stable, rebuild article-facing MCMC confirmation assets.

This stage does not mutate article tables or claims.
