# Joint QDESN simulation main launch audit plan

Date: 2026-07-06

This note records the audit and launch plan for the new joint QDESN simulation study after the article polish, VB-readiness audit, and 12000-length fixture materialization. It is intended to keep the next implementation step reproducible, inspectable, and aligned with the article rather than with the older exploratory joint-QVP calibration lanes.

## Scope

This plan covers only the new QDESN simulation study prepared for the article. It excludes TT500, GloFAS, PriceFM, and the older joint-QVP Phase 4 calibration campaign.

The article-facing model labels are:

- `QDESN RHS` for the asymmetric-Laplace specification.
- `exQDESN RHS` for the extended asymmetric-Laplace specification.
- `JOINT QDESN RHS` for the joint multi-quantile asymmetric-Laplace specification.
- `JOINT exQDESN RHS` for the joint multi-quantile extended asymmetric-Laplace specification.

The next computational step should be an actual VB fit-validation launch over the full prepared fixture set, not another smoke test or pilot.

## Audited State

| Item | Evidence | Status | Diagnosis |
|---|---:|---|---|
| Main branch state | `main...origin/main`, pushed through `2d8807a` | pass | Article and scoped simulation-preparation changes are on the clean main worktree. |
| VB readiness audit | `application/cache/joint_qdesn_simulation_vb_readiness_audit_20260706` | review | All four model families produce finite outputs. The review gate is caused by intentionally bounded `vb_max_iter = 8`, not by finiteness, crossing, or implementation failures. |
| Readiness crossings | raw = 0, contract = 0 for all four model families | pass | No immediate evidence that the new model labels or wrappers introduce crossing failures. |
| Fixture materialization | `application/cache/joint_qdesn_simulation_dgp_fixtures_20260706` | pass | The 12000-length fixture layer exists and is complete. |
| Fixture validation | 73 pass, 0 review, 0 fail | pass | Registry schema, split geometry, finite observations/design/truth, positive scale, monotone true quantiles, and forecast-origin plans all pass. |
| Scenario coverage | 9 scenarios | pass | Three bridge DGPs and six stress DGPs are available with analytic or numerical oracle quantiles. |
| Observed rows | 108000 | pass | Nine scenarios times 12000 simulated rows. |
| Forecast-origin rows | 297 | pass | Thirty-three validation origins per scenario, with origin stride 30 and lead range 1 to 30. |
| Dense VB feasibility | max `K * p = 56` | pass | Current fixtures are safely below the dense prototype guard used by the existing VB engines. |
| MCMC readiness | not launched | planned | MCMC should wait until VB fit and forecast behavior are stable, because MCMC will be initialized from VB. |

## Deep Diagnosis

### 1. The fixture layer is ready for article-scale VB work

The fixture generator has already materialized the intended long series design:

- `simulated_length = 12000`
- `dgp_warmup_length = 2000`
- `effective_length = 10000`
- `analysis_window_length = 2000`
- `desn_washout_length = 500`
- `fit_length = 500`
- `validation_length = 1000`
- `forecast_origin_stride = 30`
- `max_lead = 30`

The validation table reports only `pass` statuses. This is the strongest reason not to redesign the DGP layer now. The next risk is not data generation. The next risk is whether the VB estimation layer can recover stable fitted and forecast quantiles across the full scenario set.

### 2. VB fit validation should precede forecast validation

Forecast validation combines several sources of variation: estimation error, multi-step target dynamics, no-refit forecast design, tail behavior, and scoring noise. A fit-only validation launch isolates the estimation layer on the declared 500-row fit window. This gives a cleaner diagnostic for:

- finite fitted quantiles;
- raw and contract crossing behavior;
- distance to true conditional quantiles;
- check loss and CRPS-grid summaries;
- RHS prior behavior;
- VB convergence and objective traces;
- runtime by model and scenario.

Launching forecast validation first would make it harder to tell whether a failure is caused by estimation, by the held-out dynamics, by the no-refit forecast protocol, or by score aggregation.

### 3. The current dense VB engines are acceptable for this prepared registry

The existing AL and exAL VB implementations use dense posterior updates for the coefficient block. This would be a limitation for a large reservoir-feature design, but it is acceptable for the current registry because:

- `K = 7` quantile levels;
- `p` ranges from 5 to 8;
- the largest joint coefficient dimension is `K * p = 56`;
- the local guard default is far above this size.

The next runner should nevertheless assert this dimension contract explicitly and fail early if a future registry silently increases `K * p` beyond the validated range.

### 4. The raw/contract noncrossing policy should be retained

The article should not hide raw model behavior, but scoring should use a declared noncrossing output contract. The correct design is:

- preserve raw fitted or forecast quantiles;
- apply the monotone rearrangement/synthesis contract before scoring;
- score contract quantiles;
- report raw crossing and adjustment diagnostics;
- hard-fail only if contract quantiles still cross;
- review, not fail, if raw outputs require large or frequent adjustment.

This keeps the study honest while preventing a small adjacent-tail raw crossing from invalidating otherwise well-defined quantile scores.

### 5. Metrics should be lean and aligned with the article

The main simulation evidence should not duplicate WIS and CRPS if the article is using the integrated quantile representation of CRPS. The primary validation metrics should be:

- check loss by scenario, model, and quantile;
- CRPS-grid approximation from the quantile scores;
- truth-distance summaries against oracle conditional quantiles, including MAE, RMSE, and bias;
- empirical hit rates and hit-rate errors;
- central interval coverage, interval width, and interval score where paired quantiles exist;
- crossing and monotone-adjustment diagnostics;
- VB convergence, objective, RHS prior, and runtime summaries.

WIS can remain out of the main article tables unless there is a specific appendix reason to include it.

### 6. Forecast validation should use the requested no-refit protocol

For this article simulation, the forecast study should mimic the established univariate QDESN simulation structure more closely than the older joint-QVP rolling refit campaign:

- fit once on the declared 500-row fit window after DESN washout;
- use validation origins spaced every 30 observations;
- score leads 1 to 30;
- do not refit at each origin;
- compare forecasts with observed validation rows and oracle conditional quantiles;
- preserve the full 12000-row source series and all split metadata.

This design is easier to explain, cheaper to run, and closer to the simulation goal: determine whether the joint and independent QDESN variants can recover and forecast multi-quantile dynamics under known DGPs.

### 7. MCMC should be delayed until VB is stable

MCMC is needed for the simulation study, but it should not be the next launch. The correct ordering is:

1. complete and audit VB fit validation;
2. complete and audit VB forecast validation;
3. freeze the VB configuration used to initialize MCMC;
4. run MCMC references, starting with selected scenarios and then expanding if runtime permits.

This avoids spending MCMC time on a configuration that may still need VB-control or design adjustments.

## Recommended Launch Sequence

### Step A. Freeze and verify source artifacts

Use the existing fixture artifact:

`application/cache/joint_qdesn_simulation_dgp_fixtures_20260706`

The next implementation should add a small loader/hash verifier that checks:

- artifact manifest completeness;
- registry copy and scenario summary;
- observed series, design matrix, true quantile tables, split metadata, and forecast-origin plan;
- no missing or duplicated scenario ids;
- finite rows and monotone true quantiles;
- expected fit and validation lengths.

### Step B. Implement the VB fit-validation runner

Add a focused runner, for example:

- `application/R/joint_qdesn_simulation_fit_validation.R`
- `application/scripts/99_run_joint_qdesn_simulation_vb_fit_validation.R`
- `application/tests/test_joint_qdesn_simulation_fit_validation.R`

The runner should fit all four VB model families over all nine scenarios:

- `JOINT QDESN RHS`
- `JOINT exQDESN RHS`
- `QDESN RHS`
- `exQDESN RHS`

Required fit artifacts:

- `run_config.csv`
- `fixture_source_manifest.csv`
- `model_fit_summary.csv`
- `fit_quantiles_raw.csv`
- `fit_quantiles.csv`
- `fit_monotone_adjustment.csv`
- `fit_truth_comparison.csv`
- `check_loss_summary.csv`
- `crps_grid_summary.csv`
- `hit_rate_summary.csv`
- `interval_summary.csv`
- `crossing_summary.csv`
- `raw_crossing_summary.csv`
- `vb_convergence_audit.csv`
- `objective_diagnostics.csv`
- `rhs_prior_summary.csv`
- `runtime_summary.csv`
- `fit_validation_assessment.csv`
- `provenance.csv`
- `artifact_manifest.csv`
- `README.md`

Recommended actual launch controls:

```bash
Rscript application/scripts/99_run_joint_qdesn_simulation_vb_fit_validation.R \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --output-dir application/cache/joint_qdesn_simulation_vb_fit_validation_article_20260706 \
  --vb-max-iter 240 \
  --adaptive-vb-max-iter-grid 240,480 \
  --rhs-vb-inner 5 \
  --tau0 1
```

The exact controls may be adjusted only if the runner records the change in `run_config.csv` and the documentation.

### Step C. Audit VB fit validation before forecasting

Add a fit audit script only if the runner outputs are not already sufficient:

- `application/scripts/100_audit_joint_qdesn_simulation_vb_fit_validation.R`

The audit should decide whether each model-scenario pair is:

- `pass`: finite contract quantiles, no contract crossing, valid scores, and acceptable convergence diagnostics;
- `review`: finite outputs with max-iteration, large raw adjustment, or model-specific score instability;
- `fail`: missing hashes, malformed splits, nonfinite outputs, leakage, or contract crossings.

No forecast launch should be treated as article evidence until this fit audit is complete.

### Step D. Implement the no-refit VB forecast-validation runner

After fit validation, add:

- `application/R/joint_qdesn_simulation_forecast_validation.R`
- `application/scripts/101_run_joint_qdesn_simulation_vb_forecast_validation.R`
- `application/tests/test_joint_qdesn_simulation_forecast_validation.R`

The runner should:

- load the frozen fixtures and verified fit configuration;
- fit each scenario-model once on the fit window;
- forecast all declared validation origin and lead pairs;
- never use future validation observations in the fit;
- score contract forecast quantiles;
- preserve raw forecast quantiles and monotone adjustment diagnostics.

Required forecast artifacts:

- `run_config.csv`
- `fixture_source_manifest.csv`
- `forecast_origin_plan.csv`
- `forecast_quantiles_raw.csv`
- `forecast_quantiles.csv`
- `forecast_monotone_adjustment.csv`
- `forecast_truth_comparison.csv`
- `check_loss_summary.csv`
- `crps_grid_summary.csv`
- `hit_rate_summary.csv`
- `interval_summary.csv`
- `crossing_summary.csv`
- `raw_crossing_summary.csv`
- `vb_convergence_audit.csv`
- `runtime_summary.csv`
- `forecast_validation_assessment.csv`
- `provenance.csv`
- `artifact_manifest.csv`
- `README.md`

### Step E. Prepare article tables and figures only after the VB audits pass

The article-facing tables should be generated from frozen artifacts, not from ad hoc interactive runs. The first article table layer should summarize:

- scenario class and family;
- model label;
- check loss;
- CRPS-grid;
- truth RMSE or MAE;
- hit-rate error;
- interval coverage error;
- raw adjustment rate;
- VB convergence status.

Figures should show representative scenarios only, with observed data, true quantiles, fitted or forecast contract quantiles, and clear markers for any raw crossing events or adjustment-heavy regions.

### Step F. Add MCMC after VB fit and forecast are stable

The MCMC stage should initialize from the frozen VB outputs. It should start with selected representative and stress scenarios, then expand if runtime and diagnostics are acceptable. The MCMC layer should write separate artifacts and should not overwrite the VB evidence.

## Gates

Hard fail:

- missing or incomplete artifact manifests;
- malformed registry, split metadata, or forecast-origin plan;
- nonfinite observations, features, true quantiles, fitted quantiles, forecasts, or scores;
- train-validation leakage;
- nonpositive fitted scale paths;
- contract quantile crossings;
- missing provenance.

Review:

- VB reaches max iterations but outputs are finite;
- raw quantiles require frequent or large monotone adjustment;
- model-scenario scores are unstable relative to the rest of the scenario class;
- runtime outliers threaten MCMC feasibility;
- dense dimension approaches the validated guard.

Pass:

- source artifacts verify;
- outputs are finite;
- contract quantiles are noncrossing;
- scores and diagnostics are complete;
- no leakage is detected;
- convergence and runtime are acceptable or explicitly documented as review-level.

## Tests Required Before Launch Evidence Is Trusted

Fit-validation tests:

- fixture loader verifies hashes and required files;
- fit split uses exactly the 500 fit rows and excludes validation rows;
- all four model families run on a reduced deterministic test fixture;
- raw and contract fitted quantiles are written;
- scoring uses contract fitted quantiles;
- artifact manifest hashes are complete.

Forecast-validation tests:

- forecast origin and lead rows align with `forecast_origin_plan.csv`;
- no validation observation enters the fit;
- forecast quantiles are finite and noncrossing after the contract step;
- raw crossing diagnostics are preserved;
- check loss, CRPS-grid, hit-rate, interval, and truth-distance summaries are finite;
- artifact manifest hashes are complete.

Adjacent tests that should continue to pass:

```bash
Rscript application/tests/test_joint_qdesn_simulation_vb_readiness.R
Rscript application/tests/test_joint_qdesn_simulation_dgp_fixtures.R
```

## Next Best Action

Implement Step B and immediately launch the article-scale VB fit-validation run over the frozen fixture directory. This is the optimal next move because the fixture layer has passed, the only readiness review is due to deliberately tiny VB iterations, and forecast validation should not be interpreted until fit recovery is understood.

Once Step B is complete and audited, move to the no-refit VB forecast-validation runner. MCMC should remain deferred until both VB fit and forecast validation are stable enough to provide reliable initialization.
