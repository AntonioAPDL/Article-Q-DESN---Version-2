# Bayesian Quantile Forecasting with Deep Echo State Networks

This repository contains the working manuscript, supplement, bibliography, and
simulation tables for the Q--DESN article.

## Main Files

- `main.tex`: main article.
- `qdesn-supplement.tex`: standalone supplementary material.
- `refs.bib`: bibliography database used by both LaTeX files.
- `tables/`: generated simulation tables included by the main article.
- `Academic_Writing_Style_Profile_v0.2.md`: writing and formatting criteria
  used for manuscript revisions.
- `scripts/build_qdesn_simulation_tables.R`: script used to regenerate the
  simulation tables from external validation outputs.
- `application/`: planned GloFAS streamflow forecast-calibration workflow.
  Source-controlled files in this directory define the reproducibility
  contract; local data, caches, runs, logs, and generated outputs are ignored.
- `docs/`: audit notes, revision logs, and implementation notes.

## Build

Build the main article with:

```bash
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

Build the supplement with:

```bash
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
bibtex qdesn-supplement
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
```

Generated auxiliary LaTeX artifacts are intentionally not tracked. The main
PDF may be refreshed when syncing a manuscript-facing change to `origin/main`.

## Documentation Map

- `docs/audits/`: manuscript-quality audits from different reading passes.
- `docs/revision_logs/`: chronological records of prose, notation, and build
  changes.
- `docs/implementation_notes/`: technical implementation notes that support
  particular modeling or computation choices.

For a first read of the repository, start with `main.tex`, then
`qdesn-supplement.tex`, and use `docs/README.md` only when you need the history
behind the current draft.

## Simulation Tables

The checked-in 500-observation simulation tables are already included by
`main.tex`.
The current headline MCMC comparison tables consume the source-hash-verified
current-best 1.0.0 fit-and-forecast validation handoff through:

```bash
Rscript scripts/build_qdesn_mcmc_current_best_validation_tables.R
```

The script reads the clean promoted evidence table at
`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/validation/fitforecast_v2/promotions/qdesn_dqlm_500obs_mcmc_current_best_20260723/`
and writes the manuscript-facing MCMC tables plus
`tables/qdesn_validation_tt500_mcmc_current_best_manifest.txt`. The manifest
records the source CSV hash, shared source-registry hash, generated table
hashes, and clean input row count. Failed-signoff rows are excluded from the
headline MCMC tables, and missing clean model--quantile cells are displayed as
blank entries.

The broader generated validation bundle is retained through:

```bash
Rscript application/scripts/31_build_shared_validation_tt500_final_tables.R
Rscript application/scripts/32_audit_shared_validation_tt500_vb_competitiveness.R
```

The final table builder pins exact interface hashes, source-registry hashes,
package version, branch, validation commits, the current-best exDQLM/DQLM VB
evidence, the Stage 3/Stage 4 Q--DESN VB repair evidence, and the Q--DESN MCMC
diagnostic-qualified handoffs. It rejects old 0.5.0 validation paths and stale
home-directory paths.

For validation-table work, use R 4.6.0 or newer. On Muscat, plain `R` and
`Rscript` should resolve through `~/.local/bin` to the local R 4.6.0 install at
`/data/jaguir26/local/opt/R/4.6.0/bin`. Before regenerating tables, verify:

```bash
Rscript -e 'cat(R.version.string, "\n"); stopifnot(getRversion() >= "4.6.0")'
```

The older fit-only table builder,
`scripts/build_qdesn_simulation_tables.R`, is historical and should not be used
for the current 500-observation fit-and-forecast result tables.

The shared dynamic fit + forecast validation record is tracked outside this
repository at
`/data/jaguir26/local/src/QDESN_EXDQLM_SHARED_FIT_FORECAST_VALIDATION_PLAN_2026-05-15.md`.
Only finalized, source-hash-verified summaries from that study should be wired
back into article tables.

The shared 1.0.0 validation logic worktree is
`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0` on branch
`validation/shared-fitforecast-v2-1.0.0` at commit
`82997058338359d3434acbec8bb3b872f3e6daaa`. This branch is authoritative for
the current Article-facing 500-observation validation handoff.

The current freeze and interpretation note is
`docs/implementation_notes/shared_validation_500obs_article_freeze_and_mcmc_followup_20260704.md`.
It records that exDQLM/DQLM VB rows use the July 2026 current-best c13
evidence, while exDQLM/DQLM MCMC rows remain historical matched-protocol
baselines unless a separate MCMC refresh is later promoted.

A provisional Q-DESN 500-observation progress snapshot is wired for operational
auditing and a clearly labeled status table through
`application/config/shared_validation_tt500_provisional_progress.yaml` and
`application/scripts/29_audit_shared_validation_tt500_provisional_progress.R`.
It deliberately carries `is_final = FALSE` and `article_consumable = FALSE`;
do not use it as input to scientific result-table generation or model
comparison.

## GloFAS Application

The planned application is organized under `application/`. Start with
`application/README.md` and
`docs/implementation_notes/glofas_application_reproducibility_blueprint.md`.
The application workflow is intentionally article-owned: it will define the
input contract, model grid, forecast-origin protocol, scoring outputs, and
manuscript table/figure provenance used by Section 9. Large or private inputs
and generated runs should remain in ignored local directories.
