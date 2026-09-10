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
- [x] Dedicated v4 branch and the orchestration recovery are committed and pushed.
- [ ] Production preflight verifies the live host and frozen source evidence.
- [ ] Background launch starts and produces healthy worker progress.
- [ ] Final 136/136 VB, 160/160 MCMC, score packet, manifests, and hashes pass.

## Boundaries

Do not modify or interrupt PriceFM, GloFAS, Phase182, historical JOINT, article,
or Overleaf work. Runtime files under `application/cache/` remain ignored. This
branch is an execution lane only and must be handed to the integration
coordinator after scientific closeout; it must not merge or publish article
assets directly.

## MCMC queue preflight recovery

The first 11-worker MCMC batch stopped before sampling. All 11 workers recorded
the same host-preflight error in less than one second; no worker wrote posterior
draws, a posterior summary, or a completion receipt. The failed attempt is
preserved under the ignored runtime path
`mcmc_attempts/preflight_self_detection_20260910T032727Z`, with an assessment,
inventory, SHA-256 manifest, and verification receipt.

The cause was orchestration-only. Each forked worker reran the strict process
gate, which excluded that worker and its descendants but still saw the queue
parent and sibling workers as competing JOINT processes. The repair does not
relax the top-level host gate. A worker may exclude an execution family only
when all of the following hold:

1. the runtime contains an active `mcmc_queue.lock/owner.csv`;
2. the supplied queue PID and normalized runtime root match that lock exactly;
3. the worker PID is the queue PID or a descendant in the live process table.

Only the verified queue PID and its descendants are excluded. An unrelated
process with the same JOINT run tag still blocks execution. Batch health is now
refreshed immediately after every batch result, and failure audits classify
recorded errors before recommending an orchestration, numerical, nonfinite, or
provenance repair.

Recovery verification covers synthetic parent/sibling process trees, an actual
two-child fork, lock-owner mismatch, non-descendant rejection, duplicate
same-tag rejection, historical precision-failure classification, and health
file synchronization. The posterior-target, corrected scientific-contract,
Muscat host-contract, shared-capacity, and full confirmation tests all pass.
The only permitted continuation is `--launch-mcmc`; completed VB artifacts must
not be regenerated.

## Joint AL precision recovery

The first scientifically active MCMC batch subsequently completed six workers
and stopped on five numerical failures. All five failures were the chains of
the `asymmetric_laplace_tail` Joint QDESN AL-RHS cell; each reported that a
leading principal minor of the 168-dimensional beta precision matrix was not
positive. The matching five-chain Independent QDESN AL-RHS cell completed, as
did the first Joint exQDESN exact-M0 chain. Initial precision reconstruction is
positive definite for every failed Joint AL chain, localizing the failure to
dynamic latent-weight/RHS evolution rather than the VB initializer, DESN
backbone, `tau0`, seed plan, or exAL gamma update.

The AL sampler now exposes the same opt-in, scale-aware precision safeguard
already used by exact-M0 exAL. Article-confirmation workers enable it uniformly:
the original sparse factorization is always attempted first, relative diagonal
jitter starts at `1e-12` only after failure, and the sampler fails closed above
`1e-8`. Joint and independent AL outputs retain repair counts, maximum jitter,
iteration, matrix scale, latent-weight range, and sigma range. AL gamma fields
are explicit missing values in the common diagnostic schema.

The direct AL path is regression-tested to be draw-for-draw identical with the
safeguard enabled or disabled when no repair is needed. Therefore, previously
completed workers may be retained only after their manifests, posterior-target
hashes, and execution-commit boundary are explicitly audited. Failed receipts
must be frozen before retry; seeds, budgets, model specifications, score rules,
and completed VB artifacts remain unchanged.

The reproducible retention gate is
`application/scripts/audit_joint_qdesn_shared_backbone_article_mcmc_resume.R`.
It verifies every retained draw file, manifest, expected draw count, current
posterior-target hash, compatible execution commit and ancestry, and bounded
repair status. Its output is an ignored, hash-manifested runtime packet; a
failed row requires rerunning that worker rather than overriding the gate.
