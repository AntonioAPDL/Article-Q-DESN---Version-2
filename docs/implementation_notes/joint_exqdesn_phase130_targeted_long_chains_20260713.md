# Phase130 Joint exQDESN exAL-RHS Targeted Long-Chain Plan

Date: 2026-07-13

## Starting Point

Phase129 propagated the Phase128-selected gamma slice-width multiplier x4 to all eight Joint
exQDESN exAL-RHS scenarios. It completed cleanly:

- `EXIT_CODE=0`;
- 8/8 cases completed;
- 64/64 MCMC chains completed;
- zero case-preparation failures;
- zero chain-worker failures;
- 37/37 artifact hashes verified;
- no raw `.RData` files were saved;
- all sigma and gamma draw summaries were finite;
- no sigma lower/upper bound hits were observed.

The Phase129 output is:

```text
application/cache/joint_qdesn_phase129_joint_exqdesn_gamma_width4_packet_20260713
```

## Diagnostic Audit

The Phase129 packet is an implementation pass and a statistical review. The remaining review flags
are concentrated in the gamma/sigma pair at one quantile for two scenarios:

| Scenario | Problem cell | Phase129 Rhat | Phase129 rough ESS |
|---|---:|---:|---:|
| `nonlinear_reservoir_friendly` | gamma and sigma at tau `0.25` | about `1.42` | about `147` |
| `student_t_location_scale` | gamma and sigma at tau `0.75` | about `1.29` | about `161` |

The other six scenarios have acceptable Rhat/ESS by the current conservative thresholds, although
gamma lag-1 autocorrelation remains high. This pattern argues against another broad slice-width
screen. Width x4 fixed the catastrophic between-chain disagreement observed in Phase127/Phase128.
The remaining problem is slow within-chain movement for selected cells.

## Phase130 Decision

Phase130 should run a targeted longer-chain confirmation only for:

- `nonlinear_reservoir_friendly`;
- `student_t_location_scale`.

The purpose is to test whether longer chains resolve the remaining Rhat review cells without
changing the model or starting another broad sampler screen.

## Controls

The default Phase130 wrapper is:

```bash
Rscript application/scripts/135_run_joint_exqdesn_exal_phase130_targeted_long_chains.R
```

It delegates to the Phase129 packet runner with:

- scenario ids: `nonlinear_reservoir_friendly,student_t_location_scale`;
- gamma slice-width multiplier: `4`;
- chains per case: `12`;
- MCMC iterations/burn/thin: `16000/4000/1`;
- MCMC workers: `24`;
- VB preparation workers: `2`;
- gamma initialization: deterministic `vb_jittered`;
- trace write stride: `100`;
- raw `.RData`: disabled.

The expected workload is 24 chains total. Based on Phase129 runtimes, this should be several hours
rather than another full broad campaign.

## Outputs

Default output:

```text
application/cache/joint_qdesn_phase130_joint_exqdesn_targeted_long_chains_20260713
```

The output schema is inherited from Phase129:

- `run_config.csv`;
- source manifest verifications;
- `selected_case_controls.csv`;
- `case_preparation_failures.csv`;
- `chain_worker_failures.csv`;
- `chain_initialization.csv`;
- `vb_case_summary.csv`;
- `mcmc_gamma_sigma_lambda_trace_compact.csv`;
- `mcmc_rhat_ess_summary.csv`;
- `chain_mean_gap_summary.csv`;
- `autocorrelation_summary.csv`;
- `mcmc_draw_summary.csv`;
- `vb_mcmc_distance_summary.csv`;
- `chain_to_pooled_distance_summary.csv`;
- `runtime_summary.csv`;
- `case_assessment.csv`;
- `case_ranking.csv`;
- per-scenario trace PDFs;
- `artifact_manifest.csv`.

## Gates

Hard fail:

- nonzero exit code;
- source manifest failure;
- case-preparation failure;
- chain-worker failure;
- incomplete chain count;
- nonfinite draws or scores;
- sigma bound hits;
- missing artifact manifest or hash mismatch.

Review:

- any Rhat above `1.2`;
- any rough ESS below `100`;
- gamma lag-1 autocorrelation above `0.98`;
- large chain-to-pooled dispersion relative to Phase129.

Pass for targeted promotion:

- both targeted cases have finite diagnostics;
- no implementation failures;
- problem-cell Rhat is below `1.2`;
- rough ESS remains above `100`;
- no sigma-bound sensitivity.

High autocorrelation alone should remain a review flag, not a hard failure, if Rhat/ESS and finite
diagnostics are acceptable.

## Next Decision

After Phase130:

1. If both targeted cases pass Rhat/ESS gates, merge the Phase129 six clean cases with the Phase130
   targeted replacements and rebuild article-facing Joint exQDESN MCMC validation assets.
2. If one targeted case still fails Rhat, use a sampler-level intervention rather than another
   width sweep: likely a gamma reparameterization, block update, or tempered/overrelaxed bounded
   gamma move.
3. Do not change article claims until this targeted MCMC layer is audited and hash-manifested.
