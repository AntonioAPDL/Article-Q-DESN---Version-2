# Independent native-actor execution closure

`scripts/mq_native_external_terminal.py` does not launch a unit, compile a
library, read a scientific model or score a forecast. It provides separate
stop-post and final-inactive checks for the one-purpose retained build or
native replay. A numeric receipt alone is insufficient: the actual native
time record, issued unit, exit state, output manifest and source/purpose
identities must agree. The final readback cannot replace the actual successful
stop-post evidence.

During stop-post the unit must be loaded from its pinned issued fragment,
have no live MainPID, show a successful exited main process, and actually be
deactivating in stop-post with its expected user control group. The service
exit environment must report success/exited/zero. A later final readback
requires inactive/dead and the matching successful hook, unchanged outputs,
purpose/resource identities and payload native accounting. Collected dead
units may have cleared control-group/execution-code fields only through the
explicit accepted collected-state case. An unexecuted inactive unit is not
accepted as a completed actor.

Payload and hook CPU/wall/RSS, administrative bytes and retained output bytes
are checked separately. Native GNU-time parsing rejects missing/duplicate
fields, malformed clocks, nonfinite values and noninteger exit/RSS counts.
Generated output inventories reject symlinks and nonregular members. The
replay manifest must match exact membership, size and hashes. The retained
build receipt instead binds its three library roles and compiler logs, while
the external inventory seals every retained build output.

The issued fragment's command/environment/limit binding is verified against
one prospective `service_definition()` shared with issuance, not established
merely by hashing an arbitrary unit file. Unknown or duplicate service
directives, changed command arguments, expanded caps, changed environment,
extra pre-start commands, or environment files are rejected. The effective
loaded-unit readback separately requires no drop-ins, no pending daemon
reload, the exact single serialized payload/hook arguments, environment,
working directory, affinity, limits and kill/restart policy. Generated text
tests do not replace these actual systemd properties at execution closure.
Purpose creation, current CPU ownership, complete process-group termination,
the external hook's own accounting and independent closure remain explicit
administrative responsibilities; this helper is not a general scheduler.

Numerical qualification and successful execution are different decisions.
A finite replay may finish successfully with numerical status REVIEW. That
does not grant numerical accuracy, production consumption, a general C ABI,
scientific-result promotion or article publication. It must not be relabelled
as a crashed worker merely because it misses an accuracy gate. Conversely,
an apparently favorable numerical status never excuses incomplete execution
accounting or a failed source/runtime/input guard.

`application/tests/test_mq_native_external_terminal.py` exercises generated
metadata only: native-time parsing, actual stop-post and final linkage,
output paths/pins, manifest membership, receipt scope, REVIEW retention and
prospective and effective unit command/environment/cap mutations, override
and stale-load negatives, and an entirely mocked systemd-property parser.
It queries no real systemd unit, compiles no code, and reads no scientific
payload, model, design, posterior or future truth. The generated fixtures do
not authenticate any actual issued unit or completed native replay.
