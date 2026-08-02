# Joint exQDESN Phase156/157 collapsed gamma-scale confirmation

## Purpose

Phase156/157 tests whether the persistent exAL gamma-scale ridge can be reduced without changing the statistical model or replacing the case-specific DESN specifications selected in Phase149/150. The scientific objective remains posterior quantile-grid performance. Perfect parameter mixing is not required, but Monte Carlo error and between-chain sensitivity must be small enough that fit and forecast conclusions are stable.

## Why this stage is new

Phases128--155 already examined longer runs, additional chains, bounded and logit slice widths, gamma priors, fixed gamma, correlated Metropolis moves, alternative posterior summaries, feature designs, and case-specific DESN/RHS calibration. Repeating those screens would not identify a new mechanism.

The audit also found that the prototype exAL MCMC function historically used `a_sigma = b_sigma = 0.1` and a zero/flat intercept default unless callers supplied the selected controls. The VB validation contract uses the frozen case-specific scale prior and an empirical-quantile ordered-intercept prior. Phase157 supplies these controls explicitly. Consequently, Phase150 is a useful historical benchmark but not an exact same-prior transition-kernel control.

## Partially collapsed transition

At each quantile level, condition on the current regression coefficients, intercept, and exAL latent variables. The conditional scale kernel is generalized inverse Gaussian (GIG). Phase157 analytically integrates the scale from the gamma update, samples gamma on its bounded logit coordinate with slice sampling, and then samples scale from its exact GIG conditional.

This is a partially collapsed Gibbs transition: the gamma update no longer conditions on the current point along the near-deterministic gamma-scale ridge, while the target model and all other blocks remain unchanged. The implementation includes an algebraic decomposition test comparing the direct joint gamma-scale log kernel with its GIG representation.

All data-length sums in the collapsed density are reduced once per quantile update to exact sufficient statistics. Slice-density evaluations are therefore constant-time in the fit-window length; the regression and latent-state updates remain unchanged. Tests compare the reduced and direct GIG terms and collapsed log kernels to numerical tolerance.

## Frozen design

- Eight synthetic mechanisms are retained.
- Each mechanism keeps its own Phase150 DESN design, RHS `tau0`, `zeta2`, scale prior, and intercept-prior controls.
- VB-LD is run once per mechanism and frozen as inspectable CSV parameters/traces.
- Eight chains per mechanism use deterministic, mildly overdispersed gamma and scale starts around that mechanism's VB-LD solution.
- Each chain uses 12,000 iterations, 3,000 burn-in iterations, and thinning by 3, yielding 3,000 retained draws.
- Workers are independently resumable and write compressed CSV draws; no `.RData`, `.rda`, or `.rds` object is retained.
- The launcher dynamically caps concurrency from the host core count and concurrent R load, with 24 workers requested and 16 logical cores reserved by default.

## Artifacts

Phase156 freeze:

`application/cache/joint_qdesn_phase156_collapsed_gamma_sigma_freeze_20260731`

The freeze records source hash verification, selected controls, VB initialization and traces, chain starts, seeds, the chain plan, the prior-contract audit, the kernel audit, provenance, and an artifact manifest.

Phase157 output:

`application/cache/joint_qdesn_phase157_collapsed_gamma_sigma_mcmc_20260731`

Each worker writes `posterior_draws.csv.gz`, chain and sampler summaries, runtime, provenance, README, and a SHA-256 manifest. The automatic finalizer writes scenario-level fit/forecast scores, raw and contract crossing diagnostics, monotone adjustments, rank-normalized and folded split R-hat, bulk/tail ESS, MCSE, rank histograms, gamma-scale correlations, chain-group qhat stability, Phase150 comparisons, provenance, and a top-level manifest.

## Gates

Hard failure is reserved for invalid source hashes, malformed controls, invalid/nonfinite draws, missing worker manifests, or crossings after the monotone scoring contract. Raw crossings, rank-normalized R-hat above 1.05, bulk ESS below 400, or material first-half/second-half chain-group score differences remain review evidence. Performance and Monte Carlo stability are reported separately so imperfect gamma mixing is not confused with automatic predictive failure.

## Commands

Prepare the immutable freeze:

```bash
Rscript application/scripts/189_prepare_joint_exqdesn_phase156_collapsed_gamma_sigma.R
```

Launch the resumable campaign:

```bash
bash application/scripts/191_launch_joint_exqdesn_phase157_collapsed_gamma_sigma.sh --execute
```

Check progress:

```bash
Rscript application/scripts/192_check_joint_exqdesn_phase157_collapsed_gamma_sigma.R
```

The controller runs the finalizer automatically after all 64 worker manifests verify. Manual finalization is available through `application/scripts/193_finalize_joint_exqdesn_phase157_collapsed_gamma_sigma.R`.

## Promotion rule

Phase157 is diagnostic evidence, not an automatic article promotion. Article assets should change only if the corrected same-contract MCMC packet is complete, hash-verified, contract-noncrossing, score-stable across chain groups, and materially improves or clarifies the case-specific Joint exQDESN evidence.

## Phase156b/157b recovery amendment

The first Phase157 execution completed the expensive sampling loop in every worker but failed before publishing posterior draws. The common error was

```text
formal argument "check.names" matched by multiple actual arguments
```

The defect was confined to construction of the posterior-draw data frame: a `cbind()` call forwarded `check.names` through more than one data-frame method. No worker wrote a verified posterior manifest, so the in-memory draws could not be recovered after each process exited. This is an implementation failure, not evidence about the sampler or the statistical model.

Phase156b is a parent-linked recovery freeze. It preserves the original Phase156 scenario controls, VB-LD initializations, overdispersed starts, seeds, chain lengths, burn-in, thinning, and slice controls. The amendment changes only worker output paths, source hashes, draw serialization, explicit failure receipts, and fail-fast orchestration. A parent-child identity audit and the failed-run signature audit are included in the new manifest.

The corrected lifecycle contract is:

1. Assemble named draw blocks explicitly and reject inconsistent dimensions, duplicate names, nonfinite values, or nonpositive scales.
2. Atomically publish the compressed draw table and verify every worker manifest before marking the worker complete.
3. On any error, write a structured receipt containing the worker, case, chain, seed, failure stage, condition, timestamp, and source hash.
4. Admit workers through a bounded parallel controller. The first worker failure creates an abort sentinel; already-running workers drain, while queued workers are marked `skipped_after_abort`.
5. Finalize only when all 64 worker manifests verify. Health reporting distinguishes verified, running, failed, skipped, incomplete, and queued workers.

Before the full campaign is admitted, script 195 executes the production worker twice on one real frozen fixture with a short implementation-only chain. The gate requires deterministic canonical draw content, successful serialization/deserialization, finite scoring, positive scale draws, zero contract crossings, complete hashes, and observable injected-failure receipts. These short runs are not statistical validation evidence.

Recovery artifacts:

```text
application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802
local_trackers/joint_exqdesn_phase157b_worker_preflight_20260802
application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802
application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802_orchestration
```

For an isolated worktree, ignored cache directories are not shared automatically. Pass absolute paths to the authoritative v2 cache instead of copying fixtures or creating an undocumented cache clone. The recovery sequence is:

```bash
Rscript application/scripts/194_amend_joint_exqdesn_phase156b_collapsed_gamma_sigma.R \
  --parent-freeze-dir /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase156_collapsed_gamma_sigma_freeze_20260731 \
  --failed-phase157-dir /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase157_collapsed_gamma_sigma_mcmc_20260731 \
  --failed-orchestration-dir /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase157_collapsed_gamma_sigma_mcmc_20260731_orchestration \
  --output-dir /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802 \
  --phase157b-dir /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802

Rscript application/scripts/195_preflight_joint_exqdesn_phase157b_worker_lifecycle.R \
  --freeze-dir /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802 \
  --output-dir /data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/joint_exqdesn_phase157b_worker_preflight_20260802

bash application/scripts/191_launch_joint_exqdesn_phase157_collapsed_gamma_sigma.sh \
  --freeze-dir /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802 \
  --preflight-dir /data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/joint_exqdesn_phase157b_worker_preflight_20260802 \
  --output-dir /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802 \
  --orchestration-dir /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802_orchestration \
  --execute
```

The launcher requires a clean committed source tree whose `HEAD` matches `source_commit.csv` in Phase156b. The default resource policy requests at most 24 single-threaded workers, reserves 16 logical cores, and further reduces admission based on concurrent R load. Admission also requires at least 64 GiB of available memory and 10 GiB of free artifact storage. It does not weaken statistical controls when capacity is lower.
