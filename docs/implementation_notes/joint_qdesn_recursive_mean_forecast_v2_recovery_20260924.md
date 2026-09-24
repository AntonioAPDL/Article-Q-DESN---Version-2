# JOINT recursive mean-design forecast v2 recovery

Date: 2026-09-24

Lane: `work/joint-qdesn-recursive-mean-forecast-jerez-20260924`

Status: closed failed; preserved for diagnosis and not promotable

## Decision

Preserve the incomplete v1 runtime unchanged and repeat the complete
forecast-only reconstruction under a corrected v2 contract. Reuse the frozen
corrected-v4 VB and MCMC fits; do not refit, rescreen, retune, or alter any
model specification. Run the 16 oracle shards, three sentinels, and all 64
forecast cells in a new ignored runtime with eight single-thread physical-core
workers.

A nine-cell-only retry was rejected. The v1 half-sample implementation grouped
MCMC draws by storage order, and storage order is chain-major. Correcting that
diagnostic changes the interpretation of every cell's stability evidence even
though it does not change the mean design itself. A clean 64-cell v2 rerun is
short relative to refitting and gives one uniform contract and manifest.

## Frozen v1 evidence

The v1 campaign completed all 16 primary oracle shards and froze eight oracle
banks. It completed 55 of 64 forecast cells with valid manifests and zero
contract crossings. Nine joint cells failed:

| Worker | Inference | Scenario | Model | v1 failure |
|---:|---|---|---|---|
| 23 | VB | Persistent Heavy Tail | joint exAL | half-score |
| 35 | MCMC | Asymmetric Laplace Tail | joint exAL | half-score |
| 37 | MCMC | Gaussian-Mixture Bridge | joint AL | half-score |
| 39 | MCMC | Gaussian-Mixture Bridge | joint exAL | half-score |
| 45 | MCMC | Nonlinear Reservoir Friendly | joint AL | half-score |
| 49 | MCMC | Normal Bridge | joint AL | RMS after extension |
| 53 | MCMC | Persistent Heavy Tail | joint AL | half-score |
| 55 | MCMC | Persistent Heavy Tail | joint exAL | RMS after extension |
| 59 | MCMC | Regime Shift | joint exAL | half-score |

The v1 runtime remains ignored at
`application/cache/joint_qdesn_recursive_mean_forecast_jerez_20260924`.
Its frozen contract SHA-256 is
`1a1d0d37552b26edc0d5008677fc778a44f20a355d1b255a34b758600a3095bb`.

## Root-cause audit

Three coupled defects explain why a superficial threshold relaxation is not
acceptable:

1. The state-draw extension was triggered only by the RMS diagnostic. A cell
   that passed RMS but failed the canonical half-score gate stopped without
   receiving the declared larger integration sample.
2. MCMC state draws are concatenated chain by chain. The old contiguous half
   split therefore compared approximately chains 1--2 against chains 4--5,
   while the 0.10 RMS tolerance was calibrated to two ordinary Monte Carlo
   halves. This conflated integration error with between-chain variation.
3. Failed workers retained only an error string. The numerical tier history
   was deleted with the temporary directory, preventing a quantitative rescue
   audit.

The first two defects are control and estimand-diagnostic defects, not evidence
that the fitted posteriors are missing or corrupt. Existing score R-hat and ESS
diagnostics remain the appropriate MCMC readout checks. The v2 state
integration diagnostic now asks the separate question it was intended to ask:
whether the posterior mean recursive design is numerically stable.

## Corrected v2 contract

The scientific forecast target is unchanged:

- seven quantiles at `0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`;
- 33 origins and 30 open-loop horizons;
- origin-marginal DGP-integrated finite-grid aCRPS;
- monotone quantile contract and endpoint-clamped inverse-CDF synthesis;
- posterior mean complete readout design, followed by an independent readout
  posterior draw;
- MCMC intervals condition on the mean design and include intercept/readout
  uncertainty;
- VB intervals remain partial because retained intercept covariance is not
  available.

The v2 numerical integration policy is:

| Tier | MCMC state paths | VB state paths | Trigger |
|---|---:|---:|---|
| Initial | 1,000, 200 per chain | 1,000 | always |
| Extension | 2,000, 400 per chain | 2,000 | either stability gate fails |
| Full posterior rescue | 3,750, all 750 per chain | 4,000 | either gate still fails |

For MCMC, each diagnostic half alternates draws within every chain. For VB,
iid variational draws alternate globally. Both halves therefore represent the
same equally weighted posterior mixture. Chain-specific mean-design scores are
retained separately as a sensitivity diagnostic and are not substituted for
the integration gate.

The thresholds remain unchanged: standardized RMS at most `0.10` and relative
canonical-score difference at most `0.005`. No post hoc relaxation is allowed.

## Reproducibility and failure behavior

- `joint_qdesn_recursive_mean_forecast_contract_v2.csv` records the v1 parent
  hash and every rescue-tier control.
- The launcher propagates the exact contract path into the detached tmux
  controller. This prevents a requested v2 run from silently reverting to the
  default v1 contract.
- The comma-delimited CPU affinity is quoted in the preflight CSV, preserving
  a valid eight-column provenance record.
- Every successful cell retains selected-tier and all attempted-tier
  diagnostics.
- A failed cell writes its complete tier diagnostics and effective contract
  hash before raising an error.
- The finalizer rejects mixed half-split methods, nonfinite scores, either
  failed stability gate, or any contract crossing.
- The final packet includes its effective contract and hash-manifested tier
  history.

## Execution plan

1. Run focused v1/v2 parser, split, tier, design, oracle, score, shell, and
   existing corrected-source contract tests on Muscat.
2. Commit and push only this dedicated branch.
3. Pull the exact commit into the matching clean Jerez worktree.
4. Verify the 2,970-file corrected-v4 source inventory and the v1 parent hash.
5. Select eight currently idle, distinct physical cores; do not touch any
   unrelated process.
6. Launch into
   `application/cache/joint_qdesn_recursive_mean_forecast_v2_jerez_20260924`.
7. Monitor preflight, oracle aggregation, and all three sentinels before the
   64-cell queue is accepted as healthy.
8. Let the bounded queue finish. Do not promote partial output.
9. Require 16/16 primary oracle shards, 8/8 banks, 32/32 VB cells, 32/32 MCMC
   cells, zero failures, finite scores, zero contract crossings, and verified
   manifests.
10. Compare v2 with v1 and corrected-v4 only after finalization. Keep their
    different forecast-design estimands explicit.

## Completion checklist

- [x] Preserve v1 runtime and contract.
- [x] Diagnose score-trigger, chain-major split, and failure-evidence defects.
- [x] Add versioned v2 contract without weakening gates.
- [x] Implement within-chain alternating halves.
- [x] Separate chain sensitivity from integration stability.
- [x] Extend on either RMS or half-score failure.
- [x] Add full-posterior rescue tier.
- [x] Persist successful and failed tier diagnostics.
- [x] Propagate the selected contract through tmux.
- [x] Pass all focused tests on Muscat and Jerez.
- [x] Commit and push the dedicated branch.
- [x] Pass the clean Jerez preflight.
- [x] Launch and verify v2 oracle and sentinel gates.
- [ ] Complete and finalize 64/64 cells.
- [ ] Freeze hashes, compare estimands, and prepare an integration handoff.

## Terminal execution outcome

The v2 queue closed naturally on 2026-09-24 with 16/16 primary oracle shards,
8/8 oracle banks, 63/64 completed forecast cells, one failed cell, and no
remaining worker or tmux process. Worker 35, the asymmetric-Laplace-tail joint
exAL MCMC cell, failed on `Recursive state tier produced an unexpected draw
count.` The controller failed closed before finalization. The ignored v2
runtime occupies approximately 629 MiB and is retained as diagnostic evidence.

Subsequent source audit established that AL chains contain 750 retained draws
while exAL chains contain 1,500. The v2 rescue contract incorrectly expected
750 for both. The separate v3 cardinality-recovery document freezes the root
correction; no v2 result is promotable.

No article, Overleaf, PriceFM, GloFAS, Phase182, historical JOINT runtime, or
fitted posterior object belongs to this lane.
