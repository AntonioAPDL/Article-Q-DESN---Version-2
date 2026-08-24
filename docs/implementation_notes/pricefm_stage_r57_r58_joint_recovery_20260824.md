# PriceFM Stage-R57/R58 joint-quantile recovery and decision plan

## Scope and authority

This note unifies the PriceFM joint-quantile plan after the live Stage-R57 audit
on 2026-08-24. It covers only the PriceFM lane on branch
`work/pricefm-joint-quantile-20260824`. Runtime artifacts remain in the historical
artifact workspace at `/data/jaguir26/local/src/Article-Q-DESN`; reproducibility
code belongs in the dedicated Version-2 worktree. GloFAS, individual/joint
validation, registry, manuscript, `main`, and Overleaf are out of scope.

The frozen scientific surface has 114 region/fold cells. Every cell retains its
own validation-selected DESN geometry, lag window, feature policy, local or graph
information set, likelihood family, and RHS-NS scale. There is no global DESN
specification. The surface contains 27 AL and 87 exAL cells, all using the seven
quantiles `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`. Stage-R57 inherits
`tau0=0.001`; it is not a tau0 search.

## Executive decision

Continue the existing Stage-R57 fit campaign. Do not stop, relaunch, or discard
its completed fits. The workers are CPU-active and the partial scientific signal
is strong. Repair terminal cases in place without refitting, preserve raw joint
outputs, add the repository-standard deterministic monotone contract as a second
auditable prediction role, and use Stage-R58 to freeze the full validation-only
decision surface.

MCMC, the sealed test ledger, registry mutation, and article mutation remain
blocked. A maximum-iteration VB fit or a raw crossing is a review signal, not by
itself proof that the saved finite VB initializer is unusable.

## Audited live state

The pre-repair snapshot was taken while the original eight-worker launcher was
still active. Counts can advance after this snapshot.

| Quantity | Audited value |
| --- | ---: |
| Frozen region/fold cases | 114 |
| AL / exAL cases | 27 / 87 |
| Fit-artifact-complete cases inspected | 32 |
| Active workers | 8 |
| Queued after the 32 complete and 8 active | 74 |
| Complete cases improving frozen validation AQL | 32 / 32 |
| Median relative validation gain | 18.764% |
| Relative validation-gain range | 8.61% to 21.26% |
| Strict `tol=1e-4` convergence | 0 / 32 |
| Cases with zero raw crossing rows | 2 / 32 |
| Median raw crossing-row rate | 0.886% |
| Mean raw crossing-row rate | 3.46% |
| Median fit time | about 3.46 hours |
| R57 runtime storage at snapshot | about 14 GB |
| Free filesystem space at snapshot | about 290 GB |

AL was faster in the partial surface but had more raw crossings: seven completed
AL cases had a median 19.28% validation gain, median final change 0.337, and
median crossing-row rate 6.10%. The 25 completed exAL cases had a median 18.71%
gain, median final change 0.0501, and median crossing-row rate 0.712%. These are
partial descriptive results, not a validation-selected family comparison.

## Failure diagnosis

The expensive fit did not fail. Each affected case wrote the finite joint
prediction surface, trace, parameter summary, crossing diagnostics, and compact
`joint_vb_initialization.rds`. The generic PriceFM summarizer then required
`model_method_summary.csv`, which the original Stage-R57 runner had not written.
It therefore raised `FileNotFoundError` after fitting. The old aggregate
`launch_status.csv` mixes this postfit failure with the initial startup attempt
and must not be treated as the scientific completion ledger.

This is recoverable without fitting again:

1. reconstruct the missing method metadata from the runtime configuration,
   trace, adapter dimensions, and runner summary;
2. rerun the generic validation summarizer;
3. replay raw validation metrics and verify exact agreement;
4. derive a monotone-contract view from the same seven-output joint fit;
5. verify checkpoint and source hashes;
6. only then delete reconstructible adapter matrices if cleanup is enabled.

The runner now writes method metadata before summarization and defers heavy
adapter cleanup until the repair contract succeeds. The launcher now supports a
graceful stop sentinel for future campaigns. Neither change alters an active
fit's statistical calculations, and neither causes a launch.

The former `204_closeout_pricefm_stage_r57_joint_vb.py` zero-raw-crossing
closeout is retained only for reproducibility and now requires explicit
`--legacy-raw-gate-authorized true`. It is not the continuation path.

## Raw and monotone prediction roles

The original R57 note made zero raw crossings a hard gate and described any
isotonic operation as disallowed post-hoc synthesis. That is stricter than the
joint-QDESN contract already implemented in
`application/R/joint_qdesn_simulation_readiness.R`. The established contract:

- preserves raw outputs and their crossing diagnostics;
- applies ordered-grid isotonic projection to the outputs of the same joint fit;
- treats contract crossings as a hard failure;
- treats raw crossings, maximum-iteration termination, and large adjustments as
  review signals.

This operation does not assemble independently fit quantiles. It is a
deterministic scoring contract applied to one fitted joint seven-quantile model.
Nevertheless, R57 must not silently replace its original primary estimand.
Stage-R58 therefore reports both `raw_joint` and `monotone_contract` validation
metrics, requires improvement under both for a provisional initializer queue,
and leaves the final primary scoring policy explicitly unfrozen.

## Implemented recovery pipeline

### Stage-R57 runner and launcher hardening

- `202_run_pricefm_stage_r57_joint_vb_case.R` writes
  `model_method_summary.csv`, preserves the compact initializer, and defers
  reconstructible adapter cleanup to the repair pass.
- `203_launch_pricefm_stage_r57_joint_vb.py` supports `--stop-file` and records
  undispatched rows as `not_launched_stop_requested`. This is a future control;
  the current launcher started before this option existed and remains untouched.

### No-refit repair

`205_repair_pricefm_stage_r57_joint_vb_postfit.py` is idempotent and processes
only terminal cases. A terminal case must have all five fit artifacts and a
`job_summary.json` newer than those artifacts. This prevents repair from racing a
worker that is still writing.

The first production pass repaired 36 terminal cases with zero failures and zero
refits; 78 cases were not yet fit-complete at that pass. Its exact code is frozen
in task-branch commit `8443f7f`. Subsequent passes use a vectorized equal-weight
PAVA that is fixture-checked against the scalar algorithm, cap numerical library
threads at one per postfit worker, and reuse existing generic metric artifacts
only after the raw original-scale AQL is replayed and verified.

For each accepted case it:

- enforces the train/validation split firewall and rejects test predictions;
- reconstructs method metadata and invokes the generic summarizer;
- computes raw and monotone-contract AQL, AQCR, MAE, and RMSE on scaled and
  original units;
- verifies raw original-scale AQL against the generic summary;
- writes crossing and contract-adjustment diagnostics;
- hashes the runtime config, source config, manifests, predictions, metrics,
  trace, repair code, and compact initializer;
- marks MCMC, registry, and article actions unauthorized;
- optionally removes only `X_train.csv`, `X_val.csv`, `y_train.csv`,
  `y_val.csv`, `rows_train.csv`, `rows_val.csv`, and `rows_all.csv` after all
  checks pass.

The completed repaired summary is written before optional deletion and then
updated after deletion. An interruption therefore cannot leave a scientifically
validated case dependent on adapter rows that have already been removed.

The checkpoint, predictions, metrics, trace, parameter and method summaries,
crossing diagnostics, manifests, logs, and configuration files are retained.

### Stage-R58 validation-only triage

`206_audit_pricefm_stage_r58_joint_recovery.py` never opens the sealed test
ledger. It emits:

- `pricefm_stage_r58_case_triage.csv`;
- `pricefm_stage_r58_family_summary.csv`;
- `pricefm_stage_r58_candidate_queues.csv`;
- `pricefm_stage_r58_gates.csv`;
- `source_manifest.csv`;
- `summary.json`;
- `pricefm_stage_r58_joint_recovery_report.md`.

A provisional VB initializer candidate must satisfy all of the following:

1. postfit repair is complete;
2. raw and monotone-contract original-scale validation AQL are finite;
3. both AQL values beat the frozen authoritative validation AQL for that same
   region/fold;
4. the compact checkpoint and source-manifest hashes verify;
5. the split firewall is train/validation only and no test artifact was opened;
6. the monotone contract has zero crossings.

Strict raw candidates additionally require the original VB tolerance and zero
raw crossing rows. Both queues are diagnostic while the campaign is partial;
`mcmc_confirmation_eligible` remains false.

### Background recovery monitor

`207_monitor_pricefm_stage_r57_recovery.py` periodically runs only the repair and
R58 audit. It launches no fit and no MCMC. It retains an append-only event ledger,
stops after three consecutive operational errors, and exits successfully only
when all 114 cases are repaired and R58 reports
`full_surface_ready_for_scoring_contract_freeze`.

## Reproducible commands

```bash
PRICEFM_PY=/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python

$PRICEFM_PY application/scripts/pricefm/205_repair_pricefm_stage_r57_joint_vb_postfit.py \
  --workers 2 --cleanup-heavy true --require-original-metrics true --force false

$PRICEFM_PY application/scripts/pricefm/206_audit_pricefm_stage_r58_joint_recovery.py \
  --force true

$PRICEFM_PY application/scripts/pricefm/207_monitor_pricefm_stage_r57_recovery.py \
  --repair-workers 2 --poll-seconds 900 --cleanup-heavy true
```

The monitor may run alongside R57 because it refuses nonterminal cases. Two
postfit workers are deliberately modest relative to the eight pinned fit workers.

## Full-surface decision sequence

1. Complete all 114 Stage-R57 VB fits and no-refit repairs.
2. Rerun R58 and resolve every integrity failure before scientific selection.
3. Freeze whether the article's joint prediction role is raw, monotone-contract,
   or a preregistered dual report. Do not choose this policy from test results.
4. Freeze validation-selected region/fold candidates. Do not require one shared
   specification across cells.
5. Design a bounded exact MCMC confirmation manifest initialized from the saved
   VB checkpoints. AL and exAL remain distinct; exAL MCMC uses the collapsed
   `M0_v_collapsed_support_logit` gamma update.
6. Confirm convergence, effective sampling, quantile ordering under the frozen
   contract, and reproducibility hashes before opening test outcomes.
7. Audit the frozen MCMC winners on test against both the current authoritative
   Q-DESN result and cached PriceFM for the same cell.
8. Promote only cells that pass the agreed dual-reference and harm guards. A
   partial improvement may be reported as a bounded scientific result, but it
   must not be described as uniform superiority.
9. Only then prepare registry changes and article tables, figures, and prose in a
   separate article-integration step.

## Article evidence gate

No current R57 result is article-ready. Article mutation requires a frozen
full-surface validation selection, MCMC confirmation where demanded by the
article standard, a sealed test audit against both references, complete
seven-quantile predictions, matched metric definitions, source and prediction
hash manifests, and explicit handling of raw versus contract outputs. The
existing limitation that authoritative Q-DESN and cached PriceFM prediction
surfaces are not fully matched must also be resolved before symmetric paired
horizon or calibration claims.

## Do not do yet

- Do not relaunch already completed R57 fits.
- Do not open or join the sealed test ledger.
- Do not use test outcomes to choose the scoring contract or candidates.
- Do not declare maximum-iteration VB output converged.
- Do not discard raw crossings or hide contract adjustments.
- Do not launch MCMC from a partial or unhashed queue.
- Do not mutate the PriceFM registry or any manuscript/article file.
- Do not merge or push `main`, an Overleaf branch, or another scientific lane.

## Validation contract

```bash
Rscript application/tests/test_pricefm_joint_quantile_compact_kernel.R

$PRICEFM_PY -m pytest -q -p no:cacheprovider \
  application/tests/test_pricefm_stage_r57_joint_authority.py \
  application/tests/test_pricefm_stage_r57_joint_vb_campaign.py \
  application/tests/test_pricefm_stage_r57_r58_recovery.py
```

The tests cover authority isolation, the real tiny joint AL runner, one lane per
CPU, graceful stop behavior, equal-weight PAVA, no-refit and idempotent repair,
test-split rejection, partial R58 classification, sealed-test rejection, and the
repair-only background monitor.
