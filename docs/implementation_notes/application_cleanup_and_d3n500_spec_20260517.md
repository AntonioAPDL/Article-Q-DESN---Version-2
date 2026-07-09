# Application Artifact Cleanup and D3 n500 Spec, 2026-05-17

## Cleanup

Generated application artifacts were cleaned after promoting and verifying the
completed main application run. The cleanup removed old ignored run outputs,
smokes, pilots, design gates, caches, generated manuscript-output folders, and
stale root launch logs.

Kept generated application artifacts:

```text
application/runs/latent_path_main_al_vb_n1000_m360_20260515_221729
application/outputs/generated/latent_path_main_al_vb_n1000_m360_20260515_221729
application/cache/latent_path_al_vb_dec25_main
application/logs/latent_path_main_al_vb_n1000_m360_20260515_221729_main_launch_exit_code.txt
application/logs/latent_path_main_al_vb_n1000_m360_20260515_221729_main_launch_stdout.log
```

Removed generated artifacts:

```text
application/runs: 164 old run directories
application/outputs/generated: 26 old generated-output directories
application/cache: 22 old cache items
application/logs: 6 stale root log/pid files
```

Post-cleanup generated artifact footprint:

```text
application/runs: 1.7G
application/outputs: 40K
application/cache: 804K
application/logs: 12K
```

The promoted manuscript-facing outputs remain tracked under repository-level
`tables/` and `figures/`. The completed main run still has zero required
launch-readiness failures, and the promoted manifest still has 21 rows.

To repeat this cleanup pattern after a future successful run, replace `KEEP`
with the run id to preserve:

```sh
KEEP=latent_path_main_al_vb_n1000_m360_20260515_221729
find application/runs -mindepth 1 -maxdepth 1 ! -name "$KEEP" -exec rm -rf -- {} +
find application/outputs/generated -mindepth 1 -maxdepth 1 ! -name "$KEEP" -exec rm -rf -- {} +
find application/cache -mindepth 1 -maxdepth 1 ! -name '<matching-main-cache-name>' -exec rm -rf -- {} +
find application/logs -mindepth 1 -maxdepth 1 ! -name "${KEEP}*" -exec rm -rf -- {} +
```

## New D3 n500 Spec

New launch-target files:

```text
application/config/glofas_latent_path_al_vb_dec25_d3n500_tau1e3_slab1_main.yaml
application/config/model_grid_latent_path_al_vb_dec25_d3n500_tau1e3_slab1_main.csv
```

Reservoir:

```text
D = 3
n = [500, 500, 500]
n_tilde = [500, 500]
m = 360
washout = 500
alpha = [0.25, 0.25, 0.25]
rho = [0.95, 0.95, 0.95]
pi_w = [0.10, 0.10, 0.10]
pi_in = [1.00, 1.00, 1.00]
act_f = tanh
act_k = identity
seed = 20260512
```

RHS prior:

```text
rhs_tau0 = 1.0e-3
rhs_slab_s2 = 1.0
rhs_a_zeta = 2.0
rhs_b_zeta = 4.0
```

The `pi_in = [1.0, 1.0, 1.0]` setting matches the exdqlm defaults and the
historical three-layer San Lorenzo D3 n500 validation/spec files. The previous
Article main run used `pi_in = [0.60, 0.60]`, but the validation-side D3
standard was dense input connectivity.

`rhs_slab_s2 = 1.0` is a defensible tighter slab setting for this Article design
because reservoir inputs are standardized before the reservoir recursion and
the readout uses bounded reservoir/reduced states. It is still slightly
different from a fully z-scored readout design: `standardize_non_intercept` is
currently `false`, so the readout columns are not separately standardized after
the reservoir transform.

## Verification

Static config checks passed:

```text
D = 3
n = [500, 500, 500]
n_tilde = [500, 500]
alpha = [0.25, 0.25, 0.25]
rho = [0.95, 0.95, 0.95]
pi_in = [1.0, 1.0, 1.0]
rhs_tau0 = 1.0e-3
rhs_slab_s2 = 1.0
model grid exists and has the raw GloFAS plus Q-DESN rows
```

No new run was launched as part of this cleanup/spec commit. The next safe step
is a design/input gate against the new config, followed by a final launch only
after that gate passes.

## Design Gate Result

The new D3 n500 config was run through the input/design gate:

```sh
Rscript application/scripts/run_input_design_gate.R \
  --config application/config/glofas_latent_path_al_vb_dec25_d3n500_tau1e3_slab1_main.yaml \
  --run_id latent_path_d3n500_tau1e3_slab1_design_gate_20260517_151643
```

Gate run path:

```text
application/runs/latent_path_d3n500_tau1e3_slab1_design_gate_20260517_151643
```

Result: passed. Completed stages:

```text
00_materialize_from_source_registry
00_audit_authoritative_source_bundle
00_register_input_bundle
00_check_inputs
00_audit_input_bundle
01_build_panel
03_check_model_design
```

Design preflight summary:

```text
fit_id = qdesn_latent_path_rhs_al_vb_d3n500_tau1e3_slab1_p50
n_stacked_rows = 26446
n_y_rows = 12523
n_g_rows = 13923
n_fixed_rows = 24990
n_future_dates = 28
n_issued_glofas_rows = 1428
n_base_features = 1501
n_augmented_features = 3002
n_reservoir_features = 1500
n_direct_output_lag_features = 0
n_direct_covariate_lag_features = 0
n_reservoir_input_output_lag_features = 360
n_reservoir_input_covariate_lag_features = 122
design_hash = 01cadbd7121661bf2e46769efeaf3c4f84922d668a84cbb4ed6299a13cd7aba7
```

Panel summary:

```text
n_rows = 14423
n_retrospective = 12995
n_ensemble = 1428
date_min = 1987-05-29
date_max = 2023-01-22
horizon_min = 0
horizon_max = 28
n_members = 51
n_missing_reference = 0
n_missing_glofas = 0
```

The gate artifact is current launch evidence, not an old pilot/smoke result.
It is intentionally small (`208K`) and can be removed after the full run is
launched or if a stricter generated-artifact cleanup is needed.
