# LT and NO4 independent reference source

This package implements separate compute-only Gaussian and fixed-factor objective reference components. It does not run a posterior optimizer, alter the original mathematical source, provide runtime admission, establish scientific acceptance, or release dependent work.

The source was authored under the new pilot/reference engineering purpose. Administrative tests execute only the closed metadata validator, source parsing and adversarial metadata rejection. **No matrix, Decimal reference, synthetic oracle, R, NumPy, objective, scientific binary or target payload was executed or read on administrative CPU31.**

## Implemented components

| File | Concrete implementation |
|---|---|
| reference_contract.py | Closed predetermined LT and NO4 primary/control targets, dimensions, seeds, original units/prior, exact binary64 layout and P/RHS identities, fixed 80/120/160 precision schedule, unchanged seven limits and both RHS starts. Passing metadata cannot grant execution. |
| decimal_reference.py | Exact binary64 import with Decimal.from_float; full Cholesky mean and all inverse columns without jitter, symmetrization or changed prior; full-matrix outward-rounded inverse/mean residual bounds and conditional forward bounds for the returned covariance view; independent full RHS_NS prior terms and explicit original imported-factor AL objective. All numeric helpers are private and have no CLI or import-time arithmetic. |
| reference_compute.py | Actual fixed sibling owner boundary acquisition before request/payload parsing and numerical kernel import. Fixed reviewed source paths and exact hashed bytes are checked and the verified bytes are executed without loader re-open. Every input comes through the live boundary's allowlist. No caller-supplied validator or fake ACK flag is accepted by the actual entrypoint. |
| analytical_fixtures.py | Nine compute-only known-answer cases: sizes8/16/32 in three families. Expected full covariance and mean follow independent diagonal, Sherman-Morrison and closed2x2 identities. The code evaluates three precisions per case only after a separately admitted real compute boundary. These 27 evaluations have not run. |

The fixed LT case is n90240/p337/seed710583720/tau=0.9. The predetermined NO4 pair is n48576/p961/seed1149227177/tau=0.5, with primary tau0=9.653643731923241e-05 and paired prior-control tau0=9.653643731923241e-06. Their original full binary64 values and metadata identities remain unchanged; the shorter task-name decimal spelling is not a new numeric target.

## Boundary and invocation

The source-reviewed map must bind the physical fixed sibling owner/compute_boundary.py and every reference source by path and SHA256. The concrete call is:

    reference_compute.run(spec_pin, authority_pin, source_review_pin, acknowledgement_pin)

The entrypoint loads only the fixed reviewed sibling owner, calls its real acquire(...), verifies the live process, reads the allowlisted reference_request and validates its closed contract. It reads numerical inputs only through OwnedBoundary.read_input, checks exact P/RHS byte identities, and only then imports the reviewed numeric kernel. A separate run_synthetic(...) follows the same actual boundary and requires the exact independent nine-case fixture request.

These functions do not accept an injected ownership callback. The parent parse-gate JSON is not the kernel ACK: the shared owner must establish the actual currently qualified native Slurm/proc/TSYNC/ACK boundary. **The new Python bootstrap is not presently qualified, and old R owner receipts cannot qualify it.** The source purpose has zero new compute funding, so it cannot issue a legal runtime invocation.

The input aliases are precision, rhs, candidate_beta and candidate_covariance. The optional EXPLICIT_IMPORTED_FULL_FACTORS mode also requires original design, response and an owned factor_snapshot. Request-v2 declares little-endian IEEE754 binary64 layout separately for each matrix: precision and candidate covariance are column-major owned exports, while original X.bin design bytes remain row-major as consumed by the unchanged R179 source. The original design is not silently transposed or reinterpreted. No Decimal(str(float)) target substitution occurs. The owned snapshot binds the exact target, original failed bindings, recipe, named input byte identities and native export receipt. Its q(v) factors are evaluated as imported; they are not reconditioned on the current sigma.

The full objective can require large original X inputs (LT~243MB; NO4~373MB) and O(n*p^2) work. These are separately admitted input bounds and costs, not permission to enlarge the original useful-return caps. Gaussian-only mode does not claim objective or full target acceptance.

## Output and errors

run returns r200_reference_owned_return_parts_v1 with records containing relative_path, SHA256, length and payload bytes. The owning separately qualified bounded writer must atomically commit every declared part. This reference writes no arbitrary file.

Full covariance is returned as an explicitly labelled binary64 view in blocks of at most32 complete rows; no probe or selected rows replace the full covariance. Each prepared part is bounded by16MiB and the complete useful return by64MiB before any write. The forward-error calculation uses the actual returned binary64 view, so output conversion is part of that component bound. Higher-precision numerical stability is reported separately and is not a proof of total error.

For exact P/RHS and approximate inverse V, outward-rounded arithmetic encloses rho=||I-PV||inf and e=||P*beta-b||inf. Only when rho<1 does the implementation report ||P^-1||inf <= ||V||inf/(1-rho), beta error <= that bound times e, and inverse error <= ||V||inf*rho/(1-rho). This is a component theorem for the exact supplied matrix and returned view. It does not establish target construction, the original normed seven gates, a fixed-point certificate or an explanation of an old failure.

The independent RHS_NS prior is derived from the exact CRAN1.1.1 source, not a production prior_scalar. It includes local/global/slab normal terms, all inverse-gamma hyperpriors/entropies and the original unshrunk-intercept term. Integer/half-integer gamma recurrence supports the full original sigma shape up to200000. Pi uses Machin's alternating arctangent series; Euler's constant uses Euler-Maclaurin harmonic expansion. Analytic omitted-term quantities are recorded, but Decimal rounding propagation through special functions, target moments and the complete objective is **not** yet a rigorous closed budget.

## Evidence and remaining gates

The first29-test metadata/static action passed. A real source-loader TOCTOU concern, stricter imported q(v) floors and duplicate-rejecting synthetic-request parsing justified a changed-source second action;31/31 passed. There are31 distinct test methods, not60. Both receipts, intents, full fees and exact earlier tested source bytes are retained in HISTORY_MANIFEST.json. Numerical reference cases executed:0. Scientific payload reads:0. Children CPU:0.

Before scientific use the following remain required:

1. Independent source review and publication, plus a freshly qualified Python native bootstrap and actual current owner/kernel/ACK boundary.
2. Separately funded analytic fixture execution and interpretation of all27 precision evaluations. Metadata tests are not Gaussian or prior numerical tests.
3. Owned original-recipe reconstruction/input delivery, current factor-export provenance and explicit pricing for exact LT/NO4 dimensions, memory, startup, full covariance, interval residual work, objective, return, peer and closure. NO4 full inverse is O(961^3); no feasible timing is inferred from source.
4. Rigorous special-function/full objective rounding propagation and the full target-construction/seven-original-measure/both-RHS-start error-budget closure. Unsupported bounds remain null and all scientific acceptance flags remain false.
5. An independently reviewed measured mechanism explaining the original excess under unchanged limits. No optimizer updates, automatic eight-fit replay, tolerance change, bad-fold substitution or production promotion follows from this component source.

The reference is useful concrete source preparation. Its current output status deliberately holds full scientific acceptance rather than treating precision stability or a small backward residual as a substitute.

## Layout refinement03

The independent source review identified that the original X.bin reader is row-major (W191 r179_hb_bridge_or_pilot.R line128 uses byrow=TRUE), whereas the earlier full-objective implementation used column-major indexing for X. That frozen02 source variant and its successful source-only review remain preserved as historical preparation, not target qualification. A distinct four-CPU source refinement uses request-v2 with separate per-input layouts and row-major X indexing. Precision/covariance layouts remain explicit column-major owned exports; no original X bytes or target payload was opened, rewritten or numerically exercised. New layout-specific metadata/static rejection tests cover the changed contract; the earlier numerical/error-budget HOLD remains unchanged.
