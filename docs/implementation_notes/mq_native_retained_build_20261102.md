# Retained native build for one-unit source qualification

`scripts/build_mq_native_replay.py` implements a separate build-only purpose.
It does not load scientific inputs, fit or forecast a model, qualify numerical
accuracy, approve a general ABI or dispatch a production campaign. Existing
generated loaders and historical qualification/preparation code are unchanged.

The external, SHA-bound contract fixes an exact clean published source commit
and tree, the three C files, the builder/test/documentation closure, compiler
and link inputs, the included-header inventory and an unused external output
directory. All wider numerical, fitting, scoring, future-truth, production and
article permissions are false. Duplicate JSON keys, changed pins, expanded
limits, wrong source or unpublished identities fail explicitly.

The controlled build uses existing GCC8.5.0 and the native R4.6.0 SDK. Compiler
dependency preprocessing identifies all included headers; GCC program/link
queries and ELF dependency inspection identify the toolchain and runtime
inputs. Inventories are checked before and after compilation. The generated
Makevars fixes one-thread compilation, disables fast math and floating-point
contraction, and sets the native R library rpath. User profile/environment and
include/library overrides are excluded by a bounded environment allowlist.
The actual libcrypto linker input is explicitly resolved, pinned and linked
by absolute path rather than left to an incidental `-lcrypto` search.
Retained outputs include source copies,
objects, three libraries, exact compiler logs and a hash-bound build receipt.

Actual builds require isolated Python3.11, CPU26, CPU120 seconds, TERM at119
seconds/KILL one second later, 2GiB address space and64MiB output limits.
Whole-group native timeout and hard/soft resource limits are checked. The
coordinator separately bounds SDK enrollment and external stop/terminal
accounting; enrollment or a completed generated test is not a build grant.

`mq_native_retained_build_receipt_v1` records the new source commit/tree,
purpose hash, role-specific library path/size/hash and corresponding C source,
toolchain/header pins, compile-log hashes and actual flags. A later genuine
qualification driver must independently authenticate this receipt, registered
entry signatures, actual in-process library mappings and its complete runtime
before authentic numerical execution. No `C_ABI_qualified=TRUE` flag or global
production approval is issued by this builder. The original source and linked
dependency licenses remain applicable; no linked binary is added to Git.

The registered Python test exercises generated contract, permission, expiry,
budget, inventory, path/hash and environment rejection cases only. It performs
no compilation, authentic input read or scientific execution.
