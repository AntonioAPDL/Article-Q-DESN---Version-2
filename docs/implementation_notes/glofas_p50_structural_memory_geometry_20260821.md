# GloFAS p50 structural memory and geometry campaign

## Decision summary

The completed Stage-A, response-surface, and focused campaigns rule out another
large local alpha/rho/tau grid as the best use of computation. The focused
leader improves forecast p50 check loss by only 0.581% over FR09, below the
prospective 3% gate. `rho` was effectively flat across `.50-.99`; very small
leak rates failed effective-rank/forgetting diagnostics; large leak rates
saturated; and local prior effects were generally smaller than warm/cold path
effects.

The unresolved scientific question is structural: how much reservoir depth,
width, recurrent-input history, direct-input history, and block asymmetry are
needed by the two distinct GloFAS input streams. This campaign isolates those
questions around the best viable dynamic/prior center rather than mixing them
with another prior sweep.

## Frozen center and estimand

All candidates remain the same two-block latent-path Q-DESN application model.
The reference/shared and discrepancy reservoirs use distinct input vectors and
seeds. The center is the completed focused rank 1:

| Contract | Reference/shared | Discrepancy |
|---|---:|---:|
| D / width | 2 / 200 | 2 / 200 |
| Reservoir memory | 720 | 720 |
| Direct-input memory | 180 | 180 |
| Leak / rho | .10 / .95 | .075 / .95 |
| RHS tau0 | .10 | 1e-4 |
| Seed | 20260512 | 20261521 |

Every profile keeps washout 500, `pi_w=.03`, `pi_in=1`, input scales `.18`,
no state reduction between layers, AL VB-LD, 2,000 posterior draws, 500 xi
samples, a 50-iteration global-scale freeze, `tol=tol_par=1e-4`, and a hard
150-iteration cap. Reservoir output lags are `1:m`; PPT/soil lags are `0:m`.
Direct output lags are `1:L`; direct PPT/soil lags are `0:L`.

The primary screening estimand is unchanged: final-cutoff forecast-window p50
check loss, subject to pre-cutoff observed-fit guards. A p50 check loss is not
called CRPS. Genuine distributional CRPS requires an independently fitted
seven-quantile confirmation.

## Audit evidence

Stage A supplied the most useful structural signal under the current workflow:

- `m=720` improved the median and best score relative to `m=360`;
- direct memory 180 was generally better than 360;
- D2/n200 produced the best Stage-A score, but no tested architecture cleared
  the promotion gate;
- width helped in several historical screens, while depth helped only when it
  retained adequate per-layer width; and
- older D4/D8 results are qualitative priors only because their transition and
  scoring contracts differ from the current FR09 contract.

These findings support a bounded, role-balanced design instead of a Cartesian
product. Extremely large historical geometries are excluded from this first
structural wave because they would multiply memory and exact-VB cost before a
current-contract bridge candidate establishes value.

## Candidate design

The campaign contains exactly 48 p50 candidates, executed in at most three
waves on 20 one-thread workers:

| Evidence role | Count | Question |
|---|---:|---|
| Repeatability controls | 2 | Warm and cold reproduction of the focused leader |
| Symmetric memory/direct profiles | 13 | Reservoir history 360--1080 and direct history 90--360 |
| Symmetric architecture profiles | 14 | D1--D8 with widths 75--500 |
| Architecture-memory interactions | 6 | Whether wider/deeper reservoirs benefit from m=900/1080 |
| Block-specific architectures | 6 | Whether the two distinct input streams need different geometry |
| Block-specific memories | 7 | Whether reference and discrepancy histories should differ |

No layer reduction is introduced: `n_tilde=n` whenever `D>1`. The largest
single layer is 500, within the exact spectral-radius preflight bound of 512;
the largest total per-block state is 800. The design therefore broadens the
scientific support while retaining bounded diagnostics and storage.

## Initialization and validity

The source ranking, config, and fit object are SHA-256 pinned in the tracked
campaign YAML. Warm starts are initialization only:

- the exact warm control may transfer coefficients, future state, and scale;
- structural/layout changes may transfer future state and scale only;
- coefficient transfer is prohibited when feature coordinates change; and
- every transferred structural candidate requires a cold confirmation before
  it can advance.

The cold control quantifies numerical repeatability. After this broad screen,
at most three promising candidates should be cold-confirmed. No warm result can
launch full7 or update the article automatically.

Both actual reservoirs are screened using their distinct inputs for spectral
and leaky radii, empirical forgetting, finite/dead/saturated states,
correlation, effective rank, and conditioning. A preflight reject is a terminal
scientific outcome and skips VB.

## Selection and stopping rules

The prospective gate is frozen before launch:

- at least 3% forecast p50 check-loss improvement over FR09;
- all-history and trailing-1000 observed log1p MAE no worse than 1.05x FR09;
- trailing-200 observed log1p MAE no worse than 1.10x FR09;
- trailing-50 no worse than 1.15x is reported as a warning, not a hard gate;
- finite technical diagnostics and reservoir-preflight passage; and
- cold p50 confirmation before full7 review.

If no candidate clears 3%, the batch stops without full7 or article changes.
If candidates clear it, diagnostic review and cold confirmation precede a
seven-quantile run and genuine quantile-grid CRPS comparison.

## Reproducibility and execution

Tracked inputs:

```text
application/config/glofas_p50_structural_memory_geometry_20260821.yaml
application/R/glofas_median_structural_campaign.R
application/scripts/glofas_median_structural_prepare.R
```

Preparation and launch are separate and resumable:

```bash
Rscript application/scripts/glofas_median_structural_prepare.R \
  --campaign application/config/glofas_p50_structural_memory_geometry_20260821.yaml \
  --authorize_launch true

tmux new-session -d -s glofas_p50_structural_memory_geometry_20260821_scheduler \
  "bash local_trackers/runtime_configs/glofas_p50_structural_memory_geometry_20260821/launch_screen.sh"
```

The ignored runtime root contains the materialized manifest, candidate configs,
hash contracts, scheduler state, per-worker logs, scores, final ranking, and
cleanup evidence. Finalization is permitted only after all 48 candidates are
terminal. It removes nonprotected heavy fit/design objects and retains rank 1.

This work remains on the dedicated GloFAS branch. It does not modify PriceFM,
validation, joint-QDESN, package-engine, authoritative main, or Overleaf.

## Checklist

- [x] Freeze completed focused-campaign evidence and hashes.
- [x] Audit structural patterns and reject an uncontrolled Cartesian grid.
- [x] Define 48 deterministic, role-balanced candidates.
- [x] Pin the focused rank-1 warm-source artifacts.
- [x] Preserve separate blocks, inputs, seeds, priors, and no-reduction layers.
- [x] Preserve prospective observed-fit and forecast gates.
- [x] Add reservoir preflight and bounded storage cleanup.
- [x] Add deterministic tests for cardinality, profiles, lags, and warm policy.
- [x] Materialize and verify all runtime contracts.
- [x] Re-audit active cores immediately before launch.
- [x] Launch 20 one-thread workers without disturbing other lanes.
- [x] Complete/finalize the 48-candidate batch: 25 fits, 23 preflight
  rejections, and no unresolved failures.
- [x] Apply the prospective cold-confirmation gate. No candidate qualified.
- [x] Apply the prospective full7 gate. No full7 run was warranted or launched.

The final leader was `symmetric_memory_direct_009_9c3d23fb3a`, with forecast
p50 check loss 0.793895 and a 0.617% gain over FR09. Its paired improvement over
the focused anchor was inside the warm/cold repeatability envelope and its
moving-block interval crossed zero. See
`docs/implementation_notes/glofas_screening_program_closeout_20260824.md` for
the cumulative decision.
