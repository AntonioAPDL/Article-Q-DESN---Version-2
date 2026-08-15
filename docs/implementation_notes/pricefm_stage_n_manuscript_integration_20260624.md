# PriceFM Stage-N Manuscript Integration

Date: 2026-06-24

## Scope

This stage promotes the already-audited PriceFM Stage-M selected-panel
comparison into article-facing manuscript assets. It does not refit models,
change the authoritative PriceFM registry, change the GloFAS application, or
touch Overleaf/main.

The manuscript comparison remains scoped to cached fold-aligned PriceFM
Phase-I predictions on the selected Stage-M panel. It is not a full PriceFM
paper-wide benchmark.

## Inputs

- Stage-M article tables:
  `application/data_local/pricefm/authoritative/pricefm_stage_m_article_tables_20260624/`
- Stage-M comparability audit:
  `application/data_local/pricefm/authoritative/pricefm_stage_m_comparability_audit_20260624/`
- Stage-M decision-surface figures:
  `application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/figures/`
- Stage-M validation/test figures:
  `application/data_local/pricefm/authoritative/pricefm_stage_m_validation_test_alignment_20260624/figures/`

The audit used for this integration reported 12 comparability checks, 0 fatal
failures, and 0 warnings.

## Generated Tracked Assets

New reproducible exporter:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/72_build_pricefm_manuscript_assets.py
```

Tracked LaTeX assets:

- `tables/pricefm_stage_m_current_outputs.tex`
- `tables/pricefm_stage_m_fold_summary.tex`
- `tables/pricefm_stage_m_information_set_summary.tex`
- `tables/pricefm_stage_m_top_wins_losses.tex`
- `tables/pricefm_stage_m_validation_alignment.tex`
- `tables/pricefm_stage_m_article_asset_manifest.json`

Tracked figure assets:

- `figures/pricefm_application/pricefm_stage_m_aql_delta_by_region_fold.png`
- `figures/pricefm_application/pricefm_stage_m_local_wins_by_fold.png`
- `figures/pricefm_application/pricefm_stage_m_current_validation_vs_test.png`
- `figures/pricefm_application/pricefm_stage_m_rescue_validation_test_deltas.png`

The manifest records SHA256 hashes and byte sizes for all promoted assets.

## Manuscript Changes

`main.tex` now inputs `tables/pricefm_stage_m_current_outputs.tex` and adds a
new section:

```tex
\section{Application: European Electricity Price Forecasting}
```

The section documents:

- the PriceFM data/task context and citation;
- the selected-panel/fold-aligned comparison contract;
- the PriceFM paper quantile grid;
- fold-level AQL summaries;
- model-family and information-set summaries;
- decision-surface diagnostics;
- validation/test alignment diagnostics;
- explicit limitations and claim guardrails.

The language avoids global superiority claims. The supported statement is:
within the selected Stage-M panel and fold-aligned Phase-I comparison, the
local registry is competitive with PriceFM and often better, especially for
rows using released PriceFM graph-neighbor inputs.

## Key Article Numbers

- Selected region/folds: 42
- Regions: 15
- Folds: 3
- Local wins: 25
- PriceFM wins: 17
- Mean local AQL: 8.632
- Mean PriceFM AQL: 8.960
- Mean local-minus-PriceFM AQL: -0.328
- Graph-input rows: 27
- Target-only rows: 15

## Validation

Focused Python tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_m_article_readiness.py \
  application/tests/test_pricefm_stage_n_manuscript_assets.py \
  application/tests/test_pricefm_stage_l_decision_surface.py \
  application/tests/test_pricefm_stage_k_summarizers.py \
  -q
```

Result: 18 passed.

Script compilation:

```sh
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/70_build_pricefm_article_tables.py \
  application/scripts/pricefm/71_audit_pricefm_stage_m_comparability.py \
  application/scripts/pricefm/72_build_pricefm_manuscript_assets.py
```

Result: passed.

Claim-language audit:

```sh
rg -n "Q--DESN outperforms PriceFM overall|outperforms PriceFM overall|full paper-wide PriceFM benchmark|Selected-panel AQL is directly comparable" \
  main.tex tables/pricefm_stage_m_*.tex
```

Result: no matches.

LaTeX validation:

```sh
mkdir -p build/latex
pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build/latex main.tex
bibtex build/latex/main
pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build/latex main.tex
pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build/latex main.tex
```

Result: passed; no undefined citations or references in
`build/latex/main.log`.

Repository hygiene:

```sh
git diff --check
```

Result: passed.

## Remaining Limitations

- The manuscript-facing PriceFM comparison is selected-panel only.
- It uses cached fold-aligned PriceFM Phase-I predictions, not a full
  reproduction of every PriceFM paper aggregate.
- Graph-input rows and target-only rows must remain separated in interpretation.
- Test-helpful candidates that failed validation gates were not promoted into
  the current registry.

## Next Step

The next manuscript step is editorial: decide how much of the PriceFM section
belongs in the main text versus supplement once the surrounding simulation and
discussion sections are finalized.
