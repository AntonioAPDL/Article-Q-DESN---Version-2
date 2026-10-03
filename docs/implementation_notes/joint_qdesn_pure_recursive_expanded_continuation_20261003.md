# JOINT pure-DESN expanded-screen continuation

Date: 2026-10-03

Lane: JOINT simulation only

Execution branch: `work/joint-qdesn-pure-desn-expanded-continuation-20261003`

## Decision

Continue from the completed expanded Gaussian-RHS screen without repeating the
screen or refitting families whose complete scientific specification is
unchanged. The expanded screen changed exactly two case-specific winners:

| Scenario | Source calibration aCRPS | Expanded calibration aCRPS | Relative change | Action |
|---|---:|---:|---:|---|
| Asymmetric Laplace Tail | 0.372934 | 0.369310 | -0.972% | fresh nested VB/MCMC |
| Nonlinear Reservoir Friendly | 0.475202 | 0.472979 | -0.468% | fresh nested VB/MCMC |

The other six winners are specification-identical, including candidate ID,
architecture signature, lags, depth, layer widths, leakage, spectral radius,
input scale/sparsity, reservoir seed, readout contract, and RHS `tau0`. Their
completed workers may be reused only after plan, design, initializer,
posterior-target, and artifact-manifest checks pass.

This is preferable to a full eight-family rerun because it changes no posterior
target for the six reused families and avoids 306 nested-VB workers, 102
article-VB workers, and 120 MCMC workers. It is preferable to a two-family-only
packet because the final artifact remains a complete eight-scenario,
four-model comparison with one frozen contract.

## Scientific contract

- Eight scenarios, seven quantiles: `0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`.
- Four models per scenario: joint/independent Q-DESN under AL/exAL with RHS.
- One case-specific DESN and RHS `tau0` is shared across the four models within
  each scenario; no universal backbone is imposed across scenarios.
- Pure-DESN readout: intercept plus all retained reservoir-layer states; raw
  inputs are excluded from the readout.
- Selection used only the frozen internal recursive calibration window. The
  protected article fixture was not used during screening.
- Every exAL MCMC worker uses exact
  `M0_v_collapsed_support_logit`; structured exAL VB remains
  `VB1_structured_v`.
- Mean-state recursive scoring is primary and path-recursive scoring remains a
  sensitivity analysis.
- Primary score: DGP-integrated finite-grid aCRPS. Report posterior mean,
  median, and 95% interval, plus oracle fit/forecast recovery and raw/contract
  crossings.
- Scalar gamma/sigma mixing is review-level unless forecast/fit behavior is
  pathological. Finite predictive functionals, score behavior, and coherence
  are the operative gates.
- A lower mean primary score is promotion-worthy even when intervals overlap,
  provided outputs are finite, nonpathological, provenance-complete, and have
  zero contract crossings. Such gains must be described as numerical or
  descriptive when uncertainty overlaps.

## Frozen workflow

1. Repair the expanded finalizer's vectorized alpha/rho boundary audit and
   close the already-completed 26,112-worker screen. No screen worker reruns.
2. Prepare the complete 408-worker nested quantile graph.
3. Import and verify 306 workers for the six unchanged scenarios; compute the
   remaining 102 workers for the two changed scenarios.
4. Freeze a complete 136-component article-VB graph.
5. Import and verify 102 unchanged-scenario VB workers; compute 34 fresh VB
   components and rebuild all 32 compact initializers.
6. Require exact initializer hashes and posterior-target hashes before
   importing 120 unchanged-scenario MCMC workers.
7. Compute 40 fresh MCMC workers for the two changed scenarios. Do not reject
   a useful predictive result solely for imperfect scalar mixing.
8. Recompute all 16 DGP oracles and all 64 path/mean-state score cells so the
   final composed packet has a single scoring implementation and provenance
   surface.
9. Compare the completed packet with the current shared-backbone article
   authority. Promote only after this audit; do not edit article or Overleaf
   assets in the execution lane.
10. Defer the 19-level dense-grid crossing study until the current seven-level
    authority decision is frozen.

## Failure-closed reuse gates

Reuse is prohibited unless all of the following hold:

- exactly six scenarios are specification-identical and exactly the two named
  scenarios changed;
- source worker `DONE` markers and artifact manifests verify;
- source and target worker plans agree on model, quantile, seeds, selected
  backbone, RHS prior, and design fingerprint;
- article-MCMC target compact-initializer SHA-256 hashes are identical;
- recomputed posterior-target hashes equal the stored source hashes;
- all imported worker summaries are rebound to the target plan and their
  manifests are regenerated and reverified;
- all exAL MCMC rows declare exact M0.

Any mismatch stops before fresh computation. Existing verified imported workers
are idempotently reused on resume; incomplete or malformed targets are never
silently overwritten.

## Runtime and reproducibility

- Host: Jerez.
- Parallelism: 15 distinct physical cores with affinity
  `0,1,8,9,12,13,19,20,24,25,27,28,29,30,31`. CPU 15 is deliberately
  excluded because the prelaunch audit found an unrelated long-running process
  there; CPUs 15 and 16 remain outside the continuation allocation.
- BLAS and numerical libraries: one thread per worker.
- Pinned runtime: R 4.6.0.
- Historical expanded and source runtime roots remain immutable inputs. The new
  confirmation and score roots are isolated under the continuation worktree.
- Runtime outputs remain Git-ignored. Code, contracts, tests, and this decision
  record are committed and pushed only to the dedicated JOINT branch.
- The launcher is resumable at expanded closeout, nested quantile, VB, MCMC,
  oracle, score-cell, and finalization gates.

## Verification checklist

- [x] Expanded boundary audit is vectorized and regression-tested on multiple rows.
- [x] Expanded 768-candidate contract and 300-state readout guard are restored on
  top of the latest recovered JOINT execution code.
- [x] Six-versus-two specification identity is encoded as a fail-closed gate.
- [x] Quantile, VB, and MCMC reuse importers regenerate and verify manifests.
- [x] Confirmation freeze accepts an explicit continuation branch, run tag, and
  source worktree while preserving historical defaults.
- [x] Exact M0 is asserted for every exAL MCMC row.
- [x] Dedicated resumable 15-core Jerez launcher is implemented.
- [ ] Jerez preflight passes from a clean, synchronized remote branch.
- [ ] Expanded final manifest and terminal receipt verify.
- [ ] Quantile closeout: 408/408 complete, 0 failed; 306 reused, 102 fresh.
- [ ] VB closeout: 136/136 complete, 0 failed; 102 reused, 34 fresh.
- [ ] MCMC closeout: 160/160 complete, 0 failed; 120 reused, 40 fresh.
- [ ] Score packet: 64/64 complete with finite outputs and zero contract crossings.
- [ ] Current-authority comparison and article-safe integration handoff are frozen.

## Explicit exclusions

No new Gaussian screen, no protected-window tuning, no universal DESN choice,
no dense-grid fit, no article edit, no `main` merge, and no Overleaf publication
are authorized by this continuation.
