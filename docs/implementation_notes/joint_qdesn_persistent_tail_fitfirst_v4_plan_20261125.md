# JOINT persistent-heavy-tail fit-first V4 super-screen

## Purpose

This lane asks whether an unseen persistent-heavy-tail DESN architecture and
RHS prior can improve the fitted median and both outer conditional quantile
paths without producing pathological recursive internal forecasts. It is a
case-specific screening lane, not an article promotion lane.

The scientific continuation parent is frozen commit
`79360949b56e4a93d998c971d9129bf125ef6abc`. The closed V2, V3, and fit-first
runtimes remain immutable.

## Why V4 differs

Earlier searches covered broad marginal ranges but advanced candidates mainly
by recursive forecast score. The fresh fit-first audit showed that this could
retain smooth forecasts with inadequate quantile-path fit. V4 therefore makes
fit competence a prerequisite and forecast performance a selector only among
fit-capable models.

V4 also freezes 9,722 prior structural signatures and excludes every one from
the 8,160 generated candidates. The 32 exceptions are explicitly named
historical controls. Tiny RHS scales already shown equivalent are not repeated
densely; new effort is placed in unseen combinations and weak-shrinkage scales.

## Frozen boundary

- Scenario: `persistent_heavy_tail`.
- Washout: 500 observations.
- Development data: 1,300 observations, split into 1,000 training and 300
  internal calibration observations.
- Calibration: ten teacher-forced rolling origins; each origin uses a recursive
  30-step forecast.
- Protected final evaluation: 1,000 observations, never persisted in a
  screening fixture and never used for selection.
- Readout: intercept plus all reservoir layers; raw inputs are excluded.
- Unknown future response lags use the median recursive action.

## Search and inference

The deterministic 8,192-candidate registry contains 32 controls, 2,048 local
fit proposals, 2,048 layered proposals, 1,536 long-memory proposals, 1,024
supercritical proposals, 1,024 ridge-only high-capacity diagnostics, and 480
global safeguards. Depth reaches 8, response lags 360, promotable state budget
84, diagnostic ridge budget 2,000, leakage spans `(0.001, 0.9995)`, and radius
reaches 1.20 under explicit stability diagnostics.

Normal RHS scales are `1e-10, 1e-8, 1e-6, 1e-4, 1e-2, 1, 1e2, 1e3, 1e4,
1e5`; slab profiles are learned or fixed at `0.01, 0.10, 0.25, 1, 4, 16,
64`; AL multipliers are `0.001, 0.01, 0.10, 0.50, 1, 2, 10, 100`.

Normal RHS and AL VB use at most 500 iterations and tolerance `1e-3`.
Nonconvergence is review-level when fitted and forecast functionals remain
finite and stable. Nonfinite functionals, invalid connectivity, unstable
supercritical recursion, protected-row access, or provenance failure are hard
failures.

Connectivity is a hard pass when at least one recurrent and one input
connection are realized. A sparse nilpotent recurrent matrix can have nonzero
connections but zero spectral radius; that is reported for review rather than
misclassified as disconnected, because leaky-state memory remains present.

## Gated funnel

| Stage | Maximum workers | Action |
|---|---:|---|
| Sentinels | 6 | Low/high ridge, normal RHS, median AL, and both tail AL checks |
| R1 | 24,576 | 8,192 architectures x three fixtures at origins 1/5/10; retain 1,024 |
| R2 | 3,072 | Full ten-origin ridge evaluation; retain 128 |
| R3 | 1,152 | Three fixtures x three reservoir seeds; retain 64 promotable architectures |
| H1 | 1,920 | Ten RHS scales; retain 24 distinct architectures |
| H2 | 576 | Eight slab profiles; retain 20 distinct architecture-prior pairs |
| M1 | 480 | Eight AL scale multipliers at the median; retain 12 |
| T1 | 120 | Separate lower/upper-tail fits on five fresh fixtures; retain six challengers |
| S1 | 35 | Six challengers plus exact V2 on five separately sealed fixtures; freeze and stop |

Each finalizer verifies every worker manifest, records the stage decision,
creates and hashes only the next worker plan, and stops. No launcher calls a
finalizer or downstream stage.

## Decision rule

Median, lower-tail, and upper-tail fit gates are separate. Relative to exact
V2 on matched fixtures, median fit may worsen by at most `max(10%, 0.005)`,
each tail by at most `max(15%, 0.015)`, and horizon-one fit by at most
`max(15%, 0.015)`. A weighted score cannot conceal failure of one tail.

Among fit-capable models, the matched known-DGP integrated three-level score is
primary. Within `max(1%, 0.005)` of the best score, worst-tail fit and then
median fit break ties. Interval overlap is uncertainty, not formal equivalence.

## Execution and stopping rule

Production is authorized only on Jerez with pinned R 4.6.0, one numerical
thread per worker, distinct reviewed physical cores, at least 80 GiB free under
`/data`, and at least 128 GiB available RAM. The launcher refuses competing
JOINT, GloFAS, or PriceFM model processes owned by the user.

Only R1 may be launched after the six sentinels pass. Every later stage requires
explicit review. S1 is terminal. A successful S1 may authorize a new seven-level
independent AL confirmation; it does not authorize joint/exAL/MCMC or article
changes in this lane. Any later exAL MCMC fit must use exact M0.

## Checklist

- [x] Freeze continuation parent and preserve closed runtimes.
- [x] Freeze prior-signature exclusion and named controls.
- [x] Implement deterministic candidate strata and numerical controls.
- [x] Implement separate fit gates and forecast-after-fit selection.
- [x] Implement sealed fixture panels, plan hashes, atomic workers, and stage stops.
- [x] Add physical-core and capacity gates.
- [x] Freeze exact source manifest and pass source mutation tests.
- [ ] Pass focused and inherited regression tests under R 4.6.0.
- [ ] Push the dedicated branch and create the clean Jerez execution worktree.
- [ ] Run and finalize six sentinels.
- [ ] Launch R1 only, monitor its first scheduling wave, and leave it running.
