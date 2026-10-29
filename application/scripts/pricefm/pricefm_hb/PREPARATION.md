# PriceFM preparation tools

These administrative tools turn fixed metadata into reproducible preparation evidence. They do not stage, submit, release, cancel or retry jobs. They do not import numerical executors, change a live owner, revise scientific prices, grant numerical work, or renew an expired scope. Existing scientific modules are unchanged.

## Workflow

1. Capture PriceFM health with its original source-specific observers under a new finite administrative allowance. Preserve the exact observations and existing source/authority pins.
2. Compile a dispatch diagnosis with `dispatch_diagnosis`. It describes Muscat owner6 only. Unreadable protected processes stay unresolved; a process name never creates an exception. Even a clean snapshot does not replace the original owner's reconciliation and authority.
3. Compile the joint492-task profiling contract with `execution_profile_plan`. It reads source as text, verifies accepted hashes and original complete FI/DK2 identities, and maps actual lifecycle hooks. The numerical executor must later implement those hooks in a separately reviewed source. The plan is not measured scientific evidence.
4. Compile phase-specific calendar diagnostics with `calendar_plan`. All original branches and replacement phases remain explicit. `CONSTRUCTIVE` means a verified single-study calendar under declared assumptions; `UNPROVEN` is not mathematical infeasibility. Unknown overhead is never a measured zero. Separate four-worker calendars are not a shared-four-worker certificate.
5. Join the exact pinned artifacts with `preparation`. The joiner reconstructs the profile from frozen inputs and source, reconstructs the calendar models from original prices/preparations/configs, and independently checks every supplied constructive calendar and complete scenario universe without rerunning the search. It rejects rewritten task identities, invented feasibility, changed costs, incomplete coverage and mismatched cohorts. The dossier remains non-admitting.

All JSON inputs are bounded at16MiB, require absolute physical paths and SHA256 pins, and reject duplicate keys and nonfinite values. Outputs are create-only; a changed request requires a new output filename. Pins must come from the reviewed packet/manifest, not from an assumption that a mutable file still matches an older result.

## Administrative command pattern

Use the pinned administrative interpreter, one physical administrative CPU, no bytecode, and the declared finite scope. Run from `application/scripts/pricefm` in the isolated preparation feature worktree:

```bash
PYTHONDONTWRITEBYTECODE=1 TMPDIR=/dev/shm taskset -c 31 \
  /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python -B \
  -m pricefm_hb.preparation \
  --request /absolute/physical/dossier-request.json \
  --request-sha256 REVIEWED_REQUEST_SHA256 \
  --output /absolute/physical/new-dossier.json
```

The join request has exactly:

```json
{
  "schema": "r163_preparation_request_v1",
  "purpose": "PRICEFM_PREPARATION_EVIDENCE_JOIN",
  "numerical_execution_authorized": false,
  "inputs": {
    "dispatch": {"path": "/physical/diagnosis.json", "sha256": "REVIEWED_SHA256"},
    "profile": {"path": "/physical/profile-plan.json", "sha256": "REVIEWED_SHA256"},
    "calendar": {"path": "/physical/calendar-diagnostics.json", "sha256": "REVIEWED_SHA256"},
    "health": {"path": "/physical/health-summary.json", "sha256": "REVIEWED_SHA256"},
    "output": {"path": "/physical/saved-scalar-review.json", "sha256": "REVIEWED_SHA256"}
  }
}
```

The dispatch request is exactly `schema:r163_dispatch_request_v1`, `current:{path,sha256}` and `prior:{path,sha256}` (or null). Its CLI requires `--request`, `--request-sha256` and `--output`. Source identity is fixed to the accepted Muscat owner6 runtime; a future owner/source needs a separately reviewed adapter, not a relaxed check.

Profile and calendar request schemas, source-bound timing coverage and their full operational requirements are documented in [EXECUTION_PROFILE_PLAN.md](EXECUTION_PROFILE_PLAN.md) and [CALENDAR_PLAN.md](CALENDAR_PLAN.md).

## Interpretation and limits

The dossier keeps nine prospective profile requirements blocking: finite numerical authority/funding, reviewed instrumented source and accounting, fresh complete attestation, whole-component parity, complete joint geometry/mode/clock/seed timing or unchanged fallback, scientific memory/capacity, complete calendar/controller proof, resource ownership/whole execution window, and a separate accepted price certificate before repricing. A prepared protocol cannot make its own future measurements pass.

The original32,400CPU per study, separate1,800assessment, joint1,800controller, H96/sevenquantiles/fourclocks,100training/500officialpaths, Normal2000/AL300 and all frozen parents/scalers/banks/seeds/origins remain unchanged. Optional extras must pass their original actual-charge funding rule and whole-set resource requirements; never run a convenient partial12/18set. Failure charges, spent attempts and old clocks remain retained.

The R163 dossier adapter binds the29-region/87-fold saved scalar review. A later cohort needs its own source-checked review and adapter update. It does not silently reuse an older aggregate, retarget exposed poor regions, choose another primary operator or authorize promotion.

The shared scientific capacity proof remains a separate gate. The calendar's independent-study witnesses and conditional controller operation grid are useful diagnostics; neither is a complete joint scientific launch certificate. A provided calendar verifier can validate a construction, but search exhaustion, unmeasured assumptions and absent cross-study witnesses remain visible.

## Verification

Run the new metadata tests under the same pinned interpreter/CPU environment:

```text
python -B -m unittest pricefm_hb.dispatch_diagnosis_tests \
  pricefm_hb.execution_profile_plan_tests pricefm_hb.calendar_plan_tests \
  pricefm_hb.preparation_tests
```

Tests use synthetic metadata. Actual preparation packets compile against the accepted archived scientific metadata and source text without reading model arrays or evaluating new losses. Independent adversarial review checks the complete grids, source/price identity, evidence forgery, calendar barriers and shared-capacity limitation. Final source/test/packet hashes and administrative accounting are retained by the separate R163 audit directory.
