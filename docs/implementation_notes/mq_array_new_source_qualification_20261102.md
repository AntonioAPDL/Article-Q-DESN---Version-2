# New-source MQ array qualification and observed-prefix preparation

Status: **source implemented; authentic preparation and qualification NOT RUN**.
Neither a successful unit test nor a prepared input grants scientific production
authority. The full native inventory, other strata, host qualifications,
production consumers/storage and whole-campaign cost gates remain separate.

## Two distinct actors

`scripts/prepare_mq_array_observed_prefix.R` is a trusted data-isolation actor,
not a numerical qualifier. It has a new, external, source-bound preparation
purpose. Only this actor may deserialize the original archived design and
fixture: exactly one read of each, plus one retained-parameter CSV read. It
accesses the response prefix through time 11,000 and the original selected
posterior row, reservoir, scaling and known time features. It never evaluates
future response values, calls a saved builder, fits a model, scores forecasts
or publishes. A complete fixture archive is materialized during this separate
preparation; the receipt explicitly records that fact, rather than claiming
zero archive reads. Fixed-index selection and constructed future-prefix
invariance tests establish the isolation rule. No protected-value statistics
or future response values are exported.

`scripts/qualify_mq_array_methods.R` is a genuinely new numerical experiment.
It never deserializes the original fixture or original design and never falls
back to doing so. It requires the prepared manifest, derivation and payload,
their exact separate preparation purpose, and the committed preparer/reducer
source. Missing or unauthenticated inputs produce an explicit
`MISSING_AUTHENTIC_OBSERVED_PREFIX_REDUCTION` gate, not qualification success.
Original source assets are streaming-hashed for provenance; that is distinct
from deserializing or using future observations.

Both scripts require literal `--contract FILE --sha256 SHA --execute` arguments
and `Rscript --vanilla`. `--help` performs no experiment. No actual contract
or physical-resource grant is supplied by these source files.

## Immutable source and runtime

The new contract schema is `mq_array_source_qualification_contract_v1`, with
purpose `NEW_SOURCE_MQ_ARRAY_ONE_ORIGINAL_DRAW_ORIGIN`. The preparer instead
requires `mq_array_trusted_prefix_preparation_contract_v1`, with purpose
`SEPARATE_TRUSTED_PREPARATION_NOT_QUALIFICATION`. Old Q2, batch-qualification
and precision-extension purposes are not accepted as execution permission.

The candidate must be clean and committed at an exact HEAD/tree. The GitHub
origin URL and an exact `refs/heads/...` publication ref are checked through
command-line Git readback without fetching, updating refs or prompting for a
password. Use a dedicated frozen publication ref so concurrent main updates
cannot change the intended source. Source pins must match the exact transitive
path set returned by `mqa_required_sources()` and each committed Git blob. Every
original native-manifest entry retains its original SHA, mode and blob. No
wildcard source exemption or weakened historical guard is introduced.

Runtime requirements are Muscat, native R 4.6.0, bundled BLAS, one numerical
thread, logical CPU 27 and a complete pinned inventory returned by
`mqa_runtime_paths()`: loaded R libraries, package code/DLLs, R binaries and
the native Git/SSH/timeout executables. Unexpected namespaces, including an
installed inference-engine substitution, are rejected. At development-time
discovery the software-focused inventory contained 105 files and 93,337,011
bytes. The final policy additionally includes every strict file-backed mapping;
these counts are observations, not permanent substitutes for discovering and
pinning the actual clean process inventory. No model object is read to build
the inventory. The shared `runtime_identity_cache_observations.R` policy treats
only `/var/lib/sss/mc/{passwd,group,initgroups}` as observed OS state, and only
with canonical regular nonsymlink paths, UID/GID 981, mode 0664 and exclusively
nonexecuting mappings. Before/after metadata and hash observations are retained,
without requiring volatile cache bytes to match. Every other mapped file,
including `libnss*.so`, remains strictly pinned. Wrong ownership, executable,
renamed/deleted or unknown SSSD mappings reject the purpose; there is no broad
cache, `/var/lib`, library or numerical-input exception. The pure policy test
is `application/tests/test_runtime_identity_cache_observations.R`.
After this change, a read-only metadata discovery found 115 strict runtime
files, 321,542,083 bytes total. The largest mapped runtime data file was the
217,800,224-byte system locale archive; the finite runtime-file reader ceiling
is therefore 256 MiB, not the earlier 128 MiB software-only ceiling. It remains
byte-pinned. Runtime/input read bytes are part of later admission pricing, not
additional output permission. Only one currently mapped SSSD cache was present
in that particular snapshot; late appearance of another permitted cache is
recorded rather than treated as altered numerical software.

The OS must enforce finite CPU, address-space and file-size limits. Exact
native timeout arguments and executable are verified, as are process groups:
R's PGID and session must match the timeout ancestor and timeout must lead its
own process group. Foreground or `setsid` escape cannot satisfy the guard.
Both R and its exact timeout supervisor must have affinity restricted to CPU
27; place `taskset` outside the timeout, not only around its R child.

| Actor | CPU | TERM / KILL wall bound | Address space | Output | CPU/thread |
|---|---:|---:|---:|---:|---:|
| Trusted preparation | 120 s | 119 s + 1 s | 2 GiB | 64 MiB | 27 / 1 |
| One-unit qualification | 1,800 s | 1,799 s + 1 s | 16 GiB | 256 MiB | 27 / 1 |

These are exact prospective limits, not permission to occupy CPU 27 now. The
coordinator must first verify fresh resources, approve each external purpose
and install the corresponding OS limits and whole-process timeout. Output and
prepared-input bytes are reserved together; RDS serialization is sized before
writing. Scientific workers, full campaigns and other hosts are not authorized.
The new walls are prospectively tighter than the historical limits. This is
deliberate: per-process `RLIMIT_CPU` alone is not aggregate parent/child CPU
enforcement. One CPU for the complete timeout process group and a 120/1,800-
second wall also bounds that payload group's aggregate CPU. The coordinator's
separate setup/supervisor administration is accounted separately; final
self-plus-child CPU remains an additional readback, not the sole enforcement.
Historical Q2/precision scripts and their old purposes remain unchanged.

## Historical evidence is historical

The driver authenticates the original v1 contract, receipt and nine-entry
artifact inventory, retaining their fixed digests and numerical REVIEW. All
nine historical artifacts are hash-checked but not deserialized or copied.
The archived batch source is authenticated from Git commit
`a099aba928e6d1fb01931a4b12466125bbb2bc64`, tree
`48b8baa236859f9f32969593101c75ff45bfa88c`. Its batch-helper digest is
`f87fa0deefedd0fc155645bc5977625798b7065512a429b58f536e2875387698`.

The old-to-new bridge verifies each recorded old source blob. All old source
bytes must remain unchanged except the explicitly reviewed batch helper. The
new array helper, driver, preparer and guards are additional pinned sources.
Checkout-path relocation of an otherwise byte-identical native manifest is
allowed; historical identities and old output statuses are not rewritten.
The original Q2 contract also records Jerez input locations, whereas the
authenticated v1 experiment uses Muscat materializations of those six assets.
`mqa_original_unit_bridge()` compares every nonasset unit field exactly and
requires the same six roles, positive integer sizes and SHA-256 digests. Only
absolute canonical path relocation is permitted; old-host paths need not exist
locally, and every actual materialized path must be canonical/nonsymlink and
rehash through `q2_metadata()` before a payload read. Both actors use that same
gate. The old-to-materialized mapping is recorded in the derivation and final
qualification receipt and checked before the reduced RDS is opened. Original
contract bytes, targets, feature definitions, rows, clocks and thresholds are
not rewritten, and a digest/size/role change is never a path bridge.
The archived old batch is evaluated in an isolated environment over the
unchanged native closure, allowing actual three-way scalar/old-batch/new-array
path parity. Old success or REVIEW never becomes new-source qualification.

## Exact prepared-input interface

A successful trusted preparation writes a fresh private external directory
directly under
`~/.local/state/qdesn_forecast_transition/mq_array_prefix_preparation_<unique>`:

```
observed_prefix_payload.rds
derivation.json
input_manifest.csv
```

The manifest has exactly `relative_path,size_bytes,sha256,role` columns and two
rows, with roles `truth_free_original_observed_prefix` and
`authenticated_prefix_derivation`. Failed or extra files cannot masquerade as
a valid prepared bundle. Failure receipts are retained in their failed output
directory; they are not cleaned or reused.

The RDS contains exactly `{design, posterior, origins, mapping}`. Its design
contains the original pure-DESN reservoir, scaling and permitted DGP clock
fields; `Z` and row metadata stop at 11,000; future map entries contain only
origin/horizon/time indices. The sole origin contains exactly 11,000 observed
responses and horizon 30. The sole posterior row is original chain 1, draw 1,
with 140 slopes and seven intercepts. All seven levels retain that same
correlated native row. Mapping, input definitions and field order are hashed.
Callbacks, environments, opaque pointers and unknown response-bearing fields
are rejected; neither saved closures nor future builders are called.

The derivation binds all six original asset pins and original unit geometry,
each protected output-field hash, observed-prefix hash, prepared-payload size
and SHA, preparer commit/tree, reducer SHA and separate purpose SHA. It records
one design and one fixture deserialization honestly, zero future response-value
access, zero model/scoring calls and zero exported future responses. The
qualification checks these metadata, the committed preparer closure and the
actual preparation purpose **before** reading its prepared RDS; it then checks
all protected field hashes. A self-declared digest is not sufficient authority:
the coordinator separately reviews and pins the complete preparation purpose,
outputs and producer source.
JSON dictionary key order and integer-versus-decimal spelling are compared
semantically. Array order, scalar values, file hashes and every protected RDS
field hash remain exact; this does not relax feature or posterior-row ordering.

The pure preparation algebra is `mqa_reduce_original_payload()`; it does not
itself authorize any original read. `mqa_validate_reduced_objects()`,
`mqa_derivation_metadata()` and `mqa_validate_derivation()` expose the structural,
pre-read and fieldwise checks separately. The synthetic tests change all future
responses, future states and true-quantile columns while holding the observed
prefix fixed; the reduced output and protected-field digests are unchanged.

## Genuine numerical experiment

The original immutable unit remains scenario Asymmetric Laplace Tail, joint
AL/RHS, chain 1, row/draw 1, origin 1 at time 11,000, 20 slopes and seven levels
`0.05,0.10,0.25,0.50,0.75,0.90,0.95`. It is not a representative stress set or
an independent-product posterior qualification.

1. Before training, compare all 30 horizons for prescribed IDs
   `1,2,63,64,127,128,4095,4096,4097,8192,16384,32768,65535,65536` against both
   unchanged scalar and authenticated archived batch paths. Compare raw inputs,
   scaled inputs, readouts, raw/projected grids, uniforms and responses; retain
   the declared `1e-10` absolute-plus-relative parity thresholds and caller RNG.
2. Generate 65,536 training paths using the original scientific namespace and
   IDs, retaining arrays and compact raw-coherence counters. Invert matrices
   and compare all 30 full-mixture inversions with the native reference. The
   split criterion remains absolute OR relative difference at most `0.005`.
3. Persist training arrays, candidates, split diagnostics and a hash-bound
   `CANDIDATES_FROZEN.json` before any validation ID. A split REVIEW stops all
   validation, including validation-ID parity; it remains a complete recorded
   REVIEW, not a passing qualification.
4. Only after a passing split, check prescribed validation IDs 65,537 and
   327,680 against native/archived references. These parity probes are recorded
   in separate receipts and never alter candidates. The same scientific IDs
   also belong to the certificate range; these are not independent streams.
5. Stream CDF contributions disjoint from the training range, from IDs
   65,537–327,680 at fixed looks
   65,536, 131,072 and 262,144. Preserve the original `0.05/3` allocation at
   each look, `0.01` absolute-OR-relative quantile tolerance, frozen candidates
   and empirical-Bernstein endpoint inequalities. Stop only under the unchanged
   fixed-look rule. Retain Welford moments, block ranges/hashes and endpoint
   evidence, not a large raw validation matrix.
6. Recheck candidate commitments, all source/runtime/original-byte pins, the
   published source ref, process scope and cumulative CPU. Numerical failures,
   maximum-look REVIEW and thrown errors remain explicit and retained. No
   threshold, posterior row, coupling, seed, model or future response is selected.

This is an actual execution of new source, but a **computational source-
regression replay**, not a newly unseen statistical validation experiment.
The scientific namespace and path-ID recipe were already used in earlier
qualification work. Disjoint training/validation ranges within the frozen
recipe are preserved; repeated execution does not create new independent
evidence across experiments, nor expand the bound's one-unit scope.

Final compact stream states can be independently passed to the coordinator's
`iqr2_from_stream_state()` / `iqr2_validate()` after the final combined source
is frozen. This is an independent numerical readback, not production-consumer
qualification. Exact first-horizon structural evidence, if reported elsewhere,
cannot override a failing higher-horizon or all-endpoint gate.

## Contract fields and later execution order

Qualification contract fields include the scope/limits above; exact source
commit/tree, GitHub URL and publication ref; `source_manifest`, `source_files`,
`runtime_files`, `native_rng_source`; original unit/contract; fixed historical
baseline contract/receipt/manifest; prepared payload/derivation/manifest;
`prepared_source`, `prepared_purpose`; expiry; and fresh ignored `output_root`.
Preparer contracts use the distinct schema and limits, explicit prefix-only
permission/selector, original unit/contract and historical contract, the same
source/runtime pin machinery, expiry and fresh external state output. The guard
functions define exact executable requirements; this document is not a grant.

The coordinator must: review/merge/test/publish the source; obtain fresh resource
approval; issue and execute a separate finite preparation purpose; independently
verify its outputs/source/fieldwise receipt; then issue a new finite qualification
purpose. Do not manually invent a derivation, run the old CLI, repoint an old
grant, or call any metadata-only result QUALIFIED. Even a numerical PASS here
means only `PASS_NEW_SOURCE_ARRAY_ONE_UNIT_ONLY`; production B07, authentic
training-selected stress cases, other likelihoods/geometries/hosts, complete
inventory/storage/cost admission and all article publication gates remain open.

## Verification completed in this implementation

`application/tests/test_mq_array_qualification.R` uses generated parameter/schema
objects and a tiny temporary Git repository only. It checks scope and budget
mutations, raw-read prohibition, missing authenticated reduction, shifted
source/posterior/coupling fields, future-prefix invariance, callbacks, native CDF
atoms/ties, exact source closure/Git blob checks, dirty or missing source files,
symlinks, timeout arguments and process-group/session escapes. Actual native
default-timeout group/session proof was also checked in a bounded synthetic
invocation. No authentic archive, retained posterior, future truth, preparation
actor or qualification experiment was executed during development.

Final bounded guard-suite readback: **115 checks PASS**, 1.77 seconds elapsed,
1.49 user CPU seconds, 0.23 system CPU seconds, 98,500 KiB maximum RSS, R 4.6.0,
`--vanilla`, CPU 27 and one numerical thread, under a native 120-second timeout.
All four new R files parsed and `git diff --check` passed. Independent reviewers
also inspected the math and isolation/source bridge; these are source checks,
not an authentic numerical qualification receipt.
