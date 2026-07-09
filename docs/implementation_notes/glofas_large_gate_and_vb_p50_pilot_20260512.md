# GloFAS Large-Design Gates and Median VB Pilot

Date: 2026-05-12  
Cutoff: 2022-12-25  
Purpose: record the first full large-design gates and the median-only large VB
pilot for the GloFAS discrepancy-calibration Q-DESN workflow.

## Scope

This note documents readiness work only. It does not promote the pilot fit as a
final application result. The main goal was to verify that the large MCMC and VB
profiles use the same data lineage, reservoir specification, feature strategy,
and posterior-draw prediction contract before any manuscript-scale launch.

The large profiles use

- `D = 2`;
- `n = (500, 500)`;
- `n_tilde = 500`;
- `m = 180`;
- `washout = 500`;
- horizon-indexed origin-state discrepancy features;
- AL working likelihood;
- regularized horseshoe readout prior with `rhs_tau0 = 1e-4`.

The MCMC profile uses burn-in `1000` and saved draws `2000`. The VB profile
uses the same model design and produces `2000` approximate posterior draws for
the prediction contract.

## Runs

The full large MCMC input/design gate was run with
`application/config/glofas_discrepancy_mcmc_large_dec25.yaml`.

- Run id: `large_mcmc_all_design_gate_20260512_135328`
- Result: completed
- Output table:
  `application/runs/large_mcmc_all_design_gate_20260512_135328/tables/qdesn_discrepancy_design_preflight.csv`

The full large VB input/design gate was run with
`application/config/glofas_discrepancy_vb_large_dec25.yaml`.

- Run id: `large_vb_all_design_gate_20260512_141045`
- Result: completed
- Output table:
  `application/runs/large_vb_all_design_gate_20260512_141045/tables/qdesn_discrepancy_design_preflight.csv`

The median-only large VB pilot was run with
`application/config/glofas_discrepancy_vb_large_dec25_p50_pilot.yaml`.

- Run id: `vb_large_dec25_p50_pilot_20260512_142839`
- Result: fit, scoring, and output stages completed; launch readiness failed
  only because the article and engine repositories contained the intentional
  uncommitted implementation edits from this pass.
- Main fit artifact:
  `application/runs/vb_large_dec25_p50_pilot_20260512_142839/objects/qdesn_discrepancy_rhs_al_vb_large_p50.rds`

## Design Checks

The MCMC and VB large-design gates matched exactly on the design dimensions and
hashes for the three enabled quantile levels.

| Quantile | Training design hash prefix | Prediction design hash prefix |
| --- | --- | --- |
| 0.10 | `2fa22510e95e` | `209b915c2e2c` |
| 0.50 | `73ddca908b55` | `332eb617ee79` |
| 0.90 | `d319ee4747f4` | `62c43b38fbb1` |

The median pilot design also matched the p50 row from the full VB design gate.
This confirms that the median pilot is a restricted fit of the same large
profile, not a separate reduced specification.

## Median VB Pilot Checks

The p50 pilot completed the large AL-VB discrepancy fit and wrote the expected
posterior-draw prediction artifacts.

Key diagnostics:

- VB convergence: `TRUE`;
- VB iterations: `54`;
- VB runtime: `1442.405` seconds inside the engine fit;
- end-to-end Q-DESN fit status runtime: `1863.434` seconds;
- posterior draws: `2000`;
- forecast dates: `28`;
- posterior-draw prediction rows: `56000`;
- maximum draw-identity error after CSV readback:
  approximately `1.02e-14`.

The required posterior-draw identity is

```text
q_y_draw = q_g_draw - d_g_draw.
```

The run-level draw-check table reports this identity as satisfied within
tolerance. This is the correct contract for Bayesian forecast correction in the
current application design: each posterior draw carries a GloFAS quantile draw,
a discrepancy draw, and the implied USGS quantile draw.

The pilot also gives a first model-behavior check. The fitted posterior-model
GloFAS median was nearly constant across the 28 issued horizons
(`q_g_hat` about `1.6254` on the transformed scale), and the fitted discrepancy
was also nearly constant (`d_g_hat` about `-0.2522`). The implied corrected
median was therefore nearly constant (`qhat` about `1.8776`), even though the
raw GloFAS median varies across the issued forecast window. This is not a
software-contract failure, but it is a modeling diagnostic. Before using the VB
route for manuscript-facing claims, the next run should inspect whether this
behavior is caused by the current origin-state prediction design, the strong
`rhs_tau0 = 1e-4` shrinkage, the single-origin forecast design, or the
mean-field approximation.

## Launch-Readiness Interpretation

The median pilot initially failed launch readiness with two required failures:

- `article_git_clean`;
- `engine_git_clean`.

These failures were expected because the pilot was run before committing the
new p50 pilot configuration, article tests, documentation, and engine tests.
All input, stage, figure, output, posterior-draw, and engine-support checks
passed in the readiness report. After the implementation edits were committed,
the readiness stage was rerun on the same pilot directory and all required
checks passed.

## Current Recommendation

The median pilot is healthy enough to justify the next readiness step: rerun
the launch-readiness stage after committing the implementation edits, and then
choose between

- a three-quantile large VB pilot for Dec. 25, or
- a targeted p50 MCMC reference fit.

The clean readiness rerun passed after these edits were committed. The
three-quantile VB run is the natural next exploration step if the nearly
constant median behavior is understood and accepted as a pilot finding. A p50
MCMC reference remains important before using VB results as primary manuscript
evidence.
