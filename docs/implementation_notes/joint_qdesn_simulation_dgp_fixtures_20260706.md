# Joint QDESN Simulation DGP Fixture Layer

Date: 2026-07-06

This note documents the long-series fixture layer for the new joint QDESN
simulation study. It follows the same reproducibility discipline as the
article-facing TT500 validation: explicit registry, fixed seeds, frozen
fixtures, oracle quantiles, split metadata, forecast-origin plan, provenance,
and SHA-256 artifact manifest.

This stage prepares data only. It does not fit VB or MCMC models.

## Files

Implemented files:

- `application/config/joint_qdesn_simulation_dgp_registry_20260706.csv`
- `application/R/joint_qdesn_simulation_fixtures.R`
- `application/scripts/98_generate_joint_qdesn_simulation_dgp_fixtures.R`
- `application/tests/test_joint_qdesn_simulation_dgp_fixtures.R`

Default artifact directory:

`application/cache/joint_qdesn_simulation_dgp_fixtures_20260706`

## Registry Design

The default registry contains nine enabled scenarios:

- Gaussian bridge;
- Laplace bridge;
- Gaussian-mixture bridge;
- Student-t location-scale;
- asymmetric-Laplace tail;
- heteroskedastic seasonal;
- persistent heavy-tail;
- regime shift;
- nonlinear reservoir-friendly Gaussian mixture.

Each scenario uses the seven-level tau grid

`0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`.

The registry records:

- scenario id, class, distribution family, and dynamics class;
- full simulated length;
- DGP warmup length;
- effective length;
- last-analysis-window geometry;
- DESN washout, fit, and validation lengths;
- forecast-origin stride and maximum lead;
- seed and seed role;
- DGP parameters;
- truth quantile method.

## TT500-Like Windowing

The fixture layer intentionally uses the last 2000 effective observations,
mirroring the validated TT500 handoff pattern.

Default geometry:

| Component | Value |
|---|---:|
| Full simulated length | 12000 |
| DGP warmup | 2000 |
| Effective series | 10000 |
| Effective pre-analysis buffer | 8000 |
| DESN washout | 500 |
| Fit window | 500 |
| Validation window | 1000 |

In full-time indices this gives:

- DGP warmup: 1--2000;
- effective pre-analysis buffer: 2001--10000;
- DESN washout: 10001--10500;
- fit window: 10501--11000;
- validation window: 11001--12000.

In effective-series indices this gives:

- DESN washout: 8001--8500;
- fit window: 8501--9000;
- validation window: 9001--10000.

This is intentionally close to the TT500 configuration where the fit window is
near the end of a long source series and the forecast block is held out.

## Forecast-Origin Plan

The fixture layer writes a forecast-origin plan but does not fit or forecast.

Default protocol:

- origin stride: 30;
- scored leads: 1--30;
- no coefficient refit inside the validation blocks;
- fixed fit window for the first VB validation stage;
- no future validation observations enter the fit window.

For a 1000-row validation window, this creates 33 complete origin blocks and
scores 990 lead-target pairs per scenario per model/tau grid.

## Artifacts

The materializer writes:

- `run_config.csv`
- `frozen_registry.csv`
- `scenario_summary.csv`
- `observed_series.csv`
- `design_matrix.csv`
- `true_quantile_wide.csv`
- `true_quantile_long.csv`
- `split_metadata.csv`
- `dgp_parameters.csv`
- `forecast_origin_plan.csv`
- `oracle_policy.csv`
- `crossing_summary.csv`
- `fixture_validation.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

All outputs are CSV/README files and every output is hashed in
`artifact_manifest.csv`.

## Gates

The fixture validation layer checks:

- registry schema and unique scenario ids;
- TT500-like geometry consistency;
- finite observations;
- finite design features;
- finite true quantiles;
- positive scale paths;
- monotone oracle quantiles;
- zero true quantile crossings;
- expected role lengths;
- nonempty forecast-origin plans;
- complete artifact manifest hashes.

Hard failures here block VB fit/forecast validation.

## Commands

Default materialization:

```bash
Rscript application/scripts/98_generate_joint_qdesn_simulation_dgp_fixtures.R
```

Targeted materialization:

```bash
Rscript application/scripts/98_generate_joint_qdesn_simulation_dgp_fixtures.R \
  --scenario-ids normal_bridge,gaussian_mixture_bridge \
  --output-dir application/cache/joint_qdesn_simulation_dgp_fixtures_targeted_20260706
```

Focused test:

```bash
Rscript application/tests/test_joint_qdesn_simulation_dgp_fixtures.R
```

## Next Stage

The next stage is the VB fit-validation runner over these frozen fixtures. It
should consume `observed_series.csv`, `design_matrix.csv`,
`true_quantile_wide.csv`, `split_metadata.csv`, and `forecast_origin_plan.csv`.

The model set should be:

- `JOINT QDESN RHS`;
- `JOINT exQDESN RHS`;
- independent `QDESN RHS`;
- independent `exQDESN RHS`.

MCMC remains deferred until the VB fit and forecast stages are stable.
