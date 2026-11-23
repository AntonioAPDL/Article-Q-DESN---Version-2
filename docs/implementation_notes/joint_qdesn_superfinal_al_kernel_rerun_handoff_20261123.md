# Frozen JOINT corrected AL-kernel result handoff

Date: 2026-11-23

Status: `READY_FOR_INTEGRATION`

This is the final correction and result handoff for the JOINT super-final lane.
It supersedes the earlier correction-review handoff and the rejected frozen
predictive-stability packet for integration purposes. The earlier branches and
runtimes remain historical provenance and must not be merged separately.

## Lane identity

- Lane: JOINT super-final predictive-stability AL-kernel correction and rerun.
- Transcript: current JOINT Codex conversation; no filesystem transcript path
  is exposed to this worktree.
- Worktree:
  `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_superfinal_al_kernel_rerun_20261123`
- Branch: `work/joint-qdesn-superfinal-al-kernel-rerun-20261123`.
- Upstream:
  `origin/work/joint-qdesn-superfinal-al-kernel-rerun-20261123`.
- Scientific execution HEAD:
  `e1dc9688b6c20b1f235e402b55e50d9802ac0cd2`.
- Fresh integration base and merge base:
  `d49b08e025056020cb12bbdcf85f046fac3f2f88` (`origin/main` on
  2026-11-23).
- Relationship at closeout: 0 commits behind and 38 commits ahead of the
  recorded main base; 0 ahead and 0 behind the dedicated upstream before the
  final documentation commit.
- The final pushed handoff tip is reported out of band after commit and fresh
  fetch, because a tracked file cannot contain the hash of its own commit.

The exact final changed-file inventory is
`docs/reproducibility/joint_qdesn_superfinal_al_kernel_rerun_changed_files_20261123.csv`.
Merge this branch once. Do not separately merge its inherited persistent-tail,
stronger-window, super-final, or correction branches.

## Coordinator blocker resolution

1. The AL scale conditional is now sampled directly from its inverse-gamma
   full conditional on `(0, Inf)`. Numerical starting values cannot change the
   target support, and finite compatibility bounds are not used as clipping
   limits.
2. Corrected chains carry complete posterior-target and effective
   sampler-control hashes. Incompatible chain combinations fail closed.
3. The historical transition guard remains pinned. The composable and final
   source guards authorize only the reviewed correction and execution surfaces,
   and their mutation tests pass.
4. The minimum coherent rerun was executed: all 96 affected AL chains and all
   32 affected MCMC-AL score cells. Exact-M0 exAL evidence was reused without
   refitting.

## Health and completion

| Gate | Observed | Failures | Status |
|---|---:|---:|---|
| Corrected AL MCMC chains | 96 / 96 | 0 | pass |
| Reused exact-M0 exAL chains | 96 / 96 | 0 | pass |
| Combined MCMC chains | 192 / 192 | 0 | pass |
| Compatible three-chain model cells | 64 / 64 | 0 | pass |
| Corrected MCMC-AL score cells | 32 / 32 | 0 | pass |
| Reused VB/exAL score cells | 96 / 96 | 0 | pass |
| Reconstructed score rows | 128 / 128 | 0 | pass |
| Selected scenario-model rows | 32 / 32 | 0 | pass |
| Canonical contract crossings | 0 | 0 | pass |
| Conditional AL supplement | not required | 0 | pass |

No MCMC, score, or finalization run remains.

## Scientific result

The correction changed one of the 32 affected MCMC-AL score cells:

- `persistent_heavy_tail__challenger__joint_qdesn_rhs`;
- posterior score mean changed by `-0.0045603663`, from `0.6709442` to
  `0.6663838`;
- its score interval width increased by a factor of `1.2398332`.

The other 31 corrected MCMC-AL score cells are numerically unchanged. The
changed cell is not eligible for the final packet because its unchanged
exact-M0 joint-exAL counterpart remains functionally unstable. The frozen
whole-scenario rule therefore retains the complete persistent-heavy-tail
parity packet and skips the five-chain conditional AL supplement.

Consequently, the final corrected 32-row selected packet is byte-for-byte
identical to the previously frozen selected packet. Both have SHA-256
`69aced9bbd37ee506a382ed85a7fe2aba116ed296ae4285890540e572122f5f3`.
No article score value changes as a result of the AL-kernel correction.

Descriptively:

- all eight winner-versus-runner 95% score intervals overlap;
- all 16 likelihood-specific joint-versus-independent marginal interval pairs
  overlap;
- joint has the lower posterior mean in 6 of 16 comparisons and independent
  in 10 of 16;
- joint models have zero selected canonical raw crossings in all scenarios;
- all selected models have zero canonical contract crossings.

Overlapping intervals do not establish formal predictive equivalence. These
are descriptive comparisons, and numerical minima must not be presented as
formal superiority without an appropriate paired contrast or decision rule.

## Frozen evidence

Ignored runtime root:

`/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_superfinal_al_kernel_rerun_20261123/application/cache/joint_qdesn_superfinal_al_kernel_rerun_20261123`

Primary evidence:

- `final_decision.csv`;
- `final_manifest.csv`;
- `corrected_superfinal_selected_score_summary.csv`;
- `conditional_al_supplement_decision.csv`;
- `full_confirmation/corrected_mcmc_worker_summary.csv`;
- `full_confirmation/corrected_chain_identity_audit.csv`;
- `full_confirmation/corrected_mcmc_final_manifest.csv`;
- `full_confirmation/score_packet/score_summary.csv`;
- `full_confirmation/score_packet/corrected_vs_historical_al.csv`;
- `full_confirmation/score_packet/score_final_manifest.csv`;
- `integration_handoff/final_gate_summary.csv`;
- `integration_handoff/scenario_winners.csv`;
- `integration_handoff/joint_independent_contrasts.csv`;
- `integration_handoff/al_correction_impact_summary.csv`;
- `integration_handoff/selected_packet_identity.csv`;
- `integration_handoff/runtime_transfer_inventory.csv`;
- `integration_handoff/runtime_inventory_verification.csv`;
- `integration_handoff/handoff_manifest.csv`.

The final runtime inventory and handoff hashes are recorded in
`docs/reproducibility/joint_qdesn_superfinal_al_kernel_rerun_result_receipt_20261123.csv`.

## Verification

Focused correction, rerun, final-source, composable-source, and historical
transition-guard tests pass. The complete repository suite passes under pinned
R 4.6.0, one numerical thread, the pinned local `posterior` library, and the
existing PyYAML dependency path. Its final log SHA-256 is
`b0aa7dac7084eed3b36e8ee366d0b8f01d7eded32739b2881a7a3d1f90f730da`.

Exact commands and results are in
`docs/reproducibility/joint_qdesn_superfinal_al_kernel_rerun_test_results_20261123.csv`.
Article inputs were not modified, so manuscript compilation is not part of
this lane closeout. The integration coordinator remains responsible for the
combined-repository test and any later article regeneration or compilation.

## Publication and exclusions

Article-safe files to publish from this lane now: none. No article, table,
figure, bibliography, or Overleaf file was modified.

The following remain excluded from Git and publication:

- the corrected runtime root above;
- source and historical super-final runtimes;
- posterior draws, score draws, model objects, `.rds`, `.rda`, and `.RData`;
- caches, temporary logs, checkpoints, and `local_trackers/`.

Retain the corrected runtime until integration has verified the transfer
inventory and the article coordinator has completed any required projection.

## Remaining scientific cautions

- Interval overlap is not a formal equivalence test.
- Persistent heavy tail remains a difficult scenario; parity is retained
  because the challenger packet fails the frozen exact-M0 functional gate.
- The evaluation realization was excluded from candidate selection, but it was
  evaluated previously; do not describe it as previously unseen.
- Historical architecture and shrinkage settings changed together, so any
  improvement cannot be attributed to one hyperparameter.
- Scalar mixing diagnostics remain supporting evidence. Stable forecast
  functionals and scores are the primary scientific quantities, but
  pathological functional behavior is never waived.

## Integration order

1. Fetch `origin` with command-line Git and verify the final branch tip supplied
   with this handoff, its clean status, and 0/0 upstream synchronization.
2. Verify `integration_handoff/runtime_transfer_inventory.csv` and
   `integration_handoff/handoff_manifest.csv` against the retained runtime.
3. Create a fresh integration worktree from current `origin/main` and merge
   this branch once with `--no-ff`.
4. Do not merge any inherited intermediate JOINT branch separately.
5. Run the complete combined-repository suite and `git diff --check`.
6. Regenerate article assets only if the integration coordinator's current
   article contract requires it. This correction itself changes no selected
   score value.
7. Push authoritative main only through the guarded command-line Git workflow.
   Do not publish or touch Overleaf until the separate article projection is
   reviewed and compiled.

`READY_FOR_INTEGRATION`
