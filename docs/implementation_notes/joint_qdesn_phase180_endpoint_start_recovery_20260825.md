# Joint QDESN Phase180 Endpoint-Start Recovery

Date: 2026-08-25

Status: implementation and launch protocol for a bounded recovery amendment.
This note does not redefine the Phase180 scientific contract, authorize a new
screen, or modify article files.

## 1. Decision

The correct next action is to recover exactly the ten Phase180 chain workers
that failed before their first MCMC iteration. The other 158 workers are
complete and hash-verified and must be preserved. A full Phase180 rerun would
discard valid computation, increase runtime, and add avoidable Monte Carlo
variation without answering a new scientific question.

The recovery changes only the initial coordinate used for the exAL shape
parameter. It retains the frozen:

- scenario and readout-specific DESN specification;
- regularized-horseshoe and `tau0` controls;
- article fixture and seven-level quantile grid;
- exact M0 posterior target and sampler route;
- chain and component seeds;
- iteration, burn-in, thinning, and forecast controls;
- worker identities and output locations.

The recovery is therefore an initialization amendment, not model tuning or
candidate selection.

## 2. Closed-Run Health Audit

The original Phase180 launcher ended naturally. No Phase180 worker or launcher
was active when this recovery was designed.

| Item | Audited result |
|---|---:|
| Planned Phase180 rerun workers | 168 |
| Complete and manifest-verified | 158 |
| Failed | 10 |
| Remaining/running | 0 |
| AL workers complete | 128/128 |
| New exAL workers complete | 30/40 |
| Final scenario-model cells with eight chains | 27/32 |
| Final scenario-model cells with six chains | 5/32 |

The ten failures are workers `49`, `56`, `89`, `96`, `113`, `120`, `137`,
`144`, `145`, and `152`. They are chains 1 and 8 in five exAL cells:

- independent exQDESN, Laplace bridge;
- independent exQDESN, normal bridge;
- independent exQDESN, persistent heavy tail;
- independent exQDESN, regime shift;
- joint exQDESN, regime shift.

Every immutable failure receipt contains the same message:

```text
weights must be positive.
```

None of the failed workers wrote a complete prescore checkpoint. The failure
is therefore upstream of scoring and cannot contaminate a partial score
packet.

## 3. Root-Cause Isolation

Phase180 labels the exAL route as `M0_v_collapsed_support_logit`. The actual
dispatch is the established exact-M0 collapsed-scale sampler with the
`v` augmentation and support-logit gamma update. The target is not the cause
of the observed failures.

The original Phase180 chain starts dispersed gamma on its native bounded
support by 30 percent of the support width and clipped extreme chains to
`lower + 1e-6` or `upper - 1e-6`. At the asymmetric support endpoints for
`tau = 0.25` and `tau = 0.75`, evaluation of the legacy exAL constants suffers
catastrophic cancellation. In the reproduced worker-49 failure:

- the legacy working value of `B_gamma` was approximately `-3.61e5`;
- the algebraically stable reference value was positive and approximately
  `9.01e15`;
- the initial M0 working weight `1 / (B_gamma sigma v)` was consequently
  negative;
- the weighted regression failed before iteration one.

An instrumented replay of the real worker, fixture, controls, and seed
reproduced the failure at the affected quantile. Replacing only its gamma start
with a bounded support-logit interior value allowed the same worker to enter
and complete M0 iterations. This isolates the defect to initialization
geometry rather than the DGP, DESN specification, `tau0`, MCMC budget, or score
contract.

## 4. Corrected Start Contract

For each quantile level, let `eta(gamma; tau)` denote the existing logit map
from the bounded admissible gamma support to the real line. The recovery:

1. maps the structured-VB gamma start to `eta`;
2. clamps the center to `[-1.5, 1.5]`;
3. adds eight deterministic offsets evenly spaced over `[-2.5, 2.5]`;
4. maps the resulting values back to native gamma support.

Thus every chain starts in the bounded numerical interior `eta in [-4, 4]`,
while retaining deterministic between-chain dispersion. Sigma and all other
start blocks are unchanged.

Before a recovery freeze can be published, every exAL start is evaluated by
the actual legacy M0 constants used by the production sampler. The preflight
requires:

- gamma strictly inside its tau-specific support;
- finite positive sigma;
- finite `A_gamma`, `B_gamma`, and `lambda_gamma`;
- positive `B_gamma`;
- finite positive initial M0 working weight.

The amendment also proves that the ten original starts fail this preflight and
that all ten corrected starts pass it. This prevents a generic start change
from being mistaken for a targeted recovery.

## 5. Immutable Recovery Artifacts

The recovery freeze is written to:

```text
application/cache/joint_qdesn_phase180_balanced_dgp_score_recovery_freeze_20260825
```

It contains:

- `parent_freeze_identity.csv`;
- `recovery_worker_plan.csv`;
- `recovery_chain_start_values.csv`;
- `original_and_recovery_start_preflight.csv`;
- `original_failure_inventory.csv`;
- `preserved_worker_manifest_inventory.csv`;
- `readiness_assessment.csv`;
- `provenance.csv`;
- `artifact_manifest.csv`;
- `README.md`.

The freeze hashes the original Phase180 freeze, all ten failure receipts and
logs, and both worker and checkpoint manifests for all 158 preserved workers.
Recovered checkpoints additionally record the execution commit, amendment
manifest hash, recovery identifier, and corrected start-row hash.

Recovery execution is fail-closed: a worker refuses to run unless the current
worktree is clean and its `HEAD` equals the commit frozen by the amendment.

## 6. Execution Plan

### 6.1 Prepare after commit

The implementation must first be tested, committed, and pushed on the
dedicated JOINT branch. The production freeze then records that exact clean
commit:

```bash
Rscript application/scripts/275_prepare_joint_qdesn_phase180_endpoint_start_recovery.R
```

### 6.2 Audit CPU availability

CPU affinity must be selected immediately before launch. Only currently idle
physical cores may be leased. The recovery launcher requires an explicit CPU
list and never invents one from stale planning notes.

### 6.3 Launch exactly ten workers

```bash
JOINT_QDESN_PHASE180_RECOVERY_CPU_LIST=<audited-comma-separated-cpus> \
JOINT_QDESN_PHASE180_RECOVERY_MAX_PARALLEL=<number-of-audited-cpus> \
bash application/scripts/278_launch_joint_qdesn_phase180_endpoint_start_recovery.sh
```

The launcher uses one BLAS/OpenMP thread per worker and a completion-aware CPU
lease queue. It runs only the ten amendment-authorized worker IDs. On success,
it executes the existing overall health check, deterministic score finalizer,
article-safe staging builder, and integration-handoff builder.

### 6.4 Health command

```bash
Rscript application/scripts/277_check_joint_qdesn_phase180_endpoint_start_recovery.R \
  --write
```

## 7. Gates

### Hard fail

- the parent freeze or any preserved manifest hash changes;
- a failure receipt is missing or has a different signature;
- the recovery plan contains anything other than the ten closed failures;
- any frozen seed, control, fixture, budget, or worker identity changes;
- any corrected start fails the actual M0 preflight;
- the execution worktree is dirty or at a different commit;
- any recovered worker fails or writes an incomplete manifest;
- the recomposed 168-worker inventory is incomplete;
- any score is nonfinite or any contract crossing remains;
- packet, staging, or handoff manifests fail verification.

### Review

- raw crossings are frequent despite zero contract crossings;
- score-functional R-hat, ESS, MCSE, chain-allocation sensitivity, or
  independent coupling sensitivity exceeds the frozen Phase180 thresholds;
- posterior score intervals or joint-minus-independent contrasts do not
  establish practical separation;
- scalar parameter mixing is weak while reported score functionals remain
  stable.

Review is not failure and must not trigger retrospective model tuning. If a
score-functional gate is review-level, the next allowed action is the already
declared same-specification chain extension, not a new DESN screen.

### Pass

- recovery is 10/10;
- overall Phase180 completion is 168/168;
- the final packet has exactly 32 scenario-model cells and 16 joint-minus-
  independent contrasts;
- all implementation, source, finiteness, and contract-crossing gates pass;
- all manifests and recovery provenance verify.

## 8. Verification

Before launch:

```bash
Rscript application/tests/test_joint_qdesn_phase180_endpoint_start_recovery.R
Rscript application/tests/test_joint_qdesn_phase180_balanced_dgp_score_packet.R
Rscript application/tests/test_joint_qdesn_phase179_case_specific_dgp_score_confirmation.R
Rscript application/tests/test_joint_qdesn_post_phase178_dgp_score.R
```

After completion, repeat the focused recovery and Phase180 tests, verify every
generated manifest, and inspect the final gate assessment. Article files are
staged only; this scientific lane does not merge `main` or publish Overleaf.

## 9. Alternatives Rejected

### Full rerun

Rejected because 158 workers are already valid and verified. It would be more
expensive and less reproducible than an immutable recovery amendment.

### New DESN or `tau0` screening

Rejected because the failure occurs before MCMC iteration one and is fully
explained by the start geometry. Case-specific Phase179 specifications remain
frozen.

### Change the posterior target or M0 augmentation

Rejected because the corrected real-worker replay enters the existing sampler.
Changing the target or augmentation would create a new scientific method and
invalidate direct recomposition with the 158 completed workers.

### Silently replace the legacy exAL constants

Rejected for this closeout because it would change a broader numerical path
than necessary. If an interior-start worker later reproduces the same
pathology, stable constant evaluation should be isolated and validated as a
separate amendment rather than folded into this recovery without evidence.

## 10. Completion Rule

The recovery closes Phase180 only if the ten amended workers and the recomposed
score packet pass the frozen gates. Numerical improvements may be reported even
when scalar mixing is review-level, provided the posterior quantile-grid score
functionals are stable and provenance is complete. No result is promoted from
partial output, and no article authority changes until the integration
coordinator reviews the frozen handoff.
