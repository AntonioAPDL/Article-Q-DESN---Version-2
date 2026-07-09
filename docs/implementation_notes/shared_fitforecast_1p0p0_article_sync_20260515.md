# Shared Fit+Forecast 1.0.0 Article Sync

Date: 2026-05-15

This note records the Article-Q-DESN downstream sync after validation-side
confirmation of the shared Q--DESN and exDQLM/DQLM fit+forecast branch.

## Authoritative Validation Logic

- Worktree: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Branch: `validation/shared-fitforecast-v2-1.0.0`
- Commit: `e4e6dc0f7976c1464e91231557f9212914e7438a`
- Package version: `1.0.0`

This branch is authoritative for validation logic and article-facing
fit+forecast outputs that pass a separate pinned handoff guard.

The validation smoke hardening pass later advanced the shared validation HEAD
to `e4e6dc0f7976c1464e91231557f9212914e7438a`; Article configs now pin that
clean pushed commit.

The final validation handoff includes valid smoke interfaces for schema/preflight
evidence only. The Q--DESN tiny-smoke interface has the required H=100/H=1000
columns but does not populate those metric counts, so it must be checked with
the Article guard's explicit smoke/schema mode and must not be treated as a
final article-facing result table.

## Frozen Shared Source Registry

Source root:

`/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast`

Verified preparation hashes:

- `000__bundle_manifest.json`: `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`
- `000__canonical_slice_inventory.csv`: `53471a5854cfb3b66185fc4cdf071623e5bab6db20461d63d246677eb5cac1e2`
- `000__full_root_inventory.csv`: `e2f90e1aa931a81a18bbe64c302e09deda6ab83b495b46026da130ca269f2830`
- `qdesn_dynamic_fitforecast_v2_full_grid.csv`: `d2de49dc16f30e2cc07a836958ad900b90bdc7f09a15d3a1195b8cf31192b9f3`
- `qdesn_dynamic_fitforecast_v2_source_window_verification.csv`: `86efe9c52556d09295ff6cb85aafc03371320d17917dbf12583eccfb3db8baf5`
- `validation/fitforecast_v2/config/shared_source_contract.yaml`: `5018326161ef0da916c99334d4c6cc03419ee19dfc47f9e2528b40b3d689186e`

Source design:

- `TT_main = 10000`
- `TT_warmup = 2000`
- `TT_total = 12000`
- forecast origin source index: `9000`
- forecast block: `9001:10000`
- `TT500` training target window: `8501:9000`
- `TT5000` training target window: `4001:9000`

## Article-Side Status

The article application configs now point to the shared 1.0.0 validation logic
worktree for engine/API checks. The publication simulation table builder still
uses the documented historical fit-only table source by default. It now refuses
non-historical table source modes until validation closeout/export provides
final article-facing fit+forecast interfaces.

Article must not consume the aborted partial Q--DESN smoke tag:

`qdesn-dynamic-fitforecast-v2-smoke-20260515-184752__git-5de7a28`

Article must also refuse these as active sources:

- `/data/jaguir26/local/src/exdqlm__wt__qdesn_fitforecast_0p5p0`
- `/data/jaguir26/local/src/exdqlm__wt__validation_fitforecast_0p5p0`
- `/data/jaguir26/local/src/exdqlm__wt__qdesn_0p4p0_integration`
- `/data/jaguir26/local/src/exdqlm__wt__validation_rerun_after_0p4p0_integration`
- branch `feature/qdesn-fitforecast-validation-0p5p0`
- commit `1417a825d24a6ac805b3b4af8033bb8e14a29187`
- active `/home/jaguir26/local/src` paths

## Provisional TT500 Progress Snapshot

On 2026-06-13, Article-Q-DESN added an operational pointer to the live Q-DESN
TT500 MCMC validation progress snapshot:

`application/config/shared_validation_tt500_provisional_progress.yaml`

The validation-side exporter and runbook support were pushed on branch
`validation/shared-fitforecast-v2-1.0.0` at commit
`ec465f93b7b799e675c40f3a6382c7c6e9ae5727`.

This points to storage-light generated artifacts under:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/reports/qdesn_mcmc_validation/dynamic_fitforecast_v2_validation/qdesn-dynamic-fitforecast-v2-mcmc-tt500-20260520-035319__git-d075941/20260525-191523__git-d075941/provisional_progress`

The snapshot is explicitly non-final and non-article-consumable. It exists so
Article-Q-DESN can audit progress, hashes, source-window metadata, stale path
guardrails, and the explicitly labeled TT500 operational status table while
the validation campaign finishes. It must not be used as input to
`scripts/build_qdesn_simulation_tables.R`.

Audit command:

```sh
Rscript application/scripts/29_audit_shared_validation_tt500_provisional_progress.R
```

Status-table build command:

```sh
Rscript application/scripts/30_build_shared_validation_tt500_provisional_table.R
```

## Final TT500 Table Consumption

On 2026-06-21, Article-Q-DESN added a final TT500 article-facing handoff:

- Config: `application/config/shared_validation_tt500_final_fitforecast.yaml`
- Builder: `application/scripts/31_build_shared_validation_tt500_final_tables.R`
- Manifest: `tables/qdesn_validation_tt500_final_manifest.txt`
- Manuscript wrapper: `tables/qdesn_validation_tt500_final_tables.tex`
- Implementation note:
  `docs/implementation_notes/shared_validation_tt500_final_article_handoff_20260621.md`

The guarded build consumes 3,240 lead-level TT500 rows and writes 108 summary
rows covering Q--DESN, DQLM, and exDQLM under VB--LD and MCMC for the three
families and three target quantile levels. TT5000 MCMC remains outside article
claims until a separate final handoff is exported, pinned, guarded, and
documented.
