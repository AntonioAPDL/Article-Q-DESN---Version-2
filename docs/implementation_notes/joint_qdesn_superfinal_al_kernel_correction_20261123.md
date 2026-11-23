# JOINT super-final AL kernel correction

Date: 2026-11-23

## Scope and preservation

This correction responds to the integration review of frozen branch
`work/joint-qdesn-superfinal-predictive-stability-20261122` at
`5995ac30fae8070cb2fcef1a4cce659886c83d40`. The frozen branch, its source
runtime, its super-final runtime, article files, and Overleaf files were not
modified. No production fit, score, or forecast was launched.

The correction branch is
`work/joint-qdesn-superfinal-al-kernel-correction-20261123`. It changes the AL
transition and qualification infrastructure only. Exact-M0 exAL remains
`M0_v_collapsed_support_logit` and is not refitted by this finding.

## Root cause and mathematical correction

The campaign wrapper applied chain-specific jitter to the VB initialization and
then calculated

```
sigma_upper = max(1, 10 * max(initial_sigma))
```

The AL sampler drew from an inverse-gamma full conditional and clipped that
draw to the resulting interval. Consequently, numerical starting values
changed the Markov transition and introduced a boundary point mass. This was
not the declared model.

Under the implemented tempered AL mixture kernel and prior
`sigma_k ~ IG(a_sigma, b_sigma)`, the scale conditional for quantile `k` is

```
sigma_k | rest ~ IG(shape_k, rate_k),       sigma_k in (0, Inf)

shape_k = a_sigma + (3/2) * kappa * T

rate_k  = b_sigma + kappa * [
  sum_t(v_tk) + (1/2) * sum_t{
    (r_tk - A_k v_tk)^2 / (B_k v_tk)
  }
]
```

where `r_tk = y_t - alpha_k - z_t' beta_k`. For this campaign `kappa = 1`.
The exact update is therefore one direct inverse-gamma draw on positive,
unbounded support. A finite cap is neither part of this posterior nor an exact
truncated inverse-gamma update.

The corrected sampler:

- normalizes legacy `sigma_bounds` arguments to `(0, Inf)`;
- performs the direct inverse-gamma draw without clipping;
- records `direct_inverse_gamma_unbounded_v1`;
- reports diagnostics against the fit's actual support rather than a stale
  wrapper argument.

## Target and kernel identities

Historical `posterior_target_sha256` is retained for provenance. New artifacts
also record:

- `complete_posterior_target_sha256`, covering likelihood identity, fit
  structure, quantile grid, response/design fingerprint, RHS prior, scale
  prior, intercept prior, coefficient hierarchy, gamma-prior identity, and
  `(0, Inf)` scale support;
- `effective_sampler_control_sha256`, covering inference method, scale update,
  support, iteration/burn/thin budget, dense/precision controls, gamma controls,
  and independent-quantile seed stride.

Chains are rejected before scoring when either identity differs inside a model
cell. The super-final combiner also rejects historical capped chains mixed with
corrected uncapped chains. Whole-scenario fallback is implemented as an exact
four-model packet selection; favorable rows cannot be spliced across roles.

## Source-guard reconciliation

The historical transition guard and its manifest remain pinned. A new
composable guard verifies that historical authorization in full, verifies the
62-path JOINT manifest independently, and then requires the repository delta to
equal the exact 69-path union. The historical GloFAS mutation fixture remains
unchanged in behavior and still rejects all 43 expected mutations.

Source manifest:

`docs/reproducibility/joint_qdesn_superfinal_al_kernel_correction_sources_20261123.csv`

Pinned SHA-256:

`331437cf5a22dbb61f7d29374c9db356b68265e09ed5dd2adfe2e4e3b436a11d`

## Minimum coherent rerun

The rerun is deliberately staged.

1. Mandatory source correction: replace all 96 original AL workers, covering
   32 AL model cells and three chains per cell. Reuse the frozen designs, VB
   initializers, priors, reservoirs, DGP fixtures, chain seeds, and budgets.
2. Mandatory rescoring: recompute all 32 AL score cells, then rerun complete
   four-model scenario decisions with the unchanged exact-M0 exAL evidence.
3. Conditional supplement: rerun the five persistent-heavy-tail challenger
   joint-AL supplemental chains only if the corrected source audit still
   requires that target. Never combine their historical capped versions with
   corrected chains.
4. Rebuild the final packet and qualification receipts only after all required
   target/kernel hashes and manifests verify.

The mandatory historical cost was 43.83447 CPU-hours and 0.12152 GiB of AL
worker payloads. The conditional supplement was 2.06559 CPU-hours and 0.00473
GiB. Idealized wall-clock lower bounds are about 5.7 hours on 8 cores, 3.1 hours
on 15 cores, or 1.8 hours on 25 cores for all 101 chains; reserve 4 hours on 15
cores and at least 0.5 GiB of free disk for orchestration, rescoring, and
manifests.

Machine-readable scope:

`docs/reproducibility/joint_qdesn_superfinal_al_kernel_rerun_scope_20261123.csv`

## Qualification gates

- 96/96 mandatory AL workers complete, zero failed, finite draws.
- One complete target hash and one kernel hash per model cell.
- No finite AL support cap and no clipping code path.
- 32/32 corrected AL score cells complete and finite.
- Zero contract crossings under the frozen forecast contract.
- Complete-scenario selection and fallback only; no row splicing.
- If required, 5/5 corrected supplemental AL workers complete before the
  eight-chain score is formed.
- Existing exact-M0 exAL and RHS regressions pass.
- All nested manifests, transfer inventories, and hashes verify.
- Article and Overleaf remain unchanged until the corrected result packet is
  scientifically reviewed.

Mixing remains a review diagnostic rather than an automatic scientific veto,
consistent with the lane policy. Pathological predictive functionals, invalid
hashes, nonfinite scores, or incompatible kernels are hard failures.

## Interpretation constraints

- Overlapping score intervals do not establish formal predictive equivalence.
- The evaluation realization was excluded from candidate selection but was
  evaluated previously; it is not described as previously unseen.
- Architecture and shrinkage settings changed together in the frozen campaign,
  so an improvement cannot be attributed to one hyperparameter.

## Decision

The code correction is ready for coordinator review. The scientific packet is
not ready for article integration until the mandatory corrected AL rerun and
rescoring pass the gates above.

`NOT_READY_FOR_INTEGRATION`
