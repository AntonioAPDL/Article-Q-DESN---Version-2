# Joint QDESN Phase 126 Article-Asset Rebuild

Date: 2026-07-12

## Purpose

Phase 126 rebuilds the article-facing joint QDESN validation assets from the
frozen Phase 125 balanced MCMC audit:

```text
application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712
```

This is an article-integration and QA stage only.  It does not run VB, VB-LD,
MCMC, fixture generation, or validation scoring.

## Why This Stage Was Needed

The previous article assets were organized around the older Phase 113/114/115
evidence structure:

- selected VB source;
- one primary Joint QDESN RHS MCMC reference;
- nine-mechanism wording;
- MCMC described as a fit-window reference layer for one selected joint row.

Phase 125 supersedes that evidence structure with a balanced four-model MCMC
confirmation grid.  Leaving the article unchanged would have made the
manuscript inconsistent with the newest validation evidence.

## Source Evidence

Phase 126 consumes Phase 125, which merges the completed Phase 122 and Phase
124c MCMC blocks.  The Phase 125 state used here is:

- 8 synthetic scenarios;
- 4 model classes per scenario;
- 32/32 scenario-model MCMC rows present;
- 0 worker failures;
- 0 contract quantile crossings;
- 22 pass case gates, 10 review case gates, and 0 fail case gates;
- hard implementation gate: `pass`;
- overall gate: `review`, due to raw pre-contract crossing diagnostics.

The article-facing model rows are:

| Model | Cases | MCMC fit MAE | MCMC forecast MAE | Check loss | Grid CRPS | Raw forecast crossings | Contract crossings | Gate |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| Joint QDESN RHS | 8 | 0.091 | 0.103 | 0.160 | 0.366 | 1 | 0 | review |
| Independent QDESN RHS | 8 | 0.094 | 0.098 | 0.160 | 0.365 | 37 | 0 | review |
| Joint exQDESN RHS | 8 | 0.109 | 0.123 | 0.161 | 0.367 | 0 | 0 | pass |
| Independent exQDESN RHS | 8 | 0.104 | 0.107 | 0.160 | 0.365 | 0 | 0 | review |

## Implemented Files

Phase 126 adds:

```text
application/R/joint_qdesn_phase126_article_assets.R
application/scripts/130_build_joint_qdesn_phase126_article_assets.R
application/scripts/131_audit_joint_qdesn_phase126_article_assets.R
application/tests/test_joint_qdesn_phase126_article_assets.R
```

It writes the cache artifact:

```text
application/cache/joint_qdesn_phase126_article_assets_20260712
```

and updates the article-safe table files:

```text
tables/joint_qdesn_article_validation_mcmc_balanced_protocol.{csv,tex}
tables/joint_qdesn_article_validation_mcmc_balanced_model_summary.{csv,tex}
tables/joint_qdesn_article_validation_mcmc_balanced_scenario_summary.{csv,tex}
tables/joint_qdesn_article_validation_mcmc_balanced_gate_summary.{csv,tex}
tables/joint_qdesn_article_validation_mcmc_balanced_winner_summary.{csv,tex}
tables/joint_qdesn_article_validation_tables.tex
tables/joint_qdesn_article_validation_provenance_tables.tex
tables/joint_qdesn_article_validation_asset_manifest.csv
```

The main manuscript now inputs:

```tex
\input{tables/joint_qdesn_article_validation_mcmc_balanced_model_summary.tex}
```

The supplement now inputs:

```tex
\input{tables/joint_qdesn_article_validation_provenance_tables.tex}
```

## Predictive Contract

The validation claims remain quantile-grid/readout claims.  The composite
AL/exAL likelihood is treated as a working likelihood for quantile-path
inference, not as a unique scalar posterior predictive density.

Consequently:

- VB/VB-LD is the screening, calibration, and initialization layer.
- MCMC is the article-facing confirmation layer.
- Oracle MAE/RMSE, check loss, grid CRPS, hit-rate error, coverage diagnostics,
  and crossing diagnostics are valid quantile-grid metrics.
- Reported scores use monotone contract quantile grids.
- Raw crossings are pre-contract diagnostics and remain visible.

## Gates

Hard pass requirements:

- Phase 125 artifact manifest hashes pass;
- Phase 125 source, VB-freeze, and fixture manifests pass;
- the balanced 8-by-4 model grid is complete;
- no worker failures;
- finite MCMC draws and scores;
- provided VB initialization for all MCMC chains;
- zero contract crossings;
- article assets record Phase 125 as their source;
- manuscript text no longer claims nine mechanisms or a single selected MCMC
  reference layer.

Review conditions retained:

- raw pre-contract crossings are nonzero;
- Independent QDESN RHS carries most raw crossing diagnostics;
- exQDESN rows are crossing-stable but less accurate on average;
- article prose must avoid overclaiming scalar predictive-density validation.

## Verification Commands

```bash
Rscript application/tests/test_joint_qdesn_phase126_article_assets.R

Rscript application/scripts/130_build_joint_qdesn_phase126_article_assets.R \
  --phase125-dir application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712 \
  --output-dir application/cache/joint_qdesn_phase126_article_assets_20260712 \
  --tables-dir tables

Rscript application/scripts/131_audit_joint_qdesn_phase126_article_assets.R \
  --phase126-dir application/cache/joint_qdesn_phase126_article_assets_20260712 \
  --tables-dir tables \
  --main-tex main.tex \
  --supplement-tex qdesn-supplement.tex

latexmk -pdf -interaction=nonstopmode -halt-on-error \
  -outdir=local_trackers/codex_compile_$(date +%Y%m%d_%H%M%S) main.tex
```

## Article Message

The final article-facing message after Phase 126 is:

> The joint multi-quantile validation uses VB/VB-LD for screening,
> calibration, and MCMC initialization.  The article-facing evidence is the
> balanced MCMC confirmation grid over eight synthetic mechanisms and four
> readout/likelihood combinations.  Joint QDESN RHS is the primary AL anchor
> because it gives strong fit and forecast recovery with much cleaner raw
> crossing diagnostics than the independent AL readout.  Joint exQDESN RHS is
> the cleanest joint exAL extension by the crossing gate, although its average
> oracle-distance metrics are less competitive.  All reported scores are
> quantile-grid/readout scores after the monotone contract; raw crossings are
> retained as diagnostics.

## Next Step

After Phase 126 passes audit and compile, the article can use the balanced MCMC
table as the main joint-validation evidence.  No further broad VB or MCMC
screening is needed unless the article must restore the omitted
heteroskedastic-seasonal scenario to the balanced MCMC grid.
