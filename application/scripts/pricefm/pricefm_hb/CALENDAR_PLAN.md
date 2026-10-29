# Complete-grid calendar and controller preparation

`calendar_plan.py` is a stdlib metadata planner and witness verifier. It does
not launch a worker, load numerical arrays, read losses, change a price, renew
a grant or admit a scientific study. Its output is always
`r163_calendar_preparation_v1` / `PREPARED_NOT_ADMITTED` with
`scientific_admission=false`.

## Frozen scientific and financial surface

The CLI binds the exact accepted R161 `PRICES.json` SHA256 and both original
preparation/config SHA256 pairs. Exact archived copies are acceptable; resigned
modified prices or preparations are rejected. Complete manifests contain
FI240tasks/76branches and DK2252tasks/80branches. Every package, split,
D/S0/S1/S2 identity, four clock offsets, H96, seven quantiles, frozen audit
permutation, geometry-distinct B, nine S0 components, whole qualified12/18
extras and one replacement remain unchanged. No selection loss is read.

All component CPU/wall reservations are copied from the accepted prices.
Additional batch overhead must be explicit and is accounted separately. An
unknown overhead may be represented by an optimistic zero for diagnosis only;
its evidence flag remains false. It is never declared measured or free.

## Search and independent verification

For each phase, the planner creates balanced alternatives at several bin
counts. This differs from minimizing the number of bins alone. The finite
diagonal search explores phase alternatives fairly, under explicit maximum
combinations and CPU/wall limits. Every task appears exactly once within its
original phase; imported tasks remain explicit zero-price identities.

Scenarios cover every possible nomination/qualified branch, every nonempty
failed phase, and actual worker counts1/2/3/4: FI836 and DK2880 scenarios.
Three actual workers are conditional on a future legal four-worker policy;
the policy ladder remains1→2→4. Each scenario preserves D→nomination→S0→extras
root barriers, one dominating reconciled-component replacement after its
possible failed phase, at most three numerical waves, dispatch before5400,
lease/drain by7200, component-batch CPU/wall≤5400 and the separate1800-second
assessment inside the original outer clock. A lost batch with multiple
uncertain children is not treated as one automatically replaceable component.

Constructive calendars are witnesses under declared assumptions, not proofs
of globally minimum makespan/job count. A violated volume or individual-item
bound can prove reservation infeasibility. A failed finite search remains
`UNPROVEN`. `verify_preparation(result, models, assumptions)` checks complete
unique scenario coverage and every witness without rerunning the search. It
binds outer labels to inner worker/replacement/branch identities, rejects
Boolean/integer substitutions, recomputes prices, counts, controller estimates
and gates, and verifies phase coverage, barriers, waves, leases, worker
nonoverlap and assessment tails.

## Shared capacity and joint controller accounting

Independent per-study four-worker calendars do not establish a joint
four-worker calendar. Output therefore retains
`joint_calendar.certificate=false` and a hard-false
`joint_aggregate_capacity_calendar_certificate` gate. No implied eight-worker
allocation is created. `verify_shared_capacity` can check one explicitly
provided FI/DK2 pair, common wave anchors and combined job/assessment/drain
intervals under the shared1/2/4-worker ceiling, constructing a shared-slot
assignment. Its result explicitly does not certify all branch pairs or grant
scientific authority.

The joint1800CPU controller estimate requires all eight operation categories:
preparation, cache, metadata, transfer, parent, proof, publication and recovery.
Each row declares integer unit CPU, base/per-study/per-job/per-wave/per-phase
counts and whether its cap is measured. Existing joint charges are retained.
Every job, including replacement and assessment, has a parent charge. Unknown
grid measurements or missing complete calendars block the joint certificate;
a conditional estimate is not operational funding.

`atomic_extra_check` requires the entire frozen12/18 set and complete actual
charged-prefix membership. It subtracts the retained replacement reservation
and checks whole-set CPU, future additional batch overhead, complete calendar,
joint controller and prospective evidence. Prior prefix overhead is already
represented by actual charges and is not charged again at this decision.
Insufficient resources defer the whole set. Cheap actual completed work can
fund extras even when a worst-reservation branch fails; the planner never
predeclares all extras unavailable. Even a passing metadata check returns
`admitted=false` / `ATOMIC_RESOURCE_FIT_NOT_AUTHORITY`; the original scientific
qualifier and a separate valid numerical authority remain necessary.

## CLI and immutable artifacts

Run on administrativeCPU31 with the existing stdlib Python, `-B`,
`PYTHONDONTWRITEBYTECODE=1` and `TMPDIR=/dev/shm`:

```text
python -B calendar_plan.py --inputs /absolute/INPUTS.json \
  --inputs-sha256 EXACT_INPUT_SHA256 --output /absolute/DIAGNOSTICS.json \
  --search-combinations 64 --maximum-cpu-seconds 20
```

Input schema is `r163_calendar_inputs_v1`, purpose
`PRICEFM_METADATA_CALENDAR_PREPARATION`, with exact fields `schema`, `purpose`,
`studies`, `prices`, `assumptions`. `studies` maps FI and DK2 to preparation and
config `{path,sha256}` pins; `prices` is another pin. `assumptions` contains
explicit batch overhead, calendar tails, complete controller grid, remaining
outer wall and six evidence states. Paths must be physical, absolute, regular
JSON files≤16MiB. Hashes, unchanged read identity, duplicate keys and all
nonfinite JSON numbers are checked. Results use atomic create-only hard-link
publication; a prior artifact is never replaced.

## Actual R163 diagnosis

The real64-combination preparation covered all492tasks,156branches and1716
scenarios. The compact witness artifact is about5.47MiB. Independent final
verification checks its supplied constructions; it does not trust the search
to claim feasibility.

Compared with the preceding DK2 diagnosis, all40 mandatory two-worker cases
now have constructive witnesses (previously23constructive/17unproven).
Three-worker optional cases improve50→75 of180. Four-worker optional cases
remain163constructive/17unproven. These improvements do not establish the
complete optional calendar, a shared FI/DK2 calendar, memory, measured overhead
or an executable screening authority.

FI's38 mandatory cases have constructive independent calendars with3/4
workers, but its unchanged CPU funding gate still fails. At four workers,
165optional FI cases remain unproven. The illustrative complete joint operation
grid costs5705CPU against1800, and is explicitly unmeasured. Most calendars do
not fit the original outer time remaining at the snapshot. No full screen is
admitted.

The first2000-combination metadata search reached its90CPU hard bound before
publishing an output; that failed reservation is retained. The revised finite
search completed in12.094CPU/12.048wall under a separately reserved20CPU maximum
within the same120CPU engineering allowance. It produced witnesses during
engineering, before the final verifier was added; final source independently
revalidates them rather than claiming a frozen historical producer hash.
Original failed costs, clocks and scientific attempts are unaffected.

Engineering receipts, immutable accepted input pins, failed-attempt record,
actual witnesses and independent reviews are retained under
`local_trackers/pricefm_r163_profile_preparation_20261028/calendar_engineering`.
Unit tests use synthetic scalar metadata only. No HB access or new numerical
work is involved.
