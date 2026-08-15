# Phase132 Joint exQDESN exAL-RHS Nonlinear Width-8 Long Confirmation

## Purpose

Phase132 is the long-chain confirmation run for the only Phase131 sampler-tuning variant that
passed the target tau-0.25 gamma/sigma Rhat and ESS gate in the nonlinear reservoir-friendly
scenario.

The relevant evidence is:

- Phase130 width-4 long-chain reference improved ESS but retained target Rhat above the review
  threshold at tau 0.25;
- Phase131 compared targeted tau-0.25 gamma slice policies and found that width multiplier 8 with
  the standard 100 slice-stepping budget was the best variant;
- increasing the slice-stepping budget to 300 did not help and made the target diagnostics worse.

Phase132 therefore confirms the Phase131-selected policy under the same long-chain scale used by
Phase130:

- scenario: `nonlinear_reservoir_friendly`;
- base gamma slice-width multiplier: `4`;
- target tau: `0.25`;
- target tau gamma slice-width multiplier: `8`;
- gamma slice max steps: `100`;
- chains: `12`;
- iterations/burn/thin: `16000/4000/1`;
- raw `.RData`: not retained.

## Default Command

```bash
Rscript application/scripts/137_run_joint_exqdesn_exal_phase132_nonlinear_width8_long_confirmation.R
```

Default output:

```text
application/cache/joint_qdesn_phase132_nonlinear_tau025_width8_long_confirmation_20260714
```

## Gates

Hard fail:

- missing source manifests;
- preparation or chain worker failures;
- non-finite MCMC draws or target diagnostics;
- malformed artifact manifest.

Review:

- target tau-0.25 gamma/sigma Rhat remains above 1.2;
- target ESS remains below 100;
- gamma lag-1 autocorrelation remains high;
- large gamma/sigma/lambda chain-mean separation persists.

Pass for practical MCMC confirmation:

- implementation gates pass;
- target tau-0.25 gamma/sigma Rhat is at most 1.2;
- target tau-0.25 gamma/sigma ESS is at least 100;
- chain-mean separation is materially reduced relative to Phase130.

High lag-1 autocorrelation remains diagnostic review evidence rather than an implementation
failure. The goal is good enough MCMC confirmation for article-facing quantile-grid validation,
not independent sampling.

## Interpretation

If Phase132 confirms the Phase131 result, the repaired Joint exQDESN exAL-RHS MCMC packet should
be consolidated as:

- Phase129 for the six already acceptable scenarios;
- Phase130 for `student_t_location_scale`;
- Phase132 for `nonlinear_reservoir_friendly`.

If Phase132 does not confirm the Phase131 result, the next step should not be more burn-in or
blind thinning. The next algorithmic step should be a joint gamma-sigma update for each tau,
because the remaining pathology is a local gamma/sigma ridge.

Phase132 does not mutate article tables or figures.
