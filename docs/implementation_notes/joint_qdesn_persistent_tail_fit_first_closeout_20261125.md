# JOINT persistent-heavy-tail fit-first closeout

Date: 2026-11-25

## Scope and result

This continuation tested whether any of the ten architectures that reached the
frozen V3 tail shortlist could improve the persistent-heavy-tail case while
first demonstrating strong quantile-path fit. It did not use the article
fixture or any protected final-test outcome.

All 90 atomic workers completed without failure: 40 oracle workers and 50
seven-quantile independent AL VB fits. The five fresh fixtures were evaluated
at ten rolling origins with teacher forcing between origins and recursive
multi-step forecasting within each origin. Each fixture used eight independent
oracle shards of 4,096 paths, for 32,768 DGP paths per fixture.

The terminal decision is
`FIT_FIRST_COMPLETE_RETAIN_EXACT_V2`. The selected candidate is
`persistent_heavy_tail__v3_0002`, the exact V2 fallback. No downstream
four-model AL/exAL, joint/independent confirmation is authorized by this lane.

## Selection evidence

| Quantity | Result |
|---|---:|
| Candidates evaluated | 10 |
| Fit-eligible candidates | 3 |
| Forecast near-tie candidates | 3 |
| Selected fit MAE | 0.07164224 |
| Selected horizon-1 MAE | 0.06595859 |
| Selected DGP-integrated aCRPS | 0.5159586 |
| Article fixtures used | 0 |
| Protected rows used | 0 |
| Contract crossings | 0 |

The lowest numerical forecast score among all candidates was 0.5153370 for
`persistent_heavy_tail__v3_1866`, but its fit MAE was 0.2173235 and it failed
the frozen fit-competence gate. The selected exact V2 fallback had the best fit
and horizon-1 MAE. The other fit-eligible candidates had DGP-integrated aCRPS
0.5164714 and 0.5170280, both inside the frozen near-tie region. The result
therefore supports retaining exact V2 rather than promoting a smoother model
because of a negligible forecast-score difference.

The frozen limits were fit MAE 0.09164224, horizon-1 MAE 0.09595859,
outer-tail MAE 0.2020824, forecast near-tie aCRPS 0.5211182, and short-horizon
aCRPS 0.4915883.

All five empirical oracle checks passed. Split-half relative differences ranged
from 0.0001617 to 0.0021251 against a 0.005 tolerance. Horizon-1 empirical vs
analytic relative differences ranged from 0.0000519 to 0.0048650 against a
0.01 tolerance.

## Provenance

- Frozen V3 parent: `4f54ea14d58a3d1caacf244ae525f1bb8a8dd648`.
- Worker execution commit: `88e432dfadb65ed9cb0b0398bb5f4402410fa75d`.
- Corrected finalization commit: `0ea707dadabb40706b1d16334d1b1b48f522b192`.
- Pinned runtime: R 4.6.0, one numerical thread per worker.
- Jerez launch: 30 distinct physical cores, CPUs 0--29.
- Capacity at launch: 104 GiB free under `/data`, 489 GiB available memory.
- Runtime storage after closeout: approximately 879 MiB.

The worker commit and finalization commit are recorded separately in
`source_git_state.csv` and `fit_first_finalization_git_state.csv`. The
finalization repair reconstructs protected-safe DGP truth from the frozen
location-scale registry as `mu_t + sigma_t q_epsilon(tau)`; it does not change
or rerun any fitted model or oracle path.

## Frozen evidence

Runtime root on Jerez:

`/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_persistent_tail_fit_first_20261125/application/cache/joint_qdesn_persistent_tail_fit_first_20261125`

| Artifact | SHA-256 |
|---|---|
| `fit_first_decision.csv` | `ef50855b782484a56b988a9b6240008d3091a1ec5feb353427bc9d0e623c726a` |
| `fit_first_candidate_aggregate.csv` | `ad5473d050fbaec49dc2bd743da672478da6fc3b0cfbd3ad08270883e0f963b4` |
| `fit_first_scores_by_replicate.csv` | `206f1583b689666e821ecc8e1e6614cf96a041194fc4fe513eb9e42197345207` |
| `oracle_diagnostics.csv` | `5e63889f9bb21755a0a2f7875004c29272793292ed95728b7e8458de43aec218` |
| `fit_first_final_manifest.csv` | `63b895de5472e192bb1e0613f4a0f6d5fdcb2fb25c4bd31575f58c86d12b24fb` |
| `preparation_manifest.csv` | `9bd50edbc93afe22f47359306a7a3520c84572e877107d12ba06b135db89da22` |
| `capacity_receipt.csv` | `824085616255538d3e223d8404ec12817f08857884d4968f08f1eef3d738b248` |

Every worker manifest and all six files in the final manifest verified.

## Verification

- `test_joint_qdesn_persistent_tail_fit_first.R`: pass, 20 expectations.
- `test_joint_qdesn_persistent_tail_fit_first_source_guard.R`: pass, 13 checks
  and five mutation rejections.
- `test_joint_qdesn_persistent_tail_exploration_v3.R`: pass.
- `test_joint_qdesn_stronger_window_score.R`: pass.
- `git diff --check`: pass.

No article, bibliography, main-branch, Overleaf, PriceFM, GloFAS, or unrelated
runtime file was changed. Runtime and generated oracle banks remain ignored.
