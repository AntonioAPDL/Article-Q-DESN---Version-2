# GloFAS p50 alpha/rho/tau response-surface campaign

Date: 2026-08-19

## Purpose

This campaign follows the completed 120-fit linked D1/D2 Stage-A screen. It
keeps the Stage-A leader's geometry fixed and asks a narrower scientific
question: can reservoir leak dynamics or the two regularized-horseshoe global
scales materially improve forecast-window p50 check loss without degrading the
pre-cutoff USGS fit?

The campaign is a p50 screening stage. It cannot estimate distributional CRPS,
cannot promote a model automatically, and cannot launch seven quantile fits.
Those actions remain downstream confirmation gates.

## Frozen evidence

Stage A completed 120 of 120 candidates with no failed fits. Its leader is
`linked_stage_a_109_de5070bceb`:

| Quantity | Stage-A leader | FR09 authoritative |
|---|---:|---:|
| Forecast p50 check loss | 0.7955671 | 0.7988270 |
| All-history log1p MAE | 0.0619720 | 0.0624424 |
| Last-200 log1p MAE | 0.0533880 | 0.0536083 |
| VB iterations | 109 | 103 |

The forecast gain is approximately 0.41%, below the frozen 3% prospective
full7 gate. Candidate 109 is therefore an optimization anchor, not a promoted
replacement for FR09.

The campaign verifies SHA-256 hashes for the complete Stage-A ranking, anchor
config, and anchor fit before materialization. A changed or missing anchor
fails preparation.

## Frozen model geometry

Reference/shared and discrepancy blocks remain separate DESNs with distinct
input streams and seeds. Except in the block-specific leak subdesign, their
numerical DESN specifications are linked:

| Field | Reference/shared | Discrepancy |
|---|---:|---:|
| `D` | 2 | 2 |
| `n` | `[200, 200]` | `[200, 200]` |
| `n_tilde` | `[200]` | `[200]` |
| `m` | 720 | 720 |
| Washout | 500 | 500 |
| Reservoir output lags | `1:720` | `1:720` |
| Reservoir ppt/soil lags | `0:720` | `0:720` |
| Direct output lags | `1:180` | `1:180` |
| Direct ppt/soil lags | `0:180` | `0:180` |
| `pi_w`, `pi_in` | 0.03, 1.00 | 0.03, 1.00 |
| Input/bias scale | 0.18, 0.18 | 0.18, 0.18 |
| Seed | 20260512 | 20261521 |

The reference DESN consumes transformed reference-streamflow history. The
discrepancy DESN consumes the retrospective GloFAS-minus-reference discrepancy
path. Both also use their contract-defined precipitation and soil-moisture lag
features. Sharing numerical settings never makes the two realized reservoirs
or their input matrices identical.

## Candidate design

The tracked campaign definition is:

```text
application/config/glofas_p50_alpha_rho_tau_response_surface_20260819.yaml
```

A full `16 x 7 x 10 x 10` Cartesian product would require 11,200 fits. The
implemented deterministic response-surface design contains 56 unique p50 fits:

| Subdesign | Unique fits | Purpose |
|---|---:|---|
| Warm/cold canaries | 4 | Anchor repeatability and coordinate-transfer bias |
| Linked alpha profile | 14 additional | Full approved leak support at `rho=0.95` |
| Linked rho profile | 6 additional | Full approved radius support at `alpha=0.20` |
| Alpha/rho maximin interactions | 12 | Broad deterministic interaction coverage |
| RHS `tau0` sentinels | 8 | One-block-at-a-time prior sensitivity |
| Block-specific alpha design | 12 additional | Reference/discrepancy leak separation |
| **Total** | **56** | Exact manifest invariant |

Profile duplicates are removed deterministically. Warm and cold runs with the
same scientific parameters are retained as distinct numerical treatments.
Candidate generation is deterministic for a fixed YAML file and is protected
by both `expected_candidates=56` and `max_candidates=56`.

The alpha support is
`0.005, 0.01, 0.025, 0.05, 0.075, 0.10, 0.125, 0.15, 0.175, 0.20, 0.225,
0.25, 0.30, 0.40, 0.60, 0.92`. The rho support is
`0.50, 0.70, 0.80, 0.85, 0.90, 0.95, 0.99`. Values below alpha 0.005 and rho
above one are excluded from the primary campaign.

## Warm-start contract

Every ordinary candidate uses the SHA-pinned Stage-A leader as its source:

- tau-only changes use `exact_design` coefficient, future-state, and scale
  transfer;
- alpha/rho changes use `coordinate_transfer`, are labeled as requiring cold
  confirmation, and are checked against explicit cold canaries;
- a candidate with changed feature layout would receive state-only transfer,
  although no such geometry change occurs in this campaign; and
- `warm_start_policy: cold` disables all source artifacts explicitly.

Warm/cold treatment is part of manifest identity. It cannot be silently
deduplicated or downgraded. The final ranking records requested policy, actual
compatibility mode, source hashes, and whether cold confirmation remains
required.

## Reservoir preflight

Before VB, every candidate runs the sampler-free reservoir diagnostic on the
actual two-block design. The report covers both independently seeded DESNs and
their actual input matrices:

- recurrent and leaky-effective spectral radii;
- empirical initial-condition forgetting after the effective lag/washout drop;
- finite, dead, and saturated states;
- correlation and near-duplicate fractions;
- entropy and participation effective rank; and
- design conditioning.

If two distinct initial states have already contracted to numerical zero by
the post-washout window, the diagnostic records a forgetting ratio of zero and
passes that check. Near-zero early separation followed by renewed separation
still fails. This avoids treating complete finite-precision forgetting as an
indeterminate zero-over-zero ratio.

`repair` remains admissible and is preserved in the evidence. A hard `reject`
creates a terminal preflight-rejection marker and skips VB. Scheduler, health,
and finalization code all recognize that terminal state, so an early rejection
does not make an otherwise complete batch appear stalled.

## Inference and execution

All fits use AL VB-LD with:

```text
max_iter = max_iter_hard_cap = 150
tol = tol_par = 1e-4
n_draws = 2000
n_samp_xi = 500
RHS global-scale freeze = 50 iterations
```

The cap is intentionally prospective and fixed before scoring. The Stage-A
leader converged at iteration 109, leaving 41 iterations of headroom. A
candidate that reaches 150 is recorded as such; convergence is not silently
asserted.

The scheduler uses 20 unique cores, one process and one numerical-library
thread per fit. The launch-time resource audit reserved
`0--7, 9, 12, 13, 20, 22, 25, 28, 30, 32--34, 38`, avoiding all 40 logical
cores occupied by the concurrent joint-QDESN phase-179 campaign and leaving
four additional cores unassigned. It validates config, model-grid,
warm-source, ownership, and SHA contracts before admission. Runtime state is
written under:

```text
local_trackers/runtime_configs/glofas_p50_alpha_rho_tau_response_surface_20260819
```

The generated launcher runs the bounded scheduler, complete-batch finalizer,
and guarded cleanup in sequence. Interrupted work is resumed from completion,
preflight-rejection, status, and PID evidence rather than from tmux names.
Nonwinning heavy fit/design objects are deleted only after the whole campaign
is terminal and the ranking has been written. Eligible candidates and, when no
candidate is eligible, the top-ranked candidate remain protected.

## Scoring and decisions

Primary screening score is forecast-window p50 check loss. Historical guards
compare pre-cutoff log1p MAE against FR09 over all history and the trailing
1000, 200, and 50 observations. The frozen prospective gate still requires at
least a 3% forecast improvement plus all hard historical and technical gates.

P50 check loss is not called CRPS. A candidate can only become eligible for
review. Required next steps are cold confirmation of finalists, diagnostic
review, seed confirmation, seven independently fitted quantiles, and genuine
quantile-grid CRPS comparison.

## Reproduction

Preparation requires the frozen Stage-A runtime anchor:

```bash
Rscript application/scripts/glofas_median_response_surface_prepare.R \
  --campaign application/config/glofas_p50_alpha_rho_tau_response_surface_20260819.yaml \
  --authorize_launch true
```

The generated `launch_screen.sh` is the only campaign launcher. Live state is
reported with:

```bash
python3 application/scripts/glofas_fit_recovery_health.py \
  --manifest local_trackers/runtime_configs/glofas_p50_alpha_rho_tau_response_surface_20260819/runtime_manifest.csv \
  --output-root local_trackers/runtime_configs/glofas_p50_alpha_rho_tau_response_surface_20260819
```

Runtime artifacts remain ignored. Tracked source, tests, this campaign YAML,
and this implementation note define how they are regenerated. This scientific
lane does not merge main, publish Overleaf, launch full7 automatically, or
modify PriceFM, validation, joint-QDESN, or package-engine work.
