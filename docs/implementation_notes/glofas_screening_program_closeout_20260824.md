# GloFAS constrained-median screening program closeout

Date: 2026-08-24

## Decision

The linked D1/D2, alpha/rho/tau response-surface, focused alpha/tau, and
structural memory/geometry campaigns are complete. Together they considered
244 prospectively specified p50 candidates: 202 completed VB fits and 42 valid
reservoir-preflight rejections. No candidate passed the frozen 3% improvement
gate or became eligible for a cold p50 confirmation.

`fr09_persistence_innovation` therefore remains the authoritative full-seven
GloFAS application result. This closeout launches no fit, triggers no full-seven
rerun, and changes no article table, figure, or prose.

## Cumulative evidence

| Phase | Total | Fitted | Preflight reject | Leader | Forecast p50 loss | Gain over FR09 |
|---|---:|---:|---:|---|---:|---:|
| Linked D1/D2 Stage A | 120 | 120 | 0 | `linked_stage_a_109_de5070bceb` | 0.795567 | 0.408% |
| Alpha/rho/tau response surface | 56 | 39 | 17 | `linked_alpha_profile_010_b20be44357` | 0.794386 | 0.556% |
| Focused alpha/tau refinement | 20 | 18 | 2 | `block_alpha_refinement_019_b1b26b2d8e` | 0.794186 | 0.581% |
| Structural memory/geometry | 48 | 25 | 23 | `symmetric_memory_direct_009_9c3d23fb3a` | 0.793895 | 0.617% |

FR09's frozen forecast p50 check loss is 0.798827. The last campaign's leader
passes the historical-fit and technical gates, but its paired mean gain over
the focused anchor is only 0.000291 in loss units. The moving-block interval is
[-0.001406, 0.000864], which includes no improvement, and the gain is smaller
than the measured 0.000603 warm/cold repeatability envelope. The numerical rank
is therefore useful diagnostic evidence, not a promotion result.

These are median check-loss comparisons. They are not distributional CRPS.
Distributional CRPS remains available only from a complete seven-quantile
synthesis.

## What the program learned

- Increasing reservoir memory and selectively changing direct memory produced
  small gains, but not a stable promotion-scale effect.
- The local rho response was nearly flat over the viable range.
- Very low leak rates often failed forgetting or effective-rank diagnostics;
  large leak rates increased saturation risk.
- Separate reference and discrepancy leak/prior settings helped marginally,
  confirming that the two input streams should remain separate, but their
  effects were smaller than the frozen promotion threshold.
- Broader depth, width, memory, direct-lag, and block-asymmetry profiles did not
  uncover a qualitatively different performance regime.
- A single 28-day forecast origin has insufficient signal to justify ever finer
  local hyperparameter optimization when the observed gain is inside numerical
  repeatability uncertainty.

## Reproducible closeout

The tracked contract is:

```text
application/config/glofas_screening_program_closeout_20260824.yaml
```

Run the fail-closed program audit with:

```bash
Rscript application/scripts/glofas_screening_program_closeout.R
```

The ignored output root is:

```text
local_trackers/runtime_configs/glofas_screening_program_closeout_20260824
```

It contains the phase census, program decision, evidence hashes, and final audit
status. Ranking hashes and expected leaders are frozen in the tracked contract;
count, schema, leader, or hash drift aborts the audit.

## Retention and storage

All compact configs, manifests, hashes, rankings, scores, logs, diagnostics,
and figures remain available. The Stage-A rank-1 and rank-2 fit/design objects
are retained because rank 1 is a hash-pinned provenance source and rank 2 is the
closest rho control. Heavy fit/design objects from other terminal Stage-A
candidates may be deleted through the existing guarded cleanup API only after
a dry-run inventory and retained-object hash manifest have been written.

The response-surface, focused, and structural campaigns already applied the
same protected-finalist retention policy.

The final Stage-A cleanup removed 236 heavy fit/design files from 118 terminal
nonfinalists, recovering 182.10 GB (decimal). Four rank-1/rank-2 fit/design
files remain and all retained SHA-256 values revalidated after deletion. The
Stage-A runtime root fell from 178 GiB to 8.3 GiB; its shared application-panel
cache and all compact evidence were retained. The cleanup-report SHA-256 is
`d28f8ddf9b2a3d4fbb644368943174e3c94202626b0ac6416347b7102f90805f`.

## Future restart contract

Another local DESN alpha/rho/tau, depth, width, memory, or direct-lag grid around
the current centers is not justified by this evidence. A future GloFAS study
must begin with a distinct, prospectively stated forecasting hypothesis, such
as a changed discrepancy-transition or forecast-covariate information contract.

Before any such launch:

1. evaluate the hypothesis over multiple historical cutoffs rather than tuning
   to one 28-day window;
2. freeze data, cutoff, transition, covariate, initialization, and scoring
   contracts before inspecting outcomes;
3. retain p50 check loss as the median screening metric and preserve the
   all-history and trailing-window observed-fit guards;
4. use a small bridge design with cold controls and paired horizon-level
   comparisons before a larger campaign;
5. require an effect larger than both the prospective scientific threshold and
   the measured repeatability envelope;
6. cold-confirm finalists across reservoir seeds; and
7. run seven independent quantile fits and genuine CRPS synthesis only after
   those gates pass.

No future campaign is authorized by this note. Parameter support, cutoffs,
resource allocation, and launch approval must be supplied prospectively.

## Integration scope

This work belongs only to the dedicated GloFAS branch. It does not modify
PriceFM, validation, joint-QDESN, authoritative main, or Overleaf. The
integration chat should merge the GloFAS branch only after reviewing its frozen
handoff and combined-repository tests.
