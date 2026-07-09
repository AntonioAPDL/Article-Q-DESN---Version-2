# Latent-Path VB Structure Profile

Date: 2026-05-14

## Purpose

This note records the prelaunch profiling evidence for the covariate-aware
latent-path AL-VB application profile. The goal is to decide whether the
current full-covariance VB implementation is an acceptable development target
for the manuscript-scale Dec. 25, 2022 run.

The profile is a gate, not a model result. It does not fit the application
model and it should not be cited as forecast performance evidence.

## Active Profile

Configuration:

```text
application/config/glofas_latent_path_al_vb_dec25_full.yaml
```

Original safe profile run:

```text
application/runs/latent_path_covaware_full_vb_safe_profile_20260514
```

Streamed profile run after the structural update:

```text
application/runs/latent_path_covaware_full_vb_streamed_delta_profile_20260514_034018
```

The run used the covariate-aware latent-path design:

- response lags in the reservoir input: 180;
- ppt and soil lagged covariates in the reservoir input: 122;
- direct readout input block: disabled;
- base readout features: 1001;
- augmented discrepancy features: 2002;
- fixed likelihood rows: 24990;
- future USGS latent dates: 28;
- issued GloFAS likelihood rows: 1428;
- horizon scope: available issued GloFAS horizon, not the requested 30-day
  horizon.

## Measured Timings

The safe profile writes the following tables:

```text
tables/latent_path_profile_steps.csv
tables/latent_path_profile_object_sizes.csv
tables/latent_path_profile_summary.csv
tables/latent_path_vb_structure_assessment.csv
```

For the original safe profile run:

- building the full covariate-aware latent-path design took about 412 seconds;
- building the initial future design and analytic Jacobians took about
  129 seconds;
- the total safe profile time before the dense VB moment gate was about
  541 seconds;
- the retained design object was about 922 MB;
- the initial future-builder object was about 653 MB.

These timings are acceptable for a prelaunch gate, but they are too large to
repeat casually inside high-level workflow checks.

For the streamed profile run:

- building the full covariate-aware latent-path design took about 406 seconds;
- building the initial future design and analytic Jacobians took about
  132 seconds;
- streamed row moments took about 136 seconds and did not increase RSS;
- one theta update took about 10 seconds and increased RSS by about 61 MB;
- the linearized Delta future-path update took about 4 seconds;
- the retained design object was about 922 MB;
- the keyed future-builder object was about 33 MB, rather than the earlier
  expanded future-builder object of about 653 MB.

## Dense Full-Covariance Cost

The current full-covariance VB moment representation uses a dense
`p x p` second-moment matrix for each future likelihood row, where
`p = 2002` for the augmented discrepancy readout.

The safe profile estimates:

- one dense `p x p` covariance or second-moment matrix: about 30.6 MB;
- all future-row dense second moments: about 44.5 GB;
- fixed historical design matrix: about 381.7 MB;
- future latent-path covariance matrix: negligible at this horizon.

An earlier forced heavy profile was stopped after about 30 minutes. Its process
resident memory reached roughly 60 GB before final profile tables were written.
This confirmed the structural estimate: the bottleneck is not the recursive
state continuation itself, but the dense future-row second-moment storage and
the downstream dense theta update.

## Implementation Decision

Do not use the dense future-row moment implementation for manuscript-scale
latent-path AL-VB fits.

The active implementation uses:

- keyed future-builder output for horizon-level GloFAS design and Jacobian
  objects;
- streamed grouped future moments for the theta, mixture, scale, and objective
  updates;
- a local linearized Delta Gaussian update for the future USGS path, avoiding
  numerical-gradient BFGS over repeated recursive DESN rebuilds;
- first-order Delta prediction for posterior-draw quantiles, avoiding one
  recursive DESN rebuild per posterior draw.

The streamed profile confirms that dense future-row moment storage is no longer
the limiting memory problem. The remaining computational cost is the recursive
future-builder call, which is needed once per VB iteration under the current
linearized Delta update. The short full-specification pilot
`latent_path_fullspec_pilot_fit_20260514_214438` exercised this path under the
previous launch size while keeping the manuscript-scale launch disabled.

The historical pilot used the then-current
`application/config/glofas_latent_path_al_vb_dec25_pilot.yaml`.
It completed the input check, panel build, AL-VB fit, posterior-draw prediction,
and post-fit analysis. The fit wrote 200 posterior draws for 28 issued GloFAS
target dates, and the post-fit band check confirmed complete uncertainty bands
for both the 30-day history window and the available forecast window. Because
the pilot used only five VB iterations, its forecast metrics are a wiring
diagnostic rather than application evidence. After the launch specification was
expanded, the design preflight rather than this historical pilot is the current
dimension check.

The real Dec. 25 AL-VB launch is configured in
`application/config/glofas_latent_path_al_vb_dec25_main.yaml`. It uses the same
streamed VB structure, but the active launch specification now uses
`D = 2`, `n = (1000, 1000)`, `n_tilde = 500`, `m = 360`,
`rhs_tau0 = 1e-6`, and `rhs_freeze_tau_warmup_iters = 50`. It caps VB at 200
iterations rather than the earlier exploratory 1,500-iteration budget. The
code path now enforces a 500-iteration hard cap for article-side VB launch
configurations.

## Reproducibility Command

The safe profile can be repeated with:

```sh
Rscript application/scripts/03_profile_latent_path_al_vb.R \
  --config application/config/glofas_latent_path_al_vb_dec25_full.yaml \
  --run_id latent_path_covaware_full_vb_streamed_delta_profile_YYYYMMDD_HHMMSS \
  --future_laplace true \
  --save_design false
```

To force the dense heavy path for debugging only, first set
`inference.vb_ld.future_moment_strategy: dense_debug` in a temporary debug
configuration and then run:

```sh
Rscript application/scripts/03_profile_latent_path_al_vb.R \
  --config application/config/glofas_latent_path_al_vb_dec25_full.yaml \
  --run_id latent_path_covaware_full_vb_forced_profile_YYYYMMDD \
  --future_laplace true \
  --save_design false \
  --force_heavy true
```

The forced command should not be used as a routine gate.
