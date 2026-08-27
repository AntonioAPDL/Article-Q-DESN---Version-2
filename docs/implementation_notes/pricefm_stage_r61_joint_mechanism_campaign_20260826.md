# PriceFM Stage-R61 joint-mechanism campaign

Date: 2026-08-26

Lane: PriceFM only

Branch: `work/pricefm-joint-quantile-20260824`

Audited pre-implementation HEAD: `9c41caa4a1bc5dfd1341fb14da0f52fa767b41b7`

Status: implemented, validated, and materialized; production launch is blocked
pending the Stage-R62 matched seven-quantile authority reconstruction

## Post-R60 correction and supersession notice

Stage-R60 subsequently completed all four arms with no execution or integrity
failure and with test access still closed. Neither case was rescued.

More importantly, a post-R60 audit established that the R57 comparison column
is median-only rather than seven-quantile: all 114 transferred source configs
contain only `tau=0.5`, and 30 rows pair the copied validation value with the
other AL/exAL family. The R58/R59 `112/114` win statement and the R61
`current_authoritative_validation_AQL` gate are therefore not valid
seven-quantile promotion evidence.

The R61 mechanism implementation and tests remain useful. Its targets remain
severe joint failures under a preliminary matched seven-quantile audit. Its
prepared manifest must nevertheless remain blocked and its closeout gate must
be regenerated from Stage-R62 before any launch. The current scientific roadmap
is documented in
`pricefm_stage_r62_matched_seven_quantile_authority_roadmap_20260826.md`.

## Executive conclusion

The PriceFM joint-quantile effort is not waiting on a broader DESN capacity
grid. The two unresolved cases already use DESN specifications that perform
well when fitted as individual quantile models. Their joint fits fail on
validation after reusing the same region/fold-specific information set and
DESN geometry. The leading unresolved question is therefore how the joint
optimizer, cross-quantile RHS prior, initialization, and likelihood interact.

Stage-R61 is a bounded mechanism campaign for exactly `NO_5` fold 2 and
`SE_2` fold 2. It prepares seven case-specific arms per unresolved case and
reuses Stage-R60 as the unchanged continuation reference. It does not create a
shared specification across cases. It does not use test outcomes to design or
select an arm. It does not launch MCMC, mutate the model registry, or update the
article.

The implementation separates the RHS prior scale from its numerical starting
scale, adds a finite RHS warm-up freeze, supports an initializer built from
training-only independent quantile fits, preserves exact continuation state,
and emits block-level diagnostics. These are mechanisms the previous joint
runner could not isolate cleanly.

No Stage-R61 model is to be launched as part of this implementation. A later
launch requires all of the following: Stage-R60 closeout, pruning of any case
already resolved by R60, a fresh CPU ownership audit, explicit user
authorization, and verification that the manifest still has test access set to
false.

## Scope and hard boundaries

In scope:

- PriceFM individual-versus-joint evidence for the two unresolved cases;
- joint AL and structured exAL VB mechanism controls;
- validation-only R61 planning, runner, monitoring, repair, and closeout code;
- reproducible, launch-blocked configuration artifacts;
- focused R and Python tests.

Out of scope:

- GloFAS, individual validation, joint validation, DQLM, or other scientific lanes;
- any running Stage-R60 process or artifact mutation;
- test-set evaluation;
- MCMC fitting;
- model-registry mutation;
- manuscript, table, figure, or Overleaf mutation;
- merge to `main`, article publication, or production launch.

## Audited current state

The audit used the dedicated PriceFM worktree and the historical runtime store:

- code worktree: `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_joint_quantile_20260824`;
- runtime store: `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm`;
- branch and upstream: `work/pricefm-joint-quantile-20260824` and
  `origin/work/pricefm-joint-quantile-20260824`;
- pre-implementation branch state: clean and synchronized at `9c41caa`.

### Stage-R60 health snapshot

At the initial 2026-08-26 R61 audit snapshot, Stage-R60 remained healthy and
incomplete. It has now completed cleanly.

| Item | Observed |
|---|---:|
| Expected R60 arms | 4 |
| Fit-artifact complete | 4 |
| Postfit complete | 4 |
| Pending/running | 0 |
| Failed and unrepairable | 0 |
| Integrity failures | 0 |
| Test opened | false |

The former `SE_2` fold-2 cold extended process exited with return code zero.
There is no remaining R60 model process or tmux session. R61 did not stop,
restart, or alter the run.

Available R60 raw validation summaries were:

| Case | R60 arm | Raw validation AQL | Current individual authority AQL |
|---|---|---:|---:|
| `NO_5` fold 2 | cold extended | 6.780440 | 5.834527 |
| `NO_5` fold 2 | core+RHS warm restart | 6.761796 | 5.834527 |
| `SE_2` fold 2 | cold extended | 12.527540 | 5.360348 |
| `SE_2` fold 2 | core+RHS warm restart | 12.817927 | 5.360348 |

These are the corrected method-specific raw joint rows. The earlier values
`6.013881` and `7.357404` came from naive-baseline rows in mixed method
summaries. R60's monotone-contract values and the corrected matched
seven-quantile comparison are reported in the Stage-R62 roadmap. Neither the
raw rows nor the old median comparator may be promoted or used to open test.

## Historical evidence hierarchy

R61 was originally designed using evidence in this order:

1. Stage-R59 freezes the primary selection rule as original-scale validation
   AQL after the monotone prediction contract.
2. Stage-R57 transfers the region/fold-specific median DESN/information-set
   contract and was originally treated as an individual authority.
3. Stage-R60 provides continuation and cold-reference evidence without being
   duplicated in R61.
4. The Stage-R8 historical atlas supplies one validation-backed DESN fallback
   per unresolved case.
5. Test metrics, PriceFM test metrics, article outcomes, and post-selection
   MCMC are excluded from R61 design and selection.

The ordering remains useful for provenance, but items 1 and 2 cannot supply the
promotion comparator. Stage-R62 must replace it with an aggregate
seven-quantile validation authority.

## What the earlier stages established

### Historical median source contract

| Case | Transferred likelihood | Information set | DESN | RHS prior `tau0` | Median validation AQL |
|---|---|---|---|---:|---:|
| `NO_5` fold 2 | AL | target only | D=1, units=[120], m=96, alpha=0.5, rho=0.9, input=0.25 | 0.001 | 5.834527 |
| `SE_2` fold 2 | exAL | target only | D=2, units=[80,80], m=96, alpha=0.5, rho=0.9, input=0.20 | 0.001 | 5.360348 |

These specifications were selected per region and fold, but the displayed AQLs
are median-only. R61 preserves the case-specific principle; Stage-R62 must
reselect the likelihood family on aggregate seven-quantile validation AQL.

### Initial joint failure under the superseded comparator

The R59 contract audit showed:

| Case | Joint contract validation AQL | Delta versus old median comparator | Stability |
|---|---:|---:|---|
| `NO_5` fold 2 | 6.183849 | +0.349321 | unstable |
| `SE_2` fold 2 | 13.624549 | +8.264200 | explosive |

The deltas in this table are not like-for-like and cannot support selection.
The Stage-R62 preliminary audit nevertheless confirms that both cases are
severe joint failures against exact seven-quantile independent bundles, so the
mechanism diagnosis remains scientifically relevant.

## RHS scale diagnosis

`tau0` and the initialized global scale are different quantities:

- `tau0` is the fixed half-Cauchy scale in the RHS hierarchy;
- `tau` is the fitted global shrinkage state;
- `initial_tau` is only the numerical state from which that hierarchy starts;
- `rhs_freeze_iters` determines how long the numerical start remains fixed.

The individual PriceFM fitter used `tau0=0.001`, initialized the fitted global
scale near 1, froze it for five iterations, and then adapted it. The previous
joint implementation initialized `tau` at `tau0` and updated it immediately.
With `tau0=0.001`, that is a materially different optimization path and can
trap the joint fit in a poor basin. R61 makes prior and initialization scales
explicit for the anchor and innovation blocks separately.

This is not a conventional scalar `tau0` screen. It first asks whether the
joint implementation reaches a useful basin when given parity with the
individual numerical warm-up and when innovation shrinkage is controlled
independently.

## Ranked mechanism hypotheses

| Rank | Mechanism | Evidence | R61 identification arm |
|---:|---|---|---|
| 1 | RHS initialization/warm-up mismatch | Previous joint tau began at the tiny prior scale and updated immediately | `all_blocks_tau1_freeze5`, `joint_safe_tau_start` |
| 2 | Poor joint coefficient basin | Warm continuation did not rescue validation and can preserve the same basin | `training_only_independent_quantiles` |
| 3 | Innovation shrinkage miscalibration | One shared scale confounded anchor shrinkage with cross-quantile differences | strong/weak innovation `tau0` arms |
| 4 | Joint likelihood instability | `SE_2` exAL is especially explosive; `NO_5` AL is a smaller miss | `alternate_likelihood` |
| 5 | Joint-specific DESN geometry | Same DESN works individually, but an alternative historical geometry may condition the joint update better | `historical_desn_fallback` |
| 6 | More generic capacity is needed | Historical and current evidence does not support this as the first diagnosis | explicitly excluded |

## Exact R61 campaign

Each unresolved case receives the following seven arms. Stage-R60 remains the
reference and is not run again.

| Arm | Scientific question | Anchor prior/start | Innovation prior/start | Freeze | Initialization |
|---|---|---|---|---:|---|
| `all_blocks_tau1_freeze5` | Does individual-style tau initialization restore parity? | 0.001 / 1.0 | 0.001 / 1.0 | 5 | controlled cold |
| `joint_safe_tau_start` | Does a smaller innovation start stabilize the joint path? | 0.001 / 1.0 | 0.001 / 0.05 | 5 | controlled cold |
| `training_only_independent_quantiles` | Is the joint coefficient basin the primary failure? | 0.001 / 1.0 | 0.001 / 0.05 | 5 | independent VB mapping |
| `innovation_tau0_strong_0p0005` | Does stronger cross-quantile coupling help? | 0.001 / 1.0 | 0.0005 / 0.05 | 5 | controlled cold |
| `innovation_tau0_weak_0p005` | Does weaker cross-quantile coupling help? | 0.001 / 1.0 | 0.005 / 0.05 | 5 | controlled cold |
| `alternate_likelihood` | Is failure likelihood-specific? | 0.001 / 1.0 | 0.001 / 0.05 | 5 | controlled cold |
| `historical_desn_fallback` | Is the authority DESN poorly conditioned for a joint update? | 0.001 / 1.0 | 0.001 / 0.05 | 5 | controlled cold |

All arms use `rhs_vb_inner=5`, `max_iter=150`, `tol=1e-4`, the seven paper
quantiles, and train/validation only.

The alternate-likelihood arm uses exAL for `NO_5` and AL for `SE_2`.

### Historical fallbacks

| Case | Experiment | Likelihood | DESN | Historical validation AQL |
|---|---|---|---|---:|
| `NO_5` fold 2 | `covm_no5_f2_target_d2_n080x080_s035` | AL | D=2, units=[80,80], alpha=0.4, rho=0.9, input=0.35 | 5.900152 |
| `SE_2` fold 2 | `depthcore_d2_ultracompact_input_scale0p5` | exAL | D=2, units=[40,40], alpha=0.4, rho=0.9, input=0.50 | 5.539847 |

These fallbacks are not claimed to beat the authority. They are the closest
bounded, historically validated alternatives that alter conditioning without
introducing a large capacity grid.

## Explicitly excluded designs

- Full Cartesian capacity grid: too expensive and does not isolate the joint
  failure mechanism.
- Shared scalar `tau0` sweep: confounds anchor shrinkage and cross-quantile
  innovation shrinkage.
- Graph feature screen: both current individual authorities are target-only,
  and prior `NO_5` graph validation was worse.
- Large-D/large-n screen: same geometry already succeeds individually, while
  earlier large alternatives did not provide the needed validation evidence.
- Test-adaptive selection: invalidates the frozen validation-only contract.
- Same R60 arms: their evidence is reused, not duplicated.

## Implementation wiring

### Core inference controls

`application/R/joint_qvp_qdesn.R` now supports:

- `anchor_tau0` and `innovation_tau0` as separate prior scales;
- `anchor_init_tau` and `innovation_init_tau` as separate numerical starts;
- `rhs_freeze_iters` evaluated against a global iteration counter;
- exact continuation through `iterations_completed`;
- per-block diagnostics containing prior scale, initial scale, current scale,
  update status, and global iteration.

`application/R/joint_exqdesn_exact_structured_inference.R` consumes the same
controls. Structured exAL can inherit the AL bootstrap RHS state when explicitly
requested, and its freeze is also based on the global iteration.

### Training-only independent initializer

`application/R/pricefm_joint_quantile_inference.R` can fit one AL/exAL VB model
per quantile on training data, map their slope means and block-diagonal
covariances into joint coordinates, and use isotonic projection only to produce
an ordered intercept initialization. This is an initializer, not a post-hoc
prediction synthesis. The subsequent prediction and validation metric come
from one joint model fit.

### Stage scripts

| File | Role | Can launch models? |
|---|---|---|
| `212_prepare_pricefm_stage_r61_joint_mechanism_campaign.py` | Audit inputs and materialize 14 blocked case configs | no |
| `213_run_pricefm_stage_r61_joint_mechanism_case.R` | Execute one explicitly authorized train/validation arm | one case only; not invoked by prep |
| `214_closeout_pricefm_stage_r61_joint_mechanism_campaign.py` | Validation-only integrity audit and selection | no |
| `215_monitor_pricefm_stage_r61_joint_mechanism_campaign.py` | Monitor, postfit-repair, and close out completed arms | no model fitting |

The generic launcher is referenced only inside the blocked launch contract. It
is never called by the prep script.

## Artifact contract

The prep stage materializes code-free runtime artifacts under the historical
PriceFM runtime store:

- prep evidence:
  `application/data_local/pricefm/authoritative/pricefm_stage_r61_joint_mechanism_campaign_prep_20260826`;
- launch-blocked grid:
  `application/data_local/pricefm/experiment_grids/pricefm_stage_r61_joint_mechanism_campaign_20260826`;
- reserved run root:
  `application/data_local/pricefm/runs/pricefm_stage_r61_joint_mechanism_campaign_20260826`.

The prep evidence includes:

- arm contract;
- case diagnosis;
- historical fallback evidence;
- excluded-design ledger;
- prelaunch gates;
- blocked launch contract;
- source hash manifest;
- JSON summary and Markdown report.

Every launch-manifest row has:

- `launch_authorized=false`;
- `test_access_authorized=false`;
- `status=prepared_blocked_pending_r60_and_user_authorization`;
- a scientific specification hash;
- its own region/fold/arm runtime and adapter config.

## Future launch gate

R61 may be launched later only if all conditions pass immediately before a new
launcher command is formed:

1. R60 has reached terminal closeout.
2. Stage-R62 has frozen a matched seven-quantile independent authority.
3. The R61 configs, manifest, and closeout baseline have been regenerated from
   that corrected authority rather than edited in place.
4. Any case resolved by the corrected audit is removed from R61 rather than rerun.
5. The remaining manifest retains exactly seven preregistered arms per still
   unresolved case.
6. All configs allow exactly `train` and `val`.
7. No row authorizes test, MCMC, registry, or article access.
8. Source hashes and scientific-spec hashes match the regenerated prep artifacts.
9. Active CPU ownership is audited again across PriceFM and other lanes.
10. Only genuinely free CPUs are assigned, with one model process and one
   numerical thread per CPU.
11. The user explicitly authorizes the production launch.

Condition 1 now passes. Conditions 2, 3, and 11 do not; the current manifest
therefore must not launch.

## Validation and selection contract

After a future authorized run:

1. all expected run artifacts must be terminal and hash-verifiable;
2. postfit repair recreates the R59 monotone prediction contract;
3. selection uses only original-scale validation AQL for that contract;
4. raw joint AQL is diagnostic, not the primary selection role;
5. ranking ties break by final numerical change, then complexity rank, then arm ID;
6. a validation candidate must beat the matched independent seven-quantile
   authority frozen by Stage-R62;
7. a candidate with `final_max_change > 1` or positive last-five change slope
   enters exact continuation, not test audit;
8. a stable validation winner can enter a sealed-test-audit proposal queue;
9. that queue still has `test_access_authorized=false` and needs a separate
   explicit authorization;
10. MCMC, registry, and article eligibility remain false until later gates pass.

If neither case has a stable validation winner, the correct result is to retain
the individual authority and stop expanding this joint parameterization. A
failed R61 is scientifically informative: it would rule out warm-up,
initialization, bounded innovation shrinkage, likelihood swap, and the two
historical geometries as sufficient joint rescues.

## Storage and interruption safety

- R61 prep creates small YAML/CSV/JSON/Markdown artifacts only.
- A future runner writes a v2 checkpoint before postfit summarization.
- The monitor can repair a terminal fit whose summarizer failed without
  refitting it.
- Adapter matrices are removed only after durable postfit artifacts and hashes
  exist; manifests, feature maps, diagnostics, predictions, metrics, and the
  selected checkpoint are retained.
- Existing R60 artifacts and processes are never cleaned by R61.
- Ambiguous or non-PriceFM artifacts are never touched.

## Reproducible validation commands

Run from the dedicated PriceFM worktree:

```bash
Rscript -e 'files <- c("application/R/joint_qvp_qdesn.R", "application/R/joint_exqdesn_exact_structured_inference.R", "application/R/pricefm_joint_quantile_inference.R", "application/scripts/pricefm/213_run_pricefm_stage_r61_joint_mechanism_case.R"); invisible(lapply(files, parse))'
Rscript application/tests/test_pricefm_stage_r61_joint_mechanism_controls.R
Rscript application/tests/test_pricefm_joint_quantile_continuation.R
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python -m pytest -q application/tests/test_pricefm_stage_r61_joint_mechanism_campaign.py application/tests/test_pricefm_stage_r59_r60_joint_repair.py
git diff --check
```

The prep command may be run only after these focused tests pass. It materializes
blocked artifacts and does not invoke the launcher:

```bash
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python application/scripts/pricefm/212_prepare_pricefm_stage_r61_joint_mechanism_campaign.py
```

Do not run `203_launch_pricefm_stage_r57_joint_vb.py` as part of this stage.

### Validation result

The 2026-08-26 implementation pass completed with:

| Check | Result |
|---|---|
| Modified/new R source parse | passed, 4 files |
| Stage-R61 numerical mechanism controls | passed |
| Existing PriceFM exact continuation | passed |
| Existing PriceFM compact joint kernel | passed |
| Existing structured exAL inference | passed |
| Existing exAL dispatch | passed |
| R61 plus R59/R60 Python contract suite | `8 passed` |
| R61 prep-only rerun after warning cleanup | passed |

The materialized package contains 14 manifest rows, seven rows for each target,
the exact preregistered arm set, all prelaunch gates passing, and all launch and
test flags false. The reserved R61 run root contains zero model files. Process
inspection found no R61 runner, launcher, monitor, or closeout process.

## Evidence ledger

Primary audited inputs:

- `application/data_local/pricefm/authoritative/pricefm_stage_r57_joint_authority_freeze_20260824/pricefm_stage_r57_joint_case_authority.csv`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r59_joint_scoring_contract_20260826/summary.json`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r59_joint_scoring_contract_20260826/pricefm_stage_r59_joint_scoring_decisions.csv`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r60_joint_repair_monitor_20260826/summary.json`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r60_joint_repair_monitor_20260826/pricefm_stage_r60_joint_repair_health.csv`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r8_specification_atlas_quantile_seed_contract_20260706/pricefm_stage_r8_specification_atlas.csv`;
- Stage-R57 and Stage-R60 launch manifests and per-case configs;
- individual AL/exAL runner and RHS prior implementations;
- joint AL and structured exAL VB implementations.

The generated R61 source manifest records SHA-256 hashes for all materialized
configs, all frozen upstream evidence, and all R61 code sources.

## Decision

R61 remains a useful bounded mechanism diagnosis because it changes one
scientifically interpretable joint mechanism at a time. It is not the immediate
next stage: Stage-R62 must first repair the seven-quantile comparison authority
and reclassify the full surface. The current R61 artifacts remain
launch-blocked pending that reconstruction and a separate user launch decision.
