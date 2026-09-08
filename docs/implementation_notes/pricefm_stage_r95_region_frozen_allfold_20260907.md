# PriceFM Stage-R95 Region-Frozen All-Fold Workflow

## Purpose

Stage-R95 completes the missing `SE_2` folds after Stage-R94 selected one
seven-quantile exAL family on reserved Fold-1 validation. It is a forward
replication stage, not another calibration search.

The stage keeps the complete R94 contract fixed:

- feature policy: `graph_summary_mean`, degree 1;
- neighbors: `NO_3`, `NO_4`, `SE_1`, `SE_3`;
- lag window: 240 quarter-hours;
- depth and units: 2, `[120, 64]`;
- alpha, rho, input scale: `0.50`, `0.95`, `0.15`;
- readout: `final_layer`;
- RHS prior `tau0`: `0.01`;
- quantiles: `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`;
- likelihood family: validation-selected exAL, subject only to the
  pre-registered whole-region AL numerical fallback.

## Implemented files

- `application/scripts/pricefm/307_prepare_pricefm_stage_r95_region_frozen_allfold.py`
- `application/scripts/pricefm/308_run_pricefm_stage_r95_quantile_atom.R`
- `application/scripts/pricefm/309_launch_pricefm_stage_r95_allfold.py`
- `application/scripts/pricefm/310_closeout_pricefm_stage_r95_allfold_validation.py`
- `application/tests/test_pricefm_stage_r95_region_frozen_allfold.py`

The ignored local decision record is
`local_trackers/pricefm_stage_r95_region_frozen_allfold_master_plan_20260907.md`.

## Fit surface and dependencies

R95 reuses all seven Fold-1 atoms. It schedules exactly 30 new fits for folds 2
and 3:

| Fit | Count | Role |
|---|---:|---|
| normal RHS | 2 | one same-fold initializer per missing fold |
| AL | 14 | complete fallback surface and coherent warm parents |
| exAL | 14 | validation-selected candidate family |

Within each fold, normal RHS initializes AL at tau 0.50. The left AL branch is
`0.50 -> 0.45 -> 0.25 -> 0.10`; the right branch is
`0.50 -> 0.55 -> 0.75 -> 0.90`. Every exAL atom starts from its same-tau AL
q(beta), including the covariance diagonal, and uses the Stage-R94 coherent
RHS/latent-first initialization.

## Data and leakage controls

The preparer writes a dedicated data configuration with only train and
validation intervals for folds 2 and 3. It never writes a test interval. The
launcher creates windows only for `SE_2` and the four frozen graph neighbors.
Every worker rejects test adapter files and all test, registry, article, joint,
and MCMC authorization flags are literal `false`.

The Fold-2 and Fold-3 validation scores are diagnostics. They cannot change
the DESN, information set, `tau0`, or family selected by Stage-R94.

## Runtime and numerical contract

Normal RHS uses the validated R93 exact-name runtime. AL and exAL use the
PriceFM-local runtime `exdqlm 1.1.1.9005`, derived from the exact CRAN 1.1.1
surface with the Stage-R94 scale-aware SPD, large-n GIG, structured sigma/gamma,
and coherent AL initialization repairs.

AL requires finite coefficients, positive covariance diagonal, positive finite
scale, and finite validation predictions. exAL additionally requires the
complete Stage-R94 trajectory and endpoint gates. Formal convergence remains a
reported field, distinct from numerical eligibility.

If every exAL atom across all three folds is eligible, exAL remains the frozen
region family. If any new exAL atom is ineligible and every AL atom is eligible,
the entire region falls back to AL. Mixing families by fold or quantile is not
allowed.

## Resource and resume behavior

The launcher accepts `--workers` and `--cpu-list`, with a hard ceiling of 20.
Each subprocess is pinned to one logical CPU and all numerical thread variables
are set to one. The launcher takes two CPU utilization snapshots, verifies free
memory and disk, and requires a clean task branch equal to its recorded
upstream.

Task completion is accepted only when the terminal identity and every artifact
hash reproduce. Invalid partial outputs are moved to a stage-owned quarantine
before one permitted retry. A filesystem lock prevents duplicate launchers.
The scheduler writes atomic liveness state throughout the run.

## Commands

Materialize after code validation and after the task branch is committed and
pushed:

```bash
PRICEFM_PY=/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python
$PRICEFM_PY application/scripts/pricefm/307_prepare_pricefm_stage_r95_region_frozen_allfold.py \
  --workers 20
```

Read-only launch preflight:

```bash
$PRICEFM_PY application/scripts/pricefm/309_launch_pricefm_stage_r95_allfold.py \
  --code-root "$PWD" \
  --workers 20 \
  --cpu-list 20-39 \
  --preflight-only
```

Explicit background launch, only after a fresh CPU ownership check:

```bash
tmux new-session -d -s pricefm_stage_r95_20260907 \
  "$PRICEFM_PY application/scripts/pricefm/309_launch_pricefm_stage_r95_allfold.py \
    --code-root '$PWD' \
    --workers 20 \
    --cpu-list 20-39 \
    --approval-token RUN_PRICEFM_R95_ALLFOLD_VALIDATION"
```

The launcher performs preprocessing, dependency-aware fitting, validation
closeout, and then stops automatically.

## Generated locations

- grid and task JSON:
  `application/data_local/pricefm/experiment_grids/pricefm_stage_r95_region_frozen_allfold_validation_20260907`
- processed train/validation data:
  `application/data_local/pricefm/processed_stage_r95_region_frozen_allfold_20260907`
- run output:
  `application/data_local/pricefm/runs/pricefm_stage_r95_region_frozen_allfold_validation_20260907`
- preparation evidence:
  `application/data_local/pricefm/authoritative/pricefm_stage_r95_allfold_launch_prep_20260907`
- validation closeout:
  `application/data_local/pricefm/authoritative/pricefm_stage_r95_allfold_validation_closeout_20260907`

These paths are runtime artifacts under the historical PriceFM artifact root
and remain excluded from Git.

## Blocked next actions

Stage-R95 does not score test data or mutate the decision registry or article.
After a successful closeout, the next operation requires separate authorization
for a scoring-only test replay. That later stage must reproduce validation
predictions first and compare the frozen candidate against both authoritative
Q-DESN and cached PriceFM without refitting.
