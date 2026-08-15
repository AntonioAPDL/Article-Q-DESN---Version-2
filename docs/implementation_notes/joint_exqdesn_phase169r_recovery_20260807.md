# Joint exQDESN Phase 169R Recovery

## Failure Diagnosis

The original Phase 169 exact-MCMC campaign was stopped after 157 workers
reported the same post-fit error. At the stop boundary, 32 workers were active
and 51 had not started. No worker produced a valid final artifact.

The defect was confined to the reporting boundary. Phase 169 constructed score
metadata without `display_label` and `likelihood`, although the shared grid-CRPS
aggregator requires both columns. MCMC completed before the error occurred, but
posterior draws were serialized only after scoring. Consequently, the completed
computation was not recoverable. This failure does not compare or invalidate the
three exact sampler targets.

The original freeze, receipts, logs, exit records, and partial worker
directories remain unchanged. A dedicated closeout artifact inventories and
hashes this evidence.

## Recovery Contract

Phase 169R changes no scientific field. It preserves all five scenarios, both
fit structures, three exact samplers, eight chains per cell, case-specific DESN
and regularized-horseshoe controls, VB1 initializations, dispersed starts,
iteration budgets, thinning, and chain seeds.

The corrected worker contract adds four protections:

1. one centralized score-metadata constructor with explicit schema validation;
2. fit and forecast CRPS preflight for every scenario/structure/method cell;
3. a hash-verified posterior checkpoint written after MCMC and before scoring;
4. fail-fast dispatch after the first worker error.

Each checkpoint contains compressed coefficient, intercept, scale, and shape
draws; sampler diagnostics; run identity; source-freeze hash; runtime; and its
own artifact manifest. A rerun may resume scoring from the checkpoint only when
the worker id, method, seed, and freeze hash match exactly. Latent arrays remain
excluded.

## Artifacts

The failed-campaign closeout writes:

- `closeout_assessment.csv`;
- `worker_state.csv`;
- `failure_receipts.csv`;
- `failure_message_summary.csv`;
- `root_cause.csv`;
- `evidence_inventory.csv`;
- source-freeze verification, provenance, README, and artifact manifest.

The corrected freeze writes:

- the preserved case controls, VB initialization, starts, and chain plan;
- `scoring_preflight.csv`;
- `design_invariance_audit.csv`;
- original-freeze and closeout-manifest verification;
- source snapshot, readiness assessment, provenance, README, and manifest.

## Gates

Launch is blocked unless:

- the original campaign has no active workers;
- the original freeze and closeout manifests verify;
- all 240 seeds and every scientific chain-plan field are preserved;
- all 30 scoring preflight cells pass with finite scores and zero contract-grid
  crossings;
- the corrected source tree is committed and clean.

Finalization remains blocked until all 240 corrected workers have complete
verified manifests. Mixing and functional-stability thresholds remain review
gates after completion; implementation failures, nonfinite draws, invalid
scales, and contract crossings remain hard failures.

## Commands

The corrected production campaign is launched with:

```bash
bash application/scripts/230_launch_joint_exqdesn_phase169r_mcmc_method_selection.sh 32
```

Health is inspected with:

```bash
Rscript application/scripts/229_check_joint_exqdesn_phase169r_mcmc_method_selection.R
```

Phase 169R remains method-development evidence. Article assets must not be
changed until the completed corrected campaign is audited and one exact sampler
is frozen for balanced confirmation.
