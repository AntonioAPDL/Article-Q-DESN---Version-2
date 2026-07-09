# GloFAS Latent-Path VB Second Speed Pass

Date: 2026-06-01

This note records the second exact speed pass for the article-side GloFAS
latent-path AL-VB fitter. The pass preserves the fitted-state target: exact
chunked and unchunked full-specification pilots still agree at the fitted-state
gate.

## Scope

Changed files:

- `application/R/latent_path_vb_al.R`
- `application/R/fit_qdesn_discrepancy.R`
- `application/R/fit_qdesn_latent_path.R`
- `application/config/glofas_latent_path_al_vb_dec25_exact_chunked_smoke.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_main.yaml`
- `application/scripts/03_compare_exact_chunked_vb_pilot.R`
- `application/scripts/03_fit_models.R`
- `application/tests/test_latent_path_design.R`

## Implementation

The pass added a Cholesky-first exact Gaussian draw backend:

- `app_latent_mvn_draws_exact(..., backend = "chol_eigen_fallback")`
- backend attributes recorded as `chol`, `eigen_fallback`, or `eigen`
- substep timing for symmetrization, random normal generation, factorization,
  multiplication, and mean shift

The pass added optional substep profiling:

- row-moment substeps for future builders, fixed-block guards, fixed row
  moments, future Y loops, future keyed GloFAS loops, and future member loops;
- theta-update substeps for prior precision, fixed theta statistics, future
  contributions, and SPD solve;
- design-build substeps for beta features, alpha features, fixed augmented
  design, future probe initialization, and validation.

The pass also added exact paired-row reuse for fixed beta rows in the
two-block latent-path design. The production fixed block has the same beta
features for the reference and GloFAS source rows, so beta mean and diagonal
covariance contributions can be computed once and reused for the paired rows.

The pilot runner now accepts:

```bash
--profile_substeps true
--draw_backend chol_eigen_fallback
```

The main fit stage now writes, when present:

```text
tables/qdesn_discrepancy_vb_substep_timing.csv
```

and records the requested and used draw backends in:

```text
manifest/qdesn_discrepancy_fit_manifest.csv
tables/qdesn_discrepancy_fit_diagnostics.csv
```

The exact-chunked smoke config and active main config now pin the active shared
engine commit. The exact-chunked smoke also enables substep profiling:

```text
d4411ebb6bf9d6655fd4eef73f7fe0231ea5a351
```

Follow-up package sync on 2026-06-01: the reusable static-readout profiling
hook was promoted to the shared package at
`17eb1a4ad25117fde5f336cdf921429f8515ef5b`, and active shared-package
application configs were repinned to that commit. The timing and fitted-state
gate evidence below remains the original second-speed-pass evidence from
`d4411ebb6bf9d6655fd4eef73f7fe0231ea5a351`.

## Validation

Focused latent-path tests:

```bash
Rscript -e "repo_root <- normalizePath('.'); source(file.path(repo_root, 'application/R/00_packages.R')); app_set_repo_root(repo_root); source(app_path('application/R/input_contract.R')); source(app_path('application/R/launch_control.R')); source(app_path('application/R/artifact_hygiene.R')); source(app_path('application/R/engine_contract.R')); source(app_path('application/R/model_contract.R')); source(app_path('application/R/feature_contract.R')); source(app_path('application/R/covariate_design.R')); source(app_path('application/R/build_application_panel.R')); source(app_path('application/R/build_qdesn_features.R')); source(app_path('application/R/latent_path_design.R')); source(app_path('application/R/simulate_latent_path.R')); source(app_path('application/R/latent_path_vb_al.R')); source(app_path('application/R/latent_path_recovery.R')); source(app_path('application/R/discrepancy_design.R')); source(app_path('application/R/forecast_contract.R')); source(app_path('application/R/fit_qdesn_discrepancy.R')); source(app_path('application/R/fit_qdesn_latent_path.R')); source(app_path('application/R/score_forecasts.R')); source(app_path('application/R/post_fit_analysis.R')); source(app_path('application/tests/test_input_contract.R')); source(app_path('application/tests/test_latent_path_design.R')); cat('focused latent-path tests completed\n')"
```

Result: passed.

Application-wide test harness:

```bash
Rscript application/tests/run_tests.R
```

Result: passed.

Tiny exact gate:

```text
application/logs/second_speedpass_tiny_gate_20260601
```

| Check | Value |
| --- | ---: |
| Iterations | `4` vs `4` |
| Max fitted-state difference | `4.675371e-12` |
| Tolerance | `1e-7` |
| Passed | `TRUE` |
| Substep timing rows | `121` per fit |
| Draw backend | `chol` |

Production-style `run_all` smoke:

```text
application/runs/second_speedpass_runall_smoke_20260601
```

The smoke completed through `05_make_outputs` and wrote:

```text
application/runs/second_speedpass_runall_smoke_20260601/tables/qdesn_discrepancy_vb_substep_timing.csv
```

The first optional `06_preflight_launch` stage failed only because the
repository was dirty during this implementation pass:

```text
article_git_clean
```

After committing and pushing the speed pass, the same preflight was rerun for
`second_speedpass_runall_smoke_20260601` and passed with `31` required checks
and `0` required failures.

Full-spec exact gate:

```text
application/logs/second_speedpass_fullspec_gate_20260601
```

| Check | Unchunked | Exact chunked |
| --- | ---: | ---: |
| Iterations | `1` | `1` |
| Fit elapsed seconds | `1253.279` | `1038.883` |
| Wall time | `22:19.64` | `18:29.63` |
| Max RSS KB | `6556812` | `6423180` |
| Prediction identity max abs | `1.110223e-16` | `1.110223e-16` |
| Future covariance min eigenvalue | `0.006145765` | `0.006145765` |

Fitted-state comparison:

| Metric | Max absolute difference |
| --- | ---: |
| `theta_mean` | `0` |
| `theta_cov` | `0` |
| `sigma_mean` | `0` |
| `sigma_shape` | `0` |
| `sigma_rate` | `0` |
| `y_future_mean` | `0` |
| `y_future_cov` | `0` |
| `elbo_trace` | `0` |

Gate result: passed.

## Timing Evidence

Compared with the prior block-stat full-spec gate:

```text
application/logs/block_stats_fullspec_gate_20260601_diag
```

and the new full-spec gate:

```text
application/logs/second_speedpass_fullspec_gate_20260601
```

| Step | Prior exact chunked | New exact chunked |
| --- | ---: | ---: |
| Initial row moments | `88.075s` | `80.292s` |
| Theta update | `228.292s` | `214.012s` |
| Row moments | `267.516s` | `218.751s` |
| Theta draw generation | `98.656s` | `5.349s` |
| Fit elapsed seconds | `1198.718s` | `1038.883s` |

The Cholesky-first draw backend is the clearest isolated improvement: full-spec
theta draw generation fell from about `98.7s` to about `5.35s` in the exact
chunked gate.

## Remaining Bottlenecks

The top full-spec exact-chunked substeps were:

| Parent step | Substep | Seconds |
| --- | --- | ---: |
| `theta_update` | `theta_fixed_stats` | `170.778` |
| `row_moments` | `fixed_block_moments` | `134.688` |
| `row_moments` | `future_builder` | `56.880` |
| `initial_row_moments` | `future_builder` | `53.483` |
| `row_moments` | `fixed_cov_beta_alpha_dense_g` | `45.006` |
| `row_moments` | `fixed_cov_beta_dense_paired` | `44.178` |
| `row_moments` | `fixed_cov_alpha_dense_g` | `43.808` |
| `theta_update` | `fixed_theta_g_alpha_alpha` | `43.402` |
| `theta_update` | `fixed_theta_g_beta_beta` | `41.550` |
| `theta_update` | `fixed_theta_g_beta_alpha` | `41.136` |

The next optimization pass should target fixed-block theta statistics and
fixed-block row moments under dense covariance. The profiling evidence points
to the fixed historical block, not posterior draw generation, as the main
remaining bottleneck after this pass.

## Reproducibility Notes

The draw backend changes the random linear transformation used to generate
posterior draws from the same Gaussian covariance. Fitted variational states are
unchanged; raw draw matrices are not expected to be bitwise identical to the
old eigen-root backend under the same seed.

Substep profiling is opt-in through `vb_ld.diagnostics.profile_substeps` or the
pilot CLI flag. Ordinary production configs do not need to enable it unless a
profiling run is intended.
