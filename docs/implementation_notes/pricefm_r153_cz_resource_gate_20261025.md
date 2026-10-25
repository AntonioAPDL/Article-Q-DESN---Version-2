# R153: explicit CZ resource-boundary resolution

R143's known NO₃ numerical failure must remain visible. Its eventual terminal
`R143_QUEUE_DRAINED_WITH_QUARANTINED_FAILURES` is incompatible with R144's old
clean-predecessor requirement. This resource release preserves that failed
terminal and all NO₃ certificates instead of relabelling the queue as clean.
The user explicitly requested implementation of the October 25 reviewed plan.

## Scientific independence and exact scope

The original `486_run_pricefm_stage_r144_cz_training_fallback.py` consumes the
frozen CZ preparation, rank-three CZ RHS choice and six certified CZ
statistics/RHS prerequisites. It does not consume NO₃ fits or any other R143
region's newly generated forecast/model output. CZ's original feature bank can
contain its already frozen cross-region input data; this is different from a
scientific dependency on a newly completed R143 model.

The new effective config differs from the original JSON in exactly one field:
`predecessor_terminal_status` is the truthful degraded status above. No source
file or failed terminal is modified. Candidate, prior, quantiles, seeds, cohorts,
cap 300, 15 physical CPUs 15–29, source/target hashes and all scientific inputs
remain the original R144 contract. The authority records both config hashes
and the effective JSON explicitly.

The only permitted R143 quarantine is the two precisely reviewed NO₃ q0.75
failed targets. Their original task, packet seal and certificate SHA256 values
are embedded in the new control source. An additional PT/SE₃ failure, a changed
NO₃ certificate, an incomplete region, a new process or an ambiguous boundary
blocks the release. It does not relax a certificate or admit a repair fit.

## Ownership and source layers

`515_resolve_pricefm_stage_r153_cz_gate.py` is the actual new control entry.
`516_release_pricefm_stage_r153_cz_gate.py` owns private proof, authority
preparation, the exact old-waiter fence and one waiter launch. The original
scientific entry and worker code are unchanged R144. The delegated numerical
unit truthfully runs the new 515 entry with `delegate` and an explicit
`--delegated-entry` pointing at old 486. It calls the unchanged public
`controller(effective_config)` function, rather than patching imports or
pretending that its actual entry is old 486. The scientific function continues
to create original R144 preparation/worker argv/closeout provenance. A separate
execution bridge pins the actual new source, unit, InvocationID and lifetime.

Jerez must have clean, exact Git checkouts of:

- R153 `work/pricefm-r153-control-lifecycle-20261025`, at the released commit.
- Existing R144 `f96fcb0e3dc47da236d656cda2f0e58fb537ee1f` and R143
  `28d190306ae505c4784984d238c89cd225fab9b4`, plus their existing frozen R141
  numerical dependencies.
- Cold process-reader dependencies: R152 parent recovery
  `cbf11c6e41d6be49ebdf9c3648fb79d2e641e234` and its sibling resource core
  `cba0b6c861f20ebdffcd970d59b0fa38afd80a42` at their established absolute
  worktree paths. Only `511.RecoverySystem` metadata methods and pure resource
  core are used; no Muscat runtime, cached controller, 512 release or EE tree is
  activated or imported.

The private reader is reused because its bounded empty-exit and administrative
SSH handling was independently tested and exercised on the actual hosts.
Sources must be deployed through normal Git at exact published heads. Dirty
source copying or changing the original worktrees is not part of deployment.

## Bounded authority and accounting

The new namespace is
`DATA/launch_prep/pricefm_stage_r153_control_lifecycle_20261025/cz/<uuid>/`.
The entire CZ gate has one create-once global activation registry, not one
renewable activation per UUID. Its waiter has `Restart=no`, `KillMode=process`,
CPU accounting, a maximum seven-day independent systemd wall timer and a
1,800 CPU-second control allowance. Failed private proofs retain their complete
conservative debit. A 120 CPU-second preparation/fence/launch reserve and
90-second final-publication reserve remain inside that allowance. The script
checks measured waiter/admin CPU, remaining original deadline and immutable
source/evidence again immediately before its create-once scientific claim.

The numerical graph runs in a separate unit so its existing R144 scientific CPU
is not disguised as new waiter-control CPU. The seven-day deadline is a
pre-dispatch waiter limit, not a renewed cached allocation or a new cap on the
already authorized R144 mathematical worker. There is one numerical dispatch
claim and no automatic model retry. Old cached admissions, master, expired
clock and every cached ledger record remain unchanged.

## Deployment sequence

Use the pinned Python 3.11 environment and invoke 516 on actual Jerez, with
unique output paths outside the committed source. No production service is
operated before the committed-source private proof succeeds.

1. `probe --output UNIQUE_PROBE.json` starts only an owned private transient
   unit. It verifies actual source/lifetime/unit/cgroup/accounting/expiry and
   its cooperative exact drain. It launches no model or production service.
   Preserve all failed receipts and any cleanup reconciliation; no cost refund.
2. `prepare --probe-receipt RECEIPT ... --output PREPARE.json` creates an
   immutable authority only after source pins, original sole-process waiting
   service, R143 owner and exact NO₃ failure hashes match. Include all earlier
   private receipts. The final successful proof must match the final released
   control commit. The source-bound original waiter progress is archived.
3. `inspect --authority AUTHORITY` is read-only and normally reports that the
   entire R143 queue has not yet drained. A partial boundary is not dispatch
   permission.
4. `fence --authority AUTHORITY --output FENCE.json` is the explicit production
   control operation. It stops only the exact old R144 waiting lifetime, after
   proving its InvocationID/cmdline/cwd, sole cgroup PID and original known
   quarantine make numerical launch impossible. It archives current progress
   and verifies actual PID/unit/cgroup drain. No scientific process is signalled.
5. `launch --authority AUTHORITY --output LAUNCH.json` consumes the single
   global claim and starts the new finite waiter. No automatic retry is allowed
   if launch/activation fails. Fresh source/old-control proof and independent
   systemd timeout attestation are mandatory.

The waiter holds both its owner lock and the original R144 supervisor lock. It
publishes new progress plus a truthful execution-source bridge in the mutable
current R144 resource pointer. Original pointer bytes remain archived.

## Boundary and handoff proof

A terminal alone is insufficient. The guard requires the full fixed R143 queue
disposition, exactly the approved NO₃ failure, valid source-bound regional
closeouts for every other assigned region, an inactive R143 unit, absence of
its original process lifetime, empty recorded/current cgroups, and a fresh
strict census without predecessor/known numerical work on slot B. It repeats
unit/cgroup/lifetime and exact terminal-byte checks to reject a restarting or
changing predecessor. A reused PID is compared by fresh kernel lifetime before
reading unrelated protected metadata; an unknown live protected process still
fails closed in the generic census.

Only then is the one scientific claim created and the new explicit delegate
unit launched. The waiter exits and releases the old supervisor lock. The
delegate independently reacquires that lock, revalidates source/deadline and
boundary, attests its actual invocation, and invokes old 486. Original R144
controller certificate, fit, forecast and closeout guards continue unchanged.
A failure retains its exact claim and stops future dispatch; it never signals a
model, changes its cap or rewrites a quarantine as success.

The current long-running PT/SE₃ jobs are not drained or accelerated by this
release. Waiting is a correct deployed state. CZ scientific completion is a
future measured result, not something inferred from a successful gate launch.

## Verification

`application/tests/test_pricefm_stage_r153_cz_gate.py` covers truthful degraded
status, exact approved failure/source/config scope, full queue/closeout guards,
live and orphan cgroups, source/terminal races, strict numerical conflict
classification, broad administrative dispatcher masks, independent timeout and
CPU guards, one-shot activation/dispatch, launch failures, old-waiter fencing
and immutable claims. Tests create no models or production services.

The actual Jerez host reports `CPUUsageNSec=[not set]` despite
`CPUAccounting=yes`. The first private proof correctly failed on that field,
with exact cleanup and its 5.637701107138455 CPU-second debit retained. The
corrected source measures the waiter's own CPU plus reaped synchronous
administrative children using process time and `getrusage`; it cross-checks
fresh `/proc` CPU and never counts the separately launched scientific unit.
A native unit counter, when available, supplies an additional conservative
maximum rather than replacing the measured evidence.

Only the new administrative waiter and its inherited helper children are
confined to CPU29, with Nice10. Existing scientific affinities and the separate
R144 unit are unchanged. Each measured budget heartbeat binds exact authority,
execution source, unit/InvocationID and PID/boot/start lifetime. The pure-read-only
`observe_waiter_cpu` API uses fresh owner `/proc` CPU, last reported reaped
children and an elapsed-wall upper bound under that one-CPU constraint. It
rejects stale/unbound/reset/nonfinite evidence and escaped administrative CPU
masks; it never charges the observer's process CPU. Both owner and observer
retain the same 90-second publication reserve inside the 1,800-second allowance.

The corrected private proof records a positive actual own/admin CPU witness,
checks it against kernel process accounting and reserves the entire private
one-CPU 15-second systemd lifetime, including failures. It retains all prior
failed receipts and verifies their exact runtime bytes against committed Git
ancestors; only the final successful proof may match the active release head.

The private transient-unit receipt supplies actual-host source/accounting/drain
proof. It does not claim to have observed future R143 queue drainage or to have
run CZ. Publication and final health records must separate these states.

## Isolated CZ-only release correction

The original R153 baseline source at `bfe540920998eeeef398cfa1aad93f8d408ed6ca`
is active and remains unchanged. CZ's first preparation stopped before any
authority or activation because the original services execute canonical
relative script tokens under their frozen working directories. Actual R144
argv uses `application/scripts/pricefm/486_run_pricefm_stage_r144_cz_training_fallback.py`
with `run --poll-seconds 30`; R143 uses its corresponding 485 entry and poll15.

The isolated `pricefm_r153_cz_release_20261025` checkout validates exactly
PY/-B/script/run/poll at their original positions, accepting only the literal
absolute entry or that exact canonical relative spelling under the exact
frozen cwd. It records raw argv unchanged plus a separate resolved-script
witness. Wrong cwd, symlinks, script position/path, interpreter, flags and
suffix arguments remain rejected. The actual private proof now runs both
original live `control_snapshot` preparation predicates read-only before any
private-unit start; failures stay inside its receipt/cleanup/charge handler.

Old CZ private receipts from the canonical original control root and branch
are accepted only as paid history at the explicitly recorded 37799978 and
bfe54092 commits, with Git ancestry and exact runtime-blob verification. They
can never satisfy the new checkout's final successful proof. The original
failed preparation, diagnostics and new release administration remain covered
by the existing 120 CPU-second administrative reserve, without refunding
previous probes or replenishing the one activation.

Run baseline observations from the original active source and CZ observations
from this isolated CZ source. Their actual entry/root/source chains differ; do
not execute the baseline release from the CZ checkout. No frozen baseline or
scientific worktree is edited by this compatibility correction.
