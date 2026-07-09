# Normal DESN And Q-DESN Alignment Audit

Date: 2026-05-29

## Purpose

This note records the alignment state after the parallel Q-DESN extended-mode
chat landed package commit `f0d45ea` and the Normal DESN warm-start stage
landed through package commit `9f1c32d`. It is a comparison-readiness audit
across the Normal DESN Gaussian readout tools and the Q-DESN AL/exAL readout
tools.

The goal is not to force every model into every workflow. The goal is to make
sure shared capabilities are coherent where they should be shared, and clearly
labeled where a capability is model-specific, approximate, target-changing, or
not meaningful for a closed-form Normal ridge fit.

## Sources Inspected

Local Codex session log:

```text
/home/jaguir26/.codex/sessions/2026/05/27/rollout-2026-05-27T00-12-52-019e67a2-a40d-7d50-b712-a594b5254a68.jsonl
```

Broader Codex SQLite log store:

```text
/home/jaguir26/.codex/logs_2.sqlite
```

The SQLite store contains a `logs` table with timestamped internal log rows.
The session JSONL is the readable record of the user-facing implementation
reports for this workstream.

## Current Repo State

Package repo:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
branch: validation/shared-fitforecast-v2-1.0.0
HEAD: 9f1c32d Cover RHS Normal warm-start labels
state: clean and aligned with origin
```

Article repo:

```text
/data/jaguir26/local/src/Article-Q-DESN
branch: application-ensemble-likelihood-redesign
HEAD: 8a2135e Document extended Q-DESN VB mode gates
```

The article worktree also contains untracked GloFAS memory-refinement configs
and scripts. Those are treated as unrelated ongoing application-run artifacts
and are not part of this alignment audit.

## Recent Q-DESN Achievements

The session log and committed docs show the following progression:

- exact chunked full-data VB was implemented and validated for package
  AL/exAL and article latent-path AL fixed historical rows;
- stochastic mini-batch AL was implemented and labeled approximate;
- hybrid AL was implemented;
- warm-start API was implemented for Q-DESN VB states;
- rolling-window AL ridge refits were implemented;
- posterior-as-prior AL ridge beta handoff was implemented;
- canonical AL ridge online state-handoff wrapper was implemented;
- fixed subset and stratified subset AL ridge target modes were implemented;
- response-quantile and design-leverage stratified subset modes were added;
- diagonal covariance was implemented for AL ridge and AL RHS/RHS_NS;
- hybrid exAL was extended to ridge, RHS, and RHS_NS;
- exAL ridge diagonal covariance was reopened and supported as a diagnostic
  covariance approximation;
- pure stochastic exAL remains forbidden;
- exAL RHS/RHS_NS diagonal covariance remains forbidden.

The latest Q-DESN extended-mode source gate ran 35 methods and passed all 15
exact equivalence gates. The largest exact-gate absolute difference was
`1.638e-04`; the largest relative difference was `3.181e-08`.

## Current Normal DESN Achievements

The Normal DESN side currently supports:

- `normal_desn_fit()`;
- `qdesn_fit_normal()`;
- exact scaled-ridge Normal-inverse-gamma readout;
- exact chunked scaled-ridge Normal readout;
- approximate RHS/RHS_NS Normal VB readout;
- posterior draws and posterior predictive draws;
- narrow recursive forecast paths for reservoir-only raw-y-lag settings;
- Normal-to-Q-DESN VB initialization;
- Normal-to-Q-DESN MCMC initialization;
- serialized Normal DESN warm-start states with validation;
- Normal warm-start conversion to AL/exAL VB and MCMC initializers;
- source-median and initialization comparison harnesses.

Normal scaled ridge is closed form, so stochastic/hybrid VB batching is not
needed for that mode. Exact chunking is still useful as a memory/layout
equivalence tool. RHS/RHS_NS Normal VB is approximate and global-shrinkage
based, but currently does not have exact chunking or stochastic/hybrid batching.

## Feature Alignment Matrix

| Capability | Q-DESN AL ridge | Q-DESN AL RHS/RHS_NS | Q-DESN exAL ridge | Q-DESN exAL RHS/RHS_NS | Normal ridge | Normal RHS/RHS_NS |
|---|---|---|---|---|---|---|
| Full-data fit | implemented | implemented | implemented | implemented | implemented exact | implemented approximate VB |
| Exact chunked fit | implemented | implemented | implemented | implemented | implemented | gated |
| Stochastic mini-batch | implemented approximate | supported only where RHS global semantics are tested | forbidden | forbidden | not needed | gated |
| Hybrid refresh | implemented approximate | implemented approximate | implemented approximate | implemented approximate | not needed | gated |
| Diagonal covariance | implemented | implemented | implemented diagnostic, not recommended default | gated | not applicable to exact full covariance target | gated |
| Low-rank covariance | gated | gated | gated | gated | gated/not priority | gated |
| Warm-start metadata | implemented Q-DESN VB state | implemented Q-DESN VB state | implemented Q-DESN VB state | implemented Q-DESN VB state | implemented Normal state | implemented Normal state, approximate-labeled |
| Normal-to-Q-DESN init | can receive | can receive | can receive | can receive | source | source |
| Rolling refits | AL ridge only | gated | gated | gated | gated | gated |
| Posterior-as-prior | AL ridge only | gated | gated | gated | gated | gated |
| Online wrapper | AL ridge only | gated | gated | gated | gated | gated |
| Fixed subset target | implemented | gated | gated | gated | gated | gated |
| Stratified subset target | implemented | gated | gated | gated | gated | gated |
| Response/leverage subset | implemented | gated | gated | gated | gated | gated |
| Forecast paths | implemented | implemented through fitted readout | implemented | implemented through fitted readout | implemented narrow | implemented through fitted readout draws only |

## Interpretation

The models should not be forced into artificial symmetry:

- Normal ridge is exact closed form. Stochastic/hybrid VB is unnecessary unless
  a future approximate Gaussian streaming algorithm is explicitly desired.
- Q-DESN AL/exAL are iterative VB targets, so exact chunking, stochastic,
  hybrid, covariance approximation, and target-changing subset methods are
  meaningful.
- RHS/RHS_NS states are global in both model families. They should not be
  naively row-batched.
- Normal DESN is currently most valuable as a comparison baseline and as an
  informed initializer for Q-DESN AL/exAL.

The main real alignment gap was therefore not stochastic Normal batching. That
gap is now closed by the formal Normal DESN warm-start metadata object with
validation and conversion helpers, so Normal fits can be safely serialized and
reused as initialization sources in unified comparisons.

## Required Updates Before Final Unified Comparison

1. Use package commit `9f1c32d` or later so Normal DESN warm-start metadata is
   available.

2. Update the unified comparison harness to include:

- Q-DESN AL response-quantile subset;
- Q-DESN AL design-leverage subset;
- Q-DESN exAL ridge diagonal covariance;
- Q-DESN exAL RHS/RHS_NS hybrid;
- clear exclusion of pure stochastic exAL and exAL RHS/RHS_NS diagonal
  covariance.

3. Run the final unified source-median comparison from a clean package HEAD.

## Recommended Next Stage

The next package/documentation stage should be:

```text
Run the final Normal/Q-DESN unified source-median comparison
```

The warm-start metadata stage has passed. The unified comparison should now be
run from a clean package HEAD and documented in:

```text
docs/implementation_notes/normal_qdesn_unified_source_median_comparison_20260529.md
```

The step-by-step implementation checklist is tracked in:

```text
docs/implementation_notes/normal_qdesn_regularization_checklist_20260529.md
```
