# GloFAS Overnight Reservoir Ladder Screen, 2026-05-25

This note records the broad screening-only campaign prepared after the
capacity-1000 screens rejected all candidates and after the D1 n300 selected
reference run remained the strongest reproducible application baseline.

## Objective

Find healthier D-ESN reservoir specifications for the two-block latent-path
GloFAS Q-DESN application before launching any new application fit. The screen
checks both semantic reservoir feature maps:

- the reference/shared-quantile DESN block;
- the GloFAS discrepancy DESN block.

No VB, MCMC, promotion, or manuscript-facing application launch is performed by
this campaign.

## Fixed Contract

- Dec. 25, 2022 authoritative application panel and cutoff contract.
- Two-block latent-path design.
- Independent RHS priors for reference and discrepancy readouts remain fixed
  for later fits.
- `pi_w = 0.03`, `pi_in = 1.00`.
- `washout = 500`.
- `act_f = tanh`, `act_k = identity`.
- Exact screening seed `20260512`.
- `--diagnostic_target both`.

## Candidate Families

The generated grid is:

```text
application/config/reservoir_candidate_grid_latent_path_overnight_ladder_20260525.csv
```

The compact family summary is:

```text
application/config/glofas_overnight_ladder_screen_20260525.csv
```

The grid is larger and broader than the previous 900-row capacity-1000 repair
screen. It includes:

| Family | Role |
| --- | --- |
| `positive_control_d1n300` | refine the current selected D1 n300 region |
| `shallow_capacity_ladder` | test D1 widths 400, 500, 700, and 1000 |
| `two_layer_ladder` | test D2 no-reduction candidates with total capacity 500, 700, and 1000 |
| `three_layer_ladder` | test controlled D3 no-reduction candidates |
| `deep_stress` | retain a small deep stress block for D4, D5, D6, D8, and D10 |

## Decision Policy

The strict main-launch gate remains unchanged. A candidate should be treated as
main-admissible only if it passes the state and layer checks without hard
rejection and has:

- maximum saturation fraction at most `0.30`;
- minimum relative entropy effective rank at least `0.05`;
- covariance and state condition numbers below the hard rejection thresholds.

For discovery only, the triage script also marks close candidates:

- `pilot_override`: no hard condition failure, saturation at most `0.35`, and
  relative entropy effective rank at least `0.04`;
- `manual_near_miss`: rejected by the strict diagnostics but close to the pilot
  thresholds;
- `exploratory_only`: useful for learning, but not for fitting;
- `reject`: do not fit.

Pilot override is not a main-launch approval. It only identifies candidates for
manual review and possible tiny pilots.

## Reproducible Commands

Build the grid:

```sh
Rscript application/scripts/03_make_overnight_ladder_screen_grid_20260525.R
```

Launch the sharded screen:

```sh
tmux new-session -d -s reservoir_overnight_ladder_20260525 \
  'bash application/scripts/03_launch_overnight_ladder_screen_20260525.sh'
```

Collect manually if needed:

```sh
Rscript application/scripts/03_collect_reservoir_screening_shards.R \
  --run_id_prefix reservoir_overnight_ladder_full_20260525 \
  --require_completed true
```

Classify collected candidates:

```sh
Rscript application/scripts/03_rank_reservoir_screening_for_pilots.R \
  --screening_dir application/outputs/generated/reservoir_screening/reservoir_overnight_ladder_full_20260525
```

## Tomorrow's Review

1. Confirm every shard completed.
2. Read `pilot_triage_summary.csv`.
3. Inspect `main_admissible` candidates first.
4. If none exist, inspect `pilot_override` and `manual_near_miss` candidates.
5. Run multi-seed robustness only for the top candidates.
6. Launch tiny application pilots only after explicit approval.
7. Do not launch a new main run directly from this screen.
