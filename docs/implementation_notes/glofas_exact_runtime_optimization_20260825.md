# GloFAS Exact Runtime Optimization

Date: 2026-08-25
Lane: `work/glofas-exact-runtime-optimization-20260824`
Scientific reference: FR09 persistence-innovation latent-path Q-DESN
Status: implementation complete; release validation passed within lane scope

## Decision

This change introduces an exact runtime layer for the GloFAS latent-path VB
workflow. It does not introduce an approximate VB mode, alter the likelihood,
change the two-block reference/discrepancy model, modify the RHS priors, or
change any reservoir feature. The optimized and fallback paths remain available
behind explicit runtime controls, and all persisted runtime state carries a
semantic contract and provenance.

The release decision is:

1. use the serial OpenBLAS backend with one numerical thread per fit for
   aggregate screening throughput;
2. enable the paired fixed-statistics and compiled-future paths for prospective
   GloFAS fits;
3. serialize latent-path designs with the compact version-2 representation;
4. checkpoint long fits every 100 iterations or 30 minutes, whichever occurs
   first;
5. retain the dense exact solver and exact posterior covariance;
6. reject Schur, iterative, low-rank, diagonal, stochastic, and other
   approximation proposals from this optimization lane.

FR09 remains the scientific article result. This lane changes execution and
provenance only, so no manuscript table, figure, bibliography, or prose update
is warranted.

## Frozen Reference Contract

The runtime audit used the retained FR09 artifacts from the completed
full-seven recovery campaign. Generated binary artifacts remain excluded from
Git.

| Quantile | Artifact | SHA-256 | Semantic design hash |
|---|---|---|---|
| p05 | design | `20cd4e4437c0a4464df9b0799c2b23aa587025562e5507a970a2a85d6c200690` | `e82b7b49107ef4fba8944c754a81d76cf41e5de568cb1869bbd3d16feaf446bb` |
| p05 | historical fit | `90a50d7ccb9b77fbe151b8ff6fcbfd6b660f19caee16c7a1203538c1d0dd1fe1` | - |
| p50 | design | `9c4a441d80e28eea992abd57b3059eea10194cef6f790c723ca77e656ab70934` | `4391beb2610e5bdb664a7aeea87364310c5fc6d2419133ddb72f538e723139ac` |
| p50 | historical fit | `d086eff5c9878581ff152893d3fbbc89b45fafe3d83c202383ca1cdbd7e4d663` | - |
| p95 | design | `fc5ece15c83c5742cc88a421a4253e97b6e606331c011eba3722b57032f380fc` | `742489baac7089fc92b6742da985aba72849645e0326ad939e58c54ad0e42fcb` |
| p95 | historical fit | `e48130e8eac1a10880f8b37def0bd81142bae8f836ecf31350cf9db6520d3d1f` | - |

The p50 design is 1,030,541,553 bytes, has a `24990 x 1686` fixed design, and
uses a 28-step future horizon. Its configuration and model-grid hashes are
`736fcb6b6d812f1d97a32c078e4c8e27653fa1a997e6ef0b3ecdc5e885fa2621`
and `998a324f9068d96b9639267f25c85823fdd2bb0e1e077eb274a9f3d97aaafc35`.

## Implemented Architecture

### Numerical backend

`application/scripts/glofas_numerical_backend_exec.py` launches each worker
under a declared backend, pins all numerical thread controls, optionally binds
the process to a disjoint CPU set, verifies the external library SHA-256, and
writes an atomic terminal execution manifest. The R-side
`latent_path_runtime_backend.R` verifies that the declared library is actually
loaded and records the R version, BLAS/LAPACK paths, affinity, thread settings,
source tree, source hash, and backend fingerprint.

The selected library is:

```text
/usr/lib64/libopenblas-r0.3.15.so
11edc3faddac3c5a78506cb111e74053ebf19baaba63cf72cc8fbc212b59fdf9
```

The pthread build was tested at one, two, and four threads. It did not improve
single-fit or aggregate throughput enough to justify oversubscription. The
serial build is therefore the production recommendation.

### Exact fixed-row statistics

The design layer issues a one-time certificate only when the observed USGS and
GloFAS rows have exactly paired reference features. The VB engine validates the
certificate against dimensions, hashes, source indices, and feature names
before using fused sufficient statistics. If any condition fails, execution
falls back to the original dense exact algebra.

The optimized path fuses repeated weighted cross-products and computes the
reference/reference, reference/discrepancy, and discrepancy/discrepancy blocks
without recreating the full fixed design. It does not remove covariance terms
or alter the precision system.

### Compiled future contract

The future builder now compiles immutable lag lookup, feature, scaling, and
causality metadata once. It reuses a reference readout template, updates only
future-dependent entries, treats the persistence discrepancy block as static
when its contract permits that shortcut, and exploits paired future Jacobians.
Every compiled contract has a deterministic hash and can be disabled for an
exact fallback comparison.

### Compact design and reference cache

The compact version-2 design omits regenerable stacked matrices and restores
the legacy in-memory view on load. The semantic design hash is invariant across
legacy and compact forms. A separate immutable reference-feature cache uses a
semantic key containing the input, feature, engine, and reservoir contracts.
Cache writes are atomic and hash verified; concurrent builders coordinate with
an owned lock and fail closed on timeout or contract drift.

### Exact checkpoint and resume

Checkpoints contain the complete variational state, objective and convergence
traces, RHS update traces, diagnostics, iteration timing, and RNG state. The
contract binds the checkpoint to the design, quantile, prior, seed, semantic VB
arguments, engine functions, and numerical backend. Writes use temporary files,
round-trip validation, SHA-256 sidecars, filesystem sync, atomic rename, and one
previous valid generation. Corrupt primary checkpoints recover only from a
valid, contract-matching previous generation.

### Scheduler and artifact lifecycle

The recovery scheduler now accepts disjoint CPU sets, records backend and cache
provenance, validates checkpoint ownership, resumes only hash-valid checkpoints,
and refuses oversubscription. The cleanup CLI is dry-run by default and deletes
only explicitly named, terminal, task-owned heavy artifacts. It rechecks
ownership, active process paths, root containment, and SHA-256 immediately
before deletion.

## Numerical and Performance Evidence

All performance claims use measured iterative time, not process startup or
design loading. The principal reference and optimized timings were collected
on an isolated core. Later profile and tail canaries ran while unrelated lanes
loaded the host and are used for numerical evidence, not headline timing.

| Gate | Result | Decision |
|---|---:|---|
| Bundled-BLAS reference, FR09 p50 K=10 | 184.4837 s/iteration | frozen reference |
| Optimized serial OpenBLAS, FR09 p50 K=10, 3 repeats | median 9.4328 s/iteration; CV 2.105% | pass |
| Combined exact speedup | 19.5577x | pass |
| K=10 coefficient-mean relative norm | `4.212e-12` | pass |
| K=10 coefficient-covariance relative norm | `9.612e-12` | pass |
| K=10 future-mean relative norm | `3.775e-13` | pass |
| K=10 future-covariance relative norm | `4.266e-12` | pass |
| Compiled future, initial state | 55.82x; exact arrays | pass |
| Compiled future, perturbed state | 357.48x; max absolute `4.441e-16` | pass |
| Future finite-difference relative norm | at most `7.443e-10` | pass |
| Forbidden future derivative | 0 | pass |
| Static discrepancy Jacobian | 0 | pass |
| Compact design file reduction | 40.3889% | pass |
| Compact design semantic hash | exact equality | pass |
| K=50 checkpoint/resume state and draws | bit-for-bit equal | pass |
| Checkpoint overhead at cadence 100 | 0.3241% | pass |
| p05 paired versus fallback, K=10 | worst relative state norm `2.618e-13` | pass |
| p95 paired versus fallback, K=10 | worst relative state norm `2.926e-13` | pass |
| p50 paired versus fallback, converged | 145 iterations each; worst relative state norm `2.589e-11` | pass |

The compiled future contract hash is
`630c3753e02e8e26af2c8e251157ee776f567936fbeac2a2a408db46630a823e`.
The checkpoint uninterrupted and resumed state hash is
`9f455b4707d47036468f9e9583fd1eba58dc1574bb9040f64ede3731173cd7ab`.

Profiling itself is numerically neutral: profile-enabled and profile-disabled
K=10 runs produced the same state hash,
`cc01ee5b8fcb16b0f0b7166d2633fef979214b6437b45ff6e8b6f5730d152256`.
Their same-core median timing difference was 1.10% under the loaded host.

## Residual Optimization Gate

After the exact changes, dense fixed statistics remain the dominant work. In
the accepted low-contention profile, the SPD solve was about 2.3% and all
future-labelled substeps about 8.2% of instrumented time. The remaining cost is
dense BLAS over the exact sufficient statistics. A native extension, Schur
rewrite, sparse solve, or full-memory cache would add substantial complexity
without a qualified bottleneck or an exactness advantage. Stage 9 therefore
stops here. Future work requires a new isolated profile and a prospectively
declared gate.

## Historical Fit Boundary

The retained FR09 article fits were created before the RHS global-scale warmup
policy was added to the engine. The current engine freezes those scale updates
for 50 iterations and begins updating at iteration 51. Consequently, a current
fit is not expected to reproduce the historical article fit exactly even when
the runtime optimization is disabled.

Current-engine cold canaries converged without precision repair:

| Quantile | Historical iterations | Current iterations | Current s/iteration |
|---|---:|---:|---:|
| p05 | 356 | 300 | 9.8491 |
| p50 | 103 | 145 | 9.2707 |
| p95 | 199 | 246 | 9.6185 |

At the common p50 iteration count of 103, the current and historical engines
differ by 3.565% in coefficient-mean relative norm and 0.557% in future-mean
relative norm. The current optimized and current fallback engines are compared
separately, so this pre-existing policy boundary is not attributed to the
runtime work.

The current-engine end-to-end p50 comparison converged in 145 iterations on
both paths, reached the same objective to numerical precision, retained equal
finite masks, and required no precision repair. Relative norms were
`9.788e-13` for the coefficient mean, `1.909e-12` for its covariance,
`1.442e-13` for the future mean, and `4.861e-12` for the future covariance. The
worst recursive variational-state norm was `2.589e-11`, safely below the
prospective `1e-8` release tolerance.

## Reproducibility Evidence

Generated benchmark evidence is intentionally ignored by Git and lives under:

```text
local_trackers/glofas_exact_runtime_benchmark/
```

Important records are:

- `fr09_k10_b0_reference__fixed_k_benchmark.csv`
- `fr09_k10_b1_final_residual_r3__fixed_k_benchmark.csv`
- `fr09_k10_b1_final_residual_r3__fixed_k_comparison.csv`
- `fr09_future_compiled_inputs_final__future_*.csv`
- `fr09_serialization_v2_b0__serialization.csv`
- `fr09_k50_checkpoint_cadence100_final__checkpoint_*.csv`
- `fr09_p05_converged_final__converged_*.csv`
- `fr09_p50_converged_final__converged_*.csv`
- `fr09_p95_converged_final__converged_*.csv`
- `fr09_p05_k10_unpaired_tail_final__fixed_k_comparison.csv`
- `fr09_p95_k10_unpaired_tail_final__fixed_k_comparison.csv`
- `fr09_p50_current_engine_paired_vs_unpaired__comparison.csv`

Each fit benchmark has a sibling execution JSON and runtime-backend CSV. Binary
results are retained only until release comparisons and hashes are frozen.

The closeout storage audit classified all 42 task-owned benchmark `.rds`
objects by path, size, SHA-256, ownership, and release role. Nine accepted
evidence objects were retained for integration review and 33 superseded,
regenerable objects were removed only after a dry run, active-process check,
root-containment check, and immediate checksum revalidation. This recovered
2,457,419,962 bytes (2.289 GiB) and left 803,686,594 bytes (0.748 GiB) of
binary release evidence. The dry-run, executed, and summary manifests are:

- `fr09_task_owned_rds_cleanup_dry_run.csv`
- `fr09_task_owned_rds_cleanup_executed.csv`
- `fr09_task_owned_rds_cleanup_summary.csv`

The artifact-lifecycle CLI was also exercised end to end against an isolated
task-owned fixture. Its dry run selected only the obsolete payload, execution
removed exactly that payload, the protected artifact remained present, and
deterministic regeneration reproduced SHA-256
`0efad9c377f1e823d38f581096ae2eabbe280b5c998bcfcd858e2a155b65c708`.

## Validation Matrix

The release requires all of the following:

1. R parsing for each changed entry point and helper;
2. Python bytecode compilation for the scheduler and backend wrapper;
3. all backend-wrapper and recovery-scheduler unit tests;
4. focused R runtime, checkpoint, compact-design, cache, and artifact tests;
5. exact p50 current-engine optimized-versus-fallback convergence comparison;
6. exact p05 and p95 fixed-iteration optimized-versus-fallback comparisons;
7. a synthetic artifact dry-run, deletion, and deterministic-regeneration test;
8. the repository R harness through the GloFAS tests;
9. `git diff --check` and a lane-scope audit.

The combined repository harness may still stop after the GloFAS block at the
known unrelated shared-validation fixture assertion `nrow(promoted) == 18L`.
That failure is outside this lane and must not be repaired here.

The final lane validation produced these outcomes:

- all 24 changed R files parsed successfully;
- Python bytecode compilation passed;
- all 27 discovered `test_glofas*.py` tests passed;
- the four-file focused R suite passed for input contracts, artifact hygiene,
  latent-path design, and exact runtime/checkpoint behavior;
- the complete repository harness passed the latent-path RHS warmup and GloFAS
  p95 launch-contract blocks, then stopped at the documented unrelated
  `nrow(promoted) == 18L` assertion;
- `git diff --check` and the lane-scope audit passed.

## Operational Defaults

Prospective GloFAS configurations may use:

```yaml
runtime_optimization:
  paired_fixed_stats: true
  compiled_future_contract: true
  reference_feature_cache:
    enabled: true
    root: ""
    wait_seconds: 600

inference:
  vb_ld:
    checkpoint:
      enabled: true
      resume: true
      path: ""
      every_iterations: 100
      every_minutes: 30
      keep_previous: true
      keep_on_success: false
```

An empty cache root delegates to `QDESN_REFERENCE_FEATURE_CACHE_ROOT`. An empty
checkpoint path is expanded to a fit-specific path by `03_fit_models.R`.
Backend selection remains a process-launch concern and is not part of the
scientific YAML.

## Release Boundaries

- No authoritative FR09 fit or design object is deleted or modified.
- No validation, joint-QDESN, PriceFM, manuscript, or Overleaf file is changed.
- Runtime artifacts, caches, checkpoints, and benchmark objects remain ignored.
- The dedicated task branch is the only push target.
- Integration into authoritative main is delegated to the article integration
  coordinator.
