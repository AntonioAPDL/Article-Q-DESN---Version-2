# PriceFM Full-Surface Article Display Polish

Date: 2026-07-08

## Purpose

This pass revises the manuscript-facing PriceFM application displays after a
reader-focused audit of Section `Application: European Electricity Price
Forecasting`. The goal is editorial and reproducibility-focused: keep the
article's PriceFM message clear, reduce redundant main-text displays, remove
local workflow shorthand from reader-facing prose, and preserve detailed
diagnostics as reproducible artifacts.

No PriceFM models are launched or refitted in this pass.

## Audit Finding

The previous main-text PriceFM section printed eight displays:

- method summary;
- fold summary;
- decision summary;
- 114-row sorted delta figure;
- evidence-source summary;
- feature-policy summary;
- horizon heatmap/table;
- largest-win/largest-loss and priority-follow-up tables.

That material was technically useful but too ledger-like for the main article.
Tables 13--15 repeated the same aggregate decision surface, the row-level
figures were dense, and Tables 19--20 read as diagnostics or future-work
trackers rather than article evidence.

## Implemented Display Contract

The main article now uses three PriceFM displays:

1. `tables/pricefm_full_main_summary.tex`
   - overall and fold-level rows;
   - wins, near ties, PriceFM wins;
   - mean AQL for Q--DESN and PriceFM;
   - mean and median AQL differences.

2. `tables/pricefm_full_input_set_summary.tex`
   - graph-derived versus target-only input sets;
   - win/near-tie/loss counts;
   - mean and median AQL differences.

3. `tables/pricefm_full_horizon_diagnostic_summary.tex`
   - available horizon-block diagnostics for the subset with retained
     horizon scores;
   - explicitly described as partial-scope diagnostics.

The detailed source, feature-policy, row-extreme, priority-follow-up, and
row-level figure artifacts remain generated and manifest-tracked, but they are
not promoted as main-text displays.

## Reproducibility Repair

The current-output alias file named the generator:

```text
application/scripts/pricefm/115_build_pricefm_full_surface_manuscript_assets.py
```

but that script was missing from the tracked main worktree. This pass restores
the builder and makes it self-contained for the manuscript-asset export. The
builder reads the frozen full-surface closeout:

```text
application/data_local/pricefm/authoritative/pricefm_full_surface_decision_closeout_20260704/
```

and writes tracked LaTeX tables, figures, aliases, and the SHA-256 asset
manifest. The builder keeps the detailed audit outputs available while exposing
the compact display set through new macros:

```text
\PricefmFullMainSummaryTable
\PricefmFullInputSetSummaryTable
\PricefmFullHorizonDiagnosticSummaryTable
```

## Reader-Facing Language Changes

The main article now avoids local workflow labels such as `R3q`, `Stage-M`,
`provenance bridge`, and `priority rescue`. The section instead describes:

- an aligned PriceFM benchmark panel;
- cached fold-aligned PriceFM predictions;
- audited validation registries and paper-quantile score files;
- graph-derived versus target-only inputs;
- a bounded, nonuniform empirical result.

The supported statement is intentionally modest: Q--DESN is competitive on the
aligned PriceFM benchmark panel and has lower mean and median AQL in aggregate,
but it is not uniformly better than PriceFM.

## Key Numbers

| Quantity | Value |
|---|---:|
| Region/fold rows | 114 |
| Regions | 38 |
| Folds | 3 |
| Q--DESN wins | 66 |
| Near ties | 12 |
| PriceFM wins | 36 |
| Mean Q--DESN AQL | 6.826 |
| Mean PriceFM AQL | 7.039 |
| Mean Q--DESN minus PriceFM AQL | -0.213 |
| Median Q--DESN minus PriceFM AQL | -0.083 |

## Validation Commands

```sh
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python \
  -m py_compile \
  application/scripts/pricefm/115_build_pricefm_full_surface_manuscript_assets.py \
  application/tests/test_pricefm_full_surface_manuscript_assets.py

/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python \
  -m pytest application/tests/test_pricefm_full_surface_manuscript_assets.py -q

/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/115_build_pricefm_full_surface_manuscript_assets.py \
  --closeout-dir /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_full_surface_decision_closeout_20260704 \
  --table-dir tables \
  --figure-dir figures/pricefm_application
```

The manuscript should then be compiled with two `pdflatex` passes and the log
checked for substantive warnings.

## Remaining Limitation

This remains an application benchmark against cached fold-aligned PriceFM
predictions. It is not a full reproduction of every PriceFM paper aggregate,
and it is not application-level evidence for the joint multi-quantile readout
unless a future PriceFM run explicitly fits and promotes that joint model under
the same fold-aligned contract.
