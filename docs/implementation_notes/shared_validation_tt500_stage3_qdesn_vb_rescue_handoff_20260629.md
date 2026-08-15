# Shared Validation TT500 Stage 3 Q-DESN VB Rescue Handoff

Date: 2026-06-29

This note documents the article-side promotion of the completed Q-DESN TT500
VB Stage 3 forecast-bias rescue. The promotion is deliberately narrow: it
updates only three Q-DESN VB exAL RHS summary rows in the final TT500 manuscript
tables and leaves the pinned DQLM/exDQLM, Q-DESN MCMC, and non-targeted Q-DESN
VB rows unchanged.

## Validation Evidence

- validation worktree: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- validation branch: `validation/shared-fitforecast-v2-1.0.0`
- validation commit: `203f47adcbd417827e26e8efaf36f120e075fbf3`
- run tag: `qdesn-tt500-vb-stage3-forecast-bias-rescue-full-20260628`
- report root: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/reports/qdesn_mcmc_validation/qdesn_dynamic_fitforecast_v2_tt500_vb_stage3_forecast_bias_rescue/qdesn-tt500-vb-stage3-forecast-bias-rescue-full-20260628/20260628-114648__git-203f47a`
- results root: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/qdesn_mcmc_validation/qdesn_dynamic_fitforecast_v2_tt500_vb_stage3_forecast_bias_rescue/qdesn-tt500-vb-stage3-forecast-bias-rescue-full-20260628/20260628-114648__git-203f47a`

The strict post-run audit records 144 expected roots, 144 successful roots, no
failures, no running roots, no forbidden binary payloads, and complete generic
and dominance ranking artifacts.

## Promoted Profile

Primary promoted profile:

`tt500vb_f3_d1_n30_a0p02_r0p45_m15_lag15_rl0_pw0p03_pin0p3`

Specification:

| field | value |
|---|---:|
| D | 1 |
| n_each | 30 |
| alpha | 0.02 |
| rho | 0.45 |
| m | 15 |
| readout_y_lags | 15 |
| reservoir_lags | 0 |
| pi_w | 0.03 |
| pi_in | 0.3 |

This profile is promoted only for:

| family | tau | model row |
|---|---:|---|
| Gaussian mixture | 0.25 | Q-DESN exAL RHS, VB--LD |
| Gaussian | 0.25 | Q-DESN exAL RHS, VB--LD |
| Gaussian | 0.50 | Q-DESN exAL RHS, VB--LD |

## Article Wiring

The active config is:

`application/config/shared_validation_tt500_final_fitforecast.yaml`

The table builder is:

`application/scripts/31_build_shared_validation_tt500_final_tables.R`

The builder first validates the original pinned lead-level interfaces. It then
applies the Stage 3 summary override only if all configured hashes match, the
strict audit is ready, the primary profile passes dominance, and each
replacement row beats all primary DQLM/exDQLM VB baselines.

Generated outputs:

- `tables/qdesn_validation_tt500_final_summary.csv`
- `tables/qdesn_validation_tt500_final_tables.tex`
- `tables/qdesn_validation_tt500_final_protocol.tex`
- `tables/qdesn_validation_tt500_final_normal.tex`
- `tables/qdesn_validation_tt500_final_laplace.tex`
- `tables/qdesn_validation_tt500_final_gausmix.tex`
- `tables/qdesn_validation_tt500_final_manifest.txt`

The generated manifest records the exact original and replacement forecast
metrics for each overridden row.

## Rebuild Command

```bash
Rscript application/scripts/31_build_shared_validation_tt500_final_tables.R
```

Expected terminal summary:

```text
TT500 final manuscript tables: PASS
summary_rows: 108
lead_rows_consumed: 3240
```

The generated protocol table should report `Summary overrides = 3`.

## Guardrails

The article must continue to fail on:

- stale `/home/jaguir26/local/src` paths;
- old 0.5.0 validation worktrees or branch names;
- missing or changed Stage 3 artifact hashes;
- missing strict audit readiness;
- replacement rows that do not pass all primary dominance checks;
- accidental broad replacement of non-targeted rows.

The Stage 3 summary override is an article-facing table promotion, not a
replacement for the shared validation logic. Any future TT100, TT5000, or MCMC
study should receive its own pinned validation handoff and should not silently
reuse this override.
