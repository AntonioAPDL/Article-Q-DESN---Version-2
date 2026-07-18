# Joint exQDESN Phase139 Long-Chain Synthesis

## Purpose

Phase139 audits the completed Phase138 selected long-chain confirmation for the
joint exQDESN validation lane. It is a synthesis and decision layer, not a new
MCMC launch.

The immediate motivation is that Phase138 completed cleanly but did not close
the performance gap between exAL and matched AL specifications. Longer chains
improved gamma effective sample sizes, and the selected rows remained
noncrossing, but forecast MAE did not materially improve enough to promote exAL
as the article-facing winner.

## Inputs

Phase139 consumes existing, frozen artifacts:

- Phase135 matched exAL readiness and screening audit;
- Phase136 gamma-kernel packet;
- Phase137 selected-kernel readiness plan;
- Phase138 selected long-chain bounded and logit confirmation packets;
- Phase138 orchestration logs and exit files.

The default artifact paths are encoded in
`application/R/joint_exqdesn_phase139_long_chain_synthesis.R` and exposed by
`application/scripts/148_audit_joint_exqdesn_phase139_long_chain_synthesis.R`.

## Outputs

The default output directory is:

```text
application/cache/joint_qdesn_phase139_exal_long_chain_synthesis_20260717
```

The audit writes:

- `run_config.csv`;
- `phase139_source_manifest_audit.csv`;
- `phase139_health_summary.csv`;
- `phase139_phase138_case_summary.csv`;
- `phase139_phase138_vs_phase136.csv`;
- `phase139_exal_vs_matched_al.csv`;
- `phase139_sampler_diagnostic_summary.csv`;
- `phase139_next_model_redesign_plan.csv`;
- `phase139_decision_summary.csv`;
- `provenance.csv`;
- `README.md`;
- `artifact_manifest.csv`.

## Gates

Hard failures are reserved for implementation and reproducibility problems:
missing artifacts, failed scheduler or group exits, worker failures, nonfinite
metrics, or contract quantile crossings.

Review status is used for:

- figure-only manifest path repairs;
- high gamma autocorrelation;
- review-level Rhat;
- exAL rows that remain worse than matched AL on forecast MAE.

The article promotion gate only passes if the implementation gates are clean and
the selected exAL MCMC rows are competitive with matched AL under the declared
quantile-grid metrics.

## Interpretation Policy

Phase139 keeps the validation interpretation aligned with the corrected
predictive contract: the joint AL/exAL likelihood is a working likelihood for
quantile-path inference. The audit therefore compares quantile-grid metrics,
including fit and forecast oracle quantile MAE, check loss, and raw/contract
crossing diagnostics. It does not claim validation of a scalar posterior
predictive density.

## Expected Decision

Given the current Phase138 evidence, the expected decision is:

```text
review_do_not_promote_exal_as_article_winner
```

This means the implementation is clean enough to study, but the current exAL
specifications should not replace Joint QDESN RHS under AL as the primary
article anchor.

## Recommended Next Stage

Do not rerun the same exAL specifications with only more brute-force MCMC
iterations. If exAL remains a priority, run a targeted model-design experiment:

1. gamma fixed or near-AL sensitivity;
2. stronger gamma shrinkage prior;
3. centered or constrained gamma parameterization;
4. only then, case-specific exAL specification refinement.

These experiments should be launched only after Phase139 is reviewed and should
remain separate from article table promotion until they are audited and
manifested.

## Verification

Focused test:

```bash
Rscript application/tests/test_joint_exqdesn_phase139_long_chain_synthesis.R
```

Real artifact generation:

```bash
Rscript application/scripts/148_audit_joint_exqdesn_phase139_long_chain_synthesis.R
```
