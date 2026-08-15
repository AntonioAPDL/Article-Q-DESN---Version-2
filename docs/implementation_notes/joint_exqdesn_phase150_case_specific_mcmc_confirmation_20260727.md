# Joint exQDESN Phase150 Case-Specific MCMC Confirmation

Date: 2026-07-27

## Purpose

Phase149 completed the case-specific Joint exQDESN VB/VB-LD screen over the
eight formal synthetic scenarios.  The screen passed implementation gates and
selected one primary candidate per scenario, but the performance gains over the
previous exAL VB reference were modest for most cases.  Phase150 is therefore an
MCMC confirmation layer, not an article-promotion layer.

The goal is to answer a narrower question:

> If each scenario uses its own best Phase149 exAL VB specification, does
> VB-initialized MCMC recover enough forecast accuracy and diagnostic stability
> to justify revisiting the article-facing exQDESN rows?

## Source Evidence

Phase150 consumes:

- Phase149 screening:
  `application/cache/joint_qdesn_phase149_case_specific_exal_screening_20260726`
- Phase149 readiness registry:
  `application/cache/joint_qdesn_phase149_case_specific_exal_screening_readiness_20260726`
- Phase149 result audit:
  `application/cache/joint_qdesn_phase149_case_specific_exal_screening_20260726/phase149_result_audit`
- Formal simulation fixtures:
  `application/cache/joint_qdesn_simulation_dgp_fixtures_20260706`

The Phase149 finalizer observed 96/96 fit runs and 96/96 forecast runs.  The
result audit passed with zero hard-fail candidates and selected eight
scenario-specific primary winners.  Phase150 preserves the no-global-spec
interpretation.

## Freeze Contract

The new helper
`application/R/joint_exqdesn_phase150_case_specific_mcmc_confirmation.R`
rewrites the selected Phase149 winners into the existing Phase121 case-winner
schema:

- `case_winner_controls.csv`
- `case_winner_metric_summary.csv`
- `case_winner_gate_audit.csv`
- `artifact_manifest.csv`

This lets the existing Phase122 MCMC runner execute unchanged.  The sampler,
scoring, raw/contract quantile policy, chain diagnostics, and artifact manifest
contract remain inherited from Phase122.

Phase150 freezes one primary Joint exQDESN RHS candidate per scenario.  It does
not freeze a single global specification.

## MCMC Launch Controls

The default overnight confirmation is:

```bash
application/scripts/166_launch_joint_exqdesn_phase150_case_specific_mcmc_confirmation.sh --execute
```

Default controls:

- 8 scenarios
- Joint exQDESN RHS only
- 8 MCMC chains per scenario
- 8000 iterations per chain
- 2000 burn-in iterations
- thinning by 4
- 8 case workers in parallel
- VB initialization from the frozen case-specific Phase149 controls
- no raw `.RData` retention

These controls are intentionally stronger than the article-smoke MCMC runs while
remaining bounded enough for an overnight shared-machine launch.

## Gates

Hard fail:

- missing or mismatched Phase149/Phase150 manifests;
- fewer or more than one selected primary candidate per scenario;
- duplicated selected case ids;
- nonfinite selected Phase149 metrics;
- any selected Phase149 contract crossing;
- any Phase122 MCMC hard failure after launch.

Review:

- selected Phase149 raw crossings;
- selected Phase149 VB max-iteration flags;
- MCMC raw crossings before the monotone contract;
- large monotone adjustments;
- large VB/MCMC or chain-to-pooled distances.

Pass:

- all source manifests verify;
- exactly eight case-specific winners are frozen;
- all selected candidates are finite and contract-noncrossing;
- MCMC confirmation completes with finite draws and contract-noncrossing
  quantile grids.

## Outputs

Freeze artifact:

`application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727`

MCMC output:

`application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727`

Orchestration/log output:

`application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727_orchestration`

If the MCMC run exits successfully, the launcher also runs:

```bash
Rscript application/scripts/167_audit_joint_exqdesn_phase150_case_specific_mcmc_confirmation.R
```

The post-MCMC audit compares Phase150 case-specific exAL MCMC against the current
article balanced MCMC scenario table when available.  It does not modify article
assets.

## Lifecycle And Safe Resumption

Phase150 now has an explicit lifecycle check:

```bash
Rscript application/scripts/168_finalize_joint_exqdesn_phase150_case_specific_mcmc_confirmation.R
```

The command classifies the run as `running`, `interrupted_or_stale`, `failed`,
`completed_missing_mcmc_artifacts`, `completed_audit_in_progress`,
`completed_pending_audit`, or `complete`.  It writes a compact mutable health
snapshot to the orchestration directory.

The finalizer never restarts, stops, or overwrites an active MCMC run.  While
the run is active its only recommendation is to preserve the computation.  If
the MCMC process exits successfully but the automatic audit handoff is missing,
the finalizer runs only the post-MCMC audit against the completed artifacts.
An active automatic audit is detected and preserved, preventing a duplicate
audit race after the MCMC exit marker is written.
Interrupted or failed runs require log diagnosis and explicit authorization
before any relaunch.

## Interpretation

Phase150 should not be promoted directly into the manuscript.  It is a
confirmation experiment.  Article updates are appropriate only after the MCMC
output and audit show that the case-specific exAL rows improve or match the
existing article evidence under the quantile-grid validation contract.

If Phase150 still leaves exAL materially behind AL, the next useful direction is
not another small RHS/tau0 tweak.  The stronger next step would be a real
scenario-specific design/reservoir screen, because Phase149 varied readout,
RHS, fan, initialization, and VB controls over the frozen formal design matrix.
