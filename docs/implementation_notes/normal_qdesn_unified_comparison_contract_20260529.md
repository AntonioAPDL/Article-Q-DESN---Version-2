# Normal DESN And Q-DESN Unified Comparison Contract

Date: 2026-05-29

## Purpose

This note defines the final comparison contract for Normal DESN and Q-DESN
methods after the active Q-DESN mode work finishes. It was first written before
the final Q-DESN extended-mode pass landed, then updated after package commit
`f0d45ea Extend Q-DESN VB comparison and subset modes` and Normal warm-start
checkpoint `9f1c32d Cover RHS Normal warm-start labels`. The unified launcher
itself is implemented through package commit `63001e4 Write unified comparison
console log` and hardened through `b415b4d Harden unified comparison preflight
metadata`.

The comparison should answer three questions:

1. How do implemented Q-DESN AL/exAL modes behave on a controlled source
   median example?
2. How do Normal DESN mean-readout modes behave on the same source?
3. How useful are Normal DESN fits as initialization sources for Q-DESN VB or
   MCMC workflows?

## Timing Decision

Do not run the final authoritative unified comparison while another Codex chat
has dirty package changes. The previous dirty Q-DESN work landed as package
commit `f0d45ea`, and the Normal warm-start metadata stage landed through
`9f1c32d`. The final launcher landed through `63001e4` and was hardened through
`b415b4d`, so the final
comparison may proceed after verifying both repos are clean and synced.

Parallel work that is safe now:

- article-side comparison contract documentation;
- read-only API audit;
- result schema design;
- post-wait resume prompt.

Work to defer until the package repo is clean:

- package comparison script edits;
- final result generation;
- any authoritative claim about final method performance.

This condition is now satisfied for the package repo at `b415b4d`; the article
repo still has unrelated untracked GloFAS memory-refinement artifacts that
should be ignored or handled separately from this comparison.

## Repositories

Article repo:

```text
/data/jaguir26/local/src/Article-Q-DESN
branch: application-ensemble-likelihood-redesign
```

Package repo:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
branch: validation/shared-fitforecast-v2-1.0.0
```

Do not edit:

```text
/data/jaguir26/local/src/Article-Q-DESN__wt__main_overleaf_20260514
```

## Dataset

Use the controlled source median dataset from the shared validation study:

```text
/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500
```

Dataset metadata:

```text
scenario: dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast
family: normal
tau: 0.50
TT_main: 10000
TT_warmup: 2000
period: 90
normal_sigma: 10
q_true_equals_mu: TRUE
latent_seed: 12011
noise_seed: 12012
```

Primary files:

```text
series_wide.csv
series_long.csv
true_quantile_grid.csv
selection_indices.csv
sim_output.rds
```

The source is appropriate because, at `tau = 0.50` under Gaussian noise,
`q_true` equals the conditional mean. This makes it a clean bridge example for
comparing Normal DESN mean fits with Q-DESN median fits without claiming that
mean and quantile targets are generally identical.

## Method Families

### Normal DESN

Include when implemented and tested:

```text
normal_scaled_ridge
normal_scaled_ridge_exact_chunked
normal_rhs_vb
normal_rhs_ns_vb
normal_to_qdesn_al_vb_init
normal_to_qdesn_exal_vb_init
normal_to_qdesn_al_mcmc_init, if economical and already tested
```

Include the implemented serialized warm-start checks:

```text
normal_warm_start_to_al_vb_init
normal_warm_start_to_exal_vb_init
normal_warm_start_serialization_check
```

### Q-DESN

Include all implemented and safe modes at final package HEAD:

```text
qdesn_al_ridge_full
qdesn_al_ridge_exact_chunked
qdesn_al_ridge_stochastic
qdesn_al_ridge_hybrid
qdesn_al_ridge_diagonal_covariance
qdesn_al_ridge_fixed_subset
qdesn_al_stratified_subset_ridge
qdesn_al_stratified_response_subset_ridge
qdesn_al_stratified_leverage_subset_ridge
qdesn_al_rhs_full
qdesn_al_rhs_exact_chunked
qdesn_al_rhs_diagonal_covariance
qdesn_al_rhs_ns_full
qdesn_al_rhs_ns_exact_chunked
qdesn_al_rhs_ns_diagonal_covariance
qdesn_exal_ridge_full
qdesn_exal_ridge_exact_chunked
qdesn_exal_ridge_diagonal_covariance
qdesn_exal_ridge_hybrid
qdesn_exal_rhs_full
qdesn_exal_rhs_exact_chunked
qdesn_exal_rhs_hybrid
qdesn_exal_rhs_ns_full
qdesn_exal_rhs_ns_exact_chunked
qdesn_exal_rhs_ns_hybrid
qdesn_al_rolling_ridge
qdesn_al_posterior_as_prior_ridge
qdesn_al_online_ridge
```

Do not include as implemented unless final HEAD actually supports them:

```text
stochastic exAL
exAL RHS/RHS_NS diagonal covariance
RHS/RHS_NS posterior-as-prior
article-side stochastic/hybrid/rolling/online adapters
divide-and-combine VB
variational coresets
```

At package commit `f0d45ea`, `qdesn_exal_ridge_diagonal_covariance` is
implemented as a covariance-approximation diagnostic and should be included
with that label. It is not a recommended predictive default on the source gate
because its diagnostics were poor despite finite-state and exact-chunking
equivalence.

## Target Labels

Every row must carry one explicit target label:

```text
conditional_mean_exact
conditional_mean_exact_chunked
conditional_mean_vb_approx
initializer_workflow
quantile_full_data
quantile_exact_chunked
quantile_approx_stochastic
quantile_approx_hybrid
covariance_approximation
subset_target
rolling_window_target
posterior_as_prior_target
online_state_handoff
forbidden
```

Every row must also carry boolean flags:

```text
preserves_full_data_target
is_approximate
changes_data_target
is_workflow_tool
is_forbidden
```

## Required Metadata Columns

`method_summary.csv` should include:

```text
method_id
family
target_label
likelihood_family
prior_family
prior_details
covariance_form
chunking_mode
subset_mode
rolling_mode
online_mode
warm_start_source
preserves_full_data_target
is_approximate
changes_data_target
is_workflow_tool
seed
tau
desn_D
desn_n
desn_n_tilde
desn_m
train_rows
test_rows
source_index_min
source_index_max
design_hash
feature_settings_hash
package_sha
article_sha
converged
iterations
finite_state
runtime_sec
max_rss_kb
output_path
```

## Metrics

`prediction_metrics.csv` should include:

```text
method_id
split
n
pinball_loss
rmse_vs_q_true
mae_vs_q_true
rmse_vs_mu
mae_vs_mu
coverage_90_if_available
mean_prediction
sd_prediction
mean_truth
sd_truth
```

For Normal DESN, prediction should be interpreted as conditional mean unless
posterior predictive quantiles are explicitly computed. For the Gaussian
median source, mean and median truth align by construction.

## Exact Equivalence Gates

`exact_equivalence.csv` should compare:

- Normal scaled ridge exact chunked vs Normal scaled ridge unchunked;
- Q-DESN AL exact chunked vs Q-DESN AL unchunked for the same prior;
- Q-DESN exAL exact chunked vs Q-DESN exAL unchunked for the same prior;
- exact chunked subset target vs unchunked subset target, if subset is run;
- exact chunked online/PAP target vs unchunked online/PAP target, if run.

Required fields:

```text
pair_id
reference_method
candidate_method
tolerance
passed
max_beta_mean_diff
max_beta_cov_diff
max_sigma_diff
max_gamma_diff
max_prediction_diff
max_objective_diff
convergence_match
finite_state_match
```

Exact chunking must preserve the target. It must never update global factors
inside chunks; chunks may only accumulate row-additive sufficient statistics
before the same global update.

## Approximate Diagnostics

`approximate_diagnostics.csv` should include stochastic, hybrid, covariance
approximation, and approximate Normal RHS/RHS_NS rows.

Required fields:

```text
method_id
reference_method
approximation_type
seed
repeat_seed_diff
finite_state
converged
pinball_loss_diff
rmse_diff
beta_mean_distance
beta_cov_summary_distance
sigma_distance
gamma_distance
objective_label
notes
```

Approximate rows must never be described as exact equivalence failures. They
are different targets or approximate algorithms and should be judged by
stability, reproducibility, finite states, and predictive diagnostics.

## Target-Changing Diagnostics

`target_changing_diagnostics.csv` should include:

```text
method_id
reference_method
target_change_type
row_ids_or_window
handoff_metadata_present
order_sensitive
no_future_leakage_checked
prediction_metric_diff
notes
```

Target-changing examples include subset fits, rolling-window fits,
posterior-as-prior fits, and online state-handoff fits. These should be
compared to full-data results only as descriptive references, not as
same-target equivalence checks.

## Forbidden Modes

`forbidden_modes.csv` should record modes that were intentionally probed and
failed early:

```text
method_id
reason
expected_error_pattern
observed_error_pattern
passed_fail_early_check
```

At minimum, include unsupported high-risk modes that are easy to accidentally
enable:

```text
stochastic exAL
RHS/RHS_NS posterior-as-prior, unless implemented by final HEAD
exAL RHS/RHS_NS diagonal covariance
divide-and-combine VB
variational coresets
```

## Output Layout

Package generated outputs should go under an ignored result root:

```text
results/normal_qdesn_unified_source_median_20260529/
```

Expected files:

```text
repo_state.csv
component_runs.csv
method_summary.csv
prediction_metrics.csv
exact_equivalence.csv
approximate_diagnostics.csv
target_changing_diagnostics.csv
initializer_diagnostics.csv
forbidden_modes.csv
predictions_by_method.csv
normal_qdesn_unified_comparison_summary.md
console.log
time.log
```

Large generated outputs should not be committed.

Article tracked documentation should summarize the run in:

```text
docs/implementation_notes/normal_qdesn_unified_source_median_comparison_20260529.md
```

## Reproducibility Requirements

Before the final run:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
git status --short --branch
git fetch --all --prune
git status --short --branch
git log --oneline -8
```

Then run focused tests for the relevant implemented surface. At minimum:

```sh
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal-init-comparison.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-batching-modes.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-exact-chunking-stats.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-inference-config.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-subset-fit.R")'
```

Add tests for any methods introduced after this contract was written, especially
hybrid exAL or Normal warm-start metadata if present.

## Stop Gates

Stop and report instead of running the final comparison if:

- the package repo is dirty;
- final package HEAD differs from the article docs without an update note;
- focused tests fail;
- the source dataset is missing or hashes cannot be recorded;
- a method row cannot be labeled as exact, approximate, target-changing,
  workflow, or forbidden;
- exact chunking equivalence breaks;
- generated results would need to be committed;
- another active process is writing the same result directory.

## Recommended Execution Order

1. Fetch both repos.
2. Verify clean worktrees, ignoring unrelated GloFAS memory-refinement artifacts
   only if they are explicitly out of scope for this comparison.
3. Implement Normal DESN warm-start metadata if that stage has not yet landed.
4. Run Normal warm-start tests if package code changed after `9f1c32d`.
5. Run the unified comparison harness from a clean package HEAD:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
mkdir -p results/normal_qdesn_unified_source_median_20260529

/usr/bin/time -v \
  -o results/normal_qdesn_unified_source_median_20260529/time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_normal_qdesn_unified_source_median_20260529.R \
  --output-dir results/normal_qdesn_unified_source_median_20260529 \
  --source-dir /data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500 \
  --seed 20260529 \
  --D 1 \
  --n 50 \
  --m 1 \
  --washout 50 \
  --chunk-size 64 \
  --subset-size 180 \
  --max-iter 25 \
  --stochastic-max-iter 60 \
  --hybrid-max-iter 60 \
  --hybrid-full-every 15 \
  --cores 4
```

6. Commit compact article summary docs.
7. Do not commit large result files.
