# GloFAS fixed-target numerical diagnosis

This diagnostic separates implementation parity, variational fixed-point
stability and accuracy relative to a specified probability distribution. It
does not change the fitted GloFAS model or replace article results.

## Generated reference cases

The scalar AL cases hold location and scale fixed and compare the production
local-scale and future-response updates with an independent analytic fixed
point. The coordinate updates can agree exactly while the Gaussian response
factor has an inaccurate probability-level quantile. Such a result is retained
as an approximation-accuracy failure, not converted into a scientific pass.

The affine cases compare the production Gaussian–Delta helper with independent
quadratic calculations. They condition on fixed coefficient/scale and
augmentation moments; their Gaussian target is not the marginal AL law.
They test the incremental mean, stabilized covariance, literal member sums,
derivatives and the distinction between a Gauss–Newton approximation and the
full nonlinear Hessian. Generated causality fixtures do not authenticate a
saved application feature map.

A separate two-horizon AL reference integrates out the unobserved terminal
response exactly. Its earlier-response density is proportional to an AL
transition and ordinary issued-member factors whose location depends on that
earlier response. Independent split integration and a piecewise exponential
CDF show that later member information can move the exact marginal median
far from its conditional reference location. This is a controlled mechanism
check, not an attribution of the application's forecast loss or a proposal to
change its member weights. Mean-field accuracy is assessed separately.

The standalone entry point is:

```bash
Rscript scripts/audit_glofas_fixed_target_diagnostics.R \
  --out-dir NEW_IGNORED_DIRECTORY --generated-only
```

An exit status of zero means the software/reference checks passed. Inspect
`DECISION.json` separately for approximation-accuracy failures. No outcome of
this generated-only command authorizes a scientific campaign.

## Retained-state access

`scripts/glofas_fixed_target_forensic_reader.R` has a separate, hash-bound
read-only contract. Its first scope is exactly the authentic truth-free design
and the lower-tail/median independent AL pair. It authenticates the accepted
producer collection, input roles, model hashes, source, native resource limits
and fresh ignored output path before deserialization. It never calls a saved
callback, fits or updates a model, reads scoring truth, or publishes an article.

The compact exports identify the saved future mean/covariance, plug-in
reference/discrepancy decomposition, actual prior/nuisance summaries and
retained-Jacobian causality. A plug-in location is not automatically a
posterior expected location or a marginal response median. Complete-state
stability and requested-versus-executed prior equivalence require additional
admission if their inputs or operations are outside this reader's contract.

Original objects and failure receipts remain unchanged. Private purpose files,
payloads and output receipts stay outside Git. Any correction must preserve the
mathematical posterior, document changed execution identities and trace its
affected dependencies before production admission. An unfavorable score or
crossing alone is not a reason to change a prior, feature map, seed or target.

## Read-only coordinate-equation check

`scripts/glofas_fixed_target_stationarity_reader.R` has a new, separate
four-object purpose: two tiny frozen configurations, the truth-free design
and the median AL fit. It verifies the first reader's summary/manifest/native
terminal chain before using those summaries for named prior-field comparisons.
It compares only the specified scalar RHS/slab/intercept/schedule fields,
source-scale conditional shapes and linear prior terms; it does not assert
complete equivalence of every prior or initialization detail.

The pure helper evaluates the saved future-path gradient, its reference and
issued-member terms, the linearized precision and its covariance implication.
It retains the complete coefficient covariance, including cross-component
terms. A preconditioned gradient is reported as a diagnostic but is never
applied. The current probability is supplied explicitly from the authenticated
task, not inferred from the shared design. Numerical jitter is not interpreted
as a zero-centered prior.

Small residuals establish agreement with these coordinate equations only.
They do not establish three-pass stability of every variational factor, a
complete ELBO optimum, exact posterior accuracy, or a reason to select a new
forecast using the held-out responses.

## Verification scope

The new focused tests exercise generated references, deliberate mutations,
reader-contract rejection and generated-only reporting. The registered harness
runs them in isolated processes. This infrastructure does not itself establish
application convergence, posterior accuracy, improved forecasting, or a new
article authority.
