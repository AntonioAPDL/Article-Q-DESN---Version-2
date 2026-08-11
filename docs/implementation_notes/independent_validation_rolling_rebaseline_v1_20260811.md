# Independent validation rolling-origin rebaseline v1

The independent single-quantile article tables now consume the immutable
promotion
`qdesn_dqlm_500obs_trainonly_article_v5_rolling_rebaseline_20260811` from the
exdqlm validation branch
`validation/independent-exal-m0-structural-screen-v2-1.0.0`.

The correction rederives Q-DESN forecast MAE and forecast check loss from the
archived lead-level rolling-origin paths. It changes no candidate selections,
fit metrics, DQLM/exDQLM values, source registry, fit/forecast windows, maximum
lead, or origin stride. The bundle verifies 72 Q-DESN forecast roles, corrects
71 scalar values, has zero unresolved roles, and retains no R binary payloads.

Pinned evidence:

- validation promotion commit: `e12685b6005b74a297fd7b58360ced90746dea1c`
- interface SHA-256: `f9a2fbe2a791c28bb4d09a190888f90c6172270085d19627855150cfb3872f28`
- manifest SHA-256: `9ce5667a4f38d220ed60d71cc1d96f47417d3cbebddee5b0a8e51d62d0e4e128`
- source-ledger SHA-256: `00f58c5c20ac50fea256c433f66da213f2e440adc2f59d29af21f33f3a6bedf4`
- source-registry SHA-256: `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`

Rebuild and verification commands:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/build_independent_validation_trainonly_article.R

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/check_independent_validation_trainonly_article.R
```

The separate 84-job paired calibration campaign remains prepared but
unlaunched. It is not part of this article authority.

Verification on 2026-08-11:

- the article builder and strict checker passed with 72 interface rows, 36 VB
  rows, 36 MCMC rows, zero ridge rows, and 108 figure cells;
- `latexmk` was unavailable, so the documented `pdflatex`, `bibtex`, and three
  convergence-pass fallback was used;
- the resulting 40-page PDF had no unresolved references or citations, fatal
  errors, or overfull boxes in the final log scan; and
- a visual check of the three MCMC tables and the comparison heatmap found no
  clipping, overlap, or unreadable labels.
