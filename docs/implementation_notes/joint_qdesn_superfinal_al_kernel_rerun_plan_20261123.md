# Final JOINT AL-kernel correction and reconstruction plan

Date: 2026-11-23

Status: implementation and production execution authorized by the owner; no
integration or article publication is authorized until every gate below passes.

## Objective

Replace every AL chain affected by the start-dependent scale cap, preserve all
valid exact-M0 exAL evidence, recompute the affected posterior score cells, and
reconstruct one complete eight-scenario JOINT packet. This is a correction of
the executed transition kernel, not a reservoir screen, prior retuning exercise,
or opportunity to select favorable rows.

## Frozen inputs

- Scientific correction base: `c9e728842c5c256bfded27d27987c4f9dd7ebc94`.
- Original confirmation: 192 workers, comprising 96 AL and 96 exact-M0 exAL
  chains.
- Corrected replacement: all 96 AL workers, preserving model cells, three
  chains, seeds, starts, budgets, designs, VB initializers, priors, and DGPs.
- Reused evidence: 96 original exact-M0 exAL chains, 96 unaffected score cells,
  eight frozen oracle banks, and ten exact-M0 supplemental exAL chains.
- Recomputed evidence: exactly 32 MCMC-AL score cells.
- Invalid evidence: the five historical supplemental AL chains, because they
  used the capped scale transition.

Every frozen source is bound by an exact SHA-256 recorded in the executable
contract. Preparation fails closed on any mismatch.

## Execution stages

1. Prepare a new ignored runtime and verify all source manifests and hashes.
2. Copy the unchanged exact-M0 exAL posterior draws and add complete target and
   effective-kernel attestations without altering the draw bytes.
3. Launch exactly 96 corrected AL workers on distinct physical cores with one
   numerical thread each.
4. Require 192/192 combined workers, finite draws, three compatible chains per
   cell, exact M0 for exAL, and the unbounded inverse-gamma update for AL.
5. Reuse 96 unchanged protected score cells and all verified oracle banks.
6. Recompute exactly 32 MCMC-AL score cells under the frozen score contract.
7. Rebuild all 128 score rows, 32 challenger/parity contrasts, and eight
   complete-packet decisions.
8. Reuse the stable eight-chain Laplace joint-exAL result. Apply a whole-scenario
   persistent-tail parity fallback if the unchanged exact-M0 challenger remains
   unstable. In that case the conditional five-chain AL supplement is skipped
   because it cannot make the complete challenger packet eligible.
9. Freeze comparisons, manifests, hashes, health receipts, and the selected
   32-row packet.
10. Add a narrowly scoped versioned admission for the corrected scientific
    source, run focused and complete tests, compile both manuscripts if article
    inputs are in scope, and issue one final integration handoff.

## Promotion gates

- 96/96 corrected AL workers complete with zero failures.
- 96/96 reused exact-M0 exAL draw files retain their source SHA-256.
- 64/64 model cells contain three compatible chains and complete target/kernel
  identities.
- 32/32 corrected MCMC-AL score cells complete; all other 96 score rows are
  byte-equivalent to the frozen source.
- 128 finite score rows and zero contract crossings.
- Exactly four selected model rows in each of eight scenarios; no model-row
  splicing across challenger and parity packets.
- Historical source guards and mutation tests remain effective.
- Full test suite and Git hygiene pass on a clean, pushed dedicated branch.

Only after all gates pass may the final handoff state
`READY_FOR_INTEGRATION`. No branch in this workflow may push `main`, touch an
Overleaf branch, or publish article assets.
