# R151 finite continuation orchestration

`503_orchestrate_pricefm_stage_r151.py` is the outer standard-library coordinator
for the approved sequence: recover the two unused EE admissions through 501,
verify its disposition and actual owned drain, then conditionally run the single
frozen DK_2 cached screen through 502. It does not alter the immutable c036 EE
scientific source, targets, original preparation or completed forecast packets.
No AL fit, new geometry, official evaluation, promotion or baseline repair is
admitted by this workflow.

The outer service has one fixed **630-minute maximum**: 245 minutes for EE
recovery, 20 for the separate regional benchmark, 360 for three two-hour regional
waves and five for transitions. Every numerical admission is separately created
once and never renewed. Numerical waves retain 90 minutes for projected compute
and 30 for validation/drain. Unused time in a terminal window is discarded.

Before launch, commit and verify the dedicated source, then produce the 501 dual
source release and successful same-source/boot capability probe. Under the fixed
CPU/thread parent policy, the only production entry point is:

```text
503_orchestrate_pricefm_stage_r151.py launch --release RELEASE.json --probe PROBE.json
```

`launch` returns `R151_FINITE_ORCHESTRATOR_LAUNCHED`, a UUID `run_id`, its evidence
folder and exact coordinator intent/attestation capsule. `inspect --run-id UUID`
reads the current heartbeat and eventual terminal. `coordinate` and
`regional-wave` are service-internal commands whose argv ends in the exact unit
identity. `test-hold --controller-unit UNIT` is restricted to disposable
`pricefm-r150-test-*` probe units and creates no lease or numerical payload.

The coordinator awaits its immutable attestation before launching work. The EE
coordinator is bound to it; each wave is bound to the appropriate parent and
each payload to its wave. Parent death, finite runtime expiration and actual
InvocationID/cgroup ownership are independently guarded. The actual capability
probe exercises the outer/controller/payload chain and descendant cleanup.

An EE guard, ownership, starvation or cleanup stop blocks DK_2. A partial
deterministic or S0 pool also blocks DK_2. Admission requires either a strict
scientific assessment with its final source-bound seal, or a fully complete D
and matched C0/A/B S0 prefix with an explicit entire-set unfunded MC disposition
and independently drained owned lifetimes. An incomplete MC comparison never
establishes a scientific lead.

DK_2 receives its own `502.PREP/muscat_resources` ledger and admissions
`benchmark`, `1`, `2`, `3`. Its fixed cost-only benchmark runs only inside its
1200-second admission; D and S run only in numerical waves. The benchmark is
charged separately from the numerical ceiling. Every regional wave holds the
canonical old `controller.lock`, so the EE and regional lanes cannot dispatch
concurrently. All owned worker/controller lifetimes, including drained history,
remain in whole-tree membership/RSS accounting. The global ceiling remains two
nonexclusive IDLE numerical workers on distinct physical CPUs 15–29, vendor
threads one and idle I/O; parents remain responsive SCHED_OTHER.

The initial resource gate reserves the complete D pool, the frozen C0/A/B S0
prefix and one maximum component replacement. It checks all prospective locked
A/B scenarios for phase-respecting nonpreemptive packing, because the largest
aggregate CPU scenario need not have the hardest task shapes. Active tasks keep
their current worker slots. Dispatch follows admitted current-window slots;
the complete D barrier precedes S0.

All qualified extra seeds and the shared control are funded atomically. The
parent waits for worker exits and accounting tails, computes fresh cumulative
and remaining-window capacities and complete-set packing, publishes
`resource_budget_view.json`, then calls 502 `advance` with an explicit finite
allowance. The maximum regional stochastic count is 27. Unfunded extras remain
pending with an explicit resource terminal, no scientific completion claim and
no automatic follow-on.

Completed component CPU is charged once across every source/task/policy/final
seal-bound attempt, including whole-process CPU plus a five-second exit
allowance. Unknown or unfinished attempts keep full component reservations;
known live overruns raise their charge. Missing prior or orphaned accounting
cannot erase an attempt. The regional replacement token is global across its
three waves, consumed before stopping the predecessor, and frees its reserve
only after exact InvocationID/cgroup drain proof. A replacement must fit the
unchanged lease and the complete remaining cohort projection.

Full retained-array finalization runs as a separately owned 502 `__finalize__`
IDLE payload inside the current finite lease's validation reserve. Parents only
verify lightweight metadata and final seals. If a controller exits without a
terminal, its owned lifetimes are drained and the workflow stops; no further
admission is inferred from an exit code.

The outer terminal status is one of `R151_FINITE_WORKFLOW_COMPLETE_NOT_PROMOTED`,
`R151_FINITE_WORKFLOW_DEFERRED`, or `R151_FINITE_WORKFLOW_GUARD_STOPPED`. It records
cleanup evidence, EE recovery UUID, regional queue/pending disposition, source
HEAD, zero new fits, zero baseline worker signals, no renewals and no promotion.
Successful resource deferral does not mean the science is complete.

Focused tests cover finite admission order, exhausted windows, forbidden
renewals, EE interstage gates, all-scenario barriers and fixed slots, atomic S27
composition, component/attempt accounting, missing ownership lineage, exact
replacement drain provenance, benchmark budget deferral, bounded wait and owned
cleanup. LT/AT repair contracts remain separate preparation dossiers.
