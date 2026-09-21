# PriceFM Stage-R109 saved-driver quality closeout

## Purpose

Stage-R109 determines whether existing frozen Normal Ridge or Normal RHS paths
are good enough to justify another full downstream recursive Q-DESN replay. It
does not fit models, rerun reservoir states, access test data, write launch
YAML, or mutate the registry or article.

The implementation follows the ignored execution plan at
`local_trackers/pricefm_stage_r109_saved_driver_execution_plan_20260921.md`.

## Inputs

R109 consumes the complete R102B R98-control 500-path validation surfaces for
Normal Ridge and Normal RHS, the R108 validation truths and PriceFM driver
cache, the R103 selected-family downstream results, and the R104/R108
mechanism diagnostics. Every consumed source is hash-verified.

The diagnostic panel is fixed to AT, BE, BG, CZ, DE_LU, DK_1, DK_2, EE, and ES
over all three folds.

## Statistical contract

Probabilistic driver AQL and coverage use empirical quantiles from all 500
saved Normal paths. The saved-path mean is evaluated separately with MAE,
RMSE, and bias. It is not duplicated into pseudo-quantiles. Cached PriceFM uses
its seven released validation quantiles and median trajectory.

The candidate gate requires complete finite evidence, at least 30 percent AQL
and late-horizon improvement over RHS, proximity to the PriceFM validation
driver, no material coverage harm, and no region with more than 10 percent AQL
harm. These are continuation gates only.

## Files

- `application/scripts/pricefm/365_closeout_pricefm_stage_r109_saved_driver_quality.py`
- `application/tests/test_pricefm_stage_r109_saved_driver_quality.py`
- `docs/implementation_notes/pricefm_stage_r109_saved_driver_quality_20260921.md`

Runtime outputs are ignored under
`application/data_local/pricefm/authoritative/pricefm_stage_r109_saved_driver_quality_20260921`.

## Interpretation boundary

If neither saved Normal driver passes, the scientifically efficient next step
is the bounded R110 direct-driver redesign on BG, EE, and BE. A failed R109 gate
does not authorize a full downstream replay, DESN/tau0 rescreening, test access,
joint models, MCMC, registry mutation, or article changes.

## Validation and result

The adjacent R108/R109 focused suite passed with `14 passed`. The closeout then
completed all 81 expected method-region-fold rows (three driver methods, nine
regions, and three folds), recorded 1,676 unique source-manifest rows, and
published nine hash-verified outputs. It used one sequential process, opened no
test artifact, and started no fit or downstream replay.

| Validation driver | AQL | 10--90 coverage | Mean width | Central-path MAE |
|---|---:|---:|---:|---:|
| Cached PriceFM quantiles | 8.13959 | 0.72107 | 51.62248 | 19.92774 |
| Saved Normal Ridge paths | 21.09155 | 0.63958 | 105.05439 | 50.11718 |
| Saved Normal RHS paths | 27.18991 | 0.61962 | 132.81579 | 63.95060 |

Ridge improves pooled AQL by 22.43 percent and horizons 73--96 by 25.68
percent relative to RHS. Both improvements are real but below the preregistered
30 percent continuation thresholds. Ridge remains 159.12 percent above the
cached PriceFM driver AQL. Its largest gain is EE (50.25 percent), followed by
CZ (23.57 percent) and DK_1 (18.12 percent); it is effectively unchanged in BG
and only marginally different in DE_LU, DK_2, ES, and BE. No region exceeds the
10 percent harm guard and coverage distance improves slightly, so the negative
decision is driven by insufficient accuracy rather than instability or broad
harm.

The horizon profile identifies accumulation as the central failure. Ridge AQL
rises from 3.95 at horizons 1--6 to 32.07 at horizons 73--96; RHS rises from
4.01 to 43.16. Cached PriceFM is 2.35 and 8.77 over the same blocks. Existing
downstream evidence is consistent: complete RHS all-active replay has AQL
30.18, while the focused R104 Ridge substitutions provide only modest gains in
BE and essentially none in BG.

Neither saved Normal driver passes all gates. The frozen decision is therefore
`full_downstream_replay_authorized = false`, with next stage
`bounded_R110_standalone_driver_redesign`.

## Next stage

R110 should remain focused on BG, EE, and BE. It should compare direct
96-horizon probabilistic Normal Ridge and Normal RHS drivers using pseudo-origins
strictly inside training, preserve 500 coherent trajectories, and assess the
original validation window only after the driver policy is frozen. BG tests the
target-only failure, EE tests the largest Ridge-versus-RHS gain, and BE is the
stable graph-enabled control. Q-DESN geometry, tau0, AL/exAL family, test data,
registry, and article remain frozen until this driver gate passes.
