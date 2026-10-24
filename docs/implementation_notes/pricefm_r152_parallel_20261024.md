# PriceFM R152: baseline resource successor and finite parallel cached studies

This task implements the reviewed October 24 parallel plan on its own branch.
R141 numerical sources, fitting targets, the default 300 iterations, completed baseline
outputs, AT/LT failure evidence and publication/authority remain unchanged.
Current operational evidence is recorded separately under
`local_trackers/pricefm_chat_continuation_20261021/r152_parallel_implementation_20261024`.
Code availability and passing checks do not imply scientific completion.

## Entrypoints and responsibilities

| Entry | Responsibility |
|---|---|
| `504_supervise_pricefm_stage_r152_baseline.py` | Exact AT+LT drained-boundary cutover, legacy dispatch fences, separate baseline owner/guardian, child adoption and A/B progression |
| `505_run_pricefm_stage_r152_shared_pool.py` | Single cached dispatcher, per-study admissions, global physical slots, joint calendars, CPU/RSS/delivery guards, independent development drainage |
| `506_screen_pricefm_stage_r152_region.py` | Prospective FI study, own cohorts and cached moments, bounded pricing, matched seeds and assessment; explicit prepared DK₂ execution bridge |
| `507_orchestrate_pricefm_stage_r152_parallel.py` | Committed-source release/probe checks, parent attestation, bounded precommit and one finite workflow |
| `508_bootstrap_pricefm_stage_r152_payload.py` | First-exec policy, separate resource/scientific source checks and same-PID administrative CPU receipts |

Each entry has a matching focused test file. The existing immutable EE worker 500
remains at `c03613cd1a85cce5d02120760b954cdc15160410`. R152 does not edit that
producer, its preparation, old lease writers or historical packets.

## Exact resource and lifecycle scope

Muscat baseline A retains physical CPUs 0–14. The resource-only B successor
uses 15–23, leaving 24–29 for six cached workers. This explicitly reduces B's
maximum concurrency from 15 to 9. Optional cached workers on 22/23 are disabled initially;
they cannot fund mandatory prefixes. SMT siblings are not additional model
slots. Jerez's healthy queues and every live model affinity remain untouched.
The new baseline service is independent of the finite development parent.

The old R146 handoff is committed and rejects the actual AT+LT scheduler
failure. The successor fences old R141/R145/R146 dispatch locks, proves exact
worker-free ownership, stops only precisely identified old controls/guardians,
and records honest supersession. It preserves AT/LT quarantines and continues
the independent six A-tail and three B-tail regions using the immutable R141
controller API and canonical source/collector identities. It never resumes old
R145 after commitment or treats LT as certified.

All offline implementation, review and disposable validation precede the real
cutover. T0 is the baseline's atomic partition-loan/master commitment, before
new baseline or cached dispatch. Loan, owner and master carry one scope ID and
expiry T0+43200. No later EE/FI startup resets it. The finite 507 parent has a
300-second precommit bound and a 60-second kernel backstop beyond its 12-hour
scope; neither grants scientific execution before or after the committed master.

Development uses one-thread, one-physical-CPU SCHED_IDLE workers with idle I/O;
parents remain responsive. Available RAM/disk floors are 192/80 GiB. The 24 GiB
owned RSS soft stop covers the whole development tree, not one allowance per
study. Existing baseline numerical workers retain their original immutable
health checks; new baseline dispatch stops at its stricter floor without
signalling already-running fits. More workers do not increase a CPU allowance.

After final cached drainage, B may recover 15 cores only at a verified safe
region/controller boundary. A live nine-core controller is never moved.
The restoration can occur after the development deadline without renewing
development. Finalization must account for the finite master itself: the
publisher records its capsule and the independent baseline owner verifies its
actual exit before returning the loan. A worker-only cleanup file cannot prove
all control lifetimes drained.

## Scientific work and finite accounting

- EE: finish 58 D plus up to 6 new original-seed S components; at most 82 new
  components including all conditional extras. Reuse strict original packets
  and chunks. No new benchmark, posterior fit or geometry.
- FI: freeze 20 cached packages/19 geometries, 60 parent fits and four own banks;
  60 D + 9 S0, at most 87 components. Its own 940-anchor support yields 124/134/173
  daily origins and four clocks. No posterior is newly fitted by this stage.
- DK₂: retain the original prepared 63 D + 9 S0, at most 90 components. The existing
  EE science/budget-disposition gate and independent own-price gate remain.

The FI/DK₂ one-time 20-minute admission includes numerical preflight, 16 timed
prediction calls and two original control replays, setup, serialization and
cleanup. It computes no candidate AQL for selection. A missing/invalid cache
or unfunded complete prefix defers the study; no hidden refit, panel reduction
or repeated benchmark follows. The immutable EE benchmark is reused.

Complete each deterministic pool before selecting nominees. Preserve exact
controls, keyed audit nomination, original regional RNG, paths, cohorts and
equal-split seven-quantile loss. Admit qualified matched extra-seed sets
atomically or retain the entire set pending. Seed 0 exploration uses its own
practical margin; final confirmation recomputes the margin from mean matched
control loss across three seeds. Monte Carlo stability is not a data-confidence
interval. A clean negative outcome is valid.

New EE windows are EE-C1/C2, at most two; old waves 1/2 remain spent and old
wave 3 is unclaimed but expired. Old paths are read-only. Regional studies have
one benchmark and at most three two-hour numerical windows each. Each window
has 90 projected compute minutes plus 30 reserved for validation/drain. Whole
windows, individual jobs, phase barriers, complete prefixes/replacements and
all reserved work must fit the same six-slot joint calendar and master time.
There is no terminal-tail credit or duplicate slot funding.

Preserve EE's 21786.141935-second cumulative science ceiling and both historical
debit interpretations. Reserve the stricter 1085.449985 historical amount for
new funding while retaining the frozen 999.173762 receipt; the difference is
headroom reservation, not rewritten past spend. FI/DK₂ science each use
`min(32400,32400*s_price)` from their own frozen conservative pricing. All-in
cumulative maximum is EE+FI+DK₂+9600 admin CPU seconds, at most 96186.141935
including old EE, not a kernel quota. Admin comprises two 1200-second combined
preflight/benchmarks, three 1800-second assessments and 1800 shared-control seconds.
Charge each owned lifetime once, including subprocesses and final exit tails.
Missing, partial or corrupt receipts retain conservative full reservations.

This initial release handles starvation conservatively: it stops, drains the
owned work and records the disposition. It does not automatically exercise a
replacement token. The single-token history is preserved without replenishment.

## Release and reproduction

Use the pinned Python 3.11 interpreter from the existing PriceFM runtime.
Numerical library thread environment variables must equal 1 before first exec.
Run meaningful new checks with:

```bash
python -B -m unittest discover -s application/tests -p 'test_pricefm_stage_r152_*.py'
```

Use the configured interpreter in place of `python`; it is not the host's older
system interpreter. The new worktree must be committed/clean on its dedicated
branch and freshly equal to its normal CLI remote before freezing a release.

```text
507... freeze --output RELEASE.json
507... probe --output PROBE.json
507... launch --release RELEASE.json --probe PROBE.json
507... status
```

The actual probe parent runs with ordinary scheduling on CPUs 15–29 with idle I/O and six
one-thread vendor controls. Disposable UUID units exercise source-compatible
old EE policy receipts, numerical-library initialization without forecasts,
intentional positive thread violation, same-PID admin accounting, parent death
and exact drainage. Baseline probes use private locks and owned disposable
sessions. No scientific smoke forecast or production admission is spent on
those checks. Probe receipts are pinned to the exact committed source and boot.

Launch prepares metadata only after source/probe verification, then establishes
the finite parent and pending contract. The fenced baseline owner alone commits
T0. A pending contract contains no running loan clock. FI numerical work starts
only after initial actual EE delivery and independent own pricing. An unfunded
FI prefix or whole extra set has an explicit disposition; it must not loop
idle until master expiry or invalidate healthy EE science. Resource/ownership/
policy failure is distinct and stops dependent cached dispatch.

## Reporting and scope limits

Retain progress, strict component counts, phase, actual workers/delivery,
charged/reserved CPU, RSS, admissions/deadlines and blockers. Preserve source,
config, candidate/cohort/seed manifests, exact unit/process/InvocationID/cgroup
receipts, checkpoint/final seals, cleanup proofs and independent assessments.
Keep operational stop, iteration-cap/noncertification, negative performance,
Monte Carlo instability and budget deferral distinct.

Exposed official weaknesses may prioritize disclosed development. Candidate
selection stays training-only; the existing 38-region baseline stays frozen.
Cached Normal improvements are not downstream AL validation. New AL fits,
LT/AT repair fits, iteration changes, new architectures/joint/exAL/MCMC,
official reruns, authority promotion, main/Overleaf/article integration and
unrelated lanes are outside this release. The 12-hour allocation is not a
scientific completion or predictive-improvement ETA.
