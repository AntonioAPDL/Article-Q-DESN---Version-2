# PriceFM R132: forward-only stochastic-driver calibration

R132 is a bounded continuation of the completed R130/R131 diagnosis. It does
not refit a Normal or quantile model, change a DESN specification, inspect the
official test window for selection, or replace an article result. Exact R127,
R128, R130 and R131 sources and runtime artifacts are read-only dependencies.

The calibration question is deliberately narrow: can a small correction to
the existing stochastic Normal RHS driver improve recursive quantile-receiver
forecasts while retaining driver uncertainty? Four prespecified candidates are
considered: identity, location only, scale only, and location plus scale. The
location correction consists of a global residual mean plus shrunken target-
hour and lead-block effects. The scale correction is a shrunken lead-block
multiplier. Scale is applied to the complete driver ensemble around its current
mean, preserving path dependence and stochastic recursion.

Candidate evaluation is forward-only inside R128's training support. Split 2
is evaluated using a map estimated from split 1; split 3 uses splits 1 and 2.
The candidate must improve mean forward AQL by at least one percent and may not
lose by more than 0.5 percent on either forward split. Otherwise identity is
selected. A final map is then estimated from all three permitted internal
residual banks. R130/R131 validation outcomes, oracle values, and official test
scores never enter map estimation or candidate selection.

The final map is replayed through the frozen R130 independent AL-VB receivers
on the same 288 held-out validation origins. Normal and quantile posterior
draws, S500, source data, scalers, DESN states, teacher forcing between origins,
recursive forecasting within an origin, and pooled-CDF scoring are unchanged.
This replay is developmental evidence only. It may justify additional region
pilots, but cannot authorize an all-region launch or article promotion.

The ignored execution plan is
`local_trackers/pricefm_stage_r132_stochastic_driver_calibration_master_plan_20261011.md`.
All banks, maps, predictions, logs, receipts and reports remain under ignored
`application/data_local/pricefm`. No predecessor output is overwritten,
deleted, moved or compacted by this stage.

R128 is deliberately not represented as a completed end-to-end campaign. Its
internal ridge/RHS selection, frozen choices, training banks and winning split
fits completed and were sealed before its later nested quantile queue stopped.
R132 verifies and uses only that completed internal Normal phase. Its frozen
receiver lineage comes from the subsequently repaired R129/R130 artifacts.
The exact R130 cell and task contract is read from R131's sealed preparation,
which copied that lineage before R130's duplicate preparation file was removed;
the predictions themselves remain the sealed R130 task packets.
