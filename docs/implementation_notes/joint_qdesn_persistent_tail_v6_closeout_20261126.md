# JOINT persistent-heavy-tail V6 closeout

Date: 2026-11-26

## Scope and authority

V6 tested whether the remaining persistent-heavy-tail weakness could be improved without another
global reservoir search. It replayed 24 existing V4 architectures, expanded the fixed RHS slab at
the two most relevant profiles, and calibrated lower, median, and upper AL scales separately. It did
not inspect the protected evaluation realization, change the data split, refit joint/exAL/MCMC
models, edit article assets, or supersede V5 automatically.

Execution branch:

- `work/joint-qdesn-persistent-tail-v6-tail-calibration-20261126`
- implementation HEAD before this closeout: `1a34f1d7535d74e8e36b704d1b625f98e90b69d8`
- frozen parent: V5 closeout `3a89fa103b273cd23cd3a2416ba44ff5b8fe4492`

## Completed evidence

| Stage | Expected | Completed | Failed | Decision |
|---|---:|---:|---:|---|
| Sentinel | 26 | 26 | 0 | Screen authorized |
| Component screen | 1,890 | 1,890 | 0 | 12 triplets qualified |
| Fresh qualification | 108 | 108 | 0 | 2 challengers sealed |
| Sealed confirmation | 120 | 120 | 0 | Seven-level confirmation authorized |
| Seven-level confirmation | 15 | 15 | 0 | New candidate confirmed |
| **Total** | **2,159** | **2,159** | **0** | **V6 complete** |

All workers used selector-only fixtures, complete SHA-256 manifests, finite recursion, and zero
protected rows. There were no convergence reviews in qualification, sealed, or seven-level
evidence.

## Confirmed candidate

V6 selected the candidate-2430 architecture:

- five layers with widths `15;15;14;14;14`;
- three response lags;
- input scale `0.075`;
- leakage schedule `0.9995;0.9995;0.9841361644;0.9637788402;0.9434215161`;
- spectral-radius schedule `0.999;0.9406531336;0.8217943888;0.7029356440;0.5840768992`.

Its fitted prior profiles are deliberately level-specific:

| Band | Normal RHS `tau0` | AL RHS `tau0` | Fixed slab | AL multiplier |
|---|---:|---:|---:|---:|
| Lower (`0.05`, `0.10`) | `1e-10` | `1e-7` | `0.01` | `1000` |
| Middle (`0.25`, `0.50`, `0.75`) | `1e-10` | `1e-13` | `0.01` | `0.001` |
| Upper (`0.90`, `0.95`) | `1e-10` | `3e-9` | `0.03` | `30` |

## Seven-level results

Five fresh matched fixtures were used. Lower values are better.

| Profile | DGP-integrated score mean | 95% empirical interval | Lower fit MAE | Median fit MAE | Upper fit MAE | Contract crossings |
|---|---:|---:|---:|---:|---:|---:|
| **V6 candidate 2430** | **0.519642** | `[0.477335, 0.548414]` | **0.094087** | **0.029884** | 0.109810 | 0 |
| Exact control | 0.521169 | `[0.483701, 0.547994]` | 0.114787 | 0.039216 | **0.105798** | 0 |
| V5 candidate 3242 | 0.522741 | `[0.479498, 0.551687]` | 0.106590 | 0.037596 | 0.127295 | 0 |

Relative to V5-3242, candidate 2430 improves the mean seven-level score by about 0.59 percent,
lower fit MAE by 11.7 percent, median fit MAE by 20.5 percent, and upper fit MAE by 13.7 percent.
Relative to the exact control, its mean score improves by about 0.29 percent and its lower/median fit
is better, while its upper fit is about 3.8 percent worse.

All marginal score intervals overlap. The correct interpretation is a confirmed descriptive mean
improvement under the frozen rule, not formal superiority or predictive equivalence.

## Corrected audit event

The first qualification finalization inherited cheap-screen metric columns and appended fresh
metrics with duplicate CSV headers. The collector selected the first, stale copy. The model fits,
forecast details, compact initializers, and worker manifests were valid. The invalid decision and
its derived sealed plan were moved to:

`superseded_qualification_duplicate_metric_20261126/`

The collector was corrected to retain the fresh final occurrence, downstream plans now strip
upstream metrics, focused tests were extended, and qualification was recomputed from the unchanged
verified workers. No model was rerun for this reporting repair. The corrected result advanced two
challengers instead of one.

## Runtime storage and hashes

Jerez authoritative runtime:

`/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_persistent_tail_v6_tail_calibration_20261126/application/cache/joint_qdesn_persistent_tail_v6_20261126`

Muscat verified mirror:

`/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_persistent_tail_sealed_v5_20261126/application/cache/joint_qdesn_persistent_tail_v6_20261126`

- `transfer_inventory.csv`: SHA-256
  `4cc4642ba26ad58adc9350700cabb687abe1966dac7423b4a70f6a55dd3eeb91`
- inventory verification: 17,374 files, 130,093,649 bytes, zero mismatches
- `v6_health_summary.csv`: SHA-256
  `04a2efbb793e3bf5d4d012f46536eef79722ac320c355a392fc5d4d959fc6486`
- `v6_decision.csv`: SHA-256
  `05be3d8d26ff11690ab400c07ce6c4fd88e33a30426a316bc4aa2afe90adb843`
- `seven_aggregate.csv`: SHA-256
  `6bffdcc83a9f777e3f9cef386cc4c9c0fecf30c513162a218724ff3dee0d09d5`

Runtime remains ignored and must not enter Git or an article snapshot.

## Verification

Completed under pinned R 4.6.0:

- `test_joint_qdesn_persistent_tail_v6.R`: 47 expectations, pass;
- `test_joint_qdesn_persistent_tail_v6_source_guard.R`: 19 checks and 5 mutation rejections, pass;
- inherited V4 focused test: 54 expectations, pass;
- inherited V5 focused test: 34 expectations, pass;
- real disposable V6 component and seven-level smoke fits: pass;
- Jerez production preflight and every stage check: pass;
- `git diff --check`: pass.

## Scientific next action

V6 is complete, but it is not the final multi-model article packet. The confirmed 2430 profile now
justifies one separately frozen continuation for the persistent-heavy-tail scenario:

1. fit the complete independent AL seven-level VB model using the V6 level-specific profiles;
2. initialize the corresponding independent exAL VB model;
3. fit the joint AL and joint exAL VB models without changing the reservoir architecture;
4. initialize fresh matched MCMC confirmations from those VB fits;
5. use exact M0 for every exAL MCMC fit;
6. compare fit, forecast DGP-integrated score, realized aCRPS, crossings, score intervals, and
   functional stability against the current authority;
7. retain V6 only if the complete model-level packet remains favorable.

Scalar mixing is review-level unless fit or forecast functionals are pathological. No article or
integration update is warranted until that continuation is complete. This branch must therefore be
retained as scientific evidence, not merged as an article result yet.

**V6_COMPLETE_CONTINUATION_AUTHORIZED_NOT_READY_FOR_ARTICLE_INTEGRATION**
