# JOINT pure-recursive dense-guard recovery

Date: 2026-09-25

## Incident

The resumed pure-recursive campaign completed 372 of 408 nested quantile-VB
jobs and then stopped fail-closed in stage 7. Six joint AL jobs failed before
fitting because the inherited `max_dense_dim=300` guard was smaller than the
selected joint coefficient dimension. Article VB, MCMC, oracle generation, and
posterior scoring had not started.

The affected case-specific winners are `asymmetric_laplace_tail` and
`laplace_bridge`. Each has 48 reservoir-state readout coefficients. Under the
frozen seven-level grid, the joint coefficient dimension is therefore
`7 * 48 = 336`. The corresponding eight-byte covariance footprint is 903,168
bytes, or approximately 0.86 MiB. This is a stale static guard, not a memory
constraint, convergence failure, model-selection defect, or posterior-target
change.

All 372 completed jobs were finite and converged without review. Their worker
artifact manifests verified fully. Every completed job had a coefficient
dimension no larger than the original ceiling, so none of those results was
computed under a binding or amended guard.

## Repair

The campaign now derives its dense ceiling from the frozen selected design:

```text
resolved max_dense_dim = max(base max_dense_dim, K * p)
```

Here `K` is the number of fitted quantile levels and `p` is the number of
reservoir-state coefficient columns. The separately represented ordered
intercepts are not part of the dense beta covariance.

The shared quantile preparation boundary also records and validates, before
worker launch:

- reservoir-state coefficient dimension;
- quantile count;
- required joint beta dimension;
- resolved dense ceiling;
- estimated covariance bytes.

The same derived ceiling is embedded in the future article-confirmation
contract. The AL and exAL inference kernels retain their existing guard and
posterior implementations unchanged.

## Runtime recovery contract

The versioned recovery script:

`application/scripts/recover_joint_qdesn_pure_recursive_dense_guard.R`

is restricted to the dedicated Jerez campaign root and requires the exact
audited state: 372 completed, six failed, and 30 pending jobs. It:

1. verifies all completed worker and preparation manifests;
2. proves the old ceiling was nonbinding for every completed worker;
3. archives contracts, stage-7 logs, controller evidence, and failed workers;
4. amends only the two affected family contracts from 300 to 336;
5. records that the posterior target did not change;
6. refreshes the affected preparation manifests;
7. removes only the six archived failed-worker directories;
8. requires the post-recovery state 372 complete, zero failed, 36 pending;
9. writes and verifies a compact recovery manifest.

The idempotent campaign launcher may then be restarted. Completed stages and
workers return immediately from their existing `DONE` plus manifest gates.
Only six failed and 30 previously unattempted quantile jobs require actual
fitting. After their closeout, the existing controller proceeds to 136 article
VB components, 160 MCMC workers, DGP-oracle integration, and posterior score
finalization.

## Verification gates

- An intentionally undersized 300-dimensional contract must reject a
  336-dimensional design during preparation.
- A 336-dimensional contract must pass and report the exact memory estimate.
- Raising a nonbinding guard from 300 to 336 must produce identical AL-VB
  numerical output.
- The pure-recursive quantile and article-confirmation contracts must both
  resolve to 336 for the selected 48-state cases.
- Existing completed worker hashes must remain unchanged.
- Recovery must preserve exactly 372 completed workers and expose exactly 36
  dependency-valid jobs for execution.

No article files, Overleaf branches, historical JOINT authorities, PriceFM,
GloFAS, independent-QDESN lanes, or inference kernels are part of this repair.

## Quantile closeout compatibility recovery

All 408 quantile-VB workers subsequently completed, but the score finalizer
stopped before writing the quantile manifest because pure-recursive frozen
designs retain the DGP seed in `dgp_row$seed`, whereas the shared finalizer
expected the legacy top-level `seed` field. This affected only score-row
metadata assembly; no fit, prediction, or frozen design failed.

The shared score boundary now accepts the top-level seed when present and
otherwise reads the exact frozen registry-row seed. A focused regression test
covers the pure-recursive representation. The recovery does not rewrite any
of the 408 completed worker directories.

`application/scripts/resume_joint_qdesn_pure_recursive_after_capacity.sh`
finalizes those existing outputs once, then waits for five consecutive clean
capacity polls before resuming article VB, MCMC, oracle, and score-packet
stages on the original `2-16` affinity. The capacity gate treats the active
PriceFM R120 controller and any high-load process last observed on those CPUs
as blockers. This prevents the recovered pipeline from competing with an
unrelated scientific lane while retaining the frozen 15-core execution
contract.

## Confirmation schema recovery

After quantile closeout completed, confirmation preparation exposed a second
metadata-only compatibility issue. Pure-recursive future rows already contain
`scenario_order`, while the shared confirmation builder also imports that
column from the design manifest. A base merge therefore produced
`scenario_order.x` and `scenario_order.y`, leaving no canonical column for the
subsequent ordering operation. The failure occurred before any of the 136 VB
components or 160 MCMC workers launched.

The model-cell builder now keeps design-manifest order as the canonical value,
checks any source order for exact agreement, and rejects incomplete,
duplicated, or conflicting scenario mappings. Tests cover both the legacy
schema without source order and the pure-recursive schema with matching and
conflicting order.

`application/scripts/recover_joint_qdesn_pure_recursive_confirmation_schema.R`
requires the verified 408/408 source state and the exact failed 17-file
confirmation footprint. It hash-inventories and copies that partial root into
a recovery archive, verifies every archived byte, and only then clears the
non-authoritative partial root so confirmation preparation can restart. All
screening, selected backbones, quantile fits, predictions, and quantile
manifests remain immutable.

## Shared-capacity recovery

The replacement controller then remained launch-free for more than 37 hours.
The original `2-16` allocation overlapped PriceFM R120's declared 15-core
allocation, while two unrelated long-running one-core processes could migrate
through the same range. The exclusive-capacity gate was therefore functioning
as written but could not make timely progress. PriceFM R120 had moved into a
serial dependency-sensitive quantile stage, so waiting for its full controller
to exit could defer JOINT confirmation for several additional days.

The confirmation-only runtime contract is now version 2. It leaves every
source model, candidate, seed, posterior target, VB/MCMC budget, score rule,
and output root unchanged, but records a complete physical-core partition:

- JOINT: `1,8,9,12,13,15,19,20,24,25,27,28,29,30,31`;
- PriceFM R120: `2,3,4,5,6,7,10,11,14,17,18,21,22,23,26`;
- spare: `0,16`.

The partition uses each of Jerez's 32 physical cores exactly once and has zero
physical overlap. Preparation verifies the topology and permits PriceFM R120
as a competing process only under this recorded partition. A separate waiting
controller requires five clean target-core polls and verifies that active
PriceFM compute children remain within their declared reservation. Historical
source artifacts retain their original `2-16` contract and hashes.

The two spare cores accommodate two pre-existing broad-affinity syllabus
finalization processes. The controller permits only two exact command matches,
records their PIDs, load, and affinity on every poll, and continues to reject
all other hot processes. Their affinity is not changed by this lane.

The shared-capacity launcher begins at confirmation preparation; it cannot
rerun or rewrite ridge, RHS, or nested quantile-VB screening. The expanded
screen remains chained to a successful confirmation closeout.
