# Joint-QVP Synthetic DGP Forecast Phase 4h Closeout And Next Plan

Date: 2026-07-04

## Executive Summary

Phase 4h completed successfully. The implementation and artifact health checks passed, and the local tau0 refinement answered the central question:

```text
tau0 = 0.10 remains the best formal candidate under the Phase 4h ranking and gate policy.
```

However, the evidence also identifies a meaningful comparator:

```text
tau0 = 0.15 ties tau0 = 0.10 on total raw crossings and upper-tail crossings, runs faster, and improves tau = 0.95 truth MAE, but worsens global truth MAE by about 3.1 percent.
```

Recommended next stage:

```text
Run a bounded Phase 4h-next calibration pilot with tau0 = 0.10 as the primary arm and tau0 = 0.15 as a stability/tail comparator.
```

Do not move directly to final article-candidate validation yet. Phase 4h was intentionally targeted to the frozen crossing rows; the next question is whether the `tau0 = 0.10` result generalizes beyond the targeted set.

## Health Check

| component | status | evidence | interpretation |
|---|---|---|---|
| Detached run | complete | `tmux` session exited | No active process remains. |
| Exit code | pass | log contains `PHASE4H_EXIT_CODE=0` | Runner completed normally. |
| Targeted registry | pass | 7 rows, frozen Phase 4c seeds preserved | No seed drift. |
| Screen count | pass | 6 screen directories, 6 nested `run_config.csv` files | Full primary tau0 grid ran. |
| Root artifact manifest | pass | 13 rows, SHA-256 checks passed | Root artifacts are reproducible. |
| Nested Phase 3 manifests | pass | 6 of 6 reported verified; independent hash checks passed | Nested forecast artifacts are reproducible. |
| Contract crossings | pass | 0 for every screen | Scoring contract remains valid. |
| Raw crossings | review | best screens still have 13 raw crossings | Raw model diagnostics remain review-level. |
| VB convergence | review | best screen max-iteration rate 0.1765 | Below 0.20 review ceiling but still not fully clean. |
| Recommendation | review | `reference_remains_candidate_for_calibration_pilot` | Ready for calibration pilot, not final default promotion. |

Artifact root:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4h_tau0_refinement
```

## Candidate Ranking

| rank | screen | tau0 | raw crossings | upper-tail 0.90-0.95 crossings | max raw crossing | contract crossings | truth MAE | tau=0.95 MAE | VB max-iter rate | runtime sec | status |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | `tau0_0p10_reference` | 0.100 | 13 | 10 | 0.1231 | 0 | 0.1323865 | 0.2243435 | 0.1765 | 954.750 | reference |
| 2 | `tau0_0p15` | 0.150 | 13 | 10 | 0.1239 | 0 | 0.1365169 | 0.2180140 | 0.1765 | 755.692 | review |
| 3 | `tau0_0p2` | 0.200 | 14 | 11 | 0.1286 | 0 | 0.1377835 | 0.2218685 | 0.1765 | 717.841 | review |
| 4 | `tau0_0p25_reference` | 0.250 | 15 | 12 | 0.1319 | 0 | 0.1383506 | 0.2229567 | 0.1250 | 571.601 | review |
| 5 | `tau0_0p05` | 0.050 | 17 | 14 | 0.2756 | 0 | 0.1322589 | 0.2284943 | 0.1875 | 674.208 | review |
| 6 | `tau0_0p075` | 0.075 | 18 | 15 | 0.2934 | 0 | 0.1321670 | 0.2253353 | 0.1250 | 950.618 | review |

## Main Findings

### 1. The local optimum is not below 0.10

The aggressive values `tau0 = 0.075` and `tau0 = 0.05` improved or matched global truth MAE, but they materially worsened raw crossings:

| screen | raw crossings | max raw crossing | upper-tail crossings |
|---|---:|---:|---:|
| `tau0_0p10_reference` | 13 | 0.1231 | 10 |
| `tau0_0p075` | 18 | 0.2934 | 15 |
| `tau0_0p05` | 17 | 0.2756 | 14 |

Interpretation:

```text
Pushing tau0 below 0.10 over-shrinks or destabilizes the raw tail geometry on the targeted crossing rows.
```

This closes the local search below `tau0 = 0.10`.

### 2. The best practical comparator is tau0 = 0.15

`tau0 = 0.15` ties `tau0 = 0.10` on:

- total raw crossings: 13 vs 13;
- upper-tail `0.90-0.95` crossings: 10 vs 10;
- contract crossings: 0 vs 0;
- VB max-iteration rate: 0.1765 vs 0.1765.

It improves:

- runtime: about 21 percent faster than `tau0 = 0.10`;
- `tau = 0.95` truth MAE: 0.2180 vs 0.2243;
- interior crossing migration: no `0.75-0.90` crossing, while `tau0 = 0.10` has one.

It worsens:

- global truth MAE by about 3.1 percent;
- lower-tail raw crossings: 3 vs 2;
- `tau = 0.05`, `0.10`, and `0.90` truth MAE.

Interpretation:

```text
tau0 = 0.15 is not better than tau0 = 0.10 overall, but it is strong enough to include as a comparator in the next calibration pilot.
```

### 3. Residual crossings are scenario-specific

Comparing `tau0 = 0.10` and `tau0 = 0.15`:

| scenario | crossings at tau0=0.10 | crossings at tau0=0.15 | interpretation |
|---|---:|---:|---|
| `persistent_heavy_tail` | 5 | 6 | Main residual blocker; `0.10` is better. |
| `student_t_location_scale` | 3 | 2 | `0.15` helps this scenario. |
| `gaussian_mixture_bridge` | 2 | 2 | Tie. |
| `regime_shift` | 2 | 2 | Tie; insensitive to local tau0. |
| `laplace_bridge` | 1 | 1 | Tie. |
| `asymmetric_laplace_tail` | 0 | 0 | Clean. |
| `heteroskedastic_seasonal` | 0 | 0 | Clean. |

Interpretation:

```text
Residual crossings are not solved by scalar tau0 alone. Persistent heavy-tail and regime-shift behavior likely need scenario/design diagnostics if they remain problematic in calibration.
```

### 4. The raw/contract policy remains essential

All screens had zero contract crossings. The raw output still crosses, but the monotone contract quantiles used for scoring are valid.

Interpretation:

```text
The forecast scoring pipeline is article-safe under the current contract, while raw crossings remain diagnostic review evidence.
```

## Decision

Phase 4h supports:

```text
Keep tau0 = 0.10 as the primary candidate for calibration pilot.
```

Phase 4h does not support:

- selecting `tau0 < 0.10`;
- changing final article defaults yet;
- claiming raw crossings are solved;
- skipping calibration-size validation.

## Recommended Next Stage: Phase 4i Calibration Pilot

Purpose:

Test whether the Phase 4h targeted result generalizes beyond the frozen crossing rows, while keeping compute bounded.

Recommended arms:

| arm | role | reason |
|---|---|---|
| `tau0 = 0.10` | primary candidate | Best Phase 4h rank, best global tradeoff, lowest raw crossing count tied with `0.15`. |
| `tau0 = 0.15` | stability comparator | Same raw/upper-tail crossing count, faster runtime, better `tau=0.95` MAE, but worse global MAE. |

Optional third arm only if compute allows:

| arm | role | reason |
|---|---|---|
| `tau0 = 0.25` | stable reference | Lower VB max-iteration rate and fastest among reference-like candidates, but more raw crossings. |

### Proposed Controls

Use a calibration-pilot tier, not the full article-candidate tier:

```text
n_replicates = 3
vb_max_iter = 480
adaptive_vb_max_iter_grid = 480,720
refit_stride = 20
forecast_origin_stride = 10
max_origins_per_scenario = 40
```

If runtime is too high, reduce only one dimension and label the run clearly as a pilot:

```text
n_replicates = 2
```

Do not reduce VB controls for this pilot; doing so would confound the Phase 4h conclusion.

### Required Outputs

The pilot should write:

- candidate-arm registry;
- candidate-arm run config;
- per-arm Phase 3/Phase 4 artifacts;
- raw/contract crossing summaries;
- scenario/family/tau failure-mode summaries;
- truth-by-tau comparisons;
- runtime and VB convergence summaries;
- recommendation table;
- provenance;
- artifact manifest.

### Pilot Gates

Hard fail:

- missing or unverifiable manifests;
- seed drift;
- leakage;
- nonfinite scores;
- contract crossings.

Review:

- raw crossings remain concentrated in the same scenarios;
- VB max-iteration rate exceeds 0.20;
- `tau0 = 0.15` improves tails but worsens global metrics consistently;
- persistent heavy-tail/regime-shift residuals remain high.

Candidate for article-scale run:

- contract crossings remain zero;
- `tau0 = 0.10` or `0.15` dominates across replicates under the same tradeoff criteria;
- raw crossing rates are materially lower than the old baseline;
- truth MAE and tail MAE remain stable;
- runtime is article-scale feasible.

## If The Pilot Confirms tau0 = 0.10

Run a full calibration-size campaign with `tau0 = 0.10`, then perform a Phase 4b-style readiness audit. If it passes implementation gates and remains review-only statistically, proceed to article-candidate validation.

## If tau0 = 0.15 Wins In The Pilot

Promote `tau0 = 0.15` to the calibration-size candidate only if:

- global truth MAE degradation disappears or becomes negligible across replicates;
- `tau = 0.95` remains better;
- raw crossings tie or improve;
- runtime advantage persists.

## If Neither Candidate Generalizes

Move to structural Phase 4j diagnostics:

- separate anchor and adjacent-innovation shrinkage;
- scenario-specific heavy-tail and regime-shift DESN design audit;
- coefficient path smoothness diagnostics across tau;
- optional explicit monotonicity/smoothness regularization review.

## Recommended Immediate Command Template

The next implementation should add or reuse a small candidate-arm runner rather than manually launching separate Phase 4 campaigns. The conceptual command should look like:

```bash
Rscript application/scripts/88_run_joint_qvp_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot.R \
  --registry application/config/joint_qvp_synthetic_dgp_registry_phase1.csv \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4i_tau0_candidate_pilot_20260704 \
  --tau0-arms 0.10,0.15 \
  --tier calibration_pilot \
  --n-replicates 3 \
  --seed-base 202607400 \
  --vb-max-iter 480 \
  --adaptive-vb-max-iter-grid 480,720 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

## Bottom Line

Phase 4h did exactly what it needed to do:

- verified implementation health;
- closed the local tau0 search below 0.10;
- retained `tau0 = 0.10` as the primary candidate;
- identified `tau0 = 0.15` as a serious stability/tail comparator;
- confirmed contract quantiles remain safe;
- showed raw crossings remain diagnostic review evidence, especially for persistent heavy-tail and regime-shift behavior.

The next move should be a bounded two-arm calibration pilot, not a full article-candidate run and not a structural redesign yet.

