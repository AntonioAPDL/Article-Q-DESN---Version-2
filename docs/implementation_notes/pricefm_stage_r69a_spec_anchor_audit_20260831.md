# PriceFM Stage-R69A spec-anchor audit

Stage-R69A is a read-only launch-readiness audit for the Stage-R68 target queue.
It does not launch, fit, mutate registries, update article files, or write
launch YAML. Its only job is to verify that every targeted region/fold has a
recoverable, case-specific DESN specification anchor before a future Stage-R69B
launch-prep stage is allowed.

## Current scientific direction

The PriceFM lane is deliberately back on the independent VB comparison surface
before any joint model, MCMC, registry mutation, or article promotion. The
current evidence says the cached PriceFM replay is easier to beat than the
operational PriceFM benchmark, so the next useful work is not another global
all-cell run. It is a bounded, case-specific repair surface for the 56 cells
identified by Stage-R68:

- 14 priority-0 near-miss rows where Q-DESN is close to operational PriceFM;
- 42 priority-1 moderate-gap rows where a small local mechanism repair may
  plausibly close the gap;
- 58 no-refit rows kept out of scope, including current Q-DESN wins and far-gap
  hold rows.

This avoids refitting cells whose current Q-DESN model already wins, avoids
spending compute on severe gaps with weak evidence, and keeps selection
validation-only until a later closeout audits test performance.

## Inputs

- Stage-R68 refit target queue.
- Stage-R68 summary.
- Stage-R62 candidate bundle ledger.
- Stage-R62 summary.
- The seven historical config, feature-manifest, and metric files referenced by
  the matched R62 bundle for each target row.

## Audited fields

For each target row the script reconstructs:

- selected likelihood family, AL or exAL;
- region/fold and seven PriceFM paper quantiles;
- DESN depth `D`;
- layer width vector and common `n` per layer when available;
- lag and lead windows;
- feature policy and input scope;
- local/graph information-set metadata;
- readout/state-output policy;
- RHS-NS `tau0`;
- alpha, rho, input scale, projection scale, sparsity, and activation;
- train-origin budget and selection rule;
- component file hashes and source data-config hashes.

## Gates

All targets must:

- match exactly one R62 candidate bundle;
- have seven component configs and metric/feature files;
- match the expected quantile set;
- have consistent DESN/tau0/spec fields across the seven quantiles;
- preserve validation-only future selection;
- strip historical test splits in future launch prep;
- use exact CRAN `exdqlm` 1.1.1 public APIs for future new fits;
- keep failed R65/R66 structured-exAL reuse blocked.

Local `target_only` anchors are normalized to the local information-set
contract even when older feature manifests did not store the scope labels:
`input_scope=local_target_only`, `output_scope=target_region_path`,
`spatial_information_set=local_only_not_pricefm_graph`, and
`lead_covariate_status=realized_ex_post`. A graph degree is required only for
graph feature policies. Missing `graph_degree` is expected for local
`target_only` anchors and is not a launch blocker.

The historical component configs may contain `splits: [train, val, test]`
because they came from already-audited past runs. Stage-R69A does not open or
use test metrics. The next launch-prep stage must strip any historical test
split and materialize train/validation-only launch configs.

## Validation

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/236_audit_pricefm_stage_r69a_spec_anchor.py \
  application/tests/test_pricefm_stage_r69a_spec_anchor.py

application/data_local/pricefm/venv/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r69a_spec_anchor.py
```

Materialization:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/236_audit_pricefm_stage_r69a_spec_anchor.py
```

Expected outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_r69a_spec_anchor_audit_20260831
```

The corrected materialized audit reports 56 launch-grade anchors out of 56 R68
target rows, 392 component rows, zero blocked anchors, no launch YAML, and no
model binary artifacts.

## Implementation result

The script materializes:

- `pricefm_stage_r69a_spec_anchor_audit.csv`;
- `pricefm_stage_r69a_quantile_component_anchor_audit.csv`;
- `pricefm_stage_r69a_spec_distribution.csv`;
- `pricefm_stage_r69a_missing_or_inconsistent_anchors.csv`;
- `pricefm_stage_r69a_launch_readiness_gates.csv`;
- `source_manifest.csv`;
- `summary.json`;
- `pricefm_stage_r69a_spec_anchor_audit_report.md`.

The important result is that all 56 Stage-R68 target rows have launch-grade
case-specific anchors recoverable from R62. The anchor surface includes AL and
exAL, local and graph feature policies, per-region/per-fold DESN depth and
units, lag/lead windows, RHS-NS `tau0`, readout, and reservoir hyperparameters.

## Recommended next stages

1. Stage-R69B should convert only the 56 launch-grade anchors into a launch-prep
   manifest. It should still write no registry/article mutations and should
   strip all test splits from future configs.
2. Stage-R70 may launch the bounded independent VB refit only after the R69B
   manifest passes structural checks. It should use exact CRAN `exdqlm` 1.1.1
   public APIs and preserve case-specific anchors instead of imposing one shared
   DESN specification.
3. Stage-R71 should close out R70 with validation-only winner selection and test
   audit against both current authoritative Q-DESN and operational PriceFM.
4. Only candidates that beat both comparators should enter an article/registry
   promotion queue. Joint models, MCMC confirmation, and manuscript edits remain
   blocked until that independent VB surface is frozen.

## Do not do yet

- Do not refit all 114 cells.
- Do not reuse failed R65/R66 structured-exAL artifacts as launch authority.
- Do not open test metrics for selection.
- Do not launch from historical configs containing `test` splits.
- Do not mutate the registry, article, or manuscript.
- Do not start joint or MCMC runs from this stage.
