# Gaussian baseline reuse and response-quantile reporting

This additive continuation starts from main
`386d50be0f4ced2000b061af68f03868d0a9de38`. It does not modify the frozen
GloFAS fitting checkout, its master authorization, source manifest, ledger,
numerical kernels, priors, stopping rules or active workers. PriceFM and
Phase182 are outside its scope. No manuscript or article asset changes here.

## Statistical distinction

The retained Normal Ridge and Normal RHS fits already include a normalized
Normal future-response transition and all unit-weight issued-member factors.
The replacement Gaussian driver prior affected the quantile branch, not
these Gaussian fits. The source inspection therefore found two reuse
candidates, rather than a reason to fit either Gaussian model again.

Reuse nevertheless requires more than matching dimensions or convergence
labels. Authenticate both original retained fits, their design, original
prior and numerical-control records, target receipts and actual numerical
runtime. Compare the prepared transition design with the original design,
allowing only the explicitly described metadata changes. Reservoirs,
observations, issued members, transformations, dates, feature order and
future-feature construction must remain identical. Functions are not
executed merely to prove identity.

The original reporting used empirical type-8 quantiles of 500 simulated
future responses. The new reporting uses analytic marginal quantiles of
the same retained, ensemble-conditioned Gaussian variational response
factor:

\[
q(U)=N(m_U,V_U),\qquad
Q_h(p)=\exp\{m_{U,h}+\sqrt{V_{U,hh}}\,\Phi^{-1}(p)\}-1.
\]

This is a reporting change, not a changed fitted posterior. Do not add
another independent response error, substitute the reference readout, or
describe response quantiles as credible limits for a quantile functional.
Keep the old reporting identity and its evidence separate from the new
analytic-reporting identity. The existing conservative identity helper
remains unchanged; no identical-reporting check is weakened to admit reuse.

## Reporting-only execution

`scripts/glofas_normal_reuse_enrollment.R` supplies independently testable
identity, retained-fit and analytic-quantile checks.
`scripts/enroll_glofas_normal_baselines.R` executes them only against an
explicit, hash-pinned external reporting contract and a clean frozen source.
The contract binds both Gaussian baselines together; no favorable-result
selection or one-model enrollment is permitted.

The finite metadata/reporting purpose has one separate administrative CPU,
32 GiB address space, 240 CPU seconds, a 300-second external wall boundary
and at most 64 MiB of output. It does not use the active fitting cores or
inherit a production-fit grant. Actual process limits, source identity,
input sizes and hashes, and before/after retained reads are checked.
Outputs belong in a fresh ignored namespace and include the design-mapping
receipt, original input/runtime provenance, 392 response-quantile rows
(two models by 28 horizons by seven levels), and an artifact manifest.

The new rows have no fit-worker identity: they explicitly record reused
fits and zero new model fits. They must not masquerade as accepted outputs
of the ongoing 16-fit campaign or alter its original preparation receipt.
Later scientific closeout must bind these reporting artifacts separately
and verify their compatibility with all 16 accepted quantile fits before
scoring or article publication.

The first reporting admission stopped at the host check, before any retained
design or fit was read: R exposes Muscat's fully qualified hostname whereas
Python reports its short name. The reporting preflight now recognizes only
the two exact Muscat identities and requires Linux and R 4.6.0. Negative
tests reject Jerez and unrelated lookalike names. The failed admission and
its resource use remain retained; no scientific target or tolerance changed.

## Verification and remaining gates

The registered synthetic test covers exact metadata mapping, protected
data and future-feature identity, original model/prior/control checks,
convergence eligibility, covariance validity, response-quantile transforms,
complete keys and negative mutations. A real reporting receipt is a
separate check against the authentic retained evidence; synthetic success
does not claim that enrollment has occurred.

Run the focused test and complete registered repository harness on the
frozen combined tree, with R 4.6.0. Keep the original source guards and
their negative tests unchanged. Integrate through a fresh `--no-ff`
coordinator worktree and the guarded command-line-Git publisher. Actual
receipts and resource measurements remain ignored, not committed runtime.

Complete GloFAS promotion still requires every quantile fit to pass its
unchanged gates, separate acceptance of both baseline reports, post-fit
scoring, a coherent full comparison and regenerated article assets,
manuscript builds and direct-Git publication checks. This code integration
is not scientific-release or Overleaf-publication approval.

MQ simulation reconstruction remains held by the authentic cost/precision
qualification. Independent-study reconstruction additionally requires a
consistent conditional state filter; the training-parameter posterior is
to remain frozen. Neither requirement is solved by this reporting-only
continuation.
