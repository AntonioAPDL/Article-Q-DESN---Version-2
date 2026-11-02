# Source-bound ancestor-first AL qualification driver

## Purpose and boundary

`scripts/qualify_ind_adapted_filter.R` is an executable driver for one new,
separately admitted training-only numerical purpose. Its existence and
synthetic guard tests are not an authentic qualification. It cannot fit,
score future responses, authorize production or promote the article.

The driver uses the same original AL native column as the historical guided
diagnostic, but an explicitly different ancestor-first algorithm and stream
layout. The historical 13/27 REVIEW receipt is pinned and retained. A new
agreement result does not overwrite it or certify the full conditional filter.
Even all 27 descriptive agreements would not establish accuracy for other
parameters, exAL, later evaluation origins or all forecast horizons.

## Immutable scientific scope

The external contract schema is
`ind_ancestor_first_filter_qualification_v1`. It fixes:

- method `ancestor_first_AL_exact_v_v1`;
- RNG namespace `ind_ancestor_first_AL_training_H1_v1` and layout
  `Mersenne_Twister_time_major_proposal4_then_ancestor_then_residual_v1`;
- native posterior column 1, 500 training observations and six states;
- particle resolutions 64, 256 and 1024, seeds 71521 and 71522;
- checkpoints 100, 250 and 500; diagnostic probabilities .05, .50 and .95;
- ESS fraction .5, inversion width tolerance 1e-8 and the unchanged
  .005 absolute-OR-relative agreement criterion.

For each seed, all resolutions use prefixes of one 1024-by-500-by-four
proposal array. Ancestor and residual-resampling innovations have separate
time streams. These new streams are retained under the new purpose's
namespace, not relabelled as the old method's execution. Caller RNG state
and kind are restored even on error.

The genuine numerical loop runs all six filters, forms exact terminal
Normal--AL H1 CDF mixtures from their weighted checkpoints, inverts those
mixtures, and evaluates the original 27 predeclared within/between-seed
agreements. The 100/250 checkpoints are training diagnostics at a parameter
learned using all 500 observations, not out-of-sample forecasts. The endpoint
H1 diagnostic additionally requires constant F/G across the authenticated
training design. No response after observation 500 is loaded.

## Truth-free inputs and original proof chain

The only scientific `readRDS` is the already authenticated 13,728-byte
`training_only_input.rds`, SHA
`d38bd5f49744c67861908f8fd960781bf97efdf1c43473829b46894574252496`.
Its exact field set is `y,FF,GG,m0,C0,ex_f,ex_q,df_mat,observed_prefix_length`.
The driver accepts a constant 6-by-6 G or a verified constant 500-slice
array. An extra full-fixture/future-truth field is rejected. It never
deserializes the original 611,287,756-byte fitted object; that file is
hashed only before and after execution.

The contract also pins and cross-checks the original native forward receipt
and manifest, bootstrap receipt, historical guided receipt and native C++
source. These prove the same source/fit/column/scale identity. The paired
conditional offsets in the redacted input must agree with the original
AL probability/scale convention. A missing authentic redacted input or
changed proof blocks execution; no new full-fixture reducer or fallback is
silently invoked.

## External contract and complete source/runtime binding

Required administrative fields are `source_commit`, `source_tree`,
`expires_utc`, `output_root`, `source_files`, `runtime_manifest`, and the
fixed scientific/limit fields above. The purpose contract must be outside
the checkout, at most 512 KiB, and supplied with its exact SHA through
`--contract FILE --sha256 SHA --execute`. It explicitly sets
`allow_qualification=true` and refit/production/scoring/article-promotion
flags false.

Every file pin has exactly `path`, `size_bytes`, `sha256`. Source files are
the following exact seven current-checkout paths (the last is a checked
historical reference, not a sourced execution dependency):

```
scripts/qualify_ind_adapted_filter.R
scripts/ind_adapted_auxiliary_filter.R
scripts/ind_guided_auxiliary_filter.R
scripts/ind_guided_auxiliary_primitives.R
scripts/ind_conditional_auxiliary_filter.R
scripts/ind_conditional_filter_replay.R
scripts/qualify_ind_guided_filter.R
```

Input/proof pin fields are `training_input`, `original_fit`, `native_cpp`,
`native_forward_receipt`, `native_forward_manifest`, `bootstrap_receipt`,
and `historical_guided_receipt`. The driver freezes known original hashes
rather than accepting a new numerical case with the same administrative
role. All are rehashed after the calculation; source commit/tree and clean
checkout are rechecked without optional Git index writes.

The CSV `runtime_manifest` has exactly `path,size_bytes,sha256`, sorted by
canonical path. `ind_aq_runtime_inventory()` produces its metadata from
all installed files in base/compiler/datasets/graphics/grDevices/methods/
stats/utils/tools/digest/jsonlite, all mapped runtime file paths, the actual
R interpreter, Rscript, Git and the native timeout executable. Duplicate
canonical paths are collapsed.
The actual inventory is independently rebuilt and compared before and after
the numerical phase. It is a source/runtime metadata preparation helper,
not a model qualification or source of scientific draws. The parent must
create and review this manifest under its own bounded preparation scope.

The process must be native Muscat R 4.6.0 launched with `--vanilla`, bundled
R BLAS, exactly one core library path, explicit `R_LIBS_USER=/dev/null` and
`R_LIBS_SITE=/dev/null`, empty LD_PRELOAD, and OMP/OpenBLAS/MKL thread counts
one. No installed exdqlm namespace or unlisted loaded package is allowed.

## Finite resource admission, not a reusable grant

The prospective contract price is 1800 CPU seconds, native timeout TERM at
1799 seconds and KILL after one second, 16 GiB address space and 96 MiB
total packet budget. CPU26 and its SMT sibling require fresh ownership
review. These limits are checked from actual OS limits and the actual
`/usr/bin/timeout` ancestor. That ancestor must itself be confined to CPU26;
the single-CPU wall boundary bounds aggregate payload-process CPU even
when child utilities run. External supervisor preparation and final resource
accounting remain separately required.

In particular, `taskset -c 26` belongs outside the native timeout so the
supervisor itself inherits that affinity. The coordinator must construct
and review the complete prlimit/timeout/environment command; the driver
does not schedule or grant itself a core. No command in this document
constitutes actual numerical admission.

The packet includes two supplied-stream arrays, six filter/checkpoint/
diagnostic artifacts, H1 values, all agreement rows, progress/failure/terminal
receipts and a byte/hash manifest. Their uncompressed content is expected
to be comfortably below the 92-MiB payload allowance; compression is lossless.
Four MiB is reserved for the external contract, runtime inventory and
administrative/log records. Aggregate regular-file bytes and manifest are
checked, including hidden entries. No automatic larger-N retry or budget
renewal is implemented. Parent accounting must preserve actual exit and
resource usage, including interrupted or failed purposes.

Process CPU/wall measurements before terminal serialization are labelled
as such; no self-written receipt pretends to contain its own final writing
or external supervisor cost. A separately rehashed terminal accounting
receipt closes that boundary.

## Results and remaining qualification

A completed purpose reports
`BOUNDED_AL_TRAINING_DIAGNOSTIC_COMPLETE_FILTER_ACCURACY_NOT_CERTIFIED`.
Its agreement status is either REVIEW or
`PASS_DESCRIPTIVE_AGREEMENT_ONLY`; filter/future/full-IF01/production/article
flags remain false. The driver preserves lookahead ancestry concentration
even when adapted child weights are uniform.

The source-only test
`application/tests/test_ind_adapted_qualification_guards.R` checks scope,
fixed hashes/geometry, runtime metadata equality, exact timeout arguments,
truth-free input schemas, constant F/G, source/scale compatibility and early
negative admission without authentic inputs or scientific execution.
It is not the genuine numerical purpose described above.

Actual execution still requires independently reviewed source publication,
runtime manifest, original inputs/proofs, output price, physical ownership,
external purpose hash and fresh finite admission. The approved reconstruction
and broad campaign remain blocked until representative AL/exAL/source/
parameter and all-horizon accuracy, complete inventory, production wiring,
cost and host gates pass. No result or article replacement follows merely
from compiling this driver or passing its guard tests.
