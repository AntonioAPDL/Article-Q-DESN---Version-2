# R149 resource-only exit snapshot correction

The original scientific source remains frozen at
`0d562470f7112da0e94cc61b4bf18de8a93a5112` in the original R149 checkout.
No scientific source, configuration, prepared task, fitted model, scaler, seed,
completed task or sealed checkpoint is relabelled or changed by this correction.

## Observed failure and reproduction

At06:27:10UTC the original resource supervisor stopped with
`refusing signal: worker process group ownership is not proven`.
Its terminal reports cleanup_verified=true and zero baseline signals; the
private unit is inactive/dead with MainPID0 and no cgroup. All five baseline
service identities are unchanged. Six strict task packets (five full replays
and one MC replay) and404 sealed chunks remain valid, totaling3150 of4024
origin-clock windows. Unsealed interrupted attempts are retained.

A bounded real-child reproduction pauses the existing `/proc` reader between
`stat` and `cgroup`. The same PID/start/boot/process-group can then appear to
have a stale sleeping state and newly released root cgroups. The old predicate
rejects that mixed snapshot; a fresh read shows the same-lifetime zombie.
This is a second boundary of the previously understood Linux zombie-release
behavior, not evidence of an unrelated worker entering the private service.
The reproduction script/receipt are retained in the local R149 bundle.

The minimal shared-kernel correction rechecks an apparent ownership mismatch.
It accepts only a now-vanished process or a freshly proven same-lifetime zombie;
a persistent live cgroup mismatch, reused PID, changed lifetime, wrong process
group or unrelated process still fails closed. Regression tests cover both the
transient exit and the persistent forbidden cases. No signal is authorized
from the stale identity. The original resource/science checkout is untouched;
only this separate resource successor's493 copy changes.

## Separate controller, exact original budget

`496_supervise_pricefm_stage_r149_exit_safe_resources.py` imports the corrected
resource kernel but points SCIENCE by absolute path to the original494 source.
Scientific tasks therefore continue to validate producer0d562470 and reuse
their exact original contexts. The new resource release identifies its own
commit independently. Its external-source ledger pins all11 original source
files, the original scientific HEAD, stopped resource terminal, completed R148
terminal and the1250 preexisting immutable scientific artifacts.

The successor runtime is
`DATA/launch_prep/pricefm_stage_r149_ee_origin_coverage_20261023/muscat_resources_exit_safe`;
the separate service is `pricefm-r149-muscat-ee-idle-recovery.service`.
The original runtime and receipts remain in place and are also copied to the
continuation bundle's first-resource-attempt archive. The original partial
scientific closeout is archived before normal final closeout can replace it.

The imported lease must match the **original lease file bytes**, including its
ID, boot, epoch/monotonic start and expiry, and initial_output_bytes. There is
no new lease creation or renewal. Original expiry remains
**2026-10-23 07:52:40.082786UTC**. The new controller refuses absent, reformatted,
modified or extended lease imports. Admission also requires the old unit to
remain inactive with MainPID0 and empty cgroup, plus its successful cleanup.

The original18-task manifest and4024-window budget remain fixed. Completed
tasks are skipped and valid chunks loaded without forecasting again. Only an
interrupted unsealed chunk may repeat arithmetic under the identical task,
seed, paths and original producer; it never becomes evidence without validation.
No model is fitted and no future stage is automatically admitted.

All prior resource constraints remain: at most two SCHED_IDLE single-physical-
CPU/thread workers in0–29, idle I/O, SCHED_OTHER parent,192GiB available RAM,
80GiB free disk,24GiB own-RSS soft guard, no shared-controller quota writes,
reactive handoff/identity/source stop, own-only cleanup, Restart=no and
KillMode=control-group. Poll sleep is nominal0.5s, not a hard deadline.

## Required validation and launch

1. Prove the real exit race and test fresh zombie/vanish handling alongside
   live ownership/PID-reuse rejection and original resource regressions.
2. Test source/runtime separation, external provenance, predecessor drainage,
   exact lease import/no renewal, unchanged scope and actual idle policy.
3. Independently review; commit/push the resource-only branch and freshly fetch
   its hash. Keep the original science checkout clean at0d562470.
4. Verify original immutable artifacts, stopped unit and unchanged baseline;
   copy the lease bytes into the new runtime. Freeze a new resource release,
   prove its policy, then launch only the new private unit with file logs.
5. Verify actual PID/thread/cgroup/priority and resume proof: previously sealed
   tasks/chunks unchanged, remaining work only, identical lease. Continue to
   strict scientific completion or a legitimate original-lease/guard stop.
6. Final reporting records both source identities and both resource attempts,
   all original cache hashes, strict18-task seals, scientific interpretation and
   independent resource drainage. No manuscript/main integration is implied.
