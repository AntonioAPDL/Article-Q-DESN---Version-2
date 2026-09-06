# PriceFM Stage-R71: R70 root-cause audit and repair plan

Date: 2026-09-01

## Decision

Stage-R70 is complete with failures and is not promotion-grade. Do not repeat
the R70 launch unchanged. Freeze its artifacts, salvage completed components,
repair the numerical and exAL mechanisms before another expensive launch, and
resume only the missing or scientifically invalid work.

The next production launch must not occur until all pre-launch repair gates in
this document pass. Test access, registry mutation, article mutation, joint
models, and MCMC remain blocked.

## Scope and authority

This audit covers only the PriceFM independent seven-quantile VB lane:

- code worktree: `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_joint_quantile_20260824`;
- branch: `work/pricefm-joint-quantile-20260824`;
- audited HEAD: `09943ca0b32d4c5f6e320f8fd1cee2d81d450aae`;
- R70 tag: `pricefm_stage_r69b_bounded_cran111_independent_vb_20260831`;
- package authority: exact CRAN `exdqlm` 1.1.1, tarball SHA-256
  `3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e`.

This plan does not authorize changes to GloFAS, joint-QVP, validation, the
PriceFM registry, or either article repository.

## Inputs audited

- R67 CRAN authority audit, adapter, source probes, and runtime manifest;
- R68 target reconciliation and R69A case-specific specification anchors;
- R69B train/validation-only launch manifest and all 56 generated configs;
- R70 runner, launcher, monitor, tests, launch ledger, worker logs, component
  artifacts, parameter summaries, traces, predictions, and metric summaries;
- exact CRAN 1.1.1 sources `R/exalStaticLDVB.R`, `R/utils.R`,
  `R/static_beta_prior.R`, `R/exal_sigmagam_structured.R`, and
  `R/exal_inference_config.R`;
- representative real R70 adapter matrices and one bounded real-case public-API
  diagnostic fit.

## Frozen R70 outcome

| Quantity | Result |
|---|---:|
| Manifest cases | 56 |
| Terminal cases | 56 |
| Complete seven-quantile cases | 25 |
| Failed cases | 31 |
| Complete components from complete cases | 175 |
| Partial components retained in failed cases | 75 |
| Total materialized components | 250 / 392 |
| Missing components | 142 |
| Materialized AL fits | 250 |
| Materialized exAL fits | 250 |
| Cholesky failures | 29 |
| Structured gamma-grid failures | 2 |
| Binary model artifacts | 0 |
| Test opened | No |

All 31 failed cases contain useful partial work. Twenty failed after completing
`tau=0.10`, at the attempted `tau=0.25` component. Eleven failed after
completing through `tau=0.55`, at the attempted `tau=0.75` component. The
runner wrote no method-level start or failure checkpoint, so the failing method
inside those attempted components cannot be proven from the production logs.

## Scientific result audit

Among the 25 complete cases:

- AL was validation-best among AL, exAL, and the three naive methods in 25/25;
- AL beat the best naive method in 25/25;
- AL improved over the prior authoritative Q-DESN validation anchor in only
  2/25 cases;
- AL beat cached PriceFM in 17/25 but operational PriceFM in 0/25;
- no case beat both PriceFM references;
- the median AL change versus the prior Q-DESN anchor was `-0.0335` AQL, where
  positive means improvement;
- only ES fold 3 (`+0.0092`) and NO_5 fold 3 (`+0.0026`) improved over the prior
  Q-DESN anchor, and neither passed the operational PriceFM gate.

R70 therefore produced no promotion candidate. Test data must remain closed.

## Root-cause findings

### 1. Fixed absolute Cholesky jitter is numerically ineffective

Both the reduced AL CAVI branch and the exAL branch form

`V_inv = crossprod(X * sqrt(W)) + prior_precision`

and attempt `chol(V_inv)`, followed by exactly one fallback using
`V_inv + 1e-10 I`. The RHS-NS prior precision is nonnegative by construction,
so the matrix is mathematically positive definite when all moments are finite.
The production error is therefore consistent with floating-point loss of
positive definiteness, non-finite prior/weight moments, or both.

A deterministic stress test used 12,000 actual BG fold 1 design rows and
positive weights spanning `1e-8` to `1e8`. The weighted Gram diagonal scale was
`3.6154808678e10`, its floating-point spacing was `7.62939453125e-6`, and its
smallest computed eigenvalue was `-4.40e-7`. Adding `1e-10` did not change even
one represented diagonal value and Cholesky still failed. A relative jitter of
`scale * 1e-16 = 3.62e-6` changed the matrix and Cholesky succeeded.

This proves that the CRAN fallback can become a literal numerical no-op at the
scales encountered by weighted PriceFM designs. It does not prove the exact
latent-weight range at every failed production iteration because R70 did not
record it.

### 2. Every audited DESN design is rank deficient or nearly rank deficient

Six representative complete and failed adapters were inspected on 12,000 real
rows. All contained constant columns and had numerical rank deficiencies:

| Case | Outcome | Features | Constant columns | Rank deficiency |
|---|---|---:|---:|---:|
| AT fold 1 | complete | 223 | 1 | 4 |
| AT fold 3 | Cholesky failure | 223 | 1 | 4 |
| FR fold 3 | gamma-grid failure | 223 | 1 | 4 |
| SK fold 2 | Cholesky failure | 253 | 4 | 7 |
| ES fold 3 | complete | 183 | 1 | 4 |
| NL fold 2 | complete | 262 | 6 | 9 |

Rank deficiency is a susceptibility factor, not a sufficient explanation:
completed and failed cases both exhibit it. Silent feature deletion would also
change the RHS prior and model definition, so it is not an acceptable repair
without a separately pre-registered design change.

### 3. The RHS prior scale and initialization schedule are mismatched

R70 preserved `tau0=0.001`, initialized the RHS global scale at `tau=1`, and
froze its update for only five iterations. Exact CRAN 1.1.1 intentionally
defaults an unspecified initialization to `tau=1`, while its default RHS
freeze/warm-up is 50 iterations.

Thus R70 begins 1,000 times above the prior scale and releases the global-scale
update after 5 rather than 50 iterations. This can cause abrupt changes in the
coefficient precision precisely while the latent AL/exAL weights are still
moving. It is an amplifier of the numerical problem, but changing `tau0` alone
cannot repair an absolute-jitter no-op and must not be used as a substitute for
the factorization fix.

### 4. The structured exAL surface is scientifically invalid

Across the 250 materialized exAL components:

- only 21 converged under package criteria;
- 231 reached the 150-iteration limit;
- median coefficient L2 norm was approximately `4.79e8`;
- 133 had coefficient L2 norm above `1e6`;
- median coefficient norms at quantiles 0.25, 0.45, 0.55, and 0.75 ranged from
  approximately `7.1e8` to `1.26e10`;
- scale estimates at those quantiles commonly reached `1e7` to `1e9`;
- two cases stopped because every structured gamma-grid log weight was
  non-finite;
- exAL was validation-best in 0/25 complete cases and produced original-scale
  AQL values around `1e11`.

This is not a small calibration error. The current structured scale-skewness
implementation or its interaction with this readout/prior is failing away from
the median. All R70 exAL components must remain quarantined.

### 5. R70 telemetry reads the wrong package fields

R70 attempts to read sigma, gamma, RHS tau, and related trajectories from
`fit$misc$sigma_trace`, `fit$misc$gamma_trace`, and similarly named fields.
CRAN 1.1.1 stores sigma/gamma trajectories under
`fit$diagnostics$vb_trace` and detailed exAL/RHS diagnostics under
`fit$diagnostics$ld_block` and `fit$diagnostics$rhs`. Consequently the R70
trace CSVs contain `NA` for the variables needed to reconstruct the failure.

This is an observability bug. A repaired runner must map the actual public fit
object schema and validate that required telemetry is non-missing.

### 6. Case-level atomicity discarded method-level evidence

For each quantile R70 fits AL, then exAL, then writes both. If either call
fails, neither current-quantile result is persisted. A single exAL failure can
therefore hide a completed AL fit and fail the entire case. This prevents exact
method attribution and wastes work.

The repair must make `(case, quantile, likelihood)` the atomic resumable unit.

### 7. Bounded real-case probe

A no-artifact probe used exact CRAN 1.1.1 public APIs on BG fold 1 at
`tau=0.25`, where production failed. With the R70 controls and only 12
iterations:

- AL completed 12 iterations in 175.70 seconds;
- exAL completed 12 iterations in 270.61 seconds;
- exAL ended with beta L2 `168.101` and sigma `3.185605`;
- neither branch failed immediately.

The production failure is therefore iteration-dependent and occurs after the
initial transition, not because the adapter or starting precision is invalid.
The probe does not establish long-run stability.

## Evidence confidence ledger

| Finding | Confidence | What would close the remaining gap |
|---|---|---|
| The absolute `1e-10` fallback can be a represented no-op | Proven on a real R70 design stress matrix | Upstream regression test |
| R70 DESN matrices are rank deficient/near-collinear | Proven on representative complete and failed cases | Full 56-case diagnostic ledger |
| Current R70 exAL outputs are unusable | Proven by convergence, parameter, and validation metrics | None needed for quarantine |
| R70 telemetry extraction is mapped to the wrong fields | Proven from exact package source and all-NA output columns | Corrected schema test |
| Case-level writes lose method attribution and resumability | Proven from runner control flow and artifacts | Atomic runner test |
| Most Cholesky failures occur inside exAL | Strong inference, not proven | Method-start/terminal markers or instrumented replay |
| Five-iteration RHS warm-up amplifies instability | Mechanistically supported, not isolated causally | Bounded post-solver schedule probes |
| A different `tau0` would improve PriceFM performance | Unknown | Case-specific validation study only after stability |
| Corrected structured exAL will outperform AL | Unknown | Mechanism gates followed by validation-only evidence |

The unresolved method attribution is precisely why the next runner must be
atomic at the likelihood level. It would be scientifically incorrect to call
all 29 Cholesky failures exAL failures using the present production logs alone.

## Repair architecture

### Phase A: freeze and close out R70

Implement a read-only Stage-R71 closeout that:

1. hashes the R69B manifest, configs, runtime package, runner, and all terminal
   component files;
2. records all 56 terminal case outcomes and exact failure signatures;
3. inventories the 250 reusable components and 142 missing components;
4. recomputes validation metrics without test access;
5. records the no-promotion decision;
6. writes CSV, JSON, and Markdown outputs but no launch YAML.

### Phase B: repair the package-level precision solver

The solver should be repaired upstream in `exdqlm`, not monkey-patched inside
the PriceFM runner. A modified package must not be labelled exact CRAN 1.1.1.
It needs a new immutable version/commit and source hash before PriceFM use.

The replacement SPD factorization must:

1. symmetrize the precision matrix;
2. reject and report non-finite weights, prior precision, or matrix entries;
3. compute a scale from the matrix diagonal/norm;
4. try an adaptive relative jitter ladder tied to machine precision and scale;
5. return the chosen jitter, attempt count, scale, and conditioning proxy;
6. use an eigenvalue-floor fallback only under an explicit auditable policy;
7. leave the zero-jitter path unchanged for well-conditioned matrices;
8. fail with case, likelihood, quantile, iteration, and diagnostics if no
   bounded repair succeeds.

For backward compatibility, the repaired solver should attempt the two
existing paths first: unmodified Cholesky and then absolute `1e-10`. The new
relative ladder activates only when both old paths fail. This preserves the
arithmetic path for R70 components that already completed, while making the
previously failing path scale aware.

Required upstream tests:

- well-conditioned equivalence with the existing solve;
- the real-design weighted stress matrix where absolute `1e-10` is a no-op;
- finite-input and non-finite-input contracts;
- deterministic jitter selection;
- bounded solution perturbation;
- AL and exAL coverage of the shared solve;
- no silent covariance indefiniteness after inversion.

### Phase C: repair or reject structured exAL

Before any broad exAL refit, upstream mechanism tests must establish:

1. finite structured log weights and conditional scale kernels;
2. an AL-limit sanity check at gamma zero;
3. recovery on synthetic data with known moderate skewness;
4. stable behavior at all seven PriceFM quantiles;
5. no boundary pile-up without an explicit diagnostic;
6. finite beta, sigma, gamma, predictions, and ELBO terms;
7. non-catastrophic validation behavior relative to the same AL fit;
8. correct structured/M0 scale parameterization under the public API.

`laplace_delta` may be used as a diagnostic comparator, but it must not silently
replace the requested structured factorization. If structured exAL cannot pass
these gates, the scientifically honest outcome is an AL-only PriceFM surface
and a documented exAL mechanism failure.

### Phase D: repair the PriceFM runner

Build a new runner with method-level isolation:

- atomic key: case ID, quantile, likelihood, config hash, package hash;
- write `started.json` before each method and `terminal.json` immediately after;
- persist AL before beginning exAL;
- catch and classify each method failure without terminating unrelated work;
- resume only missing or invalid atomic keys;
- read telemetry from `diagnostics$vb_trace`, `diagnostics$rhs`, and
  `diagnostics$ld_block`;
- require finite, nonempty telemetry at the preflight test;
- record solver jitter/fallback diagnostics from the repaired package;
- preserve train/validation-only data firewalls;
- write no binary model objects by default.

### Phase E: settle RHS initialization before production

After the package solver is fixed, run bounded no-test mechanism probes on two
representative failed cases and one completed case. Compare only scheduling,
not a broad hyperparameter search:

- explicit `init_tau=1`, freeze 50;
- explicit `init_tau=tau0`, freeze 50;
- preserve the historical `tau0` anchor initially.

Select the schedule using finite iterations, no collapse flag, bounded
precision dynamics, and stable validation behavior. Do not launch a `tau0`
screen until numerical stability is established. Any later `tau0` calibration
must be case-specific and validation-only.

### Phase F: efficient repair launch

Only after Phases B-E pass:

1. reuse the 250 hash-valid AL components only after bridge tests show that the
   repaired package reproduces representative completed R70 betas and
   predictions under the backward-compatible old-first solve order;
2. fit only the 142 missing AL components;
3. treat all 250 existing exAL components as invalid;
4. refit the seven-quantile exAL surface only if the repaired structured
   mechanism passes Phase C;
5. otherwise close the independent surface as AL-only;
6. schedule one atomic fit per core with bounded memory and 20 workers only
   after a fresh server resource audit;
7. never rerun a valid component merely because its case-level predecessor
   failed.

The maximum repaired workload is 142 AL fits plus 392 corrected exAL fits. It
is materially smaller than repeating all 784 R70 fits. If exAL fails its
mechanism gate, the workload is only the 142 missing AL fits.

### Phase G: validation selection and promotion gate

After a complete stable surface exists:

1. freeze all component hashes;
2. select a model separately for each region/fold using validation AQL only;
3. require complete seven-quantile predictions and finite diagnostics;
4. compare against the current authoritative Q-DESN validation anchor;
5. open test data only for frozen validation winners;
6. require test improvement over both authoritative Q-DESN and operational
   PriceFM;
7. require reproducibility and harm guards before registry or article changes.

## Pre-launch gates

Every gate is mandatory:

- R70 closeout and salvage ledger complete;
- no active R70 process;
- upstream package version/hash frozen and honestly labelled;
- scale-aware solver tests pass;
- method-attribution and resume tests pass;
- telemetry schema tests pass with no required all-`NA` columns;
- RHS schedule probes pass without collapse or unbounded precision;
- structured exAL mechanism gates pass, or exAL is explicitly excluded;
- all reused components match config, data, code, and package-path hashes;
- launch manifest contains train and validation only;
- test, registry, article, joint, and MCMC authorization remain false;
- no unrelated worktree, process, or artifact is touched.

## Explicitly do not do yet

- Do not repeat R70 unchanged.
- Do not tune `tau0` as a substitute for fixing the solver.
- Do not silently standardize or delete DESN columns; that changes the prior
  semantics and model definition.
- Do not promote either marginal R70 improvement.
- Do not use any current R70 exAL result for selection.
- Do not open test data.
- Do not mutate the PriceFM registry or article.
- Do not run joint models or MCMC.
- Do not launch a repair campaign before the upstream and runner gates pass.

## Reproduction commands used by this audit

The final R70 state is reproduced with:

```bash
python application/scripts/pricefm/240_monitor_pricefm_stage_r70_cran111_independent_vb.py \
  --manifest application/data_local/pricefm/experiment_grids/pricefm_stage_r69b_bounded_cran111_independent_vb_20260831/case_manifest.csv \
  --write-json application/data_local/pricefm/experiment_grids/pricefm_stage_r69b_bounded_cran111_independent_vb_20260831/monitor_latest_healthcheck.json
```

The exact package source is verified with:

```bash
sha256sum application/data_local/pricefm/runtime_sources/exdqlm_cran_1p1p1/exdqlm_1.1.1.tar.gz
```

The source locations responsible for the main failures are:

- `R/utils.R`: reduced AL q(beta) Cholesky;
- `R/exalStaticLDVB.R`: exAL q(beta) Cholesky;
- `R/static_beta_prior.R`: RHS-NS initialization and update schedule;
- `R/exal_sigmagam_structured.R`: structured gamma-grid update.

## Implemented outcome

The plan was implemented on 2026-09-01 without touching the dirty `exdqlm`
package worktree or any non-PriceFM lane. Because the package lane contained
unrelated uncommitted work, the numerical repair was built as an isolated,
honestly relabelled PriceFM-local derivative of the exact CRAN tarball. It is
not represented as CRAN 1.1.1.

### R71 closeout

The read-only closeout is implemented in:

- `application/scripts/pricefm/241_audit_pricefm_stage_r71_r70_closeout.py`;
- `application/tests/test_pricefm_stage_r71_r70_closeout.py`.

Materialized evidence is under:

`application/data_local/pricefm/authoritative/pricefm_stage_r71_r70_closeout_20260901`

It reproduced 56 terminal cases, 25 complete cases, 31 failures, 250 terminal
paired components, 142 missing AL atoms, 250 quarantined exAL atoms, zero
binary artifacts, and zero validation promotion candidates. It confirmed that
AL beat the prior Q-DESN anchor in 2/25 complete cases, operational PriceFM in
0/25, cached PriceFM in 17/25, and the best naive baseline in 25/25.

### PriceFM-local package repair

The reproducible package materializer and patch are:

- `application/scripts/pricefm/242_materialize_pricefm_stage_r72_exdqlm_spd_repair.py`;
- `application/scripts/pricefm/pricefm_stage_r72_exdqlm_1p1p1_spd_repair.patch`.

The installed runtime is:

`application/data_local/pricefm/runtime_libraries/exdqlm_pricefm_r72_spd_repair`

Its contract is:

| Field | Value |
|---|---|
| Base source | exact CRAN `exdqlm_1.1.1.tar.gz` |
| Base SHA-256 | `3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e` |
| Installed version | `1.1.1.9001` |
| Repository label | `PriceFM-local` |
| Patch SHA-256 | `b85d0eb7c9069fc6a9e4ee3250c98da59c682e1b1a0e5dda4b27926cb60634d7` |
| Repair | old-first bounded scale-aware SPD Cholesky with telemetry |

The direct factorization and legacy absolute-jitter paths remain first. The
relative jitter ladder activates only if both fail, rejects non-finite input,
is bounded at relative jitter `1e-8`, and records the path, matrix scale,
jitter, and attempt count at every VB iteration.

### Atomic runner and launch prep

The runtime boundary is implemented in:

- `application/scripts/pricefm/pricefm_stage_r72_repair_adapter.R`;
- `application/scripts/pricefm/243_run_pricefm_stage_r72_repair_component.R`;
- `application/scripts/pricefm/244_prepare_pricefm_stage_r72_missing_al_repair.py`;
- `application/scripts/pricefm/246_launch_pricefm_stage_r72_missing_al_repair.py`;
- `application/scripts/pricefm/247_monitor_pricefm_stage_r72_missing_al_repair.py`.

Each process now owns one `(case, tau, likelihood)` atom. It writes a start
marker, method outputs, actual package telemetry, hashes, and a terminal marker
without serializing a model object. Resume accepts only hash-valid completed
atoms. The production manifest has 142 AL tasks across the 31 failed cases;
the 250 existing AL atoms remain immutable, and exAL is absent.

### Mechanism and RHS schedule gates

The gate implementations are:

- `application/scripts/pricefm/245_gate_pricefm_stage_r72_repair.py`;
- `application/scripts/pricefm/248_gate_pricefm_stage_r72_rhs_schedule.py`.

The first gate completed a 12-iteration real BG fold 1 `tau=0.25` AL probe
with finite outputs, the intended RHS preflight, and bounded SPD telemetry.
The campaign-level exAL gate failed: 133/250 existing atoms had beta L2 above
`1e6`, 132/250 had sigma above `1e6`, and only 21/250 converged. Structured
exAL therefore remains blocked.

The first production launch was stopped before any task completed when a
review caught that the 12-iteration probe had not crossed the iteration-50 RHS
release point required by this plan. The stop affected only R72, left 0
completed and 0 failed tasks, and retained only 20 start markers.

Six corrected schedule probes then compared `init_tau=1` and
`init_tau=tau0=0.001` through 60 iterations on BG fold 1 at `tau=0.25`, SK fold
2 at `tau=0.75`, and the completed ES fold 3 control at `tau=0.25`. Both
schedules completed all three fits without collapse or adaptive jitter. The
selected schedule was `init_tau=1`, freeze 50:

| Schedule | Mean validation pinball | Maximum beta L2 | Collapses |
|---|---:|---:|---:|
| `init_tau=1` | 0.08323045 | 249.21 | 0 |
| `init_tau=tau0` | 0.08328175 | 289.46 | 0 |

None of the 60-iteration probes met the full convergence criterion; this was
not required for a bounded schedule comparison. All crossed the release point
and recorded ten RHS tau updates.

### Validation completed

The focused validation was:

```bash
python -m pytest -q \
  application/tests/test_pricefm_stage_r71_r70_closeout.py \
  application/tests/test_pricefm_stage_r72_spd_repair.py \
  application/tests/test_pricefm_stage_r72_atomic_runner.py \
  application/tests/test_pricefm_stage_r72_missing_al_repair_prep.py \
  application/tests/test_pricefm_stage_r72_mechanism_gates.py \
  application/tests/test_pricefm_stage_r72_launcher_monitor.py
Rscript application/tests/test_pricefm_stage_r72_spd_repair.R
```

Final result: `14 passed`; the R package test also passed. Python compilation,
R parsing, and `git diff --check` passed.

### Current background launch

The final gated launch is:

- tag: `pricefm_stage_r72_missing_al_repair_20260901`;
- tmux: `pricefm_stage_r72_20260901`;
- tasks: 142 missing AL atoms;
- workers: 20;
- logical CPUs: 32-51, one process per CPU;
- RHS: case-specific `tau0=0.001`, selected `init_tau=1`, freeze 50;
- package: PriceFM-local `exdqlm` 1.1.1.9001;
- test, registry, article, joint, MCMC: blocked.

At the post-launch check, the launcher plus 20 workers were active, with zero
completed tasks, zero failures, zero binary artifacts, 489 GiB available
memory, and approximately 370 GiB free disk. The unrelated joint-validation
workers remained pinned to CPUs 0-19 and were not touched.

## Resume and closeout sequence

1. Monitor R72; do not stop or relaunch while it remains CPU-active and its
   completed count advances.
2. When terminal, require 142/142 hash-valid atoms, zero unclassified failures,
   bounded SPD telemetry, finite parameters/predictions, and no binary files.
3. Freeze and combine the 250 R70 AL atoms with the 142 R72 AL atoms into a
   complete 392-atom seven-quantile AL surface. Preserve package provenance at
   the atom level because only repaired atoms use version 1.1.1.9001.
4. Recompute validation metrics for all 56 case-specific models and compare
   against their prior authoritative Q-DESN and both cached and operational
   PriceFM references.
5. Freeze validation-only decisions before opening any test artifact.
6. Open test only for a complete frozen validation winner, then require it to
   beat both authoritative Q-DESN and operational PriceFM before any promotion.
7. Keep structured exAL, registry, article, joint models, and MCMC blocked
   unless a later, separately validated mechanism stage authorizes them.
