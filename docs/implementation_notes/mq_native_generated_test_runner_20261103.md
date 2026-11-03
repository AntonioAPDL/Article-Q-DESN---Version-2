# Standalone adapter for the four generated native tests

The full application suite previously called the key/hash test without its
three required CLI arguments. The resulting suite failure is retained; it
does not invalidate or replace the earlier correctly invoked focused tests.

`application/tests/run_mq_native_generated_tests.R` is now the single
application-suite registration for all four unchanged tests. It launches
fresh R4.6.0 subprocesses with their actual interfaces:

| Test | Trailing arguments | Build |
|---|---|---|
| Key/hash | DLL path, SHA256, existing output directory | Runner builds the key DLL |
| Isotonic | None | Unchanged test builds its own temporary DLL |
| Event/inverse | None | Unchanged test builds its own temporary DLL |
| Composed arrays | None | Unchanged test builds all three temporary DLLs |

The runner itself accepts no trailing arguments and rejects unexpected
inputs before creating outputs or compiling anything.

Builds use the existing GCC8.5.0, one-thread settings, controlled Makevars,
`-fno-fast-math`, `-ffp-contract=off` and native-R library rpath. The isotonic
and event tests replace their own user Makevars; the runner therefore also
pins compiler PATH and inherited PKG_LIBS, and checks actual child compile
logs for compiler/flags/rpath. Missing tools, failed tests, absent completion
markers or changed source bytes fail explicitly; nothing is skipped.

A fresh receipt directory retains logs, source/test hashes and exact
entrypoint outcomes. Set `MQ_NATIVE_GENERATED_RECEIPT_ROOT` to a nonexistent
canonical ignored repository path to retain it outside the default process
temporary tree. Other destinations are rejected before creating outputs.
Missing file statistics or symlinked outputs fail rather than disappear from
the accounting. Total generated output is checked against 128 MiB. The caller supplies finite aggregate
CPU/wall/memory/process-group limits; this is a test adapter, not a scheduler.
All four original tests, numerical helpers, defaults, scientific hashes,
real-data exclusions and previous failure evidence remain unchanged.

Passing this runner is generated software verification only. It grants no
authentic input access, runtime/C ABI qualification, production dispatch,
model refit, parameter pooling or article promotion.
