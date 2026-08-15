# GloFAS Large VB Launch Protocol

Date: 2026-05-12

## Purpose

This protocol prepares the variational Bayes route for the large Dec. 25,
2022 GloFAS discrepancy Q-DESN analysis. It mirrors the large MCMC profile in
source lineage, reservoir specification, regularized horseshoe prior, and
posterior-draw prediction contract. After the May 15 engine-sync update, the
0.5.0-compatible engine supplies Q--DESN feature and readout APIs, while the
latent-path AL-VB fitter remains article-side. The older package-side
`qdesn_fit_discrepancy()` boundary applies only to the legacy origin-state
bridge. The large real-data launch should still wait until the input/design
gate, synthetic VB checks, and a small article-side VB dry run have passed in
the current checkout.

The goal is a smooth inference switch:

```text
MCMC profile: inference_method = mcmc
VB profile:   inference_method = vb_ld
```

The switch must not change the input bundle, GloFAS retrospective source,
DESN design, draw-level prediction identity, or provenance rules.

## Configuration Boundary

The VB profile is controlled by:

```text
application/config/authoritative_cutoff_sources.csv
application/config/input_bundle_authoritative_dec25.yaml
application/config/glofas_discrepancy_vb_large_dec25.yaml
application/config/model_grid_vb_large_dec25.csv
application/config/quantile_grid_mcmc_diagnostic.csv
application/config/cutoffs_dec25_authoritative.csv
```

It uses the same Dec. 25 source-registry row as the MCMC profile. The GloFAS
retrospective must be the audited long-history histfix source with support
from 1987-05-29 through 2022-12-25 and source identifier
`glofas_hist_v31_lisflood_cons`.

## Large Specification

The VB profile uses the same scientific design as the large MCMC profile:

```text
D = 2
n = (500, 500)
n_tilde = 500
m = 180
washout = 500
likelihood = AL
coefficient prior = regularized horseshoe
rhs_tau0 = 1e-4
posterior-draw summaries requested = 2000
```

The method label remains `vb_ld` for compatibility with the article notation.
For AL rows, this label maps to the engine method `vb`; the Laplace-Delta
scale-asymmetry block is inactive because AL has no free exAL asymmetry
parameter. For exAL rows, the same interface should activate the
source-specific scale-asymmetry approximation after the exAL discrepancy VB
fitter is implemented and validated.

## Prediction Contract

The prediction contract is draw-based:

```text
q_y_draw = q_g_draw - d_g_draw
```

VB outputs must therefore provide approximate posterior draws, or a documented
draw-equivalent representation, for the GloFAS quantile readout and discrepancy
readout. Posterior means alone are not sufficient for the final Bayesian
application contract.

## Input and Design Gate

Run the same source, input, panel, and design gate used by MCMC, changing only
the config and fit id:

```sh
RUN_ID=vb_large_dec25_input_design_gate_YYYYMMDD

Rscript application/scripts/run_input_design_gate.R \
  --config application/config/glofas_discrepancy_vb_large_dec25.yaml \
  --cutoff_id dec25_2022 \
  --run_id "$RUN_ID" \
  --design_fit_id qdesn_discrepancy_rhs_al_vb_large_p50
```

The gate writes `manifest/qdesn_inference_support.csv` and
`tables/qdesn_inference_support_preflight.csv`. These files must record that
the configured engine supports discrepancy `AL + VB` before any fit launch.
If the engine capability table is unavailable or reports the row as
unsupported, the input/design gate may still run, but the fit stage must stop
before posterior computation.

## Fit-Stage Boundary

Use the following command only after the prelaunch gates below pass:

```sh
Rscript application/scripts/03_fit_models.R \
  --config application/config/glofas_discrepancy_vb_large_dec25.yaml \
  --run_id "$RUN_ID"
```

The command must not be used for the main real-data launch until all of the
following are true:

- the configured 0.5.0-compatible engine passes the source-policy and Q--DESN
  feature API checks;
- the article-side latent-path fitter supports
  `method = "vb"` and `likelihood_family = "al"`;
- synthetic source-indexed discrepancy tests pass for known coefficients,
  known discrepancy paths, source-specific scales, and RHS shrinkage;
- the engine returns approximate posterior draws compatible with
  `tables/posterior_draw_predictions.csv`;
- article-side dry runs verify the draw identity
  `q_y_draw = q_g_draw - d_g_draw`;
- VB diagnostics include ELBO trace, convergence status, iteration count, and
  finite posterior summaries;
- MCMC-only diagnostics such as effective sample size are not reported for VB
  approximate draws.

It is safe to run the same command as a deliberate support-gate check. If a
future branch removes or breaks `AL + VB` support, the command should stop
before posterior computation and report the unsupported rows.

## Validation Ladder

The recommended validation sequence is:

```text
1. AL-MCMC large input/design gate.
2. AL-VB large input/design gate.
3. Package-side synthetic AL-VB discrepancy tests.
4. Tiny article-side AL-VB dry run with
   `application/config/glofas_discrepancy_vb_posterior_draw_dryrun.yaml`.
5. Dec. 25 median AL-VB run.
6. Dec. 25 three-quantile AL-VB run.
7. VB versus MCMC comparison on selected smaller fits.
8. exAL MCMC and exAL VB-LD only after AL routes are stable.
```

Each completed fit run must record the article git SHA, engine git SHA, input
manifest hash, config hash, design hash, inference-method label, likelihood
family, prior settings, and method-specific diagnostics.

## Required Interpretation

VB is a practical approximation to the same article-side Bayesian readout
contract. It is not treated as a new general variational-inference method.
Until it has been compared with MCMC on controlled and selected real-data
fits, it should be described as a computational route whose approximation
quality is checked empirically.
