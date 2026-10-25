# R153 current runtime observer

`application/scripts/pricefm/518_inspect_pricefm_stage_r153_runtime.py` is the
read-only entry point for future health checks after the explicit R153 release.
Run the baseline lane on Muscat and the CZ lane on Jerez, using the same frozen
R153 source worktree and pinned Python as the current authority:

```sh
/path/to/pinned/python -B application/scripts/pricefm/518_inspect_pricefm_stage_r153_runtime.py baseline
/path/to/pinned/python -B application/scripts/pricefm/518_inspect_pricefm_stage_r153_runtime.py cz
```

It prints a JSON observation to stdout. Exit 0 means that the selected registered
lane passed its current-phase checks. Exit 1 includes a missing registration,
unattested launch, failed verification, blocked marker, or expired waiting grant.
An optional `--output /tmp/new-health-observation.json` creates a new external
file exclusively; it refuses replacement, canonical project/data destinations,
and symlink destinations. Imports suppress bytecode writes even without `-B`.
It performs no service actions, signals, launches, fits, forecasts, or mutations
of the authority, runtime, cached ledger, scientific evidence, or source files.

The baseline resolver reads the old R152 baseline's `explicit_successor.json`,
checks the sole 3+1 activation registration, authority path/hash and source,
then calls entry 514's validated entry 513 owner inspector. The historical
blocked generation-three record remains evidence of the old exhausted scope.
It does not override the explicitly registered R153 owner. Tail dispositions
can be complete without a live owner; this does not imply successful closeout
of quarantined scientific targets or completion of the global campaign.

The CZ resolver reads R153/CZ's global create-once
`single_activation_claim.json`, then validates that exact authority using the
local entry 516/515 API. It imports only the selected lane, so Muscat baseline
observations do not load the Jerez-specific CZ process dependencies.

| Phase | Required evidence | Meaning |
| --- | --- | --- |
| Not registered / activation pending | No exact registered live capsule | Current health is unproven; no retry is authorized. |
| Waiting / boundary ready | Source-bound authority, original waiter drain, fresh exact unit/process/invocation, finite systemd timeout and CPU allowance, fresh progress, current predecessor boundary | Resource gate is healthy; zero scientific dispatches are reported. |
| Delegation pending | Sole scientific claim exists, no exact activation capsule yet | One dispatch has been consumed; health is unproven and no repeat is allowed. |
| Delegated | Exact original-science claim, source/config-bound activation, fresh live scientific control lifetime and cgroup | Original R144 science is running. Its own models may occupy the slot. The empty-slot predicate is not rerun. |
| Complete | Exact original unpromoted 24-fit/365-pair result, original campaign terminal, source-bound sealed 12-row fold/operator closeout, all payload hashes, actual recorded control lifetime and model cgroup drained | Original CZ scientific protocol finished; no promotion is implied. |
| Blocked / expired | Explicit failure marker or expired unclaimed waiter allowance | Unhealthy; no automatic retry or new allowance. |

The waiter clock bounds waiting. A scientific claim made before its expiry can
continue under the already fixed original scientific graph afterward. Every
observation still verifies source and exact authority identity. A blocked marker
takes precedence over progress or a partially published terminal. An inactive
unit alone is insufficient proof of scientific drainage.

Focused hermetic tests are in
`application/tests/test_pricefm_stage_r153_runtime_observer.py`. These mock only
host inspection APIs and never contact real user services. Entry 517 and its
separate tests verify the immutable science-preparation bundle; entry 518 does
not admit those future proposed diagnostics or certificate experiments.
