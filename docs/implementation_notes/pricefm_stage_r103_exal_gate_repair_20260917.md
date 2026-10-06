# PriceFM Stage-R103 exAL diagnostic-gate repair

## Scope

This correction is limited to the validation-only R103 independent-quantile
campaign. It does not open test data, change a posterior target, refit a model,
change a prediction, select a family, or mutate the registry or article.

The campaign was stopped after preserving 330 of 1,596 atom terminals and 21
of 114 complete region-fold cases. There were no failed cases. Among the saved
atoms, 163 exAL fits were formally converged but incorrectly marked
numerically ineligible because the R103 wrapper did not copy
`fit$diagnostics$deltas$state_relative` and
`fit$diagnostics$deltas$prediction_scaled` into the saved VB trace. The frozen
exAL runtime had computed both vectors. One separate AL atom reached its
500-iteration cap without formal convergence; this repair deliberately does
not alter that atom.

## Future-fit correction

`344_run_pricefm_stage_r103_quantile_case.R` now performs the same diagnostic
extraction used by the validated R95 runner. It requires each diagnostic vector
to have exactly one value per VB iteration and records
`diagnostic_gate_method = exact_runtime_diagnostics` for new exAL terminals.
Missing or mismatched diagnostics stop the atom instead of silently making a
scientific eligibility decision.

## Preserved-fit proof

For an iteration-level coefficient change vector `d`, the frozen runtime uses

```text
delta_state_relative = max(abs(d)) / max(1, max(abs(beta_previous)))
delta_prediction_scaled = RMS(X d) / MAD(y).
```

Therefore

```text
delta_state_relative <= max(abs(d))
RMS(X d) / MAD(y) <= max(abs(d)) * RMS(row_L1(X)) / MAD(y).
```

The saved trace contains `max(abs(d))` as `delta_state`. The repair evaluates
these conservative upper bounds against the original `0.01` thresholds using
the immutable R103 training design. A historical exAL atom is repairable only
when it formally converged and its only false checks are the four checks made
unavailable by the two omitted trace columns. Every other numerical check must
already pass.

The read-only whole-surface audit proved all 163 preserved exAL atoms across
27 cases. The largest conservative relative-state bound was `0.000423`; the
largest conservative prediction-scale bound was `0.009290` for
`r103_de_lu_f1_exal_0p1`. Both are below the preregistered `0.01` gate.

The repair writes a proof beside each repaired atom, refreshes dependent
eligibility hashes, and records a manifest of protected artifacts. Coefficient
means, coefficient covariances, parameter summaries, raw VB traces, validation
predictions, and validation loss values must remain byte-identical. Completed
case metadata is refreshed; interrupted cases retain their completed atoms for
normal resumable reuse.

## Execution sequence

1. Run focused Python tests and parse the R runner.
2. Commit and push the dedicated PriceFM branch.
3. Rematerialize the source-hashed R103 prep from the clean synchronized head.
4. Run the repair without `--write` and require every historical exAL terminal
   to pass the conservative proof.
5. Snapshot protected hashes, apply the metadata repair, and revalidate all
   protected hashes.
6. Resume the same R103 campaign. Completed cases and atoms are reused; no
   campaign is restarted from zero.

R104, test evaluation, registry promotion, article changes, joint models, and
MCMC remain blocked until the complete R103 validation-only closeout.

## AL nonconvergence recovery

The same frozen snapshot contained one distinct AL atom,
`r103_dk_2_f2_al_0p45`, that was finite but did not formally converge at the
configured 500-iteration ceiling. Its conservative prediction-change bound was
`0.010073`, so it was not relabeled as eligible. R103 now reuses eligible AL
atoms but retries an ineligible AL atom against the same data, likelihood,
prior, initialization, seed, tolerance, and posterior target with a bounded
750-iteration ceiling. New AL fits that first reach 500 without convergence
receive the same single bounded retry. The terminal records both the configured
and effective ceilings. exAL atoms remain valid fallback candidates even when
ineligible, while a completed case is reusable only when its mandatory AL
fallback family is eligible.
