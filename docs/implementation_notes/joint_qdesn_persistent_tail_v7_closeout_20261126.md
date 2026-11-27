# JOINT persistent-heavy-tail V7 closeout

## Lane identity

- Lane: JOINT persistent-heavy-tail V7 full-model confirmation.
- Muscat worktree:
  `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_persistent_tail_sealed_v5_20261126`.
- Branch and upstream:
  `work/joint-qdesn-persistent-tail-v7-full-confirmation-20261126`.
- V6 parent: `770be4f5c6c8d80b4b600f65390652e49571c06d`.
- Frozen scientific HEAD before this closeout note:
  `d96998d8f520fe5c327530319163bbf3ca6ccc0f`.
- Jerez execution worktree:
  `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_persistent_tail_v7_full_confirmation_20261126`.

The six scientific commits after the V6 parent are additive and contain the V7 implementation,
source guard, protected-design correction, refreshed source pins, and complete score wiring. The
closeout commit changes documentation only. Authoritative `main`, article files, and Overleaf were
not modified.

## Frozen scope and completion

V7 tested the V6 candidate `persistent_heavy_tail__fitfirst_v4_2430` against the corrected current
authority for one scenario and four models: independent and joint QDESN under AL and exAL. It used
the seven-level grid, recursive mean-state forecast policy, three MCMC chains per model, corrected
unbounded AL scale updates, and exact M0 for every exAL chain. The architecture, article fixture,
oracle bank, forecast policy, and authority packet were hash pinned. No article or Overleaf file was
modified.

| Gate | Expected | Complete | Failed | Result |
|---|---:|---:|---:|---|
| VB components | 17 | 17 | 0 | pass |
| MCMC chains | 12 | 12 | 0 | pass |
| Model cells | 4 | 4 | 0 | pass |
| Score workers | 8 | 8 | 0 | pass |
| Contract crossings | 0 | 0 | 0 | pass |
| Compatible target/kernel identities | 4 | 4 | 0 | pass |

## Scientific result

| Model | Forecast mean improvement | Interval-width reduction | Fit-MAE change | Assessment |
|---|---:|---:|---:|---|
| Independent AL | 27.1% | 94.3% | -74.9% | strong candidate evidence |
| Joint AL | 29.2% | 58.6% | +62.6% | do not promote; joint target review |
| Independent exAL | 26.0% | 91.7% | -64.3% | strong candidate evidence |
| Joint exAL | 24.7% | 57.3% | +219.1% | do not promote; joint target review |

The independent chains were stable. Their three score-chain means differed by only `5.14e-05` for
AL and `4.61e-04` for exAL. The joint AL score rank-Rhat was 1.267. Joint exAL had tail ESS 36.8,
and one score chain was unstable; its three means spanned 0.5416 to 0.5530. More importantly, every
joint chain fit poorly at every quantile. This is not an isolated scalar-mixing warning.

The complete-scenario promotion rule therefore retained the current authority. Interval separation
is descriptive evidence, not formal predictive equivalence or superiority. The protected article
fixture was used only after V6 selection and must not become a tuning target.

## Root-cause diagnosis

V6 learned quantile-band-specific independent priors. V7 mapped the lower profile to the joint
anchor and the median profile to all adjacent differences. The median `tau0=1e-13` is an extreme
shrinkage setting for a shared innovation prior. It suppresses coefficient differences across the
entire quantile grid, explaining the smooth forecast action and poor in-sample quantile recovery.
Additional iterations cannot change this target. A new architecture screen is also not justified:
the same architecture performs strongly for both independent models.

## Correct continuation

1. Keep the V6 architecture, data split, seven-level grid, forecast policies, corrected AL kernel,
   and exact-M0 exAL kernel fixed.
2. Freeze a new joint-only prior screen before computing new protected scores. Use non-protected
   selector/qualification fixtures, not this article fixture.
3. Screen anchor and innovation scales separately. The innovation grid must span materially less
   restrictive values than `1e-13`; slab settings must be varied jointly with those scales under a
   bounded, predeclared design.
4. Rank first by finite, nonpathological seven-quantile fit, including median and both extreme
   tails; then use internal rolling-origin recursive forecast performance among the fit-eligible
   candidates.
5. Qualify a small joint AL/exAL frontier on fresh non-protected seeds. Imperfect scalar mixing is
   review-level, but unstable score functionals or uniformly poor quantile fits are not waived.
6. Run one protected four-model confirmation only after the joint prior is frozen. A future rule may
   allow model-specific replacement, but it must be declared before seeing that confirmation.

Do not rerun the successful independent chains in the exploratory screen. Do not promote their V7
rows post hoc under a rule that was frozen as whole-packet promotion.

## Runtime evidence

Runtime root on Jerez:

`application/cache/joint_qdesn_persistent_tail_v7_full_confirmation_20261126`

The transfer inventory verifies 234 files and 780,756,194 bytes. Key SHA-256 values:

| Artifact | SHA-256 |
|---|---|
| `v7_final_decision.csv` | `4b62de685d39fd85ff674fb97534cce81e8df0b7c916653f3eb36be5b165f3e3` |
| `v7_authority_comparison.csv` | `75e7a21c941bff9fb8ef4e80bc062da7c978ada09ae9ce9b07ef77c37b3e9d53` |
| `v7_score_summary.csv` | `1a84a86519d47194c0ff2261e7be83853d5d838a43161d3f2a2b0a5dd63e9e01` |
| `v7_scientific_audit.csv` | `d5248418ac80ddbad388c6e1c0af4be56ed429491e3f83d13f1fd50592a34edd` |
| `complete_chain_identity_audit.csv` | `a4609d6a66a2cbd96060ca0fd7d4e9b0350e5adb371ba2392328d909c4e0bf44` |
| `transfer_inventory.csv` | `eecb225ea7e555dc1d4f00ffeb3adad62bed1477dac877abd97a0427a4fa8b9b` |

The first score launch failed before scoring because its cell registry omitted frozen architecture
metadata. The failed logs were retained under
`superseded_score_missing_architecture_metadata_20261126`. The registry was corrected and tested;
VB and MCMC were not rerun, and the successful score packet contains no failed worker.

The ignored runtime remains on Jerez and must not enter Git. The 746 MiB directory includes the
posterior draws, manifests, score packet, audits, hashes, and the preserved pre-worker failure
receipt. Its transfer inventory was independently reverified after closeout: 234 files and
780,756,194 bytes, with no mismatch.

## Verification

All checks used pinned R 4.6.0 where applicable.

| Check | Result |
|---|---|
| `test_joint_qdesn_persistent_tail_v7.R` | pass, 49 expectations |
| `test_joint_qdesn_persistent_tail_v7_source_guard.R` | pass, 19 checks and 5 mutation rejections |
| `test_joint_qdesn_persistent_tail_v6.R` | pass, 47 expectations |
| `test_joint_qdesn_al_kernel_correction.R` | pass |
| `test_joint_exqdesn_inference_dispatch.R` | pass |
| `test_joint_qdesn_stronger_window_confirmation.R` | pass |
| `test_joint_qdesn_stronger_window_score.R` | pass |
| `test_joint_qdesn_superfinal_al_kernel_rerun.R` | pass, 18 checks |
| V7 launch-script `bash -n` | pass |
| Git whitespace check | pass |

The source guard authorizes only the eight V7 scientific paths and rejects unauthorized mutation.
The runtime chain-identity audit verifies four mutually compatible target/kernel identities. Every
exAL chain used exact `M0_v_collapsed_support_logit`; every AL chain used the corrected positive,
unbounded scale update.

## Publication and exclusion boundary

No article-safe table, figure, prose, bibliography, or Overleaf file is proposed for publication
from V7. The committed implementation and closeout notes are reviewable scientific provenance.
All files below `application/cache/joint_qdesn_persistent_tail_v7_full_confirmation_20261126`,
including `.rds` draws and the superseded score-launch receipt, remain generated runtime evidence
and excluded from Git.

## Integration status

The current authority remains authoritative. This branch is useful reproducibility and diagnostic
evidence, but it is not the requested super-final article replacement.

`NOT_READY_FOR_INTEGRATION`
