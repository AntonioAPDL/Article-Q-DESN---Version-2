# GloFAS Search Phase II RHS Execution Plan

## 1. Decision and scope

This document is the execution authority for the regularized-horseshoe (RHS)
half of GloFAS Search Phase II. It follows the completed multi-origin Normal
Ridge screen and does not reopen the Ridge candidate space, inspect the sealed
December 25, 2022 forecast window, refit Part 1--4 article models, or authorize
article promotion. The immediate authorized action is the RHS prior pilot only.
The architecture screen and seed confirmation remain explicit later approval
gates.

The scientific objective is to improve recursive historical forecast skill for
the reference USGS component and the retrospective-GloFAS discrepancy while
preserving historical fit. The final article origin remains excluded from all
selection. Six historical origins are evaluated over days 1--28, with days
1--30 retained as a secondary diagnostic. Future PRISM precipitation and ERA5
soil moisture are realized oracle covariates, so the scores measure conditional
DESN dynamics rather than operational covariate uncertainty.

## 2. Audited starting point

The completed Ridge authority is:

`/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_search_phase2_20260914/local_trackers/runtime_configs/glofas_search_phase2_ridge_20260914_r1`

It contains 828/828 scored candidate-fold fits, zero failures, 69
architectures per target, and six folds. Its aggregate SHA256 is
`2c623b778186c9698d6103870a518410976a2f091b58b80b59e761b0ee11f5ec`.
All numerical gates passed; 48 reference and 49 discrepancy architectures are
eligible after historical guardrails.

The Ridge leaders show that the two components need not share a reservoir
geometry. The mean reference leader is D1/n1500 with long output memory, while
the balanced reference candidate is D2/n3000. The discrepancy leader is
D2/n2500 with long output and covariate memory. This supports target-specific
RHS selection and rejects a linked Cartesian rescreen.

## 3. Why this staged design is optimal for the present evidence

Ridge is retained as a broad filter and exact-design initializer, not as a
surrogate RHS ranker. Earlier GloFAS screens showed weak Ridge-to-RHS rank
correlation, while broad raw `tau0` sweeps were practically flat. Therefore the
next expensive budget is spent first on six interpretable prior regimes over a
small architecture panel, then on architecture breadth under one selected
prior. This separates prior sensitivity from architecture sensitivity and
avoids confounding either result.

The pilot includes four architectures per target: the Phase I legacy anchor,
the standardized Phase I anchor, the two best guardrail-eligible Ridge
architectures under four-decimal ranking, and one deterministic maximin
candidate, with duplicate IDs removed. In the observed manifest this resolves
to exactly four distinct architectures per target. This preserves a baseline,
tests the main Ridge basin, and retains one geometrically diverse challenger.

Six priors are evaluated: calibrated expected active sizes `m0=25,100,300`
with learned slab scale; `m0=100` with fixed slab variances 4 and 16; and the
Phase I legacy `tau0`. Calibration uses design dimension, training sample size,
and Ridge residual scale. It is more comparable across widths than recycling a
single raw global scale.

## 4. Frozen workload and efficient reuse

The pilot has 8 architectures x 6 folds x 6 priors = 288 RHS fits. Jobs sharing
an architecture and fold form 48 design groups; each group builds the reservoir
design once and executes its six priors sequentially. Every job uses the exact
hashed Ridge warm start for that architecture and fold. This removes 288 Ridge
resolves and 240 redundant reservoir builds without sharing posterior state
between priors.

After the pilot is reviewed, the architecture screen evaluates 20
architectures per target under the prospectively selected prior: 240 total
cells. Exactly 48 cells overlap the pilot and are imported by path and SHA256,
leaving 192 new fits. Confirmation evaluates three finalists per target across
the original seed and three declared additional seeds: 144 cells. The 36
original-seed cells are hash-verified aliases of screen evidence, leaving 108
new fits. Total new RHS fits across all three gated stages are therefore 588.

No later stage starts automatically. Four-decimal primary CRPS defines
practical equivalence; worst-fold CRPS is the first performance tie-break.
Historical guardrails, state diagnostics, runtime, and smaller dimension then
resolve candidates without treating numerical dust as scientific improvement.

## 5. Inference and numerical contract

All RHS fits use `max_iter=100`, `min_iter=30`, `tol=1e-4`, and one numerical
thread. Readout coefficients are frozen for iterations 1--20 so local-scale and
variance blocks can adapt around the Ridge initializer. At least 30 coefficient
updates are required before convergence. Every fit retains the ELBO trace,
coefficient activity, top coefficients, convergence state, finite-state checks,
historical metrics, recursive forecast path, and score detail.

The final origin `2022-12-25` is prohibited in model packets. Model packets
contain response history only through their fold origin and no future response
truth. Scoring packets are separate. All warm starts, reused score tables, fit
summaries, model packets, and scoring packets are hash checked before use.

## 6. Implementation corrections made before launch

1. Candidate and prior selection rank rounded four-decimal CRPS before
   worst-fold and secondary-horizon scores.
2. Confirmation candidates retain a base candidate ID, allowing all four seeds
   and six folds to aggregate into one 24-cell result.
3. Confirmation historical guardrails use the corresponding Phase I anchor
   from the source architecture screen, not an absent seed-suffixed anchor.
4. Pilot, screen, and confirmation reuse registries carry source and
   destination identities plus SHA256 values.
5. Empty reuse registries have a stable readable schema.
6. Remote staging copies each unique Ridge warm start, rewrites its path for
   Jerez, and verifies its hash during preflight.
7. The scheduler receives an exact Rscript path, reports active and pending
   jobs correctly for grouped execution, and preserves scheduler/group logs in
   the return manifest.
8. Group workers invoke scoring with the same R installation as the fit.

## 7. Validation gates

Before production preparation, all changed R files must parse, Python files
must compile, focused Search-II R tests must pass, scheduler and remote-shard
tests must pass, and `git diff --check` must be clean. The implementation branch
must then be committed, pushed, clean, and synchronized because the runtime
manifest records an immutable Git HEAD.

The production pilot manifest must prove: 288 unique jobs, 48 unique design
groups, 144 jobs per target, 48 jobs per prior, six folds per
target/architecture/prior, eight architectures total, no final origin, all
warm-start files present, no warm-start hash mismatch, and exactly the frozen
VB controls. A no-fit scheduler dry run must report 288 jobs and 48 grouped
units.

Remote preflight on Jerez requires the exact pushed source HEAD, a clean branch
synchronized with its upstream, R 4.6.0 at
`/data/jaguir26/local/opt/R/4.6.0/bin/Rscript`, the pinned exdqlm source commit
`741c06e9b71566b4880ee1f948b0e3553ced0339`, and compiled `src/exdqlm.so`
SHA256 `fcdfdefb768c8c3ec006138dedd0683e512481164e70794cd098a618f128bf9f`.
Transferred packets and warm starts must reproduce their manifests exactly.

## 8. Jerez launch and monitoring

Jerez receives a dedicated clean execution worktree and a manifest-built
runtime, never a mutable copy of the Muscat tree. A single production design
group is run first as a retained canary. If all six jobs finish and score with
no failed marker, the detached scheduler resumes the remaining groups with up
to 48 one-thread workers and weighted capacity 100. This leaves host headroom
and prevents wide models from being treated as equal-memory jobs.

The launch records an auditable tmux session, scheduler log, one log per design
group, per-job status markers, and exact commands. Health reports distinguish
jobs from grouped units. Any failure blocks aggregation and later-stage
preparation. There is no automatic retry that could conceal a deterministic
failure.

## 9. Completion and return contract

After 288/288 jobs complete, Jerez runs the checker and remote finalizer. The
result manifest includes every required forecast, fit summary, score summary
and detail, trace, coefficient diagnostic, status marker, scheduler log, and
group log. Muscat imports only after verifying the sealed result manifest and
refuses to overwrite any central-owned result. Muscat then reruns the checker
and records aggregate and manifest hashes.

Pilot completion is not model promotion. The next decision is whether each
target has a numerically healthy prior winner and whether prior differences
exceed the four-decimal equivalence envelope. Only then may the separately
prepared 192-new-fit architecture stage be approved. The sealed final cutoff,
Part 1--4 refits, article tables, figures, manuscript, Overleaf, and `main`
remain untouched throughout this execution.
