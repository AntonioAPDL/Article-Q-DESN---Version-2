# Same-family GloFAS closeout software

## Scope and present status

This change supplies the missing closeout interface for the sixteen-producer
same-family future-path campaign. It does not fit a model, change a live
ledger, open future USGS observations, change article authority, or publish
Overleaf. Its tests use synthetic metadata, a temporary SQLite database and
small generated forecast tables only. The active scientific source and its
processes remain unchanged.

Software completion is not scientific campaign completion. The real closeout
requires all sixteen accepted producer packets, a separately sealed consistent
ledger snapshot, the authenticated analytic Normal enrollment, and an
authenticated truth-free extraction of the issued members. Missing or
incompatible evidence must stop the closeout. No marker is a substitute for
these checks.

## Producer and reporting contracts

The producer identity is frozen in `gsc_identity()` and the Python collector's
`IDENTITY`. It binds source commit
`fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6`, its tree, and the scientific source,
target, input and task manifests. Task and RNG names remain the historical
`gft-al-p*`, `gft-exal-p*`, `gft-mq-al` and `gft-mq-exal` names. They are not
relabelled as newly executed jobs.

For each producer the collector rechecks the existing controller's canonical
output manifest and all six retained artifacts, including a bytewise hash of
the fit. It does not deserialize a model. Both native inventory representations
(`shards` or `artifacts`) are supported, but simultaneous ambiguous inventories
are rejected. Source, target, routing, nonce, terminal identity and closed
accounting must agree. An incomplete, failed, active or retried mixed ledger
is rejected by this initial, exact-cohort interface; a future recovery with
reconciled attempts would require an explicit reviewed adapter revision.

The collector imports only the existing controller module and invokes its
static `Ledger.accepted_output_readonly` method with an explicitly read-only,
query-only SQLite connection. It never constructs a mutable `Ledger`,
checkpoints WAL, dispatches, claims, retries or acknowledges an attempt.

The sixteen target receipts must report the current same-family reference
transition, unit member factors, separate level-specific MQ paths and the
original two-block reference/discrepancy design. There must be 28 future
response factors and 1,428 issued-member factors per level, not the historical
zero-response-factor target with a replacement Gaussian driver prior.
Initializers remain moments only, not destination priors or convergence state.

The Normal models are a separate, authenticated reuse enrollment, not two more
new GFT tasks. The receipt must bind source
`cfa50ff3f4eebbdbf36c03c50b04bf2bed39c437`, its tree, exact protected-design
identity and the prepared-design digest. It must report analytic response
quantiles, no model/builder/scoring calls and no extra response noise or
isotonic adjustment. Old empirical Normal reports cannot be substituted.

All model curves use the quantiles of the full ensemble-conditioned Gaussian
VB future-response factor,
`m[h] + sqrt(V[h,h]) * qnorm(p)`, followed by `expm1`. These are approximate
marginal response quantiles, not credible limits for a fitted quantile
functional. No new error draw is added to this already inferred response
factor. No quantile path is clipped, reordered, projected or selected using
the protected window.

The required issued-member extract has exactly four columns:
`target_date,horizon,member,g_transformed`. It has 28 dates and all 51 distinct
members per date. Raw quantiles use type-8 empirical quantiles on the log1p
scale. Seven retained raw quantiles cannot reconstruct 51 authentic paths.
The extraction must have its own immutable derivation receipt tying its hash
to the prepared, truth-free design. This software intentionally does not load
that design or manufacture the extraction.

## Entry points and data flow

1. `scripts/collect_glofas_same_family_producers.py` validates a **quiescent,
   pinned SQLite snapshot** and emits a bounded metadata collection to stdout.
   A nonempty companion WAL is rejected. The live database must never be
   copied blindly, checkpointed or modified by this collector. A coordinator
   must first obtain a SQLite-consistent snapshot after all accepted states
   and supervisor exits are verified.
2. `scripts/finalize_glofas_same_family_transition.R --mode assemble` validates
   the collection, sixteen target receipts and forecast CSVs, separate Normal
   enrollment and raw-member extract. It assembles and validates exactly
   1,372 family/date/level rows without opening scoring truth.
3. It writes `quantile_paths.csv`, `raw_crossings.csv` and
   `accepted_producers.json`, then persists `FORECAST_SEAL.json`. The seal binds
   their exact hashes, all sixteen historical identities and the Normal/raw
   input pins. It is reverified before the first truth read. An ordinary final
   artifact manifest does not replace this pre-truth commitment.
4. Explicit `--mode score` authority may then open a separately pinned
   28-row USGS sidecar, containing `target_date,horizon,y_transformed`.
   The scorer has no selection, retuning, fitting or seed-screening interface.
   It computes the seven families together, with no case-level fallback.
5. `scripts/build_glofas_same_family_article_projection.R` independently
   recomputes every scored packet's numerical summaries and creates a
   **candidate-only** CSV and TeX score table. Its companion checker verifies
   the exact candidate membership, labels and values. Neither writes article
   aliases, figures, manuscript prose or publication refs.

The exact row accounting is:

| Component | Rows |
| --- | ---: |
| Fourteen independent quantile fits | 392 |
| Two MQ fits | 392 |
| Two analytic Normal baselines | 392 |
| Raw issued-member quantiles | 196 |
| Complete seven-family grid | 1,372 |

Every family uses the dates 26 December 2022 through 22 January 2023 and
levels `0.05,0.20,0.35,0.50,0.65,0.80,0.95`. The primary realized finite-grid
aCRPS is twice the trapezoidal integral of check loss on the log1p scale, with
weights `0.075,0.15,0.15,0.15,0.15,0.15,0.075`. The weights sum to 0.9 and
are not normalized to one. The packet retains seven aggregate scores,
196 family/date scores, 49 level-specific calibration summaries, nominal
central-90% coverage and raw crossing counts with denominator 168 per family.
Coverage below nominal and inverted intervals are retained, not corrected.

## External contract interfaces

All file pins are objects with absolute nonsymlink `path`, positive integer
`size_bytes` and `sha256`. No token or credential belongs in either contract.

The collection contract has:

```text
schema_version = glofas_same_family_collection_contract_v1
allow_ledger_mutation = false
allow_refit = false
allow_truth = false
expected_identity = exact six fields from gsc_identity()
master_sha256 = complete cohort's authenticated master digest
ledger_snapshot = file pin of the separately sealed SQLite snapshot
complete = pin of the matching COHORT_COMPLETE_NOT_ARTICLE_PROMOTION receipt
controller_source = pin of application/scripts/forecast_transition_control.py
read_budget.max_artifact_bytes = positive integer, at most 8 GiB
read_budget.max_total_artifact_bytes = positive integer, at most 44 GiB
```

The finalizer's external purpose contract has:

```text
schema_version = glofas_same_family_closeout_contract_v1
mode = assemble OR score
allow_assembly = true
allow_scoring = (mode == score)
allow_refit = allow_retuning = allow_publication = false
source_commit, source_tree = clean reviewed closeout implementation
expires_utc = UTC expiry covering the full requested wall time
source_files = pins for the four closeout/controller implementation files
expected_identity = exact six frozen producer fields
collection_contract = file pin of the preceding collection contract
normal_manifest, normal_receipt, normal_quantiles = authenticated file pins
prepared_design_sha256 = common exact protected prepared-design digest
raw_member_derivation, raw_members = authenticated truth-free file pins
output_root = fresh ignored child of this worktree's local_trackers
limits = finite cpu_seconds, wall_seconds, memory_bytes, output_bytes,
         logical_cpu (a separately authorized, unprotected logical CPU)
```

Score mode additionally requires `truth_role=post_fit_scoring_only`,
`model_selection_or_retuning=false` and a `truth` file pin. Assemble mode must
not open this sidecar. No contract template grants permission to execute.
Both external contract bytes and their supplied SHA-256 digests are checked.
The compiled artifact-read ceilings accommodate the frozen producer admission
limits (including the larger MQ outputs); they are not a grant to hash that
amount. The actual separately costed external purpose must specify its own
finite read limits, normally much lower, and sufficient whole-purpose CPU and
wall budgets. An exceeded read cap stops rather than being renewed implicitly.
The total artifact ceiling is `14*2 + 2*8 = 44 GiB`; it excludes the separate
44 GiB reserved for logs. The collector never reads or imports those logs.

The R entry point requires pinned R 4.6.0 on Muscat, one BLAS/OpenMP thread,
the exact CPU affinity, finite OS CPU/address-space/file-size limits and a
native TERM/KILL timeout covering the whole process group. Protected current
scientific cores and known protected siblings are excluded. Fresh resource
admission, costing and an authorized external supervisor remain coordinator
responsibilities; this code does not acquire a CPU grant or launch itself.

## Verification and remaining publication gates

Focused synthetic tests:

```bash
env OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  taskset -c 28 timeout --signal=TERM --kill-after=1s 120s \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/tests/test_glofas_same_family_closeout.R

env OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  PYTHONDONTWRITEBYTECODE=1 taskset -c 28 \
  timeout --signal=TERM --kill-after=1s 120s /usr/bin/python3.11 \
  application/tests/test_glofas_same_family_collection.py
```

The R tests cover exact identities, target/Normal compatibility, row and
transform checks, score algebra, preservation of adverse coverage/crossing
results, pre-truth sealing, independent numerical checking and rejection of
changed forecasts even when the final manifest is recomputed. Python tests
exercise the real static read-only controller API against tiny synthetic
SQLite/native-shard fixtures, including active/failure/retry states, wrong
targets, terminal identities, sidecar/payload tampering, unknown artifacts,
WAL ambiguity, finite read ceilings and symlink rejection.

The old eighteen-marker unit-member finalizer and generic simulation DKW
scorer are deliberately not reused or weakened. Their target/reporting
contracts do not describe this GloFAS factor.

After the real packet is complete, a later reviewed article integration must
still authenticate historical plotting extracts; implement and review vector
figures; replace all seven-family tables, aliases and text atomically; retain
the realized-weather information-set qualification and model diagnostics;
test the combined repository; compile main and supplement; verify the clean
article-only source bundle; and pass the applicable publication policy and
remote-readback gates. IND/MQ simulation completion is not a prerequisite for
this scientific GloFAS closeout, but final project/publication requirements
must not be bypassed. No article approval follows from an assembly, scoring,
candidate projection, or successful unit test alone.
