# JOINT corrected article comparison: Muscat 11-core execution

## Decision

The original Muscat handoff requested 25 idle physical cores. Its scientific
contract and implementation were completed on the dedicated 25-core branch,
but production remained blocked because PriceFM R97 and GloFAS Part 4 were
healthy and active. On 2026-09-09, the user explicitly authorized use of the
11 physical cores still available after preserving those campaigns.

This v4 lane changes execution capacity only. It does not change the selected
scenario-specific backbones, article fixture, seven-level quantile grid,
regularized-horseshoe posterior, VB/MCMC method, chain count, seeds, posterior
target, score definition, or promotion contract inherited from v3.

## Frozen physical-core allocation

| Lane | Logical CPU list | Physical cores | Policy |
|---|---|---:|---|
| JOINT v4 | `1-9,16,24` | 11 | One logical CPU from each distinct core |
| PriceFM R97 | `42-47,49-55,57-63` | 20 | Existing pinned allocation, unchanged |
| GloFAS Part 4 reserve | `0,32` | 1 | Entire sibling pair excluded from JOINT |

The three sets cover all 32 Muscat physical cores without overlap. Reserving
both logical siblings `0,32` prevents JOINT from competing with the unpinned
GloFAS continuation on that physical core. The v4 preflight writes both the
effective JOINT topology and the complete shared-capacity audit before any fit
starts.

## Scientific workload

- Eight scenario-specific shared backbones from the frozen source campaign.
- 136 ordered VB components and 32 compact MCMC initializers.
- 32 article-fixture model cells: joint/independent crossed with AL/exAL.
- Five chains per cell, for 160 MCMC workers total.
- Exact M0 exAL method, chain-invariant posterior-target hashes, and one
  numerical thread per worker.
- DGP-integrated finite-grid aCRPS as the primary score, with the previously
  frozen secondary diagnostics and score uncertainty summaries.

## Fail-closed execution contract

The v4 launcher requires the dedicated branch and exact upstream synchronization,
pinned R 4.6.0 and library, at least 100 GiB free on `/data`, one-thread numerical
environment variables, exact CPU affinity, verified source hashes, and the
explicit `MUSCAT_11_PHYSICAL_SHARED` token. It allows only process commands
belonging to `pricefm_stage_r97` and
`glofas_part4_joint_convergence_closeout_20260907`; any other protected process
blocks preparation.

`--run-all` executes the existing stage gates in order: preflight, VB queue,
complete-VB check, MCMC queue, MCMC check, and score-packet finalization. It
does not reuse the dormant 25-core runtime or either historical Jerez packet.

## Verification checklist

- [x] v3-to-v4 scientific fields are byte-equivalent after excluding execution metadata.
- [x] VB component seeds/dependencies and MCMC chain/start seeds are unchanged.
- [x] The 11 JOINT logical CPUs map to 11 distinct physical cores.
- [x] The 11/20/1 allocation is exhaustive and non-overlapping.
- [x] Only the two audited active campaign families can pass the process gate.
- [x] The 11-worker launcher is phase-gated, affinity-pinned, and shell-valid.
- [ ] Dedicated v4 branch is committed, pushed, clean, and upstream-exact.
- [ ] Production preflight verifies the live host and frozen source evidence.
- [ ] Background launch starts and produces healthy worker progress.
- [ ] Final 136/136 VB, 160/160 MCMC, score packet, manifests, and hashes pass.

## Boundaries

Do not modify or interrupt PriceFM, GloFAS, Phase182, historical JOINT, article,
or Overleaf work. Runtime files under `application/cache/` remain ignored. This
branch is an execution lane only and must be handed to the integration
coordinator after scientific closeout; it must not merge or publish article
assets directly.
