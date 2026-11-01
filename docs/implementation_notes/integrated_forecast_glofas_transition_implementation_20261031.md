# Integrated simulation forecasts and GloFAS future transitions

## Scope

This implementation starts from main
`48cb1bdc95f28ba7c38591b4a09df5266af2c2ad`. It implements the forecast and
execution workflows requested after the manuscript clarification. It does
not launch a campaign, revise a fitted posterior, replace article results,
change PriceFM, install a site environment, or transfer runtime evidence.
All production authority is external, finite, source-bound and initially
disabled. Existing GloFAS jobs and evidence are left intact.

The planning authority is the ignored 31 October consolidated forecast plan
and its three-host supplement. Their scientific distinction is retained:
describing an existing method, changing a forecast functional, and changing
a posterior target are different operations. The manuscript continues to
describe the currently reported methods until a completed scientific packet
supports a coherent replacement.

## Simulation forecast quantities

For retained parameter draw theta_b, simulate independent intermediate
response histories using that same parameter draw, fixed network matrices,
training-only transformations and the supplied covariate path. Each history
updates only its own reservoir. Average terminal conditional CDFs over these
histories and invert the resulting CDF. This estimates the multistep quantile
q_p(theta_b), not a location evaluated at averaged predictors and not a
conditional location from one randomly selected history.

The AL/exAL implementation preserves paired coefficient, scale and shape
draws and uses fresh likelihood errors. The MQ response law remains the
study's equally weighted isotonic grid, linear inverse-CDF interpolation and
endpoint atoms. Its CDF explicitly includes tied knots and clamped tails.
The four competing regression classes do not receive different response
generators. A joint posterior has its own cross-level dependence; independent
fits require an authenticated draw-assembly rule, not rank-coupling chosen
to improve a score. Original chain and source-draw identities are retained.

Integrating the conditional CDF over parameter draws gives a separate
posterior predictive CDF. Its quantile is not the posterior average of
q_p(theta). The API exposes this separate calculation; the default worker
does not save all inner CDF components or claim that a pooled predictive
quantile has already been materialized.

Random streams depend on scientific identity, original draw, origin, inner
replicate, horizon and sampling purpose. Host, worker count, routing blocks
and requested integration resolution do not enter the key. Increasing
resolution extends the same paths. Hash-derived CMRG states avoid reducing
a large nested calculation to one collision-prone 31-bit seed space.

### Numerical accuracy and uncertainty

Split-stream differences are numerical diagnostics, not posterior intervals
or confidence guarantees. The optional response-CDF DKW bound uses the same
independent inner responses already generated. Its confidence scope is one
parameter draw and origin, simultaneously over horizons and probability
levels. The source plan must allocate any additional multiplicity budget
across shards. Unresolved tail bounds remain infinite and cannot pass.

Production acceptance requires the predeclared DKW quantile-accuracy gate;
split-only results remain review evidence. No favorable-seed selection,
hidden threshold reduction or automatic unbounded resolution extension is
implemented. Numerical accuracy does not repair weak parameter mixing.
Existing scalar-mixing and score-stability reviews remain part of scientific
acceptance.

Quantile-only shards are written by default. Retaining inner CDF components
requires an explicit bounded request. Memory, wall time and total output
limits are tied to the coordinator's accepted reservation, not merely to
unverified command-line values.

### Native adapters and retained evidence

The MQ adapter uses existing reservoir snapshots, continuation, scaling and
readout helpers. The single-level adapter calls an authenticated native
`forecast_paths.qdesn_fit` kernel with paired parameters and explicit noise.
An isolated sourced-kernel environment can be enrolled when the installed
namespace does not provide that function. Original package version and
kernel hashes must match; installed exdqlm 1.1.2 is not silently substituted
for a historical 1.0.0 or 1.1.1 execution.

The dynamic-linear adapter requires genuine conditional origin-state
moments/draws together with the future observation, evolution and innovation
laws. The old deterministic-plugin filtering description does not establish
that evidence. Retained training-state draws are useful but do not by
themselves supply the conditional filtering law at every later origin.
Missing evidence blocks enrollment rather than triggering an undocumented
point-state approximation or refit.

The baseline also freezes its outer-conditioning convention: either integrate
the filtered origin state conditional on each parameter draw, or condition on
an authentically retained joint parameter/state draw. These define different
quantile-functional intervals and cannot be mixed within a model. Forecast
shards, score blocks and the model registry retain that convention explicitly.

The evidence preparer hashes explicit, regular, allowlisted files and writes
metadata only. It does not copy fitted objects, discover arbitrary caches,
simulate trajectories or modify frozen inputs. Forecast bundles exclude
scoring truth. The separate IND metadata catalog authenticates contracts and
capsules, labels payload hashes and adapter qualification as still required,
and does not call a metadata inventory a production-ready posterior.
The recursive call does not use future outcomes: MQ state reconstruction
truncates at each observed origin and the native single-level call supplies
`y_future_obs=NA`. This control is not proof that every historical fitted
object is physically redacted of unused future fields. Authentic bundle
qualification must also inspect origin-state, readout and payload provenance;
top-level role names alone do not establish that stronger property.

## Scoring and comparison

The scoring worker is separate from forecast construction. Only it receives
observed outcomes or DGP oracle banks. It authenticates the already accepted
forecast shards, their numerical-accuracy contracts, probability levels,
origin–horizon keys, and scoring sidecars.

Known-DGP expected check loss reuses sorted oracle draws and their prefix
sums. The multi-level score retains twice check loss and the unchanged
unnormalized trapezoidal weights. Single-level check loss has no additional
factor of two. Realized loss remains separate. Optional MAE/squared-error
records are labeled oracle quantile-path recovery, not response forecast
accuracy; their reference definition is explicit.

Origin shards retain draw-indexed sums and counts. Final posterior means,
medians and intervals are computed only after complete matching keys have
been aggregated. Unequal blocks are not given equal weight, block intervals
are not averaged, and a missing model/target registry cannot produce a final
comparison. Between-model contrasts require a separately frozen pairing map.
Quantiles from one CDF are ordered by construction; their zero crossings do
not replace the raw conditional-grid coherence diagnostic.

## GloFAS transition target

At each fixed probability level the new target is proportional to the
existing parameter prior and historical reference/product likelihood,
multiplied by one normalized source-Y future transition per horizon and
one unit-weight issued-product factor per member and horizon. The Gaussian
replacement path prior is absent. The product location remains q_ref+d,
not the latent future response plus d. Both recurrent maps are strictly
causal in the candidate future reference path.

There are 28 future-Y contributions per level and 28 times 51 product
contributions. GloFAS retains its authentic seven levels
0.05, 0.20, 0.35, 0.50, 0.65, 0.80 and 0.95; these differ from the MQ
simulation's grid. The source-specific error scales/shapes, historical rows,
coefficient priors and corrected RHS shape are preserved.

More explicitly, for one probability level p, parameters theta_p and future
reference path u_p=(u_p1,...,u_pH), the target is

\[
 \pi_p(\theta_p,u_p\mid\mathcal D,g)
 \ \propto\ \pi_p(\theta_p)L_{\mathrm{hist},p}(\theta_p)
 \prod_{h=1}^{H} f_{Y,p}\{u_{ph}\mid
       q_{ph}(u_{p,<h}),\sigma_{Y,p},\gamma_{Y,p}\}
 \prod_{h=1}^{H}\prod_{e=1}^{51} f_{G,p}\{g_{he}\mid
       q_{ph}(u_{p,<h})+d_{ph}(u_{p,<h}),\sigma_{G,p},\gamma_{G,p}\}.
\]

Here the historical data and the issued members are fixed inputs; future
gauge observations are not inputs. The two recurrent maps use only preceding
candidate reference responses and the frozen covariate paths. Each f_Y is a
normalized sequential response density from the stated family. Normal and AL
omit the shape parameter. No additional Gaussian density is multiplied into
this expression. Unit member weights also remove the powered-augmentation
ambiguity: the computational augmentation integrates back to each stated
likelihood factor.

For MQ fits, every level has its **own** u_p path. The adjacent-difference
prior couples coefficient blocks; the model does not multiply K transition
densities for a single common future path. These level-specific fits are not
an assertion of one common predictive response distribution across levels.

The additive wrapper calls the existing AL/exAL/MQ kernels with their
same-family future-Y factors enabled and no replacement Gaussian prior.
No active or historical kernel is edited. Tests distinguish target
normalization, augmentation, causal Jacobian and no-ensemble identities
from the quality of the local Gaussian–Delta approximation.

The 16-fit dependency graph starts from an authenticated compatible Normal
moment initializer, then median-outward AL, same-level exAL and complete-grid
MQ within each family. Initial values are not priors or inherited convergence
state. A missing median initializer blocks production preparation. Capped
fits are retained but are not accepted as converged prerequisites. The two
Normal reuse decisions remain blocked until complete identity is verified;
no assertion that all 18 models require refitting is made.

Reporting uses level-p marginal quantiles of the full ensemble-conditioned
Gaussian-VB future-reference factor, with the monotone inverse response
transformation. No second response error is added. These are approximate
response quantiles, not credible bands for an unknown quantile functional.
Separate level-indexed fits do not guarantee noncrossing; raw crossings are
retained. Mean readouts are not relabeled marginal predictive quantiles.

Existing numerical path jitter and MQ's small ridge floor remain recorded
stabilizers; synthetic sensitivity does not certify their effect in a real
fit. Legacy objective-monitor labels are not used to infer which path prior
or likelihood actually ran. Actual target flags, source counts and receipts
are checked explicitly. No current-window performance is used to retune
architecture, priors or stopping thresholds.

## Distributed execution controls

The shipped configuration has `launch_authorized=false`; all hosts are
unqualified, core grants empty and production budgets zero. These values
are intentional. Read-only planning creates neither a ledger nor a job.

A single coordinator-local SQLite ledger on Muscat owns task identities,
routes, claims, prerequisites and attempts. A remote lock file is not global
ownership. Claims are transactional; dispatch intent is exclusively created
and fsynced before external side effects. Budget charges survive failed or
ambiguous submission. A lost Slurm response requires exact accounting and
termination reconciliation, not blind resubmission.

The external authorization binds the full source and task definitions,
request/argv projections, input and posterior identities, qualified-host
receipts, fresh resource observations, finite grants and expiry. Claim
nonces fence output acceptance. An obsolete owner cannot promote a result.
Each claim also fixes a fresh nonsymlink output directory under that host's
qualified task namespace. A valid claim cannot redirect writes into another
lane. GloFAS uses its prepared `results/task_id/claim_nonce` namespace.

Qualified adapters are implemented for local Muscat processes, bounded
fixed-host Jerez SSH and Slurm submission on Hummingbird. Only source-owned
worker executables are admitted. Hummingbird scientific Python/R runs on
compute nodes, not login nodes. Remote verification requires separately
qualified compute-to-coordinator connectivity; no credential copying is
implemented. Missing connectivity is a failed gate, not a fallback to an
independent remote ledger.

Artifact capacity B and one merged-log allowance B are reserved and charged
as a total 2B disk budget. Workers check cumulative serialized artifacts
before writing; OS file limits additionally bound individual files and the
merged process log. Slurm workers redirect their own output to a bounded
regular file on the compute node. Memory and time limits are enforced by the
appropriate process or scheduler controls. These limits are not performance
measurements and must be qualified on the actual host before launch.

Admission respects physical topology and SMT siblings, current ownership,
aggregate reservations, measured memory, disk floors and scheduler limits.
The conservative Hummingbird ceiling is 72 aggregate CPUs or any stricter
limit. PriceFM grants and expired scopes are not reused. Cancellation is an
exact-identity dry-run proof only; it does not send a signal or clean evidence.

### Authorization inventory

External authorizations use `forecast_transition_authorization_v1` and need
`allow_launch=true`, approver, expiry, exact source commit/tree, source/input/
posterior/task hashes, allowed task IDs/hosts/operations, and the source
configuration hash. They also contain:

- `allowed_task_sha256`: full immutable task digests;
- `resource_receipt_sha256`: qualified fresh resource observations;
- `resource_grants`: admitted scope-specific grant digests;
- `qualified_hosts`: exact source/runtime/accuracy/connectivity receipts.

The scientific request digest excludes only declared operational envelope
fields. The frozen task-manifest digest excludes the subsequently attached
claim ticket. Controller helpers construct these projections; callers must
not invent a different JSON hashing convention. Secrets are not scientific
authorization fields.

Host qualification receipts are external canonical objects whose digest
excludes their own `receipt_sha256` field. They bind the already known source
commit/manifest, expiry, runtime and accuracy receipts, resource evidence,
output namespace and, for remote sites, compute-to-coordinator connectivity.
This permits qualification after a reviewed source commit without a circular
commit/receipt hash requirement. Per-host false/null values in the shipped
configuration describe the initial unqualified state; a nonnull source pin,
if later specified, is an additional constraint. The global false launch
switch and zero budgets remain hard blocks: activation requires a separately
reviewed source/configuration update followed by external qualification and
explicit launch authorization, not an untracked configuration overlay.
Likewise an empty source `core_grants` list does not confer ownership: the
external `resource_grants` digest is mandatory. A nonempty source list adds
another restriction on admitted grant identities.

The GloFAS preparer deliberately writes non-runnable templates. A compatible
parent initializer is checked against the accepted parent's actual nonce path
and file hash. Those values become known only after that parent finishes;
therefore complete requests are frozen and authorized by dependency-ready
wave, not pre-signed with fictitious future hashes. The implementation is not
an already qualified unattended 16-task multi-host campaign. The controller
transfers only its three small admission metadata files. Staging real accepted
dependencies on another host requires a separately authorized, hash-verified
evidence transfer; there is no implicit runtime copy.

Normal closeout is exposed through the tested controller `Ledger` API rather
than an unattended monitor. A verified exact host/job termination and closed
accounting receipt is supplied to `terminal`; only a successful attempt may
then reach `accept` with its complete producer manifest and ticket-bound
output directory. The same external authority must expressly allow
`record_terminal` and `accept`. Failed or ambiguous ownership can be rerouted
only through `reconcile_reassign` with old-owner termination, complete
accounting and no-orphan evidence. Charges and historical receipts survive.

Two conservative recovery cases intentionally stop for coordinator review:
failure during setup before a durable dispatch intent, and discovery that an
ambiguous submission succeeded. There is no public claim-abandonment or
same-nonce successful-job-adoption operation. Do not edit SQLite records,
delete receipts or retry automatically to bypass those states. A future
production coordinator must resolve them under a separately reviewed
recovery procedure or add narrowly scoped, tested recovery operations.

## Reproduction without production work

Use pinned R 4.6.0 and Python 3.11. The focused suites are:

```text
application/tests/test_integrated_quantile_forecast.R
application/tests/test_integrated_quantile_scoring.R
application/tests/test_integrated_forecast_evidence.R
application/tests/test_glofas_family_transition.R
application/tests/test_integrated_forecast_transition_source_guard.R
application/tests/test_forecast_transition_control.py
```

They are registered in `application/tests/run_tests.R`. Fixtures are synthetic,
source mutations use disposable files, and host/process/Slurm calls are mocked.
Any optional native-source fixture is evidence of a software interface test,
not qualification of a retained article fit.

Safe inspection starts with:

```bash
/usr/bin/python3.11 application/scripts/forecast_transition_control.py plan \
  --config application/config/forecast_transition_multihost_v1.json
```

The exact additive source manifest and a separately pinned guard authorize
only the new workflow files. The original twelve scientific files, their
historical authorization and original negative tests remain unchanged.
Removing the new manifest cannot hide new source additions.

## Remaining scientific preflight

Before any production run, freeze authentic bundles and original draw
coupling, qualify the historical IND kernel environment and later-origin
dynamic state law, allocate numerical accuracy/cost budgets, establish host
parity and released physical-core ownership, and obtain a new launch
instruction. The active Gaussian-path GloFAS campaign is not silently
converted, stopped or auto-promoted. Completing implementation is not the
same as completing a scientific campaign or approving article replacement.

## Implementation verification receipt

The implementation's registered repository harness passed under pinned
R 4.6.0, Python 3.11 and the existing isolated test environment. The native
interface fixture was explicitly enabled; its success is not historical-fit
qualification. One existing optional discrepancy-adapter test was skipped
because that external engine is unavailable; one existing plotting-range
warning was nonfatal. No complete production-runtime qualification is claimed.

Focused results: 135 integrated-forecast checks; 117 GloFAS-transition checks;
44 controller tests; scoring checks with 20 mutation rejections; evidence
checks with 10 mutation rejections; new source guard 30 checks/30 mutation
rejections. The historical source guard's original fixtures still pass
68 checks/43 mutation rejections. All fifteen changed R files parse and both
Python files byte-compile. Diff checks pass. No scientific payload was tracked.

Both identified manuscripts compile cleanly (main 39 pages, supplement 101);
anonymous proofs also pass (37 and 100 pages). Their source and article assets
are unchanged, so this code-only integration does not require a new Overleaf
projection. All execution grants remain disabled; scientific campaign and
article-promotion gates above are still outstanding.
