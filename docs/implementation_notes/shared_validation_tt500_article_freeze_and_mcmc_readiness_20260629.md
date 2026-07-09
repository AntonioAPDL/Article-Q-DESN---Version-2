# Shared Validation TT500 Article Freeze and MCMC Readiness

Date: 2026-06-29

This note freezes the Article-Q-DESN TT500 validation tables after the Stage 3
and Stage 4 Q-DESN VB repair handoffs. It also records the Article-side
decision about whether the VB evidence is strong enough to justify a selective
Q-DESN MCMC confirmation launch.

## Frozen Article State

- Article main/Overleaf worktree:
  `/data/jaguir26/local/src/Article-Q-DESN__wt__main_overleaf_20260514`
- Article branch: `repair-overleaf-sync-20260624`
- Article remote target: `origin/main`
- Article freeze commit before this note: `89ad2ea`
- Shared validation worktree:
  `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Shared validation branch: `validation/shared-fitforecast-v2-1.0.0`
- Shared validation evidence commit:
  `4d77027184df369a0607f3ac78eb7eae2687a5ed`
- Package version: `1.0.0`
- Source registry SHA-256:
  `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`
- TT500 train window: `8501:9000`
- Forecast block: `9001:10000`
- Rolling-origin forecast protocol: leads `1:30`, origin stride `30`, no refit

The frozen manuscript tables are:

- `tables/qdesn_validation_tt500_final_protocol.tex`
- `tables/qdesn_validation_tt500_final_normal.tex`
- `tables/qdesn_validation_tt500_final_laplace.tex`
- `tables/qdesn_validation_tt500_final_gausmix.tex`
- `tables/qdesn_validation_tt500_final_summary.csv`
- `tables/qdesn_validation_tt500_final_manifest.txt`

The final summary has 108 rows and consumes 3240 lead-level TT500 rows. The
summary contains 9 Q-DESN VB exAL RHS repair rows: 3 from Stage 3 and 6 from
Stage 4.

## Manuscript Review

The simulation section now follows the repository style profile: it states the
statistical target, data-generating processes, fit-and-forecast protocol,
competitors, metrics, provenance gates, and limitations before interpreting the
tables. The family-specific tables are split by simulation family and grouped
by inference method. Boldface is local to each inference panel and quantile
level, so the reader is not asked to compare unrelated cells globally.

The manuscript explicitly separates the current TT500 handoff from future
TT5000, TT100, multi-root, and MCMC-confirmation work. The MCMC panels are the
completed TT500 MCMC handoff available to the article; they are not a matched
MCMC confirmation of the later Stage 3 and Stage 4 VB repair profiles.

## VB Competitiveness Audit

Reproducible command:

```bash
Rscript application/scripts/32_audit_shared_validation_tt500_vb_competitiveness.R
```

Audit output:

`tables/qdesn_validation_tt500_vb_competitiveness_audit.csv`

Audit CSV SHA-256:

`2ba4f0b97a021f812dd758e2dfe322bf7e29b25ca640f3423c8053378e6c2c0c`

The audit compares the promoted Q-DESN exAL RHS VB row against the best
DQLM/exDQLM VB baseline for the same family and quantile level. The four
guarded metrics are fit RMSE, fit pinball loss, rolling-origin forecast MAE,
and rolling-origin forecast pinball loss.

| family | tau | fit RMSE ratio | fit pinball ratio | forecast MAE ratio | forecast pinball ratio |
|---|---:|---:|---:|---:|---:|
| normal | 0.05 | 0.134 | 0.591 | 0.735 | 0.974 |
| normal | 0.25 | 0.116 | 0.497 | 0.708 | 0.973 |
| normal | 0.50 | 0.108 | 0.407 | 0.824 | 0.984 |
| laplace | 0.05 | 0.298 | 0.603 | 0.367 | 0.957 |
| laplace | 0.25 | 0.113 | 0.460 | 0.361 | 0.948 |
| laplace | 0.50 | 0.089 | 0.452 | 0.947 | 0.990 |
| gausmix | 0.05 | 0.162 | 0.544 | 0.595 | 0.997 |
| gausmix | 0.25 | 0.100 | 0.479 | 0.635 | 0.950 |
| gausmix | 0.50 | 0.090 | 0.436 | 0.368 | 0.934 |

All 9 family/quantile cells beat the best DQLM/exDQLM VB baseline on all four
guarded metrics. The weakest margins are forecast pinball for Gaussian mixture
at tau 0.05, Laplace at tau 0.50, and Gaussian at tau 0.50; these are
competitive but should be confirmed before making stronger MCMC claims.

## MCMC Readiness Decision

The VB stage is fixed for the current TT500 article table: every family and
quantile level has a Q-DESN exAL RHS VB row that is competitive with, and
strictly better than, the best DQLM/exDQLM VB baseline on the guarded metrics.

This is enough evidence to launch a selective MCMC confirmation for the nine
promoted Q-DESN exAL RHS VB profiles, after the validation repository prepares
a dry-run and smoke-tested launcher. It is not evidence for a broad all-variant
Q-DESN MCMC relaunch, and it does not repair the existing TT500 MCMC rows in
the article table. The MCMC launch should therefore be narrow:

- family in `{normal, laplace, gausmix}`;
- tau in `{0.05, 0.25, 0.50}`;
- fit size `TT500`;
- likelihood `exAL`;
- prior `RHS`;
- profile selected by the Stage 3/Stage 4 ledger for each cell;
- VB output reused for MCMC initialization whenever available;
- same source registry, forecast grid, storage-light policy, telemetry, and
  failure-explicit status contract.

Recommended launch gate: run source verification, prepare-only, smoke, then a
small selective MCMC pilot before launching all nine cells.
