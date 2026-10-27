# Finite R154 CZ control continuation

R154 continues the original R153 wait for the entire R143 queue and delegates exactly the unchanged original R144 CZ graph. It adds one explicit finite control activation. It changes no numerical source, inputs, rank, model cap, certificate gate, baseline mask, cached grant or old ledger. The original NO3 quarantine alone is allowed; any new PT/SE3 failure blocks.

The active R153 source remains17bd756aacb0f4ce458978f10af45c75200b9a65. New code runs from its own isolated clean published worktree; actual control and scientific producer identities remain separate. The old authority/activation/claims/immutable receipts are pinned by exact bytes and never rewritten. Mutable old progress and heartbeat bytes are archived immediately before fencing. New charges have their own ledger, with no old credit, refund or clock reset.

## Scope and pricing

The new waiter uses CPU29/Nice10 and one thread for itself and synchronous administrative helpers. Numerical work is an independent systemd unit, excluded from waiter CPU. New wall expiry is at most seven days from authority creation, and therefore never later than seven days from eventual handoff. No automatic retry or additional activation is possible.

Six real source-bound samples span five60-second intervals. The first also probes existing complete regional seals and the full process census; it does not fabricate unfinished PT/SE3 closeouts. Maximum observed warm measured self+reaped-admin CPU/hour prices the whole168-hour window with25% contingency. Proof reserve is max(240CPU, all new actual charged private attempts), administrative reserve120 and final publication reserve90. Select3600 only if rate<=15 and all reserves fit; otherwise select at most6400 only if the complete formula fits. Otherwise block/reprice. Actual proof CPU and reserved unused proof headroom are separately labelled.

The control check-wall bound includes explicit extra headroom above the maximum measured cold/check sample. Require60-second polling + that bound +5-second publication margin<=90 seconds. Actual production loop checks fail closed if their check wall exceeds the admitted bound. Future PT/SE3 closeout sizes remain unmeasured; their final full gate must pass freshly. Private profiling kinds and /tmp namespaces cannot be dispatched by the production run/delegate actions.

Native per-unit CPU counters may be unavailable. Owner heartbeat binds measured self/reaped-admin CPU to PID/start/boot, actual argv/cwd/source, unit/InvocationID and single CPU. An external observer reads fresh owner proc CPU and bounds unsampled admin CPU by elapsed wall on that CPU. It never substitutes observer CPU or charges science. No shared cgroup quota/signal is used.

## Safe handoff ordering

1. Exclude competing releases with the new handoff lock; it cannot fence unmodified old code. Reject any old science claim, launch, activation, terminal, scientific preparation or task registration.
2. Recheck exact old PID/start/boot/argv/cwd, InvocationID, unit, no-restart/process-kill policy and sole administrative membership. Archive current progress/heartbeat. Fence only that exact administrative lifetime through a kernel pidfd; no plain PID or cgroup fallback is permitted. Python builds without pidfd wrappers use a narrowly scoped x86_64 syscall adapter, proved against a disposable private owner. Unsupported kernels block.
3. Prove old lifetime, classified administrative children and its specific systemd cgroup physically drained. Never stop the R143 unit or any fit.
4. Only after drain, acquire the original R144 supervisor and the new cross-lineage science lock. Recheck all old science/preparation/launch evidence, sources and queue state. If science appeared in flight, preserve it and abort successor activation.
5. Freeze the handoff receipt and consume the one new activation. Release the original supervisor before launching the waiter that needs it for its capsule. Independently attest new readiness and publish create-once successor registration.
6. Immediately before science, revalidate authority, old physical drain, every prior claim/preparation, actual full queue/closeout/cgroup/numerical boundary and CPU/wall funding. Under the cross-lineage lock create one global and one matching local science claim before starting original R144 delegation. A partial claim failure remains spent.

The original R144 supervisor stays held by the new waiter and is acquired by its delegated controller only after the waiter releases it. Original workers, numerical APIs and closeout semantics remain frozen. The observer verifies actual new roles and original R144 full closeout, including physical drain, before reporting scientific completion.

## Operators

Use the pinned runtime Python and absolute scripts in the verified new worktree. All output files are create-once.

- `519_release_pricefm_stage_r154_cz_continuation.py preflight`: current old waiter/queue, read-only.
- `... probe --output UNIQUE_RECEIPT`: real disposable /tmp control unit, six60s samples, actual source/accounting/expiry/drain and a separate exact pidfd stop proof; zero posterior fits. Every failure receipt and full conservative charge is retained.
- `... prepare --probe-receipt RECEIPT [--probe-receipt EARLIER_RECEIPT ...] --output UNIQUE_OUTPUT`: prepare a concrete immutable finite authority; no production fence or activation. Every new attempt, including failed ancestors, must be listed once. The latest proof must match the current published source.
- `... handoff --authority EXACT_AUTHORITY --output UNIQUE_OUTPUT`: production administrative action, only after independent source/proof/authority/handoff review. No separate fence/launch commands can bypass the reviewed sequence.
- `519_inspect_pricefm_stage_r154_cz_continuation.py`: source-specific read-only current health.

Tests cover scope/price/freshness, immutable lineage, private-role rejection, old/new claim races, exact PID lifetime protection, additional children, duplicate activations and actual supervisor lock release. Real private proof remains mandatory before preparing authority. Publishing or preparing this source is not scientific completion.
