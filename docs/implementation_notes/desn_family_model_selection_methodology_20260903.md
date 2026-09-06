# DESN Family Model-Selection Methodology

Date: 2026-09-03
Lane: GloFAS scientific lane, prepared for coordinator review
Status: methodology contract and implementation audit; no manuscript claims changed

## Purpose

This note defines the model-selection methodology we should use across the
article's DESN workflows. It is intentionally broader than the current GloFAS
screen, but it is grounded in the implementation surfaces that already exist in
the repository and in the package-oriented Normal-DESN work.

The goal is to make DESN specification search reproducible, comparable, and
efficient. The central idea is a staged ladder:

1. use cheap Normal-DESN screens to remove bad reservoir regions and identify
   promising geometry, memory, and dynamics;
2. use Normal RHS VB to check whether those regions survive global-local
   shrinkage and to learn better initialization states;
3. use the Normal winners to initialize and localize independent quantile
   AL/exAL RHS VB searches;
4. promote a candidate to all target quantiles only after the focal quantile and
   guardrails pass;
5. use joint quantile AL/exAL VB, and where needed MCMC, only after the
   independent candidates are already defensible.

The ladder is a workflow tool. It does not claim that a Normal fit and a
quantile fit optimize the same target. Normal ridge is exact and fast, but it is
only a screening and initialization device. The quantile likelihood, and later
the joint quantile likelihood, remain the scientific target for final article
claims.

## Scope

This note covers three article workstreams:

| Workstream | Included scope | Excluded scope |
|---|---|---|
| GloFAS application | USGS-only screening, observed-discrepancy screening, historical USGS/GloFAS bridge, forecast-ensemble synthesis | Unrelated validation scripts, PriceFM runs, joint simulation runtime artifacts |
| PriceFM application | Price-series graphical input selection and AL/exAL quantile model selection | GloFAS-specific discrepancy mechanics |
| Joint Q-DESN evaluation | Joint simulation/evaluation work with VB and MCMC confirmation | The separate individual-quantile simulation study |

The individual-quantile simulation study is deliberately excluded because it is
serving a different article role: a controlled benchmark of the single-quantile
method rather than the staged cross-family selection workflow described here.

## Implementation Audit

The audit found several relevant implementation layers.

| Layer | Current status | Main evidence | Methodology implication |
|---|---|---|---|
| Package-style Normal DESN | Exists in the exdqlm development worktree with `normal_desn_fit()`, `qdesn_fit_normal()`, posterior draws, forecasts, and Normal-to-Q-DESN warm starts | `R/qdesn_normal.R`, `R/qdesn_normal_warm_start.R`, `tests/testthat/test-qdesn-normal.R` in `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0` | Prefer adapting or porting the audited package API over inventing a second generic API |
| GloFAS Normal-DESN Part 1 | Implemented in the article lane for USGS-only Normal ridge and Normal RHS VB with ridge warm starts, scores, ELBO traces, coefficient summaries, DLM augmentation hooks, and fit figures | `application/R/glofas_normal_desn_part1_screening.R`; tests in `application/tests/test_glofas_normal_desn_part1_screening.R` | Valid as the current application-specific engine for GloFAS Part 1 |
| GloFAS Normal-DESN Part 2 | Implemented as an intermediate historical bridge that fits the observed discrepancy and scores the implied corrected USGS path; it is not yet the final joint historical model | `application/R/glofas_normal_desn_part2_bridge.R`; tests in `application/tests/test_glofas_normal_desn_part2_bridge.R` | Correctly supports discrepancy-input screening before the final joint model |
| GloFAS structural DLM extension | Implemented with a C++ Kalman backend and R wrappers for level, seasonal, transfer, readout-covariate, fitted-mean, and residual components | `application/R/glofas_structural_normal_dlm.R`; `application/src/glofas_structural_normal_dlm_kalman.cpp`; tests in `application/tests/test_glofas_structural_normal_dlm.R` | C++ is already used where it materially helps the state-space filter/smoother |
| GloFAS oracle forecast adapter | Implemented for Part 1 Normal-DESN, with plug-in mean recursion and posterior draw-recursive forecasting using realized future ppt/soil covariates | `application/R/glofas_normal_oracle_forecast.R`; tests in `application/tests/test_glofas_normal_oracle_forecast.R` | Useful diagnostic forecast surface, but it must be labelled oracle and not operational |
| PriceFM model-selection bridge | Implemented as a PriceFM-specific bridge/registry adapter, not a replacement for the package model selector | `docs/implementation_notes/pricefm_qdesn_model_selection_bridge_20260606.md`; PriceFM tests and scripts | PriceFM should use the same ladder but keep its horizon/fold registry contract |
| Joint evaluation AL/exAL VB/MCMC | Implemented for joint Q-DESN evaluation with VB, MCMC, ELBO/objective accounting, and VB-initialized chains in the joint lane | `application/R/joint_qvp_qdesn.R`; `docs/implementation_notes/joint_exal_qvp_qdesn_rhs_derivation_checklist_20260701.md` | MCMC confirmation belongs here because the simulation setting has truth and calibration targets |

The main architectural gap is not the absence of Normal ridge/RHS machinery. The
gap is that the reusable Normal-DESN pieces are split between package-style
code and GloFAS-specific wrappers. A cross-lane extraction should be done
deliberately by coordinator integration after each scientific lane is stable.
It should not be improvised inside a running GloFAS screening worktree.

## Common Selection Contract

Every candidate should be represented by a manifest row before it is fit. The
row must be sufficiently complete to rebuild the design and understand the
selection decision without reading transient worker logs.

Required fields:

| Field group | Required information |
|---|---|
| Identity | run label, candidate id, lane, stage, model family, date, branch, commit, upstream |
| Data contract | input manifest path and hashes, train/validation/test or cutoff windows, transformation, leakage policy |
| Reservoir geometry | `D`, `n`, `n_tilde`, `m`, output lags, covariate lags, auxiliary lags, washout |
| Reservoir dynamics | `alpha`, `rho`, `pi_w`, `pi_in`, input scaling, bias scaling, activation, reducer, seeds |
| Readout contract | intercept policy, whether direct inputs appear in the readout, feature blocks, column hashes |
| Prior contract | ridge scale or RHS `tau0`, slab scale, `a_zeta`, `b_zeta`, intercept handling |
| Inference contract | likelihood, VB/MCMC mode, max/min iterations, tolerances, sampling controls, warm-start source |
| Scoring contract | primary metric, secondary metrics, guardrails, practical equivalence threshold |
| Artifact contract | status files, logs, score tables, figure paths, retained object policy, cleanup eligibility |

For two-block or joint models, reference and discrepancy components must carry
separate reservoir and RHS metadata even when their numerical specifications are
identical. That avoids confusing "same specification" with "same realized
random reservoir."

## Common Diagnostics

Every nontrivial candidate screen should write compact diagnostics:

| Diagnostic block | Required checks | Reason |
|---|---|---|
| Reservoir validity | finite states, empirical forgetting, spectral radius, leaky-effective radius, dead/saturated fractions | Prevent comparing contaminated or degenerate state maps |
| Design quality | state rank, conditioning, duplicate/correlation fractions, design hash, feature-name hash | Distinguish statistical failure from design construction failure |
| Fit quality | primary score, MAE/RMSE/check loss/AQL when relevant, coefficient summaries, posterior scale summaries | Explain why a candidate wins or fails |
| VB quality | ELBO or accounted-objective trace, iteration count, final delta, convergence flag, numerical repair flags | Detect candidates that score well only because optimization failed oddly |
| Forecast quality | horizon-wise scores, recursive-input audit, future-source policy, oracle/operational label | Prevent leakage and separate diagnostic forecasts from deployable forecasts |
| Artifact hygiene | terminal markers, retained object list, manifest hashes, cleanup decision | Keep the server healthy without destroying reproducibility |

The practical comparison rule should be declared before scoring. For current
GloFAS Normal screens, differences beyond four decimals in mean CRPS should be
treated as noise unless repeated cold fits show otherwise.

## Why The Staged Ladder Is Preferred

### Normal Ridge DESN

Normal ridge is the cheapest useful gate because, conditional on the fixed DESN
design, it has a closed-form Normal-inverse-gamma posterior. It should be used
for broad reservoir search over layer count, state size, memory, lag windows,
`alpha`, and `rho`.

Use it to:

- reject bad regions quickly;
- reveal whether reservoir states can fit the target at all;
- identify promising memory/dynamics clusters;
- produce deterministic beta and scale initializers for VB.

Do not use it to:

- make final quantile claims;
- assume the top ridge row will be the top RHS or AL row;
- replace forecast-window validation under the target model.

Recent GloFAS work showed exactly why this caution matters: ridge is useful for
screening and initialization, but ridge rank was not perfectly predictive of RHS
rank. Once a candidate enters the RHS stage, RHS score and diagnostics dominate
ridge score.

### Normal RHS VB DESN

Normal RHS VB keeps the same Gaussian readout target but replaces simple ridge
shrinkage with a global-local RHS prior. It is the correct second gate when the
main unknown is whether the design contains signal that survives shrinkage, or
whether a different `tau0` makes the reservoir features usable.

Use ridge initializers for:

- beta means;
- beta variances;
- residual scale;
- design hash validation.

Required safeguards:

- finite ELBO/accounted-objective traces;
- minimum iterations for nontrivial fits;
- explicit global-scale update policy;
- coefficient activity summaries by block;
- strict dimension/hash checks for warm starts.

### Independent AL/exAL RHS VB

Independent quantile VB is where the screen first targets the quantile
likelihood. Use the median or another focal quantile first, depending on the
scientific goal, and search locally around the Normal/RHS winners rather than
restarting a blind grid.

For GloFAS, median-first is appropriate when diagnosing historical USGS fit or
discrepancy predictability. For PriceFM and joint evaluation, the focal quantile
can depend on the loss surface and article table being rebuilt.

Promotion to all quantiles should wait until:

- the focal quantile is clearly better or practically tied with a simpler winner;
- historical or validation guardrails are not violated;
- fit figures look scientifically plausible;
- the feature contract and score contract are frozen.

### Joint AL/exAL RHS VB

Joint quantile models are expensive because they introduce cross-quantile
dependence or coherence constraints. They should be fit after the independent
quantile stage has identified a defensible reservoir and prior region.

Use independent VB states to initialize joint VB whenever dimensions and feature
contracts match. If dimensions differ, use only compatible scalar and block
metadata, and mark the fit as cold or partially initialized.

### MCMC Confirmation

MCMC is a confirmation layer, not a broad screening layer. It is most important
for the joint simulation/evaluation work, where there is truth and calibration
can be assessed. MCMC can also be useful for final article-critical application
models, but only after VB has narrowed the candidate family.

For the joint evaluation lane, the expected final confirmation is:

```text
Normal ridge
Normal RHS VB
independent AL RHS VB
independent exAL RHS VB
joint AL RHS VB
joint exAL RHS VB
then MCMC for the last four quantile model classes, initialized from VB
```

## GloFAS Workflow

The GloFAS application should move through four stages.

### GloFAS Deliverable Ladder

The GloFAS lane should treat the following deliverables as the complete target
surface. This makes the staged logic explicit: each simpler model is useful
only if it either becomes a defensible diagnostic result or provides a
validated initializer/specification for the next, more article-facing model.

| Stage | Scientific target | Required model deliverables | Required forecast deliverables | Promotion role |
|---|---|---|---|---|
| G1. Univariate USGS | Learn the observed USGS dynamics through the cutoff without using retrospective GloFAS or forecast ensembles. | Best Normal ridge; best Normal RHS VB initialized from ridge; best independent Q-DESN AL RHS VB; best independent Q-DESN exAL RHS VB; if promoted, all seven quantiles for AL and exAL at `0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95`; best joint-quantile AL RHS VB and exAL RHS VB across those quantiles. | Forecasts for the winning Normal ridge, Normal RHS VB, independent AL/exAL seven-quantile fits, and joint AL/exAL seven-quantile fits, with the future covariate source labelled as oracle/retrospective or operational. | Supplies the reference/USGS DESN geometry, memory, lag, dynamics, prior, and warm-start states for later GloFAS bridge models. |
| G2. Univariate observed discrepancy | Learn the historical discrepancy `d_t = g_t - y_t` through the cutoff and test whether the discrepancy path contains learnable dynamic signal. | Best Normal ridge; best Normal RHS VB initialized from ridge; best independent Q-DESN AL RHS VB; best independent Q-DESN exAL RHS VB; if promoted, all seven quantiles for AL and exAL at `0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95`; best joint-quantile AL RHS VB and exAL RHS VB across those quantiles. | Forecasts for the winning discrepancy Normal ridge, Normal RHS VB, independent AL/exAL seven-quantile fits, and joint AL/exAL seven-quantile fits, with recursive discrepancy-input handling audited explicitly. | Supplies the discrepancy DESN geometry, input contract, prior, and warm-start states for the historical joint USGS/GloFAS model. |
| G3. Joint historical USGS and GloFAS | Fit paired retrospective USGS and GloFAS through the cutoff using a reference DESN and a discrepancy DESN. | Best joint historical Normal ridge; best joint historical Normal RHS VB; best independent Q-DESN AL RHS VB; best independent Q-DESN exAL RHS VB; if promoted, all seven quantiles for AL and exAL at `0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95`; best joint-quantile AL RHS VB and exAL RHS VB. | Forecasts from the winning historical joint Normal and quantile models, still excluding issued forecast ensembles unless the forecast contract explicitly introduces them. | Tests whether the G1 reference and G2 discrepancy winners work together before the missing-future-USGS/ensemble application is attempted. |
| G4. Joint USGS, GloFAS, and forecast ensemble | Fit the article-facing GloFAS model with issued forecast ensembles and missing future USGS values. | Best Normal ridge and Normal RHS VB only as diagnostics/initializers where the likelihood contract permits them; best independent Q-DESN AL RHS VB; best independent Q-DESN exAL RHS VB; all seven quantiles at `0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95`; best final joint-quantile AL RHS VB and exAL RHS VB. | Final forecast-window synthesis, forecast figures, horizon-wise scores, uncertainty bands, ensemble-member comparisons, and article-ready provenance. | Only this stage can replace the authoritative GloFAS article result after full completion, visual audit, score/guardrail checks, and coordinator integration. |

This ladder is aligned with the overall strategy, with two important
constraints. First, the Normal ridge and Normal RHS models are not replacements
for the article's quantile model; they are fast screens, diagnostic probes, and
warm-start sources. Second, running all seven quantiles is a promotion action,
not a default action for every exploratory row. A model should reach the
seven-quantile AL/exAL and joint-quantile deliverables only after the focal
screening target is competitive and the observational-window guardrails are
acceptable.

Rolling-origin forecasts are not required for the current GloFAS deliverable
ladder. The required forecast check is the single authoritative-cutoff forecast
for each promoted stage winner. Rolling-origin machinery may remain available
as an optional robustness diagnostic, but it should not block Part 1 closeout,
Part 2 discrepancy work, or final GloFAS synthesis.

The Part 1 deliverable closeout launcher is intentionally fail-closed. The
requested bundle has 17 one-core slots: one Normal ridge forecast, seven
independent AL quantile fits, seven independent exAL quantile fits, one joint
AL quantile fit, and one joint exAL quantile fit. At the time this methodology
note was updated, only the Normal ridge oracle forecast has a concrete GloFAS
Part 1 runner. The independent and joint quantile rows must remain blocked
until audited GloFAS Part 1 wrappers exist for those exact likelihood and
forecast/scoring contracts. This prevents a deferred scheduler from launching
placeholder commands, validation-only code, or a model whose target differs
from the declared Part 1 USGS closeout target.

### G1. Univariate USGS

Fit USGS through the cutoff using no direct readout input block unless an
explicit comparison row declares it. The reservoir input should use lagged USGS
and realized ppt/soil covariates. The Normal ridge screen is used first, then
Normal RHS VB initialized from the ridge winner.

Optional DLM augmentation is allowed only when labelled and reproducible. The
structural DLM components should be generated from the historical USGS path and
realized ppt/soil covariates, with Kalman filtering/smoothing performed by the
audited C++ backend. DLM-augmented features should be treated as a separate
feature contract, not silently mixed with ordinary lag-only candidates.

Outputs:

- full-history fit figure;
- last-200-observation fit figure;
- score table with CRPS, MAE, RMSE, and runtime;
- ridge/RHS warm-start objects only for winners and near ties;
- ELBO trace for RHS candidates.

### G2. Univariate Observed Discrepancy

Fit the historical observed discrepancy

```text
d_t = g_t - y_t
```

where `g_t` is retrospective GloFAS and `y_t` is USGS. This stage searches for a
discrepancy DESN before the final joint historical model. It may use
discrepancy lags alone, discrepancy plus ppt/soil, or discrepancy plus
retrospective GloFAS/USGS auxiliary lags and ppt/soil. The current Part 2 bridge
supports these contracts.

The primary target is discrepancy fit/prediction under the declared validation
window, with the implied corrected path

```text
y_hat_t = g_t - d_hat_t
```

reported as a guardrail. A candidate that improves discrepancy CRPS but damages
the corrected USGS path should not be promoted.

The active Part 2 bridge screen follows the same fail-closed automation pattern
as G1. The running ridge phase must finish with zero failures before any Normal
RHS VB jobs are prepared. The RHS VB phase should select the top ridge
candidates by corrected historical validation CRPS, rebuild exact two-component
ridge warm starts, and then run a sparse tau0 grid. The current default
deferred RHS screen uses the top 10 ridge candidates, fixed reference
`tau0=1`, discrepancy `tau0` in `{1, 0.1, 0.01, 0.001}`, `max_iter=100`,
`min_iter=30`, and 20 one-thread workers. After the RHS screen finishes, the
selected winner is frozen into a post-RHS closeout manifest. Forecast and
quantile closeout jobs remain blocked until audited Part 2 historical-bridge
forecast and AL/exAL quantile runners exist for the exact model contract.

### G3. Joint Historical USGS And GloFAS

This is the intended intermediate model before introducing issued forecast
ensembles. It should use the winners from G1 and G2 to initialize a two-component
historical model:

```text
y_t^usgs   = q(x_t^q)                 + eps_t^usgs
y_t^glofas = q(x_t^q) + d(x_t^d)     + eps_t^glofas
```

Here `q(x_t^q)` is the reference DESN readout and `d(x_t^d)` is the discrepancy
DESN readout under the same sign convention as G2: `d_t = g_t - y_t`.
Therefore the implied corrected USGS path remains `g_t - d_hat_t`. The two
DESNs may share the same numerical specification, but they must have separate
seeds, separate design hashes, and separate RHS states. The input contracts may
differ, especially for the discrepancy component.

Start with Normal ridge/RHS versions of this historical joint model. Only after
that bridge is healthy should the same geometry be moved into the median
quantile AL RHS VB model.

The implementation is split into two explicit execution stages. The historical
launcher fits Normal ridge and block-RHS VB from frozen G1/G2 winners. A separate
continuation chain then reuses those exact Normal fits, produces both Normal
fixed-origin forecasts, fits and forecasts independent AL/exAL quantiles through
the declared warm-start DAG, and finally fits and forecasts the joint AL/exAL
models. The continuation is fail-closed on winner, design-cache, Normal-fit, and
initializer SHA256 values. It uses separate reference/discrepancy coefficient
and RHS factors, the structured `VB1_structured_v` exAL scale/shape update, and
a two-reservoir C++ recursive forecast backend. It intentionally performs no
quantile synthesis and no rolling-origin evaluation at G3.

### G4. Joint USGS, GloFAS, And Forecast Ensemble

This stage introduces the actual GloFAS forecast ensemble and the missing future
USGS path. It is the article-facing forecast model stage. It should use the
historical winners from G1-G3 as initialization and specification anchors.

Rules:

- no CEFS/GEFS source should enter this GloFAS application unless a future
  explicit contract reverses that policy;
- future covariate source policy must be labelled as operational, retrospective,
  or oracle;
- median/focal quantile experiments come before all-seven quantile reruns;
- full-seven synthesis and article promotion require a complete, frozen run.

## PriceFM Workflow

PriceFM has one main response path: the price series under a selected graphical
input contract. Its workflow should be:

```text
univariate price with chosen graph/input design
  -> Normal ridge
  -> Normal RHS VB
  -> independent AL RHS VB
  -> independent exAL RHS VB
  -> joint AL RHS VB
  -> joint exAL RHS VB
```

PriceFM differs from GloFAS in three important ways:

- horizon and fold structure are central, so validation AQL/CRPS must be tied to
  the declared fold/horizon contract;
- graph feature metadata belongs in the candidate manifest;
- the existing PriceFM registry and promotion adapter should remain the
  article-side authority until a package selector can reproduce it exactly.

Normal ridge and Normal RHS VB are still useful, but only as design and
initialization gates. PriceFM final claims should be based on the relevant
validation/test quantile scores and the frozen fold protocol.

## Joint Evaluation Workflow

The joint simulation/evaluation lane should use the same ladder, but with an
additional confirmation burden because simulated truth is available.

Recommended sequence:

```text
univariate simulated series
  -> Normal ridge
  -> Normal RHS VB
  -> independent AL RHS VB
  -> independent exAL RHS VB
  -> joint AL RHS VB
  -> joint exAL RHS VB
  -> MCMC confirmation for the last four quantile model classes
```

MCMC chains should be initialized from the corresponding VB state whenever the
feature dimensions match. The MCMC stage should report calibration, coverage,
crossing behavior, truth distance when available, effective sample size, and
chain diagnostics. VB-only winners should not become final MCMC-backed claims
until this confirmation passes or the limitation is explicitly stated.

## Efficient Screening Design

Avoid wasteful full Cartesian grids unless the scientific question truly needs
one. The preferred search pattern is:

1. broad Normal ridge screen over geometry, memory, lags, `alpha`, and `rho`;
2. cluster the best ridge rows by practical equivalence and mechanism, not only
   by rank;
3. run Normal RHS VB on representative top clusters and nearby variants;
4. if ridge rank and RHS rank disagree, use ridge only as an initializer and
   broaden the RHS screen in the disputed directions;
5. move only stable RHS regions into AL/exAL quantile VB;
6. promote to full quantile grids only after the focal quantile and guardrails
   pass;
7. reserve MCMC for final confirmation.

Large reservoirs are allowed when justified by the data and when runtime is
managed, but they must keep the same reproducibility contract: one core per fit,
single-thread BLAS unless an isolated benchmark supports otherwise, status
files, worker logs, terminal markers, and periodic health checks.

## Warm-Start Policy

Warm starts are allowed only when their compatibility can be verified.

| Warm-start move | Default policy |
|---|---|
| Normal ridge to Normal RHS VB, same design | Allowed and preferred |
| Normal RHS VB to AL/exAL VB, same design | Allowed after dimension and feature hash checks |
| Independent VB to joint VB, same quantile grid and design blocks | Allowed, with block-level validation |
| VB to MCMC, same model family | Allowed and preferred for confirmation chains |
| Warm start after changing `D`, `n`, `m`, lags, or feature contract | Not allowed except for scalar hyperparameter carryover |
| Warm start after changing only `tau0` | Allowed if design hash and coefficient dimension match |
| Warm start after changing only `alpha`/`rho` | Treat as cold unless an equivalence canary proves state compatibility |

The warm-start object must record the source model family, design hash, feature
names, coefficient dimension, response target, training window, posterior state,
and source commit.

## Artifact And Cleanup Policy

Tracked in Git:

- source code;
- tests;
- configuration templates and fixed manifests;
- compact score tables when they are final summaries;
- methodology, audit, and implementation notes;
- promoted article figures/tables and provenance records.

Ignored locally:

- raw data;
- runtime configs under `local_trackers/`;
- worker logs;
- `.rds`, `.rda`, `.RData`, checkpoint, and posterior draw payloads;
- non-promoted exploratory figures and tables.

Heavy artifacts should be retained only for:

- authoritative models;
- current winners;
- near ties needed for practical-equivalence checks;
- warm-start sources that will be reused;
- diagnostics required to explain a scientific decision.

Everything else should be eligible for conservative cleanup after a manifest,
score row, and sufficient reproducibility metadata are retained. Cleanup should
never delete active process paths, currently running run IDs, or artifacts owned
by another lane.

## Promotion Gates

A candidate can be promoted only after all applicable gates pass:

| Gate | Requirement |
|---|---|
| Completion | all required fits terminal; no unexplained failures |
| Score | primary metric improves or is practically tied with a simpler candidate |
| Guardrails | historical, validation, or forecast constraints remain acceptable |
| Diagnostics | reservoir, design, ELBO/objective, coefficient, and forecast checks are finite and interpretable |
| Visual audit | fit and forecast figures do not reveal an obvious pathological behavior |
| Reproducibility | manifest, hashes, config, branch, commit, and run commands are recorded |
| Storage | heavy objects retained only where justified |
| Article readiness | article-safe table/figure/prose changes are identified separately from runtime artifacts |

The coordinator, not a scientific lane chat, should merge to authoritative main
and publish article snapshots. Scientific lane chats should provide frozen
handoffs with exact changed files, commits, run tags, tests, and unresolved
risks.

## Recommended Shared API Extraction

The next cross-lane engineering step should be a deliberate extraction, not an
ad hoc refactor during an active scientific screen. The target shared surface is:

```text
desn_build_design()
desn_fit_normal_ridge()
desn_fit_normal_rhs_vb()
desn_make_normal_warm_start()
desn_validate_warm_start()
desn_fit_quantile_al_rhs_vb()
desn_fit_quantile_exal_rhs_vb()
desn_fit_joint_al_rhs_vb()
desn_fit_joint_exal_rhs_vb()
desn_make_forecast_paths()
desn_score_candidate()
desn_collect_screen()
desn_artifact_cleanup_plan()
```

The extraction should first wrap existing implementation pieces rather than
rewrite them. The package-style Normal functions should be the preferred source
for generic Normal-DESN behavior; GloFAS wrappers should contribute
application-specific panel, DLM, discrepancy, and oracle forecast contracts.

Minimal validation for the extraction:

- Normal ridge closed-form algebra test;
- exact chunked versus unchunked ridge equivalence;
- RHS VB finite trace and minimum-iteration behavior;
- warm-start dimension/hash rejection tests;
- forecast recursion tests with posterior draws and no leakage;
- GloFAS Part 1/Part 2 toy-contract tests;
- PriceFM bridge dry-run compatibility test;
- joint evaluation VB/MCMC initialization smoke.

Only after those pass should each scientific lane fetch the coordinator merge
and relaunch from the shared methodology/API.

## Current Decision

This note supports promoting the methodology and the already implemented
GloFAS Normal ridge/RHS, DLM, Part 2 bridge, and oracle-forecast work as reusable
scientific infrastructure. It does not promote unfinished GloFAS Part 2 results,
does not update `main.tex`, and does not change the FR09 article result.

The immediate operational recommendation is:

1. let the current GloFAS Part 2 discrepancy ridge screen finish;
2. keep PriceFM and joint evaluation expensive runs under their own lane chats;
3. ask the coordinator to merge this methodology note and the GloFAS Normal
   infrastructure branch when the lane handoff is ready;
4. after coordinator integration, have each lane fetch authoritative `origin/main`
   and adapt the staged ladder to its own active selection task.
