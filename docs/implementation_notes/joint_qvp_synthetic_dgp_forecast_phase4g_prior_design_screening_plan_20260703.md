# Joint-QVP Synthetic DGP Forecast Validation: Phase 4g Prior/Design Screening Plan

Date: 2026-07-03

## Purpose

Phase 4e and Phase 4f established two important facts:

1. Stronger VB controls materially reduced max-iteration review behavior.
2. Raw forecast crossings persisted: 23 raw crossing pairs in the Phase 4d baseline versus 22 under the stronger-VB Phase 4e follow-up.

The next stage should therefore screen model-side controls that may reduce raw crossings and improve fit/forecast quality before running another full calibration campaign.

This is a screening plan only. It should not freeze article claims and should not modify TT500, GloFAS, or PriceFM lanes.

## Current Evidence

Relevant artifacts:

- Phase 4d full contract calibration:
  `application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702`
- Phase 4e stronger-VB targeted follow-up:
  `application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4e_targeted_crossing_followup_vb480`
- Phase 4f sparsity/tau0 diagnostics:
  `application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4f_sparsity_tau0_diagnostics`
- Phase 4f data/truth/fit overlays:
  `application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4e_targeted_crossing_followup_vb480/phase4f_data_truth_fit_overlays`

Numerical summary:

- Tau grid: `0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`.
- Phase 4d targeted rows raw crossing pairs: 23.
- Phase 4e stronger-VB targeted rows raw crossing pairs: 22.
- Contract crossing pairs: 0 in both runs.
- Targeted-row VB max-iteration rate improved from 0.69230769 to 0.125.

Interpretation: raw crossings are not mainly an iteration-limit artifact. They are more likely related to tail readout instability, insufficient adjacent-quantile coefficient sharing, feature/readout scaling, or local extreme-tail noise.

## Prior Direction Reminder

The current RHS prior precision is:

```text
precision = 1 / (tau2 * lambda2) + 1 / zeta2
```

with:

```text
tau2 = tau0^2
```

Therefore larger `tau0` weakens RHS shrinkage. If the goal is more sparsity or less noisy readout coefficients, screen smaller `tau0`, finite `zeta2`, and eventually separate anchor versus adjacent-innovation shrinkage.

## Key Hypotheses

### H1: Stronger Global RHS Shrinkage

Smaller global `tau0` may reduce raw tail crossing by shrinking noisy quantile-specific readout coefficients.

Risk: too much global shrinkage can flatten dynamics and worsen truth-distance, hit rates, and interval coverage.

### H2: Finite Slab Scale

Finite `zeta2` adds a slab precision floor and may stabilize large readout coefficients.

Risk: too-small `zeta2` may underfit sharp nonlinear/heavy-tail dynamics.

### H3: Stronger Adjacent-Innovation Shrinkage

The most promising structural idea is to shrink adjacent quantile innovations more strongly than the common anchor readout. This encourages neighboring quantile coefficient vectors to be similar without over-shrinking the shared dynamics.

Risk: this requires new plumbing because the current forecast runner exposes one global `tau0`, not separate `anchor_tau0` and `innovation_tau0`.

### H4: Alpha/Intercept Stabilization

The intercepts are ordered, but raw forecast crossings can still arise when slopes differ across tau. A tighter empirical alpha prior may reduce intercept noise and improve fit stability.

Risk: too-tight alpha priors can force empirical marginal behavior onto conditional quantiles and harm scenario-specific tail dynamics.

### H5: Readout/DESN Design

If crossing origins have large design-feature norms, unstable feature scaling, or excessive readout sensitivity, better feature/readout design can reduce crossings and improve forecast quality.

In the current synthetic registry, the design is small and DGP-driven rather than a full high-dimensional DESN reservoir, so this should start as a feature/readout audit rather than a reservoir overhaul.

## Required Plumbing Before Screening

Add a narrow Phase 4g runner/script rather than changing calibration behavior silently.

Recommended script:

`application/scripts/85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R`

The runner should:

- Load the frozen Phase 4c/4e targeted crossing registry rows exactly.
- Preserve scenario ids, seeds, replicate ids, and origin controls.
- Reuse Phase 3 forecast validation logic and raw/contract output policy.
- Expose existing controls through CLI:
  - `--tau0`
  - `--alpha-prior-sd`
  - `--rhs-vb-inner`
  - `--vb-max-iter`
  - `--adaptive-vb-max-iter-grid`
  - `--refit-stride`
  - `--forecast-origin-stride`
  - `--max-origins-per-scenario`
- Add plumbing for currently internal controls:
  - `--zeta2`, passed through `app_joint_qvp_fit_al_vb_adaptive()` into `app_joint_qvp_fit_al_vb_tiny()`.
  - `--alpha-min-spacing`, only for sensitivity and with default 0.
- Optional second step:
  - `--anchor-tau0`
  - `--innovation-tau0`
  - `--anchor-zeta2`
  - `--innovation-zeta2`

Do not alter Phase 3/4 defaults. All new controls should be explicit and recorded in run configs.

## Screening Tiers

### Tier 0: Plumbing Smoke

Purpose: confirm new controls are wired correctly.

Run 1 or 2 targeted scenarios, 5 to 8 origins each.

Controls:

- `vb_max_iter = 120`
- `adaptive_vb_max_iter_grid = 120,240`
- `refit_stride = 20`
- `forecast_origin_stride = 10`
- `max_origins_per_scenario = 8`

Pass condition:

- Artifacts complete.
- Manifests complete.
- No contract crossings.
- Control values are recorded in `run_config.csv`.
- Results change when `tau0`/`zeta2` are changed.

### Tier 1: Targeted Crossing Screen

Purpose: identify promising controls on the exact crossing-prone replicated rows.

Use the 7 Phase 4e targeted rows:

- `laplace_bridge__calibration_r05`
- `gaussian_mixture_bridge__calibration_r05`
- `student_t_location_scale__calibration_r05`
- `asymmetric_laplace_tail__calibration_r02`
- `heteroskedastic_seasonal__calibration_r04`
- `persistent_heavy_tail__calibration_r05`
- `regime_shift__calibration_r02`

Use the same controls as Phase 4e for comparability:

- `vb_max_iter = 480`
- `adaptive_vb_max_iter_grid = 480,720`
- `refit_stride = 20`
- `forecast_origin_stride = 10`
- `max_origins_per_scenario = 40`

Recommended first grid:

| screen_id | tau0 | zeta2 | alpha_prior_sd | rhs_vb_inner | rationale |
|---|---:|---:|---:|---:|---|
| baseline_vb480 | 1.00 | Inf | 1.00 | 5 | current stronger-VB reference |
| tau0_0p5 | 0.50 | Inf | 1.00 | 5 | moderate stronger global RHS shrinkage |
| tau0_0p25 | 0.25 | Inf | 1.00 | 5 | strong global RHS shrinkage |
| tau0_0p1 | 0.10 | Inf | 1.00 | 5 | aggressive shrinkage stress |
| zeta2_10 | 1.00 | 10 | 1.00 | 5 | light slab precision floor |
| zeta2_4 | 1.00 | 4 | 1.00 | 5 | moderate slab precision floor |
| tau0_0p5_zeta2_10 | 0.50 | 10 | 1.00 | 5 | combined moderate shrinkage |
| tau0_0p25_zeta2_10 | 0.25 | 10 | 1.00 | 5 | combined stronger shrinkage |
| alpha_sd_0p5 | 1.00 | Inf | 0.50 | 5 | tighter empirical alpha prior |
| rhs_inner_8 | 1.00 | Inf | 1.00 | 8 | check RHS VB update accuracy/stability |

Keep this first grid modest. If one or two candidates dominate, expand around them.

### Tier 2: Innovation-Shrinkage Screen

Purpose: test the best structural idea: adjacent quantile coefficients should be more similar, but common dynamics should remain flexible.

This requires extending the RHS state initializer/builders to support separate anchor and innovation controls.

Recommended grid:

| screen_id | anchor_tau0 | innovation_tau0 | anchor_zeta2 | innovation_zeta2 | rationale |
|---|---:|---:|---:|---:|---|
| anchor1_innov0p5 | 1.00 | 0.50 | Inf | Inf | moderate adjacent-coefficient sharing |
| anchor1_innov0p25 | 1.00 | 0.25 | Inf | Inf | strong adjacent-coefficient sharing |
| anchor1_innov0p5_zeta10 | 1.00 | 0.50 | Inf | 10 | adjacent sharing plus slab floor |
| anchor0p75_innov0p25 | 0.75 | 0.25 | Inf | Inf | light common shrinkage, strong innovation shrinkage |

Promotion condition:

- Raw crossing pairs reduce materially relative to Phase 4e.
- Truth-distance and hit-rate errors do not materially worsen.
- Runtime and convergence remain acceptable.

### Tier 3: Feature/Readout Design Audit

Purpose: determine whether raw crossings are tied to feature norms or readout instability.

Compute, by scenario and origin:

- design row norm at forecast origin;
- max absolute feature value;
- fitted readout beta norm by tau;
- adjacent beta-difference norm by tau pair;
- crossing magnitude;
- truth-distance at crossed origin;
- whether raw crossing is lower-tail or upper-tail.

Only if crossings correlate with design instability should we test feature/readout changes, such as:

- robust feature standardization inside the fit window;
- capping or winsorizing only highly unstable synthetic features for a diagnostic run;
- reducing or smoothing reservoir/readout features in a true DESN application setting.

No feature-design change should be promoted unless it improves both raw crossing behavior and forecast metrics.

### Tier 4: Winner Calibration Pilot

Promote at most 2 to 3 candidate settings from Tiers 1-3.

Run a calibration pilot:

- all enabled base scenarios;
- `n_replicates = 3`;
- same calibration lengths;
- realistic VB controls;
- same raw/contract policy.

This is not the final article candidate. It checks whether targeted improvements generalize beyond the crossing rows.

### Tier 5: Full Calibration Rerun

Only after a candidate passes the calibration pilot:

- rerun Phase 4 calibration under candidate controls;
- rerun Phase 4b readiness;
- rerun Phase 4c crossing audit;
- regenerate Phase 4f visual diagnostics.

## Metrics To Rank Candidates

Primary crossing metrics:

- raw crossing pairs;
- raw crossing origins;
- max raw crossing magnitude;
- total monotone adjusted origins;
- max monotone adjustment;
- contract crossing pairs, which must remain zero.

Primary fit/forecast metrics:

- mean absolute error to true conditional quantiles;
- max absolute error to true conditional quantiles;
- normalized truth distance;
- pinball loss;
- hit-rate error by tau;
- interval coverage error;
- interval score / WIS / CRPS grid approximation.

Computation metrics:

- VB max-iteration rate;
- objective status;
- runtime total and per refit;
- convergence attempts per origin.

Interpretability/readout metrics:

- RHS mean precision and max precision;
- beta norm by tau;
- adjacent beta-difference norm;
- alpha gaps by tau;
- feature norm at crossing origins.

## Candidate Promotion Rules

Use conservative gates.

Hard fail:

- missing artifacts or hashes;
- train/test leakage;
- nonfinite forecasts or scores;
- contract quantile crossings;
- malformed run config/provenance.

Review:

- raw crossings persist but reduce less than 25%;
- truth-distance worsens by more than 5%;
- hit-rate errors worsen by more than 0.025 absolute at any target tau;
- VB max-iteration rate exceeds 0.25;
- runtime increases by more than 2x without clear metric benefit.

Promote:

- raw crossing pairs reduce by at least 50% on targeted rows, or max crossing magnitude reduces by at least 50%;
- contract crossings remain zero;
- mean truth-distance does not worsen by more than 2%;
- hit-rate and interval metrics are neutral or improved;
- VB max-iteration rate stays at or below the Phase 4e level;
- runtime remains reasonable.

If no candidate reduces raw crossings materially without forecast degradation, keep the raw/contract policy and document raw crossings as a review-level diagnostic rather than overfitting the prior.

## Recommended Immediate Next Step

Implement Phase 4g as a targeted screen, not a full calibration rerun.

Minimum first implementation:

1. Add `zeta2` and `alpha_min_spacing` plumbing from Phase 3 forecast validation into `app_joint_qvp_fit_al_vb_tiny()`.
2. Add CLI controls to `77_run_joint_qvp_synthetic_dgp_forecast_validation.R`.
3. Add `85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R` to run the Tier 1 grid over the exact Phase 4e targeted registry rows.
4. Write outputs:
   - `screen_grid.csv`
   - `screen_run_config.csv`
   - `screen_metric_summary.csv`
   - `screen_candidate_ranking.csv`
   - `screen_crossing_summary.csv`
   - `screen_truth_metric_summary.csv`
   - `screen_vb_runtime_summary.csv`
   - `screen_recommendation.csv`
   - `README.md`
   - `artifact_manifest.csv`
5. Add focused tests:
   - control plumbing changes run config values;
   - fixed-seed targeted registry rows are preserved;
   - screen summary schema is stable;
   - artifact manifest is complete;
   - no contract crossings in smoke mode.

Recommended first real command after implementation:

```bash
Rscript application/scripts/85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R \
  --targeted-registry application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4c_crossing_audit/targeted_crossing_registry.csv \
  --output-dir application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4g_prior_design_screen \
  --tier targeted \
  --vb-max-iter 480 \
  --adaptive-vb-max-iter-grid 480,720 \
  --refit-stride 20 \
  --forecast-origin-stride 10 \
  --max-origins-per-scenario 40
```

The next decision after Phase 4g should be whether any candidate deserves a 3-replicate calibration pilot.
