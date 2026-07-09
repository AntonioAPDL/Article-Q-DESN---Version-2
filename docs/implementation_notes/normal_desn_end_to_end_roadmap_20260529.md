# Normal DESN End-to-End Roadmap

Date: 2026-05-29

## Purpose

This note defines the staged implementation plan for extending the Normal
DESN work into a fully documented, tested, and reproducible package workflow.
It is intended to guide an overnight implementation pass without blurring the
mathematical targets.

The Normal DESN is a conditional-mean Gaussian DESN readout. It is not a
quantile likelihood. Its main roles are:

- a fast Gaussian baseline for Q-DESN AL/exAL comparisons;
- a stable initialization source for AL/exAL VB and MCMC;
- a future memory-safe and rolling/online Gaussian companion to Q-DESN.

The current implemented stage already provides:

- exact scaled-ridge Normal DESN readout;
- approximate Normal DESN RHS/RHS_NS VB readout;
- Q-DESN wrapper `qdesn_fit_normal()`;
- fixed-design posterior draws and posterior predictive draws;
- `predict_mu.qdesn_normal_fit()`;
- `posterior_predict.qdesn_normal_fit()`;
- `qdesn_normal_to_vb_init()`;
- `qdesn_normal_to_mcmc_init()`;
- a simulated behavior smoke showing that Normal initializers can seed AL/exAL
  VB and AL MCMC.

## Current Repositories

Article repo:

```text
/data/jaguir26/local/src/Article-Q-DESN
branch: application-ensemble-likelihood-redesign
current Normal DESN doc commit: a1852cc
```

Package repo:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
branch: validation/shared-fitforecast-v2-1.0.0
current Normal DESN package commit: 40c6de9
```

Known workspace caution:

```text
Package file with unrelated local changes:
scripts/run_qdesn_vb_implemented_modes_source_median_20260528.R
```

Do not overwrite, revert, or stage that file unless a later stage explicitly
adopts it.

Do not edit the Overleaf/main worktree unless explicitly instructed:

```text
/data/jaguir26/local/src/Article-Q-DESN__wt__main_overleaf_20260514
```

## Mathematical Guardrails

### Exact scaled-ridge target

The exact Normal DESN target is:

```text
y | beta, omega2, X ~ N(X beta, omega2 I)
beta | omega2       ~ N(b, omega2 P^{-1})
omega2              ~ IG(a, b)
```

with inverse-gamma density proportional to:

```text
x^{-a-1} exp(-b/x).
```

The posterior is:

```text
P_n = P + X'X
h_n = P b + X'y
m_n = P_n^{-1} h_n
a_n = a + T / 2
B_n = b + 0.5 (y'y + b'P b - m_n'P_n m_n)
```

This target is exact and full-data preserving.

### RHS/RHS_NS target

Normal DESN RHS/RHS_NS is an approximate global VB readout. RHS/RHS_NS states
are global shrinkage states and must not be row-batched or described as exact
conjugate posteriors.

### Initialization target

Normal DESN initializers are workflow tools. They do not define a new
posterior target. If an AL/exAL fit runs to convergence, the posterior target
remains the AL/exAL target.

## Stage 0: Synchronize and Baseline Freeze

### Objectives

- Confirm both repositories are clean except for known unrelated work.
- Freeze current Normal DESN behavior before implementing extensions.
- Avoid mixing article documentation, package code, and unrelated local work.

### Commands

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
git status --short --branch
git fetch --all --prune
git log --oneline -5

cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
git status --short --branch
git fetch --all --prune
git log --oneline -5
```

### Baseline tests

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-qdesn-normal.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-likelihood-family.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-batching-modes.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-static-beta-prior-rhs.R")'
```

Stop if any baseline test fails.

## Stage 1: Exact Chunked Normal DESN Scaled Ridge

### Objective

Implement exact row chunking for the scaled-ridge Normal DESN. This is the
highest-value next step because it is mathematically simple, memory useful,
and directly parallel to the exact chunked Q-DESN VB work.

### Sufficient statistics

Unchunked:

```text
S_xx = X'X
s_xy = X'y
s_yy = y'y
T    = nrow(X)
```

Chunked:

```text
S_xx = sum_b X_b'X_b
s_xy = sum_b X_b'y_b
s_yy = sum_b y_b'y_b
T    = sum_b n_b
```

Then use the same exact posterior equations as the unchunked path.

### API

Extend `normal_desn_fit()` through `control$chunking`:

```r
control = list(
  chunking = list(
    enabled = TRUE,
    mode = "exact",
    chunk_size = 512L,
    order = "sequential",
    trace = FALSE
  )
)
```

Rules:

- `mode = "exact"` only.
- `order = "sequential"` only.
- Support scaled ridge first.
- RHS/RHS_NS chunking remains forbidden until separately derived.
- Non-exact modes fail early.

### Files

Package:

```text
R/qdesn_normal.R
tests/testthat/test-qdesn-normal.R
man/qdesn_normal.Rd
```

Article:

```text
docs/implementation_notes/normal_desn_exact_chunked_stage_20260529.md
docs/implementation_notes/normal_desn_implementation_stage_20260529.md
```

### Tests

Required tests:

- one chunk equals unchunked;
- many chunks equal unchunked;
- chunk size one equals unchunked;
- `qdesn_fit_normal()` forwards `normal_args$control$chunking`;
- invalid chunking mode fails;
- stochastic/hybrid chunking fails;
- RHS/RHS_NS with chunking fails for this stage;
- posterior mean, beta covariance, `omega2$a`, `omega2$b`, and log marginal
  likelihood match the unchunked reference.

Tolerances:

```text
fixed design: 1e-10
Q-DESN wrapper: 1e-8
```

### Commit boundary

Package:

```text
Add exact chunked Normal DESN readout
```

Article:

```text
Document exact chunked Normal DESN stage
```

## Stage 2: Normal DESN Source-Median Comparison Harness

### Objective

Compare implemented Normal DESN methods against implemented Q-DESN methods on
an economical source-median example that resembles the validation study.

### Dataset

Use the frozen Gaussian median source subset:

```text
/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500
```

Primary files:

```text
series_wide.csv
series_long.csv
true_quantile_grid.csv
selection_indices.csv
sim_output.rds
```

### Methods

Compare only implemented and safe methods:

```text
normal_scaled_ridge
normal_scaled_ridge_exact_chunked
normal_rhs_ns_vb
qdesn_al_ridge
qdesn_al_ridge_exact_chunked
qdesn_al_ridge_stochastic
qdesn_exal_ridge
qdesn_exal_ridge_exact_chunked
```

Optional if already stable in the current harness:

```text
qdesn_al_rhs_ns
qdesn_exal_rhs_ns
```

### Labels

Every row must include:

```text
likelihood_family
target
target_label
prior_family
exact_status
approximation_status
init_source
design_hash
feature_settings_hash
package_sha
seed
```

Recommended target labels:

```text
conditional_mean_exact
conditional_mean_exact_chunked
conditional_mean_vb_approx
quantile_full_data
quantile_exact_chunked
quantile_approx_stochastic
```

### Metrics

Because Normal DESN is a conditional-mean model, not a quantile likelihood,
report metrics carefully:

```text
RMSE against y
MAE against y
tau = 0.5 pinball
beta L2 norm
sigma or omega2 summary
finite-state flags
runtime
max RSS if measured
convergence status where applicable
```

Do not claim Normal DESN is a quantile model. For Gaussian median examples,
mean and median coincide under the predictive Normal distribution, which
makes tau 0.5 pinball interpretable as a median proxy.

### Outputs

Ignored package results:

```text
results/normal_desn_source_median_comparison_20260529/
```

Tracked package script:

```text
scripts/run_normal_desn_source_median_comparison_20260529.R
```

Tracked article note:

```text
docs/implementation_notes/normal_desn_source_median_comparison_20260529.md
```

### Tests

If a reusable package script is added, add a small synthetic smoke test:

```text
tests/testthat/test-qdesn-normal-comparison-script.R
```

The test should not require the real source folder.

### Commit boundary

Package:

```text
Add Normal DESN source comparison harness
```

Article:

```text
Document Normal DESN source-median comparison
```

## Stage 3: Normal Initialization Comparison

### Objective

Evaluate whether Normal DESN initialization is useful for AL/exAL VB and MCMC.

### Methods

Use the same source-median setup when possible:

```text
al_vb_cold
al_vb_normal_scaled_ridge_init
al_vb_normal_rhs_ns_init
exal_vb_cold
exal_vb_normal_scaled_ridge_init
exal_vb_normal_rhs_ns_init
al_mcmc_cold_tiny
al_mcmc_normal_scaled_ridge_init_tiny
```

MCMC should remain a tiny smoke unless explicitly authorized for a larger run.

### Diagnostics

Track:

```text
convergence flag
iteration count
ELBO/objective final value where available
finite-state flags
beta L2 norm
sigma/gamma summaries
runtime
RMSE
pinball
initialization source
initialization design hash
initialization package SHA
```

### Interpretation rules

- Do not claim Normal initialization improves performance unless the comparison
  supports it.
- Normal initialization is a workflow mechanism, not a new posterior target.
- If Normal RHS/RHS_NS initialization is unstable, keep only scaled ridge as
  supported and document the failure.

### Files

Package:

```text
scripts/run_normal_desn_init_comparison_20260529.R
tests/testthat/test-qdesn-normal-init-comparison.R
```

Article:

```text
docs/implementation_notes/normal_desn_initialization_comparison_20260529.md
```

### Commit boundary

Package:

```text
Add Normal DESN initialization comparison
```

Article:

```text
Document Normal DESN initialization comparison
```

## Stage 4: Recursive Normal Forecast Paths

### Objective

Implement recursive forecast paths for `qdesn_normal_fit`.

This should be separate from `forecast_paths.qdesn_fit()` because the existing
Q-DESN forecast code assumes AL/exAL posterior draws with `beta`, `sigma`, and
`gamma`.

### Forecast model

For draw `s`:

```text
beta^(s), omega2^(s)
y_{t+h}^{(s)} = x_{t+h}^{(s)'} beta^(s) + epsilon_{t+h}^{(s)}
epsilon_{t+h}^{(s)} ~ N(0, omega2^(s))
```

### API

```r
forecast_paths.qdesn_normal_fit(
  object,
  H,
  nd = 1000L,
  y_hist = NULL,
  xreg_hist = NULL,
  xreg_future = NULL,
  seed = NULL,
  draws = NULL,
  return_design = FALSE,
  ...
)
```

### Tests

Required tests:

- seed reproducibility;
- finite paths;
- correct dimensions;
- `H = 1` smoke;
- `H > 1` recursive smoke;
- posterior-draw reuse;
- no calls to AL/exAL noise machinery;
- clear failures for unsupported exogenous or decomposition cases.

### Commit boundary

Package:

```text
Add recursive Normal DESN forecast paths
```

Article:

```text
Document recursive Normal DESN forecast paths
```

## Stage 5: Normal DESN Method Availability Matrix

### Objective

Update the article-side method availability and comparison roadmap so Normal
DESN appears alongside implemented Q-DESN modes.

### Availability rows

```text
Normal DESN scaled ridge
Normal DESN exact chunked scaled ridge
Normal DESN RHS/RHS_NS VB
Normal DESN as AL/exAL initializer
Q-DESN AL
Q-DESN AL exact chunked
Q-DESN AL stochastic
Q-DESN exAL
Q-DESN exAL exact chunked
Q-DESN hybrid exAL if enabled on the package branch
```

### Labels

Use explicit labels:

```text
conditional_mean_exact
conditional_mean_exact_chunked
conditional_mean_vb_approx
initializer_workflow
quantile_full_data
quantile_exact_chunked
quantile_approx_stochastic
```

### Files

Article:

```text
docs/implementation_notes/normal_desn_qdesn_method_availability_20260529.md
docs/implementation_notes/qdesn_vb_method_availability_20260528.md
```

### Commit boundary

Article:

```text
Document Normal DESN method availability
```

## Stage 6: Normal DESN Warm-Start Object

### Objective

Create a serializable Normal DESN warm-start object. This is workflow metadata,
not a new posterior target.

### API

```r
qdesn_normal_make_warm_start(object, X = NULL, package_sha = NULL)
qdesn_normal_validate_warm_start(warm_start, X, meta, strict = TRUE)
```

### Metadata

Required fields:

```text
type = qdesn_normal_warm_start
version
beta mean/cov
omega2 posterior
target label
prior family
design hash
feature settings hash
package SHA
package version
DESN settings
```

### Tests

Required tests:

- serialization round trip;
- design hash mismatch fails;
- feature settings hash mismatch fails;
- package SHA validation optionality;
- warm start can rebuild AL/exAL VB and MCMC initialization lists.

### Commit boundary

Package:

```text
Add Normal DESN warm-start metadata
```

Article:

```text
Document Normal DESN warm-start metadata
```

## Stage 7: Normal Rolling and Online Companion

### Objective

Implement rolling or expanding Normal DESN refits only after forecast and
warm-start paths are stable.

### Rolling API

```r
qdesn_normal_fit_rolling(
  y,
  origins,
  window = c("expanding", "rolling"),
  window_size = NULL,
  normal_args = list(),
  ...
)
```

### Posterior-as-prior caution

Posterior-as-prior is mathematically natural for Normal readouts but requires a
separate derivation because the scaled-ridge prior is variance scaled.

Do not implement Normal posterior-as-prior until one of these contracts is
chosen:

- carry the full Normal-inverse-gamma posterior forward;
- carry a Gaussian beta approximation with clearly documented target change.

### Tests

Required tests:

- one-batch online equals ordinary Normal fit;
- exact chunked batch equals unchunked batch;
- rolling window no-leakage;
- expanding window monotone row inclusion;
- handoff metadata reproducibility.

### Commit boundary

Package:

```text
Add Normal DESN rolling refits
```

Online/posterior-as-prior should be a separate later commit.

## Stage 8: Future Normal DESN Batch Extensions

Exact chunking is Stage 1.

Do not implement stochastic or hybrid Normal DESN batching until:

- exact chunking is complete;
- source-median comparison is stable;
- initialization comparison is stable;
- a stochastic Gaussian posterior contract is written.

The future contract must define:

```text
sampling scheme
n / batch_size scaling
sigma or omega2 update
prior scaling
RHS global-state updates
objective diagnostics
seed/reproducibility behavior
```

## Reproducibility Standard

Every result-producing script must record:

```text
package SHA
package version
article SHA if article files are used
dataset path
dataset hash where possible
seed
DESN feature settings
design hash
feature-settings hash
method label
target label
exact/approximate status
runtime
max RSS if measured
output paths
```

Large generated outputs must remain in ignored `results/` or `application/logs/`
paths. Only compact Markdown/CSV summaries should be tracked.

## Required Final Validation Per Stage

Package:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-qdesn-normal.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-likelihood-family.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-batching-modes.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-static-beta-prior-rhs.R")'
git diff --check
```

Article:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
git diff --check
```

If article application code or configs are touched, also run:

```sh
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/run_tests.R
```

## Stop Gates

Stop and report instead of continuing if:

- baseline tests fail;
- exact chunked Normal DESN differs from unchunked beyond tolerance;
- RHS/RHS_NS is accidentally presented as exact;
- Normal DESN is labeled as a quantile model;
- Normal initialization changes AL/exAL defaults;
- recursive forecasting requires a large refactor of AL/exAL forecast code;
- the unrelated dirty package script would need to be overwritten;
- a long-running result job becomes ambiguous or threatens unrelated workers.

## Overnight Execution Order

The recommended order is:

```text
0. Sync and baseline freeze.
1. Implement exact chunked Normal DESN scaled ridge.
2. Test and commit package.
3. Document Stage 1 and commit article note.
4. Implement source-median comparison harness.
5. Run source-median comparison and document results.
6. Implement initialization comparison harness.
7. Run initialization comparison and document results.
8. If all gates pass, implement recursive Normal forecast paths.
9. Update method availability docs.
10. Stop before warm-start or rolling/online unless explicitly authorized.
```

The highest-value overnight endpoint is:

```text
Normal DESN scaled ridge exact + exact chunked
Normal DESN RHS/RHS_NS approximate VB retained
Normal DESN initializers verified for AL/exAL VB and AL MCMC
source-median comparison report
initialization comparison report
all tests passing
all commits pushed
```

## First Implementation Task

The next coding task should be:

```text
Implement exact chunked Normal DESN scaled ridge in normal_desn_fit(), prove
chunked and unchunked posterior summaries match, and route it through
qdesn_fit_normal().
```

Do not start source comparisons until this exact chunking gate passes.
