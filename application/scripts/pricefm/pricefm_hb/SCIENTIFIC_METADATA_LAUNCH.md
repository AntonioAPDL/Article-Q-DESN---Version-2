# PriceFM scientific metadata launch

This new purpose repairs the four defects independently reproduced in frozen
r179. It does not amend r179, the production guard, the old startup worker, any
scientific algorithm, saved winner or original failure. No target, toy, bridge,
pilot, optimizer or production fit is an admitted metadata-owner role.

The two available purposes are `SCIENTIFIC_NAMESPACE_NO_OPTIMIZER` and
`SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER`. Each uses a fresh scope, namespace,
one-shot role and complete reservation. Actual accepted exact-R startup is a
prerequisite; the boundary role additionally requires the complete accepted
namespace result from these exact sources. Old execution authority and fees
are never reused.

## CPU ownership and resources

The new batch shell executes the compute Python worker directly in the same
PID. There is no srun process or artificial `.0` accounting row. The allocation
is one node/task/CPU/thread, 8 GiB, at most one concurrent job, no requeue or
automatic retry, and at most1200wall seconds. Actual one-CPU affinity and live
Slurm/cgroup job, UID, memory, allocation class and deadline are checked before
READY or any R. A wider batch affinity fails before R; this code never chooses
an arbitrary CPU or changes another process's affinity.

An exact `job_ID` cgroup component is mandatory. If a `uid_UID` component is
present it must match the kernel UID; contradictory job/UID labels always fail.
A Slurm v2 layout may omit a UID label. That omission supplies no ownership
authority: live scheduler `UserId` must still equal the current kernel UID,
with exact current job/node/resources and owned lifetimes. Before this check,
bounded raw own cgroup, affinity, UID, birth/boot and limit facts are retained.
Pre-READY admission failures seal a truthful data-free failed return, never
READY or payload authority.

The inherited hard CPU ceiling is600, allowing the worker to enforce its own
cumulative90CPU soft ceiling without irreversibly capping its R child at30.
Installation never forks and has a60CPU/600wall component. The worker and batch
shell share one PID; their own overhead outside installation must remain below
30CPU. The unchanged r157 ptrace owner runs directly in that same worker PID,
with a450CPU inclusive ceiling and300wall limit. Its450CPU includes all prior
SELF and reaped native-helper CPU, including installation; it is not450fresh
payload seconds. Every newborn R/helper is kernel-owned before execution and
EXITKILL protects tracees if the tracer dies. The tracer is never placed below
H, whose child filter denies ptrace.

The conservative600CPU reservation retains all component fees. Its component
envelopes overlap for ownership checks; they are not summed as measured CPU.
The1200wall model includes READY120, installation600, owner300 and finalization
reserve180. Successful complete primary Slurm accounting is counted once; the
batch and optional extern rows are diagnostics and are not added again.

## Producer and consumer contract

`scientific_batch.load_config(path)` is a metadata-only preflight that creates
no registry, packet, intent, claim or job. It verifies the entire canonical
config binding, fresh one-purpose scope, private persistent-home placement,
new136CPU native control envelope, exact source publication and independent
source review, completed prerequisite records and the closed code-only inputs.
The full136 native reservation funds every maximum normal, cancellation,
forensic reconciliation, retirement and finalization path; all original
per-action H caps remain unchanged. `CONFIG_EXAMPLE_UNISSUED.json` in the dated
implementation tracker contains concrete archive/science pins and null fields
where new actual root/peer authority must be issued. It is not executable.

The source controller offers `prepare`, `stage`, `submit`, `ready`, `release`,
`observe`, `collect`, `accept`, `cancel`, `reconcile`, `retire_failed` and
`finalize`. Native transport, Slurm and SFTP are the only login-node activity.
Each native action runs on administrative CPU31 below the unchanged original H
with its declared action CPU/wall cap. Pass its complete actual guard as
`--previous-guard` to the next action. A failed action requires its exact
drained guard and permits only diagnostic/drain operations; a failed role stays
spent. No second stage, submit, READY fetch or release is automatically retried.

After actual READY, call
`scientific_batch.prepare_release(actual_config_path, new_bundle_directory)`.
This writes actual job/node/affinity/source-bound install, namespace and owner
specs plus **unissued** authority templates. It grants no execution or peer
PASS. Root must issue fresh exact install and owner authorities; independent
review must bind their actual pins and sources. Required review statuses are
`PASS_REVIEWED_SCIENTIFIC_CODE_INSTALL_SOURCE_AND_SPEC`,
`PASS_REVIEWED_R179_SCIENTIFIC_METADATA_OWNER_AND_SPEC`, and the outer
`PASS_REVIEWED_STARTUP_BATCH_RELEASE` with `purpose=SCIENTIFIC_METADATA_ONLY` and
all seven actual stage pins. The root outer release retains the legacy
`ROOT_RELEASED_STARTUP_BATCH_ROLE` wire literal solely for compatibility;
its role, scope, READY, sources, exact job and stage contracts define the new
narrow authority. No old startup-role grant is accepted.

The flat release bundle contains install spec/authority/review, namespace spec,
owner spec/authority/review, outer peer review and the root `RELEASE.json`.
The seven stage pins are `install_spec`, `install_authority`, `install_review`,
`namespace_spec`, `owner_spec`, `owner_authority`, `owner_review`. The local
controller and compute worker use the same strict release validator, through
an exact local alias map before upload. Payload files precede create-only
publication of the release pointer. The worker independently validates the
closed loader environment and actual READY native-helper exec allowlist.

## Namespace and return acceptance

The fixed contract requires all48 reviewed package versions, the original
fixedpoint-helper SHA and stock-function-body SHA, exact installed library and
R-home paths, all actual loaded DLLs inside the34-file pinned allowlist, and six
mandatory native namespace DLLs. Optional packaged cairo is allowed if loaded
and must match its hash; it is not falsely assumed to load during a namespace
test. Successful namespace loading proves the ABI for DLLs actually loaded.
No compiler, toy parity, future optional ABI or scientific fit is implied.

R's one intrinsic base entry is explicitly reported under `builtin_DLLs` only
when the entry-list name, DLLInfo name and path are all exactly `base`. It has
no external file hash. Its record is bound to the actual pinned native R4.6
executable. Every other entry must be a named, absolute regular file inside the
unchanged34-file allowlist and must match its hash; the six mandatory DLLs stay
required. Missing, relative, unknown pseudo, duplicate or mislabeled base
entries fail. The owner accepts exactly one typed builtin record, so this
exception cannot hide an unknown library. A bounded pre-DLL phase observation
on stderr is diagnostic metadata and never a namespace PASS.

READY records the worker UID/PID/birth/boot/affinity and current actual
kernel/libc/Python/helper identities. These must match the exact accepted-R
component context before payload release. Acceptance binds every namespace
frame to the current job/node/nonce/native/version/body/DLL contract; it also
binds the actual unchanged ptrace receipt and closed owned-tree metadata to
the same READY worker lifetime, current scope, authority and source. A swapped
old receipt, child ACK alone, status-only PASS or unreturned guard cannot pass.
The boundary requires actual kernel TSYNC program attestation and parent ACK.

Complete return and independent review precede `accept`. The resulting
candidate is still pending until the actual original accept-action guard is
validated by `finalize`. Only then is
`ACCEPTED_COMPLETE_SCIENTIFIC_METADATA_ROLE` written. It explicitly leaves
numerical parity and production admission false.

## Failures and preservation

Every submission intent and raw reply is retained before reply parsing or
success publication. Ambiguous replies never create execution authority. A
separate one-shot forensic `reconcile` observes the exact nonce/name, UID,
account and partition from canonical submission intent, and may create only a
`RECONCILED_JOB.json` drain handle. It cannot create `SUBMITTED`, retry a job,
release a payload or accept a failed role. Missing or multiple matching jobs,
foreign ownership, unproved local drain, partial return or inconsistent
accounting remain quarantined for a separately reviewed remedy. Failed fees,
partial files, old aliases and raw evidence remain unchanged.

All source and metadata tests are administrative-only. Actual R parsing,
namespace loading, ABI applicability, current TSYNC and useful returned proof
must be earned in fresh real Slurm allocations. Numerical continuation remains
separately scoped after those prerequisites.
