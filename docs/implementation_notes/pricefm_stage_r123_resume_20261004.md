# PriceFM R123: Progress-Preserving Resource Recovery

## Audit and decision

Scope is BG R123 only. The committed scientific engine remains at
`7ae8d6f578000ab17cd30567a23f7b806028cee0` in its original fitting worktree.
Do not modify its executed sources, old results or preparation identity.
The successor recovery branch adds an execution controller, not a new model.

The completed inventory is 48 pilot cells, 1,200 broad cells and 50 third-seed
cells: 646 fitted and 652 explicit washout exclusions. The three-seed ranking
has 49 eligible structures, sufficient for the planned 30-structure RHS stage.
The controller exited before any RHS fit because its second CPU preflight
could see only its previously pinned 15-core mask. Twelve cores in that mask
were idle, while a fresh server-wide audit found 27 idle physical cores.
This was neither a numerical fit failure nor evidence of lost progress.

The leading two-seed Ridge comparison gives AQL .07292454 versus .07409790
for the unchanged control, a modest 1.58% improvement, with lower 80% coverage
(74.01% versus 85.70%). Its third-seed AQL is .07217975. This does not establish
a quantile winner or an improvement over official PriceFM/article results.
The completed screening does not justify another large grid before transfer.

## Recovery design

`434_resume_pricefm_stage_r123_resources.py` imports the ORIGINAL frozen
controller using an explicit fitting-worktree path. Workers and mathematical
functions remain in that worktree. Only resource preflight and task admission
are wrapped; task admission refuses any new Ridge screening task. At every
phase boundary the wrapper restores the process's initially
permitted CPU mask, executes the original ten-second physical-core preflight,
and repins the controller to the newly selected idle pool. It never expands
past the initially permitted mask or changes another lane's process affinity.

All original resource gates remain: 9..15 distinct physical workers, at most
20% busy for both SMT siblings, 200 GiB memory/disk floors, identical Python
environment, fixed prior gate and source checks. Only an idle-core shortage
is retried, up to three samples with 30-second backoff. Memory, environment,
source, target and numerical failures are not retried or bypassed.

The driver preserves separate hashes for its own committed sources and the
old fitting HEAD. It verifies the preparation/source identities, frozen broad
design, every completed Ridge artifact, prior-gate identity and robust shortlist.
Corruption or unfinished screening blocks recovery before fitting. A separate
lock prevents duplicate recovery controllers; the original campaign lock also
remains authoritative. Previous logs, progress, ranks and execution markers are
copied and hashed under an attempt-specific metadata archive before resumption.
An old blocked marker is cleared only after a successful locked preflight and
verification of its preserved copy. No model evidence is deleted or relocated.

The completed engine can reset `complete_this_resume` to zero for skipped queues.
Use the saved inventory, not that attempt-local counter, to report cumulative
completion. Live attempt status and CPU selections distinguish current execution
from the preserved prior attempt. Completed screening artifacts are hash-checked
again at scientific closeout, not regenerated to fit the new execution history.

## Scientific stages and non-goals

Resume the existing 90 center Normal RHS fits and 60 tau-multiplier fits, then
63 primary independent AL VB atoms (three candidates x three internal splits x
seven levels). Forecast scoring and any existing conditional cap companions
are additional jobs. The fitting objective, selection support, priors, seeds,
parameter budgets and recursive forecast operator are unchanged. Nested starts
remain computational only. No screening rerun, new exAL/MCMC/joint fits,
official validation/test access, registry change or article promotion is allowed.

After completion, freeze convergence and cap classifications, complete paired
internal rankings, retained evidence and source hashes. Only then prepare the
separately approved official evaluation and coordinator handoff. This recovery
and its live scientific campaign remain NOT_READY_FOR_INTEGRATION.

## Verification and launch

New tests cover the actual original physical-core gate, re-selection beyond an
old pinned pool, unchanged posterior contracts, bounded retries, non-CPU failure
handling, corrupted/partial screening rejection, immutable identities and verified
archiving of historical execution state. Run them with the existing eight-file
R120-R123 regression suite on both servers. Inspect the audit-only mode before
starting a detached controller and monitor both resource gates and early RHS jobs.

```bash
PY=/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python
env PYTHONDONTWRITEBYTECODE=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 "$PY" -B \
  application/scripts/pricefm/434_resume_pricefm_stage_r123_resources.py \
  --mode audit --frozen-code-root "$FROZEN_R123_WORKTREE" --workers 15 \
  --log-file "$CAMPAIGN/controller_attempt_02.log"
```

For the detached launch use the SAME command with `--mode controller`, retaining
the new log, attempt ID and both worktree identities. Keep all generated campaign,
attempt, environment, binary, NPZ/RDS and ignored local-tracker paths out of Git.
Only dedicated PriceFM branches may be pushed. No main/Overleaf merge or push.
