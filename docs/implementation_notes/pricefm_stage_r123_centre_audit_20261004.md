# PriceFM R123: Bounded Centre-Fit Convergence Audit

## Why the resource recovery is not a scientific closeout

The execution-only recovery at `fb4d3f6f78d492e501102364e095ec9238180892`
passed both physical-core preflights and dispatched the frozen Normal RHS
shortlist. Before its fail-fast queue drained, it completed 27 fits and reported
12 convergence failures across four structures (all three internal splits):

- `r123_969d34e71c1f81d2`
- `r123_d6ae937db90ee3b2`
- `r123_1c2815d7e7879d5a`
- `r123_6ab7923710f4ecb4`

There are 51 unattempted centre fits. The failed logs contain exactly the frozen
entrypoint's convergence stop, not a non-finite-posterior error. The scientific
entrypoint checks finiteness first, then rejects a nonconverged result at its
2,000-iteration cap, before writing fit artifacts. Consequently these logs prove
nonacceptance, but do not reveal which trace component prevented convergence.
The successful fits took 100..1,614 iterations. Neither a longer budget nor a
relaxed criterion is justified by the available evidence.

## Smallest useful continuation

The next independent computation is to attempt the remaining 51 centre fits
exactly once and score only genuinely converged results. A failure in one
candidate need not prevent learning whether other already-shortlisted candidates
are computable. This is an execution audit, not a new candidate-selection rule.

`435_audit_pricefm_stage_r123_rhs_centres.py` runs in a new dedicated worktree,
imports the unchanged R123 engine at
`7ae8d6f578000ab17cd30567a23f7b806028cee0`, verifies all original screening,
prior and source evidence, and verifies the exact 90 centre contracts. It freezes
hashes of all existing successful fit files and previously rejected logs.

The adapter recognizes only the exact three-line log produced by the frozen
pre-artifact convergence stop, for the exact contract and with no output
directory. Such a result is explicitly rejected, never a successful fit.
Already rejected contracts are not tried again. Completed fits are reused.
Corrupt evidence, partial output, altered commands, different errors or sources
remain fatal. The original fail-fast behavior is retained for all unexpected
errors and all forecast-scoring errors.

The same resource recovery selects 9..15 idle physical workers (default 15),
one numerical thread per worker, without SMT siblings. It retains the ten-second
sample, 20% busy limit and 200 GiB memory/disk floors. Locks exclude concurrent
campaign controllers. Nothing in either previously executed worktree is edited.
No fit budget, tolerance, posterior target, initializer, DESN specification,
seed, input data or forecast operator changes.

## Deliberate stopping point

The bounded driver does not invoke the old full controller or its final
selection function. It can dispatch only centre fits and centre scoring. It
records the complete three-split candidate ranking as audit evidence, but does
not choose tau alternatives or AL winners. It finishes with
`CENTRE_AUDIT_COMPLETE_SELECTION_BLOCKED`, not a scientific campaign PASS.

The existing rule demands 30 complete centre candidates; rejected fits mean this
condition has not passed. Any later choice to continue with a smaller eligible
pool, regenerate diagnostic traces, use better computational initialization or
change iteration budgets requires a separately recorded scientific decision.
Do not silently substitute replacements, impute missing scores, mark capped fits
converged, or rank candidates using only their successful splits.

Preserve all old failed logs and successful outputs. Next, inspect the full
convergence pattern against architecture, interlayer gain and input policy.
For representative unresolved candidates, a small isolated trace-only rerun may
be justified because the original entrypoint discarded its unsaved trace. It
must reproduce the exact target and must not be promoted as a new accepted fit.
Diagnose the actual blocking trace before deciding whether computation or
candidate eligibility should change. No further large screening is warranted.

## Testing, operation and integration boundary

Tests cover exact error classification, no repeat of completed/failed fits,
immutable failure evidence, unchanged dispatch contracts, accurate success
counters and refusal of all downstream stages. Run these with the existing
recovery and R120-R123 regression tests locally and on Jerez. Run audit-only mode
before a detached launch, using a new attempt and log path:

```bash
python -B application/scripts/pricefm/435_audit_pricefm_stage_r123_rhs_centres.py \
  --mode audit --frozen-code-root "$FROZEN_R123_WORKTREE" --workers 15
```

After audit approval, use the same arguments with `--mode controller` under a
detached launcher, one exclusive-created controller log and a recorded PID.
Inspect `attempts/r123_centre_audit_20261004_01/live.json`, convergence rejections,
queue-admission records and the original centre fit/score progress. The original
queue's handled count can include recognized rejections during execution; use
artifact inventory and rejection evidence for scientific completion. Final
progress explicitly distinguishes handled commands from converged fits.

No official validation/test, exAL, joint, MCMC, registry, manuscript or Overleaf
mutation is authorized. All generated attempts, fits, RDS/NPZ/binary artifacts,
logs and ignored trackers remain excluded from Git. Push dedicated PriceFM
branches only. The scientific phase is **NOT_READY_FOR_INTEGRATION**.
