# R157 Hummingbird allocation-limit repair

The original TEST job868958 completed its delayed-READY and fresh-activation checks, then failed while allocating67MiB with approximately375MiB RSS. The metadata submitter's512MiB address-space limit was propagated by Slurm. Its original failed release, source tree,120CPU reservation,6.873 observed jobCPU,37wall seconds, terminal accounting, publication and spent TEST entry remain retained.

The new source submits with `--propagate=NONE`. Its batch script declares the existing CPU ceiling and an address-space soft limit equal to the requested allocated memory (`memory_MiB *1024` KiB for Bash). The worker and qualified payload independently record and validate actual CPU and address-space limits before numerical work. This does not increase Slurm CPU, memory or wall allocations. Unexpected limits fail before numerical imports.

## Explicit replacement qualification

This is a new reviewed one-attempt qualification, not an automatic retry. The root packet has schema `r157_control_test_requalification_v1`, status `ROOT_ADMITTED_ONE_SOURCE_BOUND_REPLACEMENT_TEST`, controller Muscat, a distinct scope02, exact new BASE source hashes, `max_new_attempts:1`, `old_charges_refunded:false`, and `all_prior_failed_terminal:true`. It pins the canonical failed claim/job868958, collection, accounting, worker seal and worker failure. Without the separately admitted recovery below, its expiry cannot exceed either the original INITIAL control pool expiry or the current resource policy expiry. Recovery instead binds the new finite scope while retaining the expired original history.

The controller verifies the retained original release hashes, failed worker/publication identity and independently parsed terminal accounting. It does not execute the historical source or reinterpret it against current source hashes. Preparation derives scope02 from the packet and carries its immutable pin into the release. Reservation preserves both spent TEST entries and rejects a further replacement. A cost claim needs exactly one accepted, drained TEST with the same actual source closure; every other TEST must be a validated terminal failed predecessor in that replacement lineage.

Packet fields:

```text
schema, status, controller, scope_id, created_epoch, expires_epoch
prior_failed_claim_key, prior_failed_job_id
prior_publication:{path,sha256}                  # publication/collection.json
prior_evidence.accounting:{path,sha256}          # publication/accounting.json
prior_evidence.worker_evidence:{path,sha256}     # publication/outputs/worker_evidence.json
prior_evidence.worker_failure:{path,sha256}      # publication/outputs/worker-failure.json
new_executed_sources:{module_name:sha256}
max_new_attempts:1, old_charges_refunded:false, all_prior_failed_terminal:true
```

## Conserved control funding

The original720CPU pool keeps its paid original TEST230, two remaining230 slots and publication30. A replacement TEST plus FI and DK2 would require three new claim slots. An optional prospective `INITIAL_SUPPLEMENT` creates exactly one230CPU slot for one explicitly bound DK2 COST claim. It references the original INITIAL authorization and failed TEST evidence, preserves exactly the original expiry, retains all original charges and refuses a second claim or publication reservation. Root may issue this supplement later; implementing support creates no funding or claim.

The supplement authorization uses the existing control-scope status, kind `INITIAL_SUPPLEMENT`, ceiling230, `old_initial_authorization_pin`, the failed-reference fields above, `permitted_claim_key`, purpose `COST_ONLY`, study `DK2`, `max_new_claims:1`, `old_charges_refunded:false`, and the unchanged original expiry. Each claim retains its217CPU priced operation maximum inside230: parent60, metadata60, transfers66, READY watch11 and admission refresh20.

## Resuming after the control window expired

The original INITIAL expired at09:33UTC on October28. It cannot admit a new
operation or receive a supplement after expiry. Recovery requires a separate,
prospective INITIAL authorization with its own finite deadline and720CPU ceiling;
the original journal, expiry,230CPU claim reservation and observed costs stay
unchanged. This does not extend the local CPU30 scientific permit or the existing
cross-host policy's absolute expiry.

The replacement packet may pin `control_recovery`, a root-reviewed JSON with
schema `r157_control_recovery_v1` and status
`ROOT_ADMITTED_NEW_FINITE_CONTROL_RECOVERY_PRESERVING_EXPIRED_HISTORY`. It binds
the exact old control specification and an immutable byte-for-byte snapshot of
that journal, the new canonical control specification, its prospective creation
and expiry, kind INITIAL, ceiling720, max_new_claims3, and explicit false refund,
old-clock mutation and automatic-retry fields. Historical verification reads the
old bytes without reopening its expired accounting window.

The new authorization's `recovery_claims` maps exactly three task hashes to
purpose, study and scope: replacement TEST scope02, the original FI cost panel
and the original DK2 cost panel. Other tasks, duplicate reservations, altered
history or later clocks fail. The replacement keeps its failed predecessor in
the canonical TEST history. An accepted historical replacement is checked at its
actual claim time; it cannot become authority for a different cost scope.

Slurm documents that resource limits propagate by default and provides
`--propagate=NONE` to disable this inheritance. The compute worker then verifies
the explicitly declared allocation limits before numerical imports.
Source: https://slurm.schedmd.com/sbatch.html

## Prefix screening remains unadmitted

The present per-job upper reservations cannot fund179 separately dispatched prefix jobs from an1800CPU controller pool. At217CPU declared maxima per job, the sum is38843CPU; at230CPU reserved per job, it is41170CPU, before shared-cache/publication work. Small observed costs do not justify replacing these declared upper bounds with an invented measured price. The next design needs auditable batching that amortizes controller and transport work, or a separately reviewed finite control-budget amendment made before execution. Neither alternative changes the existing scientific budgets or authorizes screening by itself.

## Verification

Tests use private JSON fixtures, mocked scheduler boundaries and a bounded local Python child reproducing the512MiB limit. They cover exact compute ceilings, `--propagate=NONE`, unchanged scheduler resources, explicit scope02/pin sealing, missing/changed/expired/undrained replacement evidence, one-replacement enforcement, cost qualification lineage and the one-claim230 supplement. No SSH, scientific jobs, root grants, array deserialization or R calls are performed by these tests.
