# Joint QDESN Phase 108: VB-Initialized MCMC Readiness Plan

Date: 2026-07-07

This note records the audit, diagnosis, and implementation plan for the stage
after Phase 107 selected-VB hardening. The goal is to test whether the frozen
VB specification can safely initialize the MCMC reference layer. This is not the
final article MCMC table.

## Starting Evidence

Phase 107 completed under:

`application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707`

The selected VB specification was:

- `candidate_id = rhs_tau0_0p5_alpha0p5`;
- `tau0 = 0.5`;
- `zeta2 = Inf`;
- empirical ordered-intercept prior with `alpha_prior_sd = 0.5`;
- `rhs_vb_inner = 7`;
- adaptive VB grid `480,960`.

Health summary:

| diagnostic | result |
|---|---:|
| Nested manifest checks | 44/44 pass |
| Worker failures | 0 |
| Contract quantile crossings | 0 |
| Fit raw crossing pairs | 28 |
| Forecast raw crossing pairs | 458 |
| Fit max-iteration flags | 15 |
| Forecast max-iteration flags | 15 |
| Mean forecast truth MAE | 0.1232 |
| Max forecast truth MAE | 0.2097 |
| Runtime | 287.85 minutes |

Model-level forecast evidence:

| model | forecast truth MAE | raw crossings | diagnosis |
|---|---:|---:|---|
| `JOINT QDESN RHS` | 0.0976 | 2 | Best VB candidate and the natural MCMC-readiness target. |
| `QDESN RHS` | 0.1003 | 143 | Accurate independent comparator, but raw monotone repair is larger. |
| `JOINT exQDESN RHS` | 0.1508 | 0 | Stable but less accurate; no mature exAL MCMC path is promoted here. |
| `exQDESN RHS` | 0.1440 | 313 | Improved but review-level raw crossing burden. |

## Diagnosis

The next stage should not be another broad VB screen. Phase 106/107 already
identified the only implementation-clean, non-catastrophic candidate. The
remaining question is whether the primary joint AL VB fit is a usable initializer
for MCMC.

The local repository already contains a tested AL MCMC sampler:

`app_joint_qvp_fit_al_mcmc_tiny()`

That sampler supports:

- ordered intercepts;
- RHS prior controls;
- empirical ordered-intercept prior;
- VB initialization via `init`;
- finite sigma bounds for numerical-reference stability;
- pooled multichain summaries.

The same repository does not contain an article-ready exAL MCMC implementation
for the joint QDESN simulation lane. Therefore Phase 108 should be explicitly
AL-only and should target `JOINT QDESN RHS`, while leaving exAL as a VB-only
comparison until a separate exAL MCMC layer is implemented and validated.

## Why This Is The Optimal Next Step

1. It uses the strongest Phase 107 row.
   `JOINT QDESN RHS` has the best forecast recovery and only two raw crossing
   pairs across the full Phase 107 forecast run.

2. It does not confuse MCMC readiness with model selection.
   The selected VB specification is frozen before MCMC is launched.

3. It reuses existing tested MCMC infrastructure.
   This reduces risk relative to writing a new sampler under article pressure.

4. It preserves reproducibility.
   Phase 108 verifies the Phase 107 manifests and fixture manifests before any
   MCMC fit is attempted.

5. It keeps the gate language conservative.
   MCMC readiness can pass implementation gates while still remaining review-level
   on chain distance, raw monotone adjustment, or runtime.

## Implemented Design

Add:

- `application/R/joint_qdesn_mcmc_readiness.R`;
- `application/scripts/108_run_joint_qdesn_mcmc_readiness.R`;
- `application/tests/test_joint_qdesn_mcmc_readiness.R`.

The runner:

1. Loads and verifies the Phase 107 selected contract.
2. Loads and verifies the frozen long-series fixture directory.
3. Refits `JOINT QDESN RHS` under the frozen Phase 107 VB controls.
   This is necessary because Phase 107 stored inspectable CSV summaries, not
   serialized beta/alpha/sigma fit objects.
4. Runs AL MCMC initialized from the VB fit.
5. Pools chains and computes:
   - finite draw checks;
   - sigma bound-hit diagnostics;
   - VB-to-MCMC normalized distances;
   - chain-to-pooled normalized distances;
   - raw and contract crossing diagnostics;
   - truth-distance and check-loss summaries;
   - runtime summaries;
   - provenance and SHA-256 manifests.

## Phase 108 Artifacts

The default artifact directory is:

`application/cache/joint_qdesn_mcmc_readiness_phase108_20260707`

It writes:

- `run_config.csv`;
- `phase107_source_manifest_verification.csv`;
- `fixture_source_manifest.csv`;
- `scenario_worker_failures.csv`;
- `mcmc_readiness_summary.csv`;
- `mcmc_readiness_assessment.csv`;
- `fit_quantiles_raw.csv`;
- `fit_quantiles.csv`;
- `fit_monotone_adjustment.csv`;
- `fit_truth_comparison.csv`;
- `truth_distance_summary.csv`;
- `check_loss_summary.csv`;
- `hit_rate_summary.csv`;
- `crps_grid_summary.csv`;
- `interval_summary.csv`;
- `crossing_summary.csv`;
- `raw_crossing_summary.csv`;
- `vb_convergence_audit.csv`;
- `objective_diagnostics.csv`;
- `rhs_prior_summary.csv`;
- `scale_parameter_summary.csv`;
- `mcmc_draw_summary.csv`;
- `vb_mcmc_distance_summary.csv`;
- `chain_to_pooled_distance_summary.csv`;
- `runtime_summary.csv`;
- `provenance.csv`;
- `README.md`;
- `artifact_manifest.csv`.

## Gates

Hard fail:

- Phase 107 source manifest failure;
- fixture manifest failure;
- scenario worker failure;
- nonfinite required metrics;
- MCMC not initialized from VB;
- nonfinite MCMC draws;
- VB or MCMC contract quantile crossings.

Review:

- VB reaches max iterations;
- raw VB or raw MCMC quantiles require monotone repair;
- nonzero sigma bound-hit fraction;
- VB/MCMC normalized distance above the provisional threshold;
- chain-to-pooled normalized distance above the provisional threshold;
- runtime materially exceeds expectation.

Pass:

- all implementation gates pass;
- MCMC initializes from VB;
- draws are finite;
- contract quantiles are noncrossing;
- distances and chain spread are below provisional thresholds;
- no meaningful raw adjustment or bound-hit review appears.

## Commands

Focused test:

```bash
Rscript application/tests/test_joint_qdesn_mcmc_readiness.R
```

Default Phase 108 readiness launch:

```bash
Rscript application/scripts/108_run_joint_qdesn_mcmc_readiness.R \
  --output-dir application/cache/joint_qdesn_mcmc_readiness_phase108_20260707 \
  --phase107-dir application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --n-chains 2 \
  --mcmc-n-iter 80 \
  --mcmc-burn 40 \
  --mcmc-thin 5 \
  --n-cores 4
```

## Decision Rule After Phase 108

If Phase 108 is implementation-clean but review-level on distance or runtime,
the next step should be a deeper MCMC reference for the worst scenarios only,
not a new VB screen.

If Phase 108 fails due to nonfinite MCMC draws or contract crossings, fix the
MCMC implementation before launching any final article MCMC table.

If Phase 108 passes or is only mildly review-level, proceed to the final
article-scale MCMC launch for `JOINT QDESN RHS`, then decide whether exAL needs a
separate sampler implementation or remains VB-only in the article.

## Phase 108 Outcome

The full readiness launch completed under:

```bash
Rscript application/scripts/108_run_joint_qdesn_mcmc_readiness.R \
  --output-dir application/cache/joint_qdesn_mcmc_readiness_phase108_20260707 \
  --phase107-dir application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --n-chains 2 \
  --mcmc-n-iter 80 \
  --mcmc-burn 40 \
  --mcmc-thin 5 \
  --n-cores 4
```

Artifact directory:

`application/cache/joint_qdesn_mcmc_readiness_phase108_20260707`

Health summary:

| diagnostic | result |
|---|---:|
| Artifact manifest checks | 27/27 pass |
| Phase 107 source verification | pass |
| Fixture source verification | pass |
| Worker failures | 0 |
| MCMC chains per scenario | 2 |
| Kept MCMC draws per scenario | 16 |
| Nonfinite MCMC draw blocks | 0 |
| Contract crossing pairs | 0 |
| Raw crossing pairs | 0 |
| Sigma bound-hit fraction | 0 |
| Pass scenarios | 7 |
| Review scenarios | 2 |
| Fail scenarios | 0 |

Scenario-level readiness:

| scenario | gate | MCMC truth MAE | VB/MCMC max normalized distance | reason |
|---|---|---:|---:|---|
| `normal_bridge` | pass | 0.0811 | 0.0761 | all readiness gates passed |
| `laplace_bridge` | pass | 0.0919 | 0.0345 | all readiness gates passed |
| `gaussian_mixture_bridge` | pass | 0.1032 | 0.0391 | all readiness gates passed |
| `student_t_location_scale` | review | 0.0629 | 0.0695 | VB reached max iterations |
| `asymmetric_laplace_tail` | pass | 0.0919 | 0.0461 | all readiness gates passed |
| `heteroskedastic_seasonal` | pass | 0.0873 | 0.0383 | all readiness gates passed |
| `persistent_heavy_tail` | review | 0.1245 | 0.0933 | VB reached max iterations |
| `regime_shift` | pass | 0.0940 | 0.0757 | all readiness gates passed |
| `nonlinear_reservoir_friendly` | pass | 0.1100 | 0.0556 | all readiness gates passed |

The largest VB/MCMC normalized distance was `0.0933`, far below the provisional
review threshold of `5`. The largest chain-to-pooled normalized distance was
`0.0791`, also far below the provisional threshold of `5`. The two review
scenarios are review-level only because the frozen VB fit reached its adaptive
iteration cap before MCMC; the MCMC reference itself initialized correctly,
produced finite draws, stayed away from sigma bounds, and produced noncrossing
contract quantiles.

## Phase 108 Decision

Phase 108 unblocks the MCMC path for the primary article model:

`JOINT QDESN RHS`

The evidence supports moving to a final article-scale MCMC launch for the primary
joint AL model, using the same frozen Phase 107 VB specification as initialization.
No additional broad VB screening is recommended.

The final MCMC launch should:

- keep `JOINT QDESN RHS` as the primary MCMC model;
- use longer chains than Phase 108;
- retain Phase 108's raw/contract quantile policy;
- preserve finite draw, chain-to-pooled, VB/MCMC distance, crossing, runtime,
  provenance, and manifest gates;
- treat `student_t_location_scale` and `persistent_heavy_tail` as convergence
  watch scenarios because their VB initializers reached the cap;
- keep exAL out of the MCMC table unless a separate exAL MCMC implementation is
  added and validated.

Recommended article-candidate launch:

```bash
Rscript application/scripts/108_run_joint_qdesn_mcmc_readiness.R \
  --output-dir application/cache/joint_qdesn_mcmc_article_phase109_20260707 \
  --phase107-dir application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --n-chains 2 \
  --mcmc-n-iter 1200 \
  --mcmc-burn 600 \
  --mcmc-thin 10 \
  --n-cores 4 \
  --final-article-mcmc-table true
```

This keeps 60 draws per chain and 120 pooled draws per scenario. The launch is
large enough to move beyond readiness smoke evidence while remaining bounded
enough to audit before any manuscript table is frozen.
