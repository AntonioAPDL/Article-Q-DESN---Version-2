# Joint QDESN post-VB validation audit and next-stage plan

Date: 2026-07-06

This note upgrades the immediate health-check plan after the completed article-scale VB fit and no-refit forecast validation run. It records the audit evidence, diagnoses the observed review flags, compares plausible next actions, and defines the recommended reproducible implementation path.

## Scope

This plan is scoped to the new joint QDESN simulation study. It does not touch TT500, GloFAS, PriceFM, or the older joint-QVP calibration lanes.

Primary artifact directories:

- Fit validation: `application/cache/joint_qdesn_simulation_vb_fit_validation_article_20260706`
- Forecast validation: `application/cache/joint_qdesn_simulation_vb_forecast_validation_article_20260706`
- Completed health report: `application/cache/joint_qdesn_simulation_article_vb_fit_forecast_health_20260706.md`

The code used for the launch is pushed on `main` at commit `a092792`.

## Compact Audit Summary

| Topic | Evidence | Status | Diagnosis |
|---|---:|---|---|
| Source state | `main...origin/main`, commit `a092792` | pass | Code and article-prep validation layer are clean and pushed. |
| Launch completion | 2026-07-06T16:14:02 to 2026-07-06T17:05:29 | pass | Fit and forecast both completed. |
| Fit artifact integrity | 21 files, all present, SHA-256 verified, about 149.5 MB | pass | Fit artifacts are reproducible and inspectable. |
| Forecast artifact integrity | 21 files, all present, SHA-256 verified, about 334.0 MB | pass | Forecast artifacts are reproducible and inspectable. |
| Fit gates | 1 pass, 35 review, 0 fail | review | No hard failures, but review gates need diagnosis. |
| Forecast gates | 1 pass, 35 review, 0 fail | review | Same review pattern as fit. |
| Contract crossings | 0 fit, 0 forecast | pass | The noncrossing scoring contract works. |
| Raw crossings | 528 fit, 1263 forecast | review | Dominated by independent `exQDESN RHS` on `asymmetric_laplace_tail`. |
| VB traces | 36/36 finite in fit and forecast | pass | No nonfinite trace failure. |
| VB max iteration | 34/36 reached 480 iterations | review | Need convergence-readiness audit before changing gates. |
| Objective status | 36/36 finite in fit and forecast | pass | Objective/accounting diagnostics are finite. |

## Model-Level Evidence

Forecast-level model means:

| Model | Truth MAE | Truth RMSE | Check Loss | CRPS Grid | Mean Hit Error | Interval Score | Interpretation |
|---|---:|---:|---:|---:|---:|---:|---|
| `JOINT QDESN RHS` | 0.103 | 0.125 | 0.161 | 0.369 | 0.021 | 2.538 | Best all-around article candidate. |
| `QDESN RHS` | 0.104 | 0.127 | 0.161 | 0.368 | 0.018 | 2.549 | Strong independent comparator, but more raw repairs. |
| `JOINT exQDESN RHS` | 0.155 | 0.169 | 0.163 | 0.371 | 0.039 | 2.615 | Stable, but less accurate than AL in this run. |
| `exQDESN RHS` | 58.502 | 58.829 | 19.417 | 55.303 | 0.062 | 165.976 | Dominated by one severe independent exAL failure. |

When the `asymmetric_laplace_tail` scenario is excluded, independent `exQDESN RHS` has forecast truth MAE about 0.152 and check loss about 0.166, close to `JOINT exQDESN RHS`. This means the failure is highly localized rather than a global exAL failure.

## Failure Diagnosis

### Independent exAL asymmetric-tail failure

The severe pathology is concentrated in:

- model: `exQDESN RHS`;
- scenario: `asymmetric_laplace_tail`;
- quantile: especially `tau = 0.75`;
- fit structure: independent single-quantile exAL.

Fit evidence:

- raw crossing pairs: 500;
- max monotone adjustment: about 2537;
- adjustment rate: about 0.714;
- `tau = 0.75` raw fitted quantiles average about -2724;
- contract quantiles for tau 0.05 through 0.75 collapse to about -544 on average;
- fit truth MAE for the scenario-model pair is about 389.

Forecast evidence:

- raw crossing pairs: 1008;
- max monotone adjustment: about 3673;
- adjustment rate: about 0.719;
- `tau = 0.75` raw forecasts average about -3675;
- contract quantiles for tau 0.05 through 0.75 collapse to about -735 on average;
- forecast truth MAE for the scenario-model pair is about 525.

The joint exAL model on the same DGP does not fail. The independent AL model on the same DGP does not fail severely. Therefore the leading explanation is a K=1 exAL update or initialization instability at an interior upper quantile, not a DGP/oracle problem and not a joint-readout failure.

### VB convergence reviews

The review gate is also dominated by max-iteration flags:

- 34 of 36 model-scenario fits reached the 480-iteration cap in both fit and forecast validation;
- all traces are finite;
- all objective summaries are finite;
- the forecast and fit convergence tables are identical because the forecast runner fits once on the same fit window, then applies the no-refit forecast protocol.

This means a convergence-readiness audit can be targeted to the fit stage. It does not require a new full forecast launch.

Current objective summaries are finite but insufficient to decide whether max-iteration rows are unstable or simply failing an overly strict absolute beta-change threshold. We need tail-of-trace and parameter-change diagnostics before changing gate semantics.

## Alternatives Considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| Relaunch all models with more VB iterations | Simple and brute-force | Expensive, unlikely to address the isolated exAL pathology directly, delays article evidence | Not optimal now. |
| Drop all exAL variants immediately | Simplifies article | Too aggressive; `JOINT exQDESN RHS` is stable and independent exAL is normal outside one DGP | Not optimal. |
| Proceed directly to MCMC | Could provide stronger posterior evidence | MCMC would inherit unresolved VB initialization/failure issues, especially independent exAL | Defer. |
| Build article tables immediately | Fast article progress | Risks including an unstable comparator and unexamined max-iteration reviews | Not yet. |
| Target independent exAL failure plus convergence audit | Focused, reproducible, answers actual blockers | Requires modest new audit tooling | Recommended. |

## Recommended Next Stage

The optimal next stage is a targeted post-VB validation audit, not a broad relaunch.

### Stage 1. Freeze and index the completed VB evidence

Add a small audit script, for example:

`application/scripts/102_audit_joint_qdesn_simulation_vb_fit_forecast_outputs.R`

Required outputs:

- `validation_health_summary.csv`
- `model_metric_summary.csv`
- `scenario_metric_summary.csv`
- `raw_contract_adjustment_summary.csv`
- `vb_convergence_summary.csv`
- `artifact_manifest_verification.csv`
- `article_candidate_model_ranking.csv`
- `README.md`
- `artifact_manifest.csv`

Purpose:

- preserve the fit and forecast evidence in compact, article-facing audit tables;
- verify manifests from both artifact directories;
- make the model ranking reproducible without re-reading hundreds of MB of quantile rows manually.

Gate language:

- `pass` for artifact integrity and contract noncrossing;
- `review` for max-iteration rows and raw-adjustment rows;
- `fail` only for missing hashes, nonfinite outputs, leakage, or contract crossings.

### Stage 2. Target independent exAL failure

Add a targeted diagnostic runner, for example:

`application/scripts/103_diagnose_joint_qdesn_independent_exal_tail_failure.R`

Scope:

- scenario: `asymmetric_laplace_tail`;
- model: `exQDESN RHS`;
- primary tau: `0.75`;
- neighboring tau checks: `0.70`, `0.80`, and the existing grid values;
- compare against `QDESN RHS` K=1 AL and `JOINT exQDESN RHS`.

Diagnostics to export:

- `targeted_run_config.csv`
- `tau_specific_fit_summary.csv`
- `alpha_gamma_sigma_path_summary.csv`
- `beta_norm_summary.csv`
- `raw_contract_quantile_summary.csv`
- `hit_truth_score_summary.csv`
- `exal_failure_assessment.csv`
- `README.md`
- `artifact_manifest.csv`

Minimum checks:

- AL initialization at `tau = 0.75`;
- exAL gamma support and final gamma;
- alpha update magnitude and sign;
- sigma path and lower-bound behavior;
- beta norm and fitted-no-alpha range;
- raw qhat range before contract;
- effect of stronger alpha prior;
- effect of sigma floor or damping if supported;
- effect of using joint exAL initialization if feasible.

Decision rule:

- If a small stabilizing modification fixes the K=1 exAL failure without harming other scenarios, keep independent `exQDESN RHS` as a main comparator.
- If the failure is intrinsic to the current independent exAL approximation, demote independent `exQDESN RHS` to an appendix/diagnostic comparator and disclose the reason.

### Stage 3. Target convergence-readiness

Add a convergence audit runner, for example:

`application/scripts/104_audit_joint_qdesn_vb_convergence_readiness.R`

Do not rerun the full forecast study. Use a small representative subset:

- `normal_bridge`;
- `asymmetric_laplace_tail`;
- `persistent_heavy_tail`;
- `nonlinear_reservoir_friendly`.

Models:

- `JOINT QDESN RHS`;
- `QDESN RHS`;
- `JOINT exQDESN RHS`;
- optionally exclude independent `exQDESN RHS` until Stage 2 is diagnosed.

Controls:

- compare `480`, `720`, and `960` max iterations;
- keep `rhs_vb_inner = 5` initially;
- optionally test `rhs_vb_inner = 8` for one scenario if needed;
- export tail-of-trace summaries and final fitted quantile deltas.

Required outputs:

- `convergence_run_config.csv`
- `trace_tail_summary.csv`
- `parameter_delta_summary.csv`
- `score_delta_summary.csv`
- `raw_adjustment_delta_summary.csv`
- `runtime_delta_summary.csv`
- `convergence_gate_recommendation.csv`
- `README.md`
- `artifact_manifest.csv`

Decision rule:

- If score changes from 480 to 960 are negligible and traces are finite, keep rows as `review` in internal diagnostics but allow article tables with a note.
- If scores or quantiles move materially after 480, increase the production VB controls before article tables.

### Stage 4. Prepare article evidence pack

After Stages 1 to 3, add an article evidence script:

`application/scripts/105_prepare_joint_qdesn_article_validation_tables_figures.R`

Recommended main table:

- primary rows: `JOINT QDESN RHS`, `QDESN RHS`, `JOINT exQDESN RHS`;
- include independent `exQDESN RHS` only if Stage 2 stabilizes it;
- report fit and forecast separately;
- use forecast truth MAE/RMSE, check loss, CRPS-grid, hit error, interval coverage error, raw adjustment rate, and runtime.

Recommended figures:

- observed data, true quantiles, and `JOINT QDESN RHS` forecast quantiles for one bridge and two stress scenarios;
- comparison heatmap of forecast truth MAE by scenario/model;
- raw crossing count and maximum adjustment by scenario/model;
- independent exAL failure figure for `asymmetric_laplace_tail`;
- convergence/runtimes by model.

### Stage 5. MCMC after VB readiness is resolved

MCMC should remain deferred until:

- `JOINT QDESN RHS` and `QDESN RHS` article tables are stable;
- `JOINT exQDESN RHS` is either retained or demoted based on forecast evidence;
- independent `exQDESN RHS` is fixed or explicitly excluded from the main comparison.

Initial MCMC path:

1. run selected MCMC references for `JOINT QDESN RHS` and `QDESN RHS`;
2. add `JOINT exQDESN RHS` if the exAL story remains scientifically useful;
3. only revisit independent `exQDESN RHS` after Stage 2.

## Definition of Done for the Next Implementation Stage

The next implementation stage is complete when:

- completed fit/forecast artifacts have a compact audit directory with verified hashes;
- the independent exAL `asymmetric_laplace_tail` failure has a targeted diagnosis;
- the convergence gate has a concrete recommendation based on 480/720/960 evidence;
- article candidate models are ranked with reproducible CSV summaries;
- the article table/figure preparation inputs are frozen;
- no MCMC launch is started until the above is resolved.

## Recommended Immediate Command Sequence

The next Codex implementation prompt should request:

1. implement `102_audit_joint_qdesn_simulation_vb_fit_forecast_outputs.R`;
2. implement `103_diagnose_joint_qdesn_independent_exal_tail_failure.R`;
3. implement `104_audit_joint_qdesn_vb_convergence_readiness.R`;
4. run these targeted audits;
5. write an updated implementation note with artifact locations, gate outcomes, and article-table recommendations.

Do not launch a full rerun and do not launch MCMC in the next step.
