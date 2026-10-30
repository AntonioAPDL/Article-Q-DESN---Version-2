# Saved training metadata audit

This tooling verifies existing internal-training JSON and reproduces the existing
equal-three-split frozen selection. It does not compute losses, open binary fit
or bank arrays, register candidates, mutate a campaign, or submit jobs.

The auditor applies one fixed rule to all 38 region records: an internal_score
task must have matching pinned task/result/completion-seal/source identities,
the seven original AL quantile companions, and a complete certified three-split
group. The original finite AND (formal OR independent) rule, seven independent
limits and both RHS starts are preserved. Unknown task kinds, official-test
selection flags, mismatched sources and missing evidence cannot create an
eligible group. Existing frozen winners are compared, never replaced.

The current binder runs on Muscat's saved campaign roots and explicitly uses the
previously collected local SI metadata. Other Jerez regions remain
REMOTE_NOT_OBSERVED. The generic auditor can consume another prospectively
reviewed local-copy configuration, but the binder does not perform remote
collection or follow logical original Jerez paths. Absence of scaler or recursive
alignment metadata is reported as unproved, not passed.

## Reproduction

Use the pinned Python3.11 administrative runtime, CPU31, one thread, low
priority, a fresh finite administrative authority and create-only output paths.
Do not reuse a closed scope or the existing run's output directory.

1. Run training_metadata_audit_tests.py on owned synthetic JSON. Its negative
   cases cover path/symlink/hardlink escape, pin drift, duplicate/nonfinite JSON,
   wrong authority or regional inventory, changed original limits, missing
   starts, source-head drift, official-test evidence, duplicate/missing splits,
   selection reproduction, and the distinct NO4 failure/exclusion sets.
2. Invoke training_metadata_audit_bind.py with --health-root, --authority,
   --data-root, --si-collected, --frozen-no4 and --output-config.
   This creates a fixed source/JSON-input allowlist. Binding is not an audit
   result or a numerical authority.
3. Freeze and independently review the source and configuration SHA256s before
   actual execution.
4. Invoke training_metadata_audit.py --config ABS_CONFIG.json
   --config-sha256 EXACT_SHA256 --output ABS_NEW_OUTPUT_DIRECTORY.
   The CLI retains a12CPU/90wall bound and requires CPU31. Failed attempts and
   their fees remain part of the evidence; do not automatically retry them.
5. Verify MANIFEST.json, RESULT.json, TRAINING_SPLITS.csv and REPORT.md
   after the process exits. Do not pin a redirected stdout file while the
   process is still writing it.

AUDIT_CONFIG_01.json and the immutable source freeze in the associated
implementation tracker give the exact completed run's command and input
bindings. The Normal/AL budgets remain2000/300. Source, priors, seeds, scalers,
feature policies, units and equal-three-split selection remain unchanged.

## Interpretation

NO4's eight required failed AL fits are compared against the pinned original
diagnosis, task/certificate/terminal identities and seals. Their component ratios
and same-target tau comparisons are descriptive. The144finite RHS precision
exclusions remain a separate set. Neither set authorizes retries.

Training split heterogeneity can motivate a further source/provenance
investigation. It is not proof of a causal defect or permission for extra
iterations, a broad screening grid, test-ranked launches, posthoc interval
adjustment, promotion or heavy Hummingbird jobs. Those require separate
prospective scientific, runtime, physical/drain, pricing and scheduling gates.

## Additional Jerez metadata, with a separate authority

The optional training_metadata_collect.py tool is a new, independently scoped
input expansion; it never edits or retries audit01. Its remote path is compatible
with Python3.6, has no child processes, and applies its own6CPU/120wall bounds.
It accepts only the reviewed18Jerez roots plus six exact, previously sealed SI
training-scaler JSON supplements. No network is performed by the source itself:
the parent must review and explicitly execute its source-bound invocation.

The packet caps are5120files,2MiBper sourceJSON,64MiBexported payload,
96MiBencoded packet and8MiBcompressed gzip. Preparation records are explicitly
typed DERIVED_TRAINING_CONTEXT projections of source/input/bank identities and
selection flags. Their original preparation path/hash/stat is preserved; the
projection bytes are not represented as original bytes. Large historical
references and test-comparison sections are not exported. All other selected
task/result/certificate/terminal/design/scaler/seal JSON is byte exact.

Remote collection must use training_metadata_collect_bootstrap.py: its exact
reviewed text receives SOURCE_BASE64, EXPECTED_SOURCE_SHA256 and PLAN_BASE64.
It hashes the actual decoded collector bytes before exec, compares the reviewed
plan's source hash, and arms the collector's verified-source namespace. Direct
collection without this verified bootstrap is rejected. Both sources remain
Python3.6 compatible.

The plan must be a newly reviewed actual
ROOT_AUTHORIZED_PRICEFM_ONLY_JEREZ_COLLECTION with the exact collector source
hash, source/shape/clock bindings, collectionnonce and base audit01 config pin.
Topology preparation by itself is not execution authority.

Local mode is --materialize --plan ABS_PLAN --plan-sha256 EXACT_PLAN_SHA
--execution-receipt ABS_EXECUTION_RECEIPT --base-config ABS_AUDIT01_CONFIG
--bank ABS_NEW_BANK --output-config ABS_NEW_CONFIG02.
It requires the actual reviewed execution receipt and successful local owned
guardian output. It verifies wire/source/nonce/shape/role/identity hashes before
creating a bank, preserves a durable RAW_PACK.json and MANIFEST.json, and creates
only a new config02 and a clearly labelled reconstructible JSON cache.
Individual cache-file durability is not claimed; the authoritative packet and
its index remain durable. This changes no canonical scientific output bank and
does not weaken D5's completed raw-return durability guarantees.

The actual receipt must bind exact plan, collector source, bootstrap source,
independent preexecution review, root EXECgrant and guardian pins. The accepted
guardian has actual integer-zero returncodes, CPUlimit6, finite nonnegative
aggregateCPU below6 and complete lifecyclewall at most120, independent/kernel/
owned-reaped flags true, no capreason and no forced monitor stop. BooleanFalse
is not accepted as integerzero. Strict JSON parsing rejects overflow such as
1e999, not only explicit NaN/Infinity tokens. Local/remote6CPU/120wall limits
are explicit integer bindings in the reviewed plan.

The separate --restore-cache mode can rebuild a missing cache from its durable
packet only under a fresh ROOT_AUTHORIZED_METADATA_CACHE_RECONSTRUCTION grant
with an exact bank-manifest pin. It refuses to overwrite an existing cache,
preserves the old packet/manifest, does not reexecute collection, and does not
reuse the old collection's execution clock. A future audit still needs its own
fresh authority.
