# GloFAS Capacity-1000 Reservoir Candidate Batch, 2026-05-24

This note records the capacity-controlled depth/width batch prepared after the
selected GloFAS reference run
`latent_path_d1n300_m100a092r097_tau3em3_main1000_20260523_160355`.

## Design Rule

The batch keeps the promoted reference run settings fixed except for reservoir
depth and layer widths:

- total reservoir units satisfy \(\sum_{d=1}^D n_d = 1000\);
- `m = 100`, `washout = 500`;
- `alpha = 0.92`, `rho = 0.97` for every layer;
- `pi_w = 0.03`, `pi_in = 1.00` for every layer;
- `win_scale_global = 0.20`, `win_scale_bias = 0.20`;
- seed `20260512`;
- AL likelihood, VB approximation, `max_iter = 1000`, `n_draws = 2000`;
- independent regularized-horseshoe priors for reference and discrepancy
  readouts with `rhs_tau0 = rhs_alpha_tau0 = 0.003` and `slab_s2 = 1.0`.

For \(D>1\), `n_tilde[d-1]` is set equal to the previous layer width
`n[d-1]`. In the current article reservoir generator, this makes the
inter-layer state map \(Q_{d-1}\) an identity matrix. Unequal adjacent layer
widths are therefore still no-reduction candidates: the full previous layer
state is passed forward, and the next layer's input-weight matrix handles the
dimension change.

## Candidate Table

The authoritative table is
`application/config/glofas_capacity1000_candidate_batch_20260524.csv`.
The matching reservoir-screening grid is
`application/config/reservoir_candidate_grid_latent_path_capacity1000_20260524.csv`.

| ID | D | `n` | `n_tilde` | Role |
| --- | ---: | --- | --- | --- |
| `cap1000_d1n1000` | 1 | `1000` | none | wide shallow baseline |
| `cap1000_d2n500eq` | 2 | `500;500` | `500` | equal two-layer |
| `cap1000_d4n250eq` | 4 | `250;250;250;250` | `250;250;250` | moderate equal depth |
| `cap1000_d5n200eq` | 5 | `200;200;200;200;200` | `200;200;200;200` | deeper equal width |
| `cap1000_d10n100eq` | 10 | ten `100`s | nine `100`s | deep narrow stress test |
| `cap1000_d3n400x300x300` | 3 | `400;300;300` | `400;300` | front-loaded D3 |
| `cap1000_d3n333x334x333` | 3 | `333;334;333` | `333;334` | balanced D3 |
| `cap1000_d3n300x300x400` | 3 | `300;300;400` | `300;300` | back-loaded D3 |
| `cap1000_d6n200x200x150x150x150x150` | 6 | `200;200;150;150;150;150` | `200;200;150;150;150` | medium-deep taper |
| `cap1000_d8n125eq` | 8 | eight `125`s | seven `125`s | balanced deep alternative |

Each candidate has a tracked application config and matching model grid:

- `application/config/glofas_latent_path_al_vb_dec25_cap1000_*_tau3em3_main1000.yaml`
- `application/config/model_grid_latent_path_al_vb_dec25_cap1000_*_tau3em3_main1000.csv`

## Required Validity Gate

Do not launch a fit directly from these configs. First run a reservoir-validity
pass with `--diagnostic_target both` for the exact launch seed. This checks the
semantic reference/shared-quantile reservoir matrix, the semantic discrepancy
reservoir matrix, and the corresponding readout matrices when available.

Launch-admissible means:

- the exact launch seed is not `reject`;
- neither `reference_reservoir` nor `discrepancy_reservoir` has decision
  `reject`;
- recurrent-layer diagnostics do not reject;
- finite, dead-state, saturation, effective-rank, condition-number, and
  near-duplicate diagnostics have been reviewed;
- any `repair` decision is explicitly accepted before fitting.

Use commands of this form, changing `start_index`, `end_index`, and `run_id`
for the desired row of the candidate grid:

```bash
Rscript application/scripts/03_screen_reservoir_candidate_grid.R \
  --config application/config/glofas_latent_path_al_vb_dec25_d1n300_focused_screen.yaml \
  --candidate_grid application/config/reservoir_candidate_grid_latent_path_capacity1000_20260524.csv \
  --run_id reservoir_validity_cap1000_d1n1000_20260524 \
  --seeds 20260512 \
  --diagnostic_target both \
  --cheap_validation false \
  --start_index 1 \
  --end_index 1
```

Only after this validity pass is reviewed should the matching candidate config
be launched through `application/scripts/run_all.R` with
`--confirm_final_launch true --preflight true`. Promotion remains a separate
manual step after score tables, VB diagnostics, posterior-draw contract checks,
post-fit figures, and launch-readiness outputs have been reviewed.

## First Validity Pass

The first exact-seed validity pass was run on 2026-05-24 with run ID
`reservoir_validity_cap1000_all_20260524_203015`. The run artifacts are local
and ignored by git under:

```text
application/runs/reservoir_validity_cap1000_all_20260524_203015
```

Command:

```bash
Rscript application/scripts/03_screen_reservoir_candidate_grid.R \
  --config application/config/glofas_latent_path_al_vb_dec25_d1n300_focused_screen.yaml \
  --candidate_grid application/config/reservoir_candidate_grid_latent_path_capacity1000_20260524.csv \
  --run_id reservoir_validity_cap1000_all_20260524_203015 \
  --seeds 20260512 \
  --diagnostic_target both \
  --cheap_validation false \
  --start_index 1 \
  --end_index 10
```

Outcome: all ten candidates were rejected. No application fit was launched from
this batch.

| ID | Decision | Main failure mode |
| --- | --- | --- |
| `cap1000_d1n1000` | reject | low relative effective rank in the reference reservoir matrix |
| `cap1000_d2n500eq` | reject | state saturation in both semantic reservoir matrices |
| `cap1000_d4n250eq` | reject | state saturation in both semantic reservoir matrices |
| `cap1000_d5n200eq` | reject | state saturation in both semantic reservoir matrices |
| `cap1000_d10n100eq` | reject | state saturation in both semantic reservoir matrices |
| `cap1000_d3n400x300x300` | reject | state saturation in both semantic reservoir matrices |
| `cap1000_d3n333x334x333` | reject | state saturation in both semantic reservoir matrices |
| `cap1000_d3n300x300x400` | reject | state saturation in both semantic reservoir matrices |
| `cap1000_d6n200x200x150x150x150x150` | reject | state saturation in both semantic reservoir matrices |
| `cap1000_d8n125eq` | reject | state saturation in both semantic reservoir matrices |

The recurrent-layer diagnostics passed for all 90 checked semantic layers, so
the failure is not a recurrent-weight stability failure. It is a realized
state-feature failure: for this input design and seed, the capacity-1000
settings with `alpha = 0.92`, `rho = 0.97`, `win_scale_global = 0.20`, and
`win_scale_bias = 0.20` produce reservoir states that are too saturated or too
low-rank for launch.

The next capacity-1000 screen should keep the same two-DESN contract and
independent RHS prior contract, but relax the state dynamics before any fit is
attempted. The primary repair knobs are:

- lower `win_scale_global` and `win_scale_bias`;
- lower `rho`;
- optionally use `input_bound = tanh`;
- keep `pi_w = 0.03` and `pi_in = 1.00` fixed unless the scaled candidates
  still fail;
- rerun `--diagnostic_target both` before launching any application fit.

## Repair Screening Campaign

The comprehensive repair screen prepared on 2026-05-24 keeps the ten
capacity-1000 depth/width cases, the exact launch seed, the two-DESN
application contract, and the independent RHS prior contract fixed. It varies
only the reservoir dynamics that can plausibly repair the observed realized
state-feature failures:

- `alpha` in `{0.92, 0.80, 0.65}`;
- `rho` in `{0.95, 0.93, 0.90}`;
- `win_scale_global = win_scale_bias` in `{0.10, 0.05, 0.025}`;
- `input_bound` in `{none, tanh}`.

This gives 54 candidates per depth/width case and 540 candidates total. The
authoritative repair-grid files are:

```text
application/config/glofas_capacity1000_repair_screen_20260524.csv
application/config/reservoir_candidate_grid_latent_path_capacity1000_repair_screen_20260524.csv
```

The screen is intended to find one launch-admissible candidate per base case,
if such a candidate exists. It must still be interpreted conservatively:

- `pass` candidates are eligible for a cheap validation or micro-pilot stage;
- `repair` candidates can be considered only after their specific warnings are
  reviewed;
- `reject` candidates must not be launched.

The shard collector for this campaign is:

```bash
Rscript application/scripts/03_collect_reservoir_screening_shards.R \
  --run_id_prefix reservoir_repair_cap1000_20260524 \
  --require_completed true
```

The collector writes ignored local summaries under
`application/outputs/generated/reservoir_screening/reservoir_repair_cap1000_20260524`,
including `best_candidate_by_case.csv` and `ranked_candidates.csv`.

Because the first rows of the repair screen still showed only rejections, a
gentler extension screen was also prepared. It keeps the same ten base cases
and varies:

- `alpha` in `{0.50, 0.35}`;
- `rho` in `{0.85, 0.75, 0.65}`;
- `win_scale_global = win_scale_bias` in `{0.025, 0.0125, 0.005}`;
- `input_bound` in `{none, tanh}`.

This adds 36 candidates per depth/width case and 360 candidates total. The
authoritative extension files are:

```text
application/config/glofas_capacity1000_gentle_repair_screen_20260524.csv
application/config/reservoir_candidate_grid_latent_path_capacity1000_gentle_repair_screen_20260524.csv
```

Its collector command is:

```bash
Rscript application/scripts/03_collect_reservoir_screening_shards.R \
  --run_id_prefix reservoir_gentle_cap1000_20260524 \
  --require_completed true
```
