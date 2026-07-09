# Normal/Q-DESN Unified Launcher Stage

Date: 2026-05-29

## Scope

This note records the final regularization step before the authoritative
Normal/Q-DESN comparison run. The package now has a single launch surface that
orchestrates:

- Normal DESN source-median comparison;
- Normal DESN serialized warm-start initialization comparison;
- Q-DESN implemented-mode source-median comparison.

The launcher does not reimplement model logic. It delegates to the existing
validated component scripts and normalizes their outputs into one comparison
root.

## Package Commits

Package repo:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
branch: validation/shared-fitforecast-v2-1.0.0
26284f1 Add Normal Q-DESN unified comparison launcher
63001e4 Write unified comparison console log
b415b4d Harden unified comparison preflight metadata
```

## Implemented Script

```text
scripts/run_normal_qdesn_unified_source_median_20260529.R
```

The script writes:

```text
repo_state.csv
component_runs.csv
method_summary.csv
prediction_metrics.csv
exact_equivalence.csv
approximate_diagnostics.csv
target_changing_diagnostics.csv
initializer_diagnostics.csv
forbidden_modes.csv
predictions_by_method.csv
normal_qdesn_unified_comparison_summary.md
console.log
```

The final `time.log` is supplied by the external `/usr/bin/time -v` launch
wrapper.

## Smoke Validation

Package test:

```text
tests/testthat/test-normal-qdesn-unified-comparison.R
```

Focused validation run:

```text
test-normal-qdesn-unified-comparison.R: 8 pass
test-qdesn-normal-warm-start.R: 36 pass
test-qdesn-normal-init-comparison.R: 9 pass
test-qdesn-normal.R: 144 pass
test-qdesn-vb-batching-modes.R: 42 pass
focused total: 239 pass, 0 fail
```

The unified smoke creates a tiny source directory with `series_wide.csv` and
`selection_indices.csv`, runs all three component scripts, verifies required
unified outputs, checks that exact gates pass, and checks that the warm-start
diagnostics are present.

## Authoritative Launch Command

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
mkdir -p results/normal_qdesn_unified_source_median_20260529

/usr/bin/time -v \
  -o results/normal_qdesn_unified_source_median_20260529/time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_normal_qdesn_unified_source_median_20260529.R \
  --output-dir results/normal_qdesn_unified_source_median_20260529 \
  --source-dir /data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500 \
  --seed 20260529 \
  --D 1 \
  --n 50 \
  --m 1 \
  --washout 50 \
  --chunk-size 64 \
  --subset-size 180 \
  --max-iter 25 \
  --stochastic-max-iter 60 \
  --hybrid-max-iter 60 \
  --hybrid-full-every 15 \
  --cores 4
```

## Interpretation Guardrails

- Normal DESN rows are conditional-mean Gaussian readouts.
- Q-DESN rows are tau-specific AL/exAL quantile readouts.
- Exact chunked rows are compared only to same-target unchunked references.
- Stochastic, hybrid, diagonal covariance, and Normal RHS/RHS_NS rows are
  approximate or diagnostic rows as labeled.
- Subset, rolling, posterior-as-prior, online, and initializer rows are
  target-changing or workflow diagnostics, not exact full-data replacements.

## Next Step

Run the authoritative command from package commit `b415b4d` or later, then
write the compact article result note:

```text
docs/implementation_notes/normal_qdesn_unified_source_median_comparison_20260529.md
```

Do not commit generated result files under package `results/`.
