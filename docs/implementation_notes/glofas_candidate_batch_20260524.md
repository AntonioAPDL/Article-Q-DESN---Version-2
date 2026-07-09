# GloFAS Application Candidate Batch, 2026-05-24

This note records the next focused model-selection batch after promoting the
selected reference run
`latent_path_d1n300_m100a092r097_tau3em3_main1000_20260523_160355`.

## Selection Rationale

The completed tau0 sweep showed that the regularized-horseshoe global scale is
not the dominant remaining source of variation around the selected D1 n300
reservoir: the best run used `tau0 = 0.003`, and nearby tau settings produced
nearly identical median check loss. The next batch therefore keeps the prior and
inference settings fixed and varies only screened reservoir controls.

Fixed settings:

- `D = 1`, `n = 300`, `washout = 500`
- `pi_w = 0.03`, `pi_in = 1.00`
- `win_scale_global = 0.20`, `win_scale_bias = 0.20`
- AL likelihood, VB approximation, `max_iter = 1000`, `n_draws = 2000`
- independent regularized-horseshoe priors for reference and discrepancy
  readouts with `rhs_tau0 = rhs_alpha_tau0 = 0.003` and `slab_s2 = 1.0`

Candidate settings are listed in
`application/config/glofas_application_candidate_batch_20260524.csv`.
The matching reservoir-screening grid is
`application/config/reservoir_candidate_grid_latent_path_d1n300_candidate_batch_20260524.csv`.

## Candidate Configs

Each candidate has a tracked application config and model-grid file:

- `glofas_latent_path_al_vb_dec25_d1n300_m110a088r097_tau3em3_main1000.yaml`
- `glofas_latent_path_al_vb_dec25_d1n300_m110a086r097_tau3em3_main1000.yaml`
- `glofas_latent_path_al_vb_dec25_d1n300_m100a092r095_tau3em3_main1000.yaml`
- `glofas_latent_path_al_vb_dec25_d1n300_m100a092r093_tau3em3_main1000.yaml`
- `glofas_latent_path_al_vb_dec25_d1n300_m110a090r097s13_tau3em3_main1000.yaml`

The first four keep seed `20260512` so they can be compared directly with the
selected reference seed. The fifth uses seed `20260513` because the
`m110/a090/r097` reservoir was the strongest screened architecture but seed
`20260512` was rejected by the reservoir diagnostics.

## Launch Rule

Before launching a candidate, run a reservoir-validity pass for its exact
launch seed. The pass must use `--diagnostic_target both`, which checks the
semantic reference/shared-quantile reservoir matrix, the semantic discrepancy
reservoir matrix, and the corresponding readout matrices when available. This
is the required gate because the application model uses separate deterministic
DESN feature maps for the reference quantile block and the GloFAS discrepancy
block.

Launch-admissible means:

- the exact launch seed is not `reject`;
- neither `reference_reservoir` nor `discrepancy_reservoir` has decision
  `reject`;
- recurrent-layer diagnostics do not reject;
- finite, dead-state, saturation, effective-rank, condition-number, and
  near-duplicate checks are inspected in the screening tables;
- any `repair` decision is explicitly accepted before fitting.

Use commands of this form, changing `start_index`, `end_index`, `run_id`, and
`seeds` for each row of the candidate grid:

```bash
Rscript application/scripts/03_screen_reservoir_candidate_grid.R \
  --config application/config/glofas_latent_path_al_vb_dec25_d1n300_focused_screen.yaml \
  --candidate_grid application/config/reservoir_candidate_grid_latent_path_d1n300_candidate_batch_20260524.csv \
  --run_id reservoir_validity_d1n300_m110a088r097_20260524 \
  --seeds 20260512 \
  --diagnostic_target both \
  --cheap_validation false \
  --start_index 1 \
  --end_index 1
```

Only after this validity pass is reviewed should the corresponding candidate be
launched through `application/scripts/run_all.R` with `--confirm_final_launch
true --preflight true`. The preflight stage must pass after fitting before any
candidate is eligible for promotion.

Candidates should be compared first by median check loss against the same raw
GloFAS baseline, then by launch-readiness status, VB diagnostics, posterior-draw
contract checks, and post-fit figures. Promotion remains a separate action after
manual review.
