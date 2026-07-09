# Joint-QVP Synthetic DGP Forecast Phase 4h Tau0 Refinement: Audit, Diagnosis, And Plan

Date: 2026-07-04

## Purpose

This note audits the Phase 4g prior/design screen and turns the tentative next step into a concrete, reproducible Phase 4h plan. The goal is to verify whether local refinement of the RHS global shrinkage parameter `tau0` is truly the optimal move before any article-candidate rerun or change in default validation controls.

The short conclusion is:

```text
Proceed with a targeted Phase 4h local tau0 refinement screen before changing article-candidate defaults.
```

This is the best next step because Phase 4g produced a coherent monotone signal for `tau0`, while `zeta2`, `alpha_prior_sd`, and extra RHS inner iterations were weaker or non-dominant. The remaining uncertainty is local: the best screened value, `tau0 = 0.10`, improved raw crossings and truth error but did not clear the deliberately strict 50 percent promotion threshold and had a higher VB max-iteration rate. Phase 4h should determine whether a nearby `tau0` value gives a better crossing/convergence tradeoff.

## Source Artifacts Audited

Primary Phase 4g artifact:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4g_prior_design_screen
```

Frozen targeted registry:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv
```

Registry hash recorded in Phase 4g:

```text
6ac0826b1d3259f56bbd127fe5f95d8fecd0fd00a6096284f0f62590fc23bcce
```

Audit checks:

- Root Phase 4g manifest: verified.
- Nested Phase 3 manifests: 10 of 10 verified.
- Targeted rows: 7 frozen replicated scenario rows.
- Screen rows: 10 prior/design candidates.
- Contract forecast crossings: zero for every screen.
- Generated forecast artifacts remain under ignored `application/cache/`; reproducible summaries are documented here and in Phase 4g CSV outputs.

## Phase 4g Evidence Summary

| screen | raw crossing pairs | raw crossing reduction | max monotone adjustment | mean truth MAE | VB max-iteration rate | runtime sec |
|---|---:|---:|---:|---:|---:|---:|
| baseline_vb480 | 22 | 0.000 | 0.07304 | 0.140354 | 0.1250 | 523.080 |
| tau0_0p5 | 17 | 0.227 | 0.07045 | 0.139705 | 0.0667 | 468.469 |
| tau0_0p25 | 15 | 0.318 | 0.06595 | 0.138351 | 0.1250 | 496.695 |
| tau0_0p1 | 13 | 0.409 | 0.06153 | 0.132387 | 0.1765 | 538.295 |
| zeta2_10 | 18 | 0.182 | 0.06904 | 0.139687 | 0.1250 | 512.998 |
| zeta2_4 | 18 | 0.182 | 0.06904 | 0.139687 | 0.1250 | 513.536 |
| tau0_0p5_zeta2_10 | 15 | 0.318 | 0.06668 | 0.139006 | 0.1250 | 498.414 |
| tau0_0p25_zeta2_10 | 15 | 0.318 | 0.06247 | 0.137646 | 0.1765 | 544.816 |
| alpha_sd_0p5 | 21 | 0.045 | 0.07888 | 0.140113 | 0.0667 | 414.499 |
| rhs_inner_8 | 22 | 0.000 | 0.07304 | 0.140354 | 0.1250 | 523.476 |

Key interpretation:

- `tau0` is the dominant lever.
- Smaller `tau0` monotonically reduced raw crossings from 22 to 13.
- Smaller `tau0` also monotonically improved truth MAE over the tested values.
- `tau0_0p1` is the best Phase 4g candidate by crossing count and truth error.
- `tau0_0p1` did not clear the strict 50 percent promotion threshold; it achieved about 41 percent raw crossing reduction.
- `tau0_0p1` increased VB max-iteration rate from 0.125 to 0.1765, which is still below a 0.20 local-review ceiling but is worse than `tau0_0p25` and `tau0_0p5`.

## Scenario-Level Diagnosis

Raw crossing counts by important candidates:

| base scenario | baseline | tau0_0p5 | tau0_0p25 | tau0_0p1 |
|---|---:|---:|---:|---:|
| asymmetric_laplace_tail | 0 | 0 | 0 | 0 |
| gaussian_mixture_bridge | 6 | 5 | 3 | 2 |
| heteroskedastic_seasonal | 1 | 0 | 0 | 0 |
| laplace_bridge | 2 | 1 | 1 | 1 |
| persistent_heavy_tail | 8 | 6 | 6 | 5 |
| regime_shift | 2 | 2 | 2 | 2 |
| student_t_location_scale | 3 | 3 | 3 | 3 |

Interpretation:

- `tau0` helps the most for `gaussian_mixture_bridge`, `heteroskedastic_seasonal`, and `persistent_heavy_tail`.
- `regime_shift` and `student_t_location_scale` crossings are insensitive to the Phase 4g controls; these may need scenario-specific design or origin-level analysis later.
- `asymmetric_laplace_tail` has zero raw crossings in this targeted Phase 4g screen, so it should not drive Phase 4h decisions.
- `persistent_heavy_tail` remains the largest contributor after `tau0_0p1`, with 5 of 13 crossings.

This supports a local `tau0` refinement rather than a broad multi-control expansion: the improvement pattern is coherent, but some residual crossings likely reflect scenario-specific behavior.

## Tau-Pair Diagnosis

Raw crossing origins by affected adjacent tau pair:

| screen | 0.05-0.10 | 0.75-0.90 | 0.90-0.95 |
|---|---:|---:|---:|
| baseline_vb480 | 4 | 0 | 18 |
| tau0_0p5 | 3 | 0 | 14 |
| tau0_0p25 | 3 | 0 | 12 |
| tau0_0p1 | 2 | 1 | 10 |
| zeta2_10 | 4 | 0 | 14 |
| tau0_0p25_zeta2_10 | 3 | 0 | 12 |
| alpha_sd_0p5 | 3 | 0 | 18 |

Interpretation:

- The dominant remaining failure mode is the upper extreme-tail pair `0.90-0.95`.
- `tau0_0p1` reduces upper-tail crossing origins from 18 to 10.
- `tau0_0p1` introduces one `0.75-0.90` crossing, so Phase 4h should watch for crossing migration as shrinkage becomes more aggressive.
- Lower-tail crossings are secondary and also improve under smaller `tau0`.

This argues for local refinement around `tau0 = 0.10`, not simply pushing `tau0` as small as possible.

## Per-Tau Forecast Quality Diagnosis

Selected mean truth MAE by tau:

| screen | tau=0.05 | tau=0.10 | tau=0.25 | tau=0.50 | tau=0.75 | tau=0.90 | tau=0.95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| baseline_vb480 | 0.14825 | 0.14007 | 0.10770 | 0.09697 | 0.10767 | 0.15509 | 0.22673 |
| tau0_0p25 | 0.14553 | 0.13743 | 0.10604 | 0.09568 | 0.10699 | 0.15382 | 0.22296 |
| tau0_0p1 | 0.13053 | 0.13031 | 0.10377 | 0.09248 | 0.10526 | 0.14002 | 0.22434 |
| tau0_0p25_zeta2_10 | 0.14472 | 0.13649 | 0.10573 | 0.09558 | 0.10678 | 0.15323 | 0.22100 |

Interpretation:

- `tau0_0p1` improves most taus substantially.
- The `0.95` quantile is not best under `tau0_0p1`; `tau0_0p25_zeta2_10` is better at `0.95`.
- Because the residual raw crossings are concentrated at `0.90-0.95`, Phase 4h should not rank candidates only by global MAE. It must include upper-tail-specific crossing and truth-error diagnostics.

## Why Phase 4h Is The Optimal Next Step

### Alternative 1: Run full calibration/article-candidate now

Not optimal. We have evidence that the default baseline leaves avoidable raw crossings. A full calibration rerun with the old default would be expensive and would knowingly carry a suboptimal raw-crossing profile. A full run with `tau0_0p1` would be premature because the local optimum and convergence tradeoff are not yet established.

### Alternative 2: Keep raw/contract policy and stop tuning

Not optimal. The raw/contract policy is correct and should remain, but Phase 4g shows raw crossings can be reduced without harming contract validity or truth metrics. Stopping now would leave model-side improvement on the table.

### Alternative 3: Screen broad combinations of `tau0`, `zeta2`, `alpha_prior_sd`, `rhs_vb_inner`

Not optimal as the immediate next step. Phase 4g already tested representative broad controls. `zeta2` helped modestly but did not dominate; `alpha_prior_sd` mainly improved runtime/convergence; `rhs_inner_8` changed almost nothing. A broader grid would spend compute on weak levers before resolving the clear `tau0` signal.

### Alternative 4: Implement anchor-vs-innovation shrinkage now

Promising but not first. Separate anchor and adjacent-innovation shrinkage may be the right structural improvement if local `tau0` refinement fails. However, it changes the model parameterization and implementation surface. Phase 4h is a lower-risk local refinement using already wired controls.

### Alternative 5: Improve DESN feature design now

Important later, not first. Scenario-level residuals suggest some crossings are scenario-specific, especially `persistent_heavy_tail`, `regime_shift`, and `student_t_location_scale`. But the monotone `tau0` trend should be exhausted first because it is simpler, already implemented, and globally beneficial.

## Phase 4h Objective

Run a local tau0 refinement screen over the same frozen targeted rows to identify the best tradeoff among:

- raw crossing count;
- raw crossing magnitude;
- upper-tail crossing count for `0.90-0.95`;
- monotone adjustment frequency and size;
- truth MAE/RMSE overall and by tau;
- pinball/WIS/CRPS summaries;
- empirical hit-rate errors;
- VB max-iteration rate;
- runtime.

This is still a targeted screen, not final article evidence.

## Recommended Phase 4h Candidate Grid

Primary local grid:

| screen id | tau0 | zeta2 | alpha_prior_sd | rhs_vb_inner | rationale |
|---|---:|---:|---:|---:|---|
| tau0_0p25_reference | 0.25 | Inf | 1 | 5 | Stable reference with 15 raw crossings and baseline VB max-iteration rate. |
| tau0_0p20 | 0.20 | Inf | 1 | 5 | First local point below 0.25. |
| tau0_0p15 | 0.15 | Inf | 1 | 5 | Midpoint toward the Phase 4g best. |
| tau0_0p10_reference | 0.10 | Inf | 1 | 5 | Current best crossing/truth candidate. |
| tau0_0p075 | 0.075 | Inf | 1 | 5 | Tests whether the trend continues below 0.10. |
| tau0_0p05 | 0.05 | Inf | 1 | 5 | Aggressive shrinkage boundary; watch crossing migration and convergence. |

Optional small second block only if primary results are ambiguous:

| screen id | tau0 | zeta2 | alpha_prior_sd | rhs_vb_inner | rationale |
|---|---:|---:|---:|---:|---|
| tau0_0p10_alpha_sd_0p5 | 0.10 | Inf | 0.5 | 5 | Tests whether alpha shrinkage can improve convergence/runtime without losing tau0 benefits. |
| tau0_0p15_alpha_sd_0p5 | 0.15 | Inf | 0.5 | 5 | Same, around a likely compromise value. |
| tau0_0p10_zeta2_10 | 0.10 | 10 | 1 | 5 | Tests upper-tail benefit from adding finite coupling at the current best tau0. |

Do not include broad `rhs_inner` or zeta2-only candidates in Phase 4h unless the primary grid is inconclusive.

## Recommended Phase 4h Compute Controls

Use the same compute controls as Phase 4g targeted:

```text
vb_max_iter = 480
adaptive_vb_max_iter_grid = 480,720
refit_stride = 20
forecast_origin_stride = 10
max_origins_per_scenario = 40
vb_tol = 1e-4
kappa = 1
a_sigma = 2
b_sigma = 1
alpha_prior_mean = empirical_quantile
```

Reason:

- Changing compute controls would confound the local tau0 comparison.
- The Phase 4g runtime is manageable for 6 primary candidates.
- The targeted registry has only 7 rows and 280 forecast origins per screen.

## Proposed Implementation

Add a Phase 4h runner rather than modifying Phase 4g outputs in place:

```text
application/scripts/87_run_joint_qvp_synthetic_dgp_phase4h_tau0_refinement.R
```

Preferred helper design:

- Reuse `app_joint_qvp_run_synthetic_dgp_phase4g_prior_design_screen()` where possible.
- Add a small extension allowing a custom `screen_grid` data frame, or add a Phase 4h wrapper that constructs the local grid and calls the same Phase 3 runner internally.
- Preserve the exact targeted registry path and seed rows.
- Write a dedicated Phase 4h artifact directory:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4h_tau0_refinement
```

Required root artifacts:

- `targeted_registry.csv`
- `tau0_refinement_grid.csv`
- `tau0_refinement_run_config.csv`
- `tau0_refinement_metric_summary.csv`
- `tau0_refinement_candidate_ranking.csv`
- `tau0_refinement_crossing_by_scenario.csv`
- `tau0_refinement_crossing_by_tau_pair.csv`
- `tau0_refinement_truth_by_tau.csv`
- `tau0_refinement_vb_runtime_summary.csv`
- `tau0_refinement_recommendation.csv`
- `screen_run_manifest.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

Nested Phase 3 outputs should be written under:

```text
screen_runs/<screen_id>/
```

## Phase 4h Gates

Hard fail:

- missing root or nested manifests;
- hash verification failure;
- train/test leakage;
- nonfinite forecasts or scores;
- contract forecast crossings.

Review:

- raw crossings remain above baseline by any amount;
- upper-tail crossing migration appears, especially new `0.75-0.90` crossings;
- VB max-iteration rate exceeds 0.20;
- runtime exceeds 1.25 times baseline;
- truth MAE worsens globally or at either extreme tail.

Candidate for calibration pilot:

- contract crossings are zero;
- raw crossing count is at least 40 percent below baseline, or raw crossing count is below 13;
- `0.90-0.95` crossing origins are reduced relative to `tau0_0p1`;
- global truth MAE is no worse than `tau0_0p1` by more than 1 percent, or materially improves the `0.95` quantile while keeping global MAE close;
- VB max-iteration rate is at or below 0.20;
- runtime is at or below 1.25 times baseline;
- no new broad crossing migration to central tau pairs.

This gate is intentionally less rigid than Phase 4g's 50 percent promotion rule because Phase 4h is a local refinement screen, not a broad discovery screen.

## Expected Decision Outcomes

### Outcome A: `tau0` around 0.10 remains best

Recommended action:

Run a calibration pilot with `tau0 = 0.10` before updating article-candidate defaults.

### Outcome B: `tau0` around 0.15 or 0.20 gives nearly the same crossings with better convergence

Recommended action:

Prefer the more stable compromise candidate for calibration pilot.

### Outcome C: `tau0 < 0.10` reduces crossings further without convergence/runtime cost

Recommended action:

Promote the smaller `tau0` candidate to calibration pilot, but inspect tau-pair migration carefully before article-candidate use.

### Outcome D: all local candidates plateau at 13-15 crossings

Recommended action:

Stop local tau0 tuning. Move to Phase 4i structural shrinkage:

- separate anchor and adjacent-innovation shrinkage;
- targeted heavy-tail/regime-shift feature norm audit;
- optional scenario-specific design diagnostics.

## Recommended Phase 4h Command After Implementation

```bash
Rscript application/scripts/87_run_joint_qvp_synthetic_dgp_phase4h_tau0_refinement.R \
  --targeted-registry application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4h_tau0_refinement \
  --tau0-grid 0.25,0.20,0.15,0.10,0.075,0.05 \
  --vb-max-iter 480 \
  --adaptive-vb-max-iter-grid 480,720 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

## Recommended Tests

Add focused tests for:

- local tau0 grid construction and stable screen ids;
- exact targeted registry seed preservation;
- Phase 4h smoke run over 1-2 scenarios and 2-3 tau0 values;
- nested Phase 3 run configs recording the requested `tau0` values;
- finite metrics and zero contract crossings in smoke;
- root and nested artifact manifest completeness;
- scenario/tau-pair diagnostic table schemas;
- recommendation table schema.

Do not run the full application test suite as the default Phase 4h verification; focused tests are sufficient and faster.

## Final Recommendation

Phase 4h local tau0 refinement is the optimal next step. It is narrow, evidence-driven, reproducible, and uses already implemented controls. It resolves the remaining local uncertainty around the promising `tau0_0p1` result before we spend compute on a calibration pilot or make article-candidate default changes.

The working hypothesis for Phase 4h is:

```text
The best article-candidate RHS global shrinkage value is near tau0 = 0.10, but a nearby value may improve the raw-crossing/convergence tradeoff.
```

If Phase 4h confirms this, the next stage should be a calibration-pilot Phase 4 run with the selected `tau0`, followed by a Phase 4b-style readiness audit and then an article-candidate run only if the calibration pilot passes implementation gates and has acceptable review-level statistical behavior.

## Comprehensive Audit Addendum

This addendum strengthens the decision audit behind the Phase 4h recommendation. It was prepared after re-reading the Phase 4g artifacts, the Phase 4c crossing audit, the existing Phase 3/4g runners, and the current command-line plumbing.

### Artifact And Reproducibility Audit

Audited artifact roots:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4g_prior_design_screen
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit
```

Observed reproducibility checks:

| artifact | rows | result |
|---|---:|---|
| Phase 4g root artifact manifest | 12 | present with SHA-256 hash columns |
| Phase 4g nested Phase 3 manifests | 10 | all reported verified |
| Phase 4c crossing audit manifest | 8 | present with SHA-256 hash columns |
| frozen targeted registry | 7 | present and seed-preserving |
| Phase 4g screen rows | 10 | present |
| Phase 4g forecast origins per screen | 280 | present |

The critical reproducibility constraint is to use the frozen targeted registry:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv
```

Phase 4h should not regenerate the calibration rows from base scenario ids. Regeneration can accidentally change replicate indexing or seed roles. The frozen registry records the exact scenario ids, base scenario ids, replicate ids, seeds, and validation tier.

### Mechanism Diagnosis

The working mechanism remains:

```text
raw forecast crossings are driven by noisy quantile-specific RHS coefficient variation, mostly in adjacent extreme-tail pairs.
```

Evidence supporting this mechanism:

- Phase 4c raw crossings are adjacent-pair crossings, not broad nonmonotone failures.
- The dominant Phase 4c pair is `0.90-0.95`, with 18 of 23 crossing events.
- The lower-tail pair `0.05-0.10` accounts for 5 of 23 events.
- Contract monotone outputs have zero crossings after the Phase 4c policy.
- Phase 4g shows ordered improvement as `tau0` shrinks from 1.00 to 0.50 to 0.25 to 0.10.
- The same ordered improvement is not visible for `zeta2`, `alpha_prior_sd`, or extra RHS VB inner iterations.

The ordered `tau0` path is:

| tau0 screen | raw crossings | truth MAE | VB max-iteration rate | runtime ratio |
|---|---:|---:|---:|---:|
| baseline_vb480 (`tau0=1.00`) | 22 | 0.140354 | 0.1250 | 1.000 |
| tau0_0p5 | 17 | 0.139705 | 0.0667 | 0.896 |
| tau0_0p25 | 15 | 0.138351 | 0.1250 | 0.950 |
| tau0_0p1 | 13 | 0.132387 | 0.1765 | 1.029 |

This is the core reason Phase 4h is preferred. It is not just that `tau0_0p1` ranked first; it is that the path toward smaller `tau0` is coherent for both raw crossings and truth error.

Evidence limiting the claim:

- Phase 4g is a targeted screen on 7 previously failing replicated rows, not final article evidence.
- `tau0_0p1` still has 13 raw crossings.
- `tau0_0p1` raises the VB max-iteration rate relative to baseline.
- Residual crossings in `student_t_location_scale` and `regime_shift` appear insensitive to the tested controls.
- `tau0_0p1` is not the best screen for the `tau = 0.95` truth MAE.

Therefore, Phase 4h can only select a candidate for a calibration pilot. It cannot promote a final default by itself.

### Scenario And Tau-Pair Audit

The Phase 4c raw crossing events were concentrated as follows:

| base scenario | raw crossing events |
|---|---:|
| persistent_heavy_tail | 8 |
| gaussian_mixture_bridge | 6 |
| student_t_location_scale | 3 |
| laplace_bridge | 2 |
| regime_shift | 2 |
| asymmetric_laplace_tail | 1 |
| heteroskedastic_seasonal | 1 |

The tau-pair breakdown was:

| adjacent tau pair | raw crossing events |
|---|---:|
| 0.05-0.10 | 5 |
| 0.90-0.95 | 18 |

Phase 4g then showed that `tau0_0p1` reduces the upper-tail crossing pair from 18 to 10 and the lower-tail pair from 4 to 2 in the comparable screen summary, but it introduces one `0.75-0.90` crossing. Phase 4h must therefore report crossing migration, not only total crossing count.

### Implementation Wiring Audit

The existing code already supports most of Phase 4h:

- `application/scripts/77_run_joint_qvp_synthetic_dgp_forecast_validation.R` exposes `--tau0`, `--zeta2`, `--alpha-prior-sd`, and `--rhs-vb-inner`.
- `app_joint_qvp_run_synthetic_dgp_forecast_validation()` already applies the raw/contract forecast policy and writes raw and monotone forecast outputs.
- `app_joint_qvp_phase4g_screen_grid()` already creates screen rows for prior/design controls.
- `app_joint_qvp_run_synthetic_dgp_phase4g_prior_design_screen()` already loops over screens, calls Phase 3, verifies nested manifests, aggregates metrics, and writes rankings.
- `application/scripts/85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R` already provides the command-line pattern Phase 4h should follow.

The best implementation is therefore not a new validation framework. It is:

```text
Add a thin Phase 4h wrapper, plus the smallest extension needed to pass a custom tau0-local screen grid into the existing Phase 4g machinery.
```

This keeps Phase 4h smooth and well wired because it reuses the validated Phase 3 forecast runner and the Phase 4g metric aggregation instead of duplicating logic.

### Alternatives Rechecked

| option | decision | reason |
|---|---|---|
| Full calibration now with baseline | reject | known avoidable raw crossings remain |
| Full calibration now with `tau0=0.10` | reject | local optimum and convergence tradeoff not established |
| Stop tuning and rely only on raw/contract policy | reject | contract is correct, but raw crossings remain useful model diagnostics |
| Broad multi-control grid now | defer | `tau0` is the dominant signal; broad grids waste compute before local refinement |
| More VB iterations only | reject as primary | Phase 4g already used strong controls; prior/design controls improve behavior without only increasing compute |
| Anchor/innovation shrinkage redesign now | defer | promising but larger implementation surface; only justified if local `tau0` tuning plateaus |
| DESN feature redesign now | defer | important for scenario-specific residuals, but lower priority than exhausting the simple global shrinkage signal |

### Refined Phase 4h Implementation Plan

Add:

```text
application/scripts/87_run_joint_qvp_synthetic_dgp_phase4h_tau0_refinement.R
```

Preferred helper changes:

- extend `app_joint_qvp_run_synthetic_dgp_phase4g_prior_design_screen()` to accept an optional custom `screen_grid`; or
- add `app_joint_qvp_run_synthetic_dgp_phase4h_tau0_refinement()` that constructs the local grid and calls shared Phase 4g internals.

The second option is preferred for clarity. The shared Phase 4g logic should still do the Phase 3 calls and aggregation.

Required script options:

- `--targeted-registry`
- `--output-dir`
- `--tau0-grid`
- `--include-secondary-grid`
- `--scenario-ids`
- `--vb-max-iter`
- `--adaptive-vb-max-iter-grid`
- `--refit-stride`
- `--forecast-origin-stride`
- `--max-origins-per-scenario`
- `--vb-tol`
- `--kappa`
- `--a-sigma`
- `--b-sigma`
- `--alpha-prior-mean`

Required Phase 4h artifacts:

- `targeted_registry.csv`
- `tau0_refinement_grid.csv`
- `tau0_refinement_run_config.csv`
- `tau0_refinement_metric_summary.csv`
- `tau0_refinement_candidate_ranking.csv`
- `tau0_refinement_crossing_by_scenario.csv`
- `tau0_refinement_crossing_by_tau_pair.csv`
- `tau0_refinement_truth_by_tau.csv`
- `tau0_refinement_vb_runtime_summary.csv`
- `tau0_refinement_recommendation.csv`
- `screen_run_manifest.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

Nested Phase 3 runs should remain under:

```text
screen_runs/<screen_id>/
```

### Refined Candidate Grid

Primary grid:

| screen id | tau0 | purpose |
|---|---:|---|
| tau0_0p25_reference | 0.25 | stable Phase 4g reference |
| tau0_0p20 | 0.20 | tests whether most benefit appears before the `0.10` convergence cost |
| tau0_0p15 | 0.15 | likely compromise region |
| tau0_0p10_reference | 0.10 | current Phase 4g best |
| tau0_0p075 | 0.075 | tests continuation below 0.10 |
| tau0_0p05 | 0.05 | aggressive shrinkage boundary |

Optional secondary grid only if the primary grid is ambiguous:

| screen id | purpose |
|---|---|
| tau0_0p10_alpha_sd_0p5 | check whether intercept shrinkage stabilizes `tau0=0.10` |
| tau0_0p15_alpha_sd_0p5 | check stable compromise with intercept shrinkage |
| tau0_0p10_zeta2_10 | check whether finite coupling helps the upper tail at current best `tau0` |

Do not include broad `rhs_inner` or zeta-only candidates in the first Phase 4h full run.

### Refined Gates

Hard fail:

- missing root or nested manifests;
- unverified hashes;
- changed seeds or missing frozen targeted rows;
- train/test leakage;
- nonfinite forecasts, scores, truth metrics, or runtime summaries;
- contract quantile crossings;
- missing raw/contract crossing diagnostics.

Review:

- raw crossing count remains at or above 13;
- upper-tail `0.90-0.95` crossings do not improve relative to `tau0_0p1`;
- crossings migrate into interior tau pairs;
- maximum monotone adjustment worsens relative to `tau0_0p1`;
- global truth MAE worsens by more than 1 percent relative to `tau0_0p1`;
- `tau = 0.95` truth MAE worsens materially;
- VB max-iteration rate exceeds 0.20;
- runtime exceeds 1.25 times targeted baseline;
- candidate improves crossings only by degrading forecast scores.

Candidate for calibration pilot:

- zero contract crossings;
- raw crossings below 13, or at least as low as 13 with better convergence/runtime/tail truth behavior;
- `0.90-0.95` crossings improve or do not worsen;
- global truth MAE is competitive with `tau0_0p1`;
- `tau = 0.95` truth MAE is not sacrificed;
- VB max-iteration rate is at or below 0.20;
- runtime is article-planning compatible.

Promotion to article-candidate default is not allowed from Phase 4h alone. A Phase 4h winner must pass a calibration-size rerun before default changes.

### Kill Criteria

Stop local `tau0` tuning and move to structural work if:

- every candidate below `0.10` worsens tail truth while only marginally reducing crossings;
- raw crossings migrate from extreme tails into central tau pairs;
- best crossing candidate has VB max-iteration rate above 0.25;
- contract crossings reappear;
- seed preservation cannot be verified;
- runtime becomes incompatible with article-candidate planning.

If this happens, the next stage should be Phase 4i structural diagnostics: separate anchor/innovation shrinkage, scenario-specific DESN feature audit, and explicit smoothness/monotonicity regularization options.

### Refined Test And Verification Plan

Add focused tests for:

- local tau0 grid parsing and stable screen ids, including `tau0_0p075`;
- exact targeted registry loading and seed preservation;
- custom screen-grid wiring into the Phase 4g aggregation path;
- smoke Phase 4h artifacts and schemas;
- nested Phase 3 manifest verification;
- contract crossing hard-fail behavior;
- finite ranking/recommendation outputs;
- existing Phase 4g focused tests still passing.

Smoke command after implementation:

```bash
Rscript application/scripts/87_run_joint_qvp_synthetic_dgp_phase4h_tau0_refinement.R \
  --targeted-registry application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4h_tau0_refinement_smoke \
  --tau0-grid 0.25,0.10 \
  --vb-max-iter 40 \
  --adaptive-vb-max-iter-grid 40,60 \
  --refit-stride 40 \
  --forecast-origin-stride 40 \
  --max-origins-per-scenario 2
```

Full targeted command:

```bash
Rscript application/scripts/87_run_joint_qvp_synthetic_dgp_phase4h_tau0_refinement.R \
  --targeted-registry application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4h_tau0_refinement \
  --tau0-grid 0.25,0.20,0.15,0.10,0.075,0.05 \
  --vb-max-iter 480 \
  --adaptive-vb-max-iter-grid 480,720 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

### Final Audited Recommendation

The comprehensive audit confirms the original recommendation:

```text
Phase 4h local tau0 refinement is the optimal next move.
```

It is optimal because it resolves the only strong, ordered improvement signal from Phase 4g while preserving seed control, avoiding broad compute waste, and reusing the existing Phase 3/4g validation machinery. It is also conservative: it cannot by itself change article defaults, and it has explicit kill criteria that route the project to structural diagnostics if local shrinkage stops helping.

## Implementation Entry Point

Phase 4h is implemented as a thin wrapper around the existing Phase 4g/Phase 3 machinery:

```text
application/scripts/87_run_joint_qvp_synthetic_dgp_phase4h_tau0_refinement.R
```

Primary helper:

```text
app_joint_qvp_run_synthetic_dgp_phase4h_tau0_refinement()
```

Focused test:

```text
application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4h_tau0_refinement.R
```

The full targeted launch command is:

```bash
Rscript application/scripts/87_run_joint_qvp_synthetic_dgp_phase4h_tau0_refinement.R \
  --targeted-registry application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4h_tau0_refinement \
  --tier targeted \
  --tau0-grid 0.25,0.20,0.15,0.10,0.075,0.05 \
  --vb-max-iter 480 \
  --adaptive-vb-max-iter-grid 480,720 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```
