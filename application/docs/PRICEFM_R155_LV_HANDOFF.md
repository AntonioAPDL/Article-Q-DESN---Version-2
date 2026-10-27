# Finite LV-first administrative handoff

The R154 EE queue stopped on a peer guard and spent its once-only claim. This
new 526 entry can dispatch the unchanged, unclaimed LV grant once after root
admits a loss-blind `EE_STOPPED_TO_LV_FIRST` scheduling amendment. LV's frozen
training design is independent of the missing EE S0 result. Neither an EE result
nor a poor official-fold metric selects any LV candidate, operator or parameter.

The feature is based on cd113800. Its own R155 source is distinct from the actual
scientific child: **521 from the original clean cd113800 worktree**, with that
worktree as cwd and the existing ROOT_LV_ADMITTED_01 grant/preparation/aliases.
The original LV T0 is 2026-10-27 03:37:12.528510 UTC and its absolute expiry is
2026-10-28 03:37:12.528510 UTC. The original global expiry remains
2026-10-29 01:22:13.594849 UTC. No old grant, claim, output or clock is edited.

## Root admission and once-only launch

1. Verify the published R155 branch/head, clean worktrees and exact original LV
   grant/preparation/aliases. Freeze the template into a **new** root authority
   with a fresh UUID/T0, at most 120 administrative CPU seconds and six hours;
   cap expiry at the original LV expiry and global expiry. Pin every new source
   file, the imported unchanged contract, the original queue claim/failed exit,
   EE wait/guardian receipt, the original global permit device2304/inode59124844,
   and a distinct admitted order amendment. Both original LV and new administrative
   calendar must fit the entire frozen prefix plus atomic/drain allowance.
2. The amendment states `schema=r155_loss_blind_order_amendment_v1`, `status=ADMITTED`,
   `transition=EE_STOPPED_TO_LV_FIRST`, `loss_blind=true`,
   `LV_scientifically_independent_of_EE=true`, `scientific_scope_changed=false`,
   and exact `unchanged_LV_authority` and `predecessor_queue_authority` pins.
3. A PROPOSED authority and PROPOSED amendment support a metadata-only rehearsal:
   `taskset -c 31 PINNED_PY -B NEW_SOURCE/application/scripts/pricefm/526_run_pricefm_stage_r155_lv_handoff.py --authority PROPOSAL --authority-sha256 SHA --audit-proposal`.
   This verifies all 610 original source and 770 staged input pins, full-prefix
   calendar, exact old process lifetimes/unit drain, current unchanged peer
   classifier, resource floors and the **same existing** flock. It never claims
   LV or dispatches a numerical child. Retain its actual measured CPU receipt.
4. Root independently reviews and freezes ADMITTED bytes, then uses a unique
   `systemd-run --user --unit=pricefm-r155-lv-handoff-UUID --property=Restart=no --property=KillMode=process --property=LimitCPU=infinity --working-directory=NEW_SOURCE taskset -c 31 PINNED_PY -B NEW_SOURCE/application/scripts/pricefm/526_run_pricefm_stage_r155_lv_handoff.py --authority ROOT_ADMITTED --authority-sha256 SHA`.
   This is one action, never a status command or a retry. Record the actual new
   InvocationID. All preclaim checks run again in the actual admitted process.

The admin parent has a low soft CPU cap while preserving a separately funded
6900 CPU hard ceiling for the original LV child. The child resets both its own
limits to that ceiling before exec; the original 521 separately allocates its
guardian and payload reserves inside the original 7000 total (100 prior).
No small administrative hard limit may be inherited by the scientific child.

The sole single-thread parent retains its direct child unreaped using
`waitid(WNOWAIT)`. Only that exact held child can be terminated on its own finite
clock/CPU failure. Kernel PDEATHSIG and a post-arm parent check cover parent loss;
original 521 provides the same protection to its payload. No cgroup, foreign PID,
process-group signal or unsupported-pidfd fallback is used. There is no retry,
seed expansion, promotion or automatic EE follow-on.

## Evidence and read-only incident observation

526 retains exclusive claim, actual source/cwd/argv, preclaim proof, child
identity, logs, exact wait receipt, completion seal/drain and an exit receipt.
Administrative CPU includes metadata subprocess costs and excludes the separately
reported scientific reaped child CPU; these views must not be added twice.
Old EE's 10961.212634375985 conservative CPU charge remains retained, with no refund.

The CPU31 parent optionally takes a current process/thread census every 60 seconds
after the prior scan finishes. It uses the unchanged R154 classifier, excluding
only its exact held LV child and that child's direct payload for observation.
Only classified conflicts retain relevant lifetime, argv, executable, cwd, masks
and reason when readable; departed facts remain unknown. It does not signal,
exempt a peer, change the original 521 guard, or retry a failed call. The nominal
observation latency is **60 seconds plus scan/scheduling time**, with no guaranteed
capture of shorter peers. Observation stops at 70% of the administrative CPU cap;
the parent stops its held child before 90% if its finite own budget is threatened.
Root must price the measured scan cost over the full six-hour bound before launch.
The pricing pin retains measured preparation/private-child costs and a conservative
20 CPU prior administrative debit separately from the fresh 120 CPU runtime cap;
the combined administrative envelope is 140 CPU. These debits do not modify the
original numerical LV grant or refund its pre-existing 100 CPU prior debit.

Tests are private metadata/kernel subprocesses on CPU31, including busy original
lock behavior, old lifetime/unit rejection, preserved scientific argv, inherited
funded CPU hard limits, held-child identity/reaping, actual PDEATHSIG and failed
preflight with zero claim/dispatch. They import no numerical/model libraries.

After launch, run the **new source** entry with the same admitted authority and
pin plus `--inspect` under the same `taskset -c 31 PINNED_PY -B` prefix. It reads
the actual new admin source/lifetime/unit and original 521 guardian/payload,
original claim, exact call seals, recorded pools, CPU receipts and fixed clocks.
It creates no runtime files, claim or numerical process. Save stdout in a new audit
location. Counts are verified completed call seals; completion still requires the
original assessment, clean child exit and exact physical drain.

If the original child exits nonzero, the admin also makes one immediate read-only
incident attempt using reported peer PIDs from the saved traceback. Current
lifetimes may differ from the reported PID; disappeared peers remain explicitly
unknown. Neither the interval observer nor this failure snapshot changes the old
classifier or reconstructs an unrecorded old lifetime.
