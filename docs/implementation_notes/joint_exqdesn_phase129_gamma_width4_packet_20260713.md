# Phase129 Joint exQDESN exAL-RHS Gamma Width-x4 Packet

Date: 2026-07-13

## Motivation

Phase127 showed that the Joint exQDESN exAL-RHS MCMC reference was not failing because of the
VB initialization or scale bounds. The weak point was the exAL gamma block, especially for the
Laplace bridge case, where gamma at `tau = 0.75` had Rhat above `3.5` and rough ESS below `10`.

Phase128 then ran a single-case sampler pilot on that worst case with four bounded slice-width
multipliers: `1,2,4,8`. The main finding was clear:

- width x4 had the best ranking;
- worst gamma Rhat improved to about `1.04`;
- the difficult `tau = 0.75` gamma Rhat improved to about `1.00`;
- rough ESS improved by more than an order of magnitude;
- no worker failures and no sigma-bound hits occurred;
- residual review status was driven by high within-chain autocorrelation, not by between-chain
  disagreement.

Phase129 therefore promotes width x4 to the full eight-scenario Joint exQDESN exAL-RHS packet.
This is still a sampler-health confirmation layer, not a final article-table promotion.

## Scope

The Phase129 runner consumes the already selected Joint exQDESN exAL-RHS controls from:

- `application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711`;
- `application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711`.

Together these sources provide the eight Joint exQDESN exAL-RHS cases:

1. `asymmetric_laplace_tail`;
2. `gaussian_mixture_bridge`;
3. `laplace_bridge`;
4. `nonlinear_reservoir_friendly`;
5. `normal_bridge`;
6. `persistent_heavy_tail`;
7. `regime_shift`;
8. `student_t_location_scale`.

The runner does not mutate article tables, figures, or manuscript text.

## Runner

Script:

```bash
Rscript application/scripts/134_run_joint_exqdesn_exal_gamma_width4_packet.R
```

Default output:

```text
application/cache/joint_qdesn_phase129_joint_exqdesn_gamma_width4_packet_20260713
```

Default full controls:

- gamma slice-width multiplier: `4`;
- chains per case: `8`;
- MCMC iterations/burn/thin: `8000/2000/1`;
- chain workers: `24`;
- VB preparation workers: `4`;
- gamma initialization: deterministic `vb_jittered`;
- trace write stride: `50`;
- raw `.RData`: disabled.

The full traces are used in memory to compute diagnostics and generate PDFs. The written trace
table is compacted to avoid multiplying the Phase128 449 MB single-case trace file by eight.

## Outputs

Key outputs include:

- `run_config.csv`;
- `phase122_source_manifest_verification.csv`;
- `phase124c_source_manifest_verification.csv`;
- `fixture_source_manifest.csv`;
- `selected_case_controls.csv`;
- `case_preparation_failures.csv`;
- `chain_worker_failures.csv`;
- `chain_initialization.csv`;
- `vb_case_summary.csv`;
- `vb_gamma_sigma_lambda_trace.csv`;
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
- `figures/00_phase129_gamma_width4_packet_dashboard.pdf`;
- one trace PDF per scenario;
- `artifact_manifest.csv`.

## Gates

Hard fail:

- source manifest failure;
- case-preparation failure;
- chain-worker failure;
- missing/nonfinite Rhat or ESS diagnostics;
- incomplete chain count;
- nonfinite MCMC draws;
- sigma bound sensitivity.

Review:

- Rhat above `1.2`;
- rough ESS below `100`;
- gamma lag-1 autocorrelation above `0.98`;
- VB-LD reaches the maximum iteration budget but returns finite summaries.

Pass:

- all implementation gates pass;
- Rhat and ESS are acceptable;
- no sigma-bound behavior;
- residual gamma autocorrelation is below the review threshold.

The expected scientific possibility is that cases may remain review due to high autocorrelation even
when Rhat and ESS are much improved. That outcome would support longer chains or selected targeted
reruns rather than another broad slice-width screen.

## Smoke Verification

The implementation smoke command was:

```bash
Rscript application/scripts/134_run_joint_exqdesn_exal_gamma_width4_packet.R \
  --output-dir local_trackers/joint_exqdesn_phase129_gamma_width4_packet_smoke_20260713 \
  --case-limit 1 \
  --n-chains 2 \
  --mcmc-n-iter 8 \
  --mcmc-burn 4 \
  --mcmc-thin 1 \
  --n-cores 2 \
  --vb-n-cores 1 \
  --vb-max-iter-override 2 \
  --adaptive-vb-max-iter-grid-override 2 \
  --trace-write-stride 2 \
  --save-rdata false
```

The smoke run completed with zero case-preparation failures, zero chain failures, and a complete
SHA-256 manifest.

## Full Launch

Recommended full launch:

```bash
tmux new-session -d -s joint_exqdesn_phase129_gamma_width4_20260713 \
"cd /data/jaguir26/local/src/Article-Q-DESN---Version-2 && \
Rscript application/scripts/134_run_joint_exqdesn_exal_gamma_width4_packet.R \
  --output-dir application/cache/joint_qdesn_phase129_joint_exqdesn_gamma_width4_packet_20260713 \
  --width-multiplier 4 \
  --n-chains 8 \
  --mcmc-n-iter 8000 \
  --mcmc-burn 2000 \
  --mcmc-thin 1 \
  --n-cores 24 \
  --vb-n-cores 4 \
  --gamma-init-mode vb_jittered \
  --gamma-jitter-fraction 0.10 \
  --trace-write-stride 50 \
  --save-rdata false \
  > application/cache/joint_qdesn_phase129_joint_exqdesn_gamma_width4_packet_20260713_tmux.log 2>&1; \
echo EXIT_CODE=\\$? >> application/cache/joint_qdesn_phase129_joint_exqdesn_gamma_width4_packet_20260713_tmux.log"
```

## Next Decision

After Phase129 finishes:

1. verify `EXIT_CODE=0`;
2. verify source manifests and `artifact_manifest.csv`;
3. require zero case-preparation and chain-worker failures;
4. inspect `case_assessment.csv`, `case_ranking.csv`, and the trace PDFs;
5. identify whether all cases are implementation-clean;
6. if Rhat/ESS remain acceptable and only autocorrelation is review-level, consider a targeted
   longer-chain rerun for the remaining difficult cases;
7. only after the full exAL packet is stable, rebuild article-facing MCMC confirmation assets.
