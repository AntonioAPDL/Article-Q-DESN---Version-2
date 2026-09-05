# GloFAS Part 3 Quantile And Forecast Execution

## Scope

This implementation completes the executable Part 3 historical bridge after
the Normal ridge and Normal RHS/VB fits. It adds independent and joint AL/exAL
RHS/VB fits and fixed-origin forecasts for every Part 3 model family. It does
not add a screen, synthesis, rolling-origin evaluation, forecast ensembles, or
Part 4 behavior.

The paired model is

```text
USGS_t                = R_t beta_tau                         + error
retrospective_GloFAS_t = R_t beta_tau + D_t alpha_tau        + error
```

with historical discrepancy `retrospective_GloFAS-USGS`. The reference design
comes from the frozen Part 1 winner and the discrepancy design from the frozen
Part 2 winner. They retain separate reservoirs, seeds, readout intercepts, and
regularized-horseshoe states.

## Implementation Surface

| File | Responsibility |
|---|---|
| `application/R/glofas_part3_partitioned_rhs.R` | Separate component RHS states and joint anchor/difference precision terms |
| `application/R/glofas_part3_quantile_bridge.R` | Independent/joint AL and structured-exAL block CAVI, scores, traces, coefficients |
| `application/R/glofas_part3_historical_forecast.R` | Fixed-origin preparation, Normal posterior and quantile recursion, scoring, artifacts |
| `application/src/glofas_part3_two_component_forecast.cpp` | D=1 two-reservoir recursive forecast backend |
| `application/scripts/72_prepare_glofas_part3_quantile_forecast_runtime.R` | Frozen design cache and Normal-fit SHA preflight |
| `application/scripts/73_run_glofas_part3_normal_forecast.R` | Retained Normal ridge/RHS forecast worker |
| `application/scripts/74_run_glofas_part3_quantile_fit_forecast.R` | Quantile fit then forecast worker |
| `application/scripts/75_prepare_glofas_part3_quantile_forecast_chain.py` | Exact 18-job manifest and dependency DAG |
| `application/scripts/76_launch_glofas_part3_quantile_forecast_chain.py` | Restartable one-thread tmux scheduler |
| `application/scripts/77_check_glofas_part3_quantile_forecast_chain.py` | Machine-readable health report |

## Inference Contract

The coefficient posterior is mean-field by component and quantile. Reference
updates condition on the current discrepancy contribution and use both paired
source rows. Discrepancy updates condition on the new reference contribution
and use GloFAS rows. This is block CAVI for the existing stacked likelihood and
avoids a single dense covariance over the combined 5,502-dimensional readout.

Both component blocks use their own leading intercept exemption and RHS prior.
For joint fits, the first quantile coefficient vector is the anchor and
successive vectors are shrunk through adjacent differences. exAL uses the
structured conditional `VB1_structured_v` scale/shape update. Traces call the
reported scalar a coordinate monitor; they do not misrepresent it as a complete
ELBO.

Production controls are `max_iter=100`, `min_iter=30`, `tol=0.01`, five RHS
inner updates, and per-iteration progress logs. Quantiles are
`0.05,0.20,0.35,0.50,0.65,0.80,0.95`.

## Initialization DAG

```text
Normal RHS -> AL .50
AL .50 -> AL .35 -> AL .20 -> AL .05
AL .50 -> AL .65 -> AL .80 -> AL .95
AL tau -> exAL same tau
all independent AL -> joint AL
all independent exAL -> joint exAL
```

The seven independent fits initialize joint coefficient and scale moments. The
joint difference-prior states are reconstructed from those moments because an
independent coefficient prior is not the same random object as an adjacent
difference prior.

## Forecast Contract

Forecasts are fixed-origin 30-day historical diagnostics with realized
PRISM/ERA5 covariates. No future response value enters an input. Normal
forecasts draw the full combined coefficient vector, generate separate USGS and
GloFAS observation errors, and recursively feed generated USGS and generated
`GloFAS-USGS` into their respective reservoirs. Quantile forecasts recursively
feed the raw reference and discrepancy quantile paths. Repaired quantiles are
never fed back.

The C++ backend is compared against an R reference implementation. Part 3 does
not use CEFS/GEFS, forecast ensembles, rolling origin, or quantile synthesis.

## Runtime Contract

The continuation runtime is separate from the completed Normal runtime. The
preparer verifies the Normal completion markers and fit hashes, builds the
two-component design once, and writes a hashed cache. Every worker verifies the
cache and initializer artifacts. The scheduler uses one thread per job,
dependency `.completed` markers, unique tmux sessions, and fail-closed stale or
failed states.

The continuation has 18 jobs: two retained-fit Normal forecasts, seven
independent AL fit/forecasts, seven independent exAL fit/forecasts, joint AL
fit/forecast, and joint exAL fit/forecast. Runtime artifacts remain ignored.
Each job writes machine-readable paths/scores and a three-panel PDF showing the
last 200 historical observations plus the fixed-origin reference, GloFAS, and
discrepancy forecast paths.

## Validation

Focused tests cover RHS partitioning, slab initialization, independent AL,
structured exAL, joint AL, score semantics, C++/R equivalence for Normal and
quantile recursion, discrepancy sign identity, and the complete scheduler DAG.
An actual-data two-day Normal forecast and reduced-iteration AL median canary
remain mandatory on the execution host before the production scheduler starts.

## Jerez Execution Handoff

Run this continuation from a new dedicated Jerez worktree at the exact task
branch commit. Do not change the active worktree that produced the Part 2
forecast chain and Part 3 Normal fits.

The read-only prerequisites are expected at:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_part2_rhs_jerez_20260904/
  local_trackers/runtime_configs/glofas_part3_normal_historical_jerez_20260904
```

That runtime must contain completed `normal_ridge_joint` and
`normal_rhs_vb_joint` jobs, their fit objects, their SHA-backed execution
contracts, and `configs/part3_frozen_g1_g2_winners.csv`. Preparation fails
closed until all of those conditions hold.

From the new Jerez worktree, run the focused tests listed above and then prepare
the continuation:

```bash
Rscript application/scripts/72_prepare_glofas_part3_quantile_forecast_runtime.R \
  --base_config "$BASE_CONFIG" \
  --winner_manifest "$WINNERS" \
  --normal_runtime_root "$NORMAL_ROOT" \
  --runtime_root "$RUN_ROOT" \
  --horizon_days 30
```

Before production, use scripts 73 and 74 in a separate smoke runtime for a
two-day, eight-draw retained Normal RHS forecast and a two-iteration independent
AL median fit/forecast. Require the C++ backend and do not reuse the smoke fit.

Prepare and launch the production DAG only after both canaries pass:

```bash
python3 application/scripts/75_prepare_glofas_part3_quantile_forecast_chain.py \
  --repo-root "$CODE_WT" \
  --runtime-root "$RUN_ROOT" \
  --max-iter 100 \
  --min-iter 30 \
  --tol 0.01 \
  --horizon-days 30 \
  --normal-draws 500 \
  --forecast-backend cpp

python3 application/scripts/76_launch_glofas_part3_quantile_forecast_chain.py \
  --runtime-root "$RUN_ROOT" \
  --workers 20 \
  --poll-seconds 60 \
  --session-prefix glofas_p3_qf_jerez_20260904 \
  --background
```

Monitor with script 77 using the same runtime root and session prefix. Declare
the Jerez result ready for Muscat import only at 18/18 completed, zero failed,
zero running, and zero pending, after auditing every initializer, fit, forecast,
trace, execution contract, date window, and SHA256. Package all scientific fit
and forecast deliverables, but exclude the reconstructible heavy design cache
and never track runtime outputs in Git.
