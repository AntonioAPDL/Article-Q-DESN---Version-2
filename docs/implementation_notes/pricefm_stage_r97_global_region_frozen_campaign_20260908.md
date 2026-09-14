# PriceFM Stage-R97 Complete Region-Specific Campaign

## Scientific decision

Stage R97 replaces the earlier per-case dual-comparator interpretation with the
requested complete-surface estimand. The challenger is evaluated as one fixed
surface containing all 38 PriceFM regions and all three forecast folds. Its
primary score is the unweighted arithmetic mean of the 114 original-scale AQL
values.

The primary gate is:

```text
mean AQL(R97 over the exact 114 cases)
  < mean AQL(current authoritative R92 Q-DESN over the same 114 cases)
```

The frozen R92 mean is `6.823677420470439`. Cached PriceFM has mean
`7.038685346534470` on the same fold-aligned replay and remains a secondary
complete-surface benchmark. Individual region/fold wins and losses are
diagnostics only. They are not vetoes, and test results cannot be used to mix
old and new predictions case by case.

## Scope and reuse

R97 fits 37 regions and reuses the already completed R96 `SE_2` surface for its
three cases. The final denominator is therefore:

| Source | Regions | Cases |
|---|---:|---:|
| New R97 region-specific workflows | 37 | 111 |
| Frozen R96 `SE_2` workflow | 1 | 3 |
| Complete decision surface | 38 | 114 |

The R92 registry is hash-pinned at
`3922a06a965e8eac6320edbc2cb38464c007c51698814b419271690f9a4c9f87`.
The reused R96 comparison is hash-pinned at
`b93302cd85059b8dafac12dae59bc251d30105948a302a2d7f516be65805a985`.

## Region-specific workflow

The model-selection unit is one region. Each region receives its own selected
DESN geometry, information set, and RHS `tau0`; no common specification is
forced across the panel.

1. Re-evaluate up to three current fold-authority specifications as mandatory
   controls. Identical fold controls share one arm. The exact historical graph
   degree and explicit neighbors are preserved when available.
2. Complete a deterministic 240-arm normal scaled-Ridge screen on three inner
   temporal validation windows ending before the original Fold-1 validation
   interval. Rank by median inner-validation AQL, then worst-window AQL and
   complexity. Historical test metrics never enter this ranking.
3. Advance the best 30 geometries to normal RHS VB at `tau0` values `1e-4`,
   `1e-3`, and `1e-2`. Apply the pre-registered local refinement at `5e-5`,
   `5e-4`, and `2e-3` only when the coarse winner is on a boundary, near-tied,
   or numerically incomplete.
4. Freeze one DESN and `tau0` for the region. Fit normal RHS plus all seven AL
   and repaired exAL independent quantile atoms on folds 1, 2, and 3. Quantiles
   are `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`.
5. Select one entire AL or exAL family using Fold-1 validation only. If the
   Fold-1-selected exAL family is numerically ineligible on another fold, use
   the complete AL family for the region. Family mixing by fold or quantile is
   forbidden.
6. After all 37 regions are validation-frozen, open test once. Rebuild each
   validation/test design, require exact validation-prediction replay, and
   apply the frozen posterior-mean readouts without fitting or reselection.
7. Combine the 111 R97 scores with the three frozen R96 `SE_2` scores and apply
   the single 114-case mean-AQL gate.

Fold-1-only family selection is intentional: later folds contain dates after
the Fold-1 test interval and cannot be allowed to influence a challenger that
will also be evaluated on Fold 1.

## Bounded search

The Ridge bank covers final-layer DESNs with lags `48, 96, 168, 240`, depth
one through three, and these units:

```text
[48], [64], [96], [128], [160],
[48,48], [64,64], [80,80], [96,96], [120,120], [96,48], [120,64],
[40,40,40], [48,48,48], [64,64,64], [80,80,80], [96,64,48]
```

The dynamics bank uses alpha `0.25, 0.35, 0.40, 0.45, 0.50, 0.55`, rho
`0.82, 0.90, 0.95`, and input scale `0.15, 0.20, 0.25, 0.35, 0.50`.
Target-only, graph mean, graph mean/std, and degree-1 graph concatenation are
sampled at 40/30/20/10 proportions, adjusted only to reserve slots for any
mandatory historical control outside those four search policies. R32-style
depth at least four, width above 160, lag 300/500, concatenated-layer readouts,
and the negative horizon-weight/readout mechanisms remain excluded.

## Runtime and resources

The controller permits at most 20 workers. It takes two live utilization
snapshots, selects only CPUs below the configured threshold, pins one model
process to each CPU, and sets all numerical thread variables to one. It also
requires at least 250 GiB free disk and 64 GiB available memory at launch.

The minimum planned fit count is 38,295 model cells:

| Phase | Count |
|---|---:|
| Ridge inner-validation cells | 26,640 |
| Coarse normal-RHS cells | 9,990 |
| Three-fold normal/AL/exAL tasks | 1,665 |
| No-refit test scoring cases | 111 |

Conditional RHS refinement can add at most 333 cells. The controller schedules
the whole campaign automatically, but 20 cores do not make completion within a
single night credible. Runtime artifacts are resumable and remain under the
ignored historical PriceFM artifact repository.

Each completed Ridge/RHS screening experiment is compacted immediately. Only
its validation `metric_summary.csv`, `model_method_summary.csv`, and a hashed
compaction terminal remain; adapter matrices, prediction files, and binary
models are deleted. This avoids scaling the approximately 35 GiB retained by
the original single-region screen to the full panel. Frozen quantile atoms and
their replay evidence are retained through global closeout.

## Implementation

- `291_prepare_pricefm_stage_r93_region_frozen_ladder.py`: generic controls,
  per-campaign processed root, and exact information-set preservation.
- `292_advance_pricefm_stage_r93_ridge_to_rhs.py`: accepts deduplicated fold
  controls while requiring all folds to remain represented.
- `294_advance_pricefm_stage_r93_validation_ladder.py`: region-specific
  refinement identities.
- `316_prepare_pricefm_stage_r97_global_region_campaign.py`: freezes the
  114-case authority, controls, region plan, and aggregate decision.
- `317_prepare_pricefm_stage_r97_region_quantile_surface.py`: writes each
  region's concrete 45-task validation DAG.
- `318_closeout_pricefm_stage_r97_region_quantile_surface.py`: freezes one
  whole likelihood family from validation.
- `319_orchestrate_pricefm_stage_r97_global_campaign.py`: resource-gated,
  restartable full campaign controller with streaming compaction.
- `320_score_pricefm_stage_r97_frozen_case.py`: no-refit validation replay and
  test scorer.
- `321_prepare_pricefm_stage_r97_global_scoring.py`: opens the complete frozen
  111-case scoring surface only after all regions close validation.
- `322_closeout_pricefm_stage_r97_global_surface.py`: applies the single
  114-case mean-AQL gate.
- `application/tests/test_pricefm_stage_r97_global_region_campaign.py`:
  focused contracts and end-to-end synthetic complete-surface checks.

## Failure and resume rules

The global controller owns a filesystem lock and writes atomic state. A task is
accepted as complete only from a valid terminal and source hashes. Screening
compaction markers permit safe skip-on-resume. Any region failure is recorded
as `failed_closed`; global test scoring cannot start until all 37 new regions
have valid frozen surfaces. Existing partial outputs are never silently
deleted or overwritten.

## Explicitly blocked

- no per-case test-driven replacement of current results;
- no registry mutation;
- no article or manuscript mutation;
- no joint Q-DESN fit;
- no MCMC fit;
- no result promotion before the exact complete-surface closeout.
