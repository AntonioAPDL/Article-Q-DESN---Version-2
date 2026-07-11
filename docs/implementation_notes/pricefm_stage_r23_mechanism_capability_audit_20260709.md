# PriceFM Stage-R23 Mechanism-Capability Audit

Stage-R23 is a read-only audit stage for the PriceFM branch after the negative
Stage-R22C/R22D closeout. It is designed to support an eventual broad expensive
screening path, but only after verifying which Stage-R22 mechanism knobs are
actually consumed by the runner and model code.

## Purpose

The stage audits whether Stage-R22C mechanism labels are real implementation
paths or metadata only:

- horizon-weighted readout/loss via `horizon_weight_multiplier`;
- horizon-block interaction readout via `state_output=concat_layers`;
- postfit calibration via deferred `calibration_rule` rows;
- actual reservoir/information-set search axes such as units, depth, feature
  dimension, lag window, alpha, rho, input scale, tau0, feature policy, and
  quantile scope.

## Implementation

Script:

```bash
application/scripts/pricefm/147_audit_pricefm_stage_r23_mechanism_capability.py
```

Focused tests:

```bash
application/tests/test_pricefm_stage_r23_mechanism_capability.py
```

Default output directory:

```text
application/data_local/pricefm/authoritative/pricefm_stage_r23_mechanism_capability_audit_20260709
```

## Inputs

- Stage-R22C launch manifest, deferred postfit manifest, and launch-prep gates.
- Stage-R22D closeout summary.
- PriceFM runner/model/adapter source files.
- Local `exdqlm` package source files for the `exal_ldvb_fit` wrapper and engine.

## Outputs

- `pricefm_stage_r23_field_propagation_audit.csv`
- `pricefm_stage_r23_runner_capability_matrix.csv`
- `pricefm_stage_r23_package_fit_signature.csv`
- `pricefm_stage_r23_r22c_effective_search_space.csv`
- `pricefm_stage_r23_postfit_calibration_readiness.csv`
- `pricefm_stage_r23_case_next_mechanism_queue.csv`
- `pricefm_stage_r23_expensive_path_bounds_recommendation.csv`
- `pricefm_stage_r23_no_launch_gates.csv`
- `source_manifest.csv`
- `pricefm_stage_r23_mechanism_capability_audit_report.md`
- `summary.json`

## Hard Blocks

Stage-R23 does not write launch YAML, launch jobs, fit models, mutate the
PriceFM registry, or update manuscript/article files. It should be used as the
mechanism gate before any broad expensive Stage-R24 launch prep.

## Validation

Expected validation commands:

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/147_audit_pricefm_stage_r23_mechanism_capability.py

application/data_local/pricefm/venv/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r23_mechanism_capability.py
```
