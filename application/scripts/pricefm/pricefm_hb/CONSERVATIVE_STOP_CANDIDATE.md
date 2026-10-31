# Conservative startup stop candidate (r176)

The failed CPU case last proved an upper of 2.729893 seconds against the
original 2.73 active ceiling, resumed the owned group, and next observed a
one-core upper of 2.740779 before stop confirmation. The original stopped-state
proof correctly refused that unknown running work. This is a decision-timing
problem; a clean drain does not convert the failed 125 receipt to required 124.

`startup_stop_candidate.py` verifies the exact original supervisor SHA256
`7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1`,
loads those verified bytes, and changes exactly three comparisons inside its
monitor `run`: both CPU decisions use the original active ceiling minus 0.25
seconds, and its wall decision uses the original inner deadline minus 0.25
seconds. The original independent guardian, stop-upper ceiling, five-second
stop window, original wall deadline, process ownership, seccomp filter,
hard limits, inherited-history accounting and drain remain unchanged.

The 0.25-second lead is a fixed conservative reserve, not a larger grant.
It exceeds the observed 0.01-second resume interval and 100-Hz tick rounding.
It does not promise a bounded scheduler/kernel delay: if stopping cannot be
proved inside the original ceiling/window, the original failure remains.
Every command's startup, wrapper and compilation CPU remains in the unchanged
pre-first-fork lifecycle anchor. No original file is patched on disk.

The candidate return adds its profile, unchanged-supervisor hash, lead policy
and early decision ceiling. The new kernel driver requires those fields for
successful and CPU/wall-boundary cases. Injected monitor/guardian death may
prevent a candidate monitor return, so the death rows separately record the
invoked profile and whether a profile receipt was required/present. Their
original exact death, no-receipt and descendant-drain expectations are retained.

## Source-bound staging and R startup

Use the separately named native controller `pricefm_hb.startup_batch_stop`.
Its `NAMES` closure contains the original nine files plus:

- `startup_stop_candidate.py`
- `startup_stop_helper.py`
- `startup_batch_stop.py`
- `startup_batch_stop_worker.py`
- `startup_batch_stop_kernel.py`

Thus a new publication/readback and independent source review must bind all
14 exact files before preparation. The controller stages and invokes the new
worker. The new worker runs the candidate kernel driver for the inventory role
and the candidate helper for the R role. Native administrative operations keep
their existing outer original guardian and 240-CPU complete control envelope.
Node13, one CPU/thread, 8 GiB, no requeue/retry and all finite role limits remain.

Construct new R metadata plans with
`startup_stop_helper.source_pins("R_STARTUP_METADATA_ONLY")`. Their closure
contains the candidate adapter/supervisor and the pinned original adapter and
supervisor. Finalization requires the actual candidate receipt before using
every original adapter gate. A proof of another source cannot qualify this
candidate. Existing R-plan proposals and expired roles must not be reused.

For the controller CLI, insert the staged source package parent into
`sys.path`, import `pricefm_hb.startup_batch_stop`, then call `main()` under
the existing original outer guardian with the unchanged per-action hard cap.
Arguments remain `ACTION --config CONFIG --role ROLE` and the existing bundle,
review and prior-guard options. No payload interpreter runs on the login node.

Metadata/mocked tests validate the constrained AST difference, retained hard
failures, adapter source/authority/finalization gates, native transport/accounting
rules and the candidate packet entrypoint. They are not a kernel, R startup,
scientific runtime, parity, real-target bridge or production acceptance proof.
The actual six-case compute matrix must pass under fresh reviewed authority
before the separately admitted R role can be submitted.
