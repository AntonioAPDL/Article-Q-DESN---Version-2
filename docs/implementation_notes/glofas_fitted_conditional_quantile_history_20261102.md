# Historical fitted conditional quantiles: source-derived reporting helper

This module is preparation only. It provides pure functions operating on
already verified in-memory objects. It has no file-read interface, CLI,
saved-builder call, simulation, refit, scorer, article writer, or publication
action. No retained model, design, data, or truth was opened to develop it.

## Historical response and coefficient alignment

`app_make_glofas_latent_path_design()` in
`application/R/fit_qdesn_latent_path.R` constructs paired historical rows:

\[
 H_Y=(X_\beta,0),\qquad H_G=(X_\beta,X_\alpha),\qquad
 z_Y=y,\qquad z_G=g-\text{known discrepancy offset}.
\]

Thus a historical **USGS** fitted conditional quantile uses the reference
readout only. It is not a sum of separate response and discrepancy quantiles.
The helper selects by `row_info_fixed` source, feature-row index and exact
date; checks the matching stored `X_beta` rows and zero discrepancy columns;
and requires consecutive dates through 25 December 2022. It neither rebuilds
features nor evaluates a saved closure. Defaults request the 30 dates used in
the common-window display; one to thirty dates are supported for small tests.

The retained coefficient order is checked using
`core$draws$theta` column names, assigned by each core serializer. The actual
numeric operation uses only `core$summary$theta_mean`; coefficient covariance
is not needed for the mean of a linear functional and is not fabricated.

## Exact fitted functional on the transformed scale

For AL or quantile-fixed exAL at its matching probability level \(p\),

\[
 E_q\{Q_p(y_t\mid\theta_p,\sigma_p,\gamma_p,\mathcal H_{t-1})\}
 =h^Y_t{}^\top E_q(\theta_p).
\]

This follows from the quantile-location parameterization, not from adding
error means, error quantiles, a discrepancy offset, or latent future-path
moments. `gfh_transition_rows()` associates independent cores with their
frozen task level; MQ cores must follow the complete retained `joint$tau`
order. Conflicting optional per-core probability metadata is rejected.

For either enrolled Normal prior, `latent_path_vb_normal.R` stores a variance
in `variational_state$sigma`, with inverse-gamma shape/rate moments supplied
by `app_latent_ig_expectations()`. Write this variance as \(s_Y\), even though
the implementation field is named `sigma`. For \(s_Y\sim\mathrm{IG}(a_Y,b_Y)\),

\[
 E_q\{Q_p(y_t\mid\theta,s_Y,\mathcal H_{t-1})\}
 =h^Y_t{}^\top E_q(\theta)
 +\Phi^{-1}(p)\sqrt{b_Y}\,\frac{\Gamma(a_Y-1/2)}{\Gamma(a_Y)},
 \qquad a_Y>1/2,\quad b_Y>0.
\]

The half-moment is evaluated through log-gamma functions. It is
\(E_q(\sqrt{s_Y})\), **not** \(\sqrt{E_q(s_Y)}\). No fixed-scale Ridge
variant is assumed: the authenticated retained Normal Ridge and RHS cores
both use this inverse-gamma variance update. The helper rejects missing or
unnamed variance state and inadmissible shape/rate values.

Outputs identify the estimand as
`VB_mean_conditional_quantile_on_log1p_scale`. The original-scale display is
`expm1()` of that transformed-scale mean. It is **not** a posterior mean of
the original-scale conditional quantile, a historical posterior-predictive
quantile, or a 95% credible band. No monotone projection or clamping is applied;
raw crossings and negative values, if present, are preserved.

## Different historical and future quantities

These historical fitted curves must not be relabelled as the future
`marginal_future_response_quantile_under_ensemble_conditioned_VB`. That future
quantity is calculated from the retained Gaussian future-path factor as
\(m_{F,h}+\sqrt{V_{F,hh}}\Phi^{-1}(p)\). A figure joining the two time windows
must distinguish **fitted conditional quantiles** before the origin from
**ensemble-conditioned marginal response quantiles** afterward. Neither is
a 95% credible limit for a quantile functional. Figure construction and its
caption remain a later article change.

Six fitted regression families are supported: Normal Ridge/RHS, independent
AL/exAL, and MQ AL/exAL. The seventh comparison family, raw GloFAS, has one
historical retrospective product value per date. That value can appear as a
single product series; it does not identify a historical seven-quantile fan.
The issued 51-member forecast ensemble does not supply historical members.

## Later admitted use and tests

`gfh_reference_history()`, `gfh_transition_rows()` and `gfh_normal_rows()` do
not authenticate file bytes or authorize reads. The calling coordinator must
first verify 16/16 accepted producers, COMPLETE, quiescence, exact source and
target identities, original Normal enrollment/design mapping, and a fresh
finite model/design-read purpose. The native collector must authenticate the
model payloads and their task/block association before those objects are
deserialized. Do not use this pure helper as an alternative to those gates.
Any later guarded materializer needs its own explicit source/purpose pins and
closed runtime receipt; no such actual read or materialization is authorized
by this change.

The standalone generated test is
`application/tests/test_glofas_same_family_fitted_history.R`. It tests the
source schema and date/source/feature alignment, both AL families and MQ
blocks, the Normal half-moment against independent numerical integration,
inverse-transform and estimand labels, retained crossings, absent covariance,
and malformed/mismatched states. It calls no retained-object reader or RNG.
The shared test registry is intentionally left to the integration coordinator.
