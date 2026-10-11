# PriceFM/Q-DESN month-long scientific audit and forward roadmap

Date: 2026-10-11

## Status and decision

This document freezes the scientific interpretation of the PriceFM application
work from the R93 validity repair through the completed R133 driver pilot. It
does not authorize integration, promotion, article changes, registry changes,
or an all-region launch.

The current article authority remains R98. R98 is the valid, prospective,
region-frozen Q-DESN surface over 38 regions and three folds. The later
R101--R133 work is developmental evidence. Its strongest successor result is
the completed R129B two-region pilot, but that pilot is too small and too
historically exposed to replace R98.

The immediate scientific conclusion is:

1. The validity problem that motivated R93--R98 was solved.
2. Recursive forecasting is feasible and correctly implemented, but forecast
   errors in the endogenous price driver remain the dominant bottleneck.
3. Preserving stochastic driver and parameter uncertainty is preferable to
   collapsing either source of uncertainty.
4. Static seasonal substitution, affine calibration, and post-hoc direct
   location/scale maps do not solve the transfer problem.
5. The next expensive step should be a prespecified, representative regional
   transfer panel using the frozen R129B pipeline. It should not be another
   broad DESN search or another post-hoc correction.

Overall status: **NOT READY FOR INTEGRATION**. This is intentional: the lane is
still developing a successor model and the user has explicitly deferred
integration until the scientific task is complete.

## Provenance boundary

- Audit worktree:
  `/data/jaguir26/local/src/Article-Q-DESN/.codex_work/pricefm_month_audit_roadmap_20261011`
- Audit branch: `work/pricefm-month-audit-roadmap-20261011`
- Audit base: `origin/main@1c95187013b6eb9fe04f7c641e90de6afb784337`
- Latest completed scientific branch:
  `work/pricefm-r133-direct-multihorizon-driver-20261011`
- R133 full HEAD: `ae96d21cae994a5bdce4964d85aba1d5df26a8b1`
- R133 state: complete, pushed, clean, no active jobs, not promoted.
- No main, integration, article-snapshot, or Overleaf branch is modified by
  this audit.

The conclusions below use executed frozen outputs, not similarly named plans.
Generated model objects and runtime evidence remain outside Git. Tracked code,
contracts, tests, and this audit remain in dedicated task branches.

## Benchmark hierarchy

The phrase "PriceFM result" has referred to several distinct quantities. They
must not be conflated.

| Benchmark | Mean AQL | Scientific role |
|---|---:|---|
| PriceFM paper full-shot | 5.8000 | Authors' reported result; external context only because the complete exact search is not publicly reconstructible yet. |
| Local public-architecture Phase-I/II replay | 6.009387 | Complete 114-cell validation-only local operational reconstruction; valid locally, but not the authors' exact complete search. |
| Cached released-checkpoint fold-aligned replay | 7.038685 | Current reproducible article comparator on the matched 114 cells. |
| R98 valid Q-DESN authority | 7.217007 | Current Q-DESN article authority. |
| Deprecated R92 Q-DESN | 6.823677 | Numerically attractive but invalid for authority because final forecast outcomes influenced case/fold selection. |

The paper value of 5.80 cannot be used as if it were a locally reproduced
forecast surface. The local 6.009387 replay is a strong secondary comparator,
but it is explicitly labeled as a public-architecture reconstruction. The
cached 7.038685 replay remains the direct operational article reference until
a coordinator-approved authority change occurs.

The PriceFM authors clarified that their full experiment uses a Phase-I model
trained across all regions and a Phase-II validation-only fine-tuning search
for each region and fold. Phase II evaluates 11 graph cutoffs and three seeds
per target region, or 1,254 trials per fold. This confirms that PriceFM shares
parameters across regions before region-specific fine-tuning. It does not
provide the exact winning manifest, complete layer search implementation, or
all checkpoints needed to reproduce 5.80 exactly.

## Model families and scientific roles

| Version | Selection boundary | Readout and inputs | Forecast operator | Inference | Status |
|---|---|---|---|---|---|
| R92 | Case/fold choices partly informed by final forecast outcomes | Mixed legacy specifications | Legacy scoring | Independent AL/exAL VB | Deprecated because selection leaked test information. |
| R98 | Fold-1 training/internal validation and outer validation; one region-level choice frozen across all folds | Final reservoir layer; target-only or graph summaries/graph neighborhood | Frozen legacy application operator | Independent AL/exAL RHS VB | Current valid article authority. |
| R120--R127 BG development | Expanding training-internal splits | Pure all-layer DESN, explicit target/exogenous lags | Recursive H96 with teacher forcing between origins; several predictive summaries diagnosed | Normal ridge/RHS plus independent AL VB | Developmental, not promotable. |
| R128--R129B regional pilot | Three expanding splits inside training; one regional DESN and `tau0` shared across folds and quantiles | Pure readout `[1,h_t^(1),...,h_t^(D)]`; inputs enter the reservoir, not the readout | S500 stochastic Normal RHS price driver, recursive state propagation, clipped pooled-CDF quantiles | Independent AL RHS VB | Strongest successor pilot; complete for HR and DK_1 only. |
| R130 | No refit; temporally held-out gaps | Same frozen R129B receiver | Stochastic, parameter-only, mean-driver, and oracle controls | Same frozen VB fits | Identified the driver/state-input bottleneck. |
| R131 | No refit | Same receiver | Previous-day and previous-week causal drivers | Same frozen VB fits | Both seasonal controls failed. |
| R132 | No receiver refit | Same receiver | Forward-only static stochastic-driver calibration | Same frozen VB fits | Identity selected; no gain. |
| R133 | No receiver refit | Same receiver | Decoupled direct H96 location/scale map selected internally | Same frozen VB fits | Internal gain did not transfer; not promoted. |

No joint Q-DESN, exAL successor, or MCMC PriceFM result is part of the
R128--R133 chain. Those are future model families, not hidden components of
the completed pilot.

## What R98 established

R98 replaced the invalid R92 surface even though R98 has a higher AQL. The
replacement was scientifically necessary because R98 freezes one model family,
DESN, `tau0`, and feature policy per region before the three test folds are
scored.

The frozen registry contains:

- 38 regions and three folds, for 114 complete cases;
- 33 AL cases and 81 exAL cases, corresponding to 11 AL regions and 27 exAL
  regions because family is shared across folds;
- 27 target-only, 27 graph-neighborhood, 42 graph-mean, and 18
  graph-mean-plus-SD cases;
- final-layer readout in all 114 cases;
- one DESN and `tau0` across folds within every region;
- one likelihood family across folds within every region;
- validation-only selection and no test-driven case mixing;
- no joint model and no MCMC model.

R98's mean AQL is 7.217007 versus 7.038685 for the cached PriceFM replay, a
difference of +0.178322. This small aggregate loss is acceptable as the cost
of restoring a valid evaluation. It is not evidence that the search is
finished.

## Why the recursive successor was built

The successor work addressed a mismatch between model training and a genuine
multi-step forecast. At an origin `o`, the DESN input includes known history,
current or forecast exogenous quantities, and lagged prices. Future prices are
unknown. For horizon steps beyond the first, a feasible forecast must replace
unknown target lags with simulated values and advance the reservoir state.

The intended contract is:

```text
u_t = [lagged prices, current exogenous values, lagged exogenous values,
       optional calendar terms]
z_t = [1, h_t^(1), ..., h_t^(D)]
```

Only the first reservoir layer consumes `u_t`; deeper layers consume the
preceding layer according to the DESN definition. The pure readout uses the
intercept and all reservoir layers. It does not add a direct ARX copy of `u_t`.

Within each 96-step origin, S=500 stochastic Normal RHS trajectories supply
the unknown future price lags and generate S recursive reservoir paths. When
the origin moves, the state is teacher-forced with the newly available true
history. Realized future exogenous covariates are used retrospectively and are
declared as such; future target truth is used only by the explicitly labeled
oracle diagnostic.

## Month-long evidence chain

| Stage | Main question | Executed evidence | Conclusion |
|---|---|---|---|
| R93--R98 | Can model selection be made prospective and region-frozen? | 114/114 scored cases and a complete replacement registry. | Yes. R98 is valid authority; R92 is deprecated. |
| R101--R120 | Can recursive H96 forecasting, explicit target/exogenous lags, pure all-layer readouts, and broad DESN search be wired reproducibly? | Recursive engine, contracts, sparse and dense screens, tests, and plans. | Yes operationally; model quality remained unresolved. |
| R122 | Does broad train-only BG screening identify a stable pure-DESN candidate? | 6,720 ridge cells, 348 Normal RHS fits, 63 AL fits. | Candidate frozen, but only in scaled internal units; no promotion. |
| R123 | Were apparent convergence failures genuine? | Fixed-point and full-state stationarity audits. | Some were genuine; some were artifacts of an incomplete convergence rule. Six leaders passed full-state continuation. |
| R124 | Did unconditional covariance jitter alter predictive draws? | Exact covariance-equilibrated replay over 1,302 origin/candidate combinations. | Yes, the sampler was mathematically repaired, but rankings and AQL changed negligibly. |
| R125 | Which predictive estimand/operator is defensible? | Three candidates, three splits, 12 origins per cell, S500/H96, ten operators. | CDF pooling is coherent; oracle shows substantial headroom; internal scores cannot be compared directly with official EUR/MWh AQL. |
| R126 | Does the BG model improve on matched official folds? | 24 fits, 365 official origins, no test selection. | AQL 9.4885 versus R98 9.6595, but worse than cached PriceFM 8.5398 and local PriceFM 7.3380. |
| R127 | Is recursion itself hopeless, or is the feasible driver poor? | Same-fit feasible and oracle controls. | Oracle AQL 3.9151/3.6254/6.7705 by fold versus feasible 10.3312/8.1284/10.0058. Driver/state input error is material. |
| R128--R129B | Does the repaired regional workflow transfer to weak and strong regions? | 120 Normal fits, 36 outward AL fits, six reused medians, 64 forecast batches. | Two-region mean 9.0354 beats R98 10.2557 and narrowly beats cached PriceFM 9.0704, but loses badly to local PriceFM 6.5487. HR improves; DK_1 worsens. |
| R130 | Which uncertainty component matters? | 288 held-out validation-gap origins with stochastic, parameter-only, mean-driver, and oracle controls. | Stochastic propagation is best feasible control; collapsing driver or parameter uncertainty worsens AQL. Oracle reduces AQL by about 69% in HR and 75% in DK_1. |
| R131 | Can simple daily or weekly seasonal target substitution repair the driver? | Same-fit held-out controls. | No. Both are materially worse in every fold. |
| R132 | Can static forward calibration repair the stochastic driver? | 18 internal and 120 held-out tasks. | No. Identity is selected in both regions. |
| R133 | Can a post-hoc direct H96 location/scale map transfer? | 6 internal and 120 held-out tasks, 0 failures. | No. HR worsens 9.0983 to 9.7711; DK_1 worsens 9.2364 to 9.2712. |

## Numerical and inferential corrections already settled

### RHS global-scale update

The audited Normal RHS block excludes the intercept from shrinkage. With
`d = p - 1` shrunk coefficients and the project's half-Cauchy inverse-gamma
auxiliary representation, the conditional shape is `(d + 1) / 2 = p / 2`.
The executed successor implementation uses that form. This issue does not
invalidate R128--R133.

### Initialization versus prior

Ridge, Normal RHS, median AL, and adjacent quantile fits provide warm starts.
They do not redefine prior centers or fixed hyperparameters. `tau0` is selected
inside training and then frozen. The R123 audit found no evidence that warm
starts changed the destination posterior target.

### Convergence

Coefficient-only convergence was insufficient. The corrected audit checks the
same-state coordinate equations and all relevant variational blocks after any
warm-up release. This changed certification labels, not the mathematical
model. R129B completed the outward AL surface with independent stationarity
certificates rather than trusting raw package flags alone.

### Predictive covariance

The legacy draw path used an unconditional jitter in the covariance and thus
sampled from `N(m,V+jI)`. R124 replaced it with covariance-equilibrated
Cholesky sampling from `N(m,V)`. The correction was mandatory, but its tiny AQL
effect showed that it was not the source of poor forecasting.

## What the results mean

### Promising evidence

- The R129B two-region mean is 11.9% better than the matched R98 mean and 0.39%
  better than the cached PriceFM mean for those same two regions.
- HR, the worst R98 region relative to PriceFM, improves substantially.
- Oracle controls show that the receiver can produce much better forecasts
  when the future endogenous input path is accurate.
- Path-specific and mean-feature operators are nearly identical in the tested
  setting, so the faster mean-feature calculation is a reasonable engineering
  option when it reproduces the frozen estimand.

### Limits

- Two deliberately chosen development regions do not establish all-region
  superiority.
- DK_1 deteriorates, so transfer is heterogeneous.
- The two-region result only narrowly beats the cached checkpoint and remains
  far behind the local operational PriceFM reconstruction.
- Official windows have been inspected repeatedly. These are retrospective
  development results, not a fresh confirmatory test.
- VB undercoverage is visible, but MCMC is not the next priority because the
  central AQL problem is already large and the oracle gap points to the driver.
- No evidence supports spending compute on exAL, joint fitting, or MCMC before
  the feasible driver/receiver design is stabilized.

## Directions closed by evidence

The following should not be repeated without a genuinely new hypothesis:

- test-driven case-by-case promotion like R92;
- blanket increases in VB iteration caps;
- more covariance jitter or ad hoc precision repair;
- mean-driver or parameter-only collapse as the primary forecast;
- previous-day or previous-week target substitution;
- static affine stochastic-driver calibration;
- post-hoc direct location/scale maps of the R133 type;
- choosing path versus mean-feature propagation from final test performance;
- expanding R133 to more regions;
- an immediate 38-region all-family AL/exAL/joint/MCMC launch.

## Forward scientific plan

### Stage 1: freeze a representative transfer panel

Use a fixed developmental panel selected once from the already exposed R98
strata, then never modify it in response to successor scores. The recommended
six-region panel is:

- `HR`, `SK`, and `HU`: the three largest R98 deficits relative to cached
  PriceFM;
- `DK_1` and `EE`: two regions where R98 substantially beats cached PriceFM;
- `FI`: a Nordic region with a moderate R98 deficit.

HR and DK_1 are reused, not refitted unless a source-hash or contract mismatch
requires it. The other four regions test geographic and performance transfer.
Because panel membership uses previously observed R98 results, the panel is
developmental and cannot create a new pristine confirmatory claim.

### Stage 2: run only the frozen R129B pipeline

For each new region:

1. Use expanding rolling-origin validation entirely inside training.
2. Teacher-force between origins and recursively forecast H96 within origins.
3. Select the DESN and `tau0` with Normal ridge followed by certified Normal
   RHS VB; never use official test AQL for selection.
4. Freeze one regional DESN, `tau0`, graph/exogenous policy, and forecast
   operator across all folds and quantiles.
5. Fit seven independent AL RHS VB quantiles by the certified nested warm-start
   ladder.
6. Generate S500 stochastic Normal RHS target-driver paths and propagate the
   reservoir recursively.
7. Use the already fixed clipped pooled-CDF output and report mean-feature as
   a computational sensitivity only.

Do not add exAL, joint VB, MCMC, direct readout inputs, or post-hoc calibration
in this stage. Holding the receiver contract fixed is necessary to learn
whether the R129B gain transfers.

### Stage 3: paired diagnosis without test-driven retuning

On temporally held-out validation gaps, produce stochastic and oracle controls
from the same fitted receiver. Measure AQL by early/middle/late horizon,
driver MAE and bias, coverage, width, crossings, and region/fold heterogeneity.
Oracle output is diagnostic only and cannot select a promotable specification.

The final official fold comparison must report, on identical rows and units:

- successor Q-DESN;
- R98 Q-DESN;
- cached released-checkpoint PriceFM;
- local operational Phase-I/II PriceFM as a separately labeled comparator.

### Stage 4: prespecified decision gate

The scientific decision is aggregate, not a requirement that every fold beat
both comparators. Use equal region and equal fold weights.

Advance beyond the six-region panel only if all of the following hold:

1. The complete panel has no missing region/fold/quantile outputs.
2. The aggregate successor AQL improves on R98.
3. The aggregate successor AQL is competitive with the cached PriceFM replay;
   exact equality or a tiny difference should be described, not overclaimed.
4. Degradation is not concentrated catastrophically in a geographic group or
   one fold; all heterogeneity is reported.
5. The result is unchanged under the frozen source and metric replay.
6. Selection logs prove that official outcomes did not alter candidates.

Failure of this gate leaves R98 unchanged and stops an all-region launch.

### Stage 5: only then test a new driver architecture

If the panel confirms a large feasible-versus-oracle gap, the next model should
be a genuinely trained direct multi-horizon stochastic Normal driver. It must
be trained against H96 trajectories over multiple forward internal regimes,
not fitted as a post-hoc location/scale map. Keep the quantile receiver frozen
for the first driver experiment so that the causal effect of the driver can be
identified.

The direct driver should produce coherent stochastic trajectories, preserve
within-path parameter dependence, condition only on information available at
the origin plus declared future exogenous forecasts, and be selected solely by
nested forward validation. A small preregistered architecture family is
preferable to another very broad search.

### Stage 6: all-region launch and later model families

Only a passing transfer-panel result justifies scaling the frozen workflow to
all 38 regions. Promotion is based on the complete equal-region/equal-fold
surface, never on selectively retaining winning cases.

After the independent AL recursive authority is stable, later stages may test:

- exAL with the certified structured/M0 scale update;
- a joint seven-quantile model initialized from the independent fits;
- MCMC confirmation for a bounded subset or the final selected model.

Those stages answer different questions and must not be mixed into the current
driver-transfer experiment.

## Reproducibility requirements for the next stage

Before launch, freeze:

- source branch, full commit, dynamic source hashes, environment, and exact
  CRAN `exdqlm` 1.1.1 APIs;
- region panel and reason for inclusion;
- train/internal-validation/official-test timestamps and timezone conventions;
- complete candidate manifest, seeds, S500/H96 forecast contract, graph and
  future-exogenous policy;
- one numerical thread per worker and a bounded physical-core scheduler;
- completion sentinels, heartbeats, failure records, and resumable task IDs;
- metric definitions and equal-region/equal-fold aggregation;
- explicit prohibitions on registry, article, main, and Overleaf mutation.

Retain compact manifests, metrics, certificates, and hashes. Keep model
objects, predictions, traces, logs, and PDFs under ignored runtime paths. Do
not delete frozen authority or the minimal dependencies needed to replay it.

## Evidence ledger

| Evidence | SHA-256 |
|---|---|
| R98 `summary.json` | `149b582f880cf970b3fea39b5b0d0001035386a845be259dca6709e15fc8a9f6` |
| R98 authoritative registry | `4cf8ff653c6bd7fc64a2992fbfb6e1df48867d1b7d840cd8544fb30a5c538cb6` |
| R120 master plan | `1fe1b3c1e3436d47a2fd7ef204603d002567bd0b61015279562ed651148e05fd` |
| R124 frozen handoff | `3232848498f5bfc9d916d6b72e42975840c39771c683cad2de7c73c6589fa6b6` |
| R125 diagnosis | `5665d3a4e1e5c2bbb17281608150e9d3805b3330a73958686bba7b01fdca2b38` |
| R126 decision | `22a15b9bcbc33c0eea34d7f50768ca07787b8245403e33d4b0a7b9f98d440203` |
| R127 decision | `3bfe03bfb48fb580712ec8c4278509dd126a548f6b9098003a6dd7ac07eceb53` |
| R130 scientific note | `ac5f94413ee2827ca0c636da7c530308b6ea04cb3a23404d538c0d6157412968` |
| R133 frozen handoff | `1a73f05defbf2852a1c2038286d24e3fe7b5eeca976233fc180c7feac87b3ca5` |

## Final interpretation

The last month did not merely generate many model versions. It established a
clean sequence of scientific results:

- R98 made the comparison valid.
- R124 made predictive sampling mathematically correct.
- R125--R127 defined the forecast estimand and located the dominant error.
- R128--R129B showed that the new regional pipeline can be competitive on a
  small mixed-strength cohort.
- R130 showed why uncertainty must remain stochastic.
- R131--R133 eliminated three tempting but inadequate shortcuts.

The task should therefore continue, but it should continue narrowly. The next
question is whether the frozen R129B workflow transfers across a prespecified
six-region panel. Until that question is answered, R98 remains authoritative,
R129B remains promising developmental evidence, and no integration or article
promotion is scientifically justified.
