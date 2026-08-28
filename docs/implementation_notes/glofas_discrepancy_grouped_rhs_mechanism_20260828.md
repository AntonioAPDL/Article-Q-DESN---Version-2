# GloFAS Grouped-RHS Discrepancy Mechanism Campaign

## Scope and decision boundary

This change implements the prospectively frozen mechanism experiment described
in the ignored plan
`local_trackers/glofas_discrepancy_rhs_mechanism_and_rich_screen_ultimate_plan_20260827.md`.
It addresses one finding from the completed discrepancy-equivalence audit: the
forecast contribution of the discrepancy reservoir was only about 1.39% of the
penalized readout RMS measure, and materially different reservoir geometries
therefore produced nearly identical 28-day discrepancy paths.

The experiment asks whether a single global regularized-horseshoe scale for all
discrepancy-readout coefficients suppresses reservoir features relative to the
large direct-lag block. It does not change the latent transition, GloFAS or
covariate inputs, reference DESN, discrepancy DESN geometry, AL likelihood,
dense VB covariance, historical guardrails, or forecast score definition.

Only the p50 mechanism stage is authorized. A full-seven-quantile rerun,
promotion, article update, and any transition redesign remain explicitly
unauthorized. FR09 remains the manuscript-facing result unless a later,
separately reviewed confirmation passes.

## Prior extension

Let the discrepancy readout coefficients be partitioned semantically into
direct coefficients `D`, reservoir coefficients `R`, and unpenalized
intercepts. The direct group contains output lags, precipitation/soil lags, and
the horizon term. The reservoir group contains current reservoir states and
reservoir-state lags. Feature names are never parsed heuristically: the
partition is built from `feature_info_alpha$block`, must cover every penalized
coefficient exactly once, and is bound to a stable layout hash.

For coefficient `alpha_j` in group `g`, the existing conditional precision is
retained with a group-specific global scale:

```text
E[precision(alpha_j)]
  = E[tau_g^{-2}] E[lambda_j^{-2}] + E[zeta^{-2}].
```

The local `lambda_j` hierarchy is unchanged. Each group receives its own
`tau_g` and auxiliary `xi_g` CAVI update, while `zeta` remains one shared
dynamic regularizer over the complete alpha block. The intercept precision is
unchanged and is never assigned to a penalized group. The declared `slab_s2`
field remains accepted legacy metadata but is explicitly recorded as inert; the
campaign does not silently activate a new slab term.

When grouping is disabled, dispatch returns the original single-scale update.
The legacy path is covered by an identity test. Checkpoint contracts now bind
the grouping specification, semantic layout, prior hashes, and every grouped
update function, so a checkpoint from another grouping or implementation is
rejected.

## Frozen model and inference

| Component | Frozen specification |
|---|---|
| Reference block | FR09: D1, width 300, memory 360, alpha 0.10, rho 0.95, seed 20260512 |
| Discrepancy block | Retained D16: width 64, memory 1080, alpha 0.075, rho 0.95, seed 20261521 |
| Transition | Persistence-anchored innovation |
| Reference RHS `tau0` | 0.10 |
| Legacy discrepancy RHS `tau0` | 1e-4 |
| RHS global-scale warmup | 50 VB iterations |
| VB controls | max 200, `tol=tol_par=1e-4`, 1,000 draws, 500 xi samples |
| Numerical backend | Hash-pinned serial OpenBLAS, one thread per fit |
| Forecast target | Existing fixed 28-day window; no new cutoff or forecast inputs |

## Prospective Stage A design

Stage A contains exactly 18 p50 fits. A0 is the mandatory eight-fit mechanism
gate. A1 contains ten directional prior refinements and is launched only if the
frozen A0 activation rule passes.

### A0

| ID | Role | Direct `tau0` | Reservoir `tau0` | Initialization |
|---|---|---:|---:|---|
| `grhs_a0_01` | Legacy D16 repeat | single 1e-4 | single 1e-4 | cold |
| `grhs_a0_02` | Initialization canary | single 1e-4 | single 1e-4 | exact-design warm |
| `grhs_a0_03` | Equal grouped canary | 1e-4 | 1e-4 | cold |
| `grhs_a0_04` | Reverse-direction control | 1e-2 | 1e-4 | exact-design warm |
| `grhs_a0_05` | Direct-only fitted canary | single 1e-4 | absent | cold |
| `grhs_a0_06` | Reservoir-only fitted canary | absent | single 1e-4 | cold |
| `grhs_a0_07` | Directional moderate | 1e-5 | 1e-2 | exact-design warm |
| `grhs_a0_08` | Directional strong | 1e-6 | 1e-1 | exact-design warm |

### Conditional A1

A1 evaluates the Cartesian support
`tau0_direct in {1e-6,1e-5,1e-4,1e-3}` and
`tau0_reservoir in {1e-3,1e-2,1e-1}`, excluding the two combinations already
run as A0 directional candidates. Every A1 fit uses the verified exact-design
warm start. The candidate generator asserts 8/10 wave counts, unique IDs,
unique numerical-treatment hashes, positive grouped scales, and declared-only
duplicate model hashes for the warm/cold initialization canary.

## Initialization contract

Warm starts are allowed only when the retained D16 source and target have the
same semantic design. The campaign requests coefficient, latent-future, and
source-scale initialization and requires the coefficient and future states to
be used. Direct-only and reservoir-only designs are deliberately cold because
their coefficient dimensions differ. Closeout independently verifies the
reported warm/cold treatment; a silent fallback makes the candidate
ineligible.

## Scoring and gates

The primary Stage A response is held-out forecast discrepancy MAE. For p50,
the implementation checks row by row that this equals the MAE of the corrected
USGS path and that p50 check loss is one half of that MAE. It also verifies that
the model-exported corrected path equals the independently reconstructed
`raw_glofas - predicted_discrepancy` path.

Historical USGS fit is a constraint, not the Stage A optimization target. Hard
relative-degradation limits versus the current-engine FR09 evidence are 2% for
all history, 2% for the last 1,000 observations, and 5% for the last 200. The
last-50 window has a 10% warning rather than a hard rejection because of its
greater local variability.

A0 proceeds only if at least one prospectively frozen mechanism condition
activates without systematic numerical or historical failure:

- direct and reservoir effective global scales separate by at least 2, and the
  reservoir RMS share reaches both 5% and five times the legacy-control share;
- a directional grouped fit changes the path beyond the repeatability envelope
  and beats the reverse-direction control; or
- the fitted reservoir-only canary improves by at least 1% over both the
  direct-only canary and the legacy control.

After A1, scientific success additionally requires at least 5% discrepancy-MAE
gain over the cold legacy D16 repeat and performance better than last-observed
persistence. This only authorizes a later Stage B confirmation. It does not
promote a model.

Technical eligibility requires a completed p50 fit, finite theta and sigma,
declared convergence, passed beta and alpha RHS release gates, passed draw and
forecast identities, exact warm/cold treatment, exact prior and semantic-layout
hashes, and exact reconstruction of the discrepancy innovation from direct,
reservoir, and intercept contributions.

## Runtime, monitoring, and recovery

The preparation script verifies SHA-256 hashes for the retained D16 config,
model grid, panel, fit, design, forecast table, observed-fit table, FR09
references, equivalence evidence, and numerical library. An authorized
preparation is accepted only from a clean, pushed dedicated task branch whose
HEAD equals its upstream. The orchestrator rechecks the campaign hash,
snapshot hash, prepared HEAD, and tracked-tree cleanliness before starting.

The orchestrator never uses a fixed global CPU claim. It identifies genuinely
idle physical cores after collapsing hyperthread siblings, records an ownership
audit, and waits when none are free. A0 begins with four calibration fits. Once
each reaches iteration 10 or terminates, the scheduler uses observed process-
tree RSS and a 48 GB reserve to cap concurrency. The upper limit is 20 jobs,
one serial numerical thread per fit, but the actual limit is the smaller of
free physical cores and the measured memory-safe count.

Each candidate has an atomic checkpoint every 50 iterations or 30 minutes.
Relaunching the orchestrator reconciles completion markers, live worker PIDs,
and hash-validated checkpoints. A `STOP` marker halts new launches without
killing active workers. A1 is never materialized into execution merely because
A0 finishes; the frozen A0 decision file must authorize it.

Use:

```bash
Rscript application/scripts/glofas_discrepancy_grouped_rhs_prepare.R \
  --campaign application/config/glofas_discrepancy_grouped_rhs_stage_a_20260827.yaml \
  --authorize_launch true

bash local_trackers/runtime_configs/glofas_discrepancy_grouped_rhs_stage_a_20260828/launch_stage_a.sh

python3 application/scripts/glofas_discrepancy_grouped_rhs_health.py \
  --output-root local_trackers/runtime_configs/glofas_discrepancy_grouped_rhs_stage_a_20260828
```

The launch is normally placed in a dedicated detached tmux session. Generated
configs, checkpoints, logs, fits, designs, scores, and figures remain under the
ignored task-owned runtime root.

## Artifact lifecycle

Fit and compact design objects are retained during fitting because closeout
needs exact contribution and contract checks. The finalizer loads one
candidate at a time, hashes the fit/design pair, writes compact evidence,
removes the objects from memory, and runs garbage collection. It then creates a
dry-run cleanup manifest protecting the cold control and the three best
eligible candidates. Cleanup can execute only after the corresponding frozen
decision exists, only for hash-matching `.rds/.rda/.RData` files inside this
campaign's `runs/` tree, and only when no campaign worker or orchestrator PID is
alive.

## Implementation surface

- `application/R/model_contract.R`: grouping normalization, semantic layout,
  declared/effective prior contracts and hashes.
- `application/R/latent_path_vb_al.R`: grouped RHS CAVI state, update dispatch,
  traces, release gates, and diagnostics.
- `application/R/fit_qdesn_discrepancy.R` and
  `application/R/fit_qdesn_latent_path.R`: configuration wiring, layout
  materialization, and fit-level contracts.
- `application/R/latent_path_checkpoint.R`: checkpoint semantic and engine
  binding.
- `application/R/glofas_discrepancy_grouped_rhs_campaign.R`: candidates,
  scoring identities, historical gates, fit-contract validation, and
  contribution decomposition.
- `application/scripts/glofas_discrepancy_grouped_rhs_{prepare,finalize,cleanup}.R`:
  prospective preparation, fail-closed closeout, and scoped artifact lifecycle.
- `application/scripts/glofas_discrepancy_grouped_rhs_orchestrate.sh`,
  `glofas_discrepancy_grouped_rhs_health.py`, and
  `glofas_select_free_cpus.py`: gated execution and monitoring.
- `application/scripts/glofas_fit_recovery_scheduler.py`: calibrated dynamic
  memory concurrency and wave-specific resumable state.

## Validation contract

Required before launch:

- all changed R files parse;
- all changed Python files byte-compile;
- shell launchers pass `bash -n`;
- grouped-RHS algebra, partition, prior-hash, checkpoint-mismatch, score-
  identity, historical-gate, and candidate-count tests pass;
- existing RHS warmup tests pass;
- Python scheduler and CPU-topology tests pass;
- an unauthorized 18-candidate rehearsal passes every source hash and remains
  unable to launch;
- a retained production design confirms the semantic partition and exact
  contribution reconstruction; and
- `git diff --check` passes.

No article file belongs to this implementation surface. Manuscript compilation
is therefore not an acceptance criterion for this scientific lane.

## Prelaunch validation evidence

The implementation was validated from the dedicated task worktree before any
authorized fit was started:

| Check | Result |
|---|---|
| Changed/new R source parsing | Passed, 12/12 files |
| Changed/new Python byte compilation | Passed, 4/4 files |
| Orchestrator `bash -n` | Passed |
| Scheduler/resource unit tests | Passed, 24/24 |
| Grouped-RHS algebra and campaign tests | Passed in the repository R harness |
| Existing RHS warmup and p95 launch-contract tests | Passed in the repository R harness |
| Full R harness | Reached and passed all GloFAS tests, then stopped at the known unrelated shared-validation assertion `nrow(promoted) == 18L` |
| Unauthorized preparation rehearsal | Passed: 18 candidates, 8 A0, 10 A1, 14 warm, 4 cold; launch correctly refused |
| Retained D16 semantic partition | Passed: 542 direct, 1,024 reservoir, and one intercept feature |
| Retained D16 contribution identity | Passed: maximum absolute reconstruction error `1.221e-15` |
| Retained D16 penalized reservoir RMS share | `0.00338556`, establishing the prospective control value |
| `git diff --check` | Passed |

The production partition result differs from the earlier D32 aggregate
diagnostic because it uses the retained D16 geometry and the campaign's exact
penalized direct-versus-reservoir definition. It strengthens the reason for the
experiment: under the geometry used for Stage A, the reservoir contribution is
only about 0.34% before grouped shrinkage is introduced.
