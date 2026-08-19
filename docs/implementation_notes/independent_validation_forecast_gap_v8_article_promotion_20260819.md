# Independent validation forecast-gap v8 article promotion

Date: 2026-08-19

## Scope

This note records the article-safe integration of the completed independent
single-quantile Q-DESN/DQLM forecast-gap campaign. It changes no model-fitting
code, joint-QDESN result, PriceFM result, GloFAS result, or application output.

## Frozen validation authority

- Shared validation branch: `validation/shared-fitforecast-v2-1.0.0`
- Shared integration commit: `fba22d605039dcf5d48f59c7760fc01053685451`
- Frozen task commit: `f6d7bf0fa3a0c6c8473464e636b6c6aafc5aa534`
- Promotion id:
  `qdesn_dqlm_500obs_trainonly_article_v8_forecast_gap_adaptive_20260819`
- Interface SHA-256:
  `56d930b97a66a69f2a2ddfc945eeaeea2518c479490acf04611a9a2941593acc`
- Promotion-manifest SHA-256:
  `49daad634ac060f6d845a248b8bc57e0ccb77971a7fd6b543b4c010fb63f4cd1`
- Source-ledger SHA-256:
  `de65a25ba53b9372ea02a49fbf994d05e5996e32349ccbf20227f0b125f7a37c`
- Article-delta SHA-256:
  `153534e74d81688beaec974ab5a7039cab8d3ee822964153d76db52346c76d7c`

The campaign completed 378/378 jobs with no implementation failure. Its final
stage comprised eight case-specific candidates and 24 full-budget canonical
chains. Every chain completed 5,000 burn-in and 20,000 retained iterations.
The exact `M0_v_collapsed_support_logit` transition was used for exAL, and the
declared `sigma_then_gamma` transition was retained for AL. No fitted-model
binary payload is present in the tracked promotion packet.

## Article decision

The complete 72-row v8 interface replaces the rendered v6 interface. Five
strict forecast improvements enter the article-facing metric envelope:

| Model and case | Criterion | Previous | v8 |
|---|---|---:|---:|
| Q-DESN AL-RHS, Gaussian mixture, p=0.50 | Forecast MAE | 2.367921 | 0.907369 |
| Q-DESN AL-RHS, Gaussian mixture, p=0.50 | Forecast check loss | 5.585105 | 5.441483 |
| Q-DESN AL-RHS, Gaussian, p=0.05 | Forecast check loss | 1.263698 | 1.220900 |
| Q-DESN exAL-RHS, Gaussian mixture, p=0.25 | Forecast MAE | 3.396455 | 1.819331 |
| Q-DESN exAL-RHS, Gaussian mixture, p=0.25 | Forecast check loss | 4.586349 | 4.488090 |

The final two rows are inherited v7 gains that had not yet been rendered in
the article. Consuming the complete v8 interface once prevents a partial
three-row update. No fit-window criterion changes.

## Reproducible build contract

`application/config/independent_validation_trainonly_v1.yaml` pins the v8
interface, manifest, portable source ledger, decision ledger, remaining-gap
ledger, and five-row article delta. The guarded builder verifies campaign
counts, hashes, rolling-origin metadata, cumulative v6/v7/v8 confirmation
states, and all metric-source hashes before writing any article asset.

Metric evidence is resolved through validation-relative paths so verification
does not depend on historical worktree names. The generated Cairo PDF has its
creation timestamp normalized before hashing; two consecutive builds produced
identical figure and manifest hashes.

Rebuild and verification commands:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/build_independent_validation_trainonly_article.R

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/check_independent_validation_trainonly_article.R
```

The strict checker passed with 72 interface rows, 36 VB rows, 36 MCMC rows,
108 figure cells, and zero ridge rows.

## Manuscript verification

`latexmk` is unavailable in the integration environment, so the documented
`pdflatex`/`bibtex`/`pdflatex`/`pdflatex` sequence was used for both documents.

- Main article: 43 pages
- Supplement: 39 pages
- Undefined references or citations: 0
- Overfull or underfull boxes: 0
- LaTeX or package warnings in final logs: 0
- Fatal errors: 0

Build evidence is retained under the ignored path:

```text
local_trackers/independent_validation_v8_article_compile_20260819/
```

The final result pages and the updated heatmap were also rendered to images and
visually inspected for clipping, overlap, unreadable labels, and stale values.

## Generated artifact hashes

- Full table manifest:
  `629564c409fb35126a9ffb196f64d00bfd3ef5e462c78dd939581c3bd6e301eb`
- MCMC table manifest:
  `89a56c26787b860dbe1fc48f0b6484d97925a46f8ded9ffb53c4eda699974793`
- Figure manifest:
  `1e61b57715bc2e92d79da52e94c11c65dcd939d294d0dbd5b7d3bf122ab8a8df`
- MCMC comparison heatmap:
  `c900c4c056cc3d5c160c232c6f29f834bfc59a541b80b399043fcd90e58db113`

The next independent-validation campaign, if any, must branch from the merged
v8 shared authority and target only positive entries in the v8 remaining-gap
ledger. Pre-M0 exAL screens remain diagnostic rather than definitive evidence
about DESN specifications.
