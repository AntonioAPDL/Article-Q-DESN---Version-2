# PriceFM R131: frozen-receiver causal seasonal controls

The completed R130 oracle diagnosis motivates a bounded validation-only
comparison of previous-day and previous-week price drivers. No fit, DESN,
prior, scaler, posterior approximation, official test prediction or article
authority is changed. Exact R130/R129B/R128/R127 sources remain dependencies.

For each first forecast timestamp t0 and quarter-hour h=0,...,95, the two
drivers supply y(t0+h-96) and y(t0+h-672). These indices are strictly before
t0. Both drivers update all DESN layers using only the generated price prefix,
with teacher forcing between origins and unchanged future exogenous inputs.
The receivers reuse R130's exact S500 coefficient draws and clipped seven-knot
CDF pooling. Deterministic drivers need only one reservoir trajectory; this
is exactly equivalent to repeating that trajectory for every coefficient draw.

The 288 matched validation origins cover HR and DK_1, three folds and four
fixed market clocks. R130 controls are reused, not re-fitted or re-generated.
Smoke tasks independently verify their complete stochastic forecasts before
admitting remaining chunks. Both hosts must pass source-matched tests first.

The schedule caps at 30 distinct idle physical cores on Jerez, one numerical
thread per task, with two physical-core groups and 200 GiB RAM/disk reserved.
All source/input and completed artifact hashes are checked. No predecessor
artifact is overwritten, removed or relocated; results remain ignored.

Seasonal controls are not automatically selected probabilistic models. Their
lack of driver innovation uncertainty must be evaluated alongside AQL, coverage
and width. Oracle remains diagnostic only. Historical window exposure,
retrospective realized exogenous inputs, VB uncertainty and CDF completion
limitations remain explicit. A driver correction, official test reforecast or
all-region deployment requires a separate scientifically justified stage.
