# PriceFM Stage-C Graph-Informed Next Plan

Date: 2026-06-19

This note is the next-step plan after the Stage-C Priority-1 green
seven-quantile closeout. It is a planning artifact, not a launch record. The
goal is to move from local-only DESN/Q-DESN candidates toward an apples-to-
apples comparison with PriceFM's spatial information set, while keeping the
workflow reproducible, storage-aware, and validation-clean.

## Current Evidence

The Stage-C Priority-1 green seven-quantile panel completed for `BE`, `NL`,
`SE_4`, and `SI` across folds 1, 2, and 3. It ran 84 local quantile fits and
produced 12 fold-aligned comparisons against cached PriceFM Phase-I
predictions.

Authoritative local-only decision counts:

| decision | count |
|---|---:|
| confirmed local win | 2 |
| close local loss | 3 |
| PriceFM fallback | 7 |

Original-unit test AQL over the same 12 region/fold rows:

| method | mean AQL |
|---|---:|
| PriceFM Phase-I pretraining | 7.150855 |
| Q-DESN AL RHS_NS exact chunked | 7.888203 |
| Q-DESN exAL RHS_NS exact chunked | 7.894583 |
| normal DESN RHS_NS | 9.206640 |
| normal DESN scaled ridge | 41.583257 |

The best local method per region/fold averaged `7.844993`, about `10.21%`
worse than PriceFM Phase-I. The local stack is therefore useful, but not yet a
panel-level replacement for PriceFM.

## Critical Assessment

### What Should Be Preserved

- Keep the two local wins frozen as local-only Stage-C candidates:
  - `BE` fold 1.
  - `SE_4` fold 2.
- Keep exact-chunked Q-DESN RHS_NS as the primary local quantile family.
- Keep normal DESN RHS_NS as a diagnostic baseline.
- Keep normal DESN scaled ridge out of promotion decisions.
- Keep local promotion region/fold-specific. A global winner is not supported.

### What Should Not Be Done Next

- Do not run another blind local-only reservoir hyperparameter sweep. The
  current failures are heterogeneous and horizon-dependent, not a simple global
  capacity miss.
- Do not promote validation-only rescue winners. The previous graph/local
  rescue closeout showed validation improvements can fail to transfer to the
  test audit.
- Do not immediately scale to all 38 regions and all quantiles. That would
  multiply storage and runtime before the feature-information question is
  settled.
- Do not use PriceFM test metrics to select models. PriceFM metrics may be used
  for audit and comparison only.

### Why Graph-Neighbor Inputs Are The Right Next Move

PriceFM uses a richer spatial information set than the current target-only
local DESN/Q-DESN runs. The repo already has graph-aware wiring:

- `application/scripts/pricefm/pricefm_desn_adapter.py` supports
  `feature_policy = "graph_khop"`.
- `application/scripts/pricefm/12_prepare_desn_experiment_grid.py` forwards
  `feature_policy` and `adapter.spatial` into generated configs.
- `application/scripts/pricefm/pricefm_graph.py` provides
  `graph_scope_manifest()`.
- Graph manifests record `input_scope`, `output_scope`,
  `lead_covariate_status`, and `spatial_information_set`.

Prior graph-neighbor median evidence is encouraging but not sufficient for
automatic promotion:

| artifact | key evidence |
|---|---|
| graph-neighbor median A/B registry | 18 cells completed, exact gates 18/18, 15/18 test improvements, mean test delta `-0.954242` |
| graph/local panel diagnostics | 9 selected cells beat PriceFM, 8 lagged, 1 was close |
| graph/local rescue closeout | validation-selected rescue worsened mean test AQL, so seed robustness and test-audit discipline are required |

The optimal next experiment is therefore a graph-informed median rescue for
the close/fallback rows, followed by seven-quantile promotion only for robust
median winners.

## Stage Plan

### Stage 0 - Hardening And Audit

Checklist:

- [ ] Verify git state before launching any new run.
- [ ] Verify the Stage-C local-only decision registry still matches the
      closeout note.
- [ ] Verify the PriceFM Phase-I cache is complete for all candidate
      region/fold rows.
- [ ] Verify graph manifests expose the intended regions for each target.
- [ ] Confirm `keep_matrices_after_success = false` is set in generated
      configs.
- [ ] Confirm graph runs record `feature_policy`, `input_scope`,
      `spatial_information_set`, `graph_degree`, and `lead_covariate_status`.
- [ ] Harden any panel wrapper that previously required direct per-region
      reruns, or document a direct fallback command before launching.

Acceptance criteria:

- No dirty code changes unrelated to this task.
- No missing PriceFM cached predictions.
- No generated heavy artifacts are staged for git.
- One dry-run graph config generation succeeds.

### Stage 1 - Median Graph Rescue Candidate Grid

Scope:

- Start with median only (`tau = 0.50`).
- Target the current Priority-1 green close/fallback rows:
  - `BE` folds 2 and 3.
  - `NL` folds 1, 2, and 3.
  - `SE_4` folds 1 and 3.
  - `SI` folds 1, 2, and 3.
- Optionally include the two confirmed local wins as graph diagnostics only,
  not as promotion prerequisites.

Candidate families:

- Current local winner geometry from the Stage-C registry.
- `feature_policy = graph_khop`, degree 1.
- Degree 2 only for rows where degree 1 is stable or where prior graph evidence
  suggests degree 2 is plausible.
- Q-DESN AL RHS_NS exact chunked and Q-DESN exAL RHS_NS exact chunked.
- Keep normal DESN RHS_NS as a diagnostic only if runtime remains manageable.

Focused knobs:

- Preserve the current winning lag/depth/units as the anchor.
- Vary `input_scale` around the current value, typically `0.75x`, `1.0x`, and
  `1.35x`, clipped to the established bounds.
- Vary `alpha` only by small local perturbations, for example `alpha +/- 0.10`.
- Avoid broad `rho`, `tau0`, or high-depth sweeps in this stage unless a row has
  a documented reason.

Selection rule:

- Select on validation AQL only.
- Treat test AQL as an audit metric.
- Require finite fits, complete prediction rows, and no row-alignment mismatch.

Acceptance criteria:

- Every exact-chunked gate passes.
- Every completed candidate records feature-policy metadata.
- Every row has a single validation-selected median candidate or an explicit
  no-promotion decision.
- Any candidate selected by validation but worse on test is marked as a
  validation-overfit warning, not promoted.

### Stage 2 - Seed Robustness For Median Candidates

Scope:

- Run seed robustness only for Stage 1 candidates that improve validation and
  do not show obvious test-audit failure.
- Use at least three additional seeds.
- Keep all model and graph settings fixed except seed.

Acceptance criteria:

- Median validation AQL is stable enough to justify quantile expansion.
- The same likelihood family is repeatedly competitive, or the instability is
  documented.
- Test audit does not show a large systematic degradation.

### Stage 3 - Seven-Quantile Graph Promotion

Scope:

- Run paper quantiles:
  `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`.
- Only run seven-quantile synthesis for region/folds that pass Stage 2.
- Keep the median-selected graph geometry fixed across quantiles.
- Use the same PriceFM cache and comparison scripts as Stage-C local-only.

Acceptance criteria:

- All quantile fits complete.
- Synthesis outputs exist for every promoted row.
- Row alignment has zero mismatches.
- Metrics are reported in original units.
- Decisions are frozen into:
  - promote graph-local candidate,
  - close graph-local loss,
  - PriceFM fallback.

### Stage 4 - Decision Registry And Documentation Freeze

Checklist:

- [ ] Create a graph-informed decision registry.
- [ ] Create promoted, close, and fallback registries.
- [ ] Create horizon-group diagnostics.
- [ ] Create a concise closeout note under `docs/implementation_notes`.
- [ ] Preserve generated CSV/figure artifacts under
      `application/data_local/pricefm/authoritative`.
- [ ] Commit only scripts, tests, config templates if tracked, and docs.

Acceptance criteria:

- The registry states whether each row uses target-only or graph-khop inputs.
- The registry states whether the selected candidate beats PriceFM Phase-I on
  the same fold and quantile grid.
- PriceFM remains the fallback for rows not passing graph-local promotion.

## Reproducibility Requirements

- Every run must record:
  - git SHA;
  - grid config path;
  - registry input path;
  - region and fold;
  - quantiles;
  - feature policy;
  - graph degree;
  - selected method;
  - validation/test split;
  - original-unit metrics;
  - seed;
  - generated output path.
- Generated heavy model matrices must be removed after successful summaries.
- All comparison scripts must be resumable.
- Any direct rerun fallback must use the same config and output root.

## Test Requirements

Before a broad launch:

- [ ] Unit test graph manifest determinism.
- [ ] Unit test graph-khop adapter row alignment.
- [ ] Unit test generated configs contain the expected spatial metadata.
- [ ] Smoke test one graph-khop median cell.
- [ ] Smoke test comparison and decision-freeze scripts.
- [ ] Confirm `git diff --check`.

After a launch:

- [ ] Confirm all expected cells completed.
- [ ] Confirm no row mismatches.
- [ ] Confirm no heavy `.rds`, `.rda`, or `.RData` artifacts remain outside
      approved authoritative output locations.
- [ ] Confirm generated results are ignored by git.

## Storage And Runtime Policy

- Use `--experiment-jobs` with one model core per cell unless memory pressure is
  observed.
- Keep degree 1 as the default graph run. Degree 2 is a targeted diagnostic,
  not the default.
- Clean non-selected heavy artifacts after summaries are written.
- Keep compact metric CSVs, registries, logs, and figures.

## Recommended Immediate Next Task

Implement a Stage-D graph-informed median rescue manifest for the Priority-1
green close/fallback rows. The launch should be median-only, graph-aware,
validation-selected, and test-audited. Do not expand to all quantiles until the
median candidates pass robustness gates.

This is the most efficient next move because it directly addresses the largest
known discrepancy with PriceFM's information set, reuses existing graph-khop
infrastructure, avoids blind local-only tuning, and preserves a clean path to a
fold/region-specific authoritative registry.
