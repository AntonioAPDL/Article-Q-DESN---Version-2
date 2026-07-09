# PriceFM Application Section Rewrite Plan

Date: 2026-06-25

## Objective

Replace the current PriceFM manuscript section with a self-contained,
paper-facing application section. The section should read as an empirical
application, not as a record of local screening stages. It must introduce the
data, forecasting task, information sets, model-selection protocol, evaluation
metrics, and results in a way that a reader can understand without access to
local development notes.

The section must remain reproducible from the current authoritative PriceFM
outputs, and the asset-generation workflow must be stable enough to refresh
tables and figures after future model-selection runs.

## Current State Audit

### Manuscript State

`main.tex` currently includes a PriceFM section beginning at
`\section{Application: European Electricity Price Forecasting}` and inputs
`tables/pricefm_stage_m_current_outputs.tex`.

Current problem:

- The section uses local workflow language such as `Stage-M`, `registry`,
  `rescue`, and `screening`.
- The section gives results before fully introducing the data and forecasting
  task.
- Validation/test diagnostics are too prominent for the main text and read like
  internal model-selection debugging.
- The table and figure names expose implementation-stage labels rather than
  paper-facing concepts.

### Current Authoritative Outputs

The manuscript-facing outputs are generated from:

- `application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/current_decision_surface_table.csv`
- `application/data_local/pricefm/authoritative/pricefm_stage_m_article_tables_20260624/`
- `application/data_local/pricefm/authoritative/pricefm_stage_m_comparability_audit_20260624/`
- `application/scripts/pricefm/72_build_pricefm_manuscript_assets.py`

Current selected-panel coverage:

- Region/fold rows: 42
- Regions: 15
- Folds: 3
- Graph-neighbor input rows: 27
- Target-only input rows: 15
- Local wins: 25 / 42
- Mean local AQL: 8.632
- Mean PriceFM AQL: 8.960
- Mean local-minus-PriceFM AQL: -0.328
- Paper quantiles: 0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90

Current information-set result:

| Information set | Rows | Local wins | Mean local AQL | Mean PriceFM AQL | Mean local-minus-PriceFM AQL |
|---|---:|---:|---:|---:|---:|
| PriceFM graph-neighbor inputs | 27 | 20 | 8.489 | 9.208 | -0.719 |
| Target-only inputs | 15 | 5 | 8.891 | 8.514 | 0.377 |

Region-average result over the selected panel:

| Region | Rows | Local wins | Mean local AQL | Mean PriceFM AQL | Mean local-minus-PriceFM AQL |
|---|---:|---:|---:|---:|---:|
| EE | 3 | 3 | 13.855 | 16.250 | -2.394 |
| DK_2 | 3 | 3 | 6.686 | 8.560 | -1.874 |
| NL | 3 | 2 | 5.975 | 6.905 | -0.929 |
| DK_1 | 3 | 3 | 7.507 | 8.383 | -0.876 |
| SI | 3 | 2 | 7.474 | 7.923 | -0.449 |
| LV | 3 | 1 | 12.326 | 12.383 | -0.058 |
| BE | 3 | 2 | 5.878 | 5.875 | 0.003 |
| LT | 3 | 2 | 12.665 | 12.606 | 0.059 |
| AT | 2 | 1 | 7.194 | 7.079 | 0.115 |
| SE_4 | 3 | 1 | 8.099 | 7.900 | 0.199 |
| RO | 3 | 1 | 8.013 | 7.729 | 0.284 |
| SK | 3 | 2 | 7.822 | 7.511 | 0.311 |
| HU | 3 | 1 | 8.474 | 8.123 | 0.352 |
| PL | 2 | 0 | 7.668 | 7.154 | 0.514 |
| FI | 2 | 1 | 9.253 | 8.700 | 0.553 |

Interpretation:

- The selected panel supports a scoped comparison, not a full PriceFM paper-wide
  benchmark.
- The most important scientific distinction is the information set. The local
  reservoir models are competitive when allowed to use the same released
  topology-neighbor information source, but target-only rows are weaker on
  average.
- The section should use this distinction as a controlled comparison axis.

## External Benchmark Alignment

The PriceFM paper uses a rolling evaluation with three folds, robust scaling
from the training data, and reports probabilistic and pointwise metrics
including AQL, AQCR, MAE, and RMSE. Its dataset is a European electricity-price
benchmark over 38 bidding regions and includes day-ahead price plus load, solar,
and wind forecasts. PriceFM is a graph-informed, multi-region,
multi-horizon, multi-quantile model.

For this article, direct comparison must use the cached fold-aligned PriceFM
Phase-I predictions and matching region/fold test rows. Paper-wide headline
PriceFM metrics may be used only as context unless the local outputs cover the
same aggregation set.

## Paper-Facing Section Design

### Proposed Section Outline

1. `Application: European Electricity Price Forecasting`
   - Introduce why electricity prices are a useful stress test for Q-DESN:
     high frequency, nonlinear seasonal structure, spikes, covariates, and
     cross-region dependence.
   - Cite PriceFM as the benchmark data/model source.

2. `Data and Forecasting Task`
   - State dataset scope: European bidding regions, 15-minute resolution,
     day-ahead price, load, solar, and wind forecasts.
   - State rolling folds and test windows in a compact table.
   - State horizons and quantile grid used for this article comparison.
   - State original-unit evaluation.

3. `Local Reservoir Models and Information Sets`
   - Define Q-DESN AL/RHS_NS and Q-DESN exAL/RHS_NS as the local readout
     models used here.
   - Define `target-only` and `graph-neighbor` input sets.
   - Explain that graph-neighbor rows use the same released topology
     information source as PriceFM, but still fit single-target local reservoir
     readouts rather than the full PriceFM foundation model.

4. `Evaluation Protocol`
   - Primary metric: original-unit AQL on the PriceFM paper quantile grid.
   - Secondary diagnostics: AQCR, MAE, RMSE if available and consistently
     computed.
   - Define delta: local AQL minus PriceFM AQL; negative favors the local
     reservoir model.
   - State coverage explicitly: selected panel of 42 region/folds, 15 regions,
     3 folds. If a future full 38-region panel is available, this statement must
     be updated.

5. `Results`
   - Present fold-level and information-set summaries.
   - Present a region/fold heatmap of AQL differences.
   - Present a sorted per-region average-delta figure or table.
   - Emphasize the central finding: performance is heterogeneous by region and
     information set.

6. `Limitations and Next Steps`
   - State that selected-panel results do not imply paper-wide superiority.
   - State that target-only local models are disadvantaged relative to PriceFM's
     graph-informed inputs.
   - State that the next empirical goal is to expand the same reproducible
     protocol to all available PriceFM regions/folds and then to a full
     paper-grid comparison.

### Main-Text Tables and Figures

Keep the main text compact and scientific:

1. Dataset/protocol table:
   - rows: data frequency, variables, folds, train/validation/test windows,
     quantiles, metric, information sets.
   - source: `processed/splits/split_registry.csv` plus fixed constants from
     the PriceFM asset manifest.

2. Results-by-fold table:
   - rows: folds 1--3 plus overall.
   - columns: rows, local wins, win rate, local AQL, PriceFM AQL, delta AQL.

3. Results-by-information-set table:
   - rows: target-only, graph-neighbor, optionally model family.
   - columns: rows, local wins, local AQL, PriceFM AQL, delta AQL.

4. Region/fold heatmap:
   - cell: local-minus-PriceFM AQL.
   - facet or annotation: information set.
   - row sorting: region-average delta or geographic/PriceFM order.

5. Region-average summary:
   - either table or figure.
   - include number of folds represented per region.

Move these to supplement/internal notes rather than main text:

- largest wins/losses table;
- validation/test alignment table;
- validation-vs-test scatterplot;
- rescue/stage diagnostics.

These are useful for internal QA and possibly supplement, but not for the main
application narrative.

## Asset Naming Contract

Replace stage-labeled manuscript assets with paper-facing names:

- `tables/pricefm_application_current_outputs.tex`
- `tables/pricefm_application_protocol_summary.tex`
- `tables/pricefm_application_fold_summary.tex`
- `tables/pricefm_application_information_set_summary.tex`
- `tables/pricefm_application_region_summary.tex`
- `figures/pricefm_application/pricefm_application_delta_heatmap.png`
- `figures/pricefm_application/pricefm_application_region_delta_ranking.png`
- `tables/pricefm_application_asset_manifest.json`

The old `pricefm_stage_m_*` files can remain temporarily for auditability, but
`main.tex` should only input the paper-facing alias file.

## Generator Refactor Plan

Update or replace `application/scripts/pricefm/72_build_pricefm_manuscript_assets.py`.

Required behavior:

1. Read a single authoritative config block specifying:
   - decision-surface CSV;
   - article-table output directory;
   - split registry;
   - PriceFM prediction reference;
   - quantile grid;
   - asset output paths.

2. Validate input contracts:
   - unique `(region, fold)` keys;
   - finite AQL metrics;
   - `delta_abs = local_AQL - pricefm_AQL`;
   - information-set labels are explicit;
   - quantile grid equals the declared paper grid;
   - fold/test windows match the split registry;
   - all tracked tables/figures can be regenerated from the declared sources.

3. Produce paper-facing assets:
   - protocol summary table;
   - fold summary table;
   - information-set summary table;
   - region summary table;
   - heatmap;
   - region ranking figure;
   - alias file;
   - JSON manifest with source hashes.

4. Produce an internal QA report:
   - coverage relative to full 38-region, 3-fold PriceFM scope;
   - selected-panel warning if coverage is incomplete;
   - validation/test diagnostics references;
   - forbidden manuscript language scan.

5. Never write stage labels into manuscript-facing TeX.

## Manuscript Language Guardrails

Allowed language:

- "selected-panel comparison"
- "fold-aligned PriceFM Phase-I predictions"
- "local-minus-PriceFM AQL"
- "target-only information set"
- "graph-neighbor information set"
- "does not constitute a full paper-wide PriceFM benchmark"
- "performance varies by region and information set"

Forbidden main-text language:

- "Stage-M"
- "registry"
- "rescue"
- "screening"
- "current decision surface"
- "Q-DESN outperforms PriceFM overall"
- "full PriceFM benchmark" unless all 38 regions and all folds are included
- "validation AQL" as if it were the final paper-grid test metric

Validation command:

```sh
rg -n "Stage-M|registry|rescue|screening|current decision surface|outperforms PriceFM overall|full PriceFM benchmark" main.tex tables/pricefm_application_*.tex
```

The command should return no paper-facing hits, except in internal notes or
explicit limitation text where appropriate.

## Reproducibility Criteria

Before committing a rewritten section:

1. Regenerate manuscript assets from the authoritative source paths.
2. Write/update a manifest with:
   - source CSV paths;
   - source file hashes;
   - script path and git SHA;
   - quantile grid;
   - region/fold coverage;
   - metric definitions;
   - figure/table output hashes.
3. Run the comparability checks.
4. Run the forbidden-language scan.
5. Compile locally:

```sh
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

6. Verify PDF text:

```sh
pdftotext main.pdf - | rg "Application: European Electricity Price Forecasting|PriceFM|Average quantile loss"
```

7. Run `git diff --check`.

## Implementation Checklist

### Phase 1: Freeze Inputs

- [ ] Confirm the current authoritative decision-surface CSV.
- [ ] Confirm the split registry and fold windows.
- [ ] Confirm the PriceFM Phase-I prediction reference path.
- [ ] Confirm whether current outputs remain selected-panel only or whether a
      full 38-region/fold panel is available.
- [ ] Record all source hashes.

### Phase 2: Redesign Asset Generator

- [ ] Add paper-facing output names.
- [ ] Add protocol-summary table generation.
- [ ] Add region-summary table generation.
- [ ] Add region/fold heatmap generation with paper-facing labels.
- [ ] Add region-average delta ranking figure.
- [ ] Add internal QA report and forbidden-language checks.
- [ ] Preserve old Stage-M outputs until the new section compiles.

### Phase 3: Rewrite Main Section

- [ ] Replace current PriceFM section with the self-contained outline above.
- [ ] Remove stage/rescue/registry language.
- [ ] Place validation protocol in one concise paragraph.
- [ ] Move validation/test diagnostics out of the main text.
- [ ] State selected-panel scope and information-set caveat clearly.
- [ ] Avoid global superiority claims.

### Phase 4: Validate and Compile

- [ ] Regenerate assets.
- [ ] Run comparability checks.
- [ ] Run forbidden-language scan.
- [ ] Compile local PDF.
- [ ] Verify PDF text.
- [ ] Inspect the section visually.
- [ ] Commit source, tracked assets, manifest, and refreshed PDF if still
      intentionally tracked for Overleaf sync.

## Recommended Immediate Next Step

Implement the asset-generator refactor and manuscript rewrite as a single
coherent paper-facing pass. Do not expand the empirical benchmark in this same
pass. The first goal is to make the current selected-panel evidence clear,
honest, and reproducible. After that, a separate run can expand coverage toward
the full 38-region, three-fold PriceFM scope.
