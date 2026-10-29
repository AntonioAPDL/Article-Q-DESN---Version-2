# New paired PROFILE lifecycle

`profile_control.py` implements an independent, finite experiment. It neither
renews old TEST/COST/opaque grants nor spends the32,400 scientific /1,800
assessment/controller pools. There is one new qualification job, followed by
one separately reviewed measurement job only after accepted qualification.
There is no automatic follow-on, retry, resubmission, promotion or repricing.
Every failure/unknown claim retains its reservation. Cache state is UNKNOWN;
fixed reference-then-instrumented order qualifies parity/accounting, without a
causal speedup claim.

## Compute and controller funding

| Phase | Worker pair CPU / wall | Whole job CPU / wall | Wrapper CPU | READY / exit reserves |
|---|---:|---:|---:|---:|
| QUALIFICATION_PAIR |500 /900s|600 /1200s|100|270 /30s|
| MEASUREMENT_PAIR |1500 /3600s|1700 /4200s|200|570 /30s|

Both roles use one physical Slurm CPU, one numerical thread, an explicitly
bounded1–8GiB memory request and the admitted Sandybridge reference profile.
The new whole-job funding pool is2300CPU. A create-only reservation precedes
the held submission. A job-bound funding record then pins that reservation
and the identified held submission. Canonical cumulative reservations cannot
reset; a phase already consumed under the same policy cannot acquire a retry.
Accepted runtime evidence is reused as provenance, never as permission to run.

Controller/transport funding is separate. A practical complete specification
uses400 combined local-plus-remote CPU and1800seconds of command reservations:

The actual phase allocation divides that400 into **350 CPU for the core
controller** (`controller_limits.aggregate_reserved_CPU_seconds`) and a
**separate enforced50 CPU caller envelope**. Two phases still require800 CPU.
The nominal327 CPU core calendar, including its5 CPU local metadata reserve,
is not a cumulative SELF ledger for the persistent caller or CLI clients.

- Metadata command2CPU /20wall; small proof publication5CPU /30wall.
- Bulk staging and complete raw return40CPU /120wall each.
- Full local opaque raw verification40CPU /180wall in an isolated child.
- One readiness notification reserves5CPU locally and5CPU remotely,
 120wall. Its remote stdlib helper waits at most100seconds for the exact owned
  ready file at one-second intervals. It is a finite startup notification,
  separate from scheduler/health polling.
- Three status polls, at least300seconds apart, plus5CPU for local metadata
  preparation. A second5+5CPU bounded metadata operation verifies every remote
  staged byte before startup. Metadata/proof/bulk commands reserve and cap both
  local and remote execution, including the framed-stream helper. Local validation is
  charged once. The core command calendar reserves327 combined CPU;
  unused reservations are not assumed refunded.

These limits are data in the reviewed specification; the implementation checks
that the entire staged/released/collected lifecycle, declared poll count and
validation fit them before launch. Each command consumes a durable operation
reservation before it starts. Failed/ambiguous fees stay charged. Controller
administration needs its own current finite authorization, separately from
the code engineering budget and2300 compute pool. Two phases require a new800CPU
combined controller-plus-caller grant. Earlier200/196 local-focused drafts did not bound
every remote process and are superseded without refunding earlier charges.

Before actual prelaunch, a separate current independent review and funding
proof must bind the exact outer caller source, specification, feature
publication and invocation. Its separately enforced envelope admits at most16
exact source-bound CLI clients plus one persistent tracker driver. The reviewed
kernel/limit premise requires each client to retain default, unblocked SIGXCPU
with SELF soft2 and hard40, and the driver default, unblocked SIGXCPU with SELF
soft1. The caller's conservative funding calculation is2 +16×3 =50 CPU; it
does not substitute waited-descendant CPU for SELF or double-charge the
separately reserved helpers. Explicitly admitted helper limits remain inside
the core350. Source tests alone do not establish the actual caller's signal
state, limits, current authority or eligibility to execute. The inner API/CLI
examples below require that separately reviewed caller for an actual grant;
they do not admit an unmetered interactive caller.

Current transport is a standard-library manifest/file stream over direct SSH,
without generic archive extraction or an external compressor. Both sides use
`profile_supervisor.py` to bound aggregate owned-tree CPU across forks. Kernel
session/group/affinity/namespace guards, one inherited CPU, subreapers and a
two-sided pre-exec ownership acknowledgement keep commands inside that tree.
Stopped snapshots include explicit per-live-process tick rounding. An ancestor
guardian handles monitor failure, and the monitor handles guardian loss; both
are included once in CPU. Three seconds of the existing wall are reserved for
drain/publication. Invalid or partial receipts still trigger owned cleanup.
Unsupported kernel guards fail closed before admission. Legacy rsync was
rejected after its private cleanup SIGUSR2 conflicted with ownership guards;
its failure evidence is retained and no signal exception was introduced.

BeeGFS publication uses its tested create-only hardlink operation, followed by
validated removal of the private pending name. The original `renameat2` flag
smoke failure (`EINVAL`) and unsupported `O_TMPFILE` probe remain retained;
ordinary overwriting rename is never a fallback. The receiver reopens and holds
the original pending inode, verifies the saved precommit fingerprint, then
links without replacing any existing destination. Before unlinking the pending
name it requires both held descriptors and both names to bind the same owned
regular inode, mode, byte length and mtime with exactly two links. Current
ctime must agree within that linked phase; link/unlink legitimately change
ctime and it is not compared across phases. Only a same-inode final single-link
state plus successful parent-directory fsync permits a transfer ACK. Failed or
interrupted publication retains its evidence and reservation.

Normal staged code/metadata and proof bundles are consumed only after the
complete transfer ACK and independent expected-hash checks. The one concurrent
consumer, the compute launcher's `worker_authority.json` wait, treats link2 as
publication in progress and waits within its unchanged READY/wrapper budget.
Link2 after a crash times out without reading authority or spawning a worker.
Unexpected link counts, types, owners and physical-path substitutions fail
closed. Link1 is eligibility to run the original strict hash/source/job/runtime/
review/funding gates, not admission itself; its identity is rechecked after
hashing and immediately before spawn. No scientific/certificate gate is relaxed,
and complete returned raw bytes still receive independent original-universe
and SHA verification before acceptance.

## Durable workflow

The canonical registry is
`pricefm/hb_control_registry/profile_r164/<new-scope>`. A single global lock and
a per-scope lock protect create-only, SHA256-chained records. An unresolved or
ambiguous submission blocks another profile claim. Initial preparation intent
is retained even if copying fails. No original source/cache/model file is
removed. Local copies of staged metadata provide durable history even when an
original preparation path later moves.

1. `prepare_run(spec_path)` validates the new complete source/policy/funding
   contract, current feature publication and accepted interpreter provenance.
   It copies only the explicit bounded Python/JSON allowlist and creates a
   source-derived Slurm launcher/release manifest in the new claim.
2. `stage_run(scope)` checks the own-user queue is empty, creates a new remote
   directory, stages the reviewed source/metadata and verifies its manifest.
   Large scientific inputs remain at the declared retained input root. Both
   actual components rehash the entire original input ledger themselves.
3. `submit_run(scope)` publishes submission intent before a held, nonrequeueing
   one-node/one-task/one-CPU `sbatch`. A lost or unparsable reply is spent and
   ambiguous. The source-reviewed client wrapper removes every `SBATCH_*`
   environment default before executing exact argument bytes; mail is disabled
   explicitly. It cannot be retried automatically.
4. `release_startup(scope)` verifies exact owned pending job name/workdir,
   account/partition/QOS, CPU/task/node count, no requeue, memory and time.
   It also verifies the exact `job.sh` command, requested node, absence of an
   array/GPU/GRES request, and every staged source/metadata/launcher byte against
   the trusted release manifest before releasing startup.
   It releases only bounded startup. The compute launcher verifies all staged
   bytes, the original accepted environment, live Slurm/cgroup facts, and emits
   a request/source/job-bound READY record.
5. `observe_ready(scope, notification_pin)` performs the one funded bounded
   readiness wait and validates the actual returned owned file. Root can now
   construct the complete exact-job authority/review/funding contract. A
   readiness timeout invokes cancellation of this exact owned new job, with
   job ID/user/name/workdir/resources checked before and after `scancel` and
   terminal accounting reconciled. A cancelled pending job retains its full
   reservation. If cancellation cannot be proved, the claim stays unresolved
   and blocks new work. `cancel_exact_owned_job` / CLI `cancel-owned` exposes
   this bounded correction path without signaling other jobs.
6. `release_worker(scope, authority_pin, staged_files=[...])` verifies that
   fresh complete contract, publishes all job-bound proofs in one small bundle,
   then publishes `worker_authority.json` last. The compute launcher admits
   the fixed fresh-interpreter reference /instrumented pair only after its
   independent gate passes. The READY wait cannot extend the allocation.
7. `observe_run(scope)` performs a bounded own-user queue and complete Slurm
   accounting read. A delayed/missing primary record remains unresolved with
   the full reservation retained. It never becomes a zero charge. Canonical
   primary TotalCPU is charged once; steps/child counters attribute it.
8. `collect_run(scope)` requires terminal success and an empty own-job queue,
   publishes the exact canonical accounting JSON back to that job's metadata,
   bounds remote apparent return size before copying, retrieves all useful raw
   output, then invokes the isolated40CPU /180wall verifier. It revalidates
   exact original task/chunk/array shape coverage from Muscat's pinned original
   JSON/source, every raw packet, sampler/metrics/result parity, source/job
   bindings, final sealing/accounting and the canonical primary charge. The
   returned metadata cannot define its own expected universe. A complete raw
   manifest pins every returned file before acceptance.

The accepted qualification keeps portable HB pins for its request, component
result and published canonical accounting, plus explicit local pins for the
retrieved copies. A later measurement gate can therefore re-read the exact
qualification evidence without trying to resolve a Muscat-only path on HB.

Collection/status may read completed work after numerical expiry only inside
the prospectively declared `controller_expires_epoch`, at most1800seconds
after numerical expiry. Every operation must fit that remaining finite window.
Later read-only reconciliation needs a new finite administrative authority.
Terminal unsuccessful jobs can be reconciled with
`reconcile_failure`, retaining at least the full whole-job reservation. Known
job identities after an ambiguous authority publication can be observed
without publishing another marker; an unidentified held submission requires
explicit independent reconciliation and stays blocked.

## Specification and exact review

Schema is `r164_profile_controller_spec_v1`. Required fields are:

```text
schema, scope_id, phase, created_epoch, expires_epoch, controller_expires_epoch,
request, remote_root, output_root, runtime_python, environment_bundle, node,
worker_limits, allocation_limits, worker_sources, controller_sources,
files, funding_reservation, prelaunch_review, feature_publication,
qualification, site, controller_limits, environment_provenance
```

`request` is the executor's pinned JSON, with all actual execution metadata
pins using final physical HB paths. `files` maps each to an exact local copy:
`{local, relative, sha256, bytes}`. Python/JSON only, at most256 members of16MiB
each; no credential/Git/agent trees. `spec_read` resolves remote pins through
this mapping on Muscat and reads their final paths on HB. The controller source
closure is the exact `controller_sources()` map, including all22 worker files,
the controller, aggregate supervisor and framed-stream helper. Historical
qualification source is retained; its old grants/per-process runner are unused.
New-work policy validation uses this exact local pin resolver as the explicit
reader for nested historical/authorization evidence. The worker's direct
physical-pin validator remains the default on HB.
Unchanged nested policy pins for measurement may point into the first release.
The bounded read-only resolver verifies that earlier canonical claim's full
journal chain, accepted qualification, namespace, release manifest and exact
metadata hash, then reads its retained Muscat copy. Policy bytes/hash and the
shared2300 counter remain unchanged.

`prelaunch_review` must have status `PASS_REVIEWED_NEW_PROFILE_LIFECYCLE`, the
exact scope/request/worker and controller sources, worker/whole/controller
limits and `no_old_grants_reused:true`. Its `spec_contract_sha256` is produced
by `spec_contract(spec)`: every specification field is bound except the
review's own pointer and its own stage-manifest entry, avoiding a hash cycle.
Runtime paths, bundle, node, site, input/source allowlist, output root and the
absolute window are therefore reviewed together. No boolean can override a
failed live allocation/authority gate.

`feature_publication` has status `VERIFIED_FEATURE_PUBLICATION`, the complete
controller source map and fresh command-line remote-hash evidence. Root
creates it from the actual Git publication proof. `qualification` is null for
the first job and the exact accepted full qualification pin for measurement.
Every job-bound numerical review additionally binds the canonical hash of the
complete authority except its review pointer.

`environment_provenance` contains four exact immutable accepted JSON pins,
whose hashes are exported as `ACCEPTED_RUNTIME_EVIDENCE`:

| Role | Existing accepted evidence |
|---|---|
| reference_release |R156 `releases/parity_reference_profile_02/release.json`|
| environment_completed |`published/environment_03/outputs/completed_evidence.json`|
| reference_completed |`published/parity_reference_profile_02/outputs/completed_evidence.json`|
| reference_runtime |`published/parity_reference_profile_02/outputs/environment-runtime.json`|

These bind the interpreter and bundle under accepted environment release
`r156-1ed8d7320e8444b089cb02961a8d7dee`, including the completed publication
artifact chain. Stage exact copies under the new release and update only their
pin paths. Their bytes, scientific native profile and hashes remain unchanged.
Fresh runtime/native/cgroup verification still happens on the actual node.

## API and CLI

The held-job resource check accepts Slurm's exact `TresPerTask=cpu=1`
representation of the explicit single CPU request. All other per-task TRES
values, GPU/GRES and per-node/socket/job resource requests remain rejected.
`NumCPUs`, `NumTasks` and `CPUs/Task` must each be exactly1. A pending user-held
job with zero runtime, unknown start and absent allocated TRES may report the
exact one-node range `NumNodes=1-1`; running and other states require the
concrete count1. No larger or ambiguous range is accepted.
The real held/cancelled metadata that exposed these spelling differences is
retained separately; this source compatibility change does not reopen its
spent reservation, restart its caller or grant a numerical retry.

From the package root, on administrative CPU31 with `-B`:

```text
python -B -m pricefm_hb.profile_control --prepare <spec.json>
python -B -m pricefm_hb.profile_control --scope <new-scope> --action stage
python -B -m pricefm_hb.profile_control --scope <new-scope> --action submit
python -B -m pricefm_hb.profile_control --scope <new-scope> --action release-startup
python -B -m pricefm_hb.profile_control --scope <new-scope> --action await-ready --notification <notice.json>
python -B -m pricefm_hb.profile_control --scope <new-scope> --action release-worker --authority <authority.json> --proof-staging <proof-list.json>
python -B -m pricefm_hb.profile_control --scope <new-scope> --action observe
python -B -m pricefm_hb.profile_control --scope <new-scope> --action collect
```

`proof-list.json` is a list of `{local, relative, sha256}`. Every new job-bound
funding/submission/review proof is included; the last marker must be exactly
`worker_authority.json`. The funding chain and complete authority-contract hash
are checked before publication. The internal compute-session and isolated
return-validation actions are generated by the reviewed controller itself.

Run `-B -m unittest pricefm_hb.profile_control_tests` on CPU31. Tests use owned
dummy files and fake network runners, plus one read-only original DK2
JSON/source mapping check. That integration case explicitly skips in a clean
clone without the original local metadata; its actual local PASS receipt is
retained separately. Tests make no SSH/Slurm calls and import no numerical
library. Actual qualification, collection and source publication remain
separate evidence; tests never fabricate a numerical pass.

Positive owned-command, guardian-readability and backstop fixtures reserve4CPU each and still require success. They do not prove generic metadata availability. Before the R165 bootstrap anchor, an observed first-snapshot conservative birth-lifetime upper bound could reject a2CPU command before its0.73CPU active margin was established. The earlier unwitnessed125 failure remains unexplained. The new source separately proves a pre-fork actual-CPU anchor while retaining complete process-birth wall limits; unknown time after the anchor remains charged conservatively and can still stop the command.

## R165 reviewed lifecycle and accounting changes

The original scheduler accounting is immutable. After complete raw-return
validation, collection creates a separate `accepted_job_accounting.json` with
the scientific worker source map, verified-return flag, original accounting
hash, validation hash, raw-manifest hash and component-result hash. It checks
remote absence, publishes this proof create-only, and verifies its remote hash
before creating acceptance. Qualification points to this post-validation proof;
the measurement gate keeps its original strict requirements. No flag is added
retroactively to raw Slurm accounting.

The local prior-qualification resolver admits only the exact accepted accounting
and component-result JSON roles. Canonical job/source identity, original
accounting, validation and raw-manifest hashes remain bound. It does not turn
the returned directory into a general input allowlist. Workers read the original
retained remote pins; later-phase qualification bytes and common policy bytes
remain unchanged.

At three ordinary status polls, normal success uses 29 supervised operations:
20 metadata, two bulk transfers, four proof publications, one validation and
two READY operations. With metadata4, proof5, bulk40, validation40, READY5 and
local administrative reserve5, minimum combined core funding is425 CPU seconds
and command-wall funding is1180 seconds. The separately reviewed R165 caller
uses450 core plus50 caller =500 CPU seconds per phase,1000 for the pair. These
are prospective new contracts; no old400-per-phase grant is reopened.

Exact-owned cancellation also supports an already-terminal job without sending
`scancel`. Known cancellation/accounting lag or a lost cancellation acknowledgement
can use at most two read-only queue/accounting follow-ups, at least300 seconds
apart, based on the retained owned-job proof. They never resubmit, release,
repeat cancellation or accept output. The admission window reserves600 seconds
for these waits. At three status polls, the maximum active-cancellation prefix
plus both follow-ups fits29 operations and317 core CPU seconds, below normal
success;32 operation slots remain the hard maximum.

Cancellation can also verify an exact one-node pending request after its hold
was released: queue reason or estimated start-time changes do not make that
same owned request unsafe to cancel. The literal range must still be1-1,
runtime zero, allocation TRES absent and node assignment empty; all ownership,
CPU/task, memory, command and requested-node checks remain. Held startup retains
its stricter JobHeldUser/Unknown-start conditions for the pending range.

A rejected or interrupted collection may reconcile a retained exact terminal
observation even if Slurm completed successfully. It remains a failed scientific
attempt: no acceptance, no refunded reservation, no restarted claim and no
measurement admission. Scientific sources, model contracts, finite certificates,
iteration limits and the fixed primary operator are unchanged.
