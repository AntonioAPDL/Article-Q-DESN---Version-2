# Joint exQDESN Phase133 performance-first audit

Date: 2026-07-14

## Purpose

Phase133 formalizes the next decision point for the joint QDESN validation study after the Phase129--132 Joint exQDESN exAL-RHS sampler diagnostics. The key methodological correction is that gamma/tau/sigma mixing is not the primary scientific objective. The primary objective is strong quantile-grid validation performance:

- oracle fit and forecast quantile MAE/RMSE;
- check loss;
- grid CRPS;
- hit-rate and interval-coverage diagnostics;
- raw and contract crossing diagnostics;
- chain-level stability of the posterior quantile grid.

Parameter-level gamma/tau/sigma diagnostics remain important, but they are support diagnostics unless they destabilize the posterior quantile grid or degrade the validation metrics.

## Implementation

The new script is:

```bash
Rscript application/scripts/138_audit_joint_exqdesn_performance_first_phase133.R
```

Default output:

```text
application/cache/joint_qdesn_phase133_performance_first_audit_20260714
```

The script is read-only with respect to prior validation artifacts. It consumes:

- Phase125 balanced MCMC audit;
- Phase126 article assets;
- Phase129 full eight-case Joint exQDESN width-4 diagnostics;
- Phase130 targeted long-chain diagnostics;
- Phase131 nonlinear sampler tuning;
- Phase132 nonlinear tau-0.25 width-8 long confirmation.

It verifies each source artifact manifest, merges the article-facing performance summaries with the sampler diagnostics, and writes a reproducible priority table and next-experiment plan.

## Generated artifacts

- `run_config.csv`
- `source_manifest_audit.csv`
- `joint_exqdesn_model_performance_context.csv`
- `joint_exqdesn_performance_gap_audit.csv`
- `joint_exqdesn_sampler_vs_qhat_stability_audit.csv`
- `joint_exqdesn_latest_sampler_state.csv`
- `joint_exqdesn_scenario_priority_table.csv`
- `joint_exqdesn_stage_decision_matrix.csv`
- `posterior_summary_sensitivity_readiness.csv`
- `phase132_replacement_readiness.csv`
- `joint_exqdesn_next_experiment_plan.csv`
- `audit_assessment.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

## Main findings

The Phase133 default run completed with:

- implementation gate: `pass`;
- audit gate: `review`;
- source manifests verified for Phases 125, 126, 129, 130, 131, and 132;
- five large Joint exQDESN forecast-MAE gaps.

The high-priority scenarios are:

1. `regime_shift`;
2. `nonlinear_reservoir_friendly`;
3. `normal_bridge`;
4. `student_t_location_scale`;
5. `laplace_bridge`.

Only `nonlinear_reservoir_friendly` is currently both a large performance-gap case and a sampler-ridge case. The other large-gap scenarios mostly show small qhat distances and acceptable chain-level qhat stability despite gamma-level review diagnostics. This means the next broad campaign should focus on exAL specification and posterior-summary sensitivity, not only on sampler mechanics.

## Phase132 interpretation

Phase132 improved the nonlinear tau-0.25 gamma/sigma ridge but did not fully solve it. It is still useful, but it cannot replace article-facing metrics by itself because it is a sampler-diagnostic packet and does not contain full fit/forecast score tables. The required next step for any Phase132 promotion is a scored MCMC confirmation or a runner extension that emits the needed qhat and scoring summaries.

## Gate policy

Hard fail remains reserved for:

- missing or failing source hashes;
- failed workers;
- nonfinite outputs;
- contract quantile crossings;
- train/test leakage;
- missing provenance or manifest outputs.

Review is appropriate for:

- large forecast-MAE gaps;
- missing posterior qhat summary sensitivity;
- gamma/tau/sigma Rhat issues that do not destabilize qhat;
- sampler geometry that is costly but not invalidating.

Promotion should require:

- implementation gates pass;
- quantile-grid scores are competitive;
- qhat chain-to-pooled and VB-to-MCMC distances are acceptable;
- contract crossings remain zero;
- the selected model/specification is recorded with seeds, controls, manifests, and provenance.

## Recommended next stage

The next implementation should be Phase133B:

1. Extend the MCMC confirmation workflow to emit compact posterior qhat summary diagnostics, preferably without retaining large `.RData` files.
2. Compute posterior mean, median, and trimmed-mean qhat summaries for the high-priority scenarios.
3. Re-score fit and forecast windows under these qhat summaries.
4. Use the result to decide whether each large-gap scenario needs:
   - posterior-summary promotion;
   - exAL specification calibration;
   - sampler-geometry experiments;
   - or some combination of these.

No article tables or manuscript text should be updated until a scored, manifest-audited balanced MCMC packet exists.

