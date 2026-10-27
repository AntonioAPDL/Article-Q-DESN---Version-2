# R154 fixed-state reference lane

This lane prepares numerical diagnosis of the seven sealed AT/LT/NO3 failed
returns. It contains no optimizer, production certificate overlay, registry
mutation, main integration, or article publication. The base science commit is
`4cd92ac3654f16a84a67c8db6cfc7f381113aeb9`. Active R141/R144/R146/R153 trees and
the installed CRAN package are untouched.

## Numerical contract

The manifest preserves the exact target digest, n/p, tau/tau0, seed, contract,
failed compact moments, certificate, trace, parent/design terminals, and original
source pins for all seven returns. Terminal seals bind the full design files;
those bytes and dimensions are revalidated before any target arithmetic.

Normal cap 2000 and AL cap 300 are frozen. Production acceptance remains
`finite AND (formal OR independent)`. All seven independent limits and both RHS
reconstruction convergence requirements remain unchanged. Every output from this
lane is an immutable diagnostic with no production acceptance authority.

Gaussian equilibration uses `P*=D P D`, `b*=D b`, then maps `beta=D theta` and
`V_beta=D V_theta D` into the original coordinates. No design/response rescaling,
prior change or jitter is allowed. A non-SPD original precision stops. Reported
componentwise/normwise backward errors and inverse residuals are measured against
the original P and b. Good backward error alone does not prove forward accuracy
at the observed target condition numbers around 1e13.

At AL GIG shape 1/2, the likelihood's `-sum(Elogv)/2` cancels the entropy's
`+sum(Elogv)/2` in real arithmetic. The reference retains every original prior,
Gaussian and inverse-Gamma normalization constant and the chi/psi floor
correction `sum((chi-chi_raw)*ell+(psi-psi_raw)*nu)/2`. It changes no objective
origin or relative-change denominator. The original pinned R prior's ELBO scalar
is deliberately shared between formulas. This is a transparent boundary, not an
independent high-precision audit of the entire RHS prior algorithm.

## Synthetic evidence

The Python oracle uses stdlib Decimal at exactly 80 digits. Cholesky/triangular
solves are independently implemented. Log-Gamma/digamma use exact recurrences
from 1 or 1/2 with pinned pi and Euler constants. The domain is n<=8,p<=4,
integer/half-integer IG shape<=32; production dimensions are rejected.

There are 32 Python and 32 R unique tiny fixed states, at most 64 in total.
The R cases compare the original pinned CRAN/r129 formula with the collapsed
reference; the same R cases can be checked against Decimal without adding new
cases. Both chi and psi floor branches are exercised. Tests also cover original
unit covariance recovery, prior constants, changed hashes/units/prior/state,
changed limits/caps/acceptance, expired/unfunded authorities, non-SPD inputs and
exclusive output creation. Synthetic cases establish algebra/implementation
agreement; they establish no numerical cause or repaired certificate for LT,
AT or NO3.

## Execution gate and shared permit

`522_fixed_state_control.py` requires a separately hashed root authority with
status `ROOT_ADMITTED_FIXED_STATE_DIAGNOSTIC_ONLY`, manifest digest, source
bindings, actual R runtime binding, expiry and target `LT_fold1_al0.90`. Its
initial authority cannot admit other targets or posterior fits. R independently
checks the grant/source/manifest and inherited permit descriptor as well.

The authority must pin the shared `r154_global_permits_v1` contract. Only
`muscat_cpu30` is accepted, with global numerical concurrency exactly one,
CPU30, SCHED_OTHER, Nice10, and every numerical library limited to one thread.
Physical31 and SMT63 remain headroom; SMT62 is excluded. Jerez numerical work is
unadmitted. The controller acquires the same `permit_id.lock` flock as EE/LV
before consuming the one-shot grant. A busy permit rejects without consumption.
The R child inherits this descriptor; it remains locked until all holders exit.

The maximum diagnostic envelope is 2700 CPU seconds, 7200 wall seconds, one
core, 8 GiB memory and 2 GiB output: source preparation reserves 300 CPU seconds,
fixed references reserve 600, and the R target child is capped at 1800. This is
one total envelope; it does not grant an extra 2700 seconds after preparation.
Parent CPU and reaped child CPU are measured and charged. The administrative
controller has a 300-second soft CPU limit. The child gets hard CPU/address-space limits, a wall
timeout, parent-death SIGKILL with a parent-PID race check, and at most 16 MiB
per scalar output file. This death signal applies only to the newly created
disposable diagnostic child. Receipts charge child CPU and wall time. Each grant is consumed once, including failed attempts; retries need
a new reviewed grant. No generic fit or cap-600 mode exists.

## LT-first interpretation

The prepared evaluator conditionally reconstructs the unchanged original r129
recipe from retained m,V,sigma and the exact original design. It compares seven
measures, raw current/next objectives, RHS counts/residuals and original-unit
solve behavior to the stored failed record, then evaluates both objective
formulas on that same reconstructed state. These absent original intermediate
vectors cannot be declared bitwise original state or exact optimizer resume.

LT's small absolute objective gap may reflect genuine joint nonstationarity;
passing six component gates does not imply passing the objective gate. No
rounding/Bessel cause is presumed. Reference agreement within measured
arithmetic scale supports stopping the arithmetic repair path. A meaningful
discrepancy requires further unchanged-target/source-equivalence review before
any novel diagnostic overlay; old failed records stay immutable. AT/NO3 solve
diagnosis requires separate target-specific authority and cannot promise a
stationarity pass. New posterior attempts need separately priced target
manifests and funding under the original caps.

## Reproduction

Use the pinned r137 Python and R4.6.0, with OMP/OPENBLAS/MKL/BLIS/VECLIB/NUMEXPR
thread environment all set to 1. `522_certificate_reference_test.py` accepts one
new output JSON path. The R synthetic test accepts worktree root, exact CRAN
library and new output JSON path. `522_runtime_binding.R` accepts that library
and a new JSON path (`-` emits read-only JSON to stdout). No target arithmetic is
required to observe the runtime or run these synthetic checks.

Root may first invoke the coordinator with `--check-authority`; this verifies
authority and runtime/code bytes without opening target data or running R.
Launch the administrative controller on CPU31 (`taskset -c 31`). Administrative
validation, source/runtime hashing and `--check-authority` remain on that caller
CPU. Only after successfully acquiring the shared numerical flock does the
controller move itself to CPU30 and apply the numerical scheduler, nice and I/O
settings. A busy-pool request cannot move to CPU30, read target data or consume
its one-shot grant. A real busy flock negative test exercises this boundary.
Actual execution also requires `--output-dir` to be a new child of the owned
R154 `certificates/` audit directory. The controller has no admitted default
grant and cannot infer permission from the implementation request.
