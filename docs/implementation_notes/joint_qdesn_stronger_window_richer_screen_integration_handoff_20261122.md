# JOINT stronger-window richer-screen integration handoff

Date: 2026-11-22

Status: `READY_FOR_INTEGRATION`

Article replacement authorized: `FALSE`

## Lane identity

- Lane: JOINT stronger-window, richer-screen, scenario-specific Q-DESN
  selection and protected confirmation.
- Transcript lineage:
  `/home/jaguir26/.codex/sessions/2026/10/03/rollout-2026-10-03T17-18-52-019f191a-77c2-7393-9f42-60593f12e994_01a103a2-5608-7bb3-9841-be3a057a9efb.jsonl`.
- Worktree:
  `/data/jaguir26/local/src/Article-Q-DESN/.codex_work/joint_persistent_regime_recalibration_20261120`.
- Branch: `work/joint-qdesn-stronger-window-richer-screen-20261121`.
- Upstream: `origin/work/joint-qdesn-stronger-window-richer-screen-20261121`.
- Scientific source HEAD before this handoff:
  `b9e7399842e75b32e34bd5b17e716fc5a3d85a43`.
- Current `origin/main` and merge base at freeze preparation:
  `d49b08e025056020cb12bbdcf85f046fac3f2f88`.
- Relationship before the handoff commit: 28 commits ahead, zero behind.
- The exact pushed handoff HEAD is recorded in the ignored runtime
  `integration_handoff/git_state.csv` after commit and push.

## Scientific contract

Selection is scenario-specific. It uses a 500-row washout, 1,000-row fit
window, and 300-row internal recursive calibration window. The article
evaluation fixture is excluded from all selection. Readouts contain an
intercept plus all retained reservoir layers, with no raw input terms. The
screen varies depth, layer shape and width, output lags, leakage, spectral
radius, input scale, input sparsity, recurrent sparsity, and `tau0`.

Independent quantiles use nested VB continuation. Joint models inherit the
same scenario-specific backbone. Every exAL MCMC worker uses exact M0
`M0_v_collapsed_support_logit`. Protected scoring uses the seven-level
trapezoidal grid, origin-marginal DGP-integrated aCRPS, canonical recursive
mean-state forecasting, recursive-path sensitivity, equal-tailed 95%
intervals, and frozen independent coupling. Scalar mixing is review-level
when predictive functionals are stable; predictive-functional pathology is
not waived.

## Completion audit

| Stage | Expected | Complete | Failed | Result |
|---|---:|---:|---:|---|
| Benchmark | 6 | 6 | 0 | pass |
| Ridge R1a | 32,768 | 32,768 | 0 | pass |
| Ridge R1b | 8,192 | 8,192 | 0 | pass |
| Ridge R2 | 6,144 | 6,144 | 0 | pass |
| Ridge R3 | 4,608 | 4,608 | 0 | pass |
| RHS H1 | 4,400 | 4,400 | 0 | pass |
| RHS H2 | 2,400 | 2,400 | 0 | pass |
| RHS H3 | 960 | 960 | 0 | pass |
| Median AL | 480 | 480 | 0 | pass |
| Seven-grid AL | 1,344 | 1,344 | 0 | pass |
| Internal AL/exAL transfer | 432 | 432 | 0 | pass |
| Full VB packets | 16 | 16 | 0 | pass; 272/272 components |
| Full MCMC chains | 192 | 192 | 0 | pass; 64 cells, 3 chains each |
| DGP oracle shards | 64 | 64 | 0 | pass; 8 banks |
| Protected score cells | 128 | 128 | 0 | pass |

The final independent audit verified 404 nested artifact manifests containing
1,912 entries, with zero missing, size-mismatched, or hash-mismatched files.
The 2,790-file confirmation inventory covers 5,228,293,518 bytes and verified
with zero mismatches. All 128 score cells are finite and pass their
teacher-forced audit. The selected MCMC packet has zero contract crossings
and six raw crossings.

## Frozen result

The frozen complete-packet rule promotes five challengers and retains three
new-geometry parity packets.

| Scenario | Frozen packet decision | Descriptive MCMC winner | Mean DGP-integrated aCRPS |
|---|---|---|---:|
| Asymmetric Laplace tail | retain parity | Joint exAL | 0.36910 |
| Gaussian-mixture bridge | promote challenger | Joint AL | 0.41179 |
| Laplace bridge | retain parity | Independent AL | 0.35775 |
| Nonlinear reservoir-friendly | promote challenger | Joint AL | 0.46087 |
| Normal bridge | promote challenger | Independent AL | 0.33884 |
| Persistent heavy tail | promote challenger, review | Independent AL | 0.51941 |
| Regime shift | promote challenger | Independent AL | 0.46500 |
| Student-t location-scale | retain parity | Independent AL | 0.39648 |

The persistent-heavy-tail challenger produces a large improvement over its
matched parity packet, but its two joint rows have unstable score functionals.
The joint-AL mean exceeds its own 97.5% quantile and has score MCSE 0.711;
joint exAL has folded R-hat 1.305 and tail ESS 53.6. Laplace joint-exAL parity
also has tail ESS 35.7. These three rows require review before article use.
They do not invalidate the reproducibility-code integration or the other
scenario packets.

Interval overlap is not formal predictive equivalence. The evaluation
fixture was excluded from candidate selection but was evaluated previously,
so it must not be called unseen. Architecture and shrinkage changed together;
no improvement can be attributed causally to one hyperparameter.

## Frozen evidence and hashes

Runtime root:

`application/cache/joint_qdesn_stronger_window_richer_screen_20261121/`

Handoff root:

`application/cache/joint_qdesn_stronger_window_richer_screen_20261121/integration_handoff/`

| Artifact | SHA-256 |
|---|---|
| `score_summary.csv` | `d6f8045171a2955bbbb136a040882d5d6a93d2e18af706e5a803a1313ad3483c` |
| `challenger_parity_contrasts.csv` | `ff6d540b0524669f52bd52031eecbe5d1a74dd41c876c890e7b9bc0e7aa1a310` |
| `scenario_packet_decisions.csv` | `08cd1bd5462642e6f19d5c496c6951e0cb499638d9362d06b57aa0d579c6c97b` |
| `final_decision.csv` | `5c37e0a552e87e7832643f5baf24e76e5148c97010136d005f36fafd95fbce4b` |
| `score_final_manifest.csv` | `e0713427aca5d6358e468394ade636620a2088e5d39b8c0e5196080df4774643` |
| `full_confirmation_transfer_inventory.csv` | `213dc7f45004b0383db87054abf479200193b45056b64d461f2edc75a34f28d0` |
| `integration_audit.csv` | `4e8c6cf2a86906931b1af8108bf2cdc216dd9d89b0d6f58ca055d5cac78dd0aa` |
| `predictive_functional_review.csv` | `a0a30f0cb590ceb9527123a7fdb0618396621e0af6047cfdce9e3c53611ff138` |
| `selected_mcmc_packet_summary.csv` | `0a52cdba3652341c207d59dde41ed3369c28cb7e1610921465962ba2d4b42e67` |
| `handoff_manifest.csv` | verify from runtime after `git_state.csv` is added |

The runtime is ignored and must remain excluded from Git. It occupies
6,925,625,312 bytes across 262,467 files. Do not delete the full-confirmation
posterior draws or oracle banks before integration review. Seventeen empty
failed-attempt directories were removed; durable failure logs and exits remain.

## Tests

The following focused tests passed under pinned R 4.6.0:

- `application/tests/test_joint_qdesn_stronger_window_confirmation.R`
- `application/tests/test_joint_qdesn_stronger_window_score.R`
- `application/tests/test_joint_qdesn_recursive_mean_design.R`
- `application/tests/test_joint_qdesn_recursive_dgp_oracle.R`
- `application/tests/test_joint_qdesn_recursive_mean_score_packet.R`
- `application/tests/test_joint_exqdesn_inference_dispatch.R`
- `application/tests/test_joint_qdesn_stronger_window_transfer.R`
- `git diff --check`

## Integration boundary

The coordinator may integrate the code, contracts, tests, and tracked
documentation after independently verifying the pushed branch and runtime
handoff inventory. The coordinator must separately compare the selected
packet with historical article authority and review the three flagged score
functionals. No article table, figure, prose, bibliography, or Overleaf file
is an article-safe replacement from this lane by itself.

Recommended merge order is this branch first, then a new integration-only
article reconciliation branch from current `origin/main`. Do not merge this
lane with unrelated active scientific branches in one conflict-resolution
step. Do not rerun selection, alter frozen packet decisions, or use
model-specific splicing during integration.

Runtime/generated paths that must remain excluded:

- `application/cache/joint_qdesn_stronger_window_richer_screen_20261121/`
- `local_trackers/joint_qdesn_stronger_window_richer_screen_plan_20261121/`

Article-safe candidate evidence for review, not automatic publication:

- `score_packet/score_summary.csv`
- `score_packet/challenger_parity_contrasts.csv`
- `score_packet/scenario_packet_decisions.csv`
- `integration_handoff/selected_mcmc_packet_summary.csv`
- `integration_handoff/joint_independent_interval_width_audit.csv`
- `integration_handoff/predictive_functional_review.csv`

`READY_FOR_INTEGRATION`
