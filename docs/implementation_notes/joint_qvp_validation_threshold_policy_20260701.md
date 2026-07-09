# Joint-QVP Validation Threshold Policy

Date: 2026-07-01  
Scope: joint multi-quantile QVP prototype validation only. This does not change
TT500, GloFAS, or PriceFM article-facing evidence.

## Repo Audit Basis

Existing Q-DESN validation practice in this repository separates hard
implementation gates from statistical promotion claims:

- `application/R/validation_interface_contract.R` hard-fails stale validation
  paths, missing provenance, malformed windows, missing hashes, and nonpositive
  forecast metric counts.
- `application/tests/test_shared_validation_tt500_vb_competitiveness.R`
  requires Q-DESN VB rows to beat the DQLM/exDQLM VB baselines on all required
  metrics before the article-facing competitiveness audit passes.
- `docs/implementation_notes/qdesn_vb_source_tt500_median_comparison_20260528.md`
  uses exact-equivalence checks at tolerance `1e-7` for deterministic batching
  gates, while explicitly allowing economical max-iteration runs when the
  comparison target is matched status and matched summaries.
- PriceFM planning notes use validation-first pass/fail guardrails and keep
  test-only gains as audit evidence, not promotion evidence.

The joint-QVP lane follows the same pattern: hard-fail implementation and
reproducibility defects, record statistical distances, and defer promotion
claims until threshold choices are supported by a broader validation campaign.

## Current Hard Gates

- Repeated same-config artifact runs must produce identical SHA-256 hashes.
- VB summaries, RHS prior summaries, monitor terms, AL-VB included
  partial-ELBO terms, and warm-started MCMC draws must be finite.
- RHS prior precisions must remain positive.
- Warm-started MCMC must report `init_source = provided`.
- Fitted quantile summaries in the artifact gate must have zero adjacent
  crossing pairs.
- Non-finite VB/MCMC distance is a hard failure.

## Current Review Gates

- Normalized VB/MCMC distance above `5` is `review`.
- VB fits that reach `prototype_max_iter` remain `review`, not `pass`.
- exAL-VB/VB-LD uses an approximate monitor; full ELBO acceptance is still open.
- AL-VB partial-ELBO accounting is exported for audit. GIG latent entropy is
  included and RHS mean-field scale accounting is included under the implemented
  convention, but approximate RHS log-precision and point-intercept treatment
  keep full ELBO monotonicity as an open review item.
- AL-VB accounted-objective monotonicity uses `max_drop <= 1e-8` as a pass
  signal. Larger finite drops are review-only until the RHS log-precision and
  point-intercept convention is promoted.
- AL-VB objective stress runs use the same monotonicity rule. A stress case can
  pass the objective gate while remaining overall `review` if the fit status is
  `prototype_max_iter`.
- VB-initialized AL-MCMC calibration uses a matched finite-mean sigma prior
  `IG(2, 1)` in VB and MCMC plus broad VB-relative sigma bounds:
  `sigma_upper = max(1, 50 * max(sigma_VB))`. These bounds are documented as
  reference-stabilization controls, not as posterior promotion evidence.
  Positive upper-bound hit fractions keep affected rows in threshold-review
  territory.
- The current tiny MCMC references are intentionally short implementation
  checks. They are not yet calibrated long-chain posterior agreement oracles,
  especially for the working scale block.

## Kappa Calibration Decision

Updated: 2026-07-02.

The main AL synthetic validation lane uses `kappa = 1`. A targeted
asymmetric-Laplace tail audit showed that using `kappa = 0.5` inside the
complete-data AL latent augmentation changes the fitted target and pushes the
extreme quantile fits outward. Direct check-loss quantile regression recovers
the tail truth, and AL-VB/AL-MCMC recover it when the augmented AL lane uses
`kappa = 1`.

Current policy:

- `kappa = 1` is the default for main AL-VB, VB-initialized AL-MCMC,
  time-series suite validation, repeated-seed threshold calibration, and targeted
  deep-MCMC reference checks.
- `kappa = 0.5` remains allowed only in explicitly labeled stress or
  mis-target-diagnostic runs.
- Do not use augmented-density `kappa = 0.5` failures as evidence against the
  synthetic DGP or the QVP readout. They diagnose the tempering convention.
- A tempered marginal AL/check-loss lane must get a separate derivation before
  it can replace the `kappa = 1` validation lane.

The reproducible audit is:

`application/cache/joint_qvp_ts_extreme_tail_fit_audit_20260702/audit_report.md`

The normalization uses the relevant parameter dimension and scale so tiny
short-chain MCMC smoke references are not treated as exact posterior truth:

```text
beta distance  / { sqrt(p K) (1 + ||beta_VB||_2) }
alpha distance / { sqrt(K) (1 + mean(sigma_VB)) }
sigma distance / { sqrt(K) (1 + mean(sigma_VB)) }
gamma distance / { sqrt(K) (1 + |mean(gamma_VB)|) }
```

## Artifact Outputs

The synthetic validation command writes:

- `validation_thresholds.csv`: predeclared thresholds and rationales.
- `validation_assessment.csv`: pass/review/fail status per scenario and method.
- `fit_summary.csv`: VB summaries and VB-to-MCMC raw distances.
- `monitor_terms.csv`: stable coordinate-monitor terms.
- `elbo_terms.csv`: AL-VB ELBO accounting terms, including RHS approximation
  statuses and excluded point-intercept status.
- `objective_diagnostics.csv`: objective monotonicity diagnostics for AL-VB and
  approximate-monitor diagnostics for exAL-VB/VB-LD.
- `rhs_prior_summary.csv`: RHS prior precision summaries by block.
- `crossing_summary.csv`: fitted adjacent quantile crossing diagnostics.
- `warmstart_summary.csv`: MCMC initialization and finite-draw checks.
- `artifact_manifest.csv`: file sizes and SHA-256 hashes.

Default artifact location:

`application/cache/joint_qvp_synthetic_vb_validation_20260701/`

The AL-VB objective stress command writes:

- `stress_thresholds.csv`: stress-specific implementation, objective, and
  convergence thresholds.
- `stress_assessment.csv`: pass/review/fail status per stress case.
- `fit_summary.csv`: compact AL-VB fit, convergence, objective, crossing, and
  RHS prior summaries.
- `objective_diagnostics.csv`: objective monotonicity diagnostics for the
  accounted AL-VB partial ELBO.
- `elbo_terms.csv`: final AL-VB accounting terms.
- `rhs_prior_summary.csv`: RHS prior precision summaries by block.
- `crossing_summary.csv`: fitted adjacent quantile crossing diagnostics.
- `artifact_manifest.csv`: file sizes and SHA-256 hashes.

Default stress artifact location:

`application/cache/joint_qvp_al_vb_objective_stress_20260701/`

Current default stress result:

- Six stress cases were run: `K = 1`, wide quantile grid, high-noise slope
  variation, crossing pressure, strong RHS shrinkage, and weak RHS shrinkage.
- All six cases passed implementation and accounted-objective monotonicity
  gates with `max_drop = 0` and zero fitted crossing pairs.
- After calibrated stress controls, all six cases passed the convergence and
  overall stress gates.

The VB-initialized AL-MCMC calibration command writes:

- `calibration_thresholds.csv`: MCMC calibration implementation, distance, and
  reference-stabilization thresholds.
- `calibration_assessment.csv`: pass/review/fail status per stress case.
- `fit_summary.csv`: compact VB/MCMC summaries, warm-start status, sigma bounds,
  crossing counts, and normalized distances.
- `distance_summary.csv`: raw and normalized VB-to-MCMC distances for beta,
  alpha, sigma, and fitted quantiles.
- `mcmc_draw_summary.csv`: finite-draw checks, draw spread, and sigma-bound hit
  fractions.
- `crossing_summary.csv`: fitted adjacent quantile crossing diagnostics for VB
  and MCMC means.
- `rhs_prior_summary.csv`: VB RHS prior precision summaries by block.
- `objective_diagnostics.csv`: VB accounted-objective monotonicity diagnostics.
- `elbo_terms.csv`: final-iteration AL-VB accounting terms.
- `provenance.csv`: repo, git, R, and RNG provenance.
- `artifact_manifest.csv`: file sizes and SHA-256 hashes.

Default calibration artifact location:

`application/cache/joint_qvp_al_vb_mcmc_calibration_20260701/`

Current default calibration result:

- All six cases passed implementation checks, used `init_source = provided`,
  had finite MCMC draws, had zero fitted crossing pairs, and had zero sigma
  upper-bound hit fractions.
- Five stress cases passed the loose normalized-distance rule:
  `k1_baseline`, `slope_high_noise`, `crossing_pressure`,
  `strong_shrinkage`, and `weak_shrinkage`.
- One stress case remains a distance-review row: `wide_tau_parallel`.
- Prior sensitivity showed the weak infinite-mean `IG(0.1, 0.1)` scale prior
  produced four distance-review rows and positive upper-bound hit fractions.
  The matched finite-mean `IG(2, 1)` prior removes the bound-hit issue in the
  default run, but longer-chain probes show the wide-grid case can still move
  between pass and review. Do not promote VB/MCMC distance thresholds until a
  multi-chain wide-grid reference is pinned.

The wide-grid multi-chain MCMC calibration command writes:

- `multichain_thresholds.csv`: multi-chain implementation, reference stability,
  and pooled-distance thresholds.
- `multichain_assessment.csv`: pass/review/fail status for the wide-grid
  reference.
- `fit_summary.csv`: compact VB, pooled MCMC, chain-count, sigma-bound, crossing,
  and pooled-distance summaries.
- `chain_summary.csv`: chain-to-pooled normalized distances.
- `pooled_distance_summary.csv`: raw and normalized VB-to-pooled-MCMC distances.
- `mcmc_draw_summary.csv`: per-chain finite-draw checks, draw spread, and
  sigma-bound hit fractions.
- `crossing_summary.csv`: fitted adjacent quantile crossing diagnostics for VB,
  individual chains, and pooled MCMC means.
- `rhs_prior_summary.csv`: VB RHS prior precision summaries by block.
- `objective_diagnostics.csv`: VB accounted-objective monotonicity diagnostics.
- `elbo_terms.csv`: final-iteration AL-VB accounting terms.
- `provenance.csv`: repo, git, R, and RNG provenance.
- `artifact_manifest.csv`: file sizes and SHA-256 hashes.

Default wide-grid multi-chain artifact location:

`application/cache/joint_qvp_wide_multichain_mcmc_calibration_20260701/`

Current wide-grid multi-chain result:

- Four VB-initialized chains ran from the wide three-quantile fixture with
  60 pooled retained draws.
- The reference uses matched finite-mean `IG(2, 1)` sigma priors and a weak
  proper ordered-intercept prior,
  `alpha_prior_mean = empirical_quantile`, `alpha_prior_sd = 1`.
- Implementation, reference-bound, chain-stability, and pooled-distance gates
  passed.
- There were zero sigma upper-bound hits and zero fitted crossing pairs.
- The pooled normalized VB/MCMC distance was `0.677`, alpha normalized distance
  was `0.149`, and max chain-to-pooled normalized distance was `0.286`.
- The wide-grid case now passes the current loose threshold rule under the
  documented reference controls.

The alpha-gap audit command writes:

- `run_config.csv`: deterministic fixture, prior, and MCMC controls.
- `audit_assessment.csv`: pass/review/fail status by alpha-prior scale.
- `fit_distance_summary.csv`: raw and normalized VB-to-pooled-MCMC distances.
- `chain_stability_summary.csv`: chain-to-pooled normalized distances.
- `alpha_gap_summary.csv`: per-quantile AL constants, true/VB/MCMC intercepts,
  pooled MCMC alpha quantiles, and ordered-intercept gaps.
- `quantile_fit_summary.csv`: empirical hit rates and fitted-vs-true quantile
  summaries by fit and quantile level.
- `provenance.csv`: repo, git, R, and RNG provenance.
- `artifact_manifest.csv`: file sizes and SHA-256 hashes.

Default alpha-gap audit artifact location:

`application/cache/joint_qvp_wide_alpha_gap_audit_20260701/`

Current alpha-gap audit result:

- The no-prior wide reference remains review with
  `alpha_normalized_distance = 7.008`, max alpha gap `25.193`, and chain-spread
  pass `1.153`. This confirms the issue as ordered-intercept drift, not
  single-chain instability.
- Finite weak alpha priors centered at empirical quantiles stabilize the wide
  tail-grid reference.
- The adopted reference control, `alpha_prior_sd = 1`, has pooled max
  normalized distance `0.677`, alpha normalized distance `0.149`, max alpha gap
  `0.348`, chain-spread pass `0.286`, zero crossings, and zero sigma upper-bound
  hits.

## Time-Series Synthetic Suite

The first time-series toy generator has exact conditional quantiles:

`true_q = Z %*% beta(tau) + alpha(tau)`

It supports standardized Gaussian, Student-t, and asymmetric-Laplace
location-scale innovations with AR(1), trend, seasonal, and nonlinear lag
features.

The toy fit-validation command writes:

- `observed_series.csv`, `design_matrix.csv`, and `true_quantiles.csv`: the
  truth-known toy data used for fitting.
- `fit_summary.csv`: compact VB, MCMC, truth-distance, hit-rate, crossing, and
  convergence diagnostics.
- `truth_fit_summary.csv`: per-quantile RMSE/MAE/max-error and hit-rate
  comparisons for truth, VB, and pooled MCMC.
- `readout_truth_summary.csv`: alpha/beta parameter comparisons against known
  readout truth.
- `vb_mcmc_distance_summary.csv`: VB-to-pooled-MCMC distance summary.
- `mcmc_draw_summary.csv`, `crossing_summary.csv`, `objective_diagnostics.csv`,
  and `elbo_terms.csv`: reference-draw, monotonicity, crossing, and final ELBO
  accounting diagnostics.
- `figure_manifest.csv` plus four PNG diagnostics: truth/VB/MCMC fit overlay,
  quantile-error and hit-rate plot, ELBO trace, and MCMC parameter traces.
- `provenance.csv` and `artifact_manifest.csv`.

Default toy fit-validation artifact location:

`application/cache/joint_qvp_ts_toy_fit_validation_20260701/`

Current toy fit-validation result:

- VB converged with objective pass on the default Student-t toy.
- VB and pooled MCMC have zero fitted crossing pairs and finite truth-distance
  summaries.
- The default run records `vb_truth_normalized_qhat_distance = 0.688`,
  `pooled_mcmc_truth_normalized_qhat_distance = 0.928`, and
  `vb_mcmc_max_normalized_distance = 0.515`.
- Tail quantile diagnostics intentionally remain visible in the truth plots;
  this toy is a debugging playground, not a manuscript result.

The first multi-scenario time-series synthetic suite writes combined,
storage-light truth-known artifacts for:

- default Student-t dynamic location-scale;
- Gaussian homoskedastic;
- Student-t heteroskedastic;
- asymmetric-Laplace tail;
- seasonal low-AR Gaussian;
- persistent heavy-tail wide-grid.

Default suite artifact location:

`application/cache/joint_qvp_ts_synthetic_suite_20260701/`

All default suite cases have positive conditional scale and zero true quantile
crossing pairs.

The suite-wide fit-validation command writes:

- `run_config.csv`: scenario definitions plus common VB/MCMC/reference controls.
- `suite_assessment.csv`: per-case implementation, objective, truth-distance,
  hit-rate, VB/MCMC, and overall gate status.
- `suite_fit_summary.csv`: compact VB, pooled-MCMC, truth-distance, hit-rate,
  crossing, chain, and reference-bound diagnostics.
- `truth_fit_summary.csv`: per-quantile truth/VB/pooled-MCMC RMSE, MAE,
  max-error, empirical hit-rate, and hit-rate error.
- `readout_truth_summary.csv`: alpha/beta readout recovery diagnostics against
  the known DGP parameters.
- `vb_mcmc_distance_summary.csv`: raw and normalized VB-to-pooled-MCMC
  distances.
- `chain_summary.csv`: chain-to-pooled normalized distance diagnostics.
- `mcmc_draw_summary.csv`: finite-draw checks and sigma-bound hit fractions.
- `crossing_summary.csv`: raw fitted crossing diagnostics for chains, VB, and
  pooled MCMC.
- `vb_convergence_audit.csv`: VB iteration-attempt audit rows for fixed and
  adaptive max-iteration validation runs.
- `objective_diagnostics.csv` and `elbo_terms.csv`: accounted AL-VB objective
  monitor and final ELBO accounting rows.
- `figure_manifest.csv`: two PNG diagnostics per case: fit overlay and
  quantile-error/hit-rate plot.
- `provenance.csv` and `artifact_manifest.csv`.

Default suite fit-validation artifact location:

`application/cache/joint_qvp_ts_suite_fit_validation_20260701/`

Current suite fit-validation result:

- Six truth-known cases were fit with AL-VB first and VB-initialized AL-MCMC
  second.
- The artifact manifest has 26 rows and all SHA-256 hashes verified.
- Adaptive VB grid: `{180, 360}`.
- Six cases have implementation pass status. `ts_student_t_lscale` needed one
  adaptive retry and converged at iteration 195 under the 360-iteration cap.
- There are no hard-fail rows: all MCMC chains were VB-initialized, all draw
  summaries are finite, all sigma upper-bound hit fractions are zero, and VB
  plus pooled MCMC have zero fitted crossing pairs.
- All six cases pass the provisional truth-distance thresholds:
  `vb_truth_normalized_qhat_distance <= 1.5` and
  `pooled_mcmc_truth_normalized_qhat_distance <= 2.0`.
- All six cases pass the provisional VB/MCMC agreement threshold:
  `vb_mcmc_max_normalized_distance <= 5`.
- Objective, hit-rate, and overall gates pass for all six suite cases.

The repeated-seed threshold calibration command writes:

- `replicated_run_config.csv`: six scenario definitions expanded over five
  calibration seeds plus common VB/MCMC controls.
- `replicated_assessment.csv`: implementation, objective, truth-distance,
  hit-rate, VB/MCMC, and overall status for each repeated fit.
- `replicated_fit_summary.csv`: compact repeated-fit diagnostics with
  objective drop summaries.
- `replicated_vb_convergence_audit.csv`: VB iteration-attempt audit rows for
  fixed and adaptive max-iteration validation runs.
- `replicated_hit_rate_summary.csv`: per-fit, per-tau empirical hit-rate
  errors for truth, VB, and pooled MCMC.
- `threshold_calibration_summary.csv`: global and scenario-level empirical
  quantiles for distance, hit-rate, objective, crossing, and bound-hit metrics.
- `threshold_recommendations.csv`: current threshold rules, observed q95/max
  values, and provisional candidate review thresholds.
- `gate_frequency_summary.csv`: pass/review/fail frequencies by scenario and
  gate type.
- `provenance.csv` and `artifact_manifest.csv`.

Default threshold-calibration artifact location:

`application/cache/joint_qvp_ts_suite_threshold_calibration_20260701/`

Current repeated-seed calibration result:

- 30 replicated fits were run: six scenarios times five seeds.
- The artifact manifest has nine rows and all SHA-256 hashes verified.
- There are no hard-fail rows. All repeated fits have zero VB crossings, zero
  pooled-MCMC crossings, zero sigma upper-bound hit fractions, VB-initialized
  MCMC chains, and finite MCMC draw summaries.
- Adaptive VB grid: `{180, 360, 500}`.
- Implementation status: 29 pass and one review. The only review row is
  `ts_persistent_heavy_tail_rep02_seed20260702`, which reaches the
  500-iteration cap.
- Overall gate status: 29 pass and one review.
- Objective-monitor, truth-distance, hit-rate, and VB/MCMC agreement statuses:
  30 pass.
- Retry counts: 17 rows used no retry, 12 rows used one retry, and one row used
  two retries.
- VB/MCMC agreement status: 30 pass.

Global repeated-seed q95 values:

- VB truth normalized distance: `0.135`.
- Pooled-MCMC truth normalized distance: `0.129`.
- VB/MCMC max normalized distance: `0.130`.
- Chain-to-pooled max normalized distance: `0.104`.
- VB absolute hit-rate error: `0.017`.
- Pooled-MCMC absolute hit-rate error: `0.033`.
- Objective max drop: `0.000`.

Threshold interpretation after repeated-seed calibration:

- Keep hard gates at zero tolerance for fitted crossings and sigma-bound hits.
- Retain the provisional VB truth-distance threshold `1.5` for now.
- Retain the provisional pooled-MCMC truth-distance threshold `2.0`; all
  repeated-seed rows are well below it after the calibrated `kappa = 1`
  regeneration and adaptive VB policy.
- Retain the loose VB/MCMC agreement threshold `5`; all repeated-seed rows are
  below it.
- Objective and hit-rate gates are not active blockers in the current
  regenerated lane.
- The remaining blocker is one implementation/convergence-policy review row,
  not a fit-quality failure.

The targeted deep-MCMC reference command writes:

- `target_selection.csv`: selected repeated-seed cases and target reasons.
- `deep_reference_run_config.csv`: target scenarios plus deep MCMC controls.
- `deep_reference_assessment.csv`: implementation, objective, truth-distance,
  hit-rate, VB/MCMC, and overall status under deeper reference controls.
- `deep_reference_comparison.csv`: shallow calibration metrics, deep reference
  metrics, deltas, and interpretation labels.
- `deep_reference_resolution_summary.csv`: interpretation counts.
- `deep_reference_fit_summary.csv`, `deep_reference_hit_rate_summary.csv`,
  `deep_reference_vb_mcmc_distance_summary.csv`,
  `deep_reference_chain_summary.csv`, `deep_reference_mcmc_draw_summary.csv`,
  and `deep_reference_crossing_summary.csv`.
- `deep_reference_vb_convergence_audit.csv`.
- `objective_diagnostics.csv`, `elbo_terms.csv`, `figure_manifest.csv`,
  `provenance.csv`, and `artifact_manifest.csv`.

Default deep-reference artifact location:

`application/cache/joint_qvp_ts_deep_mcmc_reference_20260701/`

Current targeted deep-MCMC result:

- Four targets were selected from the regenerated repeated-seed calibration
  bundle after the `kappa = 1` calibration decision.
- The artifact manifest has 24 rows and all SHA-256 hashes verified.
- Deep controls used four VB-initialized chains, 300 MCMC iterations, burn 150,
  thin 10, and 60 pooled retained draws per target.
- All deep-reference targets have zero VB crossings, zero pooled-MCMC
  crossings, zero sigma upper-bound hit fractions, finite MCMC draw summaries,
  and VB/MCMC agreement pass status.
- All four deep-reference targets are labeled `deep_reference_stable`.
- Gate status is four `pass`.

Threshold interpretation after targeted deep MCMC:

- Keep hard gates at zero tolerance.
- Keep the provisional VB/MCMC agreement threshold at `5`; all deep targets are
  below it.
- Truth-distance and hit-rate thresholds are no longer the active blockers in
  the regenerated lane.
- Objective-monitor reviews are no longer active in the regenerated
  repeated-seed calibration; objective max drop q95 is `0.000`.
- Deep-reference checks do not add a statistical blocker after the adaptive
  VB policy.

## VB Convergence Audit

Updated: 2026-07-02.

The convergence audit command:

`application/scripts/73_audit_joint_qvp_ts_vb_convergence.R`

uses the regenerated threshold-calibration bundle and reruns only
implementation-review rows over a larger VB iteration grid. The pinned artifact
bundle is:

`application/cache/joint_qvp_ts_vb_convergence_audit_20260702/`

Current result:

- The initial audit selected 13 implementation-review rows and showed that 12
  resolved by a larger iteration grid.
- The suite, calibration, and deep-reference runners now implement adaptive VB
  max-iteration grids and export convergence-audit CSVs.
- After regenerating the validation artifacts, one implementation-review row is
  selected by the standalone audit.
- One row, `ts_persistent_heavy_tail_rep02_seed20260702`, remained at
  `max_iter = 500`.
- The final normalized truth distance is `0.101`.
- The final absolute hit-rate error is `0.017`.

Policy interpretation:

- Most prior `prototype_max_iter` rows were default-control calibration issues,
  not fit-quality failures.
- The remaining unresolved row is an implementation/convergence-policy exception
  because its truth-distance and hit-rate diagnostics are acceptable.
- The next decision is whether to fix that case with a better stopping rule or
  carry it as an explicit prototype limitation.

## Remaining Open Gate

Before manuscript claims or application promotion, reduce or justify the single
remaining `prototype_max_iter` implementation-review row and keep the
`kappa = 1` lane with adaptive VB auditing as the reproducible AL validation
reference.
