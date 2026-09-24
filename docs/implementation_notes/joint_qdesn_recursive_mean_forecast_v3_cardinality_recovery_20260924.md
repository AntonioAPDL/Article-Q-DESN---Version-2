# JOINT recursive mean-design forecast v3 cardinality recovery

Date: 2026-09-24

Lane: `work/joint-qdesn-recursive-mean-forecast-jerez-20260924`

Status: implementation and clean full-rerun contract

## Decision

Preserve both earlier runtimes as historical evidence. Let the already active
v2 queue close without intervention, classify v2 as failed, and run a new v3
forecast-only reconstruction from the unchanged corrected-v4 fitted models.
Do not refit, retune, rescreen, weaken a gate, or promote partial output.

## Root cause

The v2 recovery correctly fixed the chain-major half split and extension
trigger, but exposed a separate retained-draw cardinality defect. Direct audit
of the source posterior files found a likelihood-specific pattern: each AL
chain contains 750 retained draws and each exAL chain contains 1,500. The
adapter's `use_all=TRUE` path ignored its requested count, so exAL returned all
7,500 draws where v2 expected 3,750.

This created two distinct contract violations:

1. v2 described 750 draws per chain as the all-draw state rescue and expected
   3,750 rows, so any cell entering that tier failed on a 7,500-row result.
2. v1 and v2 requested 750 draws per chain for final scores but also set
   `use_all=TRUE`, silently producing 7,500 rather than 3,750 score draws.

The issue is post-processing cardinality, not fitted-model quality. No source
VB or MCMC object is changed.

## Corrected v3 contract

The state and score samples now have separate, explicit roles:

| Use | MCMC draws | VB draws |
|---|---:|---:|
| Initial state integration | 1,000 total, 200 per chain | 1,000 |
| Extended state integration | 2,000 total, 400 per chain | 2,000 |
| Full state rescue | AL: 3,750 total; exAL: 7,500 total; all per chain | 4,000 |
| Final posterior score sample | 3,750 total, exactly 750 per chain | 4,000 |

The v3 score sample is chain balanced and deterministic. The state rescue uses
every retained MCMC draw only when either unchanged stability gate still fails
after 2,000 state paths. Alternating halves remain within-chain for MCMC and
iid-alternating for VB.

All scientific targets remain frozen: seven quantiles, 33 origins, 30
horizons, origin-marginal DGP-integrated finite-grid aCRPS, monotone contract,
endpoint-clamped inverse-CDF synthesis, posterior mean recursive reservoir
design, and posterior readout uncertainty conditional on that mean design.

## Failure-closed evidence

- The v3 parser freezes 750 available draws per AL chain and 1,500 per exAL
  chain.
- Preflight reads and verifies all 160 source posterior files against those
  likelihood-specific counts and writes a manifest-backed cardinality audit.
- Every requested subset must fit inside the retained source cardinality.
- Each tier checks its resulting row count.
- Tier diagnostics are written to `stability_progress.csv` after every tier,
  outside the disposable temporary output directory.
- Any worker error converts available progress into hash-identified
  `failure_diagnostics.csv`, including failures encountered while entering a
  later rescue tier.
- The finalizer rejects incomplete cells, mixed split methods, nonfinite
  scores, failed stability gates, or contract crossings.

## Execution sequence

1. Finish and preserve the active v2 queue without interruption.
2. Record its terminal counts and known cardinality failures; do not finalize
   or promote it.
3. Run parser, cardinality, adapter, design, oracle, score, shell, and
   corrected-source tests on Muscat.
4. Commit and push only the dedicated lane.
5. After no v2 worker remains, update the matching clean Jerez worktree to the
   exact v3 commit and repeat all focused tests against the real source files.
6. Preflight a new ignored v3 runtime on eight idle distinct physical cores.
7. Run 16 primary oracle shards, freeze eight oracle banks, then require all
   three sentinels to pass.
8. Run all 64 cells. Require 32/32 VB and 32/32 MCMC, zero failures, finite
   scores, zero contract crossings, and verified manifests.
9. Finalize once, audit score-draw cardinality and tier histories, compare the
   recursive-mean estimand with the corrected-v4 reference, and prepare the
   dedicated integration handoff.

## Checklist

- [x] Identify the 750-draw AL and 1,500-draw exAL source cardinalities.
- [x] Preserve v1 and v2 instead of mutating runtime history.
- [x] Separate state-rescue and score-draw contracts.
- [x] Keep all scientific gates and the forecast estimand unchanged.
- [x] Add durable per-tier failure progress.
- [x] Pass focused Muscat tests, including all-source cardinality.
- [ ] Commit and push v3 on the dedicated branch.
- [x] Observe a natural terminal v2 state: 63/64 complete, one cardinality
  failure, zero active workers, and no finalization.
- [ ] Pass focused Jerez tests at the exact v3 commit.
- [ ] Pass Jerez capacity and source-inventory preflight.
- [ ] Pass 16/16 oracle shards, 8/8 banks, and 3/3 sentinels.
- [ ] Complete and finalize 64/64 cells with zero failures.
- [ ] Freeze manifests, hashes, storage status, and integration handoff.

No article, Overleaf, PriceFM, GloFAS, Phase182, historical JOINT runtime, or
fitted posterior object belongs to this lane.
