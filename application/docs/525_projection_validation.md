# Pending numerical validation of the actual project projection

The executable entry is `application/tests/525_project_projection_toy_validation.R`.
It is prepared and **has not been run**. Its unadmitted run contract is
`application/config/pricefm/525_project_projection_toy_runcontract_template.json`.
It requires a new exact root toy grant, frozen source/runtime hashes, finite
CPU/wall/deadline funding, the existing shared muscat_cpu30 permit and actual
CPU30 affinity. Production fits, data, acceptance and automatic retry remain
unauthorized. A pending runtime compatibility issue is not a numerical pass.

The test calls the actual `r525_make_engine`, including its restore assignments
and completed-sweep checkpoint callback. Only its local test copy wraps the
exact generated restore block in `if (!is.null(init$full_state))`, enabling
original stock initialization for default comparisons. Its child-environment
gate is rebound to the hash-bound toy authority and synthetic n<=128/p<=32
limits. Its restore callback changes only schema/origin/kind labels for the
proved `r524_validate_state(..., ns)` validator; every factor and original prior
control remains unchanged. The production gate and namespace are never edited.
Removing the two injected top-level blocks and checkpoint callback must recover
the byte-identical original stock AST from both the actual and test projection.

Exactly eight optimizer calls request thirty total sweeps: three stock/project
pairs with four sweeps each (32x4 default, 64x8 beta/sigma initialization, 128x32
stress default), plus one projected checkpoint-import sweep and five stock
uninterrupted sweeps. Default pairs compare exact science outputs. Full factors
from the actual fourth checkpoint imported into the actual restore assignments
must match the uninterrupted fifth sweep; outer stopping history remains a new
run. Every projected checkpoint must exist, hash correctly, preserve all factor
blocks, RHS/control/schedule state, RNG kind/seed and immutable synthetic X/y
references, and match final fit factors. The original prior controls remain
unshrunk intercept, freeze0 and sigma IG(1,1).

Every context and checkpoint uses origin
`synthetic_project_projection_fixture`, target `synthetic_NONCANDIDATE_*` and
new synthetic X/y files. These artifacts cannot pass the real target registry.
The test asserts that the unchanged production gate rejects its synthetic data.
The entry stops on the first failed assertion; it never reruns a case or
increases the call/sweep limits.

The numerical R process writes only `validation_core.json` with schema
`r154_project_adapter_validation_core_v1`; it cannot claim successful eventual
reaping while still running. After the future root-owned guard returns, its
wrapper must add source, root grant digest, exact actual_R_runtime_binding,
launcher `pinned_native_ELF_no_Rscript_shell_wrapper`, validation_kind
`synthetic_project_projection_only`, the exact core pin and R entrypoint pin to
the immutable guard receipt. The metadata-only executable
`application/tests/525_finalize_projection_validation.py` accepts:

```
--core ABSOLUTE_OUTPUT/validation_core.json
--root-grant ABSOLUTE_ROOT_GRANT.json --root-grant-sha256 EXACT_SHA256
--owned-guard-receipt ABSOLUTE_GUARD.json --owned-guard-receipt-sha256 EXACT_SHA256
--output ABSOLUTE_OUTPUT/validation.json
```

It requires EXITED/returncode0, reaped/drained/accounting and all preexec/kernel
proofs, matching source/runtime/grant/core/entrypoint pins and every synthetic
checkpoint hash. It creates final schema `r154_project_adapter_validation_v1`
with all four numerical/AST/checkpoint flags, no_production_data_used and
native_R_ELF_seccomp_startup_pass. It explicitly records
actual_owned_guard_Rscript_launch_pass=false: the shell-wrapper path has not
passed. No launch success is inferred from metadata presence or process start.
The final numerical proof remains absent until that actual admitted run succeeds.

Metadata-only Python tests cover the finalizer using synthetic JSON/byte files.
They invoke no R, optimizer, target arrays, scientific state or certificate.
