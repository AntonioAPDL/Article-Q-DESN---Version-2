# Purpose-bound MQ native numerical backend

This addition supplies a numerical implementation for a separately authorized
one-unit source-regression qualification. It does not launch that qualification,
authorize a campaign, certify a C ABI in general, or change any canonical or
generated-only entry point. There are no model fits, scientific inputs, scores,
manuscript assets or publication changes in this addition.

## Interface and order

The guard/driver owns purpose, source, build, input, process, resource, expiry,
candidate-freeze and runtime authentication. The backend consumes those proofs:

1. `mqnk_enroll(build_manifest, enrollment_context)` accepts only the guard's
   `mq_native_runtime_enrollment_context_v1`, checked by
   `mqns_enrollment_context_check`. Its mode is
   `load_only_runtime_enrollment_v1`, with `runtime_verified = FALSE`. It may
   load the three explicitly pinned DLLs and verify their public registrations.
   Its locked `mq_native_load_only_v1` object is rejected by every numerical
   handle check. No forecast input is an argument of this step.
2. After the guard authenticates the actual loaded numerical runtime and every
   remaining gate, `mqnk_load(build_manifest, purpose_context)` accepts a
   `mq_native_replay_context_v1`. Its schema is
   `mq_native_purpose_context_v1`; its distinct mode is
   `native_source_regression_qualification_v1`. The guard's
   `mqns_context_check` must accept it. All three DLLs must already be uniquely
   loaded at their exact receipt paths. This constructor performs no new
   `dyn.load`.
3. `mqnk_arrays(handle, adapter, draw_id, origin_id, inner_ids, phase = ...)`
   returns the canonical compact arrays. `mqnk_paths_context` can additionally
   expose all generated paths and traces for a prospective parity check. Each
   invocation binds the original draw, origin, namespace, seven quantile levels
   and 30 horizons. The phase gate is `mqns_phase_check`.
4. `mqnk_inverse(handle, q, tau, probabilities)` keeps inversion tolerance
   exactly `1e-8`. `mqnk_cdf_values(handle, y, q, tau)` returns **one conditional
   CDF value per path and endpoint**, not an averaged CDF. The latter public
   endpoint API requires a sealed validation context. The internal CDF checker
   used by training inversion does not expose or use validation paths.

Public numerical entries authenticate the handle before forcing numerical
input promises. Their subordinate projection/CDF arithmetic rejects load-only
objects but does not independently repeat every source/build JSON check at
each horizon or endpoint. It is not an alternative admission API. In
particular the public CDF entry performs one full check, rather than two
identical receipt parses for the same call; the inverse already performs its
own full entry check before its internal CDF probes.

An authentic training context allows paths 1–65,536 and the guard's training
parity sentinels. Only after freezing all training candidates and passing the
existing split check may the guard return a new, separately sealed validation
context for paths 65,537–327,680 and its validation parity sentinels. Construct a
new numerical handle with that context; do not mutate or promote an old one.
The numerical handle is a locked environment retaining its original context
and receipt hashes. The driver, not this backend, authenticates the prepared
parameter/design payload and supplies its exact adapter.

The parsed build receipt has schema `mq_native_retained_build_receipt_v1`,
native canonical `R_home` and `R_libdir`, source commit/tree, and named
`dlls$key`, `dlls$isotonic`, `dlls$inverse`. Each DLL record contains canonical
nonsymlink `path`, `size_bytes` (positive and at most 8 MiB), `sha256`, relative
`source_path`, and `source_sha256`. Attach attributes `receipt_path` and
`receipt_sha256` to the parsed object. The object must equal that pinned JSON
file after removing these attributes. The guard also checks its complete
compiler/SDK/runtime/source closure; a numerical wrapper's registration check
does not replace those checks.

## Unchanged calculation

The C sources and their existing generated-only R wrappers are unchanged.
The new wrapper calls the already registered public `.Call` entries directly:

| Component | Public entry | Arguments |
|---|---|---:|
| Original key serialization/SHA/first CMRG draw | `mq_key_hash_batch` | 4 |
| Conditional equal-weight native isotonic projection | `mqi_project` | 1 |
| First generalized-inverse event index | `mqe_first_indices` | 2 |
| Individual ordered-grid conditional CDFs | `mqe_cdf_values` | 3 |

The canonical forward body is compared with the pinned parsed source. Restoring
only the declared uniform producer and matrix projection, and removing the
one entry guard, must reproduce its complete original formals/body. The proof
checks complete calls and arguments, not merely function names. Reservoir
scaling, layer/state updates, readout construction, recursive response feedback,
original IDs, and coherence accounting therefore retain their canonical R
expressions. Canonical functions and their environments are never replaced.

The inverse retains original event construction/order, `sort`, `rowsum`, both
R `cumsum` operations, scalar interpolation, R `mean` of individual CDF values,
and checked fallback on the original unprojected endpoints. In particular, C
does **not** replace R's extended-precision reductions with double sums or
`colMeans`. Endpoint atoms, ties, plateaus, and strict-lower/inclusive-upper
generalized-inverse checks retain the existing interpretation. The seven-level
weights, coupling, streams, path partitions, retention, tolerances and separate
integrated quantiles for each parameter draw are not changed.

The isotonic component remains the attributed GPL-2-or-later adaptation already
documented with its retained license. No new native code, private R ABI,
compiled method, compiler option or license exception is introduced here.

## Synthetic tests versus authentic qualification

`mqnk_load_synthetic` is a **separate** test constructor. It requires the class
and schema `mq_native_synthetic_context_v1`, mode
`synthetic_backend_contract_test_v1`, the fixed toy fixture namespace, and
false external/runtime authorization. It is never accepted by `mqnk_load`.
Its numerical outputs remain nonproduction; they are not authentic inputs
mislabelled as `generated_fixture_only`.

The generated test builds the unchanged three C files with native R 4.6.0,
GCC, `-fno-fast-math`, `-ffp-contract=off` and an explicit native-libR rpath.
It checks D=1/2/3, both toy posterior draws, K=7 and H=30: complete raw inputs,
scaling, every reservoir state, readouts, raw/projected quantiles, uniforms,
responses, paths and coherence counters. It compares identical partitions
exactly, checks uniform partition identity, training/validation ID boundaries,
RNG kind/state preservation, atoms/flats/crossings, inverse/CDF results and
mutated entry/uniform/projection bodies. It rejects missing purposes, changed
source/DLL metadata, a generated scope substituted for a genuine context,
invalid geometry, complex inputs and changed inversion tolerance.

These tests do not read authentic model/design/truth payloads, prove full-unit
speed or precision, qualify all posterior draws, or admit production. In
particular a source-regression replay in the same original namespace is not a
new independent scientific replication. Actual source-regression parity,
candidate/split/independent-CDF precision, numerical-runtime closure and final
supervisor accounting remain separate mandatory gates in the new driver.

All constructors keep `production_authorized`, `refit_authorized`,
`scoring_authorized`, `article_authorized` and `C_ABI_qualified` false. A
successful one-unit qualification cannot silently satisfy campaign inventory,
native weights, simultaneous campaign error accounting, cost or host grants.
