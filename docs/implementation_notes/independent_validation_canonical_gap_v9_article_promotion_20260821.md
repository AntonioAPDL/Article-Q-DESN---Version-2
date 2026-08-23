# Independent validation canonical-gap v9 article promotion

Date: 2026-08-21

## Scope

This note records the article-safe integration of the completed independent
single-quantile Q-DESN/DQLM canonical-gap campaign. The update is restricted to
the pinned validation interface, generated independent-validation tables and
figure, their build/check contracts, and corresponding manuscript prose. It
changes no fitting code and no joint-QDESN, PriceFM, GloFAS, or application
result.

The integration-ready article branch was rebuilt on 2026-08-23 from Article-v2
`origin/main` at `2d9bc8ccd0a55bc47dfb3934a7e477259d0de05e` rather than merged
from the earlier article branch. This preserves the subsequent reader-facing
language cleanup while applying the v9 evidence and build contract.

## Frozen validation authority

- Task branch: `validation/qdesn-canonical-gap-mcmc-v2-1.0.0`
- Scientific design and execution commit:
  `ec9a921c9adf4e183a4ce4e61ba7714a91f7f779`
- Closeout implementation commit:
  `d585cd5b55872d674d651b08875abf0042733bee`
- Promotion id:
  `qdesn_dqlm_500obs_trainonly_article_v9_canonical_gap_20260821`
- Interface SHA-256:
  `eb697b6f3e366581d158a41ecd2213761486be769b541439d2d862d840ea4b27`
- Promotion-manifest SHA-256:
  `b5a87a3b5a69ac36a1a16ee8a2638ca3d374ea1d6a80b6b72ba44901376a3993`
- Source-ledger SHA-256:
  `aefdd71842fc0ee56fdf34bed3dd739297be6f73c14b31999ee788263f5f52f2`
- Article-delta SHA-256:
  `37fa5a69d1047286201e444984f70d626da700b916b8e637b74fe1a8db5849b4`

The campaign completed 176/176 jobs with no implementation failure: two
smoke, four calibration, 128 screen, 36 refinement, and six canonical
confirmation jobs. Each promoted case was confirmed with three chains, 5,000
burn-in iterations, and 20,000 retained iterations per chain. exAL used the
exact `M0_v_collapsed_support_logit` transition; AL retained
`sigma_then_gamma`. The compact packet contains no fitted-model binary.

## Article decision

The complete 72-row v9 interface replaces v8. Four strict forecast
improvements enter the case-specific metric envelope:

| Model and case | Criterion | v8 | v9 | Gain |
|---|---|---:|---:|---:|
| Q-DESN AL-RHS, Gaussian, p=0.05 | Forecast MAE | 8.410107 | 6.916594 | 17.8% |
| Q-DESN AL-RHS, Gaussian, p=0.05 | Forecast check loss | 1.220900 | 1.200170 | 1.7% |
| Q-DESN exAL-RHS, Gaussian mixture, p=0.50 | Forecast MAE | 2.562274 | 1.419645 | 44.6% |
| Q-DESN exAL-RHS, Gaussian mixture, p=0.50 | Forecast check loss | 5.610103 | 5.486730 | 2.2% |

The replacement rule is deliberately metric-specific: every finite
three-chain forecast mean strictly below v8 is promoted, while diagnostic
grades remain disclosed and do not veto an accuracy improvement. No fit RMSE
or other displayed criterion changes.

## Reproducible build contract

`application/config/independent_validation_trainonly_v1.yaml` pins the v9
interface, promotion manifest, source ledger, decision and remaining-gap
ledgers, cumulative article delta, v8-to-v9 effect ledger, six-chain evidence,
exact promoted specifications, and rollback ledger. The builder verifies these
hashes, every metric-source hash, campaign counts, confirmation-state counts,
rolling-origin metadata, and the no-binary storage policy before writing an
article asset.

The configured validation root remains the canonical shared-validation
worktree. Before integration, the guarded scripts can verify the frozen task
branch through an explicit portable override, with `VALIDATION_ROOT` set to a
checkout containing the pinned promotion packet:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/build_independent_validation_trainonly_article.R \
  --validation-root "$VALIDATION_ROOT"

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/check_independent_validation_trainonly_article.R \
  --validation-root "$VALIDATION_ROOT"
```

The strict checker reports 72 interface rows, 36 VB rows, 36 MCMC rows, 108
figure cells, and zero ridge rows.

`latexmk` is unavailable in the integration environment, so both documents
were compiled with the documented `pdflatex`/`bibtex`/`pdflatex` convergence
sequence. The refreshed main article compiled to 40 pages and the supplement to
39 pages, with no undefined reference or citation after convergence. Final logs
retain two pre-existing box warnings outside the changed lines: a 4.78-point
main-text overflow and a 0.66-point supplementary heading overflow. The three
updated MCMC tables, heatmap, and confirmation prose were rendered and visually
inspected for clipping, overlap, stale values, and unreadable labels. Build
evidence is retained under the ignored directory
`local_trackers/independent_validation_v9_integration_ready_20260823/`.

## Generated artifact hashes

- Full table manifest:
  `0edea5476652888af2ff1ed6ff65bf2080ca1d151ee1d7b82401d9e1bf174bdb`
- MCMC table manifest:
  `40ce441a414e255435f391105c105d8e13ea4e232926fbf9f1c04a9c4b6c9bb1`
- Figure manifest:
  `ebdd00adcecb7180077e06236734e76eef52c80bc96ac4cc9107372269a7124c`
- MCMC comparison heatmap:
  `42205e6eaf215cfec56c81c3114dd6e56eace5cc5a8f90c195f5e233bce9f29c`

The integration coordinator should first fast-forward the validation task
branch into the shared validation authority and then merge
`work/independent-validation-v9-integration-ready-20260823` into the latest
Article-v2 `origin/main`. That ordering makes the tracked default validation
root resolve the pinned v9 packet without depending on either task worktree.
