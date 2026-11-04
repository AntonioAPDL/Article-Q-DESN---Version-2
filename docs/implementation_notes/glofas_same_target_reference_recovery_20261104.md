# GloFAS: same-target conditional reference recovery

## Scope and prior evidence

This diagnostic lane follows the completed nonlinear replay and conditional
AL reference checks integrated at `531b98b1be18ae906f04d0990fe519292c3b4aba`.
The earlier four chains completed, with 80,000 retained paths, but only five
of 28 horizons met all prespecified precision and mixing thresholds. That
result remains inconclusive; successful execution does not overturn it.

The conditional calculation fixes coefficient means, sets their covariance
to zero, and uses scales equal to the reciprocals of the retained mean inverse
scales. It is not a sample from the full parameter posterior. All 51 issued
ensemble members contribute ordinary, unit-weight likelihood factors. The
fresh feature map, likelihood, parameters, priors, and input gains are unchanged.
Future USGS measurements are excluded. The separately identified discrepancy
between selected and applied input gains remains unresolved and is not repaired
by this lane.

Generated analysis of the completed paths found substantial autocorrelation
and a proposal-covariance mismatch. This motivates testing better proposals
before repeating an expensive reference calculation. It does not establish
that the completed paths are a qualified posterior sample or identify the
cause of the application's poor forecasts.

## Two proposals for the identical density

Let `pi(y)` denote the existing 28-dimensional, fixed-parameter AL path
density, evaluated using fresh recurrent features. Pool all four completed
chains for a proposal centre `m` and covariance `S`. Define

```text
C = 0.95 S + 0.05 diag(diag(S)).
```

If necessary, apply the documented positive-definiteness floor
`1e-10 * trace(C) / 28`. This calibration changes only the proposal. It does
not change a prior, likelihood scale, coefficient covariance, or VB covariance.

The first arm proposes a symmetric normal random walk with covariance
`exp(2 log_scale) C`. Scalar adaptation stops after warmup. The second arm
uses a fixed 50/50 mixture of that move and a Student-t independence proposal
with five degrees of freedom, centre `m`, and scale matrix `3 C / 5` (hence
covariance `C`). For the independence move the log acceptance ratio is

```text
log pi(y_new) - log pi(y_old) + log q(y_old) - log q(y_new).
```

The random-walk ratio omits the proposal terms. Selecting between two
individually invariant kernels with fixed, state-independent probabilities
preserves the same target. Neither arm is a replacement statistical model.
Tests cover multivariate Student-t density, detailed balance, known scalar
and small nonlinear targets, covariance calibration, frozen post-warmup
adaptation, seed identity, partial-run retention, and subset/combined parity.

## Prospective pilot, not production qualification

The pilot runs four named chains per arm, each with 500 warmup and 1,000
retained iterations. Both arms and every chain remain in the output,
including failures and partial states. Selection is by computational
precision and cost, never held-out streamflow loss. Starting paths and seeds
are fixed before execution; there is no seed search.

One source-bound parent admits the same two original RDS inputs and one
generated numeric array used exclusively for proposal calibration. It checks
their before/after hashes, the prior replay, the independently closed baseline,
the exact fixed parameter point, and the full 19-file runtime source closure.
Six fresh compiled/uncached evaluations and one setup evaluation precede
eight one-thread workers. The maximum declared value-call count is
`6 + 1 + 8 * 1501 = 12015`. Original payloads are not opened by the Python
controller. No saved callbacks, truth reads, parameter/prior updates, full
fits, retuning, scoring, article changes, or publication are admitted.

The typed purpose is external to the committed tree; outputs reside in an
exclusive ignored `local_trackers` directory. Native execution is bounded by
one-hour wall/CPU limits and 16 GiB address space per actor. The conservative
nine-actor allocation is 144 GiB, with another 180 GiB of available-memory
headroom and 80 GiB of free disk required. Eight assigned logical CPUs exclude
the protected legacy jobs and their physical siblings. Historical value-call
cost multiplied by two supplies a planning projection, not a guaranteed
per-call latency bound. Insufficient remaining time prevents a fork.

The launcher uses its own owned tmux socket rather than relying on the
invoking terminal or a transient command session. Its supervisor records
native process identities and limits, monitors aggregate usage, cleans up
only its own validated session groups, and verifies source/output manifests
after exit. Generated tests exercise frontend exit, unrelated-process
preservation, timeout, lineage, and invalid-manifest rejection. R progress
files are chain-specific and do not consume sampling RNG state.
Controller metadata is published atomically without overwriting evidence.
Bounded snapshots distinguish expected progress-file renames and new owned
children from missing evidence, foreign processes, and other I/O failures;
process identities are rechecked across the native metadata reads.

Every pilot arm and the top-level result have `qualified = FALSE` or the
corresponding explicit qualification flags. Diagnostic thresholds are retained
separately. A short computational pilot cannot authorize a production reference,
full-model refit, or publication, even if its diagnostic thresholds happen to
pass. A longer reference requires a new bounded purpose and measured schedule.

## Complete-parameter check and its boundary

`scripts/diagnostics/glofas_coupled_parameter_reference.R` supplies a generated,
one-step exact integration check. For a proper normal coefficient prior,
fixed AL scales, and zero, one, or 51 ordinary member factors, it integrates
the coefficient posterior and the normalized future-response law. Tests check
no-member invariance of the parameter marginal, legitimate member updating,
coefficient--response covariance, predictive CDFs/quantiles, and a closed-form
normal--AL convolution. Tiny tail probabilities are evaluated with scaled,
piecewise quadrature rather than by weakening tolerances.

This is a controlled mathematical reference, not a qualification of the
nonlinear RHS, exAL, or multiquantile application. With no member data,
integrating a normalized future-response law must leave the historical
parameter posterior unchanged. With issued members, their marginal likelihood
can legitimately update parameters. Freezing that marginal while adding member
information would define a cut model rather than automatically preserve the
intended joint target. A complete inference correction must address this
parameter--path dependence, not just improve conditional path sampling.

## Validation and release gates

The three R test files and the Python controller test are registered in
`application/tests/run_tests.R`. Run with pinned R 4.6.0 and Python 3.11 in
the repository's verified dependency environment. The private diagnostic
posterior package library is used for authentic reference diagnostics; no
package upgrade is implied. Generated tests require no original payload reads.

Before a diagnostic launch: verify the clean committed source, explicit
external purpose, baseline/replay receipts, native limits, fresh resources,
dry-run permission checks, and durable-controller tests. Before integration:
run the combined repository harness, parse changed R, compile Python source,
run `git diff --check`, verify the exact ten-file surface, and confirm every
article-allowlisted blob is unchanged. Integrate using normal command-line
Git in an isolated integration worktree. No Overleaf publication is needed
or authorized for these diagnostic additions.

A complete application rerun remains conditional on a qualified full-model
method and a feasible dependency-aware schedule. Additional cores cannot
eliminate the median-outward and joint-fit dependencies. Historical production
timings are not a new-method ETA; they must not be used to promise a corrected
release before the author's submission deadline. Keep unsuccessful attempts,
the outstanding input-gain question, and every unpassed gate in the ignored
resume record.
