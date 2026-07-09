# PriceFM DE_LU Fold 2/3 Next Feature-Geometry Plan

Date: 2026-06-04

## Purpose

This note refines the next PriceFM modeling plan after the completed
`DE_LU` fold 2/3 deep targeted median grid. The objective is to avoid another
expensive broad search and instead focus on the most diagnostic, reproducible,
and implementation-ready steps.

Current authoritative median registry for folds 2 and 3:

```text
application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_selection_registry_20260602/
```

Most recent completed deep-grid diagnostics:

```text
application/data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_p2_diagnostics_20260603/
```

Current tracked results note:

```text
docs/implementation_notes/pricefm_de_lu_folds23_deep_targeted_grid_results_20260603.md
```

Phase A diagnostics were implemented and run after this plan was written. The
authoritative follow-up note is:

```text
docs/implementation_notes/pricefm_de_lu_folds23_feature_geometry_diagnostics_20260604.md
```

The subsequent horizon-block materialization and seed-robustness preparation
stage is documented here:

```text
docs/implementation_notes/pricefm_de_lu_folds23_horizon_block_materialization_seed_stage_20260604.md
```

Key Phase A decision:

- keep the previous fold 2/3 median registry authoritative;
- do not relaunch P2 flat/window projection grids yet;
- treat horizon-block specialization as promising for fold 2 only, pending a
  controlled promotion materializer and seed robustness;
- prioritize feature-map engineering and seed robustness over another broad
  random reservoir sweep.

## Current Evidence

The completed P0/P1/P2 grid did not improve the previous fold-specific median
registry.

| Fold | Retained Val AQL | Retained Test AQL | New Val AQL | New Test AQL | Decision |
|---:|---:|---:|---:|---:|---|
| 2 | 6.181033 | 7.017320 | 6.194532 | 7.033291 | Retain previous |
| 3 | 6.765381 | 8.559254 | 6.798915 | 8.583866 | Retain previous |

The P2 feature diagnostics were strongly negative:

| Fold | P2 pattern | Best validation AQL | Baseline retained AQL | Read |
|---:|---|---:|---:|---|
| 2 | optional window DESN projection | 9.849500 | 6.181033 | Not competitive |
| 2 | direct flat lag window | 10.783741 | 6.181033 | Not competitive |
| 3 | optional window DESN projection | 10.222126 | 6.765381 | Not competitive |

The new local winners improved early horizons but worsened enough later horizons
to lose the fold-level criterion:

| Fold | Horizon group | New minus retained AQL |
|---:|---|---:|
| 2 | 1-24 | -0.149838 |
| 2 | 25-48 | 0.202053 |
| 3 | 1-24 | -0.303888 |
| 3 | 49-72 | 0.264550 |

The seven-quantile context still has local PriceFM Phase-I ahead on folds 2 and
3:

| Fold | PriceFM AQL | Q-DESN exAL RHS_NS AQL | Gap |
|---:|---:|---:|---:|
| 2 | 5.355079 | 5.627840 | 0.272761 |
| 3 | 6.029767 | 7.015117 | 0.985350 |

## Deep Assessment By Candidate Move

### 1. Keep The Previous Median Registry Authoritative

Assessment: optimal and already justified.

Evidence:

- Both new P0/P1/P2 validation winners are worse than the previous registry.
- Test audit agrees with the validation decision.
- The previous registry is already wired into the seven-quantile comparison
  workflow.

Implementation status:

- No new code is needed.
- Future scripts should treat this registry as the baseline to beat.

Stop condition:

- Do not promote any new fold 2/3 median registry unless it beats the retained
  registry on validation AQL. Test remains audit-only.

### 2. Do Not Launch Another Broad `alpha/rho/n/L` Sweep Yet

Assessment: optimal.

Evidence:

- The P1 surface already covered short contexts, capacity, alpha, rho,
  input_scale, tau0, depth, and one seed refresh.
- The best new candidates are close but still worse than retained.
- Tau0 variation was weak or neutral.
- D2 and broader capacity did not produce a clear path.

Risk of ignoring this:

- Another broad grid would spend most time rediscovering that local geometry is
  not the bottleneck.

Better replacement:

- Run feature diagnostics and horizon-specialist diagnostics first.

### 3. Feature-Geometry Audit Before More Feature-Map Experiments

Assessment: highest-value next implementation step.

Why this is necessary:

- `flat_direct` and `window_desn_v1` were much worse than the recurrent
  `window_reservoir_v1` map.
- This is too large a performance gap to treat as ordinary hyperparameter noise.
- The current artifact hygiene removes `X_*.csv`, so rank/condition diagnostics
  are not available after a normal run.

Current implementation facts:

- `window_reservoir_v1` computes a recurrent lag state and appends
  horizon-specific lead covariates plus horizon features.
- `window_desn_v1` applies a random tanh projection to the full raw lag/lead
  window.
- `flat_direct` uses the full raw lag/lead/horizon feature vector directly.
- `adapter_manifest.json` preserves split-level activation summaries.
- It does not preserve covariance, rank, condition, near-constant columns, or
  feature-response alignment summaries.

Recommended implementation:

Create a no-fit diagnostic script:

```text
application/scripts/pricefm/23_audit_desn_feature_geometry.py
```

Inputs:

- one or more generated full configs or run cell adapter directories;
- optional train-origin cap for diagnostics;
- `--splits train,val,test`;
- `--preserve-matrices false` by default.

Outputs under ignored local storage:

```text
application/data_local/pricefm/authoritative/pricefm_de_lu_folds23_feature_geometry_audit_YYYYMMDD/
```

Required outputs:

- `feature_geometry_summary.csv`
- `feature_split_drift.csv`
- `feature_rank_condition_summary.csv`
- `feature_response_alignment.csv`
- `activation_summary.csv`
- `horizon_alignment_summary.csv`
- `feature_geometry_report.md`
- optional figures:
  - feature standard deviation distribution;
  - condition/effective-rank by method;
  - train/val/test drift;
  - horizon-feature alignment.

Metrics:

- rows, origins, horizons, feature count;
- raw dimension versus stored feature dimension;
- approximate rank or effective rank from singular values;
- condition number on centered/scaled diagnostic matrices;
- near-zero variance columns;
- high-correlation column counts;
- train-to-val/test feature mean and scale drift;
- activation pre-tanh mean, sd, max, min, and saturation fractions;
- train-only feature-response correlations by horizon group.

Reproducibility checks:

- record config path, feature map, seed, fold, region, lag window, horizon set;
- record matrix SHA when a temporary matrix is materialized;
- delete temporary matrices unless `--keep-matrices true`;
- never use test to select a model.

Tests:

- synthetic matrix with known rank/condition;
- deterministic repeated audit with fixed seed;
- failure for missing manifests/configs;
- matrix cleanup test;
- no-leakage check: feature-response alignment may report test values but must
  not mark them as selection evidence.

Decision criterion:

- If P2 maps are low-rank, poorly conditioned, highly drifted, or weakly aligned
  with the response, do not relaunch P2. Fix the feature construction first.

### 4. Horizon-Specific Diagnostics Before Horizon-Specific Models

Assessment: high value, should run after or alongside the feature audit.

Evidence:

- New candidates improve horizons 1-24 but harm 25-96.
- This suggests the problem may not have one globally best median model per
  fold.

Recommended implementation:

Create a no-refit diagnostic/selector:

```text
application/scripts/pricefm/24_select_median_horizon_blocks.py
```

Scope:

- Use existing completed median candidate outputs.
- Select by validation AQL within horizon blocks.
- Report test metrics as audit only.
- Keep candidate pool restricted to completed cells with matching region/fold,
  quantile, horizons, and row identity.

Candidate horizon blocks:

```text
1-24, 25-48, 49-72, 73-96
```

Outputs:

- `horizon_block_selection.csv`
- `horizon_block_test_audit.csv`
- `horizon_block_composite_metrics.csv`
- `horizon_block_selection_report.md`
- figures comparing retained global model versus horizon-block composite.

Important rule:

- A horizon-block composite is a target/workflow selection rule, not a new VB
  mode.

Tests:

- validation-only selection test;
- duplicate/missing horizon failure;
- row identity consistency test;
- test metrics cannot influence selected block;
- deterministic tie-breaking.

Decision criterion:

- If validation-selected horizon blocks beat the retained global model and test
  audit does not show obvious overfitting, then implement a paper-quantile
  promotion path that can use horizon-block specialists.

### 5. Seed Robustness Around Retained And Local Alternatives

Assessment: useful but only after the no-fit diagnostics.

Evidence:

- The previous retained specs use seed `20260601`.
- The deep grid reran nearby geometries mostly with seed `20260603`, and the
  anchor reruns were weaker.
- Seed variability may be larger than the small local hyperparameter gains.

Recommended focused seed grid:

Fold 2:

- retained: `L=72`, `n=120`, `alpha=0.50`, `rho=0.90`,
  `input_scale=0.50`;
- local short-horizon repair: `L=96`, `n=120`, `rho=0.90`,
  `input_scale=0.25`;
- close local alternative: `L=72`, `n=120`, `rho=0.90`,
  `input_scale=0.25`.

Fold 3:

- retained: `L=96`, `n=80`, `alpha=0.50`, `rho=0.90`,
  `input_scale=0.50`;
- local short-horizon repair: `L=96`, `n=80`, `rho=0.97`,
  `input_scale=0.35`;
- close local alternative: `L=72`, `n=80`, `rho=0.97`,
  `input_scale=0.35`.

Seeds:

```text
20260601, 20260602, 20260603, 20260604, 20260605
```

Selection:

- validation mean AQL and validation worst-case AQL across seeds;
- test remains audit-only;
- report seed standard deviation and whether a geometry is robust or fragile.

Why this beats a broad grid:

- It directly tests whether the current winners are stable.
- It is cheaper than exploring unrelated geometry.
- It can explain why the `20260601` retained registry remains stronger than
  nearby `20260603` reruns.

### 6. Feature Engineering Instead Of More Random Capacity

Assessment: likely the main path after diagnostics.

Evidence:

- Direct flat and random window projections are weak.
- Recurrent D1 features are better, but still trail PriceFM on folds 2 and 3.
- Horizon-specific gaps suggest missing structured covariates or regime
  information rather than raw capacity alone.

Candidate feature additions, in priority order:

1. Multi-scale lag summaries from the target-region lag window:
   - recent price deltas;
   - rolling mean over 1h, 6h, 24h;
   - rolling min/max;
   - volatility or median absolute deviation;
   - slope over recent windows.
2. Calendar and response-time features:
   - hour of day;
   - day of week;
   - weekend/weekday;
   - month or season;
   - response-time rather than only origin-time features.
3. Horizon-group interactions:
   - allow separate intercept-like or scale-like terms by horizon group;
   - avoid full per-horizon explosion unless validation supports it.
4. Regime features:
   - high/low recent price regime;
   - high load or renewable penetration regime.

No-leakage rule:

- Lag summaries may use only lag-window values.
- Lead covariates may use only known lead features already available in the
  PriceFM input window.
- Response price must never enter features for the response horizon.

Implementation approach:

- Add feature-map variants, not ad hoc grid hacks.
- Keep old `window_reservoir_v1` unchanged.
- Suggested names:
  - `window_reservoir_multiscale_v1`;
  - `window_reservoir_calendar_v1`;
  - `window_reservoir_multiscale_calendar_v1`.

Tests:

- feature dimensions deterministic;
- no-future-leakage on synthetic windows;
- feature manifest records all added feature families;
- generated configs include exact feature-map name and SHA;
- old grids remain unchanged.

### 7. Paper Quantile Promotion Only After Median Stability

Assessment: optimal to defer.

Evidence:

- The median registry controls the promoted seven-quantile run.
- Fold 2/3 PriceFM gaps are already known.
- Promoting unstable median specs to all quantiles would multiply compute
  without solving the selection problem.

Next promotion gate:

- Median validation registry beats retained or horizon-block selector is
  validated.
- Diagnostics explain why the new feature family is structurally better.
- Quantile grid materialization remains registry-driven.

### 8. Do Not Expand To More Regions Yet

Assessment: optimal.

Evidence:

- `DE_LU` fold 3 remains the largest current gap.
- More regions would test data diversity, but would not explain the current
  feature problem.

Revisit when:

- feature diagnostics are stable;
- region/fold median registry selection framework is finalized;
- a second region can be used as a transfer check without changing the model
  midstream.

## Recommended Overall Sequence

### Phase A: No-Fit Diagnostics

Implement and run:

```text
application/scripts/pricefm/23_audit_desn_feature_geometry.py
application/scripts/pricefm/24_select_median_horizon_blocks.py
```

Use completed outputs only. Do not fit new models.

Pass criteria:

- feature audit explains or falsifies the P2 failure;
- horizon-block diagnostics show whether specialists are worth implementing;
- no-leakage and deterministic tests pass.

Status: complete. See
`docs/implementation_notes/pricefm_de_lu_folds23_feature_geometry_diagnostics_20260604.md`.

### Phase B: Small Seed Robustness Grid

Only after Phase A, run a focused seed grid around retained and local
alternatives.

Pass criteria:

- selected geometry is robust across seeds or seed variability is explicitly
  recorded;
- no validation-selected candidate worsens the retained registry;
- no test-driven promotion.

### Phase C: Feature-Map Upgrade

Only if Phase A indicates missing feature structure, implement a small
feature-map extension.

Recommended first extension:

```text
window_reservoir_multiscale_calendar_v1
```

Do not change old feature maps. Add tests and a tiny no-fit manifest smoke
before launching any grid.

### Phase D: Median Registry Refresh

Run a small validation-selected median grid with the new feature map.

Promote only if validation AQL beats the retained registry.

### Phase E: Seven-Quantile Paper Run

Materialize and run the seven PriceFM paper quantiles only after a stable median
registry exists.

## What Not To Do Next

- Do not run another broad random `alpha/rho/n/L` grid.
- Do not rerun P2 large flat/window projections without a feature-geometry
  explanation.
- Do not select on test metrics.
- Do not broaden to all regions before closing the fold 2/3 feature question.
- Do not change the PriceFM data pipeline unless a no-leakage feature audit
  requires a formal feature-map extension.

## Immediate Next Task After Phase A

Do not launch another broad grid yet. The next implementation step was a small
horizon-block promotion materializer plus seed-robustness grid design:

1. materialize validation-selected horizon-block predictions from completed
   candidate outputs, with strict row and horizon coverage checks;
2. keep test metrics audit-only;
3. run seed robustness around the retained global winners and the Phase A
   horizon-block winners;
4. promote only if validation improves and test audit does not show obvious
   overfitting.

This remains the most efficient next move because Phase A used the completed
15 GB run as evidence and showed that the next gain is more likely to come from
horizon structure and robust feature engineering than from larger random
projection capacity.

Status: complete. The next open decision is whether to launch the prepared
50-cell median seed-robustness grid.
