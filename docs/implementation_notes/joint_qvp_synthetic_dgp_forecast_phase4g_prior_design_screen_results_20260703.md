# Joint-QVP Synthetic DGP Forecast Phase 4g Prior/Design Screen Results

Date: 2026-07-03

## Run

Command:

```bash
Rscript application/scripts/85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R \
  --tier targeted \
  --vb-max-iter 480 \
  --adaptive-vb-max-iter-grid 480,720 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40 \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4g_prior_design_screen
```

Artifact directory:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4g_prior_design_screen
```

The run used the frozen Phase 4c targeted registry:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv
```

The targeted registry contains 7 replicated scenario rows with preserved Phase 4c seeds. The screen evaluated 10 prior/design candidates. Root and nested Phase 3 manifests verified successfully.

## Main Results

| screen | raw crossing pairs | contract crossing pairs | mean truth MAE | VB max-iteration rate | runtime seconds |
|---|---:|---:|---:|---:|---:|
| baseline_vb480 | 22 | 0 | 0.140354 | 0.1250 | 523.080 |
| tau0_0p5 | 17 | 0 | 0.139705 | 0.0667 | 468.469 |
| tau0_0p25 | 15 | 0 | 0.138351 | 0.1250 | 496.695 |
| tau0_0p1 | 13 | 0 | 0.132387 | 0.1765 | 538.295 |
| zeta2_10 | 18 | 0 | 0.139687 | 0.1250 | 512.998 |
| zeta2_4 | 18 | 0 | 0.139687 | 0.1250 | 513.536 |
| tau0_0p5_zeta2_10 | 15 | 0 | 0.139006 | 0.1250 | 498.414 |
| tau0_0p25_zeta2_10 | 15 | 0 | 0.137646 | 0.1765 | 544.816 |
| alpha_sd_0p5 | 21 | 0 | 0.140113 | 0.0667 | 414.499 |
| rhs_inner_8 | 22 | 0 | 0.140354 | 0.1250 | 523.476 |

## Interpretation

The dominant signal is `tau0`, not `zeta2`, `alpha_prior_sd`, or extra RHS inner iterations.

Smaller `tau0` monotonically reduced raw forecast crossings:

- `tau0 = 1.00`: 22 raw crossing pairs.
- `tau0 = 0.50`: 17 raw crossing pairs.
- `tau0 = 0.25`: 15 raw crossing pairs.
- `tau0 = 0.10`: 13 raw crossing pairs.

The same sequence also improved mean truth MAE, with the best value at `tau0_0p1`. The cost is higher VB max-iteration rate at `tau0_0p1` and `tau0_0p25_zeta2_10`.

Finite `zeta2` helped modestly but did not stack enough to beat `tau0_0p1`. Tightening `alpha_prior_sd` improved runtime and convergence but barely reduced raw crossings. Increasing `rhs_vb_inner` from 5 to 8 did not materially change the result.

The conservative Phase 4g promotion rule required at least 50 percent raw crossing reduction. The best candidate, `tau0_0p1`, reduced raw crossings by about 41 percent, so the formal screen recommendation remains:

```text
no_promoted_candidate_keep_contract_policy_or_expand_tier2
```

This should not be read as evidence that `tau0_0p1` is unhelpful. It is the best current candidate, but it did not clear the deliberately strict promotion threshold.

## Recommended Next Step

Run a small Phase 4h local tau0 refinement screen around the promising region before changing article-candidate defaults. Suggested candidates:

- `tau0 = 0.20`
- `tau0 = 0.15`
- `tau0 = 0.10`
- `tau0 = 0.075`
- `tau0 = 0.05`

Keep:

- `zeta2 = Inf` as the primary local screen, because finite `zeta2` was not dominant.
- `alpha_prior_sd = 1`.
- `rhs_vb_inner = 5`.
- the same frozen targeted registry rows.
- the same raw/contract forecast policy.
- the same Phase 4e compute controls.

If the local screen shows that `tau0_0p1` or a nearby value gives stable raw-crossing reduction without unacceptable VB convergence cost, then run a calibration-pilot Phase 4 campaign with that tau0 before updating article-candidate defaults.
