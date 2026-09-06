# PriceFM Stage-R93 Region-Frozen Ladder Preparation

## Scope

Stage-R93 is a bounded first application of the region-frozen model-selection
algorithm to `SE_2`, the worst current PriceFM region by mean R92 Q-DESN minus
PriceFM AQL. This commit prepares the first Ridge phase and the data-dependent
continuation contract. It does not launch or fit models.

## Scientific contract

The model-selection unit is a region, not a region/fold cell. The three current
`SE_2` fold-specific winners are mandatory geometry controls in the normal
scaled-Ridge bank:

| Source fold | D | Units | m | alpha | rho | input scale |
|---:|---:|---|---:|---:|---:|---:|
| 1 | 2 | `[120,120]` | 96 | 0.40 | 0.90 | 0.25 |
| 2 | 2 | `[80,80]` | 96 | 0.50 | 0.90 | 0.20 |
| 3 | 3 | `[40,40,40]` | 96 | 0.45 | 0.90 | 0.35 |

These controls are re-evaluated under the same `SE_2` Fold-1 observational
contract as every new candidate. Their historical test AQL values are audit
provenance only and cannot affect ranking.

The Ridge bank contains 240 deterministic candidates with a 40/30/20/10 split
over target-only, graph-mean, graph-mean/std, and degree-1 graph-concatenated
information sets. It covers bounded D=1--3 geometries, final-layer widths up to
160, lag windows 48/96/168/240, and the historically credible dynamics range.
R32-style D>=4, width>160, lag 300/500, concatenated readouts, and the failed
horizon-weighted/horizon-block mechanisms are excluded.

## Temporal firewall

The first three folds are internal temporal splits wholly inside the original
Fold-1 training interval:

1. train to 2023-09-01, validate to 2024-01-01;
2. train to 2024-01-01, validate to 2024-05-01;
3. train to 2024-05-01, validate to 2024-09-01.

The original Fold-1 validation interval begins at 2024-09-01 and is reserved
for confirmation. Outer test/forecast windows are absent from the Ridge config.

## Ladder

1. Rank Ridge candidates by median inner-validation AQL, then worst-window AQL,
   readout complexity, and deterministic candidate ID. Advance exactly 30.
2. Refit the 30 under normal RHS_NS on the same windows, with a coarse tau0 grid
   and a conditional local refinement. Rank the RHS mean-field predictive
   distribution analytically, without Monte Carlo scoring noise, and select one
   geometry/tau0.
3. Confirm the one normal RHS winner on original Fold-1 validation and freeze it.
4. Fit all seven independent AL and repaired structured-exAL VB quantiles using
   the same frozen geometry and tau0. Select the likelihood family on validation.
5. Only then score the frozen family on real folds 1--3 and compare with R92
   Q-DESN and cached PriceFM as audit evidence.
6. A joint VB fit remains downstream and conditional on a complete finite
   independent surface. It is not part of this prepared Ridge launch.

Normal Ridge/RHS are repository-owned numerical stages because exact CRAN
`exdqlm 1.1.1` does not export the historical normal helpers. The later AL/exAL
stage must use the exact CRAN public API and the hash-pinned R82 structured exAL
initialization repair. Normal fits preserve coefficient means and covariance
diagonals as lightweight CSV artifacts so the selected RHS fit can initialize
the quantile ladder without retaining binary model files.

An isolated numerical audit found that the source normal helper's use of
`prior$b` allowed R partial-name matching to interpret `beta_ridge_tau2` as the
prior mean. The R93 runtime materializer copies only package source, replaces
that access with exact list-name lookup, records source and patched hashes, and
requires finite converged Ridge/RHS probes. It does not modify the shared exdqlm
worktree.

## Implementation

- `application/scripts/pricefm/291_prepare_pricefm_stage_r93_region_frozen_ladder.py`
- `application/scripts/pricefm/292_advance_pricefm_stage_r93_ridge_to_rhs.py`
- `application/scripts/pricefm/293_materialize_pricefm_stage_r93_normal_runtime.py`
- `application/tests/test_pricefm_stage_r93_region_frozen_ladder.py`
- `application/tests/test_pricefm_stage_r93_ridge_to_rhs.py`
- `application/tests/test_pricefm_stage_r93_normal_runtime.py`
- stage-selective switches in `08_run_desn_model_smoke.R`
- R93 metadata propagation in `12_prepare_desn_experiment_grid.py`

The first script materializes and validates the Ridge grid. After all Ridge
results exist, the second script refuses partial/nonconverged surfaces, rejects
any test-row contamination, applies the deterministic top-30 selector, and
materializes the 30-by-3 coarse normal-RHS grid. Both grids carry false launch
authorization. Registry, article, MCMC, joint fitting, and launch remain blocked.
