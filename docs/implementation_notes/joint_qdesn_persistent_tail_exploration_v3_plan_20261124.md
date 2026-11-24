# JOINT persistent-heavy-tail exploration v3

Date: 2026-11-24

## Objective

Improve the persistent-heavy-tail case beyond the frozen v2 winner without
changing the article, weakening provenance, or screening on protected article
outcomes. This is a case-specific architecture and prior exploration. It is not
a universal Q-DESN specification search.

The frozen parent is
`work/joint-qdesn-persistent-tail-targeted-screen-20261124` at
`a097b01df88496cacb75b86027aaa0dfe9e18825`. Its runtime remains immutable.

## Why another screen is justified

V2 improved the normal-RHS internal score from approximately 0.5002 to 0.4288,
but concentrated in a narrow, compact, high-leakage/low-radius region. It also
showed that very small `tau0` values can become numerically indistinguishable.
V3 therefore spends computation on new combinations rather than merely making
the old grid denser:

- high leakage with very low spectral radius;
- compact reservoirs with explicitly opted-in radius up to 1.2;
- heterogeneous schedules across as many as four layers;
- response lags from 1 through 60 and state budgets from 8 through 80;
- broader input scaling and input/recurrent sparsity;
- regularized-horseshoe global-scale and slab behavior;
- median and outer-tail AL performance before a full seven-level confirmation.

The 80-state ceiling is deliberate: seven quantiles times 80 states gives 560
penalized coefficients, below the reviewed dense joint-backend ceiling of 600.

## Frozen data and forecast contract

- Scenario: `persistent_heavy_tail` only.
- Window: washout 500, fit 1,000, internal calibration 300.
- Ten rolling origins; teacher forcing occurs between origins.
- Forecasting is recursive within each multi-step origin.
- Readout contains an intercept and all reservoir layers, with no raw input.
- Three new discovery fixtures are used for selection.
- Three disjoint confirmation fixtures remain seed-only until finalists freeze.
- Protected article outcomes cannot be loaded by any v3 worker.

## Search and decision stages

| Stage | Work | Advance rule |
|---|---:|---|
| N0 | 90 normal-RHS fits | Diagnose whether `1e-6` through `1e-20` form a numerically equivalent tiny-scale class. `1e-20` is a sentinel, not a broad-screen default. |
| A1 | 12,288 ridge jobs | Screen 4,096 architectures on three early origins and three discovery fixtures; retain 1,024. |
| A2 | 3,072 ridge jobs | Score all ten origins; retain 128. |
| A3 | 1,152 ridge jobs | Repeat 128 architectures over three reservoir seeds and three fixtures; retain 64. Supercritical candidates must pass state-perturbation checks. |
| H1 | 1,344 normal-RHS VB jobs | Seven nonredundant global-scale profiles over 64 architectures and three fixtures; retain one profile for each of 20 distinct architectures. |
| H2 | 300 normal-RHS VB jobs | Learned or fixed slab variance in `{learned, 0.25, 1, 4, 16}`; retain one profile for each of 16 architectures. |
| M1 | 288 independent median-AL VB jobs | Six quantile-scale multipliers over 16 profiles and three fixtures; retain ten distinct architectures. |
| T1 | 60 independent outer-tail AL VB jobs | Evaluate tau 0.05 and 0.95, combined with the median through the frozen 0.25/0.50/0.25 score; freeze four new challengers. |
| Q3 | 18 full-grid workers, 126 component fits | On three newly materialized sealed fixtures, compare four challengers with the exact authority and exact v2 winner over seven quantiles. |

All five exact architecture anchors survive A1 through A3. The exact authority
and exact v2 winner remain mandatory controls through the prior and quantile
stages; the other three anchors compete normally. Q3 retains those two controls
plus four new challengers. Every stage writes summaries, decisions, receipts, and verified
SHA-256 manifests, then stops. No launcher calls a finalizer or downstream
launcher.

## Scientific gates

Hard failures are nonfinite scores, missing or conflicting provenance, zero
realized reservoir connectivity, zero realized recurrent radius, pathological
recursive states, failed supercritical perturbation stability, protected-data
use, or nonzero post-contract crossings in Q3.

Convergence flags remain visible review diagnostics. They are not automatic
rejection criteria when fitted/forecast quantile functionals and scores are
stable. Any positive matched mean Q3 improvement over the exact v2 winner may
recommend the case-level four-model continuation; interval overlap is not a
failure and does not establish formal equivalence.

## Boundaries after Q3

V3 does not automatically fit joint/independent AL/exAL VB or MCMC models. A
positive sealed result authorizes a separately frozen case-level continuation.
Any later exAL MCMC must use exact M0. No v3 result enters the article until the
complete final lane is frozen, reviewed, integrated once, and independently
verified by the coordinator.

## Implementation checklist

- [x] Freeze contract, axes, exact anchors, seeds, dimensions, and stage sizes.
- [x] Generate deterministic candidates and preserve exact controls.
- [x] Add nonzero-connectivity, saturation, perturbation, and protection gates.
- [x] Implement fixed/calibrated global scales and learned/fixed slab profiles.
- [x] Implement median, outer-tail, and sealed full-grid AL workers.
- [x] Freeze finalists before confirmation fixture materialization.
- [x] Add atomic workers, verified manifests, health checks, and manual finalizers.
- [x] Add a Jerez-only physical-core launcher with clean/synced Git and capacity gates.
- [x] Add focused preparation and source-contract tests.
- [ ] Execute and review N0 before A1/A2/A3.
- [ ] Execute and review H1/H2/M1/T1/Q3 in order.
- [ ] If Q3 wins, freeze a separate full four-model VB/MCMC continuation.
- [ ] Integrate only the final scientifically accepted lane.
