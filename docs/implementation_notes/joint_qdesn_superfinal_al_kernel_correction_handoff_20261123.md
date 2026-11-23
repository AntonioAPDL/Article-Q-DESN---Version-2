# Frozen JOINT AL-kernel correction handoff

Date: 2026-11-23

Status: `NOT_READY_FOR_INTEGRATION`

This is a correction-review and rerun-approval handoff. It is not a scientific
result promotion, article packet, Overleaf payload, or production-launch
authorization.

## Lane identity

- Lane: JOINT super-final predictive-stability AL-kernel correction.
- Transcript: current JOINT Codex conversation; no filesystem transcript path
  is exposed to this worktree.
- Worktree:
  `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_superfinal_al_kernel_correction_20261123`
- Branch: `work/joint-qdesn-superfinal-al-kernel-correction-20261123`
- Intended upstream:
  `origin/work/joint-qdesn-superfinal-al-kernel-correction-20261123`
- Frozen source branch:
  `work/joint-qdesn-superfinal-predictive-stability-20261122`
- Frozen source HEAD:
  `5995ac30fae8070cb2fcef1a4cce659886c83d40`
- Scientific correction commit:
  `c9e728842c5c256bfded27d27987c4f9dd7ebc94`
- Base relationship: the correction commit is one direct descendant of the
  frozen source HEAD. At correction freeze, `origin/main...c9e72884` was
  `0 behind / 35 ahead`; 34 commits are inherited from the frozen source lane
  and one is this correction.

The final remote branch tip also contains this handoff note. Verify the exact
tip with `git rev-parse HEAD` after fetching; the chat handoff supplies that
post-push SHA because a file cannot contain the hash of the commit that contains
it.

## Resolution of coordinator blockers

### 1. AL scale update

Resolved. The declared AL scale prior and mixture kernel imply an
inverse-gamma conditional on `(0, Inf)`. The sampler now draws directly from
that conditional and never clips. Historical finite `sigma_bounds` arguments
are accepted only for call compatibility and normalize to `(0, Inf)`; they do
not alter the target, transition, or diagnostics.

Exact-M0 exAL was not changed.

### 2. Complete target and kernel identities

Resolved for corrected artifacts. Historical `posterior_target_sha256` is
preserved. New artifacts carry:

- `complete_posterior_target_sha256`;
- `effective_sampler_control_sha256`;
- `sigma_support = (0,Inf)`;
- an explicit scale-update identifier.

Score preparation rejects within-cell target/kernel mismatch. The super-final
combiner rejects missing or incompatible corrected identities, including any
attempt to combine historical capped chains with corrected uncapped chains.

### 3. Source guard

Resolved without changing the historical transition guard or its manifest. A
new composable guard validates the historical authorization, validates the
exact 62-path JOINT authorization, and accepts only their 69-path union. The
historical GloFAS fixture still rejects all 43 expected mutations.

### 4. Minimum rerun

Determined, not launched.

- Mandatory: 96 original AL workers, 32 cells, three chains per cell.
- Mandatory: rescore all 32 corrected AL cells and recompute complete-scenario
  decisions.
- Conditional: five supplemental persistent-heavy-tail challenger joint-AL
  chains only if the corrected source audit still requires that target.
- Reuse: all exact-M0 exAL workers/scores, VB initializers, designs, DGP
  fixtures, oracle banks, reservoirs, priors, and frozen seeds.

Historical cost was 43.83447 mandatory CPU-hours plus 2.06559 conditional
CPU-hours. Reserve approximately four wall-clock hours on 15 one-thread cores
and at least 0.5 GiB free disk. These are planning estimates, not a launch.

## Exact correction surface

Scientific and orchestration code:

- `application/R/joint_qvp_qdesn.R`
- `application/R/joint_qdesn_stronger_window_confirmation.R`
- `application/R/joint_qdesn_stronger_window_score.R`
- `application/R/joint_qdesn_superfinal_predictive_stability.R`
- `scripts/composable_scientific_source_guard.R`
- `scripts/glofas_unit_member_integration_source_guard.R`

Tests and full-suite registration:

- `application/tests/run_tests.R`
- `application/tests/test_composable_scientific_source_guard.R`
- `application/tests/test_integrated_forecast_transition_source_guard.R`
- `application/tests/test_joint_qdesn_al_kernel_correction.R`
- `application/tests/test_joint_qdesn_stronger_window_confirmation.R`
- `application/tests/test_joint_qdesn_stronger_window_score.R`
- `application/tests/test_joint_qdesn_superfinal_predictive_stability.R`
- `application/tests/test_joint_qvp_qdesn_mcmc_calibration.R`

Documentation and reproducibility metadata:

- `docs/implementation_notes/joint_qdesn_superfinal_al_kernel_correction_20261123.md`
- `docs/reproducibility/joint_qdesn_superfinal_al_kernel_correction_sources_20261123.csv`
- `docs/reproducibility/joint_qdesn_superfinal_al_kernel_correction_test_results_20261123.csv`
- `docs/reproducibility/joint_qdesn_superfinal_al_kernel_rerun_scope_20261123.csv`
- this handoff note.

No article, table, figure, bibliography, Overleaf, model-selection, reservoir,
prior, or frozen runtime file changed.

## Evidence and hashes

- JOINT 62-path source manifest SHA-256:
  `331437cf5a22dbb61f7d29374c9db356b68265e09ed5dd2adfe2e4e3b436a11d`
- Composable source guard SHA-256:
  `5168cb4f3b4a0e6741bc74aaeda2528cce3acdbe5c84bf6c987bf8bc59b71c2c`
- Frozen source MCMC summary SHA-256:
  `6621609d62e6cdeb80086b4fdb0ea03ade405a0cbdd2548bb04f65d6da7ac9c9`
- Frozen source MCMC plan SHA-256:
  `e2da12a9c87987cb0b9c0221a0ec8b69a8f66df77dab39420b636b8f151f9e01`
- Frozen supplemental MCMC summary SHA-256:
  `0fc80888470e76eea8289ca9ce6dbd01ceb69c965568a8290a322f2143dedafa`
- Coordinator chain-bound audit SHA-256:
  `4d01bf9f1223ffa3413018383703aa444ff1b1fd83191884b922a748e845a914`
- Coordinator cell-bound audit SHA-256:
  `931a75daee131cf0d986d3c8232fa1ac620ed84a429e9aabf55ec161516f4d16`

The source and super-final runtimes remain in their original ignored locations.
No corrected runtime exists yet. Production run count for this correction is
zero.

## Verification completed

Pinned R: `/data/jaguir26/local/opt/R/4.6.0/bin/Rscript` with numerical thread
counts fixed to one.

Passed:

- exact AL conditional and direct-draw equivalence;
- start/support invariance;
- complete target/kernel compatibility and rejection tests;
- valid whole-scenario fallback and anti-splicing tests;
- AL core, calibration, and multichain regressions;
- posterior-target contract regression;
- exact-M0 exAL dispatch regression;
- RHS numerical reference checks;
- all eight previously omitted JOINT lane tests, now registered in
  `application/tests/run_tests.R`;
- composable source guard: 59 checks and nine expected mutation rejections;
- transition guard: 59 checks and 35 historical mutation rejections;
- GloFAS source guard: 68 checks and all 43 historical mutation rejections;
- `git diff --check`.

The exact receipt is
`docs/reproducibility/joint_qdesn_superfinal_al_kernel_correction_test_results_20261123.csv`.

## Unresolved gates

1. The mandatory corrected AL campaign and rescoring have not been approved or
   launched. Therefore no corrected scientific result packet exists.
2. The repository-wide test harness stops at the separate appendix-compression
   receipt because that publication guard intentionally pins the old
   `application/R/joint_qvp_qdesn.R` bytes. It is not weakened here. After the
   corrected results are approved, the integration coordinator must perform a
   scoped appendix protected-source receipt refresh and rerun the full suite.
3. The conditional five-chain supplement can be decided only after the
   corrected 96-chain source packet is scored.

## Required next action and merge order

1. Coordinator reviews this correction commit, source manifest, tests, and
   proposed rerun scope.
2. Approve or reject the 96-worker mandatory AL rerun. Do not merge article
   assets and do not publish Overleaf.
3. If approved, launch into a new ignored runtime root using the frozen inputs,
   seeds, and budgets; never overwrite the historical runtimes.
4. Rescore 32 AL cells and recompute complete-scenario decisions.
5. Run the five supplemental AL workers only if the corrected source audit
   still requires them.
6. Freeze a new result handoff. Only then may the integration coordinator merge
   the corrected science, refresh the appendix source receipt, run the complete
   suite, and consider article assets.

Article-safe files to publish now: none.

Runtime/generated paths that remain excluded:

- `application/cache/joint_qdesn_stronger_window_richer_screen_20261121/`
- `application/cache/joint_qdesn_superfinal_predictive_stability_20261122/`
- any future corrected campaign runtime root;
- `local_trackers/`, logs, checkpoints, posterior draws, `.rds`, `.rda`, and
  `.RData` files.

`NOT_READY_FOR_INTEGRATION`
