# Phase170 exact exQDESN MCMC default promotion

## Purpose

Phase170 converts the completed Phase169R method-development campaign into an
auditable production-default decision. It does not change the exAL model,
posterior target, DESN specification, prior, or article results. It selects the
exact transition used when an exQDESN MCMC caller omits `method_id`.

## Evidence boundary

Phase169R completed 240 of 240 chains: five scenarios, Joint and Independent
readouts, three exact methods, and eight chains per cell. All 720,000 retained
draws were finite, all 240 worker checkpoints verified, and raw and contract
crossing counts were zero. The campaign nevertheless retained review flags for
mixing and first-four/last-four functional variation. Phase170 keeps those flags
visible and does not reinterpret them as failures of the model.

The promoted method is `M0_v_collapsed_support_logit`:

- augmentation: the established \(v_i\) representation;
- scale update: sigma collapsed from the gamma target and redrawn exactly;
- gamma coordinate: logit transform of the native bounded support;
- posterior target: the exact exAL target.

M1b has the strongest median gamma bulk ESS, five of ten forecast-MAE cell wins,
and runtime within roughly two percent of M0. Its scalar parameter summaries
agree with M0, but five fitted/forecast quantile-path cells remain outside the
stricter target-invariance tolerances. Following the predeclared decision rule,
M1b therefore remains an explicit candidate and M0 becomes the production
default. The probability-logit M1 method remains available for diagnostics but
is not promoted because it is materially slower, wins only one cell, and has
weaker worst-case bulk ESS.

## Target-invariance audit

The promotion script verifies three levels of evidence before accepting the
checked-in policy:

1. Phase169R top-level, freeze, and all worker manifests must verify.
2. M0 and M1b posterior parameter summaries must agree within declared
   standardized-difference and central-interval-overlap tolerances.
3. Fitted and forecast quantile-readout paths reconstructed from retained beta
   and intercept draws must satisfy analogous path-level tolerances.

Forecast score differences are supporting evidence only. Since M0 and M1b
target the same posterior, small score differences are treated as Monte Carlo
variation rather than as different model specifications.

## Default contract

The policy is stored in
`application/config/joint_exqdesn_inference_default_policy_v1.csv`.

After promotion:

```r
app_joint_exqdesn_fit_mcmc_dispatch(...)
app_joint_exqdesn_fit_independent_mcmc_dispatch(...)
```

resolve omitted `method_id` values to `M0_v_collapsed_support_logit`.
Reproducible or historical launches should continue to pass an explicit immutable
method identifier. `MCMC_legacy_default`, M0, M1b, and M1 remain explicit
overrides. VB dispatch is unchanged because Phase170 contains no new VB method
selection evidence.

The policy is enforced at the canonical exQDESN dispatch boundary. Historical
phase scripts that call `app_joint_qvp_fit_exal_mcmc_tiny()` directly retain
their frozen behavior and are not retroactively rewritten. New launch code must
use the dispatch API, and article-confirmation code should pass the selected M0
identifier explicitly so its manifest does not depend on an ambient default.

This default applies to both Joint and Independent exQDESN MCMC dispatch. It does
not force one DESN or RHS specification across scenarios; case-specific model
controls remain separate from sampler selection. It does not alter AL QDESN,
PriceFM, GloFAS, historical frozen campaigns, or article assets.

## Reproduction

```bash
Rscript application/scripts/231_promote_joint_exqdesn_phase170_exact_mcmc_default.R
Rscript application/tests/test_joint_exqdesn_phase170_default_promotion.R
Rscript application/tests/test_joint_exqdesn_inference_dispatch.R
```

The generated artifact is
`application/cache/joint_exqdesn_phase170_exact_mcmc_default_promotion_20260808`.
It contains source verification, parameter and quantile-path invariance tables,
method evidence, promotion gates, the frozen decision, provenance, and a SHA-256
manifest.

## Interpretation and next step

M0 is the production computational default, not a claim of universal predictive
dominance. M1b remains available for targeted method development. The next
expensive run should be a balanced article-confirmation campaign using explicit
M0 identifiers and scenario-specific winning DESN/RHS controls. Article assets
should change only after that campaign passes its own reproducibility, mixing,
functional-stability, and quantile-contract gates.
