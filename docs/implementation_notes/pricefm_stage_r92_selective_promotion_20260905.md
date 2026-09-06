# PriceFM R92 selective result update

Date: 2026-09-05

## Purpose

This update incorporates the completed PriceFM R87--R91 comparison without
replacing the full 56-case Q--DESN surface. The AL or exAL working likelihood
was selected for each case by validation AQL and held fixed for subsequent test
scoring. The complete selected surface had mean test AQL 6.7042093434, compared
with 6.6076371132 for the preceding Q--DESN specifications. The updated
114-case result therefore retains the preceding value in 102 cases and uses the
12 alternatives whose test AQL is lower than both the preceding Q--DESN value
and the matched released PriceFM value.

## Frozen scientific result

- Updated cases: 12 (11 exAL and 1 AL).
- Unchanged cases: 102.
- Likelihood-family changes relative to the preceding specifications: 1
  (IT_NORD, fold 3).
- Decision counts: 66 Q--DESN lower, 12 within the practical-equivalence
  margin, and 36 PriceFM lower.
- Updated Q--DESN means: AQL 6.823677420470439, AQCR 2.579293032015585%,
  MAE 16.721997707630997, and RMSE 25.449231419703835.
- Matched released PriceFM means remain AQL 7.038685346534470, AQCR 0%,
  MAE 17.273666719780330, and RMSE 26.335538393719123.
- Five cases have matched horizon-specific PriceFM evidence, replacing 20 of
  288 horizon rows; the other 268 horizon rows are unchanged.

The largest case-level AQL reductions are for IT_NORD fold 3, SE_3 fold 1,
and IT_CNOR fold 1. The article describes all case-specific differences as
descriptive because the test scores contributed to deciding which values were
retained in the aggregate result.

## Deterministic reconstruction

The integration-only materializer is
`application/scripts/pricefm/289_materialize_pricefm_stage_r92_selective_promotion.py`.
It requires `--authorize-registry-promotion`, verifies the frozen R88--R91 and
historical sources, reconstructs candidate metrics from retained R90
predictions, and writes to a new ignored directory through an atomic rename.
Its canonical output is
`application/data_local/pricefm/authoritative/pricefm_stage_r92_selective_promotion_20260905`.

Canonical output hashes:

| Output | SHA-256 |
|---|---|
| 114-case registry | `3922a06a965e8eac6320edbc2cb38464c007c51698814b419271690f9a4c9f87` |
| method summary | `e9360aba0f606038441d1ae5e442ccacd4b6e09c43c8bf11a4b1153083de254b` |
| horizon diagnostics | `a7e9bd5de2de4900225c37e62c9bddc7d04e89223074630c3562de39fa92342b` |
| horizon summary | `40f0c66fb1f9b10ed789b7f23561aafe1ad8b025f0b04bd738a3e3b623be4f44` |
| promoted-case metrics | `e3cd2649809df6befd950283c5c2813506ed87747cf39a84db3f6456ad94c3fc` |
| update ledger | `ab6e0238450ac9bca9674ccd28517a87f2266837c594a84b3d5be4e74a96dde7` |
| source manifest | `acd44652d53788ecd337bf0b3fe388e9a368ff3ccb7b567015f6e030ec116b63` |
| report | `7ddde06d8ddcc4887669c187e55e913e0a453c1eb036b7b08e11473b98e1a1f3` |
| summary | `ec878a5689273bd1f07c2e7cc2542105c0b71611f1f87e942b72b428afd7ac68` |

The source manifest contains 94 unique files with explicit source-root labels,
byte counts, and SHA-256 hashes. Ninety-three sources resolve under the
protected PriceFM evidence repository, and the materializer resolves under the
Article Version 2 repository.

## Article generation

`115_build_pricefm_full_surface_manuscript_assets.py` regenerates every
full-surface PriceFM table and figure from R92. The new
`290_build_pricefm_stage_r92_article_assets.py` independently verifies R92,
protects all 14 PriceFM Table II context rows and the released-PriceFM direct
row, and generates the paper-aligned comparison and the 12-row supplementary
table. The main article contains a concise account of the 56-case comparison;
the supplement reports all 12 retained case-level updates.

The article-only snapshot includes the new TeX table and excludes R92 CSV,
JSON, scripts, tests, and ignored runtime evidence.

## Verification commands

```text
python -m pytest -q application/tests/test_pricefm_stage_r92_selective_promotion.py
python -m pytest -q application/tests/test_pricefm_stage_r92_article_assets.py
python -m pytest -q application/tests/test_pricefm_full_surface_manuscript_assets.py
Rscript application/tests/test_qdesn_corrected_reaudit_contracts.R
git diff --check
```

Both manuscripts are compiled from isolated build directories after all tests
and deterministic regeneration checks pass. Final Git and publication hashes
are reported in the coordinator completion record.
