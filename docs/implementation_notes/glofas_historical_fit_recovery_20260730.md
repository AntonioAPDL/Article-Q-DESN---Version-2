# GloFAS historical-fit recovery workflow

This workflow reconstructs and tests the GloFAS Q-DESN specification that
produced the strongest remembered pre-cutoff visual fit before forecast-window
scores became the primary tuning target.

## Scientific question

The historical candidate used a shallow `D=1`, `n=300`, `m=360` reservoir with
`alpha=0.92`, but it also supplied 1,082 lagged response and covariate features
directly to each readout. Recent searches generally disabled that direct block.
The recovery experiment therefore tests the direct readout block, lag length,
leak rate, and RHS prior in a small mechanism-focused design.

Median-only screening reports MAE, RMSE, bias, and check loss. The field
`p50_degenerate_crps_proxy_mean` is retained only for compatibility and is
explicitly the MAE of a degenerate point distribution. It is not the CRPS of
the intended seven-quantile synthesized distribution.

The `log1p` scale is primary because it is the fitted response scale. Original
streamflow metrics and upper-event errors are mandatory sensitivity checks.
The observational window includes the forecast-origin cutoff date and excludes
only targets after that date.

## Reproducible stages

1. `glofas_fit_recovery_prepare.R` materializes an ignored runtime directory,
   rewrites input paths to the authoritative Version-2 data root, copies a
   checksummed allowlist of historical evidence, and writes candidate configs.
2. The ordinary input audit and panel builder create one shared read-only panel.
3. `glofas_fit_recovery_design_audit.R` constructs the exact historical design
   without fitting and compares it with the retained historical contract.
4. `glofas_fit_recovery_rescore_history.R` scores the retained historical paths
   on common dates and both response scales.
5. `glofas_fit_recovery_scheduler.py` launches bounded, single-threaded p50
   fits only when load, memory, and disk gates permit. It preserves failed
   states by default; `--retry-failed` must be supplied explicitly after the
   failure has been diagnosed and corrected.
6. Each worker runs the standard fit, scoring, output, and post-analysis stages,
   then writes compact observed-fit scores and a completion marker.
7. `glofas_fit_recovery_health.py` reconciles scheduler state, worker markers,
   process liveness, stage progress, scores, logs, and resource headroom.
8. Heavy objects are not deleted while fits are active. The cleanup helper
   requires a completed run, an explicit execution flag, and a target inside
   the declared recovery root.

## Selection boundary

The p50 batch identifies mechanisms and candidates. It cannot select an
authoritative distributional model. Strong p50 candidates must subsequently
pass independent p05/p50/p95 triage and a full seven-quantile observational
CRPS confirmation before any article promotion.

Forecast-window outcomes are excluded from recovery ranking. They are examined
only after the observational winner is frozen.

## Safety boundaries

- Runtime artifacts live below
  `local_trackers/runtime_configs/glofas_fit_recovery_20260730`.
- Historical repository paths are read-only evidence sources.
- The authoritative data root is read-only.
- The frozen engine commit is `73c043f0436b508808366f312350fd44c2d06771`.
- Every fit is limited to one BLAS/OpenMP thread.
- The scheduler is resumable and supports a stop file.
- No manuscript file is changed by this workflow.
