# PriceFM Stage-M Comparability And Writing Audit

Date: 2026-06-24

## Purpose

This note records the final comparability and writing pass for the Stage-M
PriceFM article-readiness outputs.  The pass does not launch models and does
not alter the authoritative registry.  Its purpose is to make the comparison
with PriceFM precise enough for manuscript drafting.

## Comparability Contract

The current Stage-M tables support a scoped comparison with PriceFM under the
following contract:

- benchmark: cached fold-aligned PriceFM Phase-I predictions;
- target rows: the same selected region/fold test rows used by the local
  DESN/Q-DESN paper-quantile comparisons;
- metric: original-unit average quantile loss (AQL), with lower values better;
- delta convention: local DESN/Q-DESN AQL minus PriceFM AQL;
- quantile grid: `0.10,0.25,0.45,0.50,0.55,0.75,0.90`;
- scope: 42 selected region/folds, spanning 15 regions and 3 folds;
- information sets: 27 rows use released PriceFM graph-neighbor inputs and 15
  rows are target-only local-input ablations.

This contract is comparable enough for an article table that asks whether the
current selected DESN/Q-DESN registry improves on fold-aligned PriceFM Phase-I
for the selected panel.  It is not a full reproduction of every paper-wide
PriceFM benchmark table.

## Audit Tooling

New script:

```text
application/scripts/pricefm/71_audit_pricefm_stage_m_comparability.py
```

Updated script:

```text
application/scripts/pricefm/70_build_pricefm_article_tables.py
```

The article-table builder now emits:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_article_tables_20260624/article_comparability_guardrails.csv
```

The comparability audit emits:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_comparability_audit_20260624/
```

with:

```text
comparability_checks.csv
comparability_scope.csv
article_claim_guardrails.csv
pricefm_stage_m_comparability_audit_report.md
summary.json
```

## Audit Results

The final audit passed:

| quantity | value |
|---|---:|
| checks | 12 |
| fatal failures | 0 |
| warning failures | 0 |
| region/folds | 42 |
| regions | 15 |
| folds | 3 |
| graph-input rows | 27 |
| target-only rows | 15 |
| local wins | 25 |
| mean local-minus-PriceFM AQL | -0.327574 |

Checks included:

- current decision-surface row count;
- unique region/fold keys;
- article-table keys matching the decision surface;
- finite local AQL, PriceFM AQL, and AQL deltas;
- exact delta identity `delta_abs = local_AQL - pricefm_AQL`;
- decision-label consistency;
- explicit graph-input versus target-only information-set labels;
- graph metadata on graph-input rows;
- local metadata on target-only rows;
- current quantile-registry keys matching the decision surface;
- no Stage-L test-only promotion rows in the authoritative surface;
- presence of generated article claim guardrails.

## Writing Guardrails

Allowed manuscript language:

- "Across the selected Stage-M panel of 42 region/folds, the local
  DESN/Q-DESN registry is compared with fold-aligned PriceFM Phase-I
  predictions."
- "Lower original-unit AQL is better; reported deltas are local AQL minus
  PriceFM AQL on aligned test rows."
- "The paper-grid comparison uses quantiles
  `0.10,0.25,0.45,0.50,0.55,0.75,0.90`."
- "Graph-input rows and target-only rows are reported separately."
- "Stage-K and Stage-L test-helpful candidates were not promoted when
  validation gates failed."

Avoid:

- "Q-DESN outperforms PriceFM overall."
- "The selected Stage-M panel reproduces the full PriceFM paper benchmark."
- "Median-only screening is a paper-grid result."
- "Graph-input wins are purely local univariate wins."
- "Selected-panel AQL is directly comparable to the paper-wide aggregate AQL."

## Article-Ready Interpretation

The strongest article claim is evidence-bounded:

> On the selected 42 region/fold panel, the current DESN/Q-DESN registry has
> lower fold-aligned PriceFM Phase-I AQL in 25 cases.  The advantage is
> concentrated in rows that use released PriceFM graph-neighbor inputs; the
> target-only ablation remains weaker on average.

This phrasing keeps the comparison useful while preserving the important
limitations.  It also makes the information-set distinction explicit, which is
necessary because graph-input rows are closer to the PriceFM modeling
environment than target-only rows.

## Commands

Regenerate the article tables:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/70_build_pricefm_article_tables.py
```

Run the comparability audit:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/71_audit_pricefm_stage_m_comparability.py
```

Run focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_m_article_readiness.py \
  application/tests/test_pricefm_stage_l_decision_surface.py \
  application/tests/test_pricefm_stage_k_summarizers.py
```

Compile the Stage-M scripts:

```sh
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/67_summarize_pricefm_stage_l_split_diagnostics.py \
  application/scripts/pricefm/68_summarize_pricefm_current_decision_surface.py \
  application/scripts/pricefm/69_audit_pricefm_validation_test_alignment.py \
  application/scripts/pricefm/70_build_pricefm_article_tables.py \
  application/scripts/pricefm/71_audit_pricefm_stage_m_comparability.py
```

## Decision

Stage M is ready for manuscript drafting under the scoped PriceFM Phase-I
comparison language above.  The next step is to write the PriceFM data/model
application subsection and introduce the Stage-M tables, not to launch another
model-selection grid.
