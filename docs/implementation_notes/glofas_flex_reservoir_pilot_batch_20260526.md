# GloFAS Higher-Flexibility D1 n300 Pilot Batch, 2026-05-26

This note records a prepared-only application batch created after the
`diverse8` application runs showed visually smooth fits and likely
underfitting. The batch deliberately stays close to the current best completed
candidate, `diverse8_02`, but gives the model more ways to adapt locally.

No application fit was launched while preparing this batch.

## Parent Candidate

The parent/reference candidate is:

```text
application/config/glofas_latent_path_al_vb_dec25_diverse8_d1n300_m100_a92_r95_w15_tau3em3_main1000.yaml
```

The completed score for that candidate was:

```text
run_id: diverse8_02_d1n300_m100_a92_r95_w15_20260525_1844
p50 check loss: 0.622070792290309
```

The older D1 n300 reference score was:

```text
tau0 = 0.003
p50 check loss: 0.628891911734846
```

Raw GloFAS p50 check loss was:

```text
0.875378727598426
```

## Flexibility Changes

All eight candidates keep:

- `D = 1`;
- `n = 300`;
- `alpha = 0.92`;
- `rho = 0.95`;
- `pi_w = 0.03`;
- `pi_in = 1.00`;
- `seed = 20260512`;
- AL working likelihood;
- VB with `max_iter = 1000` and `n_draws = 2000`;
- separate beta/reference and alpha/discrepancy RHS prior controls.

The batch changes three things:

1. It increases memory from `m=100` to `m=180` or `m=360`.
2. It increases reservoir input scale from the parent `0.15` to `0.18` or
   `0.22`.
3. It enables the direct readout input block, so each readout receives both
   reservoir states and direct output/covariate lag features.

The direct input block is the largest practical flexibility change. It gives
the readout access to raw lagged information when the fixed reservoir does not
preserve enough local structure.

## Prepared Artifacts

Preparation script:

```text
application/scripts/03_prepare_flex_reservoir_pilot_batch_20260526.R
```

Batch table:

```text
application/config/glofas_flex_reservoir_pilot_batch_20260526.csv
```

Config and model-grid pattern:

```text
application/config/glofas_latent_path_al_vb_dec25_flex8_*_main1000.yaml
application/config/model_grid_latent_path_al_vb_dec25_flex8_*_main1000.csv
```

## Candidate Grid

| Rank | Role | Memory | Win scale | Beta RHS `tau0` | Discrepancy RHS `tau0` | Direct input block |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | `m180_alpha_tau1em2_skip` | 180 | 0.18 | 0.003 | 0.01 | yes |
| 2 | `m180_alpha_tau3em2_skip` | 180 | 0.18 | 0.003 | 0.03 | yes |
| 3 | `m180_alpha_tau1em1_skip` | 180 | 0.18 | 0.003 | 0.10 | yes |
| 4 | `m360_alpha_tau3em2_skip` | 360 | 0.18 | 0.003 | 0.03 | yes |
| 5 | `m360_alpha_tau1em1_skip` | 360 | 0.18 | 0.003 | 0.10 | yes |
| 6 | `m360_w18_both_tau3em2_skip` | 360 | 0.18 | 0.03 | 0.03 | yes |
| 7 | `m180_w22_alpha_tau1em1_skip` | 180 | 0.22 | 0.003 | 0.10 | yes |
| 8 | `m360_w22_alpha_tau1em1_skip` | 360 | 0.22 | 0.003 | 0.10 | yes |

## Validation Status

The first candidate was run through sampler-free checks:

```sh
Rscript application/scripts/00_check_inputs.R \
  --config application/config/glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at1em02_skip_main1000.yaml \
  --run_id flex8_prelaunch_design_20260526_01

Rscript application/scripts/01_build_panel.R \
  --config application/config/glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at1em02_skip_main1000.yaml \
  --run_id flex8_prelaunch_design_20260526_01

Rscript application/scripts/03_check_model_design.R \
  --config application/config/glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at1em02_skip_main1000.yaml \
  --run_id flex8_prelaunch_design_20260526_01
```

This candidate passed and wrote:

```text
application/runs/flex8_prelaunch_design_20260526_01/tables/qdesn_discrepancy_design_preflight.csv
```

The resulting design had:

- `n_beta_features = 843`;
- `n_alpha_features = 843`;
- `n_beta_reservoir_features = 300`;
- `n_alpha_reservoir_features = 300`;
- `n_beta_direct_output_lag_features = 180`;
- `n_alpha_direct_output_lag_features = 180`;
- `n_beta_direct_covariate_lag_features = 362`;
- `n_alpha_direct_covariate_lag_features = 362`.

The second candidate began the same sampler-free design check, but the
sequential validation loop was stopped intentionally after confirming that the
new direct-input design works. The check is relatively expensive because the
skip-block design is much wider. No fitting run was launched.

## Launch Guidance

These candidates are prepared, not launched. If the next instruction is to
launch, prefer a small parallel subset first:

1. `flex8_02`: `m=180`, `win=0.18`, discrepancy `tau0=0.03`;
2. `flex8_03`: `m=180`, `win=0.18`, discrepancy `tau0=0.10`;
3. `flex8_05`: `m=360`, `win=0.18`, discrepancy `tau0=0.10`;
4. `flex8_06`: `m=360`, `win=0.18`, both-block `tau0=0.03`.

This subset directly tests whether underfitting is primarily caused by the
discrepancy prior, by short memory, or by excessive shrinkage in both readout
blocks.
