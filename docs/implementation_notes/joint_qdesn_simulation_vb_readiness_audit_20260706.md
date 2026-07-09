# Joint QDESN Simulation VB-First Readiness Audit

Date: 2026-07-06

This note documents the readiness layer added before launching the new
12000-length joint QDESN simulation fixtures. The purpose is deliberately
narrow: verify that the VB implementation paths, model labels, independent
comparators, raw/contract quantile policy, oracle policy, and artifact contract
are ready for the next implementation stage.

This is not final validation evidence and it does not launch the long fixture
generation.

## Scope

The audit is implemented in:

- `application/R/joint_qdesn_simulation_readiness.R`
- `application/scripts/97_run_joint_qdesn_simulation_vb_readiness_audit.R`
- `application/tests/test_joint_qdesn_simulation_vb_readiness_audit.R`

The default artifact directory is:

`application/cache/joint_qdesn_simulation_vb_readiness_audit_20260706`

## Models Checked

The readiness audit executes a small deterministic toy fixture and checks:

| Display label | Likelihood | Structure | Inference |
|---|---|---|---|
| `JOINT QDESN RHS` | AL | joint quantile vector | VB |
| `JOINT exQDESN RHS` | exAL | joint quantile vector | VB-LD |
| `QDESN RHS` | AL | independent single-tau fits | VB |
| `exQDESN RHS` | exAL | independent single-tau fits | VB-LD |

The independent comparators are assembled from one K=1 fit per tau. Their raw
quantile vectors are then passed through the same monotone contract used by the
joint outputs. This confirms the K=1 reduction and the comparator interface
before any article-scale runs are started.

## Raw and Contract Quantiles

The audit preserves the distinction between:

- raw output: direct fitted quantiles from the VB model; and
- contract output: monotone quantiles after the declared isotonic/rearrangement
  step.

Scoring in the future validation study should use the contract output, but the
raw crossing and adjustment diagnostics must remain visible. Raw crossings or
large adjustments are review signals. Contract crossings are implementation
failures.

## Gates

Hard fail:

- missing model path;
- nonfinite fitted quantiles;
- nonfinite or nonpositive scale summaries;
- nonfinite exAL gamma summaries;
- missing or nonfinite VB traces;
- missing or nonfinite RHS prior summaries;
- contract quantile crossings;
- incomplete artifact manifest.

Review:

- bounded readiness run reaches the VB iteration cap;
- raw quantile output requires monotone repair;
- monotone adjustment exceeds the declared review threshold.

Pass:

- all implementation, finiteness, RHS-prior, K=1, oracle-policy, design, and
  manifest gates pass.

## Artifacts

The audit writes:

- `run_config.csv`
- `readiness_checklist.csv`
- `toy_fixture_summary.csv`
- `model_scope_readiness.csv`
- `raw_contract_quantile_diagnostics.csv`
- `k1_reduction_readiness.csv`
- `oracle_policy_readiness.csv`
- `simulation_design_readiness.csv`
- `launch_blockers.csv`
- `next_phase_plan.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

Every artifact is inspectable and hashed with SHA-256 in
`artifact_manifest.csv`.

## Next Stage

If the readiness audit has no hard failures, the next implementation stage is
to build the long-series fixture registry and VB validation runners:

1. Freeze realistic VB controls.
2. Materialize the 12000-length DGP fixtures with 2000 DGP warmup, 500 DESN
   washout, 500 fit rows, and 1000 validation rows.
3. Materialize oracle quantiles once per DGP, with seed roles and hashes.
4. Run VB fit validation for `JOINT QDESN RHS`, `JOINT exQDESN RHS`,
   `QDESN RHS`, and `exQDESN RHS`.
5. Run no-refit lead 1--30 forecast validation with raw and contract quantile
   outputs.
6. Introduce MCMC references only after the VB stage is stable.
