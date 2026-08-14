# Q-DESN/DQLM 500-Observation MCMC Current-Best Article Integration

Date: 2026-07-23

## Scope

This note documents the article-safe integration of the current-best
single-quantile MCMC validation evidence into the authoritative
`Article-Q-DESN---Version-2` repository. It does not modify validation logic,
application scripts, GloFAS scripts, PriceFM scripts, or joint-QDESN scripts.

## Source evidence

- Validation worktree:
  `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Validation branch:
  `validation/shared-fitforecast-v2-1.0.0`
- Validation commit:
  `82997058338359d3434acbec8bb3b872f3e6daaa`
- Promotion root:
  `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/validation/fitforecast_v2/promotions/qdesn_dqlm_500obs_mcmc_current_best_20260723`
- Clean evidence table:
  `qdesn_dqlm_500obs_mcmc_current_best_clean_20260723.csv`
- Promotion manifest:
  `qdesn_dqlm_500obs_mcmc_current_best_manifest_20260723.json`
- Shared source-registry hash:
  `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`

The promotion verifier reports 108 total candidates, 34 clean current-best
rows, 9 family/quantile cell winners, and 6 narrow targeted follow-up cells.

## Article files

The manuscript-facing MCMC tables are regenerated with:

```bash
Rscript scripts/build_qdesn_mcmc_current_best_validation_tables.R
```

This writes:

- `tables/qdesn_validation_tt500_final_mcmc_normal.tex`
- `tables/qdesn_validation_tt500_final_mcmc_laplace.tex`
- `tables/qdesn_validation_tt500_final_mcmc_gausmix.tex`
- `tables/qdesn_validation_tt500_final_mcmc_tables.tex`
- `tables/qdesn_validation_tt500_mcmc_current_best_manifest.txt`

The manifest records the source CSV hash, source-registry hash, generated table
hashes, and clean input row count. Headline tables exclude failed-signoff rows.
Blank entries indicate that no clean current-best row is available for that
model--quantile cell.

## Compile check

`latexmk` was not available in the local environment. The repository README
fallback was used:

```bash
pdflatex -interaction=nonstopmode -halt-on-error -output-directory=local_trackers/codex_compile_20260723_191821_validation_current_best main.tex
bibtex local_trackers/codex_compile_20260723_191821_validation_current_best/main
pdflatex -interaction=nonstopmode -halt-on-error -output-directory=local_trackers/codex_compile_20260723_191821_validation_current_best main.tex
pdflatex -interaction=nonstopmode -halt-on-error -output-directory=local_trackers/codex_compile_20260723_191821_validation_current_best main.tex
```

The final pass produced:

`local_trackers/codex_compile_20260723_191821_validation_current_best/main.pdf`

No undefined references, undefined citations, fatal errors, emergency stops, or
overfull boxes were found in the final log scan.
