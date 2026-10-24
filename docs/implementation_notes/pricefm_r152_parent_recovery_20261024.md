# R152 cached-parent recovery under the original clock

The original 507 coordinator checked ownership during the roughly 137 ms gap
between partition release and the first committed baseline heartbeat. It exited
before any cached admission. The independent baseline continued normally.

Keep the active source at `cba0b6c861f20ebdffcd970d59b0fa38afd80a42` untouched.
The original master, failed parent, blocked and terminal files remain immutable.
T0 is October 24, 2026 at 13:43:42.668789 PDT; its original expiry remains
October 25 at 01:43:42.668789 PDT. This recovery creates no new time allocation,
numerical window, posterior fit, study or CPU allowance.

`509_resume_pricefm_stage_r152_cached_pool.py` combines the finite cached parent
and broker roles. It composes the original cba public resource helpers and
scientific adapters without changing their globals. Worker resource execution
remains cba; EE scientific execution remains c036. The new coordination source
has its own committed identity. All studies use the original canonical ledger.

`510_release_pricefm_stage_r152_parent_recovery.py` freezes that identity,
validates the exact failed predecessor and empty admission inventory, runs
disposable lifecycle probes, and appends one recovery authority. It requires a
clean dedicated branch and fresh normal-CLI remote equality. The authority pins
the original master SHA, T0, expiry and old capsules; it never replaces them.

The new controller registers its honest capsule at the previously unused
canonical `development/controller.json`. The original independent 505 guardian
monitors it. Workers bind to the new controller. The original 504 baseline owner
independently checks that controller's actual exit before returning the loan at
a natural boundary. Baseline scientific sources, targets, iteration limits,
quarantines, live affinities and Jerez remain unchanged.

All scheduling calendars and whole claims fit the attested kernel lifetime
and its reserved cleanup cutoff as well as the original master. The shorter
planning horizon is an in-memory calendar bound, never a replacement master.
Recovery stops early enough to drain before the original expiry.

Failed-parent CPU and every post-T0 probe remain charged within the original
1,800-second shared-control allowance. Unknown CPU counters retain conservative
wall/core bounds. Live control accounting includes waited-child CPU and an
explicit conservative shutdown tail. None of those reservations represents a
measured spend or grants additional capacity.

Full source/authority verification runs at most once per five-second poll.
Every guard still checks immutable authority/master identity, boot, original
parent drainage, canonical baseline ownership and current unit policy. Each
worker retains the original first-exec source and policy checks. This avoids
repeatedly hashing the same 409-file source map within a single poll.

Use the existing pinned Python 3.11 runtime, with the six numerical-thread
environment controls equal to one. The release actions are:

```text
510... freeze --output RELEASE.json
510... probe --output PROBE.json
510... launch --release RELEASE.json --probe PROBE.json
```

Pass every post-T0 recovery probe receipt in chronological order with repeated
`--probe` arguments, including failed probes, so their costs remain charged.
Launch accepts one recovery only and requires complete cleanup and a successful
same-source lifecycle probe. A failed probe is never overwritten. Disposable
units perform no forecast or fit.

Focused tests cover authority and source binding, clock preservation, empty
inventory, old-parent drainage, control accounting, whole-window containment,
publication waiting, lifecycle cleanup and scientific-loop compatibility.
Operational receipts and the implementation audit live outside the frozen
source tree under `local_trackers/pricefm_chat_continuation_20261021/`.

Code validation is separate from scientific completion. EE delivery must still
be demonstrated before FI's own benchmark; FI and DK₂ may defer at their
unchanged price, full-prefix, calendar or scientific gates. The original expiry
is a resource horizon, not a prediction of completion or improvement.
