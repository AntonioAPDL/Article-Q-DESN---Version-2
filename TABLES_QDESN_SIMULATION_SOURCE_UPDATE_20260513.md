# Q-DESN Simulation Table Source Update

Date: 2026-05-14 18:17:39 EDT

This note records the source contract for the regenerated simulation tables in
`tables/qdesn_simulation_rmse.tex`, `tables/qdesn_simulation_pinball.tex`, and
`tables/qdesn_simulation_runtime.tex`. It supersedes the 2026-05-13 table
source note in this file: the completed n400/m60 Q-DESN campaign is now the
Q-DESN source for the article tables.

## Repository State

- Article repo: `/data/jaguir26/local/src/Article-Q-DESN`
- Branch: `application-ensemble-likelihood-redesign`
- Article HEAD during regeneration:
  `ec397878d8782f9042e0eca38aafc4e99dc3d7c6 Add latent path VB structure profile gate`
- Pre-existing unrelated application files were dirty before this table update.
  This update is scoped to the table generator, generated table files,
  `main.tex` simulation-summary prose, and this source note.

## Sources Used

- Q-DESN source is the completed n400/m60 campaign fit summary:
  `/data/jaguir26/local/src/exdqlm__wt__qdesn_0p4p0_integration/reports/qdesn_mcmc_validation/dynamic_exdqlm_crossstudy_p90_steepertrend_n300m50_validation/qdesn-dynamic-p90-steepertrend-n400m60-rhs-tau1em5-full-20260510-204348-w30__git-20de505/20260510-204449__git-20de505/tables/campaign_fit_summary.csv`
- Q-DESN run tag:
  `qdesn-dynamic-p90-steepertrend-n400m60-rhs-tau1em5-full-20260510-204348-w30__git-20de505`
- Q-DESN source commit recorded by the run manifest: `20de505`
- Q-DESN campaign completed manifest:
  `/data/jaguir26/local/src/exdqlm__wt__qdesn_0p4p0_integration/reports/qdesn_mcmc_validation/dynamic_exdqlm_crossstudy_p90_steepertrend_n300m50_validation/qdesn-dynamic-p90-steepertrend-n400m60-rhs-tau1em5-full-20260510-204348-w30__git-20de505/20260510-204449__git-20de505/manifest/campaign_completed.json`
- Q-DESN campaign recommendation:
  `COMPARISON_READY_WITH_DOCUMENTED_DYNAMIC_FAIL_BAND`
- exDQLM/DQLM source remains the fresh dynamic72 shared interface:
  `/data/jaguir26/local/src/exdqlm__wt__validation_rerun_after_0p4p0_integration/tools/merge_reports/LOCAL_refreshed288_dynamic72_shared_interface_20260507_p90_dynamic72_qdesn_comparable_fresh_v1.csv`
- exDQLM/DQLM run tag:
  `20260507_p90_dynamic72_qdesn_comparable_fresh_v1`
- exDQLM/DQLM model-code SHA recorded in the shared interface:
  `0cbc405778f809a6d2dbd86383001a1756368f7b`

## Validation Counts

The Q-DESN campaign source has 144 rows and all rows have
`status == "SUCCESS"`. Health signoff grades are:

- PASS: 59
- WARN: 27
- FAIL: 58

These FAIL/WARN grades are diagnostic comparison-health flags from completed
fits, not runtime crashes. The campaign manifest explicitly marks the run
`COMPARISON_READY_WITH_DOCUMENTED_DYNAMIC_FAIL_BAND`, so the article tables
consume the completed metric rows and the generated manifest records the
diagnostic band.

The exDQLM/DQLM shared-interface input has 72 rows and all rows have
`status == "done"`. Health signoff grades are:

- PASS: 46
- WARN: 14
- FAIL: 12

## Generator Wiring

`scripts/build_qdesn_simulation_tables.R` now defaults to the completed Q-DESN
campaign report root and supports explicit overrides:

- `QDESN_VALIDATION_REPO`
- `QDESN_ANALYSIS_ROOT`
- `QDESN_FIT_SUMMARY_PATH`
- `QDESN_RUN_TAG`
- `QDESN_SOURCE_GIT_SHA`
- `EXDQLM_VALIDATION_REPO`
- `EXDQLM_RUN_TAG`
- `EXDQLM_SHARED_INTERFACE_PATH`

The generator accepts both current campaign summaries
(`tables/campaign_fit_summary.csv`) and legacy closeout summaries
(`tables/authoritative_fit_summary.csv`). For campaign summaries, it requires
`manifest/campaign_completed.json`.

## R Runtime Note

Future regeneration should use R 4.6.0 or newer. On Muscat as of 2026-05-15,
plain `R` and `Rscript` are expected to resolve through `~/.local/bin` to:

- `/data/jaguir26/local/opt/R/4.6.0/bin/R`
- `/data/jaguir26/local/opt/R/4.6.0/bin/Rscript`

Do not invoke `/usr/bin/Rscript` for validation-table regeneration, because it
resolves to the older system R 4.5.3 on this server. The preflight check is:

```sh
Rscript -e 'cat(R.version.string, "\n"); stopifnot(getRversion() >= "4.6.0")'
```

This note records the current article-facing fit-only table source. The new
shared dynamic fit + forecast validation relaunch is tracked separately in:

`/data/jaguir26/local/src/QDESN_EXDQLM_SHARED_FIT_FORECAST_VALIDATION_PLAN_2026-05-15.md`

Do not replace these table sources with the new fit + forecast study until that
study has a frozen shared source registry, completed storage-light summaries,
and an article-facing manifest.

## Reproduction

Default regeneration command from the Article repo:

```sh
Rscript scripts/build_qdesn_simulation_tables.R
```

The generated manifest is:
`tables/qdesn_simulation_table_source_manifest.txt`.
