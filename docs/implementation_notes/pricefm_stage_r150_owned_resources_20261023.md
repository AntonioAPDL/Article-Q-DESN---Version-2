# R150 dedicated worker ownership and finite resource waves

This implementation is a new resource controller. The second R149 ownership
refusal remains unexplained; R150 does not claim to have diagnosed that failure.
Historical stop/cleanup receipts and their external drain proof remain evidence.

## Ownership and actual execution policy

Every numerical task gets a unique UUID-named transient user service, separate
from the controller and every baseline service. An ownership intent is fsynced
before starting it. The ledger binds the exact unit, UUID description, source,
lease, executable argument vector and expected private systemd cgroup. Before
releasing a payload it adds the immutable InvocationID, ExecStart, properties,
cgroup membership and process lifetime. A standard-library bootstrap waits for
an atomic policy receipt; NumPy imports happen only in the scientific worker
after the worker verifies its actual policy and invocation/cgroup identity.

This host's systemd239 accepts `CPUSchedulingPolicy=idle` but reports and actually
starts SCHED_OTHER. Disposable probes demonstrated this rather than inferring
enforcement from a successful manager call. Consequently the exact ExecStart
begins `/usr/bin/chrt --idle 0`, whose binary hash is frozen. The Python worker
therefore starts SCHED_IDLE before its first Python import. The unit property0
is retained honestly in receipts; actual scheduler5 is required before payload
release. Systemd applies the singleton physical CPU affinity before the chrt
exec. Actual I/O class, six numerical thread environment values, invocation ID,
process policy and descendant inheritance are independently checked. The parent
is SCHED_OTHER, pinned with all preflight/import descendants to physical15–29.

Worker units have `BindsTo` and `After` their own controller, `KillMode=control-group`,
`Restart=no` and a RuntimeMaxSec no later than the original wave expiry. Abrupt
controller death therefore stops its dependent worker trees without depending on
the controller's finally block. Only a freshly verified own unit is stopped via
the service manager. There are no PID/group kill calls. Replacement invocation,
live cgroup drift, changed executable or ambiguous membership fail closed. Final
proof reads the original cgroup, including after the unit unloads. No baseline
signal or shared quota operation exists in this implementation.

## Resource contract and justified refinements

ModeB alone is implemented. The exact current R146 owner lifetime, attempt,
waiting_boundary phase and guardian lifetime/invocation are frozen at admission.
Two readings must demonstrate heartbeat advancement; age must stay within30s.
Normal advancement is required. Regression, phase/lifetime change or stale data
stops dispatch and drains only R150. AT's explicit quarantined terminal and the
current collector lifecycle are pinned, rather than requiring the obsolete five
original services to remain active. Baseline worker completion inside an
unchanged parent service is normal; changing the admitted service lifetime is
a stop. ModeA after a handoff transition needs its own review and admission.

Memory available must remain at least192GiB, disk80GiB; observed combined own
RSS has a24GiB soft stop. These are observational guards, not private cgroup
hard quotas. There are at most two numerical workers. CPUs30–31 and SMT
substitutes are excluded. Before dispatch the least busy eligible physical
CPU is sampled; this is nonexclusive borrowing, not allocation or ownership.
When499orchestrates the finite workflow, the observed RSS also includes its
separate coordinator/descendant cgroup after exact launch/source/release/unit
verification. A wave guard only observes that service; it never stops it.
Controller launch intent now persists before manager start, including the
expected original cgroup. Thus a rapid controller exit before first polling
still requires an independent read of that original path. Startup errors stop
only the persisted verified own controller and retain original error plus drain
outcome; an initial failure cannot lose ownership between launch and polling.

There is one20-minute benchmark and at most three separately persisted two-hour
waves. A lease is created once, pins source/admission/boot/start/expiry and is
never replaced or renewed. Each numerical wave admits conservative measured
wall projections into its first90minutes; the final30minutes is a drain buffer.
CPU reservations across the two workers are also bounded. Benchmark records
freeze effective idle share and conservative wall estimates; missing timing
means refusal, not an assumed full core. Whole-tree source hashes are audited
at admission; frequent guards rehash executable/configuration source rather
than manuscript images. All new R150 scripts, including499, are in that guard.

An early CPU burst cannot hide subsequent starvation: a nonstarved300s sample
resets its monotonic observation window. Less than.10 core delivered over a
full window cooperatively checkpoints, manager-drains and defers the wave.
R150 deliberately uses **zero automatic same-lease requeues**, stricter than
the plan's maximum one. This avoids repeated resource churn when idle CPU is
not available. Observed chunk duration informs a bounded cooperative grace;
strict sealed chunks survive any required manager stop. Original stop reason,
cleanup failures and offending predicates are separate fields.

## Validation and operating entry points

The resource unit tests inject replacement InvocationID, foreign services,
live cgroup/ExecStart drift, exit-time metadata changes, unloaded-but-populated
cgroups, interrupted startup before insertion into the active map, heartbeat
regression/transition, lease expiry and guard-stopped predecessors. Tests also
cover an early CPU burst followed by300seconds starvation. Raw mixed /proc
snapshots are never required for cleanup ownership.

The actual disposable-unit probe uses the exact start properties, wrapper,
stdout/stderr policy and15–29 placement. It proves first-Python scheduler,
affinity, I/O, thread environment and InvocationID; then abruptly kills only
its verified test controller through the manager and observes worker AND
descendant drain. It separately proves a real2s child runtime expiry while its
parent stays active, and rapid child exits with empty final cgroups. Failed
probe attempts are preserved; any cleanup error prevents a passing capability
receipt. The scientific controller requires a passing same-source/same-boot
probe before admission.

Run498 under a first-exec `taskset -c15-29` and all six thread variables1:
`probe --output PATH`, `preflight`, or `launch --wave benchmark|1|2|3`.
Launch starts a dedicated responsive controller; callers never run its payload
inside the shell/chat process. Wave progression is explicit and finite. The
separate499 orchestration may invoke only the frozen benchmark/1/2/3 allowlist,
after fresh admission and verified predecessor drain. No wave4, new fit, AL,
authority change or model promotion is authorized by this resource controller.
