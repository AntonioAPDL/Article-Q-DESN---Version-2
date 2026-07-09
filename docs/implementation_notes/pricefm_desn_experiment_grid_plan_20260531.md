# PriceFM DESN Experiment Grid Plan, 2026-05-31

## Status

This note is a preparation artifact. No new model grid was launched as part of
this pass.

PriceFM R binary cleanup was checked under:

```text
application/data_local/pricefm
```

No `.rds`, `.rda`, or `.RData` files were present, so no PriceFM R binary
artifacts were removed.

## Current Evidence

The recent PriceFM median runs show that the current DESN/RHS setup is not yet a
strong baseline for `DE_LU`, fold 1.

| run | lag window | selected train origins | readout features | RHS tau0 | best model AQL | naive1 AQL |
|---|---:|---:|---:|---:|---:|---:|
| `desn_model_full_median_warmstart_20260530` | 96 | 973 | 31 | 1e-4 | 15.159 | 14.009 |
| `desn_model_full_median_warmstart_lag8640_n500_20260531` | 8640 | 500 | 31 | 1e-4 | 21.856 | 14.016 |
| `desn_model_full_median_warmstart_lag8640_n3000_tau0_1e2_20260531` | 8640 | 884 | 31 | 1e-2 | 21.243 | 14.010 |

The 90-day lag runs are much worse than the simple previous-day baseline. The
`n=3000` request could not literally select 3000 daily origins on fold 1:
`L=8640` leaves only 884 contained train origins. The adapter correctly records
requested, available, and selected origins.

## Interpretation

The current failure is probably not a VB convergence failure. All fitted models
converged, exact chunking gates passed, and diagnostic traces were produced.

The more likely issue is the feature specification:

- `L=8640` creates a very high-dimensional raw history, but `feature_dim=30`
  compresses it aggressively through one random tanh projection.
- Electricity prices have very strong recent, daily, and weekly structure; a
  random projection of 90 days can wash out these signals.
- The naive baselines are strong because they directly encode recent seasonal
  persistence.
- The direct-horizon readout pools all horizons in one coefficient vector. The
  horizon one-hot features help, but they may not fully replace horizon-specific
  dynamics.

The original `L=96` run is the closest to useful. The next grid should therefore
screen mostly shorter lag windows and larger feature dimensions before spending
more time on 90-day windows.

## Prepared Grid

Tracked grid specification:

```text
application/config/pricefm_desn_experiment_grid_median_de_lu_20260531.yaml
```

Tracked preparation script:

```text
application/scripts/pricefm/12_prepare_desn_experiment_grid.py
```

Tracked parallel launcher:

```text
application/scripts/pricefm/13_run_desn_experiment_grid.py
```

The script only materializes configs. It does not build windows or launch model
fits.

Generate ignored per-experiment configs with:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_20260531.yaml \
  --write
```

Generated configs and manifest will live under:

```text
application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_spec_screen_20260531
```

The launcher can then run selected generated configs concurrently. Because the
current screen is one region and one fold, `10_run_desn_model_full.py --jobs`
does not create useful parallelism by itself; each config has one cell. The
launcher parallelizes across experiment configs and keeps a separate log per
experiment:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_20260531.yaml \
  --priorities 1 \
  --experiment-jobs 3 \
  --cell-jobs 1 \
  --build-windows false \
  --dry-run true
```

Set `--dry-run false` only when intentionally launching. For windows that are
not already built, set `--build-windows true`; window builds are performed once
per distinct generated data config before the model fits.

## Screening Design

The first screen is deliberately single-region, single-fold:

- Region: `DE_LU`
- Fold: `1`
- Quantile: median only, `tau = 0.50`
- Horizons: all 96 horizons
- Ranking split: validation
- Audit split: test
- Ranking metric: original-unit AQL
- Models per experiment:
  - normal DESN scaled ridge
  - normal DESN RHS_NS
  - Q-DESN AL RHS_NS exact chunked
  - Q-DESN exAL RHS_NS exact chunked
- Intercept shrinkage: disabled
- Train-origin request: 3000, with available/selected counts recorded

Primary screen:

| priority | lag | feature_dim | tau0 values | reason |
|---:|---:|---:|---|---|
| 1 | 96 | 60, 120, 240 | 1e-4, 3e-4, 1e-3, 3e-3, 1e-2 | Recent daily context is currently closest to useful. |
| 1 | 192 | 60, 120, 240 | 3e-4, 1e-3, 3e-3 | Two-day context tests whether one day is too short without jumping to one week. |
| 1 | 96 | 120 | projection_scale 0.5, 1.0, 2.0 at tau0 1e-3 | Checks whether tanh random features are under-scaled or saturated. |
| 1 | 96 | flat direct | tau0 1e-3 | Diagnostic for whether random projection is the bottleneck. |
| 2 | 672 | 120, 240 | 3e-4, 1e-3, 3e-3, 1e-2 | One-week context may capture weekly seasonality without 90-day dilution. |
| 2 | 1344 | 120, 240 | 1e-3, 3e-3 | Two-week extension only after the short-window screen. |

Secondary screen:

| priority | lag | feature_dim | tau0 values | reason |
|---:|---:|---:|---|---|
| 3 | 2688 | 240, 480 | 1e-3, 3e-3, 1e-2 | Four-week context with less severe compression. |
| 4 | 8640 | 240, 480 | 3e-3, 1e-2 | Revisit 90 days only with much wider projection. |

Seed robustness should be run only after the first ranking pass identifies a
promising spec.

## Additional Feature Diagnostics

The adapter now records `projection_scale` and per-split pre-tanh activation
summaries for `window_desn_v1`:

- mean and standard deviation;
- minimum and maximum;
- fraction with absolute pre-activation greater than 2;
- fraction with absolute pre-activation greater than 4.

These diagnostics are intended to distinguish a prior/VB issue from a feature
map issue. If the pre-tanh values are almost all near zero, the random feature
map is close to linear. If many values exceed four in absolute value, tanh is
saturated and information is likely being discarded.

## Parallel Launch Policy

Use experiment-level parallelism for the single-region/fold screen:

- priority 1: `--experiment-jobs 3`, `--cell-jobs 1`;
- priority 2: `--experiment-jobs 2`, `--cell-jobs 1`;
- priority 3/4: `--experiment-jobs 1`, `--cell-jobs 1`.

This keeps memory bounded because each experiment can allocate its own adapter
matrices and R process. Increase `experiment-jobs` only after observing peak RSS
in the logs.

Priority 1 should be the first actual launch. Priority 3/4 long-context
experiments should not be launched until the shorter windows have been ranked.

## Validation Criteria

Each launched experiment should pass:

- completed cell status;
- finite predictions and metrics;
- all fitted models converged or documented non-convergence;
- exact chunked AL equivalence gate;
- no warm-start fallback unless explicitly documented;
- trace and parameter CSVs written;
- diagnostic figures written;
- model outputs remain under ignored local paths;
- generated windows/configs record hashes and selected origin counts.

Ranking should be by validation AQL first. Test AQL should be treated as an
audit, not the selection criterion.

## If The Grid Still Fails

If the best screened DESN remains worse than naive by a large margin, the next
step should not be more `tau0` tuning. It should be a feature-map improvement:

- add seasonal lag-anchor features such as previous day/week same horizon;
- add rolling summaries over recent lag windows;
- add separate recent and seasonal projection blocks;
- consider horizon-group or horizon-specific readouts;
- keep the current random projection as one block, not the whole design.

Those changes would require adapter extensions and new tests before any broad
run.
