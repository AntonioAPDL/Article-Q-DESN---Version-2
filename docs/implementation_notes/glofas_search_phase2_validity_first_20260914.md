# GloFAS Search Phase II: Validity-First Normal Ridge and RHS/VB Plan

Date: 2026-09-14
Lane: `work/glofas-search-phase2-20260914`
Status: implementation and benchmark gate complete; the broad Ridge stage is
authorized but remains a separate launch. No Phase II candidate is
authoritative until every declared selection gate passes.

## 1. Decision and scope

Search Phase II is scientifically feasible and worth running, but only as a
new, sealed validation campaign. It is not valid to tune another architecture
against the already inspected 30-day window after 2022-12-25. The existing
Phase I GloFAS result therefore remains authoritative while this campaign uses
earlier pseudo-origins to ask a narrower question:

> Can a richer, better calibrated DESN specification improve recursive
> 28/30-day reference or discrepancy forecasts while retaining historical fit?

The campaign covers the two reusable univariate components only:

1. USGS reference response on `log1p` scale.
2. Historical discrepancy, `log1p(GloFAS) - log1p(USGS)`.

It does not rerun the Part 3 or Part 4 quantile families, change article files,
or promote a result. A Phase II component can enter those models only after it
passes the multi-origin, multi-seed gates below.

## 2. Audit conclusions that determine the design

| Finding | Evidence and interpretation | Consequence |
| --- | --- | --- |
| Ridge is useful but not a reliable final ranker | Prior Part 1 Ridge/RHS ranks had approximately Pearson 0.091 and Spearman 0.224; Part 2 was approximately Pearson 0.026 and Spearman 0.008 | Ridge removes poor regions and supplies exact-design warm starts; RHS scores choose RHS candidates |
| Raw `tau0` sweeps were weak | Prior local `tau0` changes produced practically equivalent scores in the winning basin | Replace a large raw grid with dimension/sample-size calibrated sparsity targets plus one legacy anchor |
| Very large/deep designs were not consistently better | Phase I explored widths through 5,000 and several deep designs without a monotone gain | Retain broad width/depth support, but use deterministic space filling and require cross-fold robustness |
| DLM augmentation did not improve the selected univariate model | The augmented challenger failed to beat the plain winner | Do not spend Phase II budget on DLM inputs |
| Extra cross-component inputs hurt Part 3 | The Normal cross-input challenger worsened every primary CRPS target and exhibited high saturation | Keep reference and discrepancy input contracts separate in Phase II |
| The discrepancy input contract mattered | Discrepancy lags plus realized PPT/soil won; broad cross inputs did not | Preserve discrepancy lags 1:`y_lag_max` and PPT/soil lags 0:`covariate_lag_max` |
| State conditioning remains a plausible bottleneck | Earlier diagnostics showed high saturation and low effective rank in some challengers | Vary sparsity/input gain and test train-only state standardization; record state diagnostics |
| The final 2022-12-25 window has already been inspected | It has been repeatedly plotted and compared | It cannot be a tuning set; any eventual use is confirmation with an explicit non-pristine label |

These findings reject three tempting but inefficient alternatives: another
full Cartesian sweep, selecting the top RHS model solely from Ridge rank, and
tuning directly on the final article forecast window.

## 3. Sealed temporal validation contract

The primary score is recursive Normal CRPS over days 1-28. Days 29-30 are a
secondary horizon because the article's issued GloFAS ensemble ends at day 28,
although this Normal component screen uses realized PRISM/ERA5 covariates for
all 30 days. Every result is explicitly labelled oracle-covariate diagnostic,
not operational forecast performance.

| Fold | Origin | Primary scoring | Secondary extension |
| --- | --- | --- | --- |
| `fold_2018_12_25` | 2018-12-25 | 2018-12-26 to 2019-01-22 | through 2019-01-24 |
| `fold_2019_12_25` | 2019-12-25 | 2019-12-26 to 2020-01-22 | through 2020-01-24 |
| `fold_2020_12_25` | 2020-12-25 | 2020-12-26 to 2021-01-22 | through 2021-01-24 |
| `fold_2021_11_12` | 2021-11-12 | 2021-11-13 to 2021-12-10 | through 2021-12-12 |
| `fold_2021_12_21` | 2021-12-21 | 2021-12-22 to 2022-01-18 | through 2022-01-20 |
| `fold_2022_05_11` | 2022-05-11 | 2022-05-12 to 2022-06-08 | through 2022-06-10 |

The windows do not overlap. The 2021-01-23 GloFAS v2.1 bundle is excluded from
the primary campaign because it changes retrospective product; it can be used
later as a labelled product-shift stress test.

### Leakage boundary

Preparation writes two physically separate artifacts per target/fold:

- model packet: history through the origin plus realized future PPT/soil;
- scoring packet: future USGS or future retrospective discrepancy truth.

The model worker knows only the model-packet path. It must write a recursive
forecast and a `.model_done` marker before the scoring process can resolve the
scoring packet. Packet hashes and the final-origin exclusion are checked at
runtime. Future response truth is never used for fitting, initialization,
state construction, or recursive lag replacement.

## 4. Candidate space

### Reference component

| Axis | Support |
| --- | --- |
| Geometry | D1 widths 1,500, 2,500, 3,000, 4,000, 5,000; D2 totals 3,000 and 5,000 |
| Output lags | 180, 360, 540 |
| PPT/soil lags | 90, 180, 360 |
| `alpha` | 0.40, 0.50, 0.60, 0.75 |
| `rho` | 0.60, 0.75, 0.90, 0.99 |

### Discrepancy component

| Axis | Support |
| --- | --- |
| Geometry | D1 widths 1,500, 2,000, 2,500, 3,000, 4,000; D2 totals 2,500 and 4,000 |
| Output/discrepancy lags | 180, 360, 540 |
| PPT/soil lags | 90, 180, 360 |
| `alpha` | 0.60, 0.70, 0.80, 0.90, 0.95 |
| `rho` | 0.30, 0.50, 0.70, 0.85, 0.95 |

Both components also vary recurrent sparsity `pi_w` over
`0.005, 0.01, 0.03, 0.10`, input sparsity `pi_in` over `0.10, 0.30, 1.00`, and
effective input gain over `0.50, 1.00, 2.00, 3.00, 4.84`. The actual input
scale is normalized for input dimension and sparsity:

```text
win_scale_global = effective_input_gain / sqrt(pi_in * m_input)
m_input = y_lag_max + 2 * (covariate_lag_max + 1)
```

This avoids confounding a longer input vector with a mechanically larger total
input variance. The legacy `win_scale_global=0.18` winner remains an exact
anchor. All new candidates use train-only readout-state z-scaling; the exact
unscaled Phase I anchor is retained to measure the change rather than assume it
helps.

The full support is not executed as a Cartesian grid. Sixty-four deterministic
maximin candidates per target cover it, followed by the legacy anchor, a
standardized anchor, and Ridge variance pilots at `1, 10, 100, 10000`. The
default manifest has 69 unique architectures per target and 828 Ridge
candidate-fold fits.

## 5. RHS prior calibration

For standardized non-intercept predictors, calibrated RHS global scales use
the existing Piironen-Vehtari-style application formula:

```text
tau0 = m0 / (p - 1 - m0) * sigma_reference / sqrt(n_fit)
```

The pilot tests `m0 = 25, 100, 300`, learned slab scale, and two fixed-slab
sentinels at `m0=100`, `zeta2=4` and `zeta2=16`. The Phase I raw `tau0` is kept
as a legacy anchor. This design separates expected model size from feature
dimension, which raw `tau0` could not do when widths ranged from 1,500 to 5,000.

The fixed-slab option is implemented as a genuine point-fixed hyperparameter:
its update and variational entropy terms are omitted. It is not treated as a
degenerate inverse-gamma update.

## 6. Execution stages and gates

| Stage | Work | Gate to continue |
| --- | --- | --- |
| 0. Implementation tests | packet sealing, recursion, scaling equivalence, fixed slab, freeze optimization, scheduler | All focused tests and `git diff --check` pass |
| 1. Benchmark | Phase I standardized reference/discrepancy anchors under Ridge and legacy RHS on one fold | 4/4 complete; zero failures; C++/R forecast equivalence; measured memory and runtime support chosen capacity |
| 2. Ridge screen | 69 architectures x 6 folds x 2 targets | Complete-fold results only; finite forecasts; no severe diagnostic reject at the prospectively declared thresholds; no historical guardrail failure |
| 3. RHS prior pilot | Phase I anchor, Ridge top 2, and 1 maximin/diverse architecture per target x 6 prior specs x 6 folds | Choose a prior prospectively by mean day-1:28 CRPS, then worst-fold CRPS |
| 4. RHS architecture screen | Phase I anchor, Ridge top 8, and 11 maximin/diverse candidates per target x 6 folds | Use RHS scores, not Ridge rank; reused pilot cells are not refit |
| 5. Seed confirmation | Top 3 per target across the fixed original seed plus 3 declared seeds x 6 folds | Select robust mean/worst-seed candidate; never select the best seed realization |
| 6. Final refit decision | Freeze component specifications and refit through 2022-12-25 only after selection | No tuning after final refit; downstream Part 3/4 rerun requires separate approval |

The frozen evaluation workload is 828 Ridge candidate-fold fits, 288 RHS
prior-pilot fits, 240 RHS architecture evaluations, and 144 seed-confirmation
evaluations. The architecture screen reuses the 48 exact pilot cells shared by
its eight pilot architectures and six folds, so it requires 192 new fits. Seed
confirmation reuses the 36 exact original-seed cells for six finalists and six
folds, so it requires 108 new fits. The three RHS stages therefore require 588
new fits rather than 672, with every reused artifact verified by SHA256.
Stages are prepared only after the preceding aggregate table passes its gate;
they are not one monolithic launch.

Within scores equal at four decimals, the tie-break order is: historical
guardrail, worst-fold CRPS, lower state saturation/better rank, lower runtime,
then smaller state dimension. This follows the user's declared rule that score
differences beyond four decimal places are noise.

## 7. Historical-fit guardrails

Every worker records all-history and trailing 1,000/200/50 MAE, RMSE, and
residual-scale plugin CRPS. Candidate comparisons use the matching Phase I
anchor on the same folds. A candidate is not promotable if its mean historical
RMSE degrades by more than 1 percent or its trailing-200 RMSE degrades by more
than 3 percent unless that exception is declared before looking at the final
window. These thresholds are campaign rules, not post-result adjustments.

The checker enforces these rules in `promotion_eligible`; it also requires all
folds, finite scores, successful fit convergence, finite state diagnostics, and
no severe diagnostic rejection. The exact Phase I legacy architecture is
reserved in every RHS pilot and screen so each target/prior has an internal
same-fold guardrail baseline. Confirmation candidates inherit eligibility from
the completed RHS screen.

## 8. Diagnostics and computational safeguards

Each candidate records finite-state status, dead and saturated fractions,
near-duplicate fraction, effective rank, and conditioning on a deterministic
2,000-row/256-feature diagnostic sample. Full-matrix correlation diagnostics
would add large memory cost without changing the screening decision. Because
the retained Phase I reservoirs themselves can exceed the generic 30 percent
saturation threshold, this campaign declares 30 percent as a warning and 60
percent as rejection before screening; non-finite states remain an immediate
rejection.

The Normal RHS implementation now:

- skips the Cholesky solve and inverse entirely during frozen-beta iterations;
- avoids materializing an extra `p x p` beta outer product for the expected SSE;
- records `beta_solve_performed` in every trace row;
- supports a 20-iteration beta freeze and requires at least 30 actual beta
  updates before convergence;
- supports fixed or learned slab variance;
- retains exact train-only scaling transformations for R and C++ recursive
  forecast equivalence.

Every completed Ridge job also writes a compact, hashed warm start. RHS pilot
and architecture manifests refuse to prepare if the matching candidate/fold
warm start is absent or later fails its hash/design-column check. During the
six-prior pilot, jobs sharing an architecture and fold execute as one
one-thread group: the reservoir design is built once, the retained Ridge
initializer is loaded once, and the six RHS fits remain separate scored jobs.
Retained warm starts remove all 288 repeated Ridge solves from the pilot, while
grouping removes 240 redundant reservoir-design builds, without coupling
priors or changing any posterior update.

The scheduler pins every model to one numerical thread and uses weighted
capacity slots: width at most 2,500 has weight 1, 2,501-4,000 has weight 2, and
larger models have weight 3. A high core count therefore cannot accidentally
launch too many 5,000-state models at once.

## 9. Reproducibility surface

| Surface | File |
| --- | --- |
| Fold contract | `application/config/glofas_search_phase2_folds_20260914.csv` |
| Scientific/search helpers | `application/R/glofas_search_phase2.R` |
| Base preparation | `application/scripts/395_prepare_glofas_search_phase2.R` |
| Model-only worker | `application/scripts/396_run_glofas_search_phase2_worker.R` |
| Sealed scorer | `application/scripts/397_score_glofas_search_phase2.R` |
| Health/aggregation | `application/scripts/398_check_glofas_search_phase2.R` |
| Capacity-aware launcher | `application/scripts/399_launch_glofas_search_phase2.py` |
| RHS pilot/screen/confirmation preparation | `application/scripts/400_prepare_glofas_search_phase2_rhs.R` |
| Grouped RHS prior-pilot worker | `application/scripts/401_run_glofas_search_phase2_rhs_group.R` |
| Focused tests | `application/tests/test_glofas_search_phase2.R` |

Runtime artifacts remain under ignored `local_trackers/runtime_configs/`.
Tracked code, fold metadata, and this document are the reproducibility surface.
Run manifests include Git HEAD, source paths/hashes, candidate and packet
manifests, session information, and exact scientific contracts.

Workers retain forecast paths, score details, ELBO traces, top-50 coefficients
by posterior mean magnitude, and block-level coefficient activity. Full model
objects and full coefficient tables are intentionally omitted because they are
rebuildable and would multiply storage across more than one thousand fits.

### Required launch order

Each stage uses a new ignored runtime root and runs its checker before the next
preparer is called:

```text
395 --mode benchmark -> 399 -> 398
395 --mode ridge     -> 399 -> 398
400 --mode pilot     -> 399 --group-rhs-design -> 398
400 --mode screen    -> 399 -> 398
400 --mode confirm   -> 399 -> 398
```

The Ridge runtime root is passed to both RHS preparation stages; the pilot
runtime is additionally passed to the screen so completed matching cells can
be reused. The completed screen runtime is passed to confirmation. A
preparation or launch command must never be substituted for a failed checker,
and no later stage is pre-scheduled before its predecessor's scientific gate
has been reviewed.

## 10. What is and is not optimal

This is the best justified next search given current evidence because it
directly measures the desired recursive forecast behavior, preserves a
historical-fit constraint, calibrates shrinkage across feature dimensions, and
spends expensive RHS fits only after broad Ridge coverage. It is not a proof
that the globally optimal DESN lies in the declared support. Its validity rests
on freezing this support and these gates before results are inspected.

Do not expand the grid, alter thresholds, add folds, or inspect 2022-12-25 to
rescue a disappointing result. A later expansion would be a separately named
campaign with a new validation budget. A genuinely independent future cutoff,
if acquired, is the strongest eventual confirmation evidence.

## 11. Benchmark closeout

The one-fold standardized-anchor benchmark completed 4/4 model fits and sealed
scores with zero final failures. Observed one-thread results were:

| Target | Method | Runtime (seconds) | Day-1:28 CRPS |
| --- | --- | ---: | ---: |
| Discrepancy | Ridge | 296.52 | 0.1978248 |
| Discrepancy | RHS | 594.65 | 0.2067242 |
| Reference | Ridge | 417.44 | 0.3711828 |
| Reference | RHS | 898.20 | 0.3399309 |

Observed resident memory stayed below approximately 3.3 GiB per job. These
single-fold scores are not model-selection evidence; they only validate the
execution envelope. Four initial scorer invocations overlapped an in-progress
source edit and failed at parse time after their forecasts were already safely
written. Their failure markers were preserved, and the sealed scorer was rerun
successfully without refitting. No scientific value changed. Future production
jobs must run only from a clean committed worktree, which the launcher handoff
now requires.
