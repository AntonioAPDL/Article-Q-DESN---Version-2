# JOINT pure-DESN score-packet recovery

## Decision

Recover exactly two incomplete score cells. Do not refit a model, change a
posterior, relax a gate, rerank partial output, or alter the deferred expanded
screen.

The frozen score packet has 62 of 64 cells complete. Worker 41 (Laplace Bridge,
joint AL, MCMC) exhausted all 3,750 retained posterior draws and passed the
finite and standardized-RMS gates, but its relative half-sample canonical-score
difference was `0.00513519345426968`, narrowly above the frozen `0.005` gate.
Worker 56 (Persistent Heavy Tail, independent exAL, MCMC) was never attempted
because the original shell queue stopped after worker 41 failed. This is a
score-state numerical-integration closeout problem, not a DESN, RHS, M0, MCMC,
or posterior-performance failure.

## Preserved scientific contract

The recovery keeps all of the following fixed:

- the scenario-specific DESN and RHS specification;
- the VB/MCMC posterior and five-chain allocation;
- exact M0 for exAL MCMC;
- the seven-level quantile grid and trapezoidal weights;
- the article fixture, rolling origins, horizons, and teacher-forcing policy;
- the DGP oracle and DGP-integrated finite-grid aCRPS definition;
- the mean-state and recursive-path forecast actions;
- the `0.10` standardized-RMS and `0.005` relative score-stability gates.

Worker 56 runs through the ordinary frozen worker path with no recovery option.
Only worker 41 receives additional integration trajectories.

## Root-cause correction

The failed cell has already used every retained AL posterior draw, so drawing
more coefficients is impossible without refitting. The remaining numerical
integral averages future response innovations used to propagate the reservoir.
For each retained posterior draw, the recovery evaluates predictive uniforms in
antithetic pairs `(u, 1-u)`. One pair per posterior draw is attempted first;
two independently seeded antithetic pairs are used only if the first tier still
misses the unchanged gate.

Each antithetic pair remains in the same within-chain alternating diagnostic
half as its posterior draw. This reduces innovation-integration noise without
artificially redistributing posterior draws between diagnostic halves. The
canonical score and posterior score intervals continue to use the original
posterior draws conditional on the recovered mean reservoir design.

Relaxing the tolerance was rejected because it would change the frozen gate.
Repeating the original 3,750 trajectories was rejected because it would not
address the integration variance. Refitting or extending MCMC was rejected
because worker 41 is finite, uses all retained draws, and fails only by a narrow
score-integration margin.

## Fail-closed recovery

`application/config/joint_qdesn_pure_recursive_score_recovery_v1.csv` freezes:

- the parent score-contract and cell-plan hashes;
- worker identities 41 and 56;
- hashes of worker 41's original `FAILED`, failure diagnostics, and stability
  progress;
- the antithetic tiers, seed stride, and two-core execution budget.

Before recovery, the launcher requires exactly `62 complete / 1 failed /
1 pending`, with failed worker 41 and pending worker 56. The recovery worker
atomically moves worker 41's original failure directory to
`score_recovery_v1/original_worker_0041_failure`, verifies its hashes, and writes
an inventory. A successful replacement cell records recovery provenance in its
own artifact manifest. A failed recovery remains failed and cannot finalize the
packet.

## Completion gates

1. Worker 56 completes under the original contract.
2. Worker 41 passes the unchanged finite, RMS, and score-stability gates.
3. All 64 cell manifests verify.
4. All mean-state and recursive-path scores are finite.
5. Contract crossings remain zero.
6. The final packet manifest verifies and `final_packet/DONE` exists.
7. The existing expanded-screen scheduler, which has remained blocked, may then
   release under its own frozen capacity and source gates.

The final packet is still diagnostic evidence. Article promotion and any
authoritative replacement require a separate completed-result audit; partial
or recovered runtime output is not promoted automatically.

## Owned files

- `application/R/joint_qdesn_recursive_mean_score_packet.R`
- `application/config/joint_qdesn_pure_recursive_score_recovery_v1.csv`
- `application/scripts/recover_joint_qdesn_pure_recursive_score_cell.R`
- `application/scripts/launch_joint_qdesn_pure_recursive_score_recovery_jerez.sh`
- `application/tests/test_joint_qdesn_recursive_mean_score_packet.R`
- this implementation note

Runtime outputs remain ignored. No article, Overleaf, PriceFM, GloFAS, Phase182,
or historical JOINT artifact belongs to this change.
