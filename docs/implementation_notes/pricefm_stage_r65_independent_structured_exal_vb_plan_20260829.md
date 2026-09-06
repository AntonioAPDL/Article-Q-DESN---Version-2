# PriceFM Stage-R65 independent structured-exAL VB completion plan

Date: 2026-08-29

Lane: PriceFM only

Status: audited design and preregistration plan only. No fit, launch, test opening,
registry mutation, article mutation, commit, or push is authorized by this
document.

## Executive decision

The next PriceFM experiment should be a complete independent seven-quantile VB
comparison under the already frozen, case-specific Stage-R62 model
specifications. For every one of the 114 region/fold cases, Stage-R65 should:

1. reconstruct one train/validation adapter from the frozen R62 scientific
   contract;
2. fit one normal-RHS anchor;
3. refit the seven AL quantiles as a parity control, with every quantile starting
   from that same normal-RHS anchor;
4. fit the seven exAL quantiles with the structured
   `q(gamma) q(sigma | gamma)` variational factorization, each initialized from
   its same-quantile AL fit;
5. select among the frozen legacy AL bundle, frozen legacy exAL bundle, and new
   structured-exAL bundle using validation data only and one whole seven-quantile
   family per region/fold;
6. keep test sealed until all validation winners and hashes are frozen.

This is the smallest complete experiment that answers the unresolved question.
It does not search DESN architecture, `tau0`, likelihood by quantile, joint
models, or MCMC. Those changes would confound the inference-factorization test
or duplicate work that is already authoritative.

## Relationship to R62-R64

Stage-R62 is the independent-model authority for this plan. Stage-R63 and
Stage-R64 remain valid, frozen evidence about the separate joint-model path, but
they are not execution dependencies for Stage-R65.

| Stage | Verified state | Consequence for R65 |
| --- | --- | --- |
| R62 | 114/114 matched region/fold cells; seven quantiles; 27 AL and 87 legacy exAL validation winners; no coverage gaps or provenance conflicts | Supplies the frozen case-specific model contracts, legacy comparison values, and selection definition |
| R63 | 38/38 corrected joint VB arms completed over 30 cells; only HU fold 3, PT fold 2, and SI fold 3 entered its validation confirmation queue | Preserved as joint evidence; it is not a reason to replace or delay the independent completion |
| R64 | Joint-MCMC preparation remains blocked by adapter replay, runner, and runtime-benchmark gates | Frozen and explicitly out of scope; R65 must not launch or prepare joint MCMC |

The new direction therefore supersedes R64 as the *next execution priority*, not
as historical evidence. No R63/R64 file, checkpoint, or decision should be
deleted or rewritten.

## Verified current state

### Repository and process state

| Item | Audited value |
| --- | --- |
| Task worktree | `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_joint_quantile_20260824` |
| Task branch/upstream | `work/pricefm-joint-quantile-20260824` / `origin/work/pricefm-joint-quantile-20260824` |
| Audited HEAD | `2ec22704344b9d6848ab8d3fb761cd46667d6f3c` |
| Branch relation | clean and synchronized at the start of this audit |
| Runtime evidence root | `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm` |
| Active PriceFM fits | none observed at the audit checkpoint |
| Other active work | unrelated processes must remain untouched |
| Free storage at audit | approximately 427 GiB; this is a transient observation, not a launch guarantee |

Resource availability must be measured again immediately before a future
launch. No fixed worker count is authorized from this snapshot.

### R62 independent authority

The authoritative source is:

`/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r62_matched_seven_quantile_authority_20260827`

Its `summary.json`, authority CSV, candidate-bundle ledger, gap ledger, gates,
and source manifest jointly establish:

- 114 region/fold cases and zero coverage gaps;
- quantiles `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`;
- validation-only selection by `seven_quantile_mean_AQL`;
- 27 selected AL bundles and 87 selected legacy exAL bundles;
- 396 provenance rows but 228 unique case-family bundles;
- 798 unique case/quantile component configurations;
- launch, test, registry, article, and MCMC authorization all false.

Each R62 case has one frozen DESN and information-set contract. Across the 114
cases those contracts are intentionally heterogeneous:

- feature policy: 58 target-only, 31 graph-khop, 24 graph-summary-mean, and one
  graph-neighbor-spread-summary;
- feature dimension: 40, 60, 80, 100, or 120;
- depth: one, two, or three;
- units: case-specific vectors from 40 through 120;
- `alpha`: 0.25 through 0.50;
- `rho`: 0.82, 0.90, or 0.98;
- `input_scale`: 0.175 through 0.50;
- `state_output = final_layer` for every case;
- `tau0 = 0.001`, `train_origin_limit = 3000`, `max_iter = 100`, and
  `n_samp_xi = 80` for every case;
- exact chunking for every case.

Stage-R65 must preserve each case's own specification. It is not searching for a
single model that works everywhere.

### Why the structured-exAL question remains open

All 798 historical R62 component configurations contain AL and exAL method
rows, but every audited historical package head predates the structured Q-DESN
engine. The R62 exAL values are therefore legacy exAL VB values, not evidence
for the newer structured `q(gamma) q(sigma | gamma)` approximation.

The legacy family difference is also small in most cases. Comparing legacy exAL
with legacy AL at the seven-quantile case level gives a median relative change
of approximately -0.675%, 66/114 cases within 1%, 94/114 within 2%, and 113/114
within 5%. This makes parity, numerical tolerances, convergence, and provenance
first-order scientific requirements. A silent runner or initialization change
could be mistaken for a likelihood gain.

### Retained artifacts and the need for a controlled refit

The R62 component directories retain configs, metric summaries, method
summaries, traces, and parameter summaries. Full prediction surfaces remain for
only 42 of 798 selected components. Consequently:

- frozen legacy scalar validation AQL values can and should be reused;
- a complete old AL/exAL postfit synthesis cannot be reconstructed from disk;
- refitting legacy exAL solely to recreate predictions would add cost without
  answering the structured-factorization question;
- a contemporaneous AL parity refit is still needed as the structured exAL warm
  start and as a check that the reconstructed adapter and runner reproduce the
  frozen authority.

## Exact scientific question

Holding region, fold, data split, information set, feature map, DESN state,
RHS prior, `tau0`, quantile grid, training cap, and metric definition fixed:

> Does structured exAL VB improve the validation AQL of a complete independent
> seven-quantile bundle relative to the frozen legacy AL and legacy exAL
> authorities?

The estimand is case-specific. The unit of selection is a region/fold bundle,
not an individual quantile and not a pooled global specification.

## Non-goals and hard boundaries

Stage-R65 must not:

- fit a joint seven-quantile model;
- run MCMC;
- tune or screen `tau0`;
- broaden depth, units, lags, feature policy, graph radius, `alpha`, `rho`, or
  input scale;
- choose AL for some quantiles and exAL for others within one region/fold;
- blend AL and exAL predictions;
- use test data in fitting, convergence intervention, selection, or tie-breaking;
- mutate the PriceFM registry or any article file;
- touch GloFAS, individual-validation, joint-validation, DQLM, or other-lane
  processes and artifacts;
- use a mutable package checkout as the scientific source;
- call a state-seeded restart an exact continuation.

## Critical alternatives considered

| Alternative | Scientific value | Cost/risk | Decision |
| --- | --- | --- | --- |
| Reuse R62 without fitting | Preserves authority | Cannot answer structured-exAL question | Reject |
| Refit AL, legacy exAL, and structured exAL everywhere | Complete contemporaneous surface | Legacy exAL refit is redundant and roughly adds another historical-family campaign | Reject |
| Run structured exAL only for the 87 current exAL winners | Lower compute | Selection-biased; cannot discover structured exAL wins in the 27 AL cases | Reject |
| Launch 798 independent one-quantile jobs | Closest to old launcher and naturally granular | Rebuilds adapters and normal anchors seven times per case; high storage and duplicated work | Reject as primary design |
| Launch 114 case-grouped jobs with seven atomic quantile components | Complete, case-specific, resumable at completed-quantile boundaries, shared adapter and anchor | Requires a narrowly scoped grouped runner and tests | Adopt |
| Resume the joint/MCMC path first | Addresses a different model family | R64 capability gates are still blocked and the independent exAL surface is incomplete | Reject for now |
| Broaden DESN or `tau0` while changing exAL inference | May find better predictors | Confounds architecture/prior changes with inference-factorization effects | Reject for R65 |

The 114-job grouped design is optimal for the current question because it
removes avoidable duplicated I/O while retaining case-level isolation and
quantile-level recovery.

## Immutable inference source

The future runner must use a dedicated detached package source at:

`cc85a75` in
`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`

That source identifies package version 1.1.1 and contains the structured Q-DESN
engine. Version text alone is insufficient; the run manifest must record the
full commit and the following audited SHA-256 values:

| File | SHA-256 |
| --- | --- |
| `R/exal_ldvb_engine.R` | `c55e3cb960f8d1d695e4340c496334b4acbf73500399872b0d5a09896493add5` |
| `R/exal_inference_config.R` | `18f6a140e0dc4e33702528b21db8bf3b264b743fc745f2daf0b276143fb11044` |
| `R/exal_sigmagam_structured.R` | `4bc6e0d11736ec5e7ef73a267c84aedf7b1de36ad218f81859e0060ec552052f` |

The package's audited structured defaults are a 151-point grid, a six-standard-
deviation span, ten frozen warmup iterations, forced activation after warmup,
0.6 damping for five updates, and at least one post-warmup structured update.
Stage-R65 must pass these values explicitly rather than inherit defaults. The
run summary must prove that structured updates actually occurred.

The package's current `main` was not the audited authority for this engine.
Future unrelated commits in any worktree must not silently alter the run.

## Runner corrections required before launch

The existing `application/scripts/pricefm/08_run_desn_model_smoke.R` is useful
evidence but is not yet a sufficient R65 runner:

1. It does not explicitly pass the sigma-gamma factorization profile.
2. Its old exAL method identifier collides with legacy exAL output.
3. Its summaries do not make posterior approximation, data-target exactness,
   and chunking exactness distinct.
4. A naive multi-quantile loop could warm a later AL quantile from the preceding
   AL quantile, changing the historical initialization contract.
5. It has no proven exact optimizer-continuation checkpoint contract.

The grouped R65 runner must instead implement this fixed sequence per case:

1. Verify the source contract and build one train/validation adapter.
2. Hash adapter inputs, rows, feature semantics, scaling parameters, and design
   dimensions before any fit.
3. Fit one deterministic normal-RHS anchor.
4. For each of the seven quantiles, initialize AL from that same normal anchor.
5. Initialize structured exAL only from its same-quantile completed AL fit.
6. Write predictions, raw original-scale metrics, convergence diagnostics, and
   provenance to a temporary component directory.
7. Atomically rename the component to `complete` only after every required file
   and hash validates.
8. On rerun, skip only a complete, hash-matching component. Recompute corrupt or
   incomplete components; never overwrite valid evidence in place.

One worker must use one numerical thread. Parallelism belongs at the case-job
level, with a resource preflight immediately before launch.

### Required method identities and telemetry

Use distinct, immutable method identities, for example:

- `qdesn_al_rhs_ns_exact_chunked_r65_parity`;
- `qdesn_exal_rhs_ns_exact_chunked_structured_r65`.

Every method summary must separately record:

- `inference_engine = VB`;
- `likelihood_family = AL` or `exAL`;
- `posterior_approximation = mean_field_or_existing_al` or
  `structured_qgamma_qsigma_given_gamma`;
- `data_target_approximation = false`;
- `exact_chunking = true`;
- package commit and source hashes;
- explicit structured profile and observed structured update count;
- normal-anchor hash and same-quantile AL initializer hash;
- convergence status, iterations, objective trace, and termination reason;
- split firewall status and proof that test was not loaded.

The phrase `approximate = false` must not be used alone because it can confuse
an exact chunked data target with an exact posterior calculation.

## Manifest contract

### Case manifest: 114 rows

The preparation stage should emit one immutable row per region/fold with at
least:

- `case_id`, `region`, and `fold`;
- R62 authority row and candidate-ledger source paths and hashes;
- scientific-contract and feature-semantics hashes;
- feature policy, graph settings, feature dimension, depth, units, lag settings,
  state output, `alpha`, `rho`, input scale, `tau0`, seed, training cap, and
  exact-chunking controls;
- ordered seven-quantile vector;
- all seven legacy AL and exAL validation references and their source hashes;
- selected legacy family and selected legacy seven-quantile AQL;
- pinned package commit, source hashes, factorization profile, and output root;
- `selection_split = val`, `test_opened = false`, and every mutation/launch gate
  false at plan time.

Preparation must fail on a missing case, duplicate case, missing quantile,
conflicting scientific hash, path outside approved PriceFM roots, or any test
selection field.

### Component ledger: 798 planned rows

Derive seven component rows per case with the frozen quantile, component config
hash, normal-anchor identity, AL parity identity, structured-exAL identity,
expected artifacts, state, and completion hash. The ledger is scheduling and
recovery metadata; it does not make quantile-level scientific decisions.

## Fit and convergence policy

The primary pass retains the historical `max_iter = 100` contract so that the
new AL parity fit remains interpretable. A component is complete only if both
its AL parity fit and structured-exAL fit have finite predictions and declared
convergence, and the structured fit records the required post-warmup updates.

No job may silently increase iterations. If a structured component reaches the
cap:

1. quarantine that component and keep its evidence;
2. complete unaffected cases and quantiles;
3. freeze a nonconvergence ledger;
4. decide in a separate, preregistered completion action whether a larger cap is
   justified for only those components;
5. if used, label the result a state-seeded restart and record the old and new
   state hashes, budgets, and objective continuity diagnostics.

The current engine supports rich initialization state but has not demonstrated
bit-for-bit continuation. The restart result must not be described as exact
continuation, and a restarted structured candidate cannot enter selection until
its parity and convergence audit passes.

## Validation-only selection algorithm

Selection is performed independently for each of the 114 region/fold cases.

### Gate 1: completeness and provenance

Require all seven quantiles, finite original-scale validation metrics, explicit
structured telemetry, matching scientific hashes, correct package hashes,
train/validation-only access, and no unresolved convergence failure.

### Gate 2: AL parity

Compare the new AL parity bundle with the frozen R62 AL bundle. Define

`tol = 1e-6 * max(1, abs(frozen_AL_AQL))`.

The same tolerance must be applied to component AQLs and the seven-quantile
mean. A mismatch blocks that case; it is evidence of data, adapter, scaling,
initialization, package, or metric drift. The tolerance must not be widened
after seeing results.

### Gate 3: three-way raw validation comparison

For a parity-valid case, compare exactly three whole-family bundles:

- frozen legacy AL;
- frozen legacy exAL;
- new structured exAL.

Use raw original-scale `seven_quantile_mean_AQL`. The new AL refit is a parity
control, not a fourth searched candidate. Select the minimum only if it improves
on the current R62 authority by more than the fixed tolerance. On a tie, retain
the current R62 authority. Never select a likelihood separately by quantile.

### Gate 4: family-separated synthesis audit

Assemble the seven independent prediction surfaces within each contemporaneous
family. If monotonicity repair is required, apply the same isotonic/PAVA rule
separately to AL and structured exAL and retain:

- raw predictions and raw AQL;
- adjusted predictions and adjusted AQL;
- crossing counts and adjustment magnitudes.

This is called assembly or postfit monotonicity repair, not a joint model and
not cross-family synthesis. The R65 primary family decision remains the raw R62-
compatible validation AQL. PAVA may diagnose usability, but it may not silently
reverse the primary winner.

### Gate 5: freeze winners before test

Write and hash the case decisions, rejected-candidate reasons, prediction
surfaces, package manifest, source manifest, and selection code. Only after this
freeze may a separate explicit action open test for audit.

## Test and promotion boundary

A validation winner is not automatically article-worthy. A later frozen test
audit must compare it on the same seven-quantile contract with both:

1. the current authoritative QDESN result for that region/fold; and
2. cached PriceFM.

Promotion requires lower aggregate test AQL than both references, complete
seven-quantile evidence, reproducibility/hash checks, and the established
per-quantile/horizon harm guard. The existing R48 policy used a 0.5% relative
harm margin; R65 should inherit that value only where the same comparison units
and rows are available, rather than invent a new post-result threshold. Any
noncomparable guard must block promotion pending an explicit contract decision.

MCMC is not part of R65. Whether a later article gate requires MCMC must be
decided after the independent VB authority is complete; it must not delay or
contaminate the validation-only VB comparison now.

Registry and article mutation remain false even after a test win until a
separate integration handoff approves exact rows, tables, figures, prose, and
source hashes.

## Storage and recovery design

The observed six-case R62 gap run used about 13 GiB because it retained 42
quantile-specific adapter copies. Approximately 11.7 GiB was repeated train and
validation design data. Sharing one adapter per case suggests a full-surface
planning footprint on the order of 30-35 GiB for adapter data, rather than well
over 200 GiB from naive sevenfold duplication. This is an estimate, not a quota.

The future preflight must calculate expected bytes from actual source cases and
require a conservative free-space reserve before launch. During the run:

- retain compact configs, metrics, traces, predictions, diagnostics, logs,
  manifests, and hashes;
- retain the normal anchor and completed fit states while recovery is possible;
- never clean an active or incomplete case;
- after closeout and hash freeze, delete only explicitly reconstructible adapter
  matrices or nonselected heavy fit states through a manifest-driven cleanup;
- preserve winner states, all prediction surfaces, and all scalar evidence;
- emit a before/after byte ledger and never use wildcard deletion.

## Reproducibility outputs

The completed R65 workflow should materialize, in separate preparation, run,
closeout, and test-audit roots:

- case manifest and 798-row component ledger;
- source and package hash manifests;
- preflight gates and resource snapshot;
- atomic per-component configs, predictions, metrics, traces, parameter
  summaries, and completion records;
- case-level AL parity report;
- convergence and restart ledger;
- raw crossing and PAVA adjustment diagnostics;
- three-way validation comparison and 114-row frozen decision authority;
- validation winner and blocked-case queues;
- storage ledger and cleanup eligibility manifest;
- JSON summary and human-readable Markdown report at every stage.

Every generated table must have a schema test, deterministic ordering, stable
case IDs, and explicit authorization booleans.

## Implementation sequence

### R65A: read-only design and runner validation

1. Implement a preparation script that reads only R62 authority artifacts and
   emits the 114-row case manifest, 798-row component ledger, gates, and hashes.
2. Implement a grouped independent runner around a reusable PriceFM helper,
   without changing the general QDESN, joint-QDESN, GloFAS, or validation code.
3. Pass the structured factorization profile explicitly and add unique method
   identities and telemetry.
4. Add unit fixtures for one case and all seven quantiles, including interrupted
   component recovery and hash mismatch behavior.
5. Add an R-focused test proving that the PriceFM Q-DESN path actually executes
   structured sigma-gamma updates rather than merely carrying metadata.
6. Add a parity fixture proving all AL quantiles initialize from the same normal
   anchor and each exAL fit from only its same-quantile AL state.

No production YAML or fit is produced in R65A.

### R65B: launch materialization after tests

Only after R65A tests pass, materialize a production config for exactly 114 case
jobs. Revalidate disk, memory, CPU ownership, immutable package source, runtime
paths, test firewall, and absence of overlapping PriceFM jobs. The launcher must
support bounded workers, one numerical thread per worker, atomic status files,
and completed-component skipping.

Materialization is not launch authorization.

### R65C: full independent VB run

After explicit user authorization, launch all 114 cases once. Monitor component
completion, convergence, adapter hashes, storage growth, and worker health.
Do not relaunch completed components and do not alter controls in response to
interim validation values.

### R65D: validation-only closeout

Run the five selection gates above, freeze 114 case decisions, and report legacy
AL, legacy exAL, and structured-exAL counts and gains. Test, registry, article,
joint, and MCMC remain blocked.

### R65E: separately authorized frozen test audit

Only after review of R65D, open test once for frozen winners, apply dual-reference
and harm gates, and produce an integration queue. No automatic mutation follows.

## Required tests before materialization

At minimum, focused tests must cover:

1. exact 114-case and 798-component coverage;
2. seven ordered quantiles per case with no duplicates;
3. exact inheritance of every case-specific R62 scientific contract;
4. no test paths or test-derived fields in preparation or selection;
5. immutable package commit and three source-file hashes;
6. explicit structured profile and observed structured update telemetry;
7. unique AL parity and structured-exAL method IDs;
8. one shared adapter and one normal anchor per case;
9. same-anchor AL and same-quantile AL-to-exAL initialization;
10. atomic completion and idempotent completed-component skipping;
11. corruption, missing-file, and hash-mismatch quarantine;
12. AL parity tolerance at component and bundle levels;
13. whole-bundle selection and current-authority tie retention;
14. separate family synthesis with no AL/exAL blending;
15. convergence quarantine and honest state-seeded restart labels;
16. authorization booleans remaining false;
17. deterministic CSV/JSON/Markdown generation;
18. no launch YAML from the read-only preparation mode.

## Stop conditions

Preparation or execution must stop, without improvising, if:

- R62 no longer resolves to 114 complete cases and 798 components;
- a scientific or feature-semantics hash conflicts;
- the detached package commit or source hashes differ;
- the structured path records zero required post-warmup updates;
- any test artifact is loaded before winner freeze;
- AL parity fails for a case;
- storage falls below the predeclared reserve;
- another PriceFM campaign overlaps the same output roots;
- a worker uses unexpected multithreaded numerical libraries;
- the runner cannot distinguish exact data targeting from approximate posterior
  inference;
- any script attempts registry, article, main, Overleaf, joint, or MCMC work.

## What would falsify this recommendation

The grouped full-surface plan should be reconsidered only if implementation
tests show that sharing an adapter or normal anchor changes the frozen AL result,
the pinned engine cannot expose verifiable structured-update telemetry, or the
measured grouped footprint exceeds the safe storage budget. In that event, the
correct response is to stop and diagnose, not to fall back silently to a partial
87-case campaign or a broader architecture search.

If structured exAL produces no meaningful validation improvements after passing
parity, that is a scientifically useful negative result. It would indicate that
the remaining PriceFM gap is unlikely to be solved by this posterior
factorization alone and would justify a later, separately preregistered decision
about `tau0`, likelihood/readout design, or case-specific architecture. It would
not justify retrospective threshold changes.

## Recommended next authorization

The next Codex task should implement **R65A only**: the read-only manifest
builder, grouped runner/helper, focused Python and R tests, explicit structured
telemetry, and no production launch artifact. After those tests and the measured
resource/storage preflight are reviewed, a separate prompt may authorize R65B
materialization and then the full R65C background launch.
