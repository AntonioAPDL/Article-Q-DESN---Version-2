# R151: finite resource recovery of the immutable R150 EE screen

The previous numerical coordinator is terminal after wave 1 stopped on measured
CPU starvation. Its scientific outputs remain valid. A direct old `498 launch2`
would consume an admission and fail its guard against the dead old `499` parent.
The new `501_recover_pricefm_stage_r150.py` replaces that resource lifecycle only.
It calls the original c036 `498` service APIs and `500` scheduler/worker without
rebinding their globals, copying numerical code, changing seeds, or relabeling
scientific producer fields. The scientific worktree stays immutable at
`c03613cd1a85cce5d02120760b954cdc15160410`.

## Policy snapshot diagnostics after the stopped wave2

The retired-aware source57f9 completed five more deterministic components, then
stopped wave2 with the generic `worker thread policy changed` exception. The
message combined OS Threads!=1 with missing/non-one thread environment settings
and retained no failing PID/value snapshot. The scientific outputs and owned
cleanup passed independent replay; **the production cause remains unproven**.
A normal completed packet's BLAS threadpool count1 is not proof that every
intermediate OS-thread/environment observation was valid.

This diagnostics-only branch adds redacted two-read process-policy attestation.
Each read remains bound to the immutable unit InvocationID/cgroup and process
PID/start_ticks/boot identity. Exec/temporarily unavailable reads need a fresh
complete stable snapshot; unverified live processes fail closed after two reads.
Only independently confirmed terminal processes are ignored. A dead main cannot
hide a live unvalidated descendant. Positive active Threads>1, any present vendor
setting different from1, scheduler/affinity or actual I/O violations still stop,
including positive observations followed by exit. Every live CPU-policy
observation is checked, including snapshot tails and terminal-confirmation
rereads, so a later exit cannot hide an observed scheduler/affinity violation.
PID reuse or unit
replacement fails instead of adopting another owner.

Failures retain PID/lifetime/state/cmdline hash, observed OS Threads, expected and
actual **six thread variables only**, read error types/errnos and controller
source hash in the exception, which is carried into the existing terminal. No
whole environment or unrelated environment value is retained. Actual zombie and
repeated-exec fixtures reproduced transient PermissionError13 on this host;
they did not reproduce the production's exact generic thread-policy message.
Those observations demonstrate a read-race failure mode without establishing
the original cause.

The immutable57f9 producer and wave2 terminal/lease are preserved. This branch
claims no scientific admission, wave reuse, lease extension or new regional
screen. The full remaining D+S0 prefix does not fit the sole unused wave3; fixing
this resource observer does not authorize a numerical continuation.

## Manual retirement-aware successor

The first released R151 source is immutable at
`90ff802d09ca9b6712ccaae052d327fb23beaede`. Its outer workflow stopped before
claiming EE wave2 because the original R141 scheduler had reached its expected
LT/AT certificate boundary and exited after draining healthy work. That terminal
and its immutable launch gate remain intact. The user-authorized fresh resource
contract is a separately reviewed manual successor, not an automatic restart.

The committed `pricefm_stage_r151_retirement_contract_20261023.json` is a
byte-identical copy of the independent 38-pin boundary dossier. Only the exact
original R141 lifetime may remain retired: every guard requires the same unit
remain unloaded, inactive, MainPID0 with no InvocationID/cgroup, both old
supervisor/LT controller PIDs absent, and the original cgroup empty. Any
reappearance, replacement, source/evidence change or lingering descendant stops.
The other three protected baseline lifetimes, AT terminal and advancing same
`waiting_boundary` handoff remain unchanged. This does not repair LT/AT or relax
any fit certificate.

The successor release pins the entire old90ff runtime source, failed outer
context/terminal and all prior EE recovery identities. Prior controllers and
workers must independently be drained before launch and remain drained at every
poll. Old regional prepared metadata and task descriptors are pinned; any old
regional lease, runtime, benchmark, checkpoint, score, decision or CPU accounting
rejects the successor so a new namespace cannot duplicate the old numerical
budget. Canonical EE admissions2/3 remain the only two unused admissions.

The new outer coordinator carries the original global expiry
`1792858323.6072176`; it cannot reset630minutes. Standalone EE launches also
cap their coordinator by that same original expiry, and all guards reject the
global cutoff both before and after a numerical lease exists. A newly attested EE coordinator
has at most245minutes and is additionally capped by its actual outer parent's
original epoch/runtime minus a five-second transition margin. Every individual
wave still must fit its parent's unchanged finite lifetime before claim. New
preouter guards accept no parent only when there is no lease, child controller
or active payload, while retaining source, retirement, baseline, handoff and
memory/disk predicates.

## Finite execution and provenance

The original canonical runtime, admission and locks remain authoritative. Wave 1
and original workflow/benchmark receipts are hash pinned and never edited.
Only absent canonical wave-2 then wave-3 leases may be claimed, each exactly once,
for 7,200 seconds with a final 1,800-second no-new-forecast reserve. There is no
new benchmark, alternate lease namespace, joining an existing lease, renewal or
fourth wave. An admission survives a crash between claim and service launch and
is consumed. Before each claim, the entire child wave plus a five-second
transition margin must fit the coordinator's original start epoch and the
smaller of its requested and actual runtime; a new child cannot reset that clock. Claim uses exactly one `lease.lock` acquisition; it never invokes
the old nested `lease_once()` helper.

The new coordinator holds canonical `workflow.lock` for its complete lifetime,
with RuntimeMaxSec 14,700. One child controller at a time holds `controller.lock`.
It is bound to the coordinator; workers are bound to the child controller. When
started by `503`, the EE coordinator also binds to the outer finite orchestrator.
A unique intent is durable before start. The first observed InvocationID is
persisted before policy checks, even for a rapidly exited service. Cleanup and
rediscovery always use that stronger lifetime once observed. A replaced
InvocationID, argv or cgroup refuses signals. The compatibility service manager
continues to use the scientific WorkingDirectory, while every new controller
capsule separately pins the absolute actual executing entry and its hash.

`freeze-release` captures the clean new branch/HEAD and all tracked bytes, old
science source, original admission and benchmark identity, and all retained
wave-1 lifecycle evidence. The new resource source and old science source are
both guarded. Prediction receipts continue to identify c036. A separate prior
resource capsule binds their wave controller to the new source and release.
The already-published scientific worker policy receipt is never appended to.

## Guards and scheduling

Controllers remain SCHED_OTHER on physical CPUs 15–29 from first execution.
At most two numerical workers use distinct single physical CPUs, SCHED_IDLE,
idle I/O and all six vendor thread settings equal one. Passive placement samples
five intervals and checks physical-core topology; it does not benchmark or
reserve delivered CPU. Every active worker and descendant is checked. Existing
baseline InvocationIDs, argv, source bytes, AT terminal, and advancing R146
`waiting_boundary` handoff remain protected. A lifecycle/handoff change defers
rather than mutating baseline jobs.

Whole owned RSS includes outer/coordinator/controllers/workers and descendants,
plus inactive draining predecessor cgroups, deduplicated by PID. Floors remain
192 GiB available RAM and 80 GiB disk, with a 24 GiB observed own-RSS soft stop.
These are observations, not a private hard quota. No shared cgroup quota is set.

The remaining full D plus worst S0 prefix is 12,277.296430 CPU seconds. A
1,178.430003-second single-replacement reserve raises it to 13,455.726433,
below the original two-unused-window adjusted capacity 14,524.094623. During D,
a componentwise split envelope dominates **every** possible A/B S0 package pair;
no scored candidate choice enters this budget. A concrete two-worker scheduling
projection retains the D-before-S phase barrier, each task's wall deadline,
current active logical slot and the full replacement wall reserve. Dispatch
follows a free current-window allocation, rather than only checking a CPU sum.
This is conservative feasibility under benchmark estimates, not guaranteed
future SCHED_IDLE delivery.

Original cumulative CPU, remaining unused/elapsed windows, per-task deadline,
and nonpreemptive packing are separate gates. Every attempt keeps a full frozen
reservation unless a valid completed observation binds the source, task,
policy InvocationID and current final seal. Valid observed partial overruns and
live lifetime-bound process CPU can increase that reservation. No incomplete
attempt earns a reduction; unknown attempts retain their full reservation.
The optional extra-seed bundle is admitted atomically against both budgets before
its first release. An unfunded set remains pending as a complete exact list;
it does not change the old scientific decision or establish a partial lead.

The 300-second delivered-CPU threshold remains .10 core. At most one durable
replacement token exists across both remaining waves. It is consumed before
cooperative stop; old InvocationID/cgroup drain is proven before a different
physical CPU can start the same task under the same lease/deadline. The reserve
retires only after durable exact predecessor-drain proof; all prior charges and
prospective remaining work stay accounted. Another event or ambiguous cleanup
stops. Sealed old-source checkpoints are reused unchanged.

Phase decisions wait for all workers and CPU-accounting tails to drain. Final
full-array verification runs as an owned idle-priority assessment payload inside
the current unexpired wave, using its validation reserve. No new admission or
ordinary-priority coordinator is used for that array computation. Only a sealed
old-source assessment yields `R151_RECOVERY_COMPLETE`; guard stops, unfunded
pending sets, zero progress and missing terminals remain explicit.

## Reproduction and validation

Run the focused pytest check with the pinned Python, CPU29, idle scheduler/I/O
priority and six thread variables one. Capability probes retain their required
ordinary-priority parent on CPUs15–29:

```bash
taskset -c 29 chrt --idle 0 ionice -c 3 env PYTHONDONTWRITEBYTECODE=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 BLIS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python -B -m pytest -q application/tests/test_pricefm_stage_r151_recovery.py
```

The focused tests exercise competing real subprocess claims and postclaim crash,
locks and namespace refusal; fake service source/ownership changes and startup
failures; all owned-RSS/floor, baseline, AT, handoff and lease guards; source and
CPU observation identities; global replacement crash semantics; fragmented and
phase-constrained scheduling; and fake complete versus unsealed wave behavior.
Release verification additionally runs the relevant R146/R148/R149/R150 and R151
regressions. See the external execution bundle for the final run count and hashes.

After normal dedicated-branch CLI Git commit/push/fresh-fetch hash equality:

- `501 ... probe --output /ABS/NEW_PROBE.json` runs actual disposable same-source,
  same-boot service capability/fault checks with **no numerical lease or model**.
  It includes the immutable existing rapid-exit/runtime/identity probes and an
  actual four-level 503→501→wave→payload chain with a confirmed forked descendant.
  All actual payload PIDs are checked before abrupt disposable outer-parent death
  and exact cgroup drain of every level. Never use this action against baseline.
- `501 ... freeze-release --output /ABS/NEW_RELEASE.json` freezes the dual source
  and unchanged numerical history. Both outputs must be new paths.
- `503 ... launch --release /ABS/NEW_RELEASE.json --probe /ABS/NEW_PROBE.json`
  starts the approved whole finite continuation; see the orchestration note.
- For EE alone, `501 ... launch --release ... --probe ...` returns `recovery_id`;
  `501 ... inspect --recovery UUID` reports strict state and retained terminal.
  Do not separately launch EE if `503` already owns the continuation.

Public helpers support explicit ownership composition by `503`. They never
provide baseline signal or scientific parameter mutation methods. Source release,
probe, tests and review must be frozen before creating numerical admission 2.
This source note does not itself claim a successful live probe or scientific
completion. The implementation remains **NOT_READY_FOR_INTEGRATION**.
