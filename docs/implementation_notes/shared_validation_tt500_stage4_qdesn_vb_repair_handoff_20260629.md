# Shared Validation TT500 Stage 4 Q-DESN VB Repair Handoff

Date: 2026-06-29

This note documents the Article-Q-DESN promotion of the completed Q-DESN TT500
VB Stage 4A/4B remaining-cell repair. The promotion updates six Q-DESN VB
exAL RHS summary rows in the final TT500 manuscript tables. It does not change
the pinned DQLM/exDQLM interfaces, Q-DESN MCMC interfaces, non-targeted Q-DESN
VB rows, TT5000 rows, or validation logic.

## Validation Evidence

- validation worktree: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- validation branch: `validation/shared-fitforecast-v2-1.0.0`
- validation evidence commit: `4d77027184df369a0607f3ac78eb7eae2687a5ed`
- candidate ledger:
  `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/validation/fitforecast_v2/docs/qdesn_tt500_vb_stage4_best_candidate_ledger_2026-06-29.csv`
- candidate ledger SHA-256:
  `585ad93f139672fa9930b170f33dcba90bc9f2f48fdaa1c4c5c63da05e4f6421`

Stage 4A report root:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/reports/qdesn_mcmc_validation/qdesn_dynamic_fitforecast_v2_tt500_vb_stage4_remaining_cells_transfer/qdesn-tt500-vb-stage4-transfer-full-20260629__git-a59c631/20260629-035305__git-a59c631`

Stage 4B report root:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/reports/qdesn_mcmc_validation/qdesn_dynamic_fitforecast_v2_tt500_vb_stage4b_gausmix005_pinball_refinement/qdesn-tt500-vb-stage4b-gausmix005-pinball-full-20260629__git-52a1821/20260629-040813__git-52a1821`

Both stages passed strict storage-light audits with all roots successful and no
forbidden binary payload retention.

## Promoted Cells

| family | tau | source | profile |
|---|---:|---|---|
| Gaussian mixture | 0.05 | Stage 4B | `tt500vb_f3_d2_n20_a0p05_r0p6_m15_lag15_rl0_pw0p03_pin0p3` |
| Gaussian mixture | 0.50 | Stage 4A | `tt500vb_f3_d1_n30_a0p03_r0p5_m15_lag15_rl0_pw0p03_pin0p3` |
| Laplace | 0.05 | Stage 4A | `tt500vb_f3_d1_n30_a0p02_r0p45_m15_lag15_rl0_pw0p03_pin0p3` |
| Laplace | 0.25 | Stage 4A | `tt500vb_f3_d1_n30_a0p02_r0p45_m15_lag15_rl0_pw0p03_pin0p3` |
| Laplace | 0.50 | Stage 4A | `tt500vb_f3_d1_n30_a0p02_r0p45_m15_lag15_rl0_pw0p03_pin0p3` |
| Gaussian | 0.05 | Stage 4A | `tt500vb_f3_d1_n30_a0p02_r0p45_m15_lag15_rl0_pw0p03_pin0p3` |

These six rows join the three already promoted Stage 3 rows, giving nine
Q-DESN VB exAL RHS TT500 summary replacements in the manuscript table builder.

## Article Wiring

The active config is:

`application/config/shared_validation_tt500_final_fitforecast.yaml`

The table builder is:

`application/scripts/31_build_shared_validation_tt500_final_tables.R`

The Stage 4 promotion uses `override_type: candidate_ledger`. The builder
requires the candidate ledger hash, ledger manifest hash, Stage 4A/4B summary
hashes, strict audit readiness, storage-light pass, successful source rows,
finite/domain checks, comparison eligibility, and dominance over the primary
DQLM/exDQLM VB baselines before replacing any Article row.

One promoted row, `laplace tau=0.05`, has `signoff_grade = WARN` because the
short VB screen reached the configured iteration cap (`vb_converged_false`).
It is accepted only because it is `SUCCESS`, finite/domain valid,
comparison-eligible, strict-audited, storage-light, and dominates the primary
VB baselines on the four promoted fit/forecast metrics. The generated manifest
records this warning explicitly.

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

The generated protocol table should report `Summary overrides = 9`.

## Guardrails

The article must continue to fail on:

- stale `/home/jaguir26/local/src` paths;
- old 0.5.0 validation worktrees or branch names;
- missing or changed candidate-ledger hashes;
- missing strict Stage 4 audit readiness;
- replacement rows that do not beat all primary VB baselines;
- Stage 4 source rows that are not successful, finite/domain valid, and
  comparison-eligible;
- accidental broad replacement of non-targeted rows.

The Stage 4 candidate ledger is an article-facing evidence source, not the
source of truth for validation logic. Any future TT100, TT5000, MCMC rerun, or
multi-root study should receive its own pinned validation handoff.
