# PriceFM Stage-R70 CRAN 1.1.1 Independent VB Launch

Date: 2026-08-31

## Purpose

Stage-R70 is the actual train/validation-only refit campaign prepared by
Stage-R69B. It fits the 56 R69A launch-grade region/fold anchors using the
exact CRAN `exdqlm` 1.1.1 public API rather than the historical fork-only
helpers. Each case is fitted as an independent PriceFM QDESN/exQDESN
region/fold bundle over the seven paper quantiles.

This is not a joint model, not MCMC, and not an article or registry mutation
stage. It is a validation-selection stage.

## Scientific Contract

- Source manifest: `pricefm_stage_r69b_bounded_cran111_independent_vb_20260831`.
- Target cases: 56 unique region/fold cells.
- Quantiles: `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`.
- Fit surface per case: AL RHS-NS VB and exAL RHS-NS VB.
- Selection split: validation only.
- Test split: excluded from all R70 case configs and blocked in the runner.
- Package authority: exact CRAN `exdqlm` 1.1.1.
- Public API: `exalStaticLDVB` through the Stage-R67 adapter.
- Preserved model anchors: case-specific DESN specification and `tau0` from
  Stage-R69A.

## Implementation

The R70 case runner is:

`application/scripts/pricefm/238_run_pricefm_stage_r70_cran111_independent_vb_case.R`

It validates each config, loads the CRAN runtime manifest, builds the
train/validation adapter if needed, refuses any test adapter files, fits AL and
exAL for all seven quantiles, and writes reproducible lightweight artifacts:

- `model_predictions_scaled.csv`
- `model_beta_mean.csv`
- `model_beta_cov_diag.csv`
- `model_method_summary.csv`
- `model_parameter_summary.csv`
- `model_trace_summary.csv`
- `warm_start_diagnostics.csv`
- `r70_component_status.csv`
- `r70_case_fit_summary.json`
- `run_manifest.json`

The runner does not write `.rds`, `.rda`, `.RData`, or `.rdata` model objects.
This keeps the actual launch from consuming avoidable disk while preserving
small beta and parameter summaries for validation closeout and later frozen
test prediction audits.

The launcher is:

`application/scripts/pricefm/239_launch_pricefm_stage_r70_cran111_independent_vb.py`

It requires `--authorize true`, validates the R69B manifest and all case
configs, records `launch_preflight.json`, schedules one case per worker, pins
each worker to one logical CPU, sets numerical thread environment variables to
one, resumes completed cases, and writes `launch_status.csv` plus
`launch_summary.json`.

The monitor is:

`application/scripts/pricefm/240_monitor_pricefm_stage_r70_cran111_independent_vb.py`

It is read-only and reports completed cases, remaining cases, terminal
components, active R70 processes, binary model artifacts, disk use, and
mutation firewalls.

## Launch Command

After validation, the production launch command is:

```bash
tmux new -d -s pricefm_stage_r70_cran111_20260831 \
  'cd /data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_joint_quantile_20260824 && \
   /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python \
     application/scripts/pricefm/239_launch_pricefm_stage_r70_cran111_independent_vb.py \
     --code-root /data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_joint_quantile_20260824 \
     --manifest /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/experiment_grids/pricefm_stage_r69b_bounded_cran111_independent_vb_20260831/case_manifest.csv \
     --workers 20 \
     --cpu-list <validated-free-cpus> \
     --authorize true'
```

## Validation

Required before launch:

- Python syntax compile for R67-R70 Python scripts/tests.
- Focused pytest for R67-R70 Python tests.
- R67 CRAN adapter test.
- R70 CRAN runtime preflight test.
- Git whitespace check on new R70 files.
- Resource preflight: sufficient disk, memory, and one logical CPU per worker.

## Downstream Closeout

Stage-R71 should close out R70 by selecting winners on validation only, then
opening test metrics only for the frozen validation winners. Promotion remains
blocked unless a candidate beats both current authoritative QDESN and
operational PriceFM under the agreed seven-quantile AQL gate, with hash and
reproducibility manifests intact.
