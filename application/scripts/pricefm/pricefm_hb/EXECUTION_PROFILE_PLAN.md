# Prospective actual-component profiling preparation

`execution_profile_plan.py` is a standard-library metadata compiler. It prepares
the exact FI and DK2 coverage universe and the instrumentation contract needed
for a separately admitted numerical profile. It reads JSON and Python text;
it neither imports the scientific executor nor opens numerical payloads,
submits jobs, changes prices or grants numerical authority.

## What the compiler verifies

- Exact accepted price, cost-plan and timing certificate hashes; exact frozen
  preparation/configuration hashes; four accepted scientific source hashes.
- The complete FI20-package/19-geometry/240-task and DK221-package/20-geometry/
  252-task universes: every package × three splits × D0/S0/S1/S2 identity.
- Four clocks0/24/48/72, H96, seven quantiles and100 training paths; frozen
  parent/scaler/bank, complete origin/timestamp and forecast RNG identities.
- Original reserved CPU/wall and exact null/dictionary reuse identities. The
  compiler preserves the whole accepted price certificate, including all
  branches. It does not reprice, select nominees or infer a refund.
- Joint dimension domination within the same mode and feature policy using
  p,m_y,m_x,depth,input_fan_in and recurrent_sparsity together. Missing four-clock
  and exact seed/split measurements are identified separately from geometric
  domination. Large p alone does not establish coverage.

The accepted original metadata produces492 explicit task entries. FI156/240
and DK2180/252 lack joint timing dominators. All tasks lack full four-clock
measurement in the old midnight-only panel. This is a coverage diagnosis, not
permission to replace the global-mode fallback with a favorable row. Every
prospective measurement or valid unchanged-rule domination must be accounted
for in a new complete finite protocol. The universe does not prescribe492 new
jobs or assume such a profile is affordable.

## Actual lifecycle and comparison order

The compiler identifies13 source/AST/line-bound hooks across frozen
`prefix.py`, `benchmark.py` and `science.py`. They cover startup/authority,
staged-input verification, runtime/adapter setup, parent-context loading,
arithmetic, retained-array conversion, chunk validation/serialization,
concatenation/full validation/metrics, full serialization, final seals and
cleanup. The all-parent PSD/preflight period is a **separate panel comparison**:
ordinary `prefix.run_component` does not invoke it, and preparation does not
insert it into ordinary numerical execution or subtract it from old timing.

A future immutable executor must implement these hooks and private accounting
tests before obtaining a numerical profile scope. Retain whole process and
aggregate parent/child CPU, complete wall, disjoint phases and unattributed
residuals, IO counters, peak RSS, affinity/cgroup and source/runtime identities.
Slurm primary allocation CPU is charged once; step/child counters attribute
that total instead of being added again. Failed, uncertain and reserved
charges remain. Startup wall, validation/list conversion and cleanup are
included rather than hidden outside the timed prediction kernel.

The two prospective storage alternatives are direct retained-source access
and amortized reuse of a fresh owned private scratch copy. Cache state remains
UNKNOWN. Fix comparison order and reuse count before measurements. Charge
copy/hash/cleanup CPU and wall; do not assume a single-pass copy is faster.
Only the fresh marker/inode-proved scratch tree can be removed. Original
source trees, parents, banks and all useful raw profile outputs are retained.

Parity requires identical scientific source and environment/native libraries,
arithmetic/RNG/origin-clock order, array keys/dtypes/shapes and ordered element
bytes, original metrics/weights and full raw packet hashes. Container-byte
differences need a reviewed serialization explanation and cannot excuse
different canonical array bytes or altered tolerances. Profiling does not
authorize another operator, candidate, seed set, official evaluation or fit.

## Interface and reproduction

From `application/scripts/pricefm`, use the existing administrative Python,
`PYTHONDONTWRITEBYTECODE=1 TMPDIR=/dev/shm`, affinity CPU31 and `-B`:

```text
taskset -c 31 <r137_py311-python> -B -m pricefm_hb.execution_profile_plan \
  --request <absolute-new-request.json> --output <absolute-new-plan.json>
```

The CLI enforces10CPU/120wall, physical nonsymlink JSON/source files of at
most16MiB, exact path/SHA256 pins, no duplicate JSON keys or nonfinite values,
and before/open/after file identity checks. Output publication is atomic and
create-only; an existing plan is never overwritten. The compiler source and
request bytes are pinned in the output. Input payloads are not rehashed by this
administrative process; future compute admission must verify complete frozen
ledgers and attest its actual runtime.

The request has exactly these fields:

```json
{
  "schema": "r163_execution_profile_request_v1",
  "purpose": "METADATA_ONLY_PROSPECTIVE_EXECUTION_PROFILE",
  "numerical_execution_authorized": false,
  "full_screening_admitted": false,
  "studies": {
    "FI": {"cost_plan": {"path": "<absolute JSON>", "sha256": "<64hex>"}, "timings": {"path": "<absolute JSON>", "sha256": "<64hex>"}},
    "DK2": {"cost_plan": {"path": "<absolute JSON>", "sha256": "<64hex>"}, "timings": {"path": "<absolute JSON>", "sha256": "<64hex>"}}
  },
  "accepted_prices": {"path": "<absolute PRICES.json>", "sha256": "<64hex>"},
  "source_pins": {
    "prefix": {"path": "<absolute prefix.py>", "sha256": "<64hex>"},
    "benchmark": {"path": "<absolute benchmark.py>", "sha256": "<64hex>"},
    "science": {"path": "<absolute science.py>", "sha256": "<64hex>"},
    "environment": {"path": "<absolute environment.py>", "sha256": "<64hex>"}
  }
}
```

The original cost plan supplies the exact preparation/configuration pins. A
reproducible actual request and compiler receipts are retained in the R163
tracker's `profile_engineering` directory. Run the private tests with the same
environment and `-B -m unittest pricefm_hb.execution_profile_plan_tests`.

## Machine-readable handoff and admission

Output schema is `r163_execution_profile_plan_v1`, status
`PREPARED_NOT_ADMITTED`, purpose
`PROSPECTIVE_ACTUAL_COMPONENT_PROFILE_PREPARATION`. `studies.FI.tasks` and
`studies.DK2.tasks` expose all canonical identities and unchanged reservations;
`joint_geometry_coverage` records gaps. `instrumentation_map`,
`lifecycle_measurement_contract`, `storage_comparisons`, `parity_requirements`,
`source_pins`, `input_pins` and `preserved_constraints` are the review surface.

`ready_for_numerical_execution`, `numerical_execution_authorized` and
`full_screening_admitted` are always false. Nine explicit blockers cover a new
finite numerical scope/funding, reviewed instrumented executor, fresh complete
identity/runtime proof, parity, full coverage or unchanged fallback, worst
scientific memory, whole optional calendar/joint-controller proof, fresh
resource/window proof and a separate accepted certificate before repricing.
Callers cannot supply positive gate overrides. This plan has no submission or
execution action and cannot be used as a worker authority. Spent opaque/COST
claims and old clocks remain spent; Normal2000/AL300,32,400CPU/study, separate
1,800assessment, joint1,800controller and the original scientific surface stay
unchanged.
