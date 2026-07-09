# PriceFM Stage-M Selection Protocol And Article Readiness

Date: 2026-06-24

## Purpose

Stage M turns the completed PriceFM model-selection work into an article-ready
evidence layer.  It does not launch new DESN/Q-DESN fits, does not patch the
authoritative registry, and does not promote any Stage-K or Stage-L test-only
candidate.

The stage answers three questions:

1. What is the current local DESN/Q-DESN versus PriceFM decision surface?
2. Where do validation and test selection signals agree or disagree?
3. Which tables and figures are safe to introduce in the article?

## Inputs

Current median registry:

```text
application/data_local/pricefm/authoritative/pricefm_stage_l_current_decision_surface_20260624/current_median_registry.csv
```

Current paper-quantile decision registry:

```text
application/data_local/pricefm/authoritative/pricefm_stage_l_current_decision_surface_20260624/current_quantile_decision_registry.csv
```

Validation/test diagnostic sources:

```text
application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_priority0_closeout_20260623/rescue_closeout_decisions.csv
application/data_local/pricefm/authoritative/pricefm_stage_k_regularized_graph_multiseed_summary_20260623/multiseed_seed_decisions.csv
application/data_local/pricefm/authoritative/pricefm_stage_l_si_seed_expansion_summary_20260624/multiseed_seed_decisions.csv
```

Stage L already verified that the decision surface has 42 current median rows,
42 current quantile rows, finite metrics, unique keys, and no fatal registry
health failures.

## Implemented Tooling

New scripts:

```text
application/scripts/pricefm/68_summarize_pricefm_current_decision_surface.py
application/scripts/pricefm/69_audit_pricefm_validation_test_alignment.py
application/scripts/pricefm/70_build_pricefm_article_tables.py
application/scripts/pricefm/71_audit_pricefm_stage_m_comparability.py
```

Updated script:

```text
application/scripts/pricefm/67_summarize_pricefm_stage_l_split_diagnostics.py
```

The split-diagnostic script now supports registry-driven adapter discovery, so
it can summarize all current region/fold rows rather than only the Stage-L LV/SI
diagnostic subset.

## Commands

Current decision surface:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/68_summarize_pricefm_current_decision_surface.py
```

Validation/test alignment:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/69_audit_pricefm_validation_test_alignment.py
```

All-current split diagnostics:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/67_summarize_pricefm_stage_l_split_diagnostics.py \
  --registry-csv application/data_local/pricefm/authoritative/pricefm_stage_l_current_decision_surface_20260624/current_median_registry.csv \
  --regions '' \
  --folds '' \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_m_split_diagnostics_20260624
```

Article tables:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/70_build_pricefm_article_tables.py
```

Comparability audit:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/71_audit_pricefm_stage_m_comparability.py
```

## Outputs

Current decision surface:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/
```

Validation/test alignment:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_validation_test_alignment_20260624/
```

Split diagnostics:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_split_diagnostics_20260624/
```

Article tables:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_article_tables_20260624/
```

Comparability audit:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_comparability_audit_20260624/
```

Article-facing CSVs:

```text
article_comparability_guardrails.csv
article_table_region_fold_decisions.csv
article_table_fold_summary.csv
article_table_method_information_set_summary.csv
article_table_validation_test_alignment.csv
article_table_split_shift_diagnostics.csv
article_figure_index.csv
```

## Main Decision-Surface Results

Negative AQL deltas mean the local DESN/Q-DESN decision is better than
PriceFM.

| scope | region/folds | local wins | win rate | mean local AQL | mean PriceFM AQL | mean delta |
|---|---:|---:|---:|---:|---:|---:|
| all current decisions | 42 | 25 | 0.595 | 8.632 | 8.960 | -0.328 |
| fold 1 | 15 | 8 | 0.533 | 8.746 | 9.068 | -0.321 |
| fold 2 | 13 | 11 | 0.846 | 8.248 | 8.629 | -0.380 |
| fold 3 | 14 | 6 | 0.429 | 8.866 | 9.152 | -0.285 |

By model family:

| model family | region/folds | local wins | win rate | mean delta |
|---|---:|---:|---:|---:|
| Q-DESN exAL RHS_NS | 36 | 21 | 0.583 | -0.352 |
| Q-DESN AL RHS_NS | 6 | 4 | 0.667 | -0.183 |

By information set:

| information set | region/folds | local wins | win rate | mean delta |
|---|---:|---:|---:|---:|
| PriceFM graph inputs | 27 | 20 | 0.741 | -0.719 |
| target-only local inputs | 15 | 5 | 0.333 | 0.377 |

This is a crucial article distinction: the current strongest comparison is not
purely local.  Many of the best rows use PriceFM graph-neighbor information.
Target-only rows are still useful as an ablation, but they are not the strongest
current competitor.

Largest local wins:

| region | fold | method | information set | local AQL | PriceFM AQL | delta |
|---|---:|---|---|---:|---:|---:|
| EE | 1 | `qdesn_exal_rhs_ns_exact_chunked` | graph inputs | 15.483 | 19.270 | -3.787 |
| EE | 3 | `qdesn_exal_rhs_ns_exact_chunked` | graph inputs | 13.621 | 16.114 | -2.493 |
| DK_2 | 3 | `qdesn_exal_rhs_ns_exact_chunked` | graph inputs | 7.411 | 9.369 | -1.957 |
| DK_2 | 2 | `qdesn_exal_rhs_ns_exact_chunked` | graph inputs | 6.332 | 8.251 | -1.920 |
| NL | 1 | `qdesn_exal_rhs_ns_exact_chunked` | graph inputs | 5.370 | 7.242 | -1.872 |

Largest PriceFM wins:

| region | fold | method | information set | local AQL | PriceFM AQL | delta |
|---|---:|---|---|---:|---:|---:|
| LT | 1 | `qdesn_exal_rhs_ns_exact_chunked` | target-only | 14.481 | 12.490 | 1.991 |
| HU | 2 | `qdesn_exal_rhs_ns_exact_chunked` | graph inputs | 8.684 | 7.322 | 1.362 |
| SK | 3 | `qdesn_exal_rhs_ns_exact_chunked` | graph inputs | 8.807 | 7.504 | 1.303 |
| FI | 1 | `qdesn_exal_rhs_ns_exact_chunked` | target-only | 10.555 | 9.253 | 1.301 |
| AT | 3 | `qdesn_exal_rhs_ns_exact_chunked` | target-only | 7.647 | 6.755 | 0.892 |

By frozen decision label:

| decision label | rows | wins | mean delta |
|---|---:|---:|---:|
| confirmed local win | 25 | 25 | -1.028 |
| local close to PriceFM | 6 | 0 | 0.297 |
| PriceFM fallback | 11 | 0 | 0.923 |

The frozen decision labels are internally consistent with the current AQL
surface.

## Validation/Test Alignment Results

Current median registry:

| quantity | value |
|---|---:|
| rows | 42 |
| mean absolute test-minus-validation AQL | 1.831 |

Diagnostic rows:

| source | rows | region/folds | validation win rate | test win rate | disagreement rate | mean validation delta | mean test delta |
|---|---:|---:|---:|---:|---:|---:|---:|
| Stage J priority-0 closeout | 9 | 9 | 0.889 | 0.222 | 0.667 | -0.501 | 0.560 |
| Stage K regularized graph | 87 | 8 | 0.034 | 0.391 | 0.356 | 1.303 | 1.360 |
| Stage L SI seed expansion | 8 | 1 | 0.500 | 1.000 | 0.500 | -0.054 | -1.726 |

Interpretation:

- Stage J mostly improved validation but not test, so it exposed overfitting
  risk.
- Stage K mostly failed validation and did not produce a stable rescue.
- Stage L SI fold 1 improved test for every seed, but half the seeds failed
  validation.  It remains test-promising but not promotable.

## Split Diagnostics

The current-registry split diagnostic covered:

| item | value |
|---|---:|
| region/folds | 42 |
| split rows | 126 |
| contrast rows | 126 |
| regions | 15 |
| folds | 3 |

Aggregate split contrasts on scaled responses:

| contrast | rows | mean mean-delta | mean median-delta | mean sd-ratio |
|---|---:|---:|---:|---:|
| validation minus train | 42 | -0.469 | -0.170 | 0.532 |
| test minus validation | 42 | 0.011 | 0.009 | 0.934 |
| test minus train | 42 | -0.458 | -0.161 | 0.488 |

The validation and test windows are both lower and less variable than training
on average.  Test and validation are much closer to each other than either is
to training, but model-level validation/test disagreements still occur.

## Figures

Generated figure paths:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/figures/stage_m_aql_delta_by_region_fold.png
application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/figures/stage_m_local_wins_by_fold.png
application/data_local/pricefm/authoritative/pricefm_stage_m_validation_test_alignment_20260624/figures/stage_m_current_validation_vs_test.png
application/data_local/pricefm/authoritative/pricefm_stage_m_validation_test_alignment_20260624/figures/stage_m_rescue_validation_test_deltas.png
```

## Article Readiness Decision

The PriceFM results are now ready for a first article-facing data/model/results
draft with careful scope language:

- The comparison currently covers 42 region/fold decisions.
- The quantile-grid comparison is against cached fold-aligned PriceFM Phase-I
  predictions on the same selected region/fold test rows.
- The direct metric is original-unit AQL on the paper quantile grid
  `0.10,0.25,0.45,0.50,0.55,0.75,0.90`.
- Results must distinguish graph-input rows from target-only rows.
- Stage-K and Stage-L should be described as unsuccessful rescue attempts, not
  as promoted model improvements.
- SI fold 1 is a validation/test mismatch example, not a new winner.
- PriceFM paper headline metrics should be used only as broad context.  The
  article table should use the fold-aligned Phase-I rows, because the Stage-M
  selected panel is not the full paper-wide benchmark.

## Comparability And Writing Audit

Tracked note:

```text
docs/implementation_notes/pricefm_stage_m_comparability_and_writing_audit_20260624.md
```

The comparability audit passed `12` checks with `0` fatal failures and `0`
warning failures.  It verified unique region/fold keys, finite AQL metrics,
the AQL delta identity, decision-label consistency, graph-input versus
target-only metadata, the absence of Stage-L test-only promoted rows, and the
presence of generated article claim guardrails.

Article-safe phrasing:

> On the selected 42 region/fold panel, the current DESN/Q-DESN registry has
> lower fold-aligned PriceFM Phase-I AQL in 25 cases.  The advantage is
> concentrated in rows that use released PriceFM graph-neighbor inputs; the
> target-only ablation remains weaker on average.

Avoid broader language such as "Q-DESN outperforms PriceFM overall" or direct
comparisons between the selected-panel AQL and the paper-wide aggregate AQL.

## Recommended Next Step

Start drafting the article-facing PriceFM subsection from the Stage-M tables.
Do not launch another broad grid until the manuscript tables make clear which
region/folds remain unresolved and whether the next scientific question is:

1. target-only ablation improvement;
2. graph-input comparison refinement;
3. validation/test protocol revision; or
4. broader regional scaling.

The immediate next coding step, if needed, is a lightweight manuscript-table
export that converts the Stage-M article CSVs into LaTeX-ready tables.  It
should not rerun models.

## Validation

Focused tests:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_m_article_readiness.py \
  application/tests/test_pricefm_stage_l_decision_surface.py \
  application/tests/test_pricefm_stage_k_summarizers.py
```

Result:

```text
16 passed
```

Compile check:

```sh
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/67_summarize_pricefm_stage_l_split_diagnostics.py \
  application/scripts/pricefm/68_summarize_pricefm_current_decision_surface.py \
  application/scripts/pricefm/69_audit_pricefm_validation_test_alignment.py \
  application/scripts/pricefm/70_build_pricefm_article_tables.py \
  application/scripts/pricefm/71_audit_pricefm_stage_m_comparability.py
```

Result: passed.
