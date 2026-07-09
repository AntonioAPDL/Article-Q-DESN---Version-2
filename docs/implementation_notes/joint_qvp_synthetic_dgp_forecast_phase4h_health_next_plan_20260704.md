# Joint-QVP Synthetic DGP Forecast Phase 4h Health Check And Next Plan

Date: 2026-07-04

## Current Health Summary

Phase 4h is implemented and the full targeted tau0-refinement campaign is currently running in a detached `tmux` session.

| item | status | evidence | interpretation |
|---|---|---|---|
| Detached runner | running | `tmux` session `phase4h_tau0_refinement_20260704` is alive | The campaign is active and not blocked by the Codex shell. |
| R process | running | child process PID `3211390`, CPU-bound at about 99 percent during check | The job is doing computation, not idle. |
| Elapsed time at check | about 12 minutes | process elapsed time `12:33` during audit | Normal for a strong-control targeted VB screen. |
| Log file | present, empty so far | `phase4h_tau0_refinement_tmux_20260704_051021.log`, 0 bytes | Expected because the runner prints mostly at completion; not evidence of failure. |
| Output directory | present | `application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4h_tau0_refinement` | Artifact root is being populated. |
| Phase 1 targeted fixtures | complete | 13 fixture files under `phase1_fixtures_targeted` | Frozen scenario fixtures were materialized. |
| Fixture manifest | verified | 12 rows, all SHA-256 checks passed | Source fixture layer is reproducible. |
| Frozen targeted registry | correct | 7 rows, seeds `202610005,202611005,202612005,202613002,202614004,202615005,202616002` | Exact Phase 4c targeted rows were preserved. |
| Screen progress | in progress | `tau0_0p25_reference` complete; `tau0_0p2` directory started | 1 of 6 primary tau0 screens has completed. |
| Root Phase 4h summaries | pending | no root files yet | Expected; root summaries are written after all screens finish. |
| Smoke run | passed | smoke artifact hashes verified | CLI and artifact path are working. |
| Focused tests | passed | Phase 4g and Phase 4h focused tests completed | Implementation wiring is currently healthy. |

## Completed Screen Sanity Check

The first completed full-run screen is:

```text
tau0_0p25_reference
```

Summary:

| metric | value |
|---|---:|
| nested artifact manifest rows | 21 |
| nested manifest hashes verified | TRUE |
| raw crossing pairs | 15 |
| raw crossing origins | 15 |
| raw max crossing magnitude | 0.1319045 |
| contract crossing pairs | 0 |
| mean truth MAE | 0.1383506 |
| mean truth RMSE | 0.1656789 |
| VB refits | 16 |
| VB max-iteration rate | 0.125 |
| scenario gates | 1 pass, 6 review |

This exactly matches the previous Phase 4g `tau0_0p25` reference metrics:

| screen | raw crossings | raw max crossing | truth MAE | VB max-iteration rate |
|---|---:|---:|---:|---:|
| Phase 4g `tau0_0p25` | 15 | 0.1319045 | 0.1383506 | 0.125 |
| Phase 4h `tau0_0p25_reference` | 15 | 0.1319045 | 0.1383506 | 0.125 |

Interpretation:

```text
The Phase 4h wrapper is reproducing the Phase 4g reference behavior exactly for the completed reference screen.
```

That is the strongest possible early wiring check. It indicates the custom-grid wrapper has not changed the Phase 3 forecast validation contract, seed handling, or scoring path.

## Partial Crossing Diagnosis For Completed Screen

Raw crossings for `tau0_0p25_reference` remain concentrated where expected:

| adjacent tau pair | raw crossings |
|---|---:|
| 0.05-0.10 | 3 |
| 0.10-0.25 | 0 |
| 0.25-0.50 | 0 |
| 0.50-0.75 | 0 |
| 0.75-0.90 | 0 |
| 0.90-0.95 | 12 |

Scenario-level raw crossings:

| scenario | raw crossings |
|---|---:|
| persistent_heavy_tail__calibration_r05 | 6 |
| gaussian_mixture_bridge__calibration_r05 | 3 |
| student_t_location_scale__calibration_r05 | 3 |
| regime_shift__calibration_r02 | 2 |
| laplace_bridge__calibration_r05 | 1 |
| asymmetric_laplace_tail__calibration_r02 | 0 |
| heteroskedastic_seasonal__calibration_r04 | 0 |

Interpretation:

- The reference screen preserves the known failure geography.
- The dominant residual problem remains the upper extreme tail `0.90-0.95`.
- The major scenario contributors are still `persistent_heavy_tail`, `gaussian_mixture_bridge`, and `student_t_location_scale`.
- Contract forecast quantiles remain noncrossing, so the scoring contract is intact.

## What Is Not Done Yet

The full Phase 4h result is not yet available. The following root artifacts are expected only after all six screens complete:

- `tau0_refinement_grid.csv`
- `tau0_refinement_run_config.csv`
- `tau0_refinement_metric_summary.csv`
- `tau0_refinement_candidate_ranking.csv`
- `tau0_refinement_crossing_by_scenario.csv`
- `tau0_refinement_crossing_by_tau_pair.csv`
- `tau0_refinement_truth_by_tau.csv`
- `tau0_refinement_vb_runtime_summary.csv`
- `tau0_refinement_recommendation.csv`
- `artifact_manifest.csv`

Until those root files exist, the final tau0 decision should remain pending.

## Monitoring Commands

Check process health:

```bash
SESSION=$(cat application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/logs/phase4h_tau0_refinement.tmux_session)
tmux has-session -t "$SESSION" && echo running || echo not_running
tmux list-panes -t "$SESSION" -F 'pane_pid=#{pane_pid} current_command=#{pane_current_command}'
```

Inspect process resource use:

```bash
PANE_PID=$(cat application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/logs/phase4h_tau0_refinement.pid)
ps -o pid,ppid,stat,etime,time,%cpu,%mem,rss,vsz,cmd --ppid "$PANE_PID"
```

Tail completion log:

```bash
tail -f application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/logs/phase4h_tau0_refinement_tmux_20260704_051021.log
```

Check screen progress:

```bash
find application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702/phase4h_tau0_refinement/screen_runs \
  -maxdepth 2 -name run_config.csv | sort
```

## Completion Audit Plan

Once the run completes, perform this audit before interpreting the statistics:

1. Verify the `tmux` session exited normally and the log contains `PHASE4H_EXIT_CODE=0`.
2. Verify `artifact_manifest.csv` exists at the Phase 4h root.
3. Verify every root artifact hash.
4. Verify every nested Phase 3 manifest through `screen_run_manifest.csv`.
5. Confirm all six intended primary screens ran:
   - `tau0_0p25_reference`
   - `tau0_0p2`
   - `tau0_0p15`
   - `tau0_0p10_reference`
   - `tau0_0p075`
   - `tau0_0p05`
6. Confirm all screens used the frozen targeted registry and the same seven scenario ids/seeds.
7. Confirm contract crossings are zero for every screen.
8. Confirm all truth, hit-rate, pinball, WIS, CRPS, runtime, and VB summaries are finite.
9. Compare each candidate against `tau0_0p10_reference`, not only against `tau0_0p25_reference`.
10. Inspect crossing migration by tau pair, especially any movement into `0.75-0.90` or central pairs.

## Decision Rules After Completion

The Phase 4h winner should not be selected from global MAE alone. Use a gated decision:

| decision dimension | preferred behavior |
|---|---|
| Contract crossings | must be zero |
| Raw crossings | below 13, or equal to 13 with better convergence/tail truth |
| Upper-tail crossings | reduce or do not worsen `0.90-0.95` relative to `tau0_0p10_reference` |
| Crossing migration | no material movement into central tau pairs |
| Global truth MAE | no worse than `tau0_0p10_reference` by more than 1 percent |
| `tau=0.95` truth MAE | should not be sacrificed for total crossing reduction |
| VB max-iteration rate | preferably <= 0.20 |
| Runtime | preferably <= 1.25 times reference/baseline |

## Expected Interpretation Patterns

### Pattern A: `tau0_0p10_reference` remains best

Recommendation:

Run a calibration-pilot Phase 4 campaign with `tau0 = 0.10`. Do not change article defaults until the pilot passes a Phase 4b-style readiness audit.

### Pattern B: `tau0_0p15` or `tau0_0p2` nearly matches raw crossings with better VB convergence

Recommendation:

Prefer the more stable compromise candidate for the calibration pilot. This is the cleanest likely outcome if `tau0 = 0.10` is slightly too aggressive.

### Pattern C: `tau0_0p075` or `tau0_0p05` reduces crossings further without worsening tails or convergence

Recommendation:

Promote the smaller tau0 candidate to calibration pilot, but treat crossing migration and `tau = 0.95` truth error as review risks.

### Pattern D: all candidates plateau around 13-15 raw crossings

Recommendation:

Stop local tau0 tuning. Move to a Phase 4i structural diagnostic layer:

- separate anchor and adjacent-innovation shrinkage;
- scenario-level DESN feature norm audit;
- targeted heavy-tail/regime-shift design diagnostics;
- optional explicit smoothness/monotonicity regularization options.

## Recommended Next Action

Let the current Phase 4h run finish. The run is healthy and already reproduced the Phase 4g `tau0_0p25` reference exactly, so there is no reason to interrupt or relaunch it.

After completion, run the completion audit above and then prepare a Phase 4h closeout report with:

- final candidate ranking;
- raw vs contract crossing summary;
- tau-pair crossing migration;
- scenario-level residual crossing diagnosis;
- truth-by-tau comparison;
- VB convergence/runtime comparison;
- recommendation for calibration pilot or Phase 4i structural diagnostics.

