# PriceFM Stage-R62 matched seven-quantile authority roadmap

Date: 2026-08-26

Lane: PriceFM only

Branch: `work/pricefm-joint-quantile-20260824`

Audited HEAD: `9c41caa4a1bc5dfd1341fb14da0f52fa767b41b7`

Status: read-only audit and implementation roadmap; no launch authorized

## Executive decision

Stage-R60 is complete: all four repair arms finished with return code zero, all
four postfit summaries were materialized, no integrity failure was reported,
and test access remained closed. Neither target was rescued. `NO_5` fold 2
worsened relative to its existing R59 joint fit. `SE_2` fold 2 improved relative
to R59, but remained far behind a matched seven-quantile independent fit.

The more important audit finding is that the R57 comparison authority is not a
seven-quantile authority. All 114 source configurations contain only
`tau=0.5`; all 228 AL/exAL validation rows satisfy `AQL=MAE/2`, as expected for
a median-only fit. R57 then declared seven target quantiles while copying the
median `selection_metric_value` into its comparison column. In 30 of 114 cells,
that value also belongs to the other AL/exAL family rather than the family whose
configuration was transferred into R57.

Consequently, the R58/R59 statement that the joint model won in 112 of 114
cells is not scientifically usable. The joint fits themselves remain valid
seven-quantile model artifacts; their old win labels do not.

A read-only historical reconstruction found exact, semantically matched,
complete seven-quantile independent bundles for 108 of 114 cells. Preliminary
validation-only comparison against those bundles gives 11 joint wins, 62 joint
losses no larger than 1%, 29 losses between 1% and 5%, and 6 losses above 5%.
Six cells still lack an exact seven-quantile independent comparator.

The optimal next step is therefore Stage-R62: reconstruct and freeze the
matched seven-quantile independent authority before another joint launch. R61
mechanism code remains useful, especially for the two severe targets, but its
prepared launch and closeout gate must not be used until they consume the R62
authority. No R61 job should be launched from the currently materialized
manifest.

## Scope and boundaries

This roadmap is confined to PriceFM individual-versus-joint seven-quantile
modeling. It preserves the user's case-specific modeling objective: each region
and fold may retain its own information set, DESN geometry, likelihood family,
RHS prior scale, and final model decision. It does not seek one shared DESN
specification for all 114 cells.

The following remain blocked:

- test-set opening or test-adaptive selection;
- a new VB or MCMC launch;
- R61 launch-manifest authorization;
- model-registry mutation;
- article, table, figure, prose, or Overleaf mutation;
- cleanup of R57-R61 checkpoints or predictions;
- GloFAS, individual-validation, joint-validation, DQLM, or other-lane work;
- merge or push to `main`.

## Audited state

| Item | Current evidence | Decision |
|---|---:|---|
| R57 joint cells | 114/114 fit and postfit complete | Keep artifacts; invalidate old win labels |
| R57 source configs with seven quantiles | 0/114 | R57 comparator is not like-for-like |
| R57 source configs with median only | 114/114 | Confirmed |
| Median AL/exAL rows with `AQL=MAE/2` | 228/228 | Confirmed |
| R57 authority values matching declared source family | 84/114 | Confirmed |
| R57 authority values matching the other family | 30/114 | Family-transfer defect |
| R60 arms complete | 4/4 | Complete, no relaunch |
| R60 failed/integrity failures | 0/0 | Operationally clean |
| R60 validation winners under its old gate | 0 | Diagnostic only |
| R60 test opened | false | Firewall preserved |
| Historical exact seven-quantile matches | 108/114 | Sufficient to expose the authority defect |
| Exact seven-quantile coverage gaps | 6/114 | Must be filled or explicitly unresolved |
| Preliminary corrected joint wins | 11/108 | Candidate queue, not promotion |
| R61 prepared arms | 14, seven per severe target | Keep blocked; rebase gate on R62 |
| R61 model processes/artifacts | none | No R61 launch occurred |

Runtime evidence is stored under the historical artifact repository
`/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm`. Code
and tracked documentation are owned by the dedicated Version-2 worktree
`/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_joint_quantile_20260824`.

## Why the earlier authority is invalid

`200_freeze_pricefm_stage_r57_joint_authority.py` performs two separate actions
that were individually plausible but jointly incompatible:

1. It matches the Stage-R8 atlas to the full-surface registry using
   `qdesn_method_id` and recovers the corresponding median experiment config.
2. It manually declares the seven paper quantiles for the new joint fit while
   copying `selection_metric_value` from the old registry into
   `current_authoritative_validation_AQL`.

The copied value is a median validation AQL, not an AQL aggregated over the
seven paper quantiles. A median-only pinball loss is exactly one half of median
MAE, which is why every historical source row satisfies `AQL=MAE/2`. A joint
seven-quantile AQL cannot be compared to that value.

The upstream full-surface registry introduces a second defect. It uses a method
identifier carried by the test-comparison surface while retaining a validation
selection value that may have been supplied by the other family. R57's
one-to-one region/fold and hash gates verify file identity, but they do not
verify that the metric, quantile set, and method family describe the same fit.
This produced 30 family/value mismatches:

| Registry source class | Mismatched cells |
|---|---:|
| `stage_m` | 17 |
| `current_r3q` | 13 |
| provenance bridge | 0 |

This is a comparison-contract failure, not evidence that the R57 joint
implementation or its saved predictions are corrupt.

## R60 closeout diagnosis

The completed R60 values below use the method-specific joint row, not the first
row of a mixed method summary. Earlier preliminary values `6.013881` and
`7.357404` were naive-baseline rows accidentally read as joint rows and are
superseded.

| Case | Comparator/arm | Validation AQL | Interpretation |
|---|---|---:|---|
| `NO_5` fold 2 | matched independent 7Q exAL | 4.885547 | corrected provisional comparator |
| `NO_5` fold 2 | R59 joint contract | 6.183849 | existing joint fit |
| `NO_5` fold 2 | R60 warm contract | 6.382036 | best R60 arm; 3.20% worse than R59 |
| `NO_5` fold 2 | R60 cold contract | 6.413125 | worse than warm and R59 |
| `SE_2` fold 2 | matched independent 7Q exAL | 4.805428 | corrected provisional comparator |
| `SE_2` fold 2 | R59 joint contract | 13.624549 | existing joint failure |
| `SE_2` fold 2 | R60 cold contract | 12.486075 | 8.36% better than R59, still 159.83% worse than independent |
| `SE_2` fold 2 | R60 warm contract | 12.774108 | stable numerically, poor scientifically |

All four R60 checkpoints, scientific-spec hashes, source-manifest hashes, and
split firewalls verified. R60 therefore answers its narrow question: longer
continuation and a core-plus-RHS restart are not sufficient rescues. The cold
extended `SE_2` result shows some optimizer sensitivity, but not enough to
justify test access or MCMC confirmation.

## Preliminary matched seven-quantile reconstruction

The audit scanned historical `authoritative/*/panel_status.csv` and
`panel_metric.csv` artifacts, grouped exactly seven complete quantile runs, and
matched them to the R57 source contract after semantic type normalization.
Matching included region/fold, information-set policy, graph degree where
applicable, lag and lead windows, DESN feature map and geometry, reservoir
hyperparameters, state output, seed, RHS `tau0`, training-origin controls, and
split-boundary semantics. Numeric YAML strings and numeric YAML scalars were
treated as equivalent.

The provisional corrected surface is:

| Queue | Rule on `(joint AQL - independent AQL) / independent AQL` | Cells |
|---|---|---:|
| Existing joint validation win | `< 0` | 11 |
| Near loss | `0` through `1%` | 62 |
| Moderate loss | above `1%` through `5%` | 29 |
| Severe loss | above `5%` | 6 |
| Exact comparator missing | no exact complete bundle | 6 |

The 11 provisional joint-win cells are:

- `NO_4` fold 2;
- `DK_2` fold 3;
- `FI` folds 1 and 2;
- `DK_1` fold 2;
- `SE_3` fold 1;
- `NO_1` fold 2;
- `NO_2` fold 3;
- `SE_1` fold 2;
- `ES` fold 3;
- `NO_3` fold 2.

The six exact-comparator gaps are:

- `AT` fold 2;
- `BG` folds 1, 2, and 3;
- `FI` fold 3;
- `PL` fold 2.

Among the 108 matched cells, validation-only aggregate seven-quantile selection
prefers exAL in 83 and AL in 25. That selected family differs from the R57 joint
family in 26 cells. Those 26 cells require explicit review because the joint
campaign did not inherit the family selected by the corrected seven-quantile
authority.

These counts are audit findings, not yet a frozen replacement registry. The
production R62 implementation must independently reproduce them and apply
stronger feature-schema and provenance checks before any downstream decision.

## Unified execution plan

### Phase 0: freeze the completed evidence

1. Treat R57-R60 run artifacts as immutable inputs.
2. Record the terminal R60 launch status, four job-summary hashes, four metric
   hashes, and closeout hashes.
3. Mark the old R58/R59 `112/114` win count as superseded for selection and
   promotion, while retaining it as historical provenance.
4. Keep R61 code and blocked artifacts, but prohibit use of its current
   `current_authoritative_validation_AQL` gate.
5. Keep test, MCMC, registry, and article flags false.

### Stage-R62A: reconstruct the independent seven-quantile authority

Implement one read-only script and focused tests. The proposed script is
`application/scripts/pricefm/216_reconstruct_pricefm_stage_r62_matched_seven_quantile_authority.py`.
It must:

1. discover complete historical seven-quantile bundles without relying only on
   experiment names;
2. require exactly the paper quantiles
   `[0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]`;
3. normalize YAML numeric strings before comparison;
4. fingerprint the full data window, split boundaries, feature policy, adapter
   feature schema, graph contract, DESN geometry, seed, training controls, and
   `tau0`;
5. verify the seven component configurations share one scientific fingerprint;
6. recompute or independently verify aggregate original-scale validation AQL;
7. select AL versus exAL using aggregate seven-quantile validation AQL only;
8. deduplicate repeated summaries only when metrics and scientific hashes agree;
9. flag conflicting provenance rather than choosing silently;
10. emit no test metric and read no test value for selection;
11. never write launch YAML or mutate an existing authority.

Required outputs under a new authoritative runtime directory are:

- `pricefm_stage_r62_candidate_bundle_ledger.csv`;
- `pricefm_stage_r62_matched_seven_quantile_authority.csv`;
- `pricefm_stage_r62_exact_coverage_gaps.csv`;
- `pricefm_stage_r62_family_corrections.csv`;
- `pricefm_stage_r62_corrected_joint_comparison.csv`;
- `pricefm_stage_r62_mechanism_queues.csv`;
- `pricefm_stage_r62_gates.csv`;
- `source_manifest.csv`;
- `summary.json`;
- a generated Markdown audit report.

The authority remains provisional until all 114 cells pass. The six missing
cells must not be filled with median values or nearest-neighbor specifications.

### Stage-R62B: fill only genuine coverage gaps

If Stage-R62A confirms the same six gaps, prepare a separate, launch-blocked
manifest that replays each missing case's exact individual specification at all
seven quantiles. One configuration should fit both AL and exAL where the current
runner contract permits it. This is at most 42 quantile jobs, not another broad
DESN screen.

Before a later launch, require exact config/hash parity, validation-only output,
one process per assigned free core, resumability, and cleanup rules that retain
predictions and metrics while removing only nonselected heavy state after
closeout. This roadmap does not authorize that launch.

### Stage-R62C: freeze the corrected full surface

After all 114 cells have exact independent bundles:

1. freeze one AL/exAL seven-quantile validation winner per region/fold;
2. compare the existing joint R59 contract AQL like-for-like;
3. classify existing joint wins, near losses, moderate losses, severe losses,
   family-transfer mismatches, instability, and crossing adjustments;
4. record selected independent and joint checkpoint/prediction hashes;
5. freeze the next-experiment queue before opening any test artifact.

### Stage-R63: bounded case-specific joint follow-up

The corrected surface, not the old two-row gate, determines the next launch.
The launch should remain case-specific:

- preserve existing joint wins unless a reproducibility check fails;
- rerun cells whose corrected seven-quantile family differs from the R57 family
  using the corrected family and the same case-specific DESN/information set;
- use the R61 RHS initialization and independent-training initializer mechanisms
  for severe or mechanistically compatible failures;
- prioritize near losses only when a specific mechanism is supported, because
  62 cells are already within 1% and a blanket grid would be wasteful;
- retain the independent model for cells where joint modeling does not improve
  validation evidence.

R61's current 14-row manifest must be regenerated from the corrected authority;
its hashes and closeout baseline cannot simply be edited in place. The two R61
targets remain valuable severe-failure cases, but they are not the complete
corrected failure surface.

### Validation-only winner gate

A joint VB candidate may enter confirmation only when all of the following hold:

1. exact region/fold scientific fingerprint parity is verified;
2. all seven quantiles are present and finite;
3. original-scale validation AQL beats the corrected independent seven-quantile
   authority;
4. the comparison uses one preregistered scoring contract;
5. raw and monotone-contract roles are both reported;
6. convergence and crossing diagnostics pass the declared stability guard;
7. no test value participated in design, fitting, selection, tie-breaking, or
   continuation;
8. source, config, prediction, metric, and checkpoint hashes verify.

An improvement over the old median comparator is irrelevant to this gate.

### MCMC confirmation

MCMC is reserved for validation-selected joint winners, not for repairing poor
VB candidates. Freeze the VB winner before MCMC and before test access.

- Initialize the complete joint MCMC state from the selected full-state VB v2
  checkpoint.
- Use joint AL Gibbs for AL winners.
- Use the collapsed exAL `M0_v_collapsed_support_logit` update for exAL winners.
- Preserve the selected case-specific information set, DESN geometry, seven
  quantiles, and RHS prior contract.
- Require multiple deterministic chains, explicit seeds, effective sample size,
  split-Rhat, divergence/numerical diagnostics, checkpoint hashes, and
  validation agreement with the VB candidate.
- Do not replace a failed MCMC confirmation using test information. A failure
  returns the cell to diagnosis or retains the independent authority.

### Sealed test and article gate

Only after validation selection and MCMC confirmation are frozen may a single
sealed test audit compare the candidate with both:

1. the corrected independent seven-quantile Q-DESN/exQDESN authority; and
2. cached PriceFM under the same fold, horizons, quantiles, unit, and AQL
   definition.

Registry or article promotion requires beating both references on the declared
test gate, complete seven-quantile predictions, reproducible hashes, acceptable
crossing behavior, and a frozen provenance manifest. Cells that do not pass
remain independent-authority or PriceFM-favored cases. The article should report
heterogeneous case-level outcomes rather than imply uniform superiority.

## Stage-R62 acceptance gates

| Gate | Required result |
|---|---|
| Unique surface | exactly 114 region/fold rows |
| Quantile contract | exactly seven paper quantiles per family bundle |
| Metric contract | original-scale validation AQL over the same seven quantiles |
| Scientific parity | data, information set, DESN, seed, training, and `tau0` match |
| Feature parity | adapter feature names/order or a verified semantic schema hash match |
| Family selection | AL/exAL chosen on aggregate seven-quantile validation only |
| Duplicate provenance | identical metric and hashes, otherwise blocked |
| Test firewall | no test fields in selection outputs; `test_opened=false` |
| Integrity | all source/config/metric/prediction hashes verify |
| Mutation | registry/article/MCMC/launch all false |

## Reproducibility ledger

Primary evidence checked:

- `application/data_local/pricefm/authoritative/pricefm_stage_r57_joint_authority_freeze_20260824/pricefm_stage_r57_joint_case_authority.csv`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r59_joint_scoring_contract_20260826/pricefm_stage_r59_joint_scoring_decisions.csv`;
- `application/data_local/pricefm/experiment_grids/pricefm_stage_r60_joint_repair_20260826/launch_status.csv`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r60_joint_repair_postfit_20260826/summary.json`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r60_joint_repair_closeout_20260826/pricefm_stage_r60_joint_repair_arm_metrics.csv`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r60_joint_repair_closeout_20260826/pricefm_stage_r60_joint_repair_case_decisions.csv`;
- all historical `application/data_local/pricefm/authoritative/*/panel_status.csv` and matching `panel_metric.csv` files;
- all R57 source model and data configurations referenced by the frozen authority;
- `application/scripts/pricefm/200_freeze_pricefm_stage_r57_joint_authority.py`;
- historical `application/scripts/pricefm/114_closeout_pricefm_full_surface_decision_registry.py`.

Read-only checks performed:

```bash
git status -sb
git branch --show-current
git rev-parse HEAD
ps -eo pid,ppid,etimes,%cpu,%mem,rss,nlwp,stat,cmd --sort=-%cpu
tmux ls
jq . application/data_local/pricefm/authoritative/pricefm_stage_r60_joint_repair_monitor_20260826/summary.json
sed -n '1,20p' application/data_local/pricefm/experiment_grids/pricefm_stage_r60_joint_repair_20260826/launch_status.csv
```

The semantic historical scan was ephemeral and wrote no artifact. Its counts
must be reproduced by the tested Stage-R62 implementation before they are used
as authority.

## Do not do yet

- Do not keep waiting for R60; it is complete.
- Do not relaunch R60.
- Do not launch the currently prepared R61 grid.
- Do not use `112/114` as evidence of joint superiority.
- Do not compare seven-quantile joint AQL with median-only AQL.
- Do not fill the six gaps with approximate configurations.
- Do not open test to decide which family, mechanism, or DESN to fit.
- Do not launch MCMC for a VB validation loser.
- Do not mutate the PriceFM registry or any article asset.
- Do not clean R57-R61 heavy artifacts before R62 pins the required evidence.

## Final recommendation

Implement and validate Stage-R62A as a read-only authority reconstruction next.
If it reproduces the 108 exact matches and six gaps, prepare but do not
automatically launch the six-cell exact quantile completion. Only after a full
114-cell seven-quantile authority is frozen should the project regenerate a
case-specific R61/R63 launch contract. This sequence is cheaper than another
broad grid, repairs the comparison at its foundation, preserves the test
firewall, and still supports the intended joint-model and MCMC confirmation
path wherever validation evidence justifies it.
