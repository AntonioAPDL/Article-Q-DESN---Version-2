# GloFAS Normal Winner Transfer: 2021-12-21

## Objective

Evaluate whether the frozen Dec. 25, 2022 winning DESN specification transfers to the Dec. 21, 2021 cutoff under the Part 4 Normal Ridge and Normal RHS/VB models. This is a specification-transfer experiment, not a parameter-transfer experiment.

## Fixed Scientific Contract

- Cutoff and training end: `2021-12-21`.
- Scoring window: `2021-12-22` through `2022-01-20`.
- Issued GloFAS support: 51 members at horizons 1 through 28, ending `2022-01-18`.
- Future USGS: scoring sidecar only; physically excluded from fit objects.
- Covariates: realized PRISM precipitation and ERA5 soil moisture. No NWS, GEFS, blended covariates, or climate-index principal components.
- Scale: all fitting and diagnostic plotting use `log1p`.
- Readout: reservoir state plus intercept only; no direct input block.

Reference DESN: `D=1`, `n=3000`, `m=360`, output lags `1:360`, PPT/soil lags `0:180`, washout `500`, `alpha=0.5`, `rho=0.9`, `pi_w=0.03`, `pi_in=1`, input scales `0.18`, seed `20260512`, and RHS `tau0=1`.

Discrepancy DESN: `D=1`, `n=2500`, `m=360`, output lags `1:360`, PPT/soil lags `0:180`, washout `500`, `alpha=0.8`, `rho=0.7`, `pi_w=0.03`, `pi_in=1`, input scales `0.18`, seed `20261521`, and RHS `tau0=0.001`.

## Initialization And Leakage Policy

The Ridge model starts from the alternate-cutoff data and prior only. The RHS/VB model starts from the completed Ridge fit built from the exact same alternate-cutoff design. Its coefficient block is frozen for the existing 20-iteration warmup while the remaining variational blocks adapt.

No Dec. 25 fitted coefficients, posterior covariance, local/global shrinkage states, observation-scale state, latent future path, fitted standardization state, or sufficient statistic is transferred. The Dec. 25 artifacts contribute only the frozen architecture, lag, seed, and prior hyperparameter specification.

## Reproducibility Surface

- Input/preparation module: `application/R/glofas_part4_multicutoff_normal_transfer.R`.
- Preparation command: `application/scripts/393_prepare_glofas_multicutoff_normal_transfer.R`.
- Existing fit worker: `application/scripts/386_run_glofas_part4_latent_family_job.R`.
- Existing DAG launcher, generalized with an explicit expected-job count: `application/scripts/387_launch_glofas_part4_latent_family_dag.py`.
- Diagnostic plot: `application/scripts/394_plot_glofas_multicutoff_normal_transfer.R`.
- Focused tests: `application/tests/test_glofas_part4_multicutoff_normal_transfer.R`.

The ignored runtime contains the materialized four-input manifest, cutoff table, bundle audit, geometry-only anchor manifest, transfer contract, prelaunch hashes, job-specific artifact manifests, iteration traces, fit objects, predictions, scores, and the final PDF.

## Controls

Normal controls are `max_iter=100`, `min_iter=30`, `tol=0.01`, `min_beta_updates=10`, `n_draws=500`, and one-thread BLAS per worker. The two jobs are dependency-gated: RHS/VB cannot start until the same-cutoff Ridge fit has completed.

