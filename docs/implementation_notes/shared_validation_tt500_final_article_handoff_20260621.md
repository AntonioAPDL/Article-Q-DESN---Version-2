# Shared Validation TT500 Final Article Handoff

Date: 2026-06-21

This note records the Article-Q-DESN consumption point for the finalized TT500
shared Q-DESN + exDQLM/DQLM fit-and-forecast validation outputs. It supersedes
the provisional TT500 progress snapshot for scientific result tables. The
provisional snapshot remains useful only as historical operational evidence.

## Validation Source

- Worktree: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Branch: `validation/shared-fitforecast-v2-1.0.0`
- Validation HEAD at article sync: `437dc73385d0922cd2f79d13262947ff1ba01d77`
- Package version: `1.0.0`
- Source registry hash: `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`
- TT500 training window: `8501:9000`
- Forecast origin: `9000`
- Forecast block: `9001:10000`
- Rolling-origin protocol: maximum lead `30`, origin stride `30`, no refit.

## Article Guard

Tracked config:

```sh
application/config/shared_validation_tt500_final_fitforecast.yaml
```

The active shared-engine application configs are also pinned to the same clean
validation HEAD `437dc73385d0922cd2f79d13262947ff1ba01d77` for source-policy
checks. The Q-DESN interface files themselves retain
`ec465f93b7b799e675c40f3a6382c7c6e9ae5727` as their artifact export commit,
because that is the commit at which the scale-repaired lead-level files were
created.

The final guard in `application/R/validation_interface_contract.R` checks:

- no stale `/home/jaguir26/local/src` paths;
- no old 0.5.0 validation worktree, branch, or commit references;
- exact interface SHA-256 hashes;
- package version `1.0.0`;
- validation branch `validation/shared-fitforecast-v2-1.0.0`;
- declared validation artifact commits;
- shared source-registry hash;
- TT500 source windows and forecast block;
- rolling-origin lead grid `1:30`;
- finite fit, forecast, runtime, and scored-origin metrics;
- Q-DESN forecast metric paths marked `scale_repaired`.

## Consumed Interfaces

Q-DESN MCMC TT500 scale-repaired interface:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/reports/qdesn_mcmc_validation/dynamic_fitforecast_v2_validation/qdesn-rolling-origin-v3-scale-repair-20260621__git-ec465f9/final_tt500/interfaces/qdesn_dynamic_fitforecast_v2_shared_interface.csv
```

SHA-256:

```text
dd9b35bdb20763f5b1e4d2cfaf261deb8c4cc09e87400cb789802d4d97473a16
```

Q-DESN VB full scale-repaired interface:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/reports/qdesn_mcmc_validation/dynamic_fitforecast_v2_validation/qdesn-rolling-origin-v3-scale-repair-20260621__git-ec465f9/vb_full/interfaces/qdesn_dynamic_fitforecast_v2_shared_interface.csv
```

SHA-256:

```text
d92cacc5edaad2bbef7eb02d51a55cf21bb5d456f2a91eff5d29d1b0f6da6e92
```

exDQLM/DQLM dynamic fit+forecast interface:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/validation/fitforecast_v2/runs/20260515_exdqlm_dqlm_dynamic_fitforecast_v2_orchestrated_3500202605200353075941/interfaces/exdqlm_dqlm_dynamic_fitforecast_v2_shared_interface.csv
```

SHA-256:

```text
2333de505952e403a6b97d54e710368878fdbc2197f4c9f9060d22dc10c31515
```

## Article Build Command

```sh
Rscript application/scripts/31_build_shared_validation_tt500_final_tables.R
```

The command passed after the validation-section presentation pass on
2026-06-21 and reported:

```text
TT500 final manuscript tables: PASS
summary_rows: 108
lead_rows_consumed: 3240
protocol: /data/jaguir26/local/src/Article-Q-DESN/tables/qdesn_validation_tt500_final_protocol.tex
```

## Article Outputs

- `tables/qdesn_validation_tt500_final_summary.csv`
- `tables/qdesn_validation_tt500_final_tables.tex`
- `tables/qdesn_validation_tt500_final_protocol.tex`
- `tables/qdesn_validation_tt500_final_normal.tex`
- `tables/qdesn_validation_tt500_final_laplace.tex`
- `tables/qdesn_validation_tt500_final_gausmix.tex`
- `tables/qdesn_validation_tt500_final_manifest.txt`

The generated manifest records output hashes and the exact consumed interface
paths. `main.tex` includes `tables/qdesn_validation_tt500_final_tables.tex`.

## Manuscript Presentation Pass

The article section is titled `Simulation Validation Study` and keeps the
stable label `sec:simulation`. The section separates the data-generating
processes, fit-and-forecast protocol, competing methods, criteria, TT500
results, and reproducibility limitations. The generated wrapper now includes a
compact protocol/provenance table before the three family-specific result
tables. The family tables keep VB--LD and MCMC as separate panels, report
fit RMSE, rolling-origin forecast MAE, pinball loss, and runtime, and use
boldface only for the lowest value within each inference panel and quantile
level.

## Verification

The presentation pass was rebuilt and checked with:

```sh
Rscript application/scripts/31_build_shared_validation_tt500_final_tables.R
Rscript application/tests/run_tests.R
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

The table builder, tests, and two LaTeX passes succeeded. After compilation,
`main.aux` places the protocol table and three family result tables in the
simulation-validation section, and `main.log` has no overfull boxes or
undefined-reference warnings. The final PDF has 29 pages.

## Consumption Policy

This is the article-facing TT500 handoff only. TT5000 MCMC is not claimed by
these tables. Any future TT5000 or TT100 handoff should use a new tracked
config, exact interface hashes, separate article-side guard expectations, and a
fresh manifest.
