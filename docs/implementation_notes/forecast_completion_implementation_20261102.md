# Forecast-completion implementation and scientific admission boundaries

## Purpose

This source lane implements the safe, independently testable portions of
the remaining-work audit prepared on 2 November 2026. It preserves the
approved forecasting targets and active GloFAS source. It does not equate a
software test, a small numerical qualification, a complete scientific packet
and an article release.

The previous source authority is
`951ee40b74b4830fac23809ed4369fa469474a91`. The GloFAS same-family campaign
continues independently at its frozen source. PriceFM and Phase182 are not
modified by this lane. No model refit, source evidence deletion, posterior
thinning or article change is implicit in these additions.

## Three independent source paths

The IND method is documented in
`ind_ancestor_first_filter_and_future_cdf_20261102.md`. It introduces an
ancestor-first auxiliary proposal, actual causal continuation states and
known-feature future marginal CDFs. A reporting mixture is not a continuation
state. Static training-posterior weights remain fixed. The exAL lookahead
approximation changes the proposal, with an explicit residual importance
ratio and evidence normalizer; it is not a new likelihood or posterior.

The MQ array method preserves the original source kernels, random-purpose
keys, recursion, projection and endpoint response law. Its compact raw
coherence counters describe pre-projection path kernels. They must not be
relabelled as historical mean-grid crossing rates or inferred from the
ordered integrated quantiles. Allocation reduction is not evidence that
the complete campaign is affordable.

The corrected GloFAS closeout must assemble all sixteen accepted quantile
fits and the separately authenticated Normal/raw-ensemble reports. Its
seven-family surface contains exactly 1,372 forecast rows on twenty-eight
dates and seven probability levels. Protected USGS truth is a post-fit
scoring input. An incomplete cohort, a historical Gaussian future-path
target, or an incompatible Normal reporting convention must not pass by
changing a path or status label.

Each source path can be developed and tested independently. Their genuine
numerical/producer qualifications remain separate. A completed GloFAS
packet need not wait for either simulation reconstruction.

## Typed numerical evidence

`scripts/integrated_quantile_receipts_v2.R` is a new, opt-in numerical
receipt interface. It does not modify the original DKW validator or silently
enable its method in the production worker/controller/scorer.

Its supported method is the fixed-draw, observed-origin held-out conditional
CDF certificate. The final Welford count, mean and second central moment,
frozen training candidates, split diagnostic, source identities, look
allocation, contiguous stream ranges and final replay-chain root are retained.
The validator independently reconstructs endpoint locations, sample variance,
confidence radius and quantile-bracketing inequalities. It ignores a
producer's PASS label. The original full qualification packets remain intact.

The empirical-Bernstein radius is

\[
 r_n=\sqrt{2s^2\log(4M/\alpha_\ell)/n}
       +\frac{7\log(4M/\alpha_\ell)}{3(n-1)}.
\]

Training uses IDs 1--65,536. Validation uses disjoint IDs
65,537--327,680 with the three original prescribed looks and alpha .05/3
per look. The original .01 absolute-OR-relative quantile and .005 split
criteria are unchanged. No optional look, altered candidate, or particle-
filter interpretation is allowed.

The probability statement concerns future iid paths conditional on one
parameter/origin. It is neither an origin-filter accuracy guarantee nor
a campaign-wide familywise guarantee. Receipt hashes detect changes; they
do not prove source identity, iid generation or numerical accuracy by
themselves. Authentic source/runtime/stream qualification and central
production admission must provide those separate assurances.

A canonical numerical-column hash avoids a genuine serialization trap:
equivalent data frames may have different attribute ordering after column
extraction. The full receipt and typed block still have integrity hashes.
The v2 reference block codec retains complete members without thinning or
averaging, rejects mixed models/targets/geometry and validates on both pack
and unpack. It is a correctness reference, not yet the fully amortized,
priced production storage codec. In particular it does not imply that
millions of such reference objects have an approved storage price.

An IND filter/future calculation cannot be accepted through this MQ receipt.
It needs its own evidence type and qualification. GloFAS's analytic Gaussian
VB future-response summaries are a third calculation, not either simulation
receipt method.

## Complete-workload cost gate

`scripts/check_forecast_reconstruction_admission.py` checks a SHA-pinned,
small external cost contract. It requires a complete native stratum registry,
one source-identical measured benchmark per declared stratum, reviewed
precision/parity/source-smoke artifact bindings and at least 25 percent
prospective contingency.

CPU, wall-work, artifacts, logs/administration, setup/scoring/transfer/
controller overhead, measured peak RSS and physical retained-output storage
are priced explicitly. The host checks subtract other lanes' reservations,
staging and final retained allocations before enforcing disk floors.
The sum of physical retained allocations must cover the complete priced
output, not merely an arbitrarily large global byte budget.

The cost checker rehashes the pinned review files but does not interpret or
authenticate all scientific/runtime semantics in them. Its result therefore
explicitly records `external_receipt_semantics_validated_here=false`,
`host_and_numerical_admission_still_required=true` and
`allow_launch=false`. The actual host/source/grant/accounting controller
remains authoritative. An optimistic capacity floor is not an ETA; neither
queue time nor the sequential qualification/closeout work disappears when
CPU time is divided by a core count.

Usage is read-only:

```bash
/usr/bin/python3.11 scripts/check_forecast_reconstruction_admission.py \
  --contract /absolute/path/to/frozen-cost-contract.json \
  --sha256 FULL_SHA256
```

A failed gate returns `NOT_ADMITTED`; it never renews a price, chooses a
new seed, changes a target or launches a job. The shipped multihost
production defaults remain disabled.

## Remaining hard gates

Before genuine simulation production:

1. Authenticate the complete native Q--DESN/MQ membership, feature replay,
   empirical weights and joint/product coupling. Keep criterion-specific
   IND specifications; do not equate metric labels with native draws.
2. Finish source-bound representative IND filter/future and MQ numerical
   qualification. Retain all historical REVIEW evidence. Source-level
   synthetic checks do not replace those executed qualifications.
3. Finish versioned production worker/block/controller/scorer dispatch,
   exact source inventories, independently checked evidence and compact
   retention. Preserve all original v1 guards under their historical scope.
4. Revalidate standalone qualification against the actual production
   numerical closure. If IND VB is included, authenticate and validate its
   full factor route before pricing.
5. Pass the complete measured cost, precision and physical storage gate.
   Qualify each method/source/host on its actual compute runtime, with
   fresh grants, single-coordinator ownership, recovery and accounting.
6. Only then issue finite reconstruction purposes. Time recursion stays
   local to a trajectory/filter; independent parameter blocks can be
   dispatched in parallel. Seal the required forecasts before protected
   scoring. Promote only complete, reviewed scientific packets.

Before GloFAS scoring/promotion, all sixteen fits must be accepted and
their terminal/convergence evidence must pass. The closeout must use an
authentic pinned, quiescent ledger snapshot, separate Normal bindings and
genuine raw-member/history extracts. It must not read truth early or
pretend that the still-running fit packet is complete.

Article regeneration, both manuscript compilations, anonymous/source-bundle
checks and the existing guarded command-line Git publication follow the
approved scientific handoffs. No Overleaf publication is warranted by this
software-only lane. Final whole-article readiness additionally depends on
the external PriceFM authority.

## Verification

Focused tests are registered in the combined repository harness. They use
synthetic inputs, bounded one-thread execution and no protected fit/truth
reads, scheduler submission or source-runtime mutation. The integration
receipt records the exact commands, outcomes, resource limits, changed
surface and remote readback. A complete project declaration remains blocked
until the scientific, production and publication gates above actually pass.
