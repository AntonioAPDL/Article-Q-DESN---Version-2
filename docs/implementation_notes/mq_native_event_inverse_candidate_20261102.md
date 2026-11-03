# MQ event/inverse candidate: generated checks only

This additive candidate preserves the per-parameter-draw integrated-quantile
target. It changes no canonical function, default backend, posterior measure,
probability grid, response law, numerical tolerance, stopping rule or source
guard. It is not a production worker or an authentic-model qualification.

## Deliberately limited native work

`scripts/mq_native_event_inverse.R` supplies the explicitly named
`mqe_inverse()` route. It requires an explicit generated-only scope and an
already-built, SHA-pinned DLL loaded by `mqe_load()`. Compilation, data
discovery, model loading and scientific launch are not provided.

The canonical `app_iqf_mq_matrix_inverse()` remains the reference. The new
route retains its input validation, conditional native isotonic projection,
event construction and event order, `sort(unique(...))`, `match`, `rowsum`,
both R `cumsum()` calls, interval-mass checks and clipping. These operations
are not reimplemented with a different reduction or grouped summation order.
In particular, official R 4.6.0 `src/main/cum.c` accumulates `cumsum()` in
`LDOUBLE`; a new sequential-double C sum would not be byte-equivalent.

The C helper performs only two narrowly specified operations:

- Find the first index satisfying `right >= p` for each requested probability.
  It preserves unsorted and repeated requests and the first generalized inverse
  at atoms and plateaus. R still performs the original interpolation and
  scalar `max/min` clamp, including signed-zero/exceptional-value behavior.
- Evaluate each ordered row's existing piecewise-linear/endpoint-atom CDF at
  the candidate-check points. The binary64 expression order is unchanged.
  R still calls `mean()` on the resulting individual-value vectors, retaining
  its extended-precision accumulation and correction. Neither `colMeans()`
  nor a new double accumulator is substituted.

The native entry points use only the public R extension API, own registered
symbols and disabled dynamic symbol lookup. There are no private R functions,
internal stats symbols, Rcpp assumptions or new third-party implementations.
The original implementation is MIT licensed (permission below). No R source
implementation is copied into the C helper.

## Checks and fallback

The unchanged R CDF bracketing check at `answer ± tolerance` remains mandatory.
`mqe_inverse()` calls the original checked bisection on nonfinite events,
invalid accumulated mass, unresolved inverse or failed probes. It retains
the **unprojected original endpoints** when constructing that fallback's
initial bracket. It does not renormalize a defective CDF, smooth atoms, sort
instead of project, relax precision, or return an unchecked answer.

The explicit `unchanged_reference` CDF option uses the original R CDF checker.
The default within this explicitly selected candidate uses native individual
CDF values followed by the unchanged R mean. If the native temporary-value
matrix would exceed its declared 64 MiB bound, the original R CDF checker
is used. The original R checker also handles an infinite query caused by
overflow under a nondefault huge tolerance; the candidate does not invent a
different failure there. An optional generated receipt reports the quantiles and whether
checked bisection was used. Its source-authentication and production flags
are always false; it is not a numerical-confidence certificate.

The reference DLL loader admits only a canonical nonsymlink absolute path,
size under 8 MiB, matching before/after SHA and registered two-/three-argument
entries. The C functions independently check their types/dimensions before
dereferencing. The R interface accepts real integer/double inputs only;
complex values are rejected before coercion rather than dropping imaginary
components. No compiled library belongs in Git.

## Generated experiment

The standalone test uses one controlled temporary build with the existing
GCC/R toolchain, user/site Makevars explicitly controlled and
`-O2 -fno-fast-math -ffp-contract=off`. Generated checks compare exact binary64
values, not merely a relaxed tolerance. They include endpoint and interior
atoms, ties, flat pieces, separated supports/plateaus, tiny/subnormal values,
named/repeated/unsorted probabilities, K=2/7/16, original-input preservation,
registered-symbol/type failures, and 30 horizons separately for each of two
generated parameter-draw paths. No fit, posterior, future truth or authentic
fixture is read. The native pointwise-CDF means are compared with the unchanged
R CDF function, and the original bisection fallback is exercised explicitly.

The first bounded attempt compiled cleanly but stopped at a test dependency
visibility check before numerical comparisons. Its 0.48-second failure receipt
is retained in ignored local trackers. The test now loads reference helper
definitions with the same global visibility used by the canonical standalone
tests; no numerical algorithm was changed to pass it.

A separately authorized second generated-only attempt passed **218 checks**,
using 2.23 wall seconds, 1.66 user + 0.15 system CPU seconds and 127,432 KiB
peak RSS on logical CPU29. It was bounded by 120 CPU seconds, a 119-second
TERM deadline plus one-second KILL, 2 GiB address space and 64 MiB aggregate
retained output. Sources and caller RNG state were unchanged.

Final review then corrected dispatch of nonfinite query points under a
nondefault enormous tolerance to the original R CDF checker. The C source
and DLL were unchanged. A separately authorized existing-DLL-only check
passed seven comparisons/assertions on this patched R source (huge-tolerance,
unchanged default and subnormal-fallback branches), in 0.78 wall / 0.77 CPU
seconds and 73,652 KiB RSS. Both receipts and exact source/DLL hashes are
retained. The prepatch 218-check receipt is not relabelled as a full retest
of the final source; the coordinator's combined-source test must rerun the
standalone test, including its newly added overflow-query case.

Independent review also added explicit real-type guards before coercion.
A final existing-DLL-only five-check guard/default-parity test passed on
that source in 0.65 wall / 0.64 CPU seconds and 73,620 KiB RSS. It does not
replace the pending final-source full standalone/combined test; all preceding
receipts retain their original source hashes and scope.

One N=8,192/K=7 generated inverse timing was 0.137 CPU seconds for the
reference and 0.117 for the candidate. This single small timing is not an
authentic-stratum benchmark, uncertainty estimate, full-unit speedup, campaign
ETA or resource admission. Event sorting/grouping and other R work remain.
No 20–37-fold full-unit gain is established by these or the other hot-loop
candidate tests.

## Remaining gates

The coordinator must compose only explicitly selected frozen candidate APIs,
rerun generated whole-path and mutation tests, and independently pin the
combined source, compiler flags, actual loaded native-R/shared-library mappings
and runtime. A separately authorized representative authentic qualification
must compare every path/grid, integrated quantile and numerical bound under
finite resource limits. Existing accepted MQ evidence must not be relabelled
as qualification of this new source. Native inventory/weights/coupling,
campaign confidence, score precision, retention and full cost/host admission
remain separate unresolved production gates.

## MIT permission for the original candidate files

Copyright (c) 2026 Q-DESN contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to
do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
