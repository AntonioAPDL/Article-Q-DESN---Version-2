# Joint exQDESN Phase145 Gamma Sampler Root-Cause Screen

Date: 2026-07-23

## Purpose

Phase145 tests sampler-only improvements for the sampled-gamma `exQDESN RHS`
model under the exAL working likelihood. It does not change the model, the
gamma support, the article claims, or the quantile-grid validation contract.

The motivating evidence is that previous sampled-gamma exAL runs remained
performance-weaker than the matched AL model and the fixed-gamma-zero exAL
sensitivity layer. The Phase144A 32-chain support-grid run made the issue
clearer: the chains retained strong gamma initialization memory at tail
quantiles and gamma chain means were almost perfectly compensated by sigma chain
means. This points to gamma-sigma ridge geometry rather than simply too few
retained samples.

## Implementation

Phase145 adds optional target-preserving refresh controls to
`app_joint_qvp_fit_exal_mcmc_tiny()`:

- `gamma_refresh_repeats`: number of gamma refresh passes per tau block;
- `gamma_refresh_block`: one of `none`, `sigma`, `sigma_s`, or `sigma_s_v`.

The default remains exactly the original behavior:

```r
gamma_refresh_repeats = 1L
gamma_refresh_block = "none"
```

When the repeat count is greater than one, the sampler can perform additional
conditional updates after a gamma draw. For example, `sigma` repeats update
sigma under the current gamma and then update gamma again; `sigma_s` also
refreshes the half-normal latent variable; `sigma_s_v` refreshes the GIG latent
variable as well. These are sampler-kernel changes, not model changes.

The Phase136 gamma-kernel packet runner was extended to accept a custom variant
registry and to record the sampler controls in all relevant metadata. Existing
Phase136 behavior is preserved when no custom registry is supplied.

## Phase145 Variants

The Stage145B root-cause screen uses one case first:

`student_t_location_scale__joint_exqdesn_rhs_vb`

The variants isolate different hypotheses:

| Variant | Initialization | Step-out | Refresh | Hypothesis |
|---|---|---:|---|---|
| `phase145_logit_w4_vb_local` | VB-local jitter | 100 | none | support-grid overdispersion may be too aggressive |
| `phase145_logit_w4_support_steps500` | support grid | 500 | none | stronger step-out may help remote starts |
| `phase145_logit_w4_vb_steps500` | VB-local jitter | 500 | none | local starts plus stronger step-out |
| `phase145_logit_w4_vb_refresh3_sigma` | VB-local jitter | 500 | gamma-sigma x3 | gamma-sigma ridge-breaking |
| `phase145_logit_w4_vb_refresh5_sigma` | VB-local jitter | 500 | gamma-sigma x5 | stronger ridge-breaking |
| `phase145_logit_w4_vb_refresh3_sigma_s` | VB-local jitter | 500 | gamma-sigma-s x3 | latent `s` lag diagnosis |

## Artifacts

The runner writes the usual Phase136 fit/forecast scoring artifacts plus
Phase145-specific diagnostics:

- `phase145_variant_registry.csv`;
- `gamma_chain_memory_summary.csv`;
- `gamma_sigma_ridge_summary.csv`;
- `tail_gamma_region_summary.csv`;
- `phase145_decision_summary.csv`;
- `README_phase145.md`;
- refreshed `artifact_manifest.csv`.

The chain-memory summary measures whether final gamma chain means remain
ordered by chain id. The ridge summary measures gamma-sigma chain-mean
correlation by tau and variant. These diagnostics are interpreted alongside
forecast MAE, fit MAE, check loss, grid CRPS, raw/contract crossings, R-hat,
ESS, and runtime.

## Gates

Hard fail:

- worker or preparation failures;
- nonfinite traces, qhat, or scores;
- contract quantile crossings;
- missing or invalid artifact hashes.

Review:

- high gamma R-hat or autocorrelation with finite qhat metrics;
- strong chain-initialization memory;
- high gamma-sigma chain-mean correlation;
- raw crossings repaired by the monotone contract;
- runtime too high for propagation.

Pass:

- implementation gates pass;
- qhat metrics improve against recent sampled-gamma references;
- gamma diagnostics improve enough, or remaining weakness is clearly bounded
  and does not harm quantile-grid performance.

## Launch Command

The Stage145B launch used:

```bash
tmux new-session -d -s joint_exqdesn_phase145_student_t_root_cause_20260723 \
  'cd /data/jaguir26/local/src/Article-Q-DESN---Version-2 && \
   Rscript application/scripts/153_run_joint_exqdesn_phase145_gamma_sampler_root_cause_screen.R \
     --output-dir application/cache/joint_qdesn_phase145_gamma_sampler_root_cause_student_t_20260723 \
     --case-ids student_t_location_scale__joint_exqdesn_rhs_vb \
     --n-chains 8 \
     --mcmc-n-iter 10000 \
     --mcmc-burn 3000 \
     --mcmc-thin 2 \
     --n-cores 32 \
     --vb-n-cores 6 \
     --trace-write-stride 50 \
     --save-rdata false \
     --dry-run false'
```

Log:

`application/logs/joint_qdesn_phase145_gamma_sampler_root_cause_student_t_20260723.log`

Output:

`application/cache/joint_qdesn_phase145_gamma_sampler_root_cause_student_t_20260723`

## Verification

Focused tests:

```bash
Rscript application/tests/test_joint_qvp_qdesn_exal_mcmc.R
Rscript application/tests/test_joint_exqdesn_phase145_gamma_sampler_root_cause.R
Rscript application/tests/test_joint_exqdesn_phase141_gamma_redesign_readiness.R
Rscript application/tests/test_joint_exqdesn_phase142_post_geometry_synthesis.R
```

The script dry-run was also executed and its manifest verified.

## Next Step

Stage145B completed all 48 requested chains but the first implementation
failed during Phase145-only post-processing because the lean
`mcmc_trace_summary.csv` table did not carry the newly added sampler metadata.
The chain packet itself was valid: worker failures were zero, preparation
failures were zero, and the recovered artifact manifest verified 56/56 hashes.
The recovery script is:

```bash
Rscript application/scripts/154_recover_joint_exqdesn_phase145_gamma_sampler_root_cause_artifacts.R \
  --output-dir application/cache/joint_qdesn_phase145_gamma_sampler_root_cause_student_t_20260723
```

Recovered Stage145B evidence:

- gate status: `review`;
- best forecast MAE: `phase145_logit_w4_vb_local` at about 0.1067;
- best gamma geometry: `phase145_logit_w4_vb_refresh3_sigma_s`, with the
  smallest gamma R-hat, largest gamma ESS, smallest chain-mean gap, and lowest
  max lag-1 gamma autocorrelation among the serious variants;
- support-grid initialization is not acceptable for propagation because it
  creates extreme tail chain-memory and R-hat failures;
- all MCMC raw and contract crossing counts were zero.

The next stage is therefore not another broad search. It is a focused
Stage145C long confirmation on the same `student_t_location_scale` case:

1. `phase145_logit_w4_vb_local`: the current best forecast-performance path;
2. `phase145_logit_w4_vb_refresh3_sigma_s`: the current best geometry path.

Stage145C increases chain support and retained draws while keeping the exAL
model and DESN/RHS specification fixed. It is still a sampler diagnostic layer,
not an article-table promotion layer.

Recommended Stage145C command:

```bash
bash application/scripts/155_launch_joint_exqdesn_phase145_focus_long_student_t_overnight.sh
```

After Stage145C completes, audit:

1. worker/preparation failures and manifest hashes;
2. best variant by forecast MAE and fit MAE;
3. gamma chain-memory summaries;
4. gamma-sigma ridge summaries;
5. R-hat, ESS, lag-1 autocorrelation, and runtime;
6. raw and contract crossing summaries.

Only if Stage145C improves qhat metrics and/or gamma geometry enough to justify
the cost should its sampler settings be propagated to the remaining high-priority
exQDESN cases. If Stage145C keeps the same gap relative to fixed-gamma or AL
references, stop sampler-only tuning and keep the conservative Phase143 article
position while describing sampled-gamma exAL as a reviewed sensitivity layer.
