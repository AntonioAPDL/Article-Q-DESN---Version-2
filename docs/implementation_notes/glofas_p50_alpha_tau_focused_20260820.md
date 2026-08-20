# GloFAS p50 focused alpha/tau refinement

## Purpose

This campaign is a bounded follow-up to the completed 56-candidate
alpha/rho/tau response surface. It asks whether a local interaction between
reservoir leak rate and discrepancy-block RHS shrinkage can produce a material
forecast-window p50 gain without degrading the pre-cutoff fit.

It is not an article promotion, a full-seven-quantile run, or a new model
family. FR09 remains the authoritative application baseline.

## Evidence and decision

The predecessor campaign produced 39 converged fits and 17 deterministic
reservoir-preflight rejections. Its main findings were:

- linked leak rates `.075` and `.10` were the best viable region;
- `.05` and smaller leak rates failed low-effective-rank diagnostics;
- `.40` and larger leak rates failed saturation diagnostics;
- changing `rho` from `.50` through `.99` had little useful local effect;
- discrepancy RHS `tau0=1e-4` and `1e-6` were promising at leak rate `.20`;
- shared RHS `tau0` changes were weaker;
- block-specific leak rates did not beat the linked `.10` result under
  discrepancy `tau0=.001`; and
- warm/cold differences were large enough that cold controls remain mandatory.

The optimal next experiment is therefore a local interaction design, not a
second broad Cartesian screen. It freezes the axes that lacked signal and spends
one 20-worker wave on the unresolved interaction.

## Frozen model contract

Every candidate uses the same two-block latent-path GloFAS model:

- separate reference/shared and discrepancy DESNs;
- distinct input streams and seeds `20260512` and `20261521`;
- `D=2`, `n=[200,200]`, `n_tilde=[200]`;
- reservoir memory `m=720`, washout 500;
- direct output/covariate memory 180;
- `rho=.95`, `pi_w=.03`, `pi_in=1`, input scales `.18`;
- shared RHS `tau0=.1`;
- AL VB-LD with `max_iter=150`, `tol=tol_par=1e-4`;
- 2,000 posterior draws and 500 xi samples; and
- the existing 50-iteration RHS global-scale freeze.

The anchor is predecessor rank 1,
`linked_alpha_profile_010_b20be44357`. Its ranking, config, and fit object are
SHA-256 pinned in the campaign YAML. The anchor initializes eligible candidates
but does not replace FR09 as the scoring baseline.

## Candidate design

The exact 20 candidates are:

| Family | Count | Design |
|---|---:|---|
| Cold controls | 2 | linked `alpha=.10`, discrepancy `tau0=1e-3` and `1e-4` |
| Linked interactions | 12 | `alpha={.0625,.075,.0875,.10,.1125,.125}` by discrepancy `tau0={1e-6,1e-4}` |
| Block-specific refinement | 6 | ordered reference/discrepancy alpha contrasts in `.075-.10`, discrepancy `tau0=1e-4` |

`alpha=.0625` intentionally maps the empirical boundary above the rejected
`.05` profile. Reservoir preflight may reject it; that is informative and
cheaper than fitting a contaminated state matrix.

The linked interaction candidates require numerically identical alpha/rho
specifications across the two separate DESNs. The block-specific candidates
relax only the leak-rate equality; their inputs, states, and priors remain
separate.

## Warm-start contract

Warm starts are initialization only. They do not alter the target likelihood,
prior, convergence tolerances, or iteration cap.

- The cold controls receive no fit-object source.
- Alpha changes use coordinate-transfer initialization and require cold
  confirmation before any promotion decision.
- At `alpha=.10`, changing only discrepancy `tau0` is an exact-design
  transfer.
- Target RHS state, AL latent weights, row moments, and objective traces are
  recomputed.
- No warm result can trigger full7 automatically.

## Screening and selection

Both actual reservoir blocks are screened before VB for spectral/leaky radius,
forgetting, finite/dead/saturated states, correlation, effective rank, and
conditioning. A reject decision is terminal and skips fitting.

The prospective selection contract is unchanged:

- primary p50 metric: forecast-window check loss;
- hard guards: pre-cutoff log1p MAE over all history and trailing
  1000/200 observations;
- trailing-50 fit remains a warning rather than a hard gate;
- required forecast improvement over FR09: 3%;
- p50 check loss is never reported as distributional CRPS; and
- full7 plus genuine quantile-grid CRPS are required before article promotion.

## Execution and storage

The tracked definition is:

```text
application/config/glofas_p50_alpha_tau_focused_20260820.yaml
```

Preparation:

```bash
Rscript application/scripts/glofas_median_response_surface_prepare.R \
  --campaign application/config/glofas_p50_alpha_tau_focused_20260820.yaml \
  --authorize_launch true
```

The generated launcher is:

```text
local_trackers/runtime_configs/glofas_p50_alpha_tau_focused_20260820/launch_screen.sh
```

It uses 20 unique single-core assignments, BLAS/OpenMP thread caps, load,
memory, and disk admission gates, and resumable status markers. Complete-batch
finalization writes ranking, selection, preflight, cleanup, and hash-bearing
status evidence. Nonwinner heavy objects are removed only after all 20
candidates are terminal; rank 1 remains protected.

## Decision boundary

After completion:

1. compare warm and cold controls to quantify path dependence;
2. inspect all reservoir repairs/rejections and VB convergence;
3. cold-confirm up to three genuinely improved treatments if needed;
4. stop if gains remain inside the repeatability envelope or below 3%;
5. run all seven quantiles only for a cold-confirmed eligible treatment; and
6. hand article-safe evidence to the integration lane only after full7 passes.

This campaign does not modify PriceFM, validation, joint-QDESN, package-engine,
main, or Overleaf branches.
