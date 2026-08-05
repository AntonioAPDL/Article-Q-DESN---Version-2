# PriceFM Stage-R36 Nested Horizon-Readout Qualification

## Decision

Stage-R34 completed 480 case-specific capacity/history experiments and produced no
PriceFM win, even under retrospective test-oracle selection. Stage-R35 showed that
the remaining problem is not adequately explained by a shared reservoir size,
lag-window, AL/exAL, or postfit-calibration choice. It also showed weak validation
transfer and repeated historical visibility of the existing test split.

Stage-R36 therefore does not broaden the R33/R34 grid. It implements one genuinely
new consumed mechanism: independent AL/RHS-NS readout fits for horizons 1-24,
25-48, 49-72, and 73-96. Each block has its own coefficients, scale state, and
regularized-horseshoe shrinkage state. This differs from the earlier adapter-level
horizon interactions, which remained columns in one shared fit.

## Bounded Target Set

The launch contains 11 region/fold cases from the Stage-R35 priority-0/1 queue:

- harm guards: HU fold 2 and NO_4 fold 1;
- mechanism-qualification targets: IT_CALA folds 2/3, IT_SARD fold 1, NO_3 folds
  2/3, NO_4 folds 2/3, NO_5 fold 3, and SE_1 fold 3.

Each case reuses exactly one reservoir specification: its Stage-R34
validation-selected anchor. Specifications remain case-specific. No test-oracle
row is used to choose depth, width, lag window, feature policy, shrinkage, seed, or
horizon weighting.

## Paired Mechanism Contract

Every experiment fits both arms on the same reservoir states and training rows:

1. `shared_static`: one AL/RHS-NS readout across all 96 horizons;
2. `separate_horizon_block`: four independent AL/RHS-NS readouts, one per
   24-horizon block.

Only AL is retained because Stage-R34 found AL versus exAL effectively flat in
17/20 cases. Normal baselines and exact-equivalence repetition are disabled for
this mechanism screen. The adapter's previous `horizon_block` interaction is set
to `none`, preventing reuse of the falsified shared-interaction rescue family.

The inherited case-specific horizon frequency weighting remains active. Integer
scale 4 represents all multipliers exactly. The maximum theoretical replication
factor is 6.5 for SE_1 fold 3 and is fail-closed below an explicit 8x ceiling.

## Nested Temporal Selection

The runner receives only `train` and `val`. It does not build, load, predict, rank,
or summarize the existing test split.

Within the outer training period, three expanding rolling folds use:

- initial training fraction: 0.55;
- validation fraction: 0.15;
- minimum training origins: 180;
- minimum validation origins: 60;
- response-time embargo: every training response precedes the first validation
  origin.

The future closeout must rank readout modes within each region/fold using median
inner-fold scaled AQL, with a worst-fold harm guard. The frozen inner winner is
then evaluated on the ordinary outer validation period. Cross-case pooling and a
shared winning specification are forbidden.

## Evidence Boundary

Stage-R36 is mechanism qualification, not article promotion. The existing test
split has been visible during nine earlier stages and remains quarantined. A
promising R36 result still requires a fresh confirmation design, full-quantile
evaluation, reproducibility/hash checks, and wins against both authoritative
QDESN and cached PriceFM. MCMC is confirmatory only after those VB gates pass.

Registry, manuscript, article, and MCMC mutation remain blocked.

## Implementation

- `application/scripts/pricefm/pricefm_horizon_readout.R` provides block fitting,
  prediction, nested-fold construction, embargo checks, and quantile diagnostics.
- `application/scripts/pricefm/08_run_desn_model_smoke.R` consumes the new readout
  and nested-validation configuration and writes nested metrics.
- `application/scripts/pricefm/09_summarize_desn_model_smoke.py` supports
  validation-only evaluation surfaces.
- `application/scripts/pricefm/pricefm_full_run.py` supports configured split
  readiness and forwards the nested-validation contract.
- `application/scripts/pricefm/12_prepare_desn_experiment_grid.py` forwards nested
  and readout settings to generated cell configs.
- `application/scripts/pricefm/161_prepare_pricefm_stage_r36_nested_horizon_readout_launch.py`
  verifies inputs and materializes the bounded launch.

The generated preparation lives at:

`application/data_local/pricefm/authoritative/pricefm_stage_r36_nested_horizon_readout_launch_prep_20260804`

The generated grid and run roots are:

- `application/data_local/pricefm/experiment_grids/pricefm_stage_r36_nested_horizon_readout_20260804`;
- `application/data_local/pricefm/runs/pricefm_stage_r36_nested_horizon_readout_20260804`.

All required historical train/validation windows, interpreters, package sources,
mechanism tokens, split contracts, and mutation blocks pass the materialized
launch-prep gates.
