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
  the repo from accidentally staged fit outputs. It also exercises scoped
  GloFAS cleanup manifests, active/authoritative protections, and verified
  deletion of explicitly approved terminal-run payloads.
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
  serialization, seed aggregation, semantic two-block initial-condition
  forgetting, and a tiny fake-design integration path.
- `test_glofas_constrained_median_screening.R`: constrained p50 range
  expansion, semantic warm starts, historical/forecast gates, the frozen
  Stage-A design, and the exact 56-candidate alpha/rho/tau response-surface
  campaign with retained warm/cold canaries, plus the deterministic
  48-candidate structural memory/geometry campaign.
- `test_glofas_screening_program_closeout.R`: cumulative phase census,
  leader selection, no-promotion decision, and fail-closed ranking-hash drift
  for the completed GloFAS constrained-median program.
- `test_latent_path_design.R`: application-model contract parsing,
  latent-path state continuation, requested versus effective issued-horizon
  handling, synthetic AL fixture generation, scaling of reservoir lag inputs,
  post-cutoff USGS leakage guards, keyed GloFAS future-builder output,
  two-block reference/discrepancy future features, independent beta/alpha RHS
  states, posterior-draw prediction validation, dense-debug versus
  streamed-grouped VB moment equivalence, grouped objective equivalence, and
  the linearized Delta future-path update for the target ensemble-likelihood
  model.
- `test_latent_path_runtime_optimization.R`: exact paired-statistics and
  fallback algebra, compact-design semantic round trips and direct-fit
  equivalence, immutable reference-feature cache environment fallback, hits,
  invalidation, corruption, and lock failures, runtime-backend manifests, and
  uninterrupted versus interrupted/resumed VB identity.
- `test_glofas_numerical_backend_exec.py`: child-process backend/thread/CPU
  controls, OpenBLAS path/hash rejection, and terminal execution manifests.
- `test_glofas_fit_recovery_scheduler.py`: physical-core and NUMA-aware CPU
  allocation, disjoint multithread sets, checkpoint-aware restart with owned
  checkpoint paths, and owned reference-cache roots in addition to the
  existing bounded scheduler gates.
- `test_glofas_discrepancy_transition.R`: legacy mapping, strictly prior
  anchors, discrepancy-only context, issued-ensemble provenance, and causal
  baseline construction.
- `test_glofas_discrepancy_transition_campaign.R`: candidate/cutoff cardinality,
  exact FR09 comparator routing, origin-persistence weather, no-leakage gates,
  future discrepancy scoring, and equal-origin aggregation.
- `test_glofas_discrepancy_context_repair_campaign.R`: frozen T01/T10
  continuation, complete context-variable/placement factorial, strict warm-start
  modes, stable-at-cap numerical gate, context extrapolation diagnostics, and
  the prospective aggregate-bias guardrail. It also verifies the evidence-bound
  required-anchor/advisory-comparator decision and rejects unsafe Stage-1 theta
  or non-T01 warm-start dependencies.
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
