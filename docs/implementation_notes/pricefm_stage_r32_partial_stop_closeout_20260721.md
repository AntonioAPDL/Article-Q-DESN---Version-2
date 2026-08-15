# PriceFM Stage-R32 partial stop closeout and lean redesign note

Date: 2026-07-21

## Scope

This note documents the manual stop, read-only partial closeout, and guarded
cache cleanup for the PriceFM Stage-R32 large-capacity/history launch:

- Run tag: `pricefm_stage_r32_large_capacity_history_20260714`
- Run root: `application/data_local/pricefm/runs/pricefm_stage_r32_large_capacity_history_20260714`
- Prep root: `application/data_local/pricefm/authoritative/pricefm_stage_r32_large_capacity_history_launch_prep_20260714`
- Closeout root: `application/data_local/pricefm/authoritative/pricefm_stage_r32_partial_stop_closeout_20260721`

The work is PriceFM-only. It does not mutate the registry, manuscript, article
repo, or non-PriceFM application code.

## Why R32 was stopped

R32 was designed as an expensive large-capacity/history search over 480 planned
rows. By 2026-07-21, it had produced a very small amount of completed evidence
relative to its resource burn:

- 480 planned rows
- 9 completed experiment directories with metric summaries
- 18 QDESN/exQDESN metric rows
- 7 failed rows, mostly return-code-137 failures
- 20 manually stopped run directories without metrics
- 444 queued/not-started rows
- 0 completed metric rows beating current authoritative Q-DESN on test
- 0 completed metric rows beating cached PriceFM on test
- 0 completed metric rows beating both references

The active R32 workers were consuming large memory, with several live R workers
around tens of GiB RSS. After stopping only the R32 process group, R30 remained
alive and system memory pressure dropped sharply.

## What was implemented

Added:

- `application/scripts/pricefm/156_closeout_pricefm_stage_r32_partial_stop.py`
- `application/tests/test_pricefm_stage_r32_partial_stop_closeout.py`

The script:

- reads the Stage-R32 launch manifest, case plan, run root, logs, and completed
  metric summaries;
- classifies each planned row as completed, failed, manually stopped, or queued;
- recomputes validation-selected and test-oracle partial rows;
- audits test performance against current Q-DESN and PriceFM references from the
  launch manifest;
- writes reproducible CSV/JSON/Markdown closeout artifacts;
- keeps registry, manuscript, launch, and MCMC gates blocked;
- optionally deletes only reconstructable heavy cache files under the R32 run
  root, guarded by a no-R32-process check.

Validation:

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/156_closeout_pricefm_stage_r32_partial_stop.py

application/data_local/pricefm/venv/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r32_partial_stop_closeout.py
```

Result: `2 passed`.

## Materialized outputs

Closeout outputs:

- `pricefm_stage_r32_partial_run_status.csv`
- `pricefm_stage_r32_partial_metric_rows.csv`
- `pricefm_stage_r32_partial_validation_selected_case.csv`
- `pricefm_stage_r32_partial_test_oracle_case.csv`
- `pricefm_stage_r32_partial_capacity_diagnostics.csv`
- `pricefm_stage_r32_partial_failure_summary.csv`
- `pricefm_stage_r32_partial_closeout_gates.csv`
- `pricefm_stage_r32_partial_next_design_recommendations.csv`
- `pricefm_stage_r32_partial_cleanup_manifest.csv`
- `pricefm_stage_r32_partial_cleanup_summary.json`
- `pricefm_stage_r32_manual_stop_evidence.json`
- `source_manifest.csv`
- `summary.json`
- `pricefm_stage_r32_partial_stop_closeout_report.md`

Cleanup result:

- 236 reconstructable heavy cache files removed
- 60,789,151,879 bytes removed
- no cleanup errors
- no remaining R32 `.rds/.rda/.RData/.rdata`, `X_*`, `y_*`, `rows_*`, or
  `feature_map_matrix.npz` files under the R32 run root
- metric summaries, status files, configs, logs, reports, and source manifests
  were retained

## Main scientific diagnosis

The partial evidence does not support resuming the same R32 design. The best
completed R32 candidate is still far from PriceFM:

- best completed R32 row: `r32_no5_f3_capl300d3n100balancedfinallayer_141b47b2`
- method: `qdesn_exal_rhs_ns_exact_chunked`
- test AQL: `5.016736`
- current Q-DESN AQL: `4.058703`
- cached PriceFM AQL: `3.732891`
- test minus current Q-DESN: `0.958033`
- test minus PriceFM: `1.283845`

Completed rows using larger or deeper capacity were worse, not better. The
observed pattern supports a leaner, more targeted design rather than completing
the remaining R32 queue.

## Recommended next design direction

Do not relaunch R32 as-is. After the still-running R30 launch closes out, design
the next launch around memory-normalized, case-specific candidates:

- `n_per_layer`: use `48,64,96`; allow `128` only for a tiny audited subset.
- `D`/depth: use `2,3`; keep `4` out of the default grid.
- lag window `m`: use `96,168,240`; avoid `500` by default.
- readout: prioritize `final_layer`; allow concat only when `n <= 64` and
  `D <= 3`.
- regularization: keep the R30/R32 regimes but shift smaller models toward
  stronger shrinkage, such as `alpha` in `0.35-0.50`, `rho` in `0.82-0.90`,
  `input_scale` in `0.20-0.35`, and `tau0` in `0.001-0.002`.
- targeting: choose cases after R30 closeout using validation-only selection and
  test metrics as audit-only.

Blocked actions remain:

- do not mutate the PriceFM registry;
- do not update article/manuscript assets from R32;
- do not launch the next grid until R30 is closed out and the lean target set is
  frozen;
- do not start MCMC confirmation unless a validation-selected VB candidate beats
  both current Q-DESN and cached PriceFM.
