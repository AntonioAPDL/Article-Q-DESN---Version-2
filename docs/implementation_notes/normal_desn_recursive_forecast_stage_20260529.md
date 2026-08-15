# Normal DESN Recursive Forecast Stage

Date: 2026-05-29

## Scope

This stage adds recursive forecast paths for `qdesn_normal_fit` in the package
worktree:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
```

The implementation is intentionally narrow and safe:

- supports standard univariate raw-y-lag reservoir inputs;
- supports reservoir-only readout designs;
- uses Normal DESN posterior draws for beta and `omega2`;
- recursively samples future Normal observations;
- supports teacher-forced `y_future_obs`;
- fails early for exogenous, decomposition, origin-state override, readout-spec
  override, and reservoir-lag forecast controls.

This avoids reusing AL/exAL latent-noise forecast machinery for a Gaussian
readout.

## API

```r
forecast_paths.qdesn_normal_fit(
  object,
  H,
  nd = 1000L,
  y_hist = NULL,
  seed = NULL,
  draws = NULL,
  y_future_obs = NULL,
  return_design = FALSE,
  ...
)
```

Output fields include:

```text
yrep
mu_draws
beta
omega2
nd
H
design
target
forecast_family = normal_recursive
```

## Forecast Recursion

For posterior draw `s` and horizon step `h`:

```text
beta^(s), omega2^(s) ~ Normal DESN readout posterior
x_{T+h}^{(s)}        = DESN feature recursion from the current path history
mu_{T+h}^{(s)}       = x_{T+h}^{(s)'} beta^(s)
y_{T+h}^{(s)}        = mu_{T+h}^{(s)} + eps_{T+h}^{(s)}
eps_{T+h}^{(s)}      ~ N(0, omega2^(s))
```

If `y_future_obs[h]` is finite, the observed value is inserted into the
recursive history for future reservoir inputs.

## Validation

Focused package test:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-qdesn-normal.R")'
```

Result:

```text
test-qdesn-normal.R: 144 pass, 0 fail
```

The tests verify:

- reproducible recursive paths under fixed seed;
- finite `yrep` and `mu_draws`;
- correct `H x nd` dimensions;
- optional design array dimensions;
- posterior-draw reuse through the Normal readout path;
- teacher forcing through `y_future_obs`;
- early failures for unsupported exogenous controls and malformed future
  observations.

## Limitations

The function does not yet implement:

- exogenous forecast inputs;
- decomposition-aware inputs;
- explicit origin-state override;
- reservoir-lag readout forecasts;
- lattice forecasts.

Those should be added only after a separate Normal DESN forecast contract is
written and tested.

## Next Stage

The next documentation step is to update the Normal/Q-DESN method availability
matrix so the implemented Normal DESN pieces are visible alongside Q-DESN
AL/exAL modes.
