# GloFAS Latent-Path Ensemble-Likelihood Contract

Date: 2026-05-13

## Statistical Objects

Let \(T\) denote the forecast origin and let \(H\) denote the largest
available issued GloFAS horizon after applying the requested cutoff window.
If the configured horizon is longer than the archived issued ensemble coverage,
the effective analysis horizon is reduced to the largest contiguous available
horizon. Historical observations are available through \(T\). The future USGS
values \(Y_{T+1:T+H}\) are not observed at the forecast origin and are treated
as latent missing data.

Observed rows:

- historical USGS observations \(Y_t\), \(t \le T\);
- retrospective GloFAS values \(G^{\mathrm{retro}}_t\), \(t \le T\);
- issued GloFAS ensemble members \(G^{\mathrm{ens}}_{T,h,j}\),
  \(h=1,\ldots,H\), \(j=1,\ldots,J\).

Latent forecast-window objects:

- future USGS path \(Y_{T+1:T+H}\);
- future reservoir states determined by that path and origin-available
  covariates;
- shared reference quantile path \(q_t\);
- GloFAS discrepancy path \(\delta_t\).

The readout locations are

```text
q_t     = x_t' beta,
delta_t = z_t' alpha,
q_G,t   = q_t + delta_t.
```

For the first prototype, the shared quantile and discrepancy may use the same
future state block with different readout coefficients. A second discrepancy
reservoir can be added only after the one-state latent-path model is validated.

## Likelihood Ownership

Let \(L_{p_0}\) denote either the AL or exAL working likelihood at level
\(p_0\). For AL, the \(\gamma\) terms below are absent. The historical
reference rows use the reference location:

```text
Y_t ~ L_p0(q_t, sigma_Y, gamma_Y), t <= T.
```

The retrospective GloFAS rows use the GloFAS-side location:

```text
G^retro_t ~ L_p0(q_t + delta_t, sigma_G, gamma_G), t <= T.
```

The issued GloFAS ensemble rows also use the GloFAS-side location:

```text
G^ens_{T,h,j} ~ L_p0(q_{T+h} + delta_{T+h}, sigma_G, gamma_G).
```

The parameters \(\sigma_G\) and, for exAL, \(\gamma_G\), are shared across
retrospective and issued GloFAS rows. This is the main difference from the
origin-state bridge, where issued ensemble values can be used as post-fit
forecast inputs rather than likelihood rows in the same posterior target.

## Future-State Recursion

For \(t \le T\), the reservoir states are computed once from observed inputs.
For \(t > T\), states are deterministic functions of:

- the stored state at the forecast origin;
- observed historical lags while available;
- strictly lagged latent future USGS values when output lags extend beyond
  \(T\);
- origin-available forecast covariates.

Thus future design rows are not fixed before fitting. They must be recomputed
inside inference whenever the latent future path changes. Only the \(H\)
forecast-window states need to be recomputed; historical states are fixed.
The output-lag convention must exclude the contemporaneous value: the design
row for target \(T+h\) may use \(Y_{T+h-1},Y_{T+h-2},\ldots\), but not
\(Y_{T+h}\) itself. This prevents circular use of the response in its own
readout row.
The current continuation helper supports response-lag reservoir inputs and
deterministic precipitation and soil-moisture covariates inside the reservoir
recursion. Forecast-window covariates must remain origin-available and audited.
Direct readout covariates can still be handled separately from the state
recursion when a configuration explicitly enables the direct input block.

## Derivation Checklist

The supplement derivation should be developed in this order.

1. Define the joint posterior for
   \[
   p(\theta,Y_{T+1:T+H}\mid
   Y_{1:T},G^{\mathrm{retro}}_{1:T},G^{\mathrm{ens}}_{T,1:H,1:J}).
   \]
2. Show that \(H=0\) reduces to the fixed-design discrepancy posterior.
3. Show that a fixed future path reduces the forecast-window update to the
   source-stacked regression form.
4. Derive the AL variational target first, with the future reference path,
   output-lag recursion, and forecast-window covariates in the same
   approximation. The nonlinear state recursion means that the future-path
   factor is handled by a model-specific Laplace--Delta approximation, not by
   the fixed-design CAVI routine alone.
5. Derive AL-MCMC as the posterior simulation reference after the AL-VB path
   passes synthetic checks.
6. Extend to exAL only after the AL-VB and AL-MCMC implementations agree on
   synthetic and small real-data checks.

## Implementation Gate

No real GloFAS latent-path fit should be interpreted until these checks pass:

- future-state continuation matches a direct full-history reservoir build when
  the held-out future path is supplied as a validation oracle;
- no post-cutoff observed USGS value enters a model input except as a latent
  sampled value;
- GloFAS ensemble rows update the common GloFAS scale and, for exAL, the common
  GloFAS asymmetry parameter;
- AL-VB recovers known synthetic paths and records a stable Laplace--Delta
  ELBO approximation;
- AL-MCMC recovers known synthetic paths and provides a reference comparison
  for AL-VB;
- exAL-VB and exAL-MCMC recover known synthetic paths before exAL is used in
  the application.
