# GloFAS MCMC Diagnostic Pilot

Date: 2026-05-12

## Purpose

This note freezes the first scientific diagnostic pilot after the validated
posterior-draw dry run. The pilot is not the final manuscript-scale
application. Its purpose is to inspect model behavior under the full
posterior-draw prediction contract with a more substantive DESN specification,
three quantile levels, and run-level diagnostics.

## Last Validated Gate

The current posterior-draw reproducibility gate is

```text
application/runs/posterior_draw_dryrun_preflight_20260512_025147
```

That run used article SHA `6c325a5` and engine SHA `915a75a`, wrote
`tables/posterior_draw_predictions.csv`, and passed all required launch
readiness checks. It remains a wiring gate because it used a deliberately small
reservoir and a short MCMC chain.

## Diagnostic Pilot Scope

The diagnostic pilot uses the audited Dec. 25, 2022 GloFAS cutoff and the
issued GloFAS horizon only. The fitted quantile levels are

```text
0.10, 0.50, 0.90
```

The model set is deliberately narrow:

- raw GloFAS ensemble quantiles at the same three levels;
- Q--DESN GloFAS discrepancy calibration with the AL working likelihood,
  MCMC, and the regularized horseshoe prior.

The prediction contract remains posterior-draw based:

```text
q_y_draw = q_g_draw - d_g_draw
```

The Q--DESN discrepancy rows use
`q_g_source = posterior_model_quantile` and
`discrepancy_feature_strategy = horizon_indexed_origin_state`.

## DESN Specification

The diagnostic DESN is larger than the dry-run gate but still small enough to
inspect quickly:

```text
D = 2
n = (40, 24)
n_tilde = 20
m = 7
washout = 30
alpha = (0.30, 0.25)
rho = (0.90, 0.85)
pi_w = (0.10, 0.10)
pi_in = (0.60, 0.60)
```

This choice keeps the readout dimension moderate while allowing weekly lag
information and a two-layer reservoir representation. The 30-day washout is
used to remove the initial reservoir transient. The configuration is a
diagnostic default, not a tuned architecture.

## Inference Settings

The pilot uses AL-MCMC with

```text
n_mcmc = 300
n_burn = 200
thin = 1
```

The chain length is intentionally modest. It is long enough to exercise the
posterior-draw workflow and produce inspectable fit diagnostics, but it is not
intended as a final convergence setting.

## Tracked Configuration

The diagnostic pilot is controlled by

```text
application/config/glofas_discrepancy_mcmc_diagnostic_dec25.yaml
application/config/model_grid_mcmc_diagnostic_dec25.csv
application/config/quantile_grid_mcmc_diagnostic.csv
```

The run must record the article git SHA, engine git SHA, input manifest hash,
config hash, design hash, prediction design hash, fit status, posterior draw
checks, and output provenance.

## Required Outputs

The diagnostic pilot should produce at least

```text
tables/posterior_draw_predictions.csv
tables/prediction_quantiles.csv
tables/qdesn_discrepancy_fit_diagnostics.csv
tables/qdesn_discrepancy_draw_checks.csv
tables/score_summary.csv
tables/manuscript_output_provenance.csv
```

The generated output directory should include the score table and model
diagnostic figures:

```text
glofas_qdesn_discrepancy_corrected_quantile_paths.pdf
glofas_qdesn_discrepancy_draws_by_horizon.pdf
```

## Advancement Criteria

Move to a larger application campaign only if the diagnostic pilot satisfies
all of the following:

1. All required preflight checks pass.
2. Every posterior-draw row satisfies
   `q_y_draw = q_g_draw - d_g_draw`.
3. Raw GloFAS rows are labeled with `ensemble_empirical_quantile`.
4. Q--DESN discrepancy rows are labeled with `posterior_model_quantile`.
5. Fit diagnostics have finite coefficient, scale, and effective-sample-size
   summaries.
6. The model diagnostic figures are generated from the run directory and have
   output provenance.
7. No manuscript performance claim is made from this pilot without a separate
   decision to promote the run.
