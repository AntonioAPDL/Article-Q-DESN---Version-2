# Opt-in batched isotonic projection candidate

This source-only candidate batches the unchanged, **unweighted** rowwise
isotonic action. It is not a worker implementation, native-source
qualification, host authorization, campaign launch, or article change. No
canonical source, projection default, posterior inventory, coupling, precision
rule, RNG mapping, or scoring target changes. There is no parameter-draw
pooling: projection acts separately on each supplied path-specific grid.

## Numerical and license provenance

The reference is the official local R 4.6.0 source
`src/library/stats/src/isoreg.c`, SHA-256
`76b143e6ad7b6ab53493115c839b539eef76f4d406633364e76d10629762c241`.
Its R wrapper `src/library/stats/R/isoreg.R` has SHA-256
`5c80925079017d937d3029b5a3495f632cf4aad0817e1a3dca193a8cb4f5dfea`.
The complete accompanying manual `src/library/stats/man/isoreg.Rd` was read.

The native routine computes the convex minorant of sequential double
cumulative sums. It selects the earliest endpoint with the strict `<`
minimum-slope scan and recomputes each output slope from those cumulative
sums. This can differ in floating-point arithmetic from a block-mean PAVA
implementation, although both describe unweighted isotonic least squares
mathematically. The candidate adapts the actual native arithmetic; it neither
sorts the values nor uses quantile-spacing/scoring weights.

`scripts/native/mq_isoreg_batch.c` retains the Brian Ripley, R Core Team and
R Foundation notices and is licensed **GPL version 2 or later**. The verbatim
GPL-2 text in `scripts/licenses/mq_isoreg_GPL-2.txt` matches the R source
COPYING SHA-256
`e6d6a009505e345fe949e1310334fcb0747f28dae2856759de102ab66b722cb4`.
These notices apply to this adapted module; they do not purport to relicense
the entire repository.

## Canonical action and native interface

The unchanged `app_iqf_grid()` first checks whether a row crosses. An already
ordered finite row is returned without calling `stats::isoreg()`. The candidate
preserves those input bits, including signed zeros, **before** computing any
cumulative sum. Consequently an ordered row can remain valid even when its
hypothetical sum overflows. A crossed row with a nonfinite total is rejected
as in native `isoreg()`. Nonfinite entries are always rejected. A nonprogress
guard rejects an unresolved cumulative segment instead of hanging.
That conservative failure guard does not assert identical behavior for every
pathological native failure; it never substitutes a different projected value.

The standalone `.Call` entry uses only public R APIs and is explicitly
registered with dynamic symbols disabled and symbol-object calls required.
Its C entry independently checks a real matrix, dimensions and finite values
before numeric use. The temporary candidate supports 1–1,000,000 rows and
2–64 levels; these are finite prototype bounds, not a production storage or
resource contract. Output is a new matrix with the same dimensions/dimnames;
the input is not modified. No private `stats` symbol or ABI is called.

`scripts/mq_isoreg_batch.R` requires an explicit bounded, hash-pinned compiled
DLL and `generated_fixture_only` scope. Sourcing the R file neither compiles
nor loads anything. No library is installed and no canonical caller uses this
entry. Actual native ABI/source/runtime qualification remains a separate
later gate even when this generated test passes.

## Generated build and checks

The standalone test builds the C source in a fresh R temporary directory
using the installed R 4.6.0 SDK. A controlled temporary user Makevars and
`R_MAKEVARS_SITE=/dev/null` exclude unknown user/site compiler flags. Both
`-fno-fast-math` and `-ffp-contract=off` are explicit. The observed compiler is
GCC 8.5.0 (`Red Hat 8.5.0-28`), with `-O2`. No Rcpp, external BLAS, package
installation, scientific object, or retained data is used.

`application/tests/test_mq_isoreg_batch.R` passes **49 generated checks**:

- Bitwise (`num.eq=FALSE`) parity with the conditional native action for
  ordered/crossed rows, ties/flats, signed zeros, adjacent-ULP changes,
  subnormal/tiny/large values, offsets, cancellation, and K=2, 7 and 16.
- Integer-wrapper conversion, single-row batches, unchanged input bytes,
  dimensions/dimnames, direct-C type/shape guards, and forbidden string-symbol
  invocation.
- Nonfinite-value and crossed-row overflow rejection; ordered-row overflow
  bypass; absent-scope and incorrect-DLL-pin rejection.
- Bitwise generated recursive-path parity through 30 horizons, computed
  separately for two parameter-draw fixtures and sixteen paths each. No
  existing function is replaced or monkey-patched, and no draws are pooled.
- Unchanged canonical source hashes and unchanged global RNG state.

One complete temporary build/test used one thread on CPU 30 with total
119-second TERM / 120-second KILL, 120 CPU-second, 2 GiB address-space and
64 MiB per-file limits. The passing run used 1.06 user + 0.16 system CPU
seconds, 1.23 wall seconds and 76,744 KiB peak RSS. An earlier 0.58-second
development run exposed an R `DLLInfo` `$` accessor error; using `[[` for its
metadata corrected it. Both bounded receipts remain ignored. No numerical
equivalence failure was hidden or repaired by changing a tolerance.

These checks establish parity on the generated corpus in this compiler/R
environment, not every compiler/ABI or an authentic unit. The temporary DLL
hash was `dc8df7361c152ab680974d808352e905b447cf86eeda74a90f2d728d8366d14a`.
This is a recorded test build, not a reusable execution grant or production
binary pin. The tests measure correctness, not full-unit speedup; no campaign
speed or resource claim follows from them.

Future work, if separately authorized, can wire a distinct opt-in array
variant and qualify its exact source/compiler/runtime against a frozen native
unit. It must preserve parameter-draw-specific integrated quantiles, source
and stream identities, raw crossing evidence, numerical precision, scoring
and cumulative resource gates. Default switching or actual reconstruction is
not authorized by this candidate. The shared test registry is left to the
integration coordinator; no full repository suite or manuscript build is
claimed here.
