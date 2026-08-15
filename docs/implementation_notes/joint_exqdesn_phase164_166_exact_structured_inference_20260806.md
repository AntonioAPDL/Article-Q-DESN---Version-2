# Joint and independent exQDESN exact/structured inference, Phases 164--166

## Purpose and decision boundary

Phases 164--166 implement the first gated comparison of alternative exAL
scale--shape inference methods for Joint and Independent exQDESN. The model,
case-specific DESN/RHS specifications, Phase153 data, split, quantile grid, and
scoring contract are frozen. Only the inference approximation changes.

This stage does **not** update article tables, select an MCMC method, or claim
that structured variational inference is superior. Phase166 is a full-size
method-development campaign. Its paired results determine whether one
structured VB method is stable enough to initialize a later exact-MCMC method
comparison.

## Frozen scientific contract

- exAL is retained as the working likelihood, with `kappa = 1`.
- The native gamma support and the inverse-gamma scale prior are unchanged.
- Joint and Independent fits use their frozen scenario-specific Phase153
  DESN/RHS controls.
- The quantile grid is `0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`.
- The fit and validation windows contain 500 and 1,000 rows, respectively.
- Raw quantiles are retained; the monotone contract grid is used for scores.
- Validation remains quantile-grid based: oracle MAE/RMSE, check loss,
  integrated quantile-score grid CRPS, interval diagnostics, and crossings.

## Implemented inference methods

The versioned registry is
`application/config/joint_exqdesn_inference_method_registry_v1.csv`.

| Method | Augmentation | Scale--shape treatment | Role |
|---|---|---|---|
| `VB0_point_v` | current `v` | point gamma; current GIG scale moments | verified baseline |
| `VB1_structured_v` | current `v` | `q(gamma) q(sigma | gamma)` | structured bridge |
| `VB2_structured_u` | `u = B_gamma v` | `q(gamma) q(sigma | gamma)` | primary structured candidate |
| `M0_v_collapsed_support_logit` | `v` | sigma-collapsed gamma; exact GIG redraw | exact baseline |
| `M1b_u_collapsed_support_logit` | `u` | sigma-collapsed gamma; exact GIG redraw | augmentation isolation |
| `M1_u_collapsed_p_logit` | `u` | sigma-collapsed gamma; exact GIG redraw | primary exact candidate |
| `K_branch_inverse_cdf` | `u` | branch-normalized fixed-state reference | correctness control |

Omitting a method identifier preserves the historical VB and MCMC defaults.
Focused regression tests verify that the explicit legacy paths return the same
results under the same seed and inputs.

## Exact u augmentation and collapsed scale block

For `p = p_gamma`, define

```text
k = A_gamma / B_gamma = 1/2 - p,
u_i = B_gamma v_i,
k^2 + p(1-p) = 1/4.
```

Then

```text
u_i | sigma,gamma ~ Exp[p(1-p)/(2 sigma)],
y_i | u_i,s_i,... ~ N(mu_i + sigma lambda_gamma s_i + k u_i,
                       sigma u_i).
```

Conditioning on the remaining blocks, sigma has a GIG kernel. The gamma
transition integrates sigma analytically and redraws sigma exactly at the new
gamma. `M1b` and `M1` therefore combine the `u` augmentation and sigma collapse;
they differ only in the scalar gamma coordinate.

The structured VB methods use the same conditional GIG algebra to retain
gamma--sigma dependence. Their monitor is deliberately labeled
`structured_cavi_coordinate_monitor_not_full_elbo`; the current accounting is
partial because local-factor and point-intercept entropy terms are not yet
reported. It must not be described as a complete ELBO.

## Numerical implementation

The additive engine is
`application/R/joint_exqdesn_exact_structured_inference.R`; opt-in dispatch is
in `application/R/joint_exqdesn_inference_dispatch.R`. Historical functions in
`joint_qvp_qdesn.R` are not rewritten.

Important numerical safeguards are:

1. vectorized, safeguarded inversion from `p_gamma` to native gamma using a
   cached monotone map plus Newton refinement;
2. effective `p_gamma` endpoints induced by the frozen native support, so the
   new coordinates do not silently enlarge the historical posterior target;
3. separate negative and positive gamma branches;
4. mode-centered composite Gauss--Legendre quadrature in branchwise
   `logit(p_gamma)` coordinates, with the exact native-gamma Jacobian;
5. stable large-order evaluation of `log K_nu(z)` and GIG moment ratios, with
   an exact inverse-gamma limit;
6. a standardized log-sigma direct-integral reference centered at the analytic
   GIG mode;
7. compact CSV diagnostics only; no default RData, RDS, or full fit objects.

The production quadrature sequence uses orders 4, 8, and 12 per mode-centered
panel. Diagnostics report order per panel, total nodes, branch masses, and
successive normalized-moment changes.

## Phase164 source and method freeze

Run:

```bash
Rscript application/scripts/216_prepare_joint_exqdesn_phase164_165_exact_structured.R
```

The default Phase164 artifact is:

```text
application/cache/joint_exqdesn_phase164_source_method_freeze_20260806
```

It verifies all upstream manifests, freezes the first ten Phase153 replicates
per scenario, materializes 80 scenario-specific fixture shards, and creates a
480-row registry:

```text
80 scenario replicates x 2 structures x 3 VB methods = 480 rows.
```

The 160 `VB0` rows are reused only after candidate-manifest verification. The
320 structured rows are new fits. The selected fixture shards are stored under
`application/cache/joint_exqdesn_phase166_selected_fixtures_20260806` so each
worker avoids rereading the 6.2 GB Phase153 source bundle.

Current real-data Phase164 result: `pass`, with zero source-hash failures, 80
selected scenarios, 240 hashed fixture shards, and all 480 registry rows.

## Phase165 exact controls

The same prepare script writes:

```text
application/cache/joint_exqdesn_phase165_exact_algebra_controls_20260806
```

The controls use 500-row frozen states from Normal Bridge, Nonlinear
Reservoir-Friendly, and Regime Shift at the lower, central, and upper quantile
levels. The current gate result is:

| Check | Result |
|---|---:|
| transformed-density states | 36 |
| maximum `v`/`u` log-density error | `8.53e-14` |
| maximum direct sigma-collapse error | `5.75e-11` |
| branch-quadrature failures | 0 of 9 |
| Phase165 gate | `pass` |

These are mathematical and numerical controls, not performance pilots.

## Phase166 production campaign

The launcher is:

```bash
bash application/scripts/220_launch_joint_exqdesn_phase166_structured_vb.sh 32
```

It refuses an uncommitted worktree or an existing Phase166 worker/finalizer
session. Scenario-structure groups are assigned atomically: all three methods
for one group remain on one worker. Each worker builds the frozen-specification
`VB0_point_v` state once in memory and uses that identical state to initialize
both structured methods. No warm-start object is serialized.

The default output is:

```text
application/cache/joint_exqdesn_phase166_structured_vb_method_development_20260806
```

Each candidate checkpoint is atomic, hash-manifested, and restartable. The
finalizer runs only after every worker records `EXIT_CODE=0`.

An essential full-window timing check, not retained as evidence, measured
approximately 3.3 seconds per structured iteration after one-time coordinate
caching and below 300 MB RSS. A 32-worker launch is appropriate on the current
64-core, 503 GiB host while leaving capacity for unrelated active workstreams.

## Gates and next stage

Hard failure includes source/hash mismatch, malformed registry or split,
nonfinite fit/score, nonpositive scale, or contract crossings. Finite
max-iteration or quadrature-review states remain `review`; they are not silently
promoted.

After Phase166 completes:

1. audit paired `VB1`/`VB2` differences against `VB0` by structure, scenario,
   replicate, and tau;
2. freeze at most one structured method per model structure using declared
   implementation, stability, and functional-performance gates;
3. run fresh held-out confirmation only for a method that passes that freeze;
4. initialize the later exact-MCMC `M0`/`M1b`/`M1` comparison from the selected
   structured state;
5. touch article assets only after exact-MCMC confirmation is complete,
   reproducible, audited, and hash-manifested.

No later phase is launched speculatively while Phase166 is unresolved.

## Verification

```bash
Rscript application/tests/test_joint_exqdesn_exact_structured_inference.R
Rscript application/tests/test_joint_exqdesn_inference_dispatch.R
Rscript application/tests/test_joint_exqdesn_phase164_166_orchestration.R
# The historical exAL VB file is sourced by application/tests/run_tests.R;
# it is not a standalone Rscript entry point.
Rscript application/tests/test_joint_qvp_qdesn_exal_mcmc.R
Rscript application/tests/test_joint_exqdesn_phase156_collapsed_gamma_sigma.R
Rscript application/tests/test_joint_exqdesn_phase163b_corrected_closure.R
```

Every generated Phase164--166 artifact includes provenance and a SHA-256
manifest. Source commit and tree identifiers are regenerated from the committed
launch revision.
