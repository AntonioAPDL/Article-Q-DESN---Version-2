# PriceFM R127: Frozen-Fit Driver Diagnosis

## Scope And Authorization

The 2026-10-08 request authorizes implementing and running the executable
Stage 0-2 portion of the ignored post-R126 master plan. This is BG-only
diagnosis, not an all-region refit, screening, model promotion, or manuscript
update. Stages 3-5 remain conditional on these diagnostics and a reviewed
corrective experiment. No existing R123-R126 source is modified. Dedicated
R127 branches only; integration and article publication belong to the coordinator.

Parent HEAD: `e2ab44b7062710ab4c105b1afec23f27a66425f2`.
Parent tag: `pricefm_stage_r126_matched_comparison_20261007`.
New tag: `pricefm_stage_r127_driver_diagnosis_20261008`.
Pinned baseline plan SHA-256:
`c0b1c670e23d3f5914e24d9a0740cf98e95931cda58d6547ac01c7e7f3cd39fc`.
The baseline plan retains its historical PLAN ONLY status. The new ignored
implementation tracker records the later authorization; history is not rewritten.

## Scientific Design

Reuse the 24 complete official-fold fits (3 Normal RHS VB, 21 independent AL
RHS VB) and candidate A's 24 partial internal fits. No fits are repeated.
The fixed regional specification is two layers of 256 units, price lag order
2880 quarter-hours, exogenous lag order 4 plus current load/solar/wind,
alpha 0.2, rho 0.55, input scale 0.025, fan-in 16, pure all-layer readout,
seed 2026092501, and tau0 0.0001499045764139044.
The 7 quantile levels are 0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90.

Official diagnostic: all 365 origins (120/123/122), H=96 quarter-hours,
S=500. Keep each fold's exact fitted parameters, inner and outer scalers,
receiver draw seeds, covariance-preserving sampler, and clipped-CDF pooling.
Only replace unknown future price lags by the true response prefix strictly
before the forecasted step. The existing R126 causal forecasts are reused.
The first step must agree with R126. Oracle scores cannot enter a selector.

Training-internal diagnostic: three partial-fitting splits, 12 calendar-chosen
origins per split at 00/06/12/18 hours, 144 origin-clock pairs. Controls:

1. Same stochastic Normal RHS recursion as R126.
2. Same path-specific Normal coefficient draws but zero innovations.
3. Normal coefficient-mean recursion with zero innovations.
4. True price-lag prefix (oracle, diagnostic only).

Each path keeps its Normal coefficient and variance draw fixed through the
horizon. All controls share the same 500 receiver coefficient draws. No AL,
Normal or quantile posterior prior is reconstructed or altered. Control 3 is
not the mean of stochastic features after nonlinear recurrence. It has one
recursive state path but still 500 receiver coefficient draws.

## Efficient Reuse And Alignment

Shifted windows are stitched from adjacent sealed daily arrays, rather than
reprocessing raw data. This justified implementation choice preserves exactly
the executed outer scaler, float32 rounding and internal standardization.
History at a shifted origin contains only observations before that origin.
All 96 responses remain inside that split's internal validation support. Each
origin initializes its own states from observed history; within-origin states
advance recursively. No state is carried between diagnostic origins.

Midnight causal/oracle outputs are reused from R125. States are replayed because
their moments were not previously saved; cached forecasts skip repeated CDF
inversion except the first-step identity check. No repeated model fitting.
Two independent S=500 streams on three predeclared split-3 midnight origins
assess Monte Carlo sensitivity. They are not ranked or seed-selected.

Internal quantities are in outer fold-1 standardized price units, not EUR/MWh.
Official quantities undo both scaler stages and are EUR/MWh. Positive outer
affine preprocessing cancels algebraically under target-only train-fitted
inner standardization, but original float32 quantization is retained. This
argument does not automatically apply to graph summaries. Existing partial-fit
formal convergence is inherited; this phase does not invent a new certificate
for unexported latent VB factors.

## Output And Interpretation

Store only forecasts and compact per-lead moments, not S x H x P state banks:
Normal-driver mean/SD, mean state displacement from oracle, state variance,
fractions near zero or saturation, and local one-standardized-unit current
exogenous sensitivity with prior states fixed. At five fixed leads report
the median raw-location variance identity

`Var(beta'z) = E_z[z' Sigma_beta z] + Var_z[mu_beta'z]`.

This is exact for the independent receiver posterior and the empirical state
distribution. It is not a decomposition of the pooled price CDF variance.
Local perturbation is a sensitivity diagnostic, not feature importance or
an operational forecast. Preserve calibration and width alongside AQL.

Automatic closeout writes complete official-fold and internal-control CSVs,
variance and Monte Carlo tables, a compact PDF, a sealed decision and terminal.
Existing R98 and both PriceFM references come from the hash-pinned R126
comparison. Its checkpoint-exposure and reconstruction limitations remain.
There is no automatic refit or promotion. Previously inspected official
outcomes cannot be renamed an untouched confirmatory test.

## Execution And Resource Gates

Entrypoint: `application/scripts/pricefm/450_run_pricefm_stage_r127_driver_diagnosis.py`.
Run the source-matched `pricefm_r127_release.py` on Muscat and Jerez first.
It inherits the R120-R126 scientific regressions and four pinned R 4.6.0 suites.
Pass the exact historical ignored R120 regression input to each release.
The new worktree needs the hash-pinned baseline plan in `local_trackers/`.
Do not put runtime artifacts or either ignored plan into Git.

The launch-prep command accepts `--receipt` and `--reference` paths. It checks
source identity, hashes, training provenance, completed parent fits and sealed
official predictions before writing immutable preparation/tasks.
The controller accepts `--workers 1..15`; one combined budget covers both
diagnostic stages. Select distinct physical cores whose busiest logical sibling
is below 35% in a fresh five-second sample. Each worker is pinned to one core;
all relevant BLAS/OpenMP thread limits are one before imports.
Maintain 200 GiB available RAM and 200 GiB free disk; cap new campaign outputs
at 1 GiB. These are admission gates, not claims of exclusive resource reservation.

The 82 scheduled tasks contain 15 first-origin smoke tasks. They are real
campaign tasks and therefore reused, not duplicated. The remaining 67 tasks
are released only after all 15 smoke tasks pass. Failed workers stop dispatch;
existing workers drain. Never terminate or modify another lane's jobs.
Successful tasks are hash-sealed and reused on resumption. A controller lock
and live-worker check prevent duplicate dispatch. Partial evidence is retained
and never silently overwritten. A full report requires every expected origin.

Example (paths abbreviated only in this document):

```bash
python -B application/scripts/pricefm/450_run_pricefm_stage_r127_driver_diagnosis.py prepare --receipt RELEASE/validation.json --reference REFERENCES/fold_metrics.csv
python -B application/scripts/pricefm/450_run_pricefm_stage_r127_driver_diagnosis.py controller --workers 15
```

Runtime roots remain under the existing ignored `application/data_local/pricefm/`:
`launch_prep/pricefm_stage_r127_driver_diagnosis_20261008/` and
`campaigns/pricefm_stage_r127_driver_diagnosis_20261008/`.
Return compact sealed outputs to Muscat without relocating the Jerez evidence.

## Checks And Remaining Decisions

Regression coverage includes exact causal/oracle agreement with parent code,
future-price poisoning, oracle-prefix isolation, current exogenous timing,
independent state banks, teacher forcing between origins, seed/chunk invariance,
shifted history and response alignment, split containment, affine scaling,
raw-location variance algebra, cached reuse and the single resource schedule.
Release tests also exercise the inherited prior/initializer separation and
public CRAN exdqlm 1.1.1 AL implementation. No MCMC or joint model runs here.

Noisy-oracle experiments, a new PriceFM internal-cutoff fit, new-region adapters
and corrective screening are explicitly deferred. They are not prerequisites
to the exact same-fit diagnosis. Decide their necessity from completed training-
internal error/calibration/sensitivity evidence. A large oracle gain does not
prove recursion can be repaired by increasing reservoir complexity alone.
