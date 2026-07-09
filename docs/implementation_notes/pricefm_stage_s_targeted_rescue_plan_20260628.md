# PriceFM Stage-S Targeted Rescue Plan

Date: 2026-06-28

## Purpose

Stage S is the next PriceFM/Q-DESN screening stage after the Stage-R diagnostic
closeout.  It should not be a broad capacity sweep.  Stage R showed that the
main unresolved signal is split by failure mode:

- target-only rows underperform much more often than graph-input rows;
- Stage-Q near-miss refinement had poor validation/test transfer and should not
  be continued;
- a few graph-input rows show horizon-block weakness, but not enough evidence
  for an unrestricted grid.

Stage S should therefore be a targeted, reproducible rescue stage with a
manifest-first gate.  The first implementation should prepare and validate the
manifest and optional dry-run grid; the actual model launch should remain an
explicit second action.

## Implementation Status

The manifest-builder, grid-readiness pass, priority-0 launch, and closeout are
complete.  Stage S completed cleanly as a reproducible negative result: no
validation-selected or test-oracle Stage-S candidate beat the current Stage-M
surface or cached PriceFM metric for its region/fold.  The Stage-M article
decision surface remains unchanged.

Tracked implementation files:

```text
application/scripts/pricefm/79_prepare_pricefm_stage_s_targeted_rescue.py
application/scripts/pricefm/80_closeout_pricefm_stage_s_targeted_rescue.py
application/tests/test_pricefm_stage_s_targeted_rescue.py
docs/implementation_notes/pricefm_stage_s_targeted_rescue_plan_20260628.md
docs/implementation_notes/pricefm_stage_s_targeted_rescue_closeout_20260629.md
```

Ignored local outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_s_targeted_rescue_plan_20260628/
application/data_local/pricefm/authoritative/pricefm_stage_s_targeted_rescue_closeout_20260629/
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_s_targeted_rescue_20260628.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_s_targeted_rescue_20260628/
application/data_local/pricefm/runs/pricefm_stage_s_targeted_rescue_20260628/
```

Manifest summary:

| Quantity | Value |
|---|---:|
| Target rows | 13 |
| Graph-parity rows | 10 |
| Horizon-pilot rows | 3 |
| Blocked rows | 29 |
| Total experiments | 138 |
| Graph-parity experiments | 120 |
| Horizon-pilot experiments | 18 |
| Generated grid configs | 138 |
| Grid validation status | passed |
| Model fits launched | 138 |
| Model fits completed | 138 |
| Metric files | 138 |
| Binary fit artifacts retained | 0 |
| Promotion recommended | FALSE |
| Stage-M surface changed | FALSE |

Stage-S target rows:

| Family | Region/fold rows | Experiments |
|---|---|---:|
| Graph-parity rescue | LT-1, FI-1, AT-3, SE_4-1, PL-3, LV-1, SI-1, PL-1, LV-2, SE_4-3 | 120 |
| Horizon-block pilot | RO-3, HU-3, BE-3 | 18 |

Commands run:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/79_prepare_pricefm_stage_s_targeted_rescue.py

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/79_prepare_pricefm_stage_s_targeted_rescue.py \
  --write-grid true

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_s_targeted_rescue_20260628.yaml \
  --write

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/14_validate_reservoir_grid_artifacts.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_s_targeted_rescue_20260628.yaml \
  --write-generated \
  --output-json application/data_local/pricefm/authoritative/pricefm_stage_s_targeted_rescue_plan_20260628/stage_s_grid_validation.json \
  --output-csv application/data_local/pricefm/authoritative/pricefm_stage_s_targeted_rescue_plan_20260628/stage_s_grid_validation.csv
```

Validation status:

- manifest generation passed;
- optional grid YAML generation passed;
- generated full-config manifest has 138 rows;
- grid artifact validation passed for all 138 rows;
- validation-selection fields are validation-only;
- test metrics are recorded as audit-only;
- blocked rows are excluded from the launch manifest;
- no `.rds`, `.rda`, `.RData`, or `.rdata` fit artifacts were produced by the
  manifest/grid-readiness pass.

Closeout status:

- priority-0 launch completed with zero nonzero return codes;
- all 138 expected metric files were present;
- no `.rds`, `.rda`, `.RData`, or `.rdata` fit artifacts remained;
- validation-selected candidates beat Stage-M in 0 of 13 rows;
- validation-selected candidates beat cached PriceFM in 0 of 13 rows;
- test-oracle candidates beat Stage-M in 0 of 13 rows;
- test-oracle candidates beat cached PriceFM in 0 of 13 rows;
- the best test-oracle Stage-S candidate was still 0.716 AQL worse than cached
  PriceFM;
- no seven-quantile confirmation queue was triggered.

Tracked closeout:

```text
docs/implementation_notes/pricefm_stage_s_targeted_rescue_closeout_20260629.md
```

Ignored closeout outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_s_targeted_rescue_closeout_20260629/
```

The next action is structural diagnostics before any new search.  Do not launch
Stage-S priority 1 and do not continue graph-parity rescue variants from this
same family without a new diagnosis.

## Current Evidence

Authoritative Stage-R closeout:

```text
docs/implementation_notes/pricefm_stage_r_selection_diagnostics_20260627.md
application/data_local/pricefm/authoritative/pricefm_stage_r_selection_diagnostics_20260627/
```

Stage-R health:

| Quantity | Value |
|---|---:|
| Stage-M rows | 42 |
| Candidate transfer rows | 210 |
| Stage-M surface changed | FALSE |
| Stage-Q priority-1 recommended | FALSE |
| Launch configs written | FALSE |

Information-set parity:

| Information set | Rows | Q-DESN wins | Win rate | Mean delta AQL | Median delta AQL |
|---|---:|---:|---:|---:|---:|
| PriceFM graph inputs | 27 | 20 | 0.741 | -0.719 | -0.677 |
| Target only | 15 | 5 | 0.333 | 0.377 | 0.315 |

This justifies graph-parity exploration for target-only underperformers.  It
does not justify a larger generic reservoir sweep.

Validation/test transfer evidence:

| Source | Rows | Region/folds | Test win rate | PriceFM win rate | Disagree rate | Mean test delta vs PriceFM |
|---|---:|---:|---:|---:|---:|---:|
| Stage-N validation-selected | 17 | 17 | 0.412 | 0.000 | 0.412 | 3.008 |
| Stage-O selection rules | 68 | 17 | 0.412 | 0.000 | 0.412 | 3.069 |
| Stage-Q validation-selected | 2 | 2 | 0.000 | 0.000 | 0.000 | 2.085 |
| Stage-Q test-oracle audit | 2 | 2 | 0.000 | 0.000 | 0.000 | 1.666 |

This blocks Stage-Q priority 1 and blocks any plan that relies on a single
median validation-AQL rule without additional diagnostics.

## Critical Audit Of Possible Next Actions

| Action | Decision | Reason |
|---|---|---|
| Launch Stage-Q priority 1 | Reject | Priority 0 already tested this family on the strongest near misses, and even test-oracle rows failed against Stage P and PriceFM. |
| Run a broad D/alpha/rho/capacity sweep | Reject for now | Existing failure is information-set and selection-transfer specific, not simply missing capacity. |
| Promote test-oracle rows | Reject | Test metrics are audit-only and cannot be used for article-surface selection. |
| Mutate Stage-M immediately | Reject | Stage-M remains the current article decision surface until median and paper-quantile confirmation pass. |
| Seven-quantile all unresolved rows now | Reject for now | Expensive and premature; median rescue signal is not yet credible for the unresolved rows. |
| Manifest-only Stage S | Accept | It converts Stage-R evidence into a small, auditable candidate set with explicit launch gates. |

## Stage-S Scope

Stage S should include two priority-0 candidate families after manifest review.

### Family 1: graph-parity target-only rescue

Rows:

```text
LT-1, FI-1, AT-3, SE_4-1, PL-3, LV-1, SI-1, PL-1, LV-2, SE_4-3
```

Current status:

| Property | Value |
|---|---:|
| Rows | 10 |
| Current information set | target-only |
| Mean current AQL gap vs PriceFM | 0.715 |
| Largest current AQL gap | 1.991 |
| Mean absolute validation/test gap | 1.332 |

Rationale: these rows are the clearest mismatch with PriceFM.  The model is
being asked to compete without the graph-neighbor information that appears to
matter in the rows where Q-DESN succeeds.

Allowed feature policies:

- `graph_khop`, degree 1;
- `graph_khop`, degree 2;
- `graph_summary_mean`, degree 1 or 2, as a compact graph-input alternative;
- `graph_summary_mean_std`, degree 1 or 2, only if the manifest remains within
  the launch budget.

Initial geometry should be anchored to already-used, known-safe families:

| Geometry | Purpose |
|---|---|
| `L=96, D=1, units=[120], alpha=0.5, rho=0.9, input_scale=0.5` | Main Stage-C/graph anchor |
| `L=96, D=1, units=[120], alpha=0.5, rho=0.9, input_scale=0.25` | Lower-input-scale anchor |
| `L=96, D=2, units=[80,80], alpha=0.4, rho=0.9, input_scale=0.35` | Compact D2 anchor |

Do not include D4/D5/D6 or very large `n` in priority 0.  Those are not
failure-mode matched and would inflate compute before graph parity is tested.

### Family 2: horizon-block selection pilot

Rows:

```text
RO-3, HU-3, BE-3
```

Current status:

| Property | Value |
|---|---:|
| Rows | 3 |
| Current information set | PriceFM graph inputs |
| Mean current AQL gap vs PriceFM | 0.338 |
| Mean absolute validation/test gap | 2.376 |

Rationale: these rows already use graph inputs.  The issue looks more like
validation/test and horizon-block instability than missing spatial information.

Stage S should first treat these as a selection-rule pilot, not a large model
search.  Candidate variants should be modest and close to the current graph
geometry, and the closeout must compare validation-only rules:

- global validation AQL;
- average validation AQL over horizon blocks;
- max validation AQL over horizon blocks;
- late-weighted validation AQL.

Test horizon metrics remain audit-only.

## Explicitly Blocked Rows

| Row(s) | Reason |
|---|---|
| RO-1, NL-3 | Stage-Q showed near-zero validation/test rank transfer; do not relaunch without a new selection contract. |
| HU-2, SK-3 | PriceFM is far ahead and existing rescue stages have not closed comparable gaps. |
| 25 current-win rows | Already beat cached PriceFM; no compute needed. |

## Implementation Plan

### Stage S0: manifest and contract

Add a manifest builder:

```text
application/scripts/pricefm/79_prepare_pricefm_stage_s_targeted_rescue.py
```

Default output directory:

```text
application/data_local/pricefm/authoritative/pricefm_stage_s_targeted_rescue_plan_20260628/
```

Default optional grid config path:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_s_targeted_rescue_20260628.yaml
```

Default run root, if later launched:

```text
application/data_local/pricefm/runs/pricefm_stage_s_targeted_rescue_20260628/
```

The builder should read:

- Stage-R `stage_r_next_grid_recommendations.csv`;
- Stage-R `stage_r_region_fold_scorecard.csv`;
- Stage-R `stage_r_horizon_block_diagnostics.csv`;
- current Stage-M surface;
- a known-safe template grid YAML;
- graph hash from `pricefm_graph.graph_hash()`.

Required outputs:

- `stage_s_input_manifest.csv`;
- `stage_s_target_rows.csv`;
- `stage_s_experiment_manifest.csv`;
- `stage_s_blocked_rows.csv`;
- `stage_s_expected_cost.csv`;
- `stage_s_plan_summary.md`;
- `summary.json`;
- optional dry-run grid YAML only when explicitly requested.

Default behavior should be manifest-only:

```text
write_grid = false
```

If `write_grid = true`, the script may write a grid YAML, but it should still
not launch fits.

### Stage S1: manifest tests

Add:

```text
application/tests/test_pricefm_stage_s_targeted_rescue.py
```

Minimum tests:

- missing Stage-R inputs fail clearly;
- duplicate target keys fail clearly;
- no launch YAML is written by default;
- Stage-Q blocked rows are not present in target rows;
- `pricefm_far_ahead` rows are not present in target rows;
- graph-parity rows receive graph feature policies only;
- horizon-pilot rows receive horizon-pilot labels and validation-only selection
  rules;
- every experiment records `test_metrics_role = audit_only`;
- every experiment records `selection_is_validation_only = true`;
- artifact hygiene preserves metrics/figures and cleans binary fit artifacts;
- manifest counts match the configured caps.

### Stage S2: optional dry-run grid

Only after Stage S0/S1 pass, run the manifest builder with `write_grid = true`
and use the existing PriceFM grid launcher in dry-run mode.  The dry run should
build windows and validate paths but should not fit models.

Dry-run acceptance criteria:

- generated config parses;
- all target region/fold pairs exist in the PriceFM data bundle;
- graph windows align by anchor across active regions;
- manifest row count equals generated experiment count;
- no `.rds`, `.rda`, `.RData`, or `.rdata` files are produced;
- no Stage-M surface file is modified.

### Stage S3: optional priority-0 launch

Do not launch in the same step as the manifest unless explicitly requested.
If launched later, use priority 0 only:

- graph-parity rows: launch a bounded graph-input screen;
- horizon rows: launch only the small horizon-block pilot;
- `experiment_jobs` between 12 and 20 depending on available CPU;
- `cell_jobs = 1`;
- artifact hygiene enabled;
- binary model artifacts deleted after metrics and figures are written.

### Stage S4: closeout

Add:

```text
application/scripts/pricefm/80_closeout_pricefm_stage_s_targeted_rescue.py
```

Required closeout outputs:

- run health table;
- metric-file completeness;
- binary-artifact hygiene check;
- validation-selected rows;
- horizon-rule selected rows;
- test-audit table;
- comparison to current Stage-M and cached PriceFM;
- recommended seven-quantile confirmation queue;
- no-promotion rows;
- summary Markdown and JSON.

Closeout must preserve the selection contract:

- validation metrics select candidates;
- test metrics audit candidates;
- no candidate changes Stage-M without later seven-paper-quantile confirmation.

## Recommended Priority-0 Size

The first Stage-S launch should be bounded.  A reasonable target is:

| Family | Rows | Variants per row | Approx. experiments |
|---|---:|---:|---:|
| Graph-parity rescue | 10 | 8-12 | 80-120 |
| Horizon-block pilot | 3 | 6-10 | 18-30 |
| Total | 13 | mixed | 98-150 |

This is large enough to test the diagnosed failure modes but much smaller than
a broad region/fold/capacity sweep.

## Reproducibility Criteria

Every Stage-S artifact must record:

- repo branch, HEAD, and dirty state;
- command line;
- input file paths and SHA-256 hashes;
- graph hash;
- target row source and failure mode;
- exact feature policy and graph degree;
- validation-selection rule;
- test-audit role;
- artifact-cleaning policy;
- output/run roots.

All generated run outputs remain ignored under `application/data_local/pricefm/`.
Tracked docs should summarize only compact, reproducible decisions.

## Documentation Criteria

Add or update:

```text
docs/implementation_notes/pricefm_stage_s_targeted_rescue_plan_20260628.md
docs/implementation_notes/pricefm_stage_s_targeted_rescue_closeout_20260628.md
```

The closeout doc should include:

- why Stage-S was launched;
- rows included and excluded;
- candidate families;
- validation-only selection rule;
- test-audit results;
- comparison to current Stage-M and cached PriceFM;
- exact list of rows recommended for seven-quantile confirmation;
- exact list of rows that remain unresolved;
- whether Stage-M remains unchanged.

## Stop Gates

Stop before launch if:

- Stage-R inputs are missing or inconsistent;
- Stage-M row count is not 42;
- any target row is duplicated;
- Stage-Q priority-1 is no longer blocked;
- RO-1 or NL-3 appear in the launch manifest;
- HU-2 or SK-3 appear in the launch manifest;
- a candidate relies on test metrics for selection;
- graph candidate metadata lacks graph hash, degree, or input scope;
- dry-run window anchors do not align across graph regions;
- expected experiment count exceeds the reviewed cap;
- output would require committing large generated files.

Stop after launch if:

- any nonzero return code appears;
- metric files are missing;
- non-finite metrics appear;
- binary fit artifacts remain after cleanup;
- validation/test transfer is again near-zero for the selected family;
- the best validation-selected row is worse than current Stage-M by the
  guardrail tolerance.

## Why This Is The Optimal Next Move

Stage-S should not be a broad overnight exploration because the current evidence
does not support that.  Stage-Q already showed that a broad-ish refinement can
complete cleanly while failing scientifically.  Stage-R gives a better
diagnosis: the unresolved panel is split between missing graph information and
horizon/selection instability.

The manifest-first Stage-S plan is optimal because it:

1. attacks the strongest observed failure mode first;
2. avoids re-running a falsified Stage-Q family;
3. keeps test metrics audit-only;
4. preserves the current article decision surface;
5. keeps generated artifacts local and ignored;
6. creates a reusable template for future region/fold expansion;
7. allows a later launch to be reviewed, sized, and reproduced exactly.

## Checklist

### Before implementation

- [x] Re-verify repo state.
- [x] Re-read Stage-R summary JSON and candidate CSVs.
- [x] Confirm no PriceFM process was required for manifest generation.
- [x] Confirm no newer authoritative PriceFM stage supersedes Stage-R.

### Manifest builder

- [x] Implement `79_prepare_pricefm_stage_s_targeted_rescue.py`.
- [x] Write no grid by default.
- [x] Record input manifest and hashes.
- [x] Write target, blocked, experiment, and expected-cost CSVs.
- [x] Write summary JSON and Markdown.

### Tests

- [x] Add `test_pricefm_stage_s_targeted_rescue.py`.
- [x] Test missing inputs, duplicate keys, blocked rows, graph metadata,
  validation-only labels, and artifact hygiene.
- [x] Run Stage-S focused tests.
- [x] Run Stage-R and Stage-S focused tests.
- [x] Run `git diff --check`.

### Optional dry run

- [x] Generate grid only after manifest review.
- [x] Validate generated grid configs with no model fitting.
- [x] Confirm generated graph/input metadata is present.
- [x] Confirm no binary model artifacts are created.

### Optional launch

- [x] Launch priority 0 only after explicit authorization.
- [x] Use parallel experiment jobs with `cell_jobs = 1`.
- [x] Monitor return codes and metric files.
- [x] Clean binary artifacts automatically.

### Closeout

- [x] Implement closeout script after launch.
- [x] Select candidates using validation metrics only.
- [x] Use test metrics as audit-only.
- [x] Recommend seven-paper-quantile confirmation only for credible rows.
- [x] Keep Stage-M unchanged until confirmation passes.

### Post-closeout decision

- [x] Freeze Stage S as negative evidence.
- [x] Do not launch Stage-S priority 1.
- [x] Preserve the current Stage-M article decision surface.
- [x] Move the next discussion to structural model/data diagnostics.
