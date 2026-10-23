# R148: bounded EE screening development alongside the frozen baseline

## Decision and authorization

The user authorized a comprehensive audit of the preceding parallel-screening
proposal and implementation of the justified work while the baseline continues.
This changes the earlier finish-first order for isolated screening development.
It does not authorize baseline replacement, publication, or the separate proposed
AT 600-iteration recovery. R147 remains reserved for that recovery proposal;
R148 identifies this development lane.

The preceding proposal is preserved in the local continuation bundle under
`local_trackers/pricefm_chat_continuation_20261021/parallel_screening_development_20261022/`.
It allowed up to 32 new Ridge geometries only if an actual coverage gap justified
them. The audited implementation uses **zero new geometries, zero optimizations,
and 18 cached Normal-RHS rescoring tasks**. This is the first conditional stage
of the plan; later expensive confirmation is gated by its results.

## Findings that change the next experiment

| Finding | Evidence and implication |
|---|---|
| Existing coverage is substantial | All 645 EE Ridge packets, comprising 1,935 split records, passed the independent identity/seal audit. More geometries alone are not supported by the current evidence. |
| Confirmation often repeats a geometry | All 12 completed baseline regions used both AL finalist slots for different tau0 settings of one geometry; 11 selected the frozen-control geometry. Distinct architectures deserve diagnosis before expanding the grid. |
| tau0 is consumed | EE prior/auxiliary quantities change with tau0, but fitted predictions are nearly tied. This is weak effective sensitivity, not evidence of an ignored input. |
| Driver/receiver diversity was already tried | Completed R138 DK_1 crossed six receivers with three fixed drivers. Its internal gain was about 0.49%; official AQL was 8.762958, worse than current DK_1 and R98. Do not repeat those 18 pairings or claim diversity is sufficient. |
| EE has the largest observed absolute deficit | On the provisional 12-region subset, EE exceeds R98 AQL by 3.46270, DK_1 by 2.44682 and DK_2 by 1.34173. Equal-region mean loss makes absolute excess relevant. This is not a ranking of all 38 regions. |
| Cached fits and cached scores differ | Normal-RHS posterior moments and scalers are retained. Ridge packets retain scores, not the heavy fitted moments needed for free forecast replay. A saved Ridge score is not a saved Ridge model. |
| Historical scoring panels differ | The four-origin Ridge and twelve-origin RHS grids are generally not nested. A direct score difference can mix model, prediction policy, Monte Carlo variation and origin composition. |
| Existing proxy ranks disagree | Across the 25 EE geometries with certified three-split RHS scores, cached Ridge/RHS Spearman correlation is -0.19 and their conditional top-five overlap is zero. This is conditional on the old shortlist, with different fitted estimators, panels and policies; it motivates diagnosis but does not identify a cause. |

The baseline snapshot at 2026-10-23 04:20 UTC had 12/38 closed regions and
36/114 closed official fold cells. Muscat's DE_LU and IT_CSUD and Jerez's
IT_SARD/IT_CNOR remained active. AT R146 had one uncertified required median;
the separately proposed bounded recovery is not implemented by this lane.
These counts are a dated snapshot, not a claim that the baseline has finished.

## Frozen scientific scope

The source/configuration surface is:

- `application/scripts/pricefm/492_run_pricefm_stage_r148_ee_parallel_development.py`
- `application/config/pricefm_stage_r148_ee_parallel_development_20261023.json`
- `application/config/pricefm_stage_r148_ee_cached_controls_20261023.json`
- `application/scripts/pricefm/493_supervise_pricefm_stage_r148_ee_idle_resources.py`
- `application/config/pricefm_stage_r148_ee_idle_resources_20261023.json`

Use six distinct cached EE Normal-RHS architectures, each on the same three
training-contained rolling splits. Preserve the actual frozen EE baseline
driver's tau0 for the protected control. This differs by a factor of ten from
the lowest cached Normal-RHS ranking row for that geometry; silently choosing
the ranking row would not reproduce the frozen control. Use one declared cached
scale for each of the other five geometries. Pin source commits, cache seals,
task identities, training banks, scalers, and posterior artifacts before scoring.

For each fit, evaluate deterministic Normal-location recursion and stochastic
Normal-RHS recursion using 100 posterior paths, the established 96-step horizon,
and the seven fixed quantiles. This compares forecast policies within a saved
Normal-RHS fit. It does not isolate the causal effect of fitting Ridge versus
Normal-RHS: their estimators, priors and fitted coefficients differ.

Freeze 16 origin-clock pairs as the exact historical four Ridge origins crossed
with four offsets. Construct a nested 48-pair panel by retaining those four
origins and adding eight deterministically spaced historical RHS-grid candidates.
Save the original twelve-origin RHS grid separately: the new nested panel is
not necessarily the historical RHS panel. Common-origin stochastic paths must
be stable under panel size and iteration order. Calculate stochastic forecasts
once for the larger panel and take the exact subset for the smaller panel.
Preserve parameter-draw and innovation randomness reproducibly.

Workers load pinned training banks and cached moments only. They do not load raw
FINAL data, official-fold designs, or test outcomes. Historical EE/HR/R138
closeout pins are context and lineage, not inputs to candidate ranking. HR is a
cached positive control and R138 a completed negative example; neither is refit.

EE was prioritized using previously seen official performance. Consequently all
R148 results are development evidence. Training-contained tuning does not make
that test period unseen again. The remaining 26 regions also need a historical
exposure audit before anyone calls them untouched confirmation.

## Resource policy and its limits

The dedicated Muscat unit is
`pricefm-r148-muscat-ee-idle-development.service`. Its supervisor remains
SCHED_OTHER; at most two numerical children use SCHED_IDLE, idle I/O priority,
one physical CPU from 0–29 each, and one thread in every numerical runtime.
CPUs 30–31 and SMT siblings are excluded. CPU choice uses observed idleness and
does not grant exclusive ownership. Kernel priority allows normal baseline work
to preempt these children if an allocator fills a previously quiet CPU.

Each lease lasts at most two hours elapsed time (four nominal worker core-hours).
It persists across a restart and is never automatically renewed. The service
uses `Restart=no` and `KillMode=control-group`; its cgroup contains only R148
processes. Host-level inspection found cgroup v1 CPU membership at `/` and
memory membership shared by the whole user manager: kernel CPU/memory limits
are not delegated to individual user units. Do not apply a quota to that shared
hierarchy. The effective CPU bound is two single-core numerical children; the
small monitoring parent is additional. A 24 GiB summed own-process RSS stop
guard is observed between polls, not a hard kernel allocation limit. Runtime
guards retain at least 192 GiB MemAvailable and 80 GiB free disk. Output growth
is telemetry only: the user's no-arbitrary-storage-cap constraint is preserved.
The 192 GiB floor conservatively strengthens the draft's
180 GiB floor. Memory and I/O are shared resources; idle scheduling does not
guarantee zero interference.

The frozen R146 handoff supervisor does not read a development lease. Therefore
the draft's strict stop-before-reassignment claim cannot be implemented without
changing baseline behavior. R148 instead checks before every payload admission,
then polls every 0.5 seconds and stops its own children when any R146 handoff
state appears or its waiting gate changes. Detection latency includes operating
system and monitoring work; it is not an atomic interlock. SCHED_IDLE protects
baseline CPU priority during this observation race. No baseline lock, service,
process, affinity, scheduling policy or result is modified.

The actual child proves its PID/start-time/boot/group/cgroup identity, scheduling
policy, idle I/O and CPU affinity before a parent permit allows scientific work.
Runtime checks continue after exec. Cleanup validates ownership before signaling
only development groups. Source changes, failed seals, missing policy evidence,
resource crossings, handoff, errors or lease expiry stop admission and preserve
partial attempts without promoting them.

## Reproduction and acceptance

The pinned Python is
`/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python`.
Set `PYTHONDONTWRITEBYTECODE=1` and numerical thread environment variables to one.
Run the focused R148 scientific/resource/contract tests, relevant R146 resource
regressions, and `git diff --check`. Tests must cover origin nesting, stable RNG,
strict payload/seal checks, cache/source tampering, worker admission, lease
nonrenewal, ownership and handoff cleanup. The older R141 dependency tests need
`PRICEFM_R141_DEPENDENCY=/data/jaguir26/local/src/Article-Q-DESN/.codex_work/pricefm_r127_closeout_20261008`.

Commit the task branch, push using command-line Git, and freshly fetch/read back
the identical remote commit before releasing numerical work. Freeze the runtime
release from that clean committed source. Script 493 provides `release`, `run`
and `status`; script 492 provides gated `prepare`, `worker` and inspection. Do not
run an ungated scientific payload at ordinary priority. Launch only the dedicated
unit with `KillMode=control-group`, `Restart=no` and the declared working
directory. Do not add unsupported CPUQuota/MemoryMax properties or claim that
recorded systemd properties establish actual kernel isolation. Runtime artifacts
belong under the R148 tag in `DATA/launch_prep/` and `DATA/campaigns/`, never an
existing baseline namespace. Exact source, test, release, launch and observation
receipts are saved in the ignored continuation bundle.

A completed pilot requires 18 strictly verified task seals. Partial scores are
reported as partial; a zero exit code alone does not establish completion.
Analysis compares paired deterministic/stochastic and 16/48-panel AQL changes,
architecture ranks and the protected control. Rank fidelity covers only these
six cached RHS-selected architectures, not discovery performance across all 645.
Record panel metadata and keep
historical Ridge comparisons qualified by the different fitted estimator.
One hundred paths and one Monte Carlo seed are diagnostic, not a precision or
superiority claim. Do not silently turn rank movements into accepted models.

## Decision after the pilot

1. If seeds/panels/lineage fail, repair the development implementation and reseal
   only valid tasks. Do not rescue invalid output by weakening baseline rules.
2. If cached rankings remain stable, keep the existing screen until an actual
   training-diagnosed coverage gap justifies additional candidates. Report a
   negative diagnostic result plainly.
3. If rankings change materially, establish whether the change follows origin
   coverage or forecast policy. Check Monte Carlo sensitivity and split
   consistency before spending on a new receiver. A renewed compute lease needs
   a new explicit, bounded admission; this lease does not auto-extend.
4. A subsequent minimal EE receiver comparison would hold the cached driver
   fixed and could need 21 AL fits across three training splits (300 iterations
   by default). A candidate outside the cached shortlist can additionally need
   nine Normal-RHS fits and three statistics packets. These are declared future
   costs, not tasks admitted by R148. No official-fold, AL, joint, exAL or MCMC
   worker kind is enabled here.
5. Freeze the baseline and audit its full 38-region output separately. Any later
   family comparison or replacement requires its own reproducible selection and
   audited untouched confirmation design. Integration, article and Overleaf
   publication follow the repository's separate Git-only policy.

This sequence spends compute only when the preceding evidence justifies the
next stage, retains the baseline as a reproducible reference, and leaves every
accepted or deferred decision visible in the continuation ledger.

## Timing and reporting

The R148 lease ends no later than two hours after its persisted start, including
the policy probe. Completion of all 18 tasks within it is conditional on available
idle CPU time and the baseline handoff. Estimate throughput from sealed task
elapsed times and live CPU consumption; do not treat wall time under SCHED_IDLE
as guaranteed dedicated-core performance. Report completed tasks, remaining
tasks and the actual expiry together.

The full baseline has no defensible successful-completion ETA until the AT
certificate blocker is resolved. Earlier November 2–3 estimates were healthy-tail
scenarios, not commitments. Preserve the user's November 6 deadline, but do not
promise the later family/VB/MCMC expansion without measured throughput and a
validated implementation matrix. Finishing this development workflow and
finishing the 38-region scientific study are distinct completion events.
