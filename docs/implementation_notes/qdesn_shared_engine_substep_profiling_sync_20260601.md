# Q-DESN Shared Engine Substep Profiling Sync

Date: 2026-06-01

## Purpose

This note records the controlled promotion of a reusable diagnostic feature
from the Article-Q-DESN GloFAS efficiency work into the shared Q-DESN package
branch. The promotion keeps application-specific latent-path algebra in the
article repo and moves only generic static-readout VB timing diagnostics into
the package.

## Shared Package State

Package worktree:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`

- branch: `validation/shared-fitforecast-v2-1.0.0`
- promoted commit: `17eb1a4ad25117fde5f336cdf921429f8515ef5b`
- subject: `Add Q-DESN VB substep profiling`
- package version: `1.0.0`

The package commit adds opt-in timing through:

```r
diagnostics = list(profile_substeps = TRUE)
```

For `qdesn_fit_vb()` and direct `exal_fit(..., method = "vb")` calls, timing
rows are retained under:

```r
fit$misc$substep_timing
```

The profiling path records timing only and does not change the VB target,
update order, priors, likelihood, or fitted-state summaries.

## Promotion Boundary

Promoted to the shared package:

- generic substep timing for the static exAL/AL VB readout engine;
- diagnostics propagation through `exal_make_vb_control()` and `qdesn_fit_vb()`;
- tests showing profiling is opt-in and fitted states are unchanged.

Kept Article-side:

- GloFAS two-block latent-path row structure;
- fixed historical `Y/G` paired-row reuse;
- recursive future-path builder shortcuts;
- Article run-promotion, artifact hygiene, and application-specific figures.

This boundary keeps the shared package reusable for univariate Q-DESN fits
without making it depend on the GloFAS application design.

## Article Config Repin

The active shared-package GloFAS application configs were repinned from
`d4411ebb6bf9d6655fd4eef73f7fe0231ea5a351` to
`17eb1a4ad25117fde5f336cdf921429f8515ef5b`.

Updated configs:

- `application/config/glofas_latent_path_al_vb_dec25_main.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_exact_chunked_smoke.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_fullspec_exact_chunked_pilot.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_fullspec_unchunked_pilot.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_exact_chunked_pilot.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_unchunked_pilot.yaml`

Historical `article/app-engine-73c043f` configs and completed run provenance
were not changed.

## Validation

Package-side focused gates:

- `test-exal-vb-substep-profiling.R`: passed, 17 checks.
- `test-exal-exact-chunking-stats.R`: passed, 38 checks.
- `test-qdesn-vb-batching-modes.R`: passed, 42 checks.
- `test-exal-batching-controls.R`: passed, 61 checks.
- `git diff --check`: clean.

Article-side validation after repin:

```sh
Rscript application/tests/run_tests.R
```

The application-wide harness should pass from a clean Article worktree after
this note and the config repin are committed.
