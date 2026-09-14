# PriceFM R98 article-authority projection

Date: 2026-09-13

## Decision

The PriceFM article comparison now uses the complete R98 region-frozen surface.
R98 replaces R92 as one indivisible 114-case authority even though its aggregate
average quantile loss (AQL) is higher. No favorable R92 case is retained.

R98 fixes one training- and validation-selected Q--DESN specification per
region before test evaluation. The reservoir specification, RHS global scale,
feature policy, and likelihood family are common to the three folds within a
region. The evaluation contains 38 regions, three folds, no post-test selection
change, no R92 fallback, and no failed score case.

The benchmark remains retrospective because Q--DESN uses retrospectively
observed lead covariates. The word *prospective* refers only to the separation
between model selection and the held-out test scores.

## Frozen evidence

The integration verified every one of the 308 entries in `source_manifest.csv`
before constructing the article projection. The principal input hashes are:

| Input | SHA-256 |
|---|---|
| `pricefm_stage_r98_authoritative_registry.csv` | `4cf8ff653c6bd7fc64a2992fbfb6e1df48867d1b7d840cd8544fb30a5c538cb6` |
| `pricefm_stage_r98_authority_transition_ledger.csv` | `35b0f3d55a1e5ac7e489b3cf171c0f9865e07a012e2fbb4a4674302fa5ef53cd` |
| `pricefm_stage_r98_global_comparison.csv` | `e3831615ceefe497d68f72176c4a68437448634868aed4c2fada5029ec2768b4` |
| `source_manifest.csv` | `98e5abd74b46988c1afa014455e8cf457929a6ecab3def39b3eeb74d89218dfa` |
| `pricefm_stage_r98_article_asset_manifest.json` | `707162b84816734a787408e244489e59fa17a27d7cdaab07ae7466994754d476` |

The builder is `scripts/build_pricefm_r98_article_projection.py`. It verifies
these inputs and all nested source-manifest entries before writing any tracked
asset. Exact copies are staged on the repository filesystem and then installed
by atomic rename. The checker is
`scripts/check_pricefm_r98_article_projection.py`.

## Reader-facing results

| Comparison | Q--DESN | PriceFM | Q--DESN minus PriceFM |
|---|---:|---:|---:|
| Mean AQL, 114 region--fold cases | 7.217007 | 7.038685 | +0.178322 |
| Cases with lower AQL | 54 | 60 | -- |
| Regions with lower three-fold mean AQL | 16 | 22 | -- |

The mean differences by fold are +0.056374, -0.027406, and +0.505998 for
folds 1, 2, and 3, respectively. The primary interpretation is that R98 is
protocol-valid but slightly worse than PriceFM in aggregate, with appreciable
heterogeneity across folds and regions.

R92 has mean Q--DESN AQL 6.823677, but it used a case-specific,
held-out-informed selection rule. It is retained only as historical sensitivity
evidence in the supplement and in Git history. The R91 selective-promotion
table and the incomplete 72-case horizon table are no longer part of the
article projection.

## Publication surface

The article-only projection contains the complete 114-row R98 registry, the
114-row transition ledger, aggregate/fold/region summaries, the frozen
region-level figure, and `tables/pricefm_r98_article_projection_manifest.json`.
The main article reports the complete overall and fold comparison. The
supplement reports the aggregate historical sensitivity and all 38 regional
means.

Historical R91/R92 builders and scientific notes remain in Git, with the two
former article builders explicitly marked deprecated. They must not overwrite
the R98 article assets.

## Reproduction

```bash
/usr/bin/python3.11 scripts/build_pricefm_r98_article_projection.py \
  --evidence-root /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r98_validity_first_authority_closeout_20260913

/usr/bin/python3.11 scripts/check_pricefm_r98_article_projection.py
```

The first command requires the frozen local evidence root. The second verifies
the tracked article projection without requiring the runtime evidence.
