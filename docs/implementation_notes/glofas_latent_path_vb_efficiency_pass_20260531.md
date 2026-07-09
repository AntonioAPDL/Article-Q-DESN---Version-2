# GloFAS Latent-Path VB Efficiency Pass

Date: 2026-05-31
Article branch: `application-ensemble-likelihood-redesign`

## Scope

This note records the first implementation pass from the local GloFAS
latent-path VB efficiency tracker. The goal was to harden exact chunking for
the full-specification latent-path AL-VB application fit and add enough
diagnostics to identify the next true bottleneck.

This pass did not change the statistical target. Exact chunking remains a
full-data, target-preserving implementation device.

## Changes

- Added source-aware fixed-row chunks for the latent-path historical rows.
- Kept exact chunking restricted to sequential full-data accumulation.
- Added per-iteration timing records to `app_fit_latent_path_al_vb_core()`.
- Added optional trace output through `chunking$trace`.
- Added chunking fields to latent-path fit diagnostics and profile summaries.
- Updated the exact-chunking comparison script with safe pilot overrides for
  `max_iter`, `n_draws`, `chunk_size`, and trace behavior.
- Fixed `/usr/bin/time -v` wall-time parsing for labels containing `h:mm:ss`.
- Added a synthetic latent-path recovery test comparing unchunked and exact
  chunked fitted states.
- Repinned the tiny and full-spec exact-chunking pilot configs to the current
  shared validation engine commit:
  `d4411ebb6bf9d6655fd4eef73f7fe0231ea5a351`.

## Validation

Focused tests:

```sh
Rscript application/tests/test_latent_path_recovery.R
Rscript application/tests/test_vb_preparation.R
```

The full `application/tests/run_tests.R` harness was attempted, but it stopped
before reaching the latent-path tests because other configs still pin older
engine commits. The focused tests above cover the files modified in this pass.

Tiny real-data exact-chunking gate:

```text
application/logs/exact_chunked_vb_tiny_gate_20260531_r2
```

| Field | Value |
| --- | ---: |
| Iterations | `2` |
| Max fitted-state gate difference | `4.2632564145606e-14` |
| Tolerance | `1e-7` |
| Passed | `TRUE` |

Full-spec exact-chunking gate:

```text
application/logs/exact_chunked_vb_fullspec_gate_20260531_d4411eb
```

| Field | Unchunked | Exact chunked |
| --- | ---: | ---: |
| Iterations | `5` | `5` |
| Wall time | `1:22:34` | `1:24:50` |
| Fit elapsed seconds | `4887.722` | `5025.466` |
| Max RSS KB | `4938068` | `4838916` |
| Posterior identity max abs | `2.22e-16` | `2.22e-16` |
| Future covariance min eigenvalue | `0.00120681071455187` | `0.00120681071455068` |

Full-spec fitted-state comparison:

| Metric | Max absolute difference |
| --- | ---: |
| `theta_mean` | `1.9240165016754e-13` |
| `theta_cov` | `2.27851862811407e-17` |
| `sigma_mean` | `1.69309011255336e-15` |
| `sigma_shape` | `0` |
| `sigma_rate` | `3.18323145620525e-11` |
| `y_future_mean` | `1.15329967798061e-12` |
| `y_future_cov` | `4.56371052059978e-14` |
| `elbo_trace` | `3.8198777474463e-11` |

Gate result: passed at tolerance `1e-7`.

## Bottleneck Evidence

For the full-spec exact-chunked gate with `chunk_size = 2048`, the traced VB
steps showed that the expensive work is concentrated in two steps:

| Step | Typical time per iteration |
| --- | ---: |
| `theta_update` | about `351` to `363` seconds |
| `row_moments` | about `388` to `400` seconds |
| `future_update` | about `21` seconds |
| `v_update`, `sigma_update`, `prior_update`, `objective` | negligible |

Thus exact chunking is now validated, but it is not the speed solution. The
next efficiency pass should target row-moment construction, repeated covariance
use, and dense linear algebra inside the theta update.

## Activation Decision

Exact chunking is cleared as a full-specification equivalence mode for
diagnostic and memory-layout work. It should not be described as a faster mode
for the current GloFAS latent-path application until the row-moment and
theta-update bottlenecks are optimized.

Do not enable exact chunking in production/main application configs solely for
speed. Enable it only when the exactness gate, memory behavior, and runtime
tradeoff are appropriate for the specific run.

## Exact-Only Follow-Up Pass

The follow-up implementation pass remained exact-only. No diagonal, low-rank,
active-set, stochastic, or other approximate VB mode was introduced.

Changes:

- Wrote per-iteration latent-path VB timing from the normal `03_fit_models.R`
  stage to `tables/qdesn_discrepancy_vb_iteration_timing.csv`.
- Added fit-stage artifact-retention controls with current behavior preserved
  by default:
  `execution.artifacts.retain_fit_object`,
  `execution.artifacts.retain_design_object`,
  `execution.artifacts.retain_prediction_design_object`, and
  `execution.artifacts.retain_reference_fit_object`.
- Added manifest columns recording whether fit, design, and prediction-design
  objects were retained.
- Added a guard that refuses storage-light fit/design object removal when
  post-analysis is configured to run immediately, because post-analysis reads
  those retained objects.
- Added post-iteration timing rows for theta, future-path, and sigma draw
  generation. These rows use `iteration = NA` and make the full-spec tail cost
  visible without changing the fitted state.
- Refactored exact row-moment algebra so the streamed grouped path no longer
  materializes the full `theta_cov + theta_mean theta_mean'` matrix for its
  fixed-row and future-row second moments.
- Cached keyed GloFAS future-row indices in the streamed row moments and reused
  them in the theta and future updates.

Validation:

```text
Focused tests:
  artifact hygiene: PASS
  latent-path design equivalence: PASS
  latent-path recovery: PASS
  VB preparation: PASS
```

The full `application/tests/run_tests.R` harness was attempted again, but it
stopped at the existing engine-contract check before reaching the modified
latent-path code:

```text
Error: isTRUE(engine_report$ok) is not TRUE
```

Tiny exact real-data gate:

```text
application/logs/exact_efficiency_refactor_tiny_gate_20260531
```

| Field | Value |
| --- | ---: |
| Iterations | `2` |
| Max fitted-state gate difference | `7.38964445190504e-13` |
| Tolerance | `1e-7` |
| Passed | `TRUE` |
| Unchunked wall time | `0:09.58` |
| Exact chunked wall time | `0:09.39` |

Normal `run_all` smoke exercising `03_fit_models.R`:

```text
application/runs/exact_efficiency_refactor_runall_tiny_drawtiming_20260531
```

This smoke produced `tables/qdesn_discrepancy_vb_iteration_timing.csv` with
standalone step timings and confirmed that the fit manifest records the
artifact-retention columns. The run is a tiny wiring check only, not an
application result.

The timing table includes the post-loop rows
`theta_draw_generation`, `future_draw_generation`, and
`sigma_draw_generation` with `iteration = NA`.

Bounded full-spec exact gate after the exact-only refactor:

```text
application/logs/exact_efficiency_refactor_fullspec_gate_20260531
```

| Field | Unchunked | Exact chunked |
| --- | ---: | ---: |
| Iterations | `1` | `1` |
| Fit elapsed seconds | `1739.993` | `2019.708` |
| Max RSS KB | `4901284` | `4930556` |
| Posterior identity max abs | `1.11e-16` | `1.11e-16` |
| Future covariance min eigenvalue | `0.00614576528795185` | `0.00614576528795186` |
| Max fitted-state gate difference | `7.27595761418343e-12` |  |
| Tolerance | `1e-7` |  |
| Passed | `TRUE` |  |

The exact-chunked full-spec trace again identified the expensive exact steps:

| Step | Time |
| --- | ---: |
| `theta_update` | `331.138` sec |
| `future_update` | `19.855` sec |
| `row_moments` | `584.435` sec |

This gate confirms target preservation on the wide design. It also confirms
that this pass should not be advertised as a speed improvement for production
runs; the next exact-only efficiency work should target dense row-moment
algebra, solver reuse, and posterior draw generation.

## Probe-Cache And Fixed-Moment Speed Pass

A second controlled pass completed the first audit-driven speed plan. It
remained exact-only and did not introduce any approximate VB update.

Changes:

- Completed the streamed grouped fixed-row second-moment algebra so the
  historical row moments use
  `E[(H theta)^2] = (H E[theta])^2 + diag(H Var(theta) H')` without
  materializing `theta_cov + theta_mean theta_mean'`.
- Added pre-loop timing rows to `app_fit_latent_path_al_vb_core()`:
  `prior_initialization`, `initial_row_moments`, `sigma_initialization`, and
  `initial_v_update`.
- Added fit-stage timing around latent-path design construction, VB argument
  preparation, the core VB fit, and design summarization/hash work.
- Wrote normal `03_fit_models.R` stage timing to
  `tables/qdesn_discrepancy_fit_stage_timing.csv`.
- Wrote exact-pilot timing sidecars:
  `__vb_iteration_timing.csv` and `__fit_stage_timing.csv`.
- Cached the initial future-design probe inside the runtime design object and
  reused it during validation, hashing, and summary construction.
- Stripped the runtime future-probe cache before optional design-object
  serialization so retained design artifacts do not silently grow.
- Added a latent-path test that verifies cached-probe reuse and the new
  initialization timing rows.

Validation:

```text
Focused latent-path speed-pass tests: PASS
Tiny paired exact gate: PASS
Tiny run_all smoke through fit/score/output stages: PASS
Bounded full-spec paired exact gate: PASS
```

The tiny `run_all` smoke reached outputs and produced both timing tables:

```text
application/runs/exact_speedpass_probe_cache_runall_tiny_20260531
```

It failed only the final launch-readiness preflight because the article
worktree was intentionally dirty during the implementation check:

```text
[code] article_git_clean
```

All fit, prediction, posterior-draw, scoring, figure, engine, and output
contract checks were otherwise OK. This is an expected implementation-time
preflight failure, not a model or timing-table failure.

Tiny paired exact gate:

```text
application/logs/exact_speedpass_probe_cache_tiny_gate_20260531
```

| Field | Value |
| --- | ---: |
| Iterations | `2` |
| Unchunked fit elapsed seconds | `5.007` |
| Exact chunked fit elapsed seconds | `6.157` |
| Max fitted-state gate difference | `1.506351e-12` |
| Tolerance | `1e-7` |
| Passed | `TRUE` |

Bounded full-spec paired exact gate:

```text
application/logs/exact_speedpass_probe_cache_fullspec_gate_20260531
```

| Field | Unchunked | Exact chunked |
| --- | ---: | ---: |
| Iterations | `1` | `1` |
| Wall time | `28:42.03` | `27:15.39` |
| Fit elapsed seconds | `1663.008` | `1577.499` |
| Max RSS KB | `4472596` | `4530936` |
| Max fitted-state gate difference | `1.09139364212751e-11` |  |
| Tolerance | `1e-7` |  |
| Passed | `TRUE` |  |

Full-spec stage timing:

| Stage | Unchunked seconds | Exact chunked seconds |
| --- | ---: | ---: |
| `build_latent_path_design` | `367.059` | `332.089` |
| `prepare_vb_args` | `0.102` | `0.100` |
| `fit_latent_path_al_vb_core` | `1223.593` | `1172.809` |
| `summarize_latent_path_design` | `72.194` | `72.445` |

Full-spec VB timing:

| Step | Unchunked seconds | Exact chunked seconds |
| --- | ---: | ---: |
| `initial_row_moments` | `398.665` | `372.013` |
| `theta_update` | `349.983` | `328.697` |
| `future_update` | `19.945` | `19.470` |
| `row_moments` | `372.235` | `369.843` |
| `theta_draw_generation` | `81.761` | `81.737` |

This pass turns the speed work from a broad suspicion into a measured budget.
The dominant exact costs are now:

1. fixed/future row-moment construction;
2. dense theta precision construction and solve;
3. full theta posterior draw generation;
4. full design construction and design hash/summary work.

The next specialized optimization should therefore target block-structured
theta updates and posterior draw generation. Those changes should stay behind
the same exact-equivalence gates before any production launch.
