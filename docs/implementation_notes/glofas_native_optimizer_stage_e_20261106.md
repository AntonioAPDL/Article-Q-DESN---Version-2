# GloFAS native optimizer Stage E qualification

## Boundary

Stage E is a truth-free operational, numerical-precision, and cost
qualification for the independent median-AL native target. It is not an
optimizer fit, Stage F launch, production campaign, forecast comparison,
authority replacement, or publication action. It reads exactly the accepted
truth-free design and median-AL fit once under a new source-pinned purpose.
Future USGS is physically excluded.

The qualification binds the Stage D contract without changing the scientific
model: 7,510 physical coordinates, 2,502 readout coefficients, 12,455
historical rows per source, two retained DESNs with gains `0.5/0.35`, 28 future
horizons, 51 unit-weight issued members at each horizon, distinct Y/G scales,
and the full normalized Nishimura--Suchard product hierarchy. The Stage A prior
receipt fixes the exact task, target, prior, and one-Jacobian identities.

## Prospective acceptance budget

`scripts/diagnostics/glofas_native_stage_e_acceptance_budget.json` freezes all
contexts, directions, seeds, particle counts, tolerances, and resource caps
before either original RDS object is opened. The matrix includes:

| Check | Frozen scope |
|---|---|
| Continuation parity | H2/H28, three paths, A/B/A, features and locations at `1e-10` |
| Historical derivatives | 16 roles, mean/log-SD, steps `1e-4` and `3e-5` |
| Nonlinear H2 | Three parameter contexts, split quadrature, four N=256 replicates |
| H28 precision | Three contexts, N=64/128/256, four initial replicates |
| Conditional extension | Twelve more replicates only after the frozen cost/RAM rule |
| RHS invariance | RHS-only perturbation changes the prior but not future evidence |
| Frozen-q gradients | N=64/128, four batches, two outer draws, raw and centered scores |
| Reporting precision | MCSE `0.001`, cross-count difference plus two MCSE `0.005` |

The initial H28 grid has 36 evaluations. Its extension produces 144 total
grid evaluations and is allowed only if all initial calculations are valid,
twice the slowest measured evaluation projects inside the remaining wall cap,
and measured process memory plus 180 GiB of server headroom is available. No
failed replicate is replaced. The smallest admissible adjacent particle pair
must also agree with every larger assessed count; N=256 is not selected merely
because it is largest.

## Implementation

`scripts/diagnostics/glofas_native_stage_e.R` is a pure in-memory qualification
module. It reconstructs the diagonal-Gaussian initializer from retained VB
moments while keeping those values computational rather than prior-defining.
It performs the complete parity, derivative, H2, H28, invariance, gradient,
precision, and cost calculations and returns compact tables. It has no file
reader and no optimizer call.

The optional diagnostic feature rows in
`scripts/diagnostics/glofas_two_desn_particle_backend.R` are inserted into each
cache entry atomically. Cache identity now includes the exact coefficient and
source-scale hash. This makes the required A/B/A test meaningful: B cannot
reuse A's features, while the repeated A must hit the original exact ancestor.

`scripts/glofas_native_stage_e_reader.R` is the sole authentic entry point. It
requires a private external purpose, exact clean committed source, one logical
CPU, R 4.6.0 with one-thread BLAS, an eight-hour timeout ancestor, 32 GiB address
space, and 64 MiB output cap. It authenticates the accepted producer collection,
input manifest, Stage A prior receipt, acceptance budget, and complete source
closure before reading exactly two originals. Both payloads are hashed before
and after deserialization. Partial failures retain a no-fit failure receipt.

Permitted outputs are CSV/JSON evidence, the native target contract, compact
binding, receipt, and manifest. Particle paths, the design, fitted objects,
callbacks, future truth, and derived contexts are never serialized. Every
receipt fixes model-fit and optimizer-iteration counts at zero and keeps Stage
F, native fitting, production, and publication flags false.

## Decisions

The only Stage E decisions are `REVISE_SOURCE`, `REJECT`, `INCONCLUSIVE`, and
`ADMIT_STAGE_F_PROPOSAL`. The last state permits drafting a separately reviewed
Stage F proposal only. It does not launch or approve a fit. Source/parity/
derivative/RHS failures yield `REVISE_SOURCE`; nonlinear or complete-grid
numerical failures yield `REJECT`; an inadmissible 16-replicate extension yields
`INCONCLUSIVE`.

Generated-only tests cover permission rejection, the complete coordinate map,
initializer reconstruction, exact parameter-aware cache reuse, prospective
particle-count selection, and cross-count reporting failure. Those tests open
no authentic RDS payload and run no model.
