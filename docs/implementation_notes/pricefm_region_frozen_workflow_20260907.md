# PriceFM Reusable Region-Frozen Workflow

## Scientific unit

The workflow selects one specification per region, not one global PriceFM
specification and not separate specifications by fold or quantile. The frozen
regional unit contains the information set, reservoir geometry, lag window,
dynamics, final-layer readout, RHS prior and tau0, and one complete AL or exAL
seven-quantile family.

Geometry and tau0 are selected from temporal validation windows entirely inside
the selection fold's training interval. The original selection-fold validation
window selects AL versus repaired exAL. The selected regional contract is then
carried unchanged to all three real folds. Test results may audit that frozen
surface but may not trigger another search.

## Implemented contracts

`pricefm_region_frozen_contract.py` centralizes canonical hashes, immutable file
records, dual-field test-firewall validation, mutation firewalls, exact paper
quantiles, content-addressed task IDs, Git identity checks, completion checks,
and evidence quarantine.

`304_prepare_pricefm_region_frozen_contract.py` accepts an arbitrary PriceFM
region and explicit authority, control, data, artifact-root, and pipeline paths.
It freezes source copies and their hashes, resolves graph scopes, records the
bounded candidate bank and correctly bracketed tau0-refinement rule, and emits
no launch configuration.

`305_prepare_pricefm_region_frozen_allfold.py` consumes a frozen validation
family and creates a content-addressed all-fold dependency graph. Fold 1 reuses
seven atoms. An AL winner requires 16 new fits across folds 2 and 3: two normal
RHS initializers and fourteen AL atoms. An exAL winner requires 30: two normal
RHS initializers, fourteen AL warm starts, and fourteen exAL candidate atoms.
The graph exposes parallel left and right AL branches and same-tau exAL children.

## Immediate compatibility path

R93 remains historical evidence. R94 is a compatibility layer that repairs only
the seven Fold-1 exAL transitions for `SE_2`. Its design matrices are regenerated
outside the R93 adapter because the R93 controller removed large X matrices after
successful completion. Regeneration must reproduce the hashes recorded in the
R93 adapter manifest exactly.

R94 pins the clean task branch and upstream, runtime, runner, nested adapter
scripts, every train/validation adapter artifact, each same-tau AL coefficient
mean/covariance and scale, and each atomic output. Invalid partial output is
quarantined rather than overwritten. The scheduler reports process liveness,
CPU-time, memory, log growth, and terminal state.

The prospective exAL numerical gate checks finite outputs and traces, at least
35 structured sigma/gamma updates, bounded sigma/gamma and coefficient growth,
and stable last-ten raw, relative-coordinate, and prediction-scale changes. The
raw first coefficient transition and package convergence flag remain visible
diagnostics, not universal validity gates.

## Authorization boundaries

The R94 controller may run through validation-family freeze when explicitly
authorized. It stops there. A second phase may prepare and fit folds 2 and 3 on
train/validation only after the complete regional family is frozen. Test data is
opened only by a separately authorized scoring-only replay that performs no fit,
requires validation prediction reproduction to absolute tolerance `1e-10`, and
compares with both authoritative Q-DESN and cached PriceFM.

Registry changes, article edits, joint Q-DESN, and MCMC are outside this lane's
automatic workflow. The PriceFM lane produces a hash-complete integration
handoff for the coordinator instead.

## Reuse and recovery

Future regions start from a new immutable region contract and a newly frozen
authority snapshot. No source edit or hard-coded region path is required in the
contract or all-fold graph builders. Completed atoms are reused only when task
identity and artifact hashes match. Interrupted or corrupt partial atoms are
quarantined and retried once under the same preregistered contract. Numerical
failure invokes the complete AL fallback; it does not alter thresholds or open
another rescue loop.
