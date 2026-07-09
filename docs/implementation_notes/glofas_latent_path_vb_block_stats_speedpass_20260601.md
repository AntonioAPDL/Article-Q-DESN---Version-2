# GloFAS Latent-Path VB Block-Statistics Speed Pass

Date: 2026-06-01
Branch: `application-ensemble-likelihood-redesign`

## Summary

This note documents an exact speed pass for the GloFAS latent-path AL-VB
application solver. The change does not alter the model, prior, likelihood,
variational family, prediction contract, or output schema. It only changes how
fixed historical row moments and fixed historical theta statistics are computed
when the latent-path design has the standard two-block structure:

```text
Y rows: h_Y = [x_beta, 0]
G rows: h_G = [x_beta, x_alpha]
```

Unsupported designs fall back to the previous dense augmented-design path.

## Implementation

The implementation adds guarded internal helpers in
`application/R/latent_path_vb_al.R`:

- `app_latent_fixed_block_design()`;
- `app_latent_fixed_row_moments_block()`;
- `app_latent_fixed_theta_stats_block()`;
- `app_latent_diagonal_values()`.

The block helpers use the existing `X_beta_stack`, `X_alpha_stack`,
`source_fixed`, `beta_index`, and `alpha_index` fields when available. The guard
checks row/column compatibility, source labels, beta-block equality, G-row
alpha-block equality, and Y-row alpha no-leakage. Numeric equality checks ignore
column-name attributes because `H_fixed` uses prefixed names such as `beta__...`
and `alpha__...`, while the stacked feature matrices keep their original feature
names.

For diagonal theta covariance matrices, the fixed row-moment helper uses an
exact diagonal quadratic-form shortcut. This mainly accelerates the initial row
moment calculation, where the VB covariance is initialized as diagonal.

## Validation

Focused latent-path tests were extended in
`application/tests/test_latent_path_design.R` to cover:

- dense-versus-block fixed row moments;
- dense-versus-block fixed theta precision/RHS statistics;
- `X_beta != X_alpha`;
- production-style feature-name mismatch between `H_fixed` and stacked feature
  matrices;
- fallback when the block object is absent;
- fallback when Y rows violate the alpha no-leakage guard.

Focused latent-path test command:

```bash
Rscript -e "repo_root <- normalizePath('.'); source(file.path(repo_root, 'application/R/00_packages.R')); app_set_repo_root(repo_root); source(app_path('application/R/input_contract.R')); source(app_path('application/R/launch_control.R')); source(app_path('application/R/artifact_hygiene.R')); source(app_path('application/R/engine_contract.R')); source(app_path('application/R/model_contract.R')); source(app_path('application/R/feature_contract.R')); source(app_path('application/R/covariate_design.R')); source(app_path('application/R/build_application_panel.R')); source(app_path('application/R/build_qdesn_features.R')); source(app_path('application/R/latent_path_design.R')); source(app_path('application/R/simulate_latent_path.R')); source(app_path('application/R/latent_path_vb_al.R')); source(app_path('application/R/latent_path_recovery.R')); source(app_path('application/R/discrepancy_design.R')); source(app_path('application/R/forecast_contract.R')); source(app_path('application/R/fit_qdesn_discrepancy.R')); source(app_path('application/R/fit_qdesn_latent_path.R')); source(app_path('application/R/score_forecasts.R')); source(app_path('application/R/post_fit_analysis.R')); source(app_path('application/tests/test_input_contract.R')); source(app_path('application/tests/test_latent_path_design.R')); cat('focused latent-path tests completed\n')"
```

Tiny exact gate:

```text
application/logs/block_stats_tiny_gate_20260601_diag
```

Result:

| Gate | Value |
| --- | ---: |
| Max fitted-state difference | `6.821210e-13` |
| Tolerance | `1e-7` |
| Passed | `TRUE` |

Full-spec exact gate:

```text
application/logs/block_stats_fullspec_gate_20260601_diag
```

Result:

| Gate | Value |
| --- | ---: |
| Max fitted-state difference | `0` |
| Tolerance | `1e-7` |
| Same design hash | `TRUE` |
| Same model/cutoff | `TRUE` |
| Prediction identity max error | `1.110223e-16` |
| No-leakage audits checked | `3` |
| Passed | `TRUE` |

## Timing Evidence

Previous full-spec exact-chunked baseline:

```text
application/logs/exact_speedpass_probe_cache_fullspec_gate_20260531
```

New full-spec exact gate:

```text
application/logs/block_stats_fullspec_gate_20260601_diag
```

Selected timings:

| Step | Previous exact chunked | New exact chunked |
| --- | ---: | ---: |
| Initial row moments | `372.013s` | `88.075s` |
| Theta update | `328.697s` | `228.292s` |
| Row moments | `369.843s` | `267.516s` |
| Theta draw generation | `81.737s` | `98.656s` |
| Fit elapsed | `1577.499s` | `1198.718s` |

The full-spec exact-chunked elapsed time improved by about 24%. The remaining
large costs are dense posterior-covariance row moments, theta posterior draws,
design construction, and design summarization.

## Notes

The unchunked full-spec gate also passed, but the unchunked and chunked timings
show run-to-run variability in dense linear algebra. The important acceptance
criterion is exact fitted-state identity plus a material improvement over the
previous baseline on the same full-spec gate.

Future exact speed passes should prioritize:

1. Cholesky-first theta posterior draws with eigen fallback;
2. design hash/summary slimming;
3. reducing dense `H_fixed` storage once downstream contracts are adjusted.

