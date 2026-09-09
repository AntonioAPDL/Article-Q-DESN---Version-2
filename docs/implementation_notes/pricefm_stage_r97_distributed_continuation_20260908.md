# PriceFM Stage-R97 distributed continuation

## Scope

This change adds orchestration around the frozen Stage-R97 scientific pipeline. It
does not alter the Ridge, normal-RHS, AL, exAL, validation-selection, or scoring
implementations in scripts 316--322. Its purpose is to preserve completed work and
split the remaining 37-region validation campaign between Muscat and Jerez without
allowing duplicate region ownership or premature test access.

## Components

- `pricefm_r97_distributed_contract.py` implements canonical seals, firewalls,
  marker validation, remaining-work estimates, and deterministic region assignment.
- `323_prepare_pricefm_stage_r97_distributed_continuation.py` audits the live
  campaign and emits preview or frozen checkpoint/assignment/host contracts.
- `324_orchestrate_pricefm_stage_r97_host_shard.py` runs one exclusive host shard.
  Screening permits at most two models from one region concurrently, caps all
  numerical threads at one, and supports a `DRAIN` sentinel.
- `325_transfer_pricefm_stage_r97_host_shard.py` creates and verifies a byte- and
  SHA-256-bound transfer inventory. It does not invoke `rsync` itself.
- `326_finalize_pricefm_stage_r97_distributed_campaign.py` reconciles both complete
  validation shards. Test scoring is a separate Muscat-only command with an explicit
  one-time approval token.

## Invariants

1. Every valid `r97_compaction_terminal.json` is reused after retained-file hash
   verification. No completed experiment is intentionally refit.
2. Region ownership is exclusive. The default capacity-aware split is 25 regions
   on Jerez and 12 on Muscat, recomputed from the final checkpoint.
3. The original global controller must release its lock before a frozen checkpoint
   or host launch can pass.
4. Preview contracts can be written while the original controller remains active,
   but they are explicitly non-launchable.
5. Frozen contracts require a clean PriceFM branch synchronized with its upstream.
6. Neither host-shard controller imports or invokes the global scoring methods.
7. Both shard terminals must be complete, disjoint, and jointly cover all 37 regions
   before reconciliation succeeds.
8. Registry, article, joint-model, MCMC, and pre-reconciliation test access remain
   blocked throughout distributed validation.

## Resource policy

Muscat is capped at 20 one-core workers. Jerez is capped at 50 one-core workers.
Within a host, no region may occupy more than two workers at once. The controller
stops admitting work when the `DRAIN` sentinel exists or the configured disk pause
floor is crossed; already-running model processes are allowed to finish.

For Jerez, the operational defaults are a 300 GiB post-staging start gate, a 270 GiB
admission-stop level, a 260 GiB pause floor, and an absolute 250 GiB safety floor.
These values must be checked against the final transfer inventory before launch.

## Migration sequence

1. Keep the original Muscat controller running while code, tests, Jerez worktree,
   environment, and common payload are prepared.
2. Generate a preview checkpoint and transfer inventory; transfer and verify the
   common payload on Jerez.
3. Commit and push this dedicated PriceFM branch, then create the exact synchronized
   branch/worktree on Jerez.
4. At the agreed cutover, stop only the original R97 process group and wait until its
   global lock is free. Do not delete partial output.
5. Generate the final frozen checkpoint. Its assignment is authoritative; the
   preview assignment is not.
6. Start the Muscat shard first. Transfer the final Jerez-owned region delta, verify
   every manifest entry, and only then start the Jerez shard.
7. Reconcile complete validation closeouts on Muscat. Open test once only after the
   reconciliation terminal passes and explicit scoring authorization is supplied.

## Validation

Focused tests cover canonical tamper detection, marker reuse, deterministic exclusive
assignment, preview/freeze controls, scoring isolation, transfer round trips, hash
failure, symlink escape, overlap rejection, and one-time scoring authorization. The
existing Stage-R97 suite remains the regression authority for the scientific layer.

## Non-goals

This stage does not modify the PriceFM registry or article, does not fit joint or MCMC
models, does not retune any region using test data, and does not touch GloFAS or either
validation-study lane.
