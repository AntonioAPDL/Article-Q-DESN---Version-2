# R164 distinct prospective synthetic authority

`repair_authority.py` implements the new policy consumer and launcher required
after the original522 CPU30 pool expired. It does not edit or import the old
522 admission function. It does not issue a grant. Source engineering/tests are
metadata-only; an actual numerical run needs the reviewed, published sources
and the complete separately funded authority chain below.

The frozen R157 scientific source remains native HEAD
`4541f853e65bf16736e58509775f8c9cbe8b6ed2`. The original
`525_project_projection_toy_validation.R`, its mathematical bodies and all
scientific assertions remain unchanged. Its existing interface accepts the new
global contract's finite expiry, same physical flock and single-worker fields.
The Python launcher and finalizer are versioned R164 protocol consumers. The
new grant schema is `r164_projection_toy_grant_v1`; the unchanged R toy's status
string is retained only as its explicit interface field.

## Scope and authority chain

The study purpose is exactly
`NEW_PROSPECTIVE_PRICEFM_SYNTHETIC_PROJECTION_TOY_ONLY`. Its unique ID matches
`r164-projection-toy-[A-Za-z0-9_-]{8,100}`. New funding and a prospective window
of at most7,200seconds are distinct from the old allocation. Old clocks,
claims, funding, failed attempts and charges remain unchanged. The policy pins
the exact old global/resource hashes and original failed toy grant. The new
grant retains every paid-history pin from that grant plus both root driver
accounting receipts and the second attempt's failure receipt. No unused old
balance is claimed.

| Artifact | Required schema/status | Direction of authority |
| --- | --- | --- |
| Root source/funding authorization | `r164_distinct_study_root_authorization_v1` / `ROOT_REVIEWED_NEW_PROSPECTIVE_SYNTHETIC_STUDY` | Binds full proposed-policy semantic SHA, source bindings, study ID, new300CPU funding and no production authority |
| New resource policy | `r164_projection_toy_resource_policy_v1` / `ROOT_ADMITTED_DISTINCT_PROSPECTIVE_SYNTHETIC_STUDY` | Pins that root authorization and immutable old history; fixes window, original lock D/I, one attempt, owner/claim/output directories and execution sources |
| New global contract | `r164_projection_toy_global_contract_v1` | Pins new policy and fresh physical-peer census; same study/window, `max_new_numerical=1`, original lock directory, `old_pool_renewed=false` |
| New numerical grant | `r164_projection_toy_grant_v1` / `ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY` | Pins actual new pool/policy, scientific/native source, separate adapter source, runtime/bootstrap proof, paid history, fresh publication and priority drain |
| Canonical owner admission | `r164_distinct_study_owner_admission_v1` / `ROOT_ADMITTED_EXACT_NEW_STUDY_OWNER` | Created after hashing the grant; binds exact grant/pool/policy and original lock D/I at `policy.owner_admission_dir/<scope_id>.json` |
| Canonical one-shot claim | `r164_distinct_study_claim_v1` | Atomic create-only `policy.claim_registry_dir/<study_id>.json`; a second output/grant cannot reuse the study |

Root authorization hashes `draft_policy(policy)`: the complete policy with
status `PROPOSED_DISTINCT_PROSPECTIVE_SYNTHETIC_STUDY` and without its
`root_authorization` pointer. This makes the source review acyclic. The admitted
policy then pins that authorization. The global contract pins the policy; the
grant pins the global contract; the owner admission pins the final actual
grant. The grant never pins its own admission envelope. A modified old expiry,
old schema with a new label, altered lock file or expired old owner handoff is
rejected.

No generic cross-host owner recognition follows from this protocol. Existing
HB `policy.validate_owner_admission` still enforces the old expiry and accepts
only the old r157 grant. It remains unchanged. The new study requires successful
EE/LV exits, no live numerical lifetimes, no pending refill and physical drain.
Any controller that would observe or coordinate concurrent local ownership
must explicitly understand the new protocol before such overlap is admitted.
For this R164 plan, the optional local toy and new HB profile experiments are
**sequenced**, with existing baseline work continuing throughout. The policy
forbids HB profile overlap. A fresh root sequencing proof must report zero
active/pending HB profile jobs before the toy, preserving the profile policy's
zero-new-Muscat-worker premise. This implementation does not amend old policies
to pretend they recognize the new owner.

## Execution boundary

The new study retains one worker on CPU30, physical guard pair30/62,
SMT62 excluded, CPU31/SMT63 reserved, and8GiB. The unchanged synthetic experiment
has exactly eight optimizer calls, 30 combined iterations, n≤128/p≤32 and no
production inputs or acceptance. The grant has at most300combined CPU seconds,
at most1,800wall seconds, at least10CPU reserved beyond its child limit, one
attempt and no refunds. Actual new funding must price all preflight, supervisor,
failure, finalizer, retrieval and outer-driver work; these ceilings are not a
claim that any measurement has passed.

Before a claim or R child, the launcher verifies:

- Exact clean scientific native HEAD and separate clean reviewed adapter
  branch/HEAD; full source closure, including this module and its metadata
  helper; fresh root Git remote readback of both sources.
- Actual frozen runtime/executable/package/shared-object pins, unchanged stock
  body and fixedpoint helper; the accepted zero-optimizer ptrace/TSYNC metadata
  receipt and tested boundary library; exact bootstrap executable closure.
- New authority, original lock path/device/inode, full prospective calendar,
  canonical acyclic admission, fresh original EE/LV success/drain and fresh
  hash-bound physical-peer census. All source/runtime hashing is charged to the
  new process budget and checks its reserve.

It then opens the existing original lock without creating or replacing it,
acquires the exclusive nonblocking flock, proves its actual held D/I, repeats
fresh priority/physical-peer checks, and creates the canonical one-shot claim.
Only then does it create the new output, constrain its own process and invoke
the pinned native R ELF through the unchanged R157 guard. The guard traces all
startup children, verifies the installed kernel TSYNC filter before scientific
access, owns/reaps its exact tree and checks the physical pair at most every
10seconds. Its existing exact-owned-lifetime signal rules remain unchanged.

New owner receipts bind the actual canonical admission and held original lock
to kernel-owned trace proof and exact owner identity. They are throttled to
10seconds within a phase; the frozen guard's own owner record retains its
existing cadence. An `UNREAPED_BLOCKED` tree never becomes an approved owner.
A failed claim remains consumed; no automatic retry or replacement is provided.
Incomplete ownership is a blocker requiring retained guard/failure evidence and
fresh reconciliation before any future study. This source does not claim that
an exiting parent can independently prove a remaining child's final drain.

The R164 metadata finalizer preserves the original scientific proof conditions:
exact default/import parity, all factors/schedules/RNG/checkpoint IO, exact stock
AST, unchanged production gate rejecting synthetic inputs, exact8/30/128/32
scope, 13 contiguous synthetic checkpoints and bound guard/runtime/source. It
does not deserialize checkpoint RDS payloads; it verifies their opaque hashes
after the admitted R child is reaped.

Its accounting result is `COMPLETE_AWAIT_OUTER_REAP_ACCOUNTING`, not production
eligibility. A separately funded root driver must retain full-parent/reaped
CPU and finalization accounting after this launcher exits, including failed
preflight costs. The launcher always reports `numerical_production_admission=false`.
The old525 bridge/pilot consumer also rejects the new protocol; a source-reviewed
versioned bridge/pilot consumer is a later gate after the toy passes, not an
implicit consequence of this implementation.

## Source-only verification and use

```bash
PYTHONDONTWRITEBYTECODE=1 TMPDIR=/dev/shm \
PYTHONPATH=application/scripts/pricefm ionice -c 3 nice -n 19 taskset -c 31 \
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python -B \
-m unittest pricefm_hb.repair_authority_tests -v
```

`fixture()` in the tests is a complete synthetic protocol witness, never an
executable grant. The public pure validators accept injected metadata readers
only for tests; production `authority()` always uses physical SHA-bound files,
real Git source readback and pinned runtime/guard functions in a private module
namespace. No numerical module or R interpreter is imported by these tests.

After root has independently reviewed the source and bound actual published
source, funding and fresh proofs, the entrypoint is:

```text
python -B -m pricefm_hb.repair_authority
  --root-grant <physical new grant.json>
  --root-grant-sha256 <exact hash>
  --output <exact new policy output directory>
  [--check-authority]
```

`--check-authority` performs source/runtime/authority and current physical-peer
checks; it creates no claim, takes no lock and runs no optimizer. It still
requires a valid newly admitted finite policy/grant and charges its own work.
The root driver must account that separate check if it is performed. Source
tests and a successful authority check do not prove numerical parity.

The synthetic toy is independent of missing NO3 remote DAG evidence. Actual
target bridge/pilot and dependent release still need current source-bound NO3
metadata and the repaired global dependency reconciliation described in
`REPAIR_READINESS.md`.

## Fresh priority and physical-peer observation

The old527 metadata producer also capped its plans at the expired old pool.
R164 therefore provides a versioned metadata-only producer, not an expiry patch:

```text
python -B -m pricefm_hb.repair_authority
  --priority-plan <new physical metadata plan.json>
  --priority-plan-sha256 <exact hash>
  --output <new plan's exact output directory>
```

The plan schema is `r164_priority_drain_observation_plan_v1`, admitted status
`ROOT_ADMITTED_METADATA_PRIORITY_DRAIN_CAPTURE_ONLY`, and separately funded
20CPU/60wall administrative scope on31 with zero numerical calls. It pins the
new reviewed policy and old immutable pool solely as historical/lock evidence.
The frozen527 source functions inspect the actual unchanged EE/LV/successor
callers and validate their completion/seals/units/dead lifetimes/no-refill. The
new producer probes the same original flock and invokes the unchanged physical
30/62 guard with a fresh hash-bound census. It never calls the old plan validator
that would require an unexpired old pool. All current permission/ownership
failures remain fail-closed and are retained. Root must review its full reaped
parent accounting before using any fresh proof, which expires after60seconds.

The first current diagnostic, at epoch1793259319.123712, failed with
`PermissionError: /proc/1315370/exe`. It used the unchanged frozen physical guard
with an empty conservative allowlist and made no claim, lock, signal, affinity
change or numerical call. This is a current ownership-visibility barrier, not
proof that that process is numerical and not a reason to ignore it. A later
admission must obtain a fresh full proof with no omitted inaccessible peers.

`repair_engineering/prepare_authority_drafts.py` prepares the actual source-bound
policy/grant/owner/capture input bundle under the R164 tracker. Every prepared
object remains a draft and includes explicit placeholders for fresh authority,
publication, source HEAD, sequencing, census and physical-proof pins. Root must
instantiate newly issued immutable files after review; converting a dated draft
in place or extending an old clock is not part of this protocol.
