# Application Tests

This directory will contain checks that protect the application from the most
common reproducibility failures.

Tracked tests:

- `test_input_contract.R`: input manifests, hashes, schemas, and date ranges.
- `test_input_bundle.R`: registration of required and optional bundle inputs.
- `test_input_figures.R`: pre-model diagnostic figures and figure provenance.
- `test_launch_control.R`: final-launch confirmation, blocked run ids, run
  directory reuse guards, and safe non-fitting stage plans.
- `test_artifact_hygiene.R`: report-only inventory of generated or heavy
  artifacts, including run-level summaries for cleanup planning, protecting
  the repo from accidentally staged fit outputs.
- `test_engine_contract.R`: package boundary, required exports, and prior mapping.
- `test_vb_preparation.R`: VB preparation config, model grid,
  inference-support gate, VB argument normalization, and method-aware
  diagnostics for approximate VB draws.
- `test_forecast_contract.R`: issued-horizon prediction-contract metadata,
  subtraction identity, and final-launch guard for pilot contracts.
- `test_discrepancy_design.R`: deterministic source-stacked discrepancy design.
- `test_reservoir_screening.R`: sampler-free reservoir diagnostics, including
  spectral-radius and leaky-effective checks, finite/dead/saturated state
  guards, correlation redundancy, pruning, effective rank, conditioning,
  serialization, seed aggregation, and a tiny fake-design integration path.
- `test_latent_path_design.R`: application-model contract parsing,
  latent-path state continuation, requested versus effective issued-horizon
  handling, synthetic AL fixture generation, scaling of reservoir lag inputs,
  post-cutoff USGS leakage guards, keyed GloFAS future-builder output,
  two-block reference/discrepancy future features, independent beta/alpha RHS
  states, posterior-draw prediction validation, dense-debug versus
  streamed-grouped VB moment equivalence, grouped objective equivalence, and
  the linearized Delta future-path update for the target ensemble-likelihood
  model.
- `test_no_leakage.R`: forecast-origin information sets and target dates.
- `test_quantile_grid.R`: sorted quantile levels and monotone synthesis output.
- `test_reproducibility.R`: fixed seeds, stable run IDs, and required artifacts.
- `test_launch_readiness.R`: preflight checks for completed dry-run
  directories before final application launch.
- `test_promotion_contract.R`: final-promotion guards and storage-light
  provenance snapshot mapping.
- `test_application_output_registry.R`: current-output registry generation,
  compact manuscript score-table labels, and selected-output hash manifests.
- `test_post_fit_analysis.R`: post-fit draw extraction, history and forecast
  summaries, AL versus exAL gamma handling, VB trace plotting, p50-only metric
  behavior, and coefficient forest plot generation.

Tests should run before any output is promoted into the manuscript.
Run them under the same local R 4.6.0 runtime used for validation and
application gates:

```sh
hash -r
Rscript -e 'cat(R.version.string, "\n"); stopifnot(getRversion() >= "4.6.0")'
Rscript application/tests/run_tests.R
```
