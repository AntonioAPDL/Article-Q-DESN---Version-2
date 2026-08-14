# PriceFM Stage-J Information-Set Rescue Plan

Date: 2026-06-23

## Purpose

Stage J is the next PriceFM/DESN-QDESN comparison stage after the Stage-I
unresolved rescue closeout. Its purpose is not to repeat the same unresolved
grid. Stage I already showed that another broad pass over the same local/graph
geometry has low marginal value. The scientifically useful next move is to
change the information set for the remaining weak region-folds, then pass any
candidate through the same median, seed-robustness, and seven-quantile gates.

The central question is:

> Can graph-neighbor or otherwise richer input scopes close the remaining
> region-fold gaps while keeping the comparison reproducible, validation-clean,
> and explicitly labeled relative to PriceFM's spatial information set?

## Current Baseline

Authoritative Stage-I registry:

```text
application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_i_unresolved_20260623/authoritative_quantile_decision_registry.csv
```

Stage-I closeout doc:

```text
docs/implementation_notes/pricefm_stage_i_unresolved_rescue_closeout_20260623.md
```

Current Stage-I decision counts:

| Decision | Rows |
|---|---:|
| `stage_c_confirmed_local_win` | 25 |
| `stage_c_local_close_to_pricefm` | 6 |
| `stage_c_pricefm_fallback` | 11 |

Current aggregate seven-quantile comparison:

| Quantity | Value |
|---|---:|
| mean local AQL | `8.632195` |
| mean PriceFM AQL | `8.959769` |
| mean local - PriceFM AQL | `-0.327574` |
| mean relative delta | `-0.027768` |

Stage-I did not change the final quantile decisions relative to Stage H. It
added important audit/provenance, especially for `RO` fold 3, but the only
seed-robust median rescue did not beat cached PriceFM after seven-quantile
promotion.

## Critical Diagnosis

Repeating Stage I as-is is not optimal.

Stage-I facts:

- `284` median rescue experiments were run.
- `4` median candidates reached the seed-robustness screen.
- `1` candidate passed seed robustness.
- `0` candidates changed the authoritative seven-quantile decision.
- The final unresolved rows are mostly close losses or PriceFM fallbacks where
  the current representation is likely the limiting factor.

Therefore, the next stage should change one of the real levers:

- the input information set;
- graph degree or graph-neighbor representation;
- horizon-aware or neighbor-summary features;
- per-row geometry around already promising graph/local winners.

Among those, graph-neighbor information-set refinement is the most practical
first step because the repository already has adapter support, metadata, tests,
and closeout scripts for `graph_khop`.

## Existing Infrastructure To Reuse

Graph/input support is already wired through:

- `application/scripts/pricefm/pricefm_graph.py`
- `application/scripts/pricefm/pricefm_desn_adapter.py`
- `application/scripts/pricefm/40_prepare_pricefm_graph_local_rescue_median_grid.py`
- `application/scripts/pricefm/42_closeout_pricefm_graph_local_rescue.py`
- `application/scripts/pricefm/43_prepare_pricefm_graph_local_rescue_seed_grid.py`
- `application/scripts/pricefm/44_summarize_pricefm_graph_local_rescue_seedrob.py`
- `application/scripts/pricefm/45_patch_pricefm_median_registry_from_seedrob.py`
- `application/scripts/pricefm/60_prepare_pricefm_stage_h_targeted_rescue.py`
- `application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py`
- `application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py`
- `application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py`
- `application/scripts/pricefm/53_freeze_pricefm_stage_c_quantile_decisions.py`
- `application/scripts/pricefm/57_freeze_pricefm_authoritative_quantile_decisions.py`

Relevant tests already cover graph feature expansion and rescue workflows:

- `application/tests/test_pricefm_desn_adapter_graph_khop.py`
- `application/tests/test_pricefm_graph.py`
- `application/tests/test_pricefm_graph_neighbor_grid.py`
- `application/tests/test_pricefm_graph_neighbor_closeout.py`
- `application/tests/test_pricefm_graph_local_rescue_workflow.py`
- `application/tests/test_pricefm_stage_h_targeted_rescue.py`

Stage J should extend or parameterize these workflows only if needed. It should
not create a second model-selection framework.

## Remaining Weak Rows

Rows below are sorted by seven-quantile relative AQL gap against cached PriceFM.
Positive delta means local DESN/QDESN is worse than PriceFM.

| Region | Fold | Current decision | Delta rel | Current input scope | Current geometry | Stage-J interpretation |
|---|---:|---|---:|---|---|---|
| `SE_4` | 3 | close | `0.011812` | target only | D2 `[80,80]` | Best low-risk graph-khop conversion candidate |
| `LV` | 2 | close | `0.021444` | target only | D2 `[80,80]` | Low-degree graph; cheap graph degree 1/2 audit |
| `HU` | 3 | close | `0.036138` | graph degree 2 | D1 `[120]` | Already graph; tune geometry, not just degree |
| `LV` | 1 | close | `0.040082` | target only | D2 `[80,80]` | Same family as LV-2; graph test is cheap |
| `SI` | 1 | close | `0.045101` | target only | D1 `[120]` | Strong graph-neighbor candidate |
| `PL` | 1 | close | `0.047538` | target only | D1 `[120]` | Graph degree 1/2 may close small gap |
| `RO` | 3 | fallback | `0.050651` | graph degree 2 | D2 `[80,80]` | Stage-I audited; only revisit if geometry changes |
| `BE` | 3 | fallback | `0.051656` | graph degree 1 | D1 `[120]` | Near miss; try graph degree 2 and geometry |
| `NL` | 3 | fallback | `0.058272` | graph degree 2 | D1 `[120]` | Near miss; try D2/scale variants |
| `PL` | 3 | fallback | `0.092716` | target only | D1 `[120]` | Graph conversion, but lower priority |
| `RO` | 1 | fallback | `0.096365` | graph degree 2 | D1 `[120]` | Geometry/capacity refinement |
| `SE_4` | 1 | fallback | `0.101260` | target only | D2 `[80,80]` | Graph conversion, but gap larger |
| `AT` | 3 | fallback | `0.131982` | target only | D1 `[120]` | Graph conversion; larger gap |
| `FI` | 1 | fallback | `0.140641` | target only | D2 `[80,80]` | Graph conversion; larger gap |
| `LT` | 1 | fallback | `0.159386` | target only | D2 `[80,80]` | Graph conversion; larger gap |
| `SK` | 3 | fallback | `0.173640` | graph degree 2 | D1 `[120]` | Geometry/capacity refinement |
| `HU` | 2 | fallback | `0.186000` | graph degree 1 | D3 `[60,60,60]` | Hard row; not first unless capacity remains |

## Graph Scope Audit

The graph scope sizes imply two practical groups.

Small or moderate graph expansions are cheap and should be prioritized:

| Region | Degree 1 active regions | Degree 2 active regions |
|---|---:|---:|
| `LV` | 3 | 6 |
| `RO` | 3 | 8 |
| `BE` | 4 | 13 |
| `LT` | 4 | 10 |
| `SK` | 4 | 11 |
| `SI` | 5 | 11 |
| `FI` | 5 | 11 |
| `NL` | 5 | 14 |
| `HU` | 6 | 11 |
| `PL` | 6 | 16 |
| `SE_4` | 6 | 18 |
| `AT` | 6 | 18 |

Degree 2 for `SE_4`, `AT`, and `PL` is potentially wide and should be used
selectively. Degree 1 is the safer first information-set parity step for those
rows unless a dry-run shows feature counts and runtime are comfortably bounded.

## Recommended Stage-J Strategy

### Stage JA: Audit And Dry-Run

Goal: prove the intended candidate set is expressible without fitting models.

Checklist:

- [ ] Freeze the Stage-I registry as the Stage-J baseline.
- [ ] Create a Stage-J scope CSV with row tier, current decision, current input
      scope, graph degree, active-region count, and intended action.
- [ ] Confirm graph metadata fields are present for all graph candidates:
      `feature_policy`, `graph_degree`, `graph_source`, `graph_hash`,
      `input_scope`, `output_scope`, `lead_covariate_status`,
      `spatial_information_set`.
- [ ] Dry-run the grid with `--build-windows true --resume true --dry-run true`.
- [ ] Confirm selected experiment count, priorities, run roots, and generated
      roots before any live launch.
- [ ] Confirm no test metrics are used for median selection.
- [ ] Confirm no R binary artifacts exist in the dry-run roots.

Recommended output roots:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_j_information_set_rescue_20260623.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_j_information_set_rescue_20260623
application/data_local/pricefm/runs/pricefm_stage_j_information_set_rescue_20260623
application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_plan_20260623
```

### Stage JB: Median Rescue Screen

Goal: run a controlled median-only screen over rows where information-set
changes can plausibly improve the seven-quantile decision.

Priority 0 should be small and high value:

- close target-only rows:
  `SE_4-3`, `LV-2`, `LV-1`, `SI-1`, `PL-1`;
- close graph row:
  `HU-3`;
- near-fallback graph rows:
  `BE-3`, `NL-3`, and optionally `RO-3`.

Priority 1 should run only after Priority 0 closeout:

- target-only fallbacks with medium gaps:
  `PL-3`, `SE_4-1`, `AT-3`;
- graph fallbacks:
  `RO-1`, `SK-3`;
- high-gap target-only rows:
  `FI-1`, `LT-1`.

Priority 2 should remain optional:

- `HU-2`, unless Stage-JB shows graph geometry refinements work well for `HU`.

Candidate design:

| Current state | Recommended variants | Reason |
|---|---|---|
| target-only close row | graph degree 1 base, graph degree 2 base, degree 1/2 input-scale low/high, alpha low/high | Tests information-set parity before adding capacity |
| target-only larger fallback | graph degree 1 base, graph degree 2 base, compact D2 if D1 current, one units-high variant | More cautious because gap is larger |
| already graph degree 1 | graph degree 2 base, input-scale low/high, alpha low/high, compact D2 | Changes representation without discarding graph signal |
| already graph degree 2 | D2/D3 capacity if current D1, input-scale low/high, alpha low/high, target-only guardrail only if prior evidence suggests graph hurts | Tests whether graph is right but compressed poorly |

Do not make `tau0` a wide axis. Current evidence still points to input
representation and graph scope as the main bottleneck. Keep `tau0 = 1e-3`
unless a row has a specific documented reason for `1e-4` or `1e-2`.

Recommended launch settings:

```text
experiment_jobs = 16 to 20
cell_jobs = 1
OMP_NUM_THREADS = 1
OPENBLAS_NUM_THREADS = 1
MKL_NUM_THREADS = 1
VECLIB_MAXIMUM_THREADS = 1
NUMEXPR_NUM_THREADS = 1
```

These settings match the current workflow: many independent model cells,
single-threaded BLAS per process, and resumable grid execution.

### Stage JC: Median Closeout

Goal: compare Stage-J median candidates against the current Stage-I median
registry using validation AQL only.

Checklist:

- [ ] Every expected `metric_summary.csv` exists.
- [ ] No model run reports failed status.
- [ ] No large `.rds`, `.rda`, `.RData`, or `.rdata` artifacts remain.
- [ ] Candidate selection uses validation/original/AQL only.
- [ ] Test AQL and cached PriceFM AQL are audit-only fields.
- [ ] Graph metadata survives into the median registry.
- [ ] Closeout table separates improved, unchanged, and worse rows.

If Stage-J priority 0 yields no validation-improving median candidates, stop
and do not launch lower priorities until the model/input design is reconsidered.

### Stage JD: Seed Robustness

Goal: filter out fragile median improvements.

Run seed robustness only for Stage-J median candidates that improve validation
AQL and do not fail sanity checks. Use at least three fresh seeds and keep the
candidate geometry fixed.

Checklist:

- [ ] Seed-robust candidate is finite for every seed.
- [ ] Median validation AQL improvement is stable enough to justify promotion.
- [ ] No seed candidate depends on test/PriceFM metrics for selection.
- [ ] Seedrob patched median registry records source and seed metadata.

### Stage JE: Seven-Quantile Confirmation

Goal: decide whether any Stage-J candidate should alter the authoritative
quantile decision.

Quantile promotion remains the same conservative path:

- prepare seven PriceFM-paper quantiles from the patched median registry;
- run only patch rows, not the whole panel unless needed;
- compare against the cached fold-aligned PriceFM benchmark;
- freeze the decision registry only through the existing freeze scripts.

Checklist:

- [ ] All seven quantile fits finish.
- [ ] Synthesized local quantile forecast is finite.
- [ ] AQL comparison uses the same fold/region/horizon alignment as the cached
      PriceFM benchmark.
- [ ] New local row is promoted only if the seven-quantile AQL beats PriceFM or
      satisfies the already documented close/win rule.
- [ ] Otherwise, keep the PriceFM fallback and preserve Stage-J audit metadata.

### Stage JF: Documentation And Cleanup

Goal: make the stage reproducible and leave the repo clean.

Deliverables:

- [ ] Stage-J plan doc, this file.
- [ ] Stage-J dry-run/audit summary.
- [ ] Stage-J median closeout doc.
- [ ] Stage-J seedrob summary if seedrob runs.
- [ ] Stage-J quantile promotion closeout if quantiles run.
- [ ] Final authoritative decision registry only if decisions change or audit
      metadata is intentionally frozen.
- [ ] Compact tables committed only as documentation; generated run outputs
      remain ignored.
- [ ] `git diff --check` passes.
- [ ] Relevant pytest files pass.

## Minimal Code Work Expected

Prefer reusing existing generators. Implement new code only if one of these
gaps appears during Stage JA:

1. Existing Stage-H/I generators cannot select the exact Stage-J row tier.
2. Existing generators cannot distinguish target-only conversion variants from
   graph-geometry refinement variants.
3. Existing manifests cannot record the Stage-J action label and information-set
   rationale.

If code is needed, the smallest safe implementation is a Stage-J wrapper around
`60_prepare_pricefm_stage_h_targeted_rescue.py`, not a new modeling path.

Required tests for any Stage-J preparer update:

- stage label and target label are configurable;
- target-only rows receive graph degree 1/2 variants;
- graph rows receive geometry variants without losing graph metadata;
- severe fallback rows can be excluded from priority 0;
- generated experiments are validation-only;
- metadata fields include input scope, output scope, lead covariate status, and
  spatial information set.

## Stop Gates

Stop and report instead of launching or promoting if:

- Stage-J dry-run selects unexpected rows or priorities;
- graph metadata is missing or inconsistent;
- graph degree 2 produces an impractically large feature count for a row;
- any selection path uses test or PriceFM metrics as model-selection criteria;
- cached PriceFM row alignment fails;
- median launch produces failed experiment rows;
- seed robustness fails for all candidate improvements;
- seven-quantile local synthesis lags PriceFM after promotion;
- large R binary artifacts accumulate;
- a process threatens unrelated ongoing validation jobs.

## Why This Is The Optimal Next Move

This plan is more informative than another broad unresolved rescue because it
changes the likely limiting factor: the information set. It is safer than a
new model architecture because graph-khop support is already implemented and
tested. It is more efficient than expanding to all unresolved rows equally
because it starts with small-gap rows where a modest improvement can change the
decision. It remains apples-to-apples disciplined because every candidate is
explicitly labeled as local-only or PriceFM-graph-input and must pass the same
seven-quantile comparison machinery before becoming authoritative.

The recommended immediate next action is Stage JA: create the scoped Stage-J
audit/dry-run artifacts from the Stage-I registry, validate the generated
candidate table, and only then decide whether to launch priority 0.
