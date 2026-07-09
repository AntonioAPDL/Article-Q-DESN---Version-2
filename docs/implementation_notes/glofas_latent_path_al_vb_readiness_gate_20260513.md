# Latent-Path AL-VB Readiness Gate

This note records the article-side readiness workflow for the GloFAS
latent-path ensemble-likelihood application model. The workflow stops before
the full Dec. 25, 2022 fit. Its purpose is to verify the algebra, posterior-draw
prediction contract, input wiring, and computational scale before committing
resources to the large run.

## Model Scope

The active executable model is the AL version of the latent-path discrepancy
calibration model. Historical USGS rows inform the shared quantile readout, and
historical retrospective GloFAS rows inform the sum of the shared readout and
the GloFAS discrepancy readout. Issued GloFAS ensemble members after the cutoff
are likelihood rows for the same GloFAS quantile path. The future USGS path is
treated as latent, because the recursive DESN state for dates after the cutoff
depends on future response lags.

For each posterior draw, the reported reference quantile is defined by the
identity

```text
q_y_draw = q_g_draw - d_g_draw.
```

The current gate validates that identity at the draw level. It does not replace
the future full application fit, and it does not make application claims.

## Gates

1. **Synthetic recovery gate.**
   The script `application/scripts/03_run_latent_path_synthetic_recovery.R`
   simulates from a known AL latent-path model with source-specific scales,
   fits the article-side AL-VB approximation, writes recovery metrics, and
   fails closed if configured tolerances are not met.

2. **Smoke fit gate.**
   The existing smoke configuration
   `application/config/glofas_latent_path_al_vb_dec25_smoke.yaml` runs the
   real input bundle on a deliberately tiny DESN and short horizon. This checks
   recursive future-state construction against the authoritative Dec. 25 input
   bundle and records `discrepancy_feature_strategy = recursive_latent_path` in
   the posterior-draw prediction contract.

3. **Full-specification readiness gate.**
   The configuration
   `application/config/glofas_latent_path_al_vb_dec25_full.yaml` records the
   full median-only AL-VB specification: `D = 2`, `n = (1000, 1000)`,
   `n_tilde = 500`, `m = 360`, `washout = 500`, `tau0 = 1e-6`,
   `rhs_freeze_tau_warmup_iters = 50`, and `max_iter = 200`, with
   `n_draws = 2000`. The profile script
   `application/scripts/03_profile_latent_path_al_vb.R` builds the design and
   performs bounded one-step diagnostics without launching the full VB loop.
   The active VB implementation uses streamed grouped future moments, a
   linearized Delta update for the future USGS path, and first-order Delta
   prediction for posterior-draw quantiles.

4. **Short full-specification pilot gate.**
   The configuration
   `application/config/glofas_latent_path_al_vb_dec25_pilot.yaml` uses the same
   large reservoir, lag structure, covariate-aware reservoir inputs, AL working
   likelihood, and RHS prior as the held full run, but limits VB to five
   iterations and 200 posterior draws. This gate verifies that the full design,
   fit, posterior-draw prediction, and post-fit analysis stages work together
   before any manuscript-scale fit is launched.

5. **Main launch configuration.**
   The configuration
   `application/config/glofas_latent_path_al_vb_dec25_main.yaml` is the
   real Dec. 25 AL-VB launch file. It uses the same design and prior as the
   readiness and pilot configurations, caps VB at 200 iterations, and sets
   `execution.final_launch.enabled: true`. Article-side VB launch configs are
   guarded by a 500-iteration hard cap.

## Commands

Synthetic recovery:

```bash
Rscript application/scripts/03_run_latent_path_synthetic_recovery.R \
  --config application/config/glofas_latent_path_al_vb_synthetic_recovery.yaml \
  --run_id latent_path_synthetic_recovery_$(date +%Y%m%d_%H%M%S)
```

Smoke fit:

```bash
Rscript application/scripts/03_fit_models.R \
  --config application/config/glofas_latent_path_al_vb_dec25_smoke.yaml \
  --run_id latent_path_smoke_fit_$(date +%Y%m%d_%H%M%S)
```

Full-specification input and design readiness:

```bash
Rscript application/scripts/00_check_inputs.R \
  --config application/config/glofas_latent_path_al_vb_dec25_full.yaml

Rscript application/scripts/01_build_panel.R \
  --config application/config/glofas_latent_path_al_vb_dec25_full.yaml

Rscript application/scripts/03_check_model_design.R \
  --config application/config/glofas_latent_path_al_vb_dec25_full.yaml

Rscript application/scripts/03_profile_latent_path_al_vb.R \
  --config application/config/glofas_latent_path_al_vb_dec25_full.yaml \
  --future_laplace true \
  --save_design false
```

Short full-specification pilot:

```bash
RUN_ID=latent_path_fullspec_pilot_fit_$(date +%Y%m%d_%H%M%S)

Rscript application/scripts/00_check_inputs.R \
  --config application/config/glofas_latent_path_al_vb_dec25_pilot.yaml \
  --run_id "$RUN_ID"

Rscript application/scripts/01_build_panel.R \
  --config application/config/glofas_latent_path_al_vb_dec25_pilot.yaml \
  --run_id "$RUN_ID"

Rscript application/scripts/03_fit_models.R \
  --config application/config/glofas_latent_path_al_vb_dec25_pilot.yaml \
  --run_id "$RUN_ID"

Rscript application/scripts/07_post_analysis.R \
  --config application/config/glofas_latent_path_al_vb_dec25_pilot.yaml \
  --run_id "$RUN_ID"
```

The full fit is intentionally withheld:

```bash
# Do not run until the readiness gates are reviewed.
Rscript application/scripts/03_fit_models.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml
```

## Review Criteria Before Full Fit

- The synthetic recovery gate passes and reports finite posterior-draw paths.
- The smoke fit writes posterior-draw predictions with zero draw-identity error.
- The full-specification design check reports the available issued GloFAS
  horizon and confirms whether it is shorter than the requested 30-day horizon.
- The profile output identifies the feature dimension, fixed-row count,
  issued-ensemble row count, moment strategy, future-path update strategy, and
  one-step update cost.
- The design summary is reviewed for the actual feature content. In the current
  full-specification readiness config, `include_input_block: false` means ppt
  and soil are materialized and audited as inputs, but they are not direct
  readout features. The article-side recursive reservoir continuation now
  supports response-lag reservoir inputs and deterministic ppt and soil lagged
  covariates inside the reservoir recursion.
- The streamed profile should show no dense future-row moment allocation. The
  May 14 streamed profile reported a keyed future-builder object of about
  33 MB, streamed row moments of about 408 MB, a theta update of about
  10 seconds, and a linearized Delta future-path update of about 4 seconds.
- A short full-specification pilot should be reviewed before any
  manuscript-scale run because each VB iteration still requires one recursive
  future-builder call.
- The May 14 pilot `latent_path_fullspec_pilot_fit_20260514_214438` completed
  under the previous launch size, with 28 available issued GloFAS target dates,
  200 posterior draws, finite scale draws, numerical-precision draw-identity
  error, and complete 95 percent uncertainty bands in the post-fit
  forecast-window check. Its five VB iterations are intentionally insufficient
  for application inference. After changing the launch size, a new design
  preflight is required before fitting.
- The readiness configuration remains `execution.final_launch.enabled: false`.
  The main launch configuration is the only latent-path AL-VB Dec. 25 config
  with `execution.final_launch.enabled: true`.
