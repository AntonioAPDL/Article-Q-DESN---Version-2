# R150 retained diagnostics

`application/scripts/pricefm/pricefm_r150_diagnostics.py` verifies and reads
the sealed official EE, DK_1, DE_LU, DK_2 and R138 negative-control forecasts.
It never imports a model engine, opens raw data values, changes original
campaigns, selects candidates/operators or runs forecasts/fits.

The reader verifies every original source/input/bank/release/raw identity,
descriptor and completion seal before array analysis. One bounded read-only
SSH batch streams the two Jerez producers as a tar; later runs verify and
reuse that archive. Remote collection writes no files. Predictions and exact
truth are already EUR/MWh, and the frozen fixed UTC+1/no-DST market clock and
equal-three-fold AQL target are preserved.

The output includes quantile reliability with strict/inclusive tie brackets,
80/50/10% coverage and widths, median error/bias, six-hour horizon blocks,
additive origin/fold/calendar influence, all six retained operators and the
paired R138-versus-R141 contrast. Missing lag-feature/training-threshold
evidence is reported explicitly. Seven quantiles do not identify a full PIT
or unidentified extreme tails; previously exposed official outcomes remain
development diagnostics.

Use the pinned Python3.11 runtime with `-B`. Run the reader once with
`--output <diagnostics_bundle> --fetch-remote`; subsequent reproductions omit
`--fetch-remote`. Run `application/tests/test_pricefm_r150_diagnostics.py` for
the analytic loss/transform/tie/weight/clock and seal/archive fault checks.

The execution report and hash ledger live in the ignored continuation bundle
`r150_cached_continuation_20261023/diagnostics`. They are diagnosis evidence,
not baseline replacement or independent confirmation.
