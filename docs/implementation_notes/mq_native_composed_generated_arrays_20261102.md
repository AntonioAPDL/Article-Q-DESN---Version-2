# Generated-only composition of three native candidates

This branch merges the three frozen additive candidates without rewriting
their history:

| Component | Frozen commit |
|---|---|
| Key serialization/SHA/uniforms | `0ba50f4367b423406b5df07cf8543b9fc45d0fa6` |
| Unweighted isotonic action | `13fe9ea77052358e883c87a6b30d70c321fc3292` |
| Event index / pointwise CDF | `f194f413ecff1f44552087ad8dcc142f6e1c38b1` |

The base is main `a55d10580d5e5d0f2ee773bd3fbeb1f7c5a438bd`.
All three merges use `--no-ff`. Existing application kernels, source guards,
workers, qualifiers, test registry, defaults and article files are unchanged.
Only a standalone composer, generated test and this note are added afterward.
No scientific object, data, posterior draw, future truth or RDS is read.

## Precisely bounded implementation change

`mqc_paths_context()` copies the numerical body of the frozen
`app_iqf_mqb_paths_context()` with only two numerical substitutions:

1. Its one path-ID × horizon uniform producer calls the explicit native
   key/serializer/SHA candidate with the unchanged namespace, original draw,
   origin and path IDs, and original first-step RNG proof.
2. Each horizon passes the complete B × K raw readout matrix to the batched
   native-equivalent isotonic candidate once. There are no per-row R
   projections inside the copied recursion.

The raw lag construction, scaling, layer state updates, projections, readout,
feedback, response inverse, coherence updates, counters, traces, ordering and
original IDs are otherwise unchanged. No posterior coefficients or future
features are averaged. Each parameter draw has its **own** recursive paths
and integrated distribution; draws are not pooled to substitute another target.

The source guard pins the nine canonical/candidate source files. It compares
the actual canonical body's deparse and formals with its pinned parsed source,
including under JIT compilation. A structural restoration verifies exact
entry-guard and replacement-call arguments before restoring the two original
expressions and comparing the rest of the function. Tests reject changed
namespace, path IDs, projection input `mu * 0`, entry guard and formals. No
global/environment monkey-patch or default replacement is used.

`mqc_load()` requires all three explicit compiled DLL paths and SHA-256 pins.
One nonauthorizing handle supplies the key, isotonic and inverse/CDF APIs.
`mqc_arrays()`, `mqc_inverse()` and `mqc_cdf()` require explicit
`generated_fixture_only` scope. The inverse uses the unchanged frozen
event/CDF candidate: R retains event preparation, sorting/grouping, cumulative
arithmetic, interpolation, scalar clamps, final means and checked original-
grid bisection fallback. The registered C entries do not call private R APIs.

The flags `production_authorized`, `source_runtime_authenticated` and
`C_ABI_qualified` remain false. File hashes and observed loaded libraries are
test evidence, not independently authenticated worker/host admission.

## Complete controlled generated verification

`application/tests/test_mq_native_composed_arrays.R` compiles the three
unchanged C sources in one fresh temporary directory. It uses R 4.6.0,
digest 0.6.39, `/usr/bin/gcc` 8.5.0, controlled user/site Makevars, `-O2`,
`-fno-fast-math`, `-ffp-contract=off`, and an explicit native-R library rpath.
There is one numerical thread and no new BLAS, Rcpp or package installation.

The final complete build/test passed **465 checks**. It records and rechecks
all 18 sourced/test/module/C source files, all three actual DLL hashes,
compiler commands, actual `getLoadedDLLs()` and `/proc/self/maps` output.
The test requires exactly the expected native `libR.so` mapping, checks the
actual libcrypto and candidate mappings, and rejects missing/deleted selected
code mappings rather than silently discarding them. Observed code identities:

| Code | SHA-256 |
|---|---|
| Key DLL | `0ef50ac7f0047a3a53d933a3bc85b52eba70a3118051a372a69be485d46942a5` |
| Isotonic DLL | `ac70aca7eab05a27a38bcf49c5539be166a463a967195983f5914c1c30d9f73d` |
| Inverse DLL | `f1b7af006024907a0855a987b7ab051b8410be5c971ddc5152653a075441bef7` |
| Native R `libR.so` | `e56b819647d3d68a53fb8ea0d9b9d363a25e9e7f2a677f4b02eb003f01579558` |
| Loaded `libcrypto.so.1.1.1k` | `5409cd3605c1c45754ce325e14b1823100b85b7f646e5511f5f5d2855b7abc3d` |

The generated checks cover D=1/2/3, identity/tanh/ReLU activation, transformed
lower layers, input standardization choices, both original parameter draws,
30 horizons, all seven probability levels, raw and ordered readouts, states,
responses, complete traces, coherence/counters and RNG state. Each identical
ID partition matches its corresponding unchanged reference bit for bit.
Original uniform tuples also match across partitions. This does not assert
universal bitwise magnitude invariance across *different* BLAS/reduction
partitions; no existing cross-partition numerical tolerance is tightened or
relaxed by this candidate.

The final allocation used logical CPU30, 120 CPU seconds, TERM at 119 wall
seconds plus one-second KILL, 2 GiB address space and 64 MiB per-file and
checked aggregate build/receipt output. The complete build/test took
**15.76 wall seconds**, 15.14 user + 0.50 system CPU seconds and
**188,468 KiB** peak RSS. There was no fit or scientific launch.

An earlier generated attempt passed 459 checks (15.78 wall seconds). It
preceded the additional source/mapping/negative-test receipt checks and is
retained separately, not relabelled as final verification. Its original
receipt pinned nine immutable kernel sources but did not contemporaneously
hash the newly written test/module. An explicitly labelled historical test
snapshot was reconstructed by reversing the subsequent known patch; the
module itself was unchanged. Final verification records complete source
bindings before and after execution and does not rely on that reconstruction.

## Generated timing, not an authentic speed claim

One fixed B=1,024, H=30 generated staged-kernel example used actual 128-ID
partitions, a single declared parameter draw, disjoint training IDs 1–1,024
and validation IDs 1,025–2,048. Reference and composed training arrays,
integrated quantiles and validation CDF values were bitwise identical.

| Generated stage | Reference wall seconds | Composed wall seconds |
|---|---:|---:|
| Training paths | 3.792 | 0.590 |
| Seven-level inversion | 0.363 | 0.231 |
| Validation paths | 4.058 | 0.427 |
| Validation CDF | 0.115 | 0.020 |
| Whole staged kernel | 8.334 | 1.272 |

This is one small generated design, not an authentic model, full posterior
campaign, uncertainty estimate, total workflow forecast, or host admission.
In particular, it does not establish a 20–37-fold full-unit gain. Real event
sorting, full reservoir costs, validation precision, output and scheduling
costs remain to be measured prospectively under a separately authorized
qualification. All retained receipts are ignored metadata, not article assets.

## Remaining integration and qualification gates

The coordinator owns shared test-registry changes and combined repository
tests. No full-suite pass is claimed for this composer yet. Before authentic
qualification, freeze the complete new source/compiler/SDK/runtime closure,
explicit resource/read purpose, exact native parameter measure and weights,
coupling, retention, production confidence/score precision and campaign cost
policy. Existing accepted native evidence cannot silently qualify this new
source. No production purpose, qualifier change, worker default, scientific
execution, article update, remote push or publication is authorized here.
