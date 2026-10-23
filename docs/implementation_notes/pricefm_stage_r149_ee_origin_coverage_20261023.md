# R149: complete-origin EE replay and Monte Carlo sensitivity

## Authorization and audited decision

The user explicitly requested a new audit of the completed R148 follow-up plan
and implementation of the justified work while the baseline continues. R148 is
complete and stays frozen at `adce9120de82f2d3c60703957ce7e0823cd9cc7f`.
This is a separate R149 source, output namespace, service and bounded resource
admission. It does not reopen or renew R148's completed lease.

R148 showed an origin-panel rank reversal among six cached EE Normal-RHS fits.
The small-panel stochastic winner, `r134_19b9f530c3d2246e` (C5), beat the
protected control on 16 origin-clock pairs but lost by 3.13% on the nested 48.
The control won both 48-pair policies. Historical Ridge/RHS rank correlation
across 25 certified RHS geometries was -0.19, but different estimators, origin
grids and prediction policies were confounded. Those results do not justify
blindly adding geometries or beginning AL confirmation.

The next useful experiment holds fitted models fixed and checks the complete
eligible training-contained origin cohort. It then measures Monte Carlo
sensitivity on the existing sparse panel. This answers the immediate sampling
question at lower cost than refitting models or repeating a whole search.

## Fixed scientific budget

| Component | Architectures | Splits / seeds | New tasks | New fits |
|---|---:|---|---:|---:|
| Complete-origin replay | 2 | 3 splits, original seed | 6 | 0 |
| Sparse Monte Carlo sensitivity | 2 | 3 splits, 2 extra seeds | 12 | 0 |
| Total | 2 | Frozen before launch | 18 | 0 |

The two architectures are the actual frozen EE control
`r134_0cab1abbe8ace168` (C0) and the R148 stochastic16 winner C5. Preserve their
original certified R137 parents, actual tau0 settings, scalers, specifications,
priors and source identities. C0's actual frozen tau0 is
`.0024929739307713865`; do not replace it with its ten-times-smaller cached
Normal argmin scale. Cached moments are read without updating or fitting.

All work uses the original three rolling splits contained inside Fold1
training, the same pure all-layer readout, seven quantiles, 96 quarter-hour
horizon and four clock offsets `[0,24,48,72]`. Stochastic scoring retains 100
paths. Original-seed full replay must preserve the exact R148 RNG construction.
The extra master seeds are `2026102301` and `2026102302`, frozen before scoring.
Extra-seed tasks use the exact R148 nested 48-pair panel and depend on a valid
full-replay seal for the same architecture/split.

No new Ridge, Normal-RHS, AL, exAL, joint or MCMC fits are admitted. No official
fold designs, raw FINAL data, new calendar inputs, registry, article, main or
Overleaf changes are part of this stage. The separate proposed R147 AT
600-iteration recovery remains outside this screening task. Default AL remains
300; no certificate or public-engine behavior is relaxed.

## Complete-origin eligibility and weights

The validation cohorts contain 125, 135 and 174 daily origins. The final day of
each split cannot support all four shifted 24-hour windows inside that split.
Use `validation[:-1]`: **124, 134 and 173 daily origins**, totaling 431. At four
offsets this is **1,724 origin-clock pairs per architecture**. Verify actual
shifted-window boundaries and identities rather than relying on counts alone.

The primary comparison retains the historical **equal-three-split macro AQL**:
first average eligible origins/clocks within each split, then average the three
split scores equally. Also report the **431-day pooled diagnostic**, weighted
by 124/134/173 origins. They are different estimands; do not silently replace
the primary score with the pooled result. Seven-quantile loss, median MAE,
80% coverage and interval width retain their original definitions and units.

Calendar/season labels are sampling metadata, not added model features. If
lagged-volatility regimes are reported, use only information available at each
origin and learn thresholds on the exact inner-training rows. Never stratify
from official test losses. Retained complete-origin predictions permit later
coverage and contribution audits without another forecast or fit.

Once all six full replays are verified, perform a frozen sampling-design audit
using their paired C5-minus-C0 daily losses, averaged over the four clocks.
Compare uniform, weekday-stratified and month-stratified sampling within each
split at budgets of 4, 12, 24 and 48 days, with 32 resampling replicates and
master seed `2026102303`. Select origins from identities and calendar labels,
never their losses. Sort origin identities canonically before keyed RNG draws.
Each feasible stratified sample covers every nonempty stratum, respects its
population size and estimates the split contrast with
`sum_h (N_h/N) * mean(sampled daily differences in h)`. Mark insufficient
budgets unsupported rather than assigning zero weight to unsampled strata.
Report bias, mean absolute error and sign agreement against the complete-origin
reference, retaining the primary equal-split macro and a separate pooled
diagnostic. Compare the old fixed panels descriptively, without treating them
as probability samples. This postprocessing adds no forecast task or fit.

The 32 replicates measure finite-cohort sampling error conditional on two
preselected fits and one full-cohort forecast seed. They do not supply new
temporal confirmation, full-cohort Monte Carlo stability or a globally optimal
panel. No sampler or next-stage budget is automatically selected from them.

## Numerical replay and retained evidence

Save standardized and EUR/MWh quantiles and truth, per-origin/per-clock losses,
ordered origin timestamps and stable RNG keys, posterior/path/seed identity,
scalers and all parent lineage. Preserve the original fit and cache hashes
before and after scoring. Teacher forcing remains between origins; recursion
within an origin cannot use future target observations.

Stochastic predictions on the old 16/48 subsets must reproduce R148 byte
hashes exactly, using the same posterior draw and innovation streams independent
of chunk size or order. R148 retained hashes but not arrays. Therefore obtain a
canonical twelve-row deterministic reference using the frozen R148 helper,
verify its saved small-panel hash first, and compare full-replay subsets with
that regenerated reference. The declared deterministic tolerance is
`atol=1e-12, rtol=1e-10` in standardized units; a hash mismatch alone is not a
numerical tolerance check. Reject a failed replay rather than weakening the
rule after observing scores.

Use small checkpoints (eight origins per clock) so a resource stop does not
discard an entire long task. A checkpoint seal binds the committed source,
task hash, original parent/fit/scaler/bank hashes, clock, exact ordered origins,
path count and seed. Retain incomplete attempts; reuse only fully verified
matching checkpoints. A partial or differently seeded chunk is never a completed
task. Canonical task completion requires the exact full surface, finite arrays,
correct dimensions, recomputed metrics, original-source lineage and complete
artifact hashes. A successful process exit alone is insufficient.

## Source and resource implementation

The scientific entry point is
`494_run_pricefm_stage_r149_ee_origin_coverage.py`; the resource entry point is
`495_supervise_pricefm_stage_r149_ee_idle_resources.py`. Configurations use the
R149 tag `pricefm_stage_r149_ee_origin_coverage_20261023`. Runtime artifacts live
only in that tag's separate `DATA/launch_prep/` and `DATA/campaigns/` directories.
The dedicated service is `pricefm-r149-muscat-ee-idle-development.service`.

Reuse the audited R148 numerical helpers and resource kernel. Only the copy of
the shared resource module in the new R149 worktree is parameterized; original
R148 defaults and regression behavior stay intact. The original execution
worktree and completed evidence remain untouched. Do not duplicate the whole
supervisor or rewrite its source dynamically to change stage labels.

The new admission is at most two SCHED_IDLE numerical workers, each pinned to
one distinct physical CPU in 0-29, with one numerical thread and idle I/O.
CPUs 30-31 and SMT substitutes remain excluded. The monitoring parent retains
SCHED_OTHER. This is nonexclusive sharing of reserved cores, not an exclusive
core loan. Verify actual PID/thread scheduling, affinity, I/O and loaded BLAS
thread pools before and during payload execution.

The new lease is **two hours elapsed time**, persistent across process restarts
and never automatically renewed. The service uses `Restart=no` and
`KillMode=control-group`, containing only development processes. Capture stdout
and stderr to files from the first launch. Retain 192 GiB MemAvailable and
80 GiB free disk, plus the 24 GiB summed own-RSS soft stop. This cgroup-v1 host
does not delegate private CPU/memory controllers; do not write limits to shared
hierarchies or claim hard MemoryMax/CPUQuota enforcement. There is no arbitrary
output-size cap.

Observe the five existing Muscat baseline service identities read-only. Check
the unchanged R146 waiting gate before each admission and target a 0.5-second
sleep between polls. This is not a hard response deadline: initial semantic
validation of a new seal and source/Git/filesystem operations can extend the
interval while a sibling worker is active. Verified artifact signatures are
memoized; the final all-task check follows drainage of all owned children.
Any handoff state, baseline identity change, resource crossing, source change,
lease expiry or invalid result stops only owned development processes. The
handoff observer is reactive, not an atomic interlock; SCHED_IDLE preserves
baseline CPU priority during observation latency. Preserve the verified Linux
zombie-lifetime exception and unsuccessful cleanup receipts. Never signal,
pause, renice, re-affinitize or stop an existing baseline service or worker.

## Validation and launch sequence

1. Test scientific boundaries, exact task scope, eligibility/weighting,
   canonical replay, seed identity, finite retained arrays, checkpoint integrity,
   partial-result handling and idempotence. Use real tiny frozen-runtime
   numerical tests without fitting a model.
2. Test the resource adapter and original R148 defaults, real idle-policy and
   zombie handling, own-only cleanup, private cgroup identity, handoff stop,
   persistent lease, source pins and dependency admission.
3. Obtain independent code/contract review; run relevant R146/R148 regressions
   with the pinned dependency. Check the exact file surface and `git diff --check`.
4. Commit and normally push the dedicated branch using command-line Git, then
   freshly fetch and require the remote hash to match the clean local source.
   Do not merge main, publish an article or change Overleaf.
5. Release the immutable R149 source/task manifest, prove the actual scheduling
   policy, launch only the dedicated unit, inspect real progress and preserve
   exact commands and receipts in the local continuation bundle.
6. Continue through all admitted tasks or a guarded stop. Verify final source,
   original caches, strict task seals, per-origin metrics and cleanup before
   reporting completion. Save the complete assessment and update continuation.

The pinned Python is
`DATA/runtime_envs/r137_py311/bin/python`, with bytecode disabled and numerical
thread environment variables set to one. The older regression suite needs
`PRICEFM_R141_DEPENDENCY=/data/jaguir26/local/src/Article-Q-DESN/.codex_work/pricefm_r127_closeout_20261008`.

## Interpretation, next gates and timing

Report full-origin C5-minus-C0 differences by split, both aggregate estimands,
calendar/regime contributions, old16/48 versus full reference, and sparse-panel
three-seed variation. Full-origin replay is a comparison of two preselected
cached Normal fits; it is not a new best-model claim across 645 geometries.
Sparse extra-seed stability cannot prove full-origin ranking stability because
parameter draws are shared across origins. If a full-origin contrast is near
zero or unstable, keep the expensive-fit gate closed and state what uncertainty
is missing. More Monte Carlo seeds quantify algorithmic variation, not fresh
data confirmation or independent split replication.

EE was prioritized using seen official outcomes. All results remain development
evidence; training-contained replay does not restore untouched tests. The later
independent/joint AL/exAL VB/MCMC study and requested exAL scale-gamma/M0 updates
still need their own matched manifests and audited confirmation design.

If the same complete-origin protocol is later extended to all 25 certified RHS
geometries, the gross budget is 75 tasks. These six can be reused only with
identical cohort, scale, seed, weights and provenance, leaving **69 additional**
tasks. The old R148 57-task extension applies only to its unchanged sparse panel.
If the panel changes again, declare the recomputation rather than relabeling
scores. New geometries still require a concrete coverage gap; AL confirmation
still requires a consistent advantage and an explicit budget, including matched
control replay and any missing Normal/statistics prerequisites.

The preceding estimate is 30-60 minutes for six complete-origin tasks and
6-12 minutes for sparse seed tasks on two available idle workers. Calibrate from
actual checkpoint throughput, not dedicated-core assumptions. The lease can
end earlier because of baseline priority; checkpoints preserve valid progress.
The precommit read-only C0 split1 smoke replayed one original twelve-origin
clock in eight-plus-four chunks, taking 8.64 and 4.56 seconds. Its original
stochastic twelve/four-row hashes and canonical deterministic four-row hash
matched exactly; the chunk/reference deterministic maximum difference was
zero. Raw/scaled truth, retained NPZ semantics and actual single-thread pools
also passed. This is a diagnostic smoke, not a production task or completed
source release; its script and receipt are retained in the continuation bundle.
The full 38-region baseline ETA remains unresolved while AT certification is
blocked. The November 6 deadline is preserved without promising that all later
family/MCMC work can finish by it.
