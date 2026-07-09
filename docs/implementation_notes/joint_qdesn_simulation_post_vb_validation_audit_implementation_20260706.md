# Joint QDESN post-VB validation audit implementation

Date: 2026-07-06

This note records the implemented post-VB audit layer for the new joint QDESN simulation study. The goal was not to launch another full validation campaign. The goal was to preserve the completed article-scale VB fit and forecast evidence, diagnose the independent exAL pathology, and check whether the high VB max-iteration rate requires a production rerun before article tables.

## Scope

This work is scoped to the new joint QDESN simulation study only. It does not modify TT500, GloFAS, PriceFM, or the older joint-QVP calibration lanes.

Source article-scale artifacts:

- Fit validation: `application/cache/joint_qdesn_simulation_vb_fit_validation_article_20260706`
- Forecast validation: `application/cache/joint_qdesn_simulation_vb_forecast_validation_article_20260706`
- Previous health report: `application/cache/joint_qdesn_simulation_article_vb_fit_forecast_health_20260706.md`

Implemented scripts:

- `application/scripts/102_audit_joint_qdesn_simulation_vb_fit_forecast_outputs.R`
- `application/scripts/103_diagnose_joint_qdesn_independent_exal_tail_failure.R`
- `application/scripts/104_audit_joint_qdesn_vb_convergence_readiness.R`

## Commands

The audit layer was run from the clean main validation worktree:

```bash
Rscript application/scripts/102_audit_joint_qdesn_simulation_vb_fit_forecast_outputs.R
Rscript application/scripts/103_diagnose_joint_qdesn_independent_exal_tail_failure.R
Rscript application/scripts/104_audit_joint_qdesn_vb_convergence_readiness.R
```

The scripts write CSV artifacts, compact `README.md` summaries, provenance, and SHA-256 manifests.

## Artifact Integrity

| Artifact directory | Files in manifest | Hash status |
|---|---:|---|
| `application/cache/joint_qdesn_simulation_post_vb_validation_audit_20260706` | 10 | pass |
| `application/cache/joint_qdesn_independent_exal_tail_failure_diagnostic_20260706` | 9 | pass |
| `application/cache/joint_qdesn_vb_convergence_readiness_20260706` | 9 | pass |

The source fit and forecast artifact manifests were also verified by the compact audit.

## Compact VB Evidence

The completed article-scale VB run remains implementation-clean:

| Stage | Manifest | Contract crossings | Raw crossings | Gate rows | Overall |
|---|---|---:|---:|---|---|
| Fit | pass | 0 | 528 | 1 pass, 35 review, 0 fail | review |
| Forecast | pass | 0 | 1263 | 1 pass, 35 review, 0 fail | review |

The review status is driven by conservative diagnostics, mainly raw monotone adjustments and max-iteration flags. There are no hard failures: no missing hashes, nonfinite scores, leakage flags, or contract crossings.

Forecast model ranking:

| Rank | Model label | Role | Truth MAE | Check loss | CRPS grid | Comment |
|---:|---|---|---:|---:|---:|---|
| 1 | `JOINT QDESN RHS` | primary article candidate | 0.103 | 0.161 | 0.369 | Best overall joint model. |
| 2 | `QDESN RHS` | independent comparator | 0.104 | 0.161 | 0.368 | Very close forecast performance, with more raw repairs. |
| 3 | `JOINT exQDESN RHS` | secondary exAL comparator | 0.155 | 0.163 | 0.371 | Stable but less accurate here. |
| 4 | `exQDESN RHS` | hold for failure audit | 58.502 | 19.417 | 55.303 | Dominated by one severe asymmetric-tail failure. |

## Independent exAL Tail-Failure Diagnosis

The targeted diagnostic confirms a localized independent `exQDESN RHS` failure on `asymmetric_laplace_tail`, especially at `tau = 0.75`.

Key findings:

- Status: `confirmed_failure`
- Raw crossing pairs in the reproduced current grid: 500
- Contract crossing pairs: 0
- `tau = 0.75` exAL raw mean fitted quantile: about `-2723.6`
- `tau = 0.75` true quantile mean: about `1.01`
- `tau = 0.75` raw truth MAE: about `2724.6`
- `tau = 0.75` contract truth MAE: about `545.5`
- `tau = 0.75` maximum monotone adjustment: about `2537.0`
- exAL `alpha_mean` at `tau = 0.75`: about `3432`
- exAL `sigma_mean` at `tau = 0.75`: about `0.0094`

The adjacent sensitivity checks show that `tau = 0.70` and `tau = 0.80` remain numerically reasonable under the same frozen data and design. Shrinking the empirical alpha prior standard deviation from `1` to `0.25` does not repair the `tau = 0.75` failure. This points to a K=1 exAL update or local approximation instability at that interior upper quantile, not a global exAL failure and not a fixture problem.

Recommended article treatment:

- Do not include independent `exQDESN RHS` in the main article table unless the K=1 exAL stabilizer is implemented and rerun.
- Keep `JOINT exQDESN RHS` as the exAL comparison because it is stable on the same DGP.
- If independent exAL is discussed, place it in an appendix or diagnostic note with the localized failure disclosed.

## VB Convergence-Readiness Audit

The convergence audit reran a representative fit-stage subset at `480`, `720`, and `960` VB iterations:

- scenarios: `normal_bridge`, `asymmetric_laplace_tail`, `persistent_heavy_tail`, `nonlinear_reservoir_friendly`
- models: `JOINT QDESN RHS`, `QDESN RHS`, `JOINT exQDESN RHS`

Gate recommendations:

| Recommendation | Count |
|---|---:|
| `pass_with_note` | 11 |
| `review` | 1 |
| `fail` | 0 |

The single review row is `JOINT QDESN RHS` on `persistent_heavy_tail` from 480 to 720 iterations:

- mean absolute fitted-quantile delta: about `0.0067`
- maximum fitted-quantile delta: about `0.0590`
- truth MAE changed from `0.11835` to `0.11748`
- check-loss delta: about `0.000014`
- contract crossings: 0
- monotone adjustment remains negligible

This is a borderline quantile-delta review, not an implementation failure. The score changes are negligible, so the completed article-scale VB evidence can be used with a convergence note rather than requiring a new full launch.

Mean runtime by representative fit:

| Model | 480 iter | 720 iter | 960 iter |
|---|---:|---:|---:|
| `JOINT QDESN RHS` | 68.7 s | 90.7 s | 109.0 s |
| `QDESN RHS` | 94.4 s | 123.3 s | 135.5 s |
| `JOINT exQDESN RHS` | 249.8 s | 329.1 s | 386.8 s |

## Decision

The optimal next step is not another full VB relaunch. The evidence supports:

1. Use `JOINT QDESN RHS` as the primary article candidate.
2. Use `QDESN RHS` as the independent single-quantile comparator.
3. Use `JOINT exQDESN RHS` as the stable exAL comparator.
4. Hold independent `exQDESN RHS` out of the main table until the K=1 exAL failure is repaired.
5. Keep the completed 480-iteration article-scale VB results, with an explicit convergence note because most traces reach the cap but the targeted 960-iteration audit shows negligible score movement.

## Next Implementation Stage

Prepare the article evidence pack from the completed VB artifacts:

- produce main fit and forecast validation tables;
- produce scenario/model heatmaps for truth error and check loss;
- produce raw-adjustment and noncrossing-contract diagnostics;
- include one or two clear fit/forecast overlay figures;
- exclude independent `exQDESN RHS` from the main table unless repaired;
- defer MCMC until the VB article evidence pack is frozen.

The next script should be named consistently, for example:

`application/scripts/105_prepare_joint_qdesn_article_validation_tables_figures.R`

It should consume the completed fit/forecast artifacts and the post-VB audit artifacts without relaunching model fits.
