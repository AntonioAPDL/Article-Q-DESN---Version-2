# PriceFM R123 dependency-aware execution

## Scope and diagnosis

The certified successor is BG, outer Fold 1 training only, with three internal
rolling-origin validation splits. It is not a new official three-fold result.
The immutable shortlist contains three DESN/tau0 pairs and seven independent
AL VB quantiles per split: 63 primary fits. Exact CRAN exdqlm 1.1.1, frozen
R420/adapter code, zero prior centers, caps, reservoir seeds and 500 forecast
paths are unchanged. No exAL, joint, MCMC, screening, official validation/test,
registry, article or Overleaf work is authorized by this execution change.

The old controller assigns one worker to an entire quantile ladder. Its order
is 0.50, 0.45, 0.55, 0.25, 0.75, 0.10, 0.90. Actual dependencies are instead:

```
Normal -> 0.50 -> 0.45 -> 0.25 -> 0.10
              -> 0.55 -> 0.75 -> 0.90
```

On inspection, 57/63 fits and 6/9 scored panels were complete. Three fits were
running, while two additional tails had accepted parent initializers. Scheduling
these independent branches together avoids an unnecessary serial delay; it
does not justify increasing the scientific budget or restarting any live fit.

## Transition and preservation

R444 executes from its own dedicated task branch, while all numerical fitting
and scoring execute the original certified-successor checkout at full HEAD
`40d42d15a477c2f9d50dbc69b4eb9885da91ec29`.

Preparation verifies frozen sources, authorization, unique certified Normal
initializers, designs, contracts, output hashes, process identities and resources.
The existing 15 distinct physical cores remain the ceiling, with all numerical
thread environment variables fixed to one. Busy sibling cores and cores pinned
by another numerical task are excluded. At least 200 GiB each of available RAM
and free disk are retained. Fewer runnable models than cores is expected near
completion; no redundant model is launched to fill an idle core.

Only the exact Python scheduling PID is paused after its PID, start ticks and
command line have been verified. Pidfds are used when available. Muscat/Jerez's
EL8 kernel does not support them, so the legacy fallback repeats the full
identity check immediately before each individual PID signal. This leaves a
small non-atomic check/signal race; no process-group signal is ever used.
Its R children are never
signaled. A fresh inventory and immutable transition receipt precede termination
of that Python PID only. A failed pre-transition check resumes the old scheduler.
The replacement acquires all three existing controller locks and adopts the
unchanged running R processes on their original CPUs. Existing atom outputs and
contracts are never overwritten. An atom is submitted at most once and only
after its declared parent passes the unchanged acceptance policy.

The terminated Python wrapper cannot install the output hash receipt when its
old R child finishes. R444 therefore seals that child's complete six-file atomic
output only after checking its executed contract, target, dimensions, prior/API
declarations and process provenance. A separate receipt records the adoption.
Incomplete, unowned or mismatching output remains preserved and blocks progress.
Finite capped fits are not relabeled as formally converged. The existing
score-blind paired-cap check remains available only when the raw gate fails.

After all accepted atoms exist, the frozen ladder scorer and ranking code run
with every fitting call explicitly forbidden. Already scored panels are hash
verified and reused. Both existing closeout observers remain running. Frozen
sources, protected parent evidence and the original scientific terminal identity
are checked again before completion. Runtime receipts stay in ignored data_local.

## Verification and limitations

`application/tests/test_pricefm_stage_r123_dependency_resume.py` checks ready
sibling concurrency, adopted CPU preservation, exact-once scheduling, ancestor
and rejection handling, core limits, PID reuse, a real scheduler-only signal
transition with a surviving child, no overwrite, complete-output sealing,
target/prior/API validation, and rollback before takeover. The existing PriceFM
R123 regression suite must also remain passing on both hosts before activation.

No complete variational state is available in these AL exports; this change
does not claim to resume numerical optimization after an R-process failure.
Such a failure remains blocked with its evidence intact, not silently refitted.
Results are internal-selection evidence and NOT_READY_FOR_INTEGRATION until
the full scientific phase and later separately authorized outer evaluation end.

## Runtime interface

Use the pinned PriceFM Python and the same paths for both modes. `--owner-root`
is the clean frozen certified-successor checkout; `--frozen-code-root` is the
original connectivity checkout. `--attempt` is a separate ignored campaign,
not inside the scientific campaign's evidence tree. `--workers 15` is mandatory.
First run `--mode prepare --expected-controller-pid <verified PID>`, inspect the
receipt, then detach `--mode controller` with those identical arguments. Keep
its controller log outside both frozen evidence trees. Do not stop numerical
R workers or either evidence observer.
