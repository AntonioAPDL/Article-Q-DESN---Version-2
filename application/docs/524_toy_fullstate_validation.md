# Staged full-state consumer and bounded toy validation

Three diagnostic states reproduce all original recorded scalars exactly, but
none is repaired. The half-order objective rewrite does not repair any of them;
the same-state mean equilibration cannot repair NO3 or AT predictor failures.
These results do not establish a universal cause or prove that continuation
would certify. All 29 known dependants remain blocked.

The concrete, independently inspectable problem is that stock initialization
accepts only beta/sigma and discards covariance, RHS and latent factors. It also
interprets sigma0 differently from the retained E[sigma]. This justifies a
staged **toy-only consumer validation**, not a production continuation attempt.

## Consumer scope and equations

The new R module requires synthetic origin and n<=128, p<=32. Production target
dimensions are rejected. A private function clone inherits the original CRAN
namespace, adds an authority/dimension gate and factor import before the loop,
and keeps all original update/objective/stopping/sampling AST expressions. It
does not mutate the installed namespace, package files or frozen 522/523 trees.
Source-only factory inspection confirms removal of the two added blocks
recovers the exact original AST. No optimizer was run for that inspection.

The import preserves m,V, RHS shapes/rates/moments/schedule context, q(v) and
q(sigma). It resets the new outer optimizer's iteration, stability, formal flag
and trace through the original initializer. RHS internal schedule counters are
retained and labeled separately from AL iteration counts; freeze controls are
required to be zero. No recovered original optimizer state is claimed.

For q(sigma), the saved mean is b/(a-1). A compact reconstruction would require
b=(a-1)*sigma; stock beta/sigma warm-start initialization instead uses b=a*sigma0.
Variational rates are not prior rates: the sigma prior stays IG(1,1), coefficient
prior center stays zero, prior V0 stays diag(1e6), and normalized RHS controls
must match exactly. Imported inherited convergence flags are rejected.

Crucially, stock updates q(v) before q(sigma). Its final latent chi/psi generally
reflect the previous sigma precision. A checkpoint validator must test the
moments against their own stored GIG parameters, not recompute latents from the
current sigma. The explicit-factor objective uses those imported ell/nu/Elog-v,
their GIG entropy, current sigma shape/rate, full coefficient covariance and the
original prior closure with all constants. It is distinct from r129's conditional
latent reconstruction. The new module implements this distinction explicitly.

The independent one-block map separately forms the Gaussian system, uses
triangular solves, updates RHS, then GIG latents with old sigma precision, then
sigma, then evaluates the explicit-factor objective. The original prior closure
is a shared boundary and is not advertised as an independent prior oracle.

## Exact proposed experiment

There are eight semantic cases and **eight actual optimizer invocations total**:
three stock/project default-path pairs consume six runs of four sweeps; one
imported-factor run consumes one sweep; one stock uninterrupted reference uses
five sweeps. Total requested sweeps across the entire experiment are 30, with
at most five per invocation. This is stricter than the requested per-run cap30.

| Case | Proof | Optimizer invocations |
|---|---|---:|
| 1 | n32,p4,q.5 stock-default exact science equality | 2 |
| 2 | n64,p8,q.9 beta/sigma stock-initializer equality | 2 |
| 3 | Zero-update factor round trip and explicit ELBO | 0 |
| 4 | Four-sweep checkpoint + one imported sweep equals uninterrupted fifth; independent block comparison | 2 |
| 5 | Sigma mean/rate semantics with IG(1,1) unchanged | 0 |
| 6 | Wrong target, missing factors, negative rates, inherited flags, production dimensions rejected | 0 |
| 7 | Valid latent factors retained in their own parameterization | 0 |
| 8 | n128,p32,q.1 stock-default stress pair | 2 |

Default comparisons include factors, prior state, traces and stopping output,
excluding wall-clock fields. Imported-versus-uninterrupted comparison concerns
the actual factors; the new stopping history is explicitly a new run. The
independent block comparison uses 1e-10 numerical tolerance on well-conditioned
toys. This tolerance is not a production certificate threshold or gate change.

The clone intentionally retains stock Gaussian inverse-product and legacy
fallback behavior to isolate initialization semantics. Passing these tests
would not prove a conditioning repair, target convergence or improved forecasts.

## Admission, resource accounting and interpretation

No actual toy optimizer has run. Root must review source/equations and issue a
separate hashed toy-only authority. EE/LV keep ready-permit priority. The job
uses the same global V2 CPU30 flock, original clock/expiry, one numerical thread,
SCHED_OTHER/Nice10/idle I/O, inherited lock FD, parent-death protection, 8 GiB
address-space ceiling, hard child CPU<=300 and a wall timeout bounded by both
grant and original resource expiry. Authority/hash checks stay on CPU31.
The preflight inspects the actual physical sibling pair {30,62}, rejecting an
unknown numerical peer on either thread; the toy child itself remains pinned
only to30. SMT62 is not an additional allocation. Metadata tests exercise an
unknown numerical peer confined to62 and require rejection.
The absolute diagnostic-stage deadline is also bound to the earlier of the
first LT grant's expiry and the original global expiry: currently
2026-10-27 03:35:09.515675 UTC. Even source-superseded earlier grants retain this
clock boundary; a toy grant cannot extend it.

The prior master charge is 1605.504408 CPU seconds. A new conservative source
charge100 gives 1705.504408 before any toy run. A full child ceiling300 leaves
at least694.495592 of the one original2700 envelope. No old cost or clock is
reset. Claims are one-shot and there is no automatic retry or production fit.

Failure of stock-default equivalence or checkpoint factor equality blocks the
consumer. Passing validates bounded consumption semantics only. A future real
posterior pilot would still need a justified mechanism, independent numerical
checks, exact target/source/initializer contracts, whole-attempt funding and
explicit cumulative-update accounting under original AL300/Normal2000 policy.
It cannot disguise AL600 as a reset or infer continuation authority from these
toy checks. No production certificate or collector override is implemented.
