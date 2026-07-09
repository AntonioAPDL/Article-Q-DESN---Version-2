# GloFAS Shortlist Multiseed Reservoir Screen, 2026-05-25

This note records the next gate after the broad overnight reservoir ladder
screen. The purpose is seed-robustness screening only. It does not run VB,
MCMC, application scoring, promotion, or manuscript-output selection.

## Input Evidence

The broad screen output is:

```text
application/outputs/generated/reservoir_screening/reservoir_overnight_ladder_full_20260525
```

It screened 2,016 candidates. The triage summary was:

| triage class | candidates |
| --- | ---: |
| `main_admissible` | 578 |
| `manual_near_miss` | 391 |
| `reject` | 1,047 |

The useful signal was concentrated in D1 and D2 candidates. D3 and deeper
stress-test candidates produced no main-admissible rows under the current
screening policy.

## Shortlist Construction

The shortlist is built by:

```sh
Rscript application/scripts/03_make_shortlist_multiseed_grid_20260525.R
```

The script reads `pilot_triage_candidates.csv`, keeps only `main_admissible`
rows, scores them by saturation, relative entropy effective rank, condition
number, and maximum absolute correlation, then selects a balanced set:

- current D1 n300 reference-control candidate;
- top D1 n300 positive-control refinements;
- top shallow D1 capacity-ladder candidates by base case;
- top D2 no-reduction candidates by base case;
- global score fill rows if needed.

The tracked outputs are:

```text
application/config/reservoir_candidate_grid_latent_path_shortlist_multiseed_20260525.csv
application/config/glofas_shortlist_multiseed_screen_20260525.csv
```

## Multiseed Gate

The shortlist is screened over seeds:

```text
20260512:20260518
```

The screen must use:

```text
--diagnostic_target both
```

so both semantic DESN feature maps are checked:

- reference/shared-quantile reservoir;
- GloFAS discrepancy reservoir.

The sharded launch command is:

```sh
tmux new-session -d -s reservoir_shortlist_multiseed_20260525 \
  'bash application/scripts/03_launch_shortlist_multiseed_screen_20260525.sh'
```

The full-screen run prefix is:

```text
reservoir_shortlist_multiseed_full_20260525
```

## Preflight

A one-candidate multiseed preflight was run before launching the full shortlist:

```text
run_id = reservoir_shortlist_multiseed_20260525_preflight_ref
candidate = d1n300_refine_m100_a0p92_r0p97_w0p20_boundnone
seeds = 20260512:20260518
status = completed
decision = repair
rejected seeds = none
state reports = 28 repair, 0 reject
```

This reproduces the current reference-control behavior over seven seeds and
confirms that the shortlist grid, seed loop, and semantic two-block diagnostics
are wired correctly.

## Interpretation Policy

This gate does not authorize a main application run. A candidate should be
considered for a tiny pilot only if:

- no seed is rejected;
- both semantic matrices are no worse than `repair`;
- layer stability diagnostics do not reject;
- saturation, rank, condition-number, and correlation diagnostics are reviewed
  across all seeds;
- it remains competitive with the current D1 n300 reference-control candidate.

If multiple candidates pass, prefer:

1. the best robust D1 n300 refinement;
2. a robust shallow D1 capacity candidate if it improves state diagnostics;
3. a robust D2 candidate only if it is stable across all seeds.

Do not launch a new full application model from this screen without explicit
approval.
