# Durable native R-only control (r180)

The original H4 submit action for job887286 failed125 while its controller
was in D-state during durable local publication. A complete JOB existed but
the SUBMITTED journal record did not. The failed guard and spent compute role
remain failed; exact cancellation and old-claim closeout are separate evidence.

`startup_native_r_only.py` is a new native frontend. It never alters the
fourteen compute files accepted by job887283. Those files retain the original
worker/kernel/helper/guard contracts. The borrowed native implementation keeps
its two-entry legacy ROLES tuple, so inherited R accept/finalize still take the
R branch. The new CLI/config admit only EXACT_R46_STARTUP_METADATA.

## Scope and component reuse

The unchanged worker requires the protocol status literal
`PROSPECTIVE_TWO_ROLE_HB_RUNTIME_QUALIFICATION_SCOPE`. The new frontend requires
that literal PLUS all of these narrowing fields:

```text
mode = FRESH_R_ONLY_WITH_EXACT_ACCEPTED_KERNEL_REUSE
roles = [EXACT_R46_STARTUP_METADATA]
maximum_jobs = 1
max_concurrent_jobs = 1
compute_CPU_reservation = 600
old_roles_reopened = false
automatic_retries = false
issued_epoch < fixed_latest_submit_epoch <= expires_epoch - 1200
```

The status literal is protocol compatibility, not a second funded role. The
fresh scope requires its own allowed_metadata_output_root, expiry, fixed submit
cutoff, namespace and canonical authority. No old deadline, slot, fee or failed
job is reused. The complete new one-role native envelope is128 CPU seconds:
the original per-action local/remote fees and maximum calls sum to112, with16
for validation/final failure tails. All original action CPU/wall limits remain.

Existing component eligibility is verified from the exact old ACCEPTED,
RESULT, complete return manifest/files, original SPEC and packet, six actual
case labels/results, actual accept guard, canonical accounting and original
independent role review. All14 compute hashes and the node/cached-Python
identity must match. A new independent cross-context review is also mandatory.
The new R SPEC embeds the exact old accepted summary with its original pins;
it does not create an inventory directory, new ACCEPTED journal or new kernel
test result. An eligibility check alone does not issue reuse/R authority.

Fresh R READY kernel/uname/libc/Python/helper context must match the accepted
component before release. A different allocated single CPU remains explicit
and does not imply a shared process or physical ownership exemption. Current
Slurm job/node/source/READY binding and the actual R guard remain mandatory.

## Canonical durable placement

The actual unchanged-H4 metadata probes found the private persistent /home device
passing and /data ext4 failing125 in D-state. Both probe fees remain charged.
This is observed evidence, not a hard future fsync-latency guarantee.

The config's canonical_state_root must be the exact owned private
`/home/jaguir26/.local/state/pricefm/r180_*` root in the successful placement
proof. Use a NEW mode700 child named `R_only_<nonce>` as the scope's
allowed_metadata_output_root; its registry is a further child. Do not use the
probe directory itself, /tmp, symlinks, a world/group-accessible directory or
a different device. The proof's original H4 receipt/payload/root/device must
match. File+directory fsync, exclusive creation and original guard stop rules
are retained; D is never accepted as stopped. Archive accepted completed state
to the main tracker with separately bounded hashes/readback after the guarded
action, not as extra /data fsync work inside the low-cap submit action.

## Config construction contract

Config schema is `pricefm_native_R_only_config_v1`. Required inputs:

- scope: the fresh narrowing scope pin above.
- site: the unchanged native SSH/site pin.
- native_control_budget: status PROSPECTIVE_ONE_R_JOB_NATIVE_CONTROL_BUDGET,
  combined_native_control_CPU_ceiling128 and the same scope expiry.
- registry, remote_namespace, node, cached_python and cached_python_sha256:
  new local registry, distinct `/mnt/beegfs/home/jaguir26/pricefm_r180_*`
  namespace, node13 and the accepted exact cached runtime identity.
- source_dir: the directory containing the unchanged14 compute files.
- frontend_source: the exact new startup_native_r_only.py pin.
- publication: status PASS_NATIVE_R_ONLY_FRONTEND_SOURCE_PUBLICATION, the
  freshly read-back40-character commit, exact source_files map of all14
  compute hashes and the exact frontend_source pin.
- source_review: status PASS_REVIEWED_NATIVE_R_ONLY_FRONTEND_SOURCE,
  exact source_files and frontend_source bindings.
- accepted_inventory: the original job887283 ACCEPTED pin, never a clone.
- reuse_review: status PASS_REVIEWED_ACCEPTED_KERNEL_REUSE_FOR_FRESH_R_SCOPE,
  binding accepted_inventory, accepted_result, full_return_manifest,
  actual_accept_action_guard, all14 source_files, frontend_source, NEW scope,
  node13, fresh_R_role_required=true and old_failed_R_role_reopened=false.
- canonical_state_root and placement_proof: the exact actual home probe root
  and PLACEMENT_OBSERVATIONS pin.
- carrier and carrier_manifest: the approved runtime archive pins.
- canonical_authority: the pin of CANONICAL_NATIVE_R_ONLY_AUTHORITY.json in
  the new allowed output root. Its status is
  ROOT_AUTHORIZED_CANONICAL_NATIVE_R_ONLY_CONFIG, roles=[R], maximum_jobs1,
  max_concurrent_jobs1, fresh issue/expiry inside the scope, and binding equal
  to `canonical_identity(config)` including carrier, frontend, reuse and
  placement inputs. The authority pin itself is excluded from that identity
  to avoid a circular hash.

Import `pricefm_hb.startup_native_r_only` and call main under the same original
outer action guardian. CLI actions/flags remain compatible with the native
protocol; only the R role is selectable. `load_config` is a metadata-only
preflight. It never creates a scope, review, publication or submission grant.

## Interrupted submission

A failed action with a completed SUBMITTED journal retains its existing
failure-tail path. If submit was interrupted after a complete JOB but before
SUBMITTED, the new acknowledgement requires exactly one pending start with
the current frontend/source/publication/review/14-file identity, the matching
packet, durable submit.intent and SUBMISSION_INTENT chain, exact sbatch argv,
unambiguous matching reply/job/scope and actual failed/drained PID/birth guard.
It permits either the exact SUBMISSION_INTENT tail or that intent followed by
one retained action=submit exception record from the real CLI; unrelated or
additional trailing states remain blocked.
It records cancellation-only identity, never successful submission or reuse.
ROLE_FAILED_SPENT is published before failed_ack, closing the interruption
window in which an ack could otherwise exist without quarantine. Release,
submit and accept remain blocked for a failed role.

Missing/partial JOB, lost/ambiguous reply, changed source/job/argv, corrupt
journal or unproved drain remain blocked; no job is guessed and no retry is
issued. Partial final journal corruption is not silently discarded. A cancel
request remains a request, not terminal accounting or claim-absence proof.

Metadata tests include realistic JOB/journal and directory-sync interruption,
failed-ack publication, malformed/foreign inputs, source/runtime reuse gates,
fresh READY mismatch, separate placement and inherited R accept/finalize.
They execute no SSH, Slurm, child workload, R or scientific model.
