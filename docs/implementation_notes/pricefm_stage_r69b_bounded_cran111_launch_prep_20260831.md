# PriceFM Stage-R69B bounded CRAN 1.1.1 launch prep

Stage-R69B converts the corrected Stage-R69A launch-grade anchors into a
bounded, train/validation-only launch-prep manifest. It does not launch, fit
models, read test metrics, mutate the PriceFM registry, or update the article.

## Scientific role

The current PriceFM lane is focused on finishing the independent seven-quantile
VB surface before any joint model, MCMC confirmation, or article promotion.
Stage-R68 identified 56 targeted region/fold cells where a bounded refit is
scientifically defensible:

- 14 priority-0 near-miss cells;
- 42 priority-1 moderate-gap cells;
- no far-gap or current-Q-DESN-win cells.

Stage-R69A verified that all 56 cells have recoverable case-specific DESN
anchors. Stage-R69B uses exactly those anchors and does not broaden the target
surface.

## Inputs

- `pricefm_stage_r69a_spec_anchor_audit.csv`;
- `pricefm_stage_r69a_quantile_component_anchor_audit.csv`;
- `pricefm_stage_r69a_launch_readiness_gates.csv`;
- Stage-R69A `summary.json`;
- CRAN `exdqlm` 1.1.1 runtime manifest from Stage-R67.

## Outputs

The prep materializes:

- one case-level YAML config per target cell;
- one portable data config per target cell;
- `case_manifest.csv`;
- `component_ledger.csv`;
- `pricefm_stage_r69b_launch_control.yaml`;
- `pricefm_stage_r69b_launch_prep_gates.csv`;
- `source_manifest.csv`;
- `summary.json`;
- `pricefm_stage_r69b_launch_prep_report.md`.

## Core contract

Each generated case config has:

- `splits: [train, val]`;
- seven paper quantiles: `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`;
- both AL and exAL likelihoods planned;
- the exact CRAN `exdqlm` 1.1.1 runtime manifest;
- public API `exalStaticLDVB`;
- no fork-only namespace calls;
- the case-specific DESN depth, units, feature policy, readout, lag window,
  reservoir hyperparameters, and RHS-NS `tau0` recovered by Stage-R69A;
- no external checkpoint reuse;
- no registry, article, joint-model, or MCMC authorization.

Historical source configs may contain test splits because they are already
audited past-run configs. Stage-R69B strips those splits in all generated
future-run configs. Test metrics remain audit-only after frozen validation
selection.

## Validation

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/237_prepare_pricefm_stage_r69b_bounded_cran111_launch_prep.py \
  application/tests/test_pricefm_stage_r69b_bounded_cran111_launch_prep.py

application/data_local/pricefm/venv/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r69b_bounded_cran111_launch_prep.py
```

Materialization:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/237_prepare_pricefm_stage_r69b_bounded_cran111_launch_prep.py
```

## Do not do yet

- Do not invoke a launcher from Stage-R69B.
- Do not create `launch_status.csv`.
- Do not read or select on test metrics.
- Do not mutate the registry or article.
- Do not start joint or MCMC fits.
- Do not refit all 114 cells.
