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

## Recorded diagnostic findings

At diagnostic source `dd83bfabc89000132e39ab803db4462673bcf5f9`, the 42
scalar cases pass their independently checked reference and coordinate-update
comparisons. The 36 nonmedian approximation-accuracy failures remain explicit.
The 34 affine checks pass; their Gaussian references condition on augmentation
moments. Both suites reject deliberate source mutations. The generated reader
contract suites pass 99 and 58 checks, and the pure equation suite passes 53.

For example, at probability 0.05, the reported Gaussian-factor quantile has
probability approximately 0.137243 under the exact AL distribution, rather
than 0.05. The analytic AL CDF and independent Normal-mixture integration agree
within `1e-8`. This controlled example isolates an approximation limitation;
it does not estimate how much of the application's loss it explains.

The first authenticated read inspected one truth-free design and the
independent AL fits at 0.05 and 0.50. Both retained future covariances are
symmetric and positive definite; their condition numbers are approximately
30.42 and 96.33. Stored reference and discrepancy Jacobians exclude current
and later latent responses. These are saved-state checks, not a fresh
reconstruction of every feature or proof of complete optimizer convergence.

A separately admitted read evaluated the median coordinate equations and two
tiny frozen configurations. All 44 named prior-field comparisons passed. The
reference/discrepancy global-prior scales are `5.2043087e-5` and `0.0001159`;
both intercept precisions are `1e-9`, with slab hyperparameters 2 and 4. This
does not certify every unlisted prior or the uninspected multiquantile fits.

The median future block is close to its linearized coordinate equations:

| Diagnostic | Value |
|---|---:|
| Maximum absolute preconditioned step, not applied | 5.4346395e-5 |
| Covariance relative Frobenius discrepancy | 3.5140297e-5 |
| Normalized linear-solve residual | 3.3198892e-17 |
| Linearized precision condition number | 96.3280 |

At horizon 17 the saved path mean is -0.416236, whereas the conditional
reference plug-in is 2.409956. The reference and issued-factor gradient terms
are approximately -4.427515 and +4.427156, leaving a small residual. At the
terminal horizon, where there are no later factors, the path mean and
conditional reference location agree to about `1.7e-10`. The displacement is
therefore supported by the executed coupled equations; its magnitude alone
does not establish a coding or stopping defect. Full-state, three-pass
stability and accuracy relative to the nonlinear posterior remain unverified.

The independent exact two-horizon AL example provides a useful distinction.
With conditional reference location zero, its exact earlier-response median
is -0.010185 with one later member and -1.986548 with 51 ordinary later-member
factors. Thus conditioning on later issued information can itself substantially
move a response marginal. This example does not quantify that effect in the
application. Its 51-member mean-field median also fails the separate CDF
accuracy check, illustrating that posterior conditioning and approximation
error can coexist.

## Decision and remaining gate

No iteration-only production rerun is justified by these diagnostics. No
production kernel, prior, feature map, result table, figure or manuscript has
been changed. The current article packet is retained, including its adverse
results; this closeout does not approve a replacement scientific authority.

A new inference implementation would need to preserve the mathematical target
and qualify all coupled expectations. Collapsing future AL auxiliary variables
changes the coefficient objective; retaining a structured future block requires
joint moments rather than products of separate expectations. Neither is a
drop-in correction established by the scalar example. Replacing a marginal
quantile with the conditional plug-in, or freezing historical parameter
learning, is not automatically inference-equivalent.

Before another campaign, require an independently reviewed same-target
derivation, relevant one-/two-horizon and uncertain-parameter benchmarks,
exAL/MQ qualification where affected, accurate objective/stopping accounting,
and a timed feasible dependency schedule. Preserve the protected scoring
window throughout. Do not seek a favorable run by seed or prior selection.

## Diagnostic placement and unchanged scientific authorization

The four mathematical and read-only equation helpers live under
`scripts/diagnostics/`, not the production `application/R/` surface. They
provide generated reference iterations and evaluation of supplied numeric
state, without a scientific dispatch or retained-fit continuation entry point.
The generated tests, diagnostic driver and guarded reader import those exact
paths; any later admitted reader must pin the updated source closure.

Both production source guards, their immutable manifests and all three
historical source/editorial consumer tests remain byte-identical to the
pre-diagnostic authority. They run against the current repository without a
historical-fixture exception or an expanded scientific grant. The original
scientific paths, modes, working/index checks and mutation rejections remain
active. This placement separates diagnostic evaluation from production model
implementation; it does not authorize inference changes in an unguarded path.

The numerical findings above and their source-bound private receipts remain
at their original diagnostic commits, including
`dd83bfabc89000132e39ab803db4462673bcf5f9`. Relocation does not rewrite those
receipts, reopen a closed purpose, reidentify a fitted object or authorize a
new retained-payload read. No production guard, fitting source, scientific
result or article asset is changed by this integration repair.
