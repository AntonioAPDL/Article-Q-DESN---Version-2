# Independent validation paired-confirmation article promotion

The article-facing independent single-quantile validation now consumes the
immutable promotion
`qdesn_dqlm_500obs_trainonly_article_v6_paired_confirmation_20260811` from
`validation/independent-exal-m0-structural-screen-v2-1.0.0`.

The v6 handoff inherits all 72 rows from the v5 rolling-origin authority and
changes exactly two metric roles for Gaussian `p = 0.05` exQ-DESN RHS MCMC:

| Criterion | v5 value | Three-chain mean | Relative improvement |
|---|---:|---:|---:|
| Forecast MAE | 3.0486288082 | 2.8631525779 | 6.0839% |
| Forecast check loss | 1.0860907656 | 1.0804362066 | 0.5206% |

Each promoted value is the arithmetic mean of three successful full-budget
chains, each with 5,000 burn-in and 20,000 retained iterations. The predeclared
rule required both the chain mean and median to improve on v5. Fit RMSE for the
same cell and every Gaussian `p = 0.50` criterion failed that rule and remain
unchanged. Diagnostic grades are retained in the metric-level record and are
not used as accuracy vetoes.

Pinned evidence:

- validation promotion artifact commit: `5a4e6ed210bd113d2d0459c6f6b47cde6439ffcb`
- execution commit: `0f0634e40b5d1e320b61ad7af1464beb56546fb3`
- closeout commit: `aefc4e1bdc1d6b6ae1a8df1df32d384acad7a9c5`
- method: `M0_v_collapsed_support_logit`
- run tag: `ind-exal-m0-paired-confirm-v1-full-20260811__git-0f0634e`
- interface SHA-256: `d269be9219d969908b63ef818398ce31387dcaf1bc929e74b39e383f99661fb3`
- manifest SHA-256: `e11dd70df84f0af781b41533c271b323333d895735d993f7a86959ef51efdbf0`
- source-ledger SHA-256: `cd7b0159f98943c98c1f669cebaf38862c60af9eaea31b68cdbc6eee39594c96`
- source-registry SHA-256: `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`
- retained binary payloads: 0

Rebuild and verification commands:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/build_independent_validation_trainonly_article.R

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/check_independent_validation_trainonly_article.R
```

The next lower-tail calibration campaign is documented in the validation
repository but remains unlaunched. It is not part of this article authority.

## Verification

Verification on 2026-08-11 established the following:

- the validation promotion verifier passed with 72 interface rows, exactly two
  promoted metric roles, 208 source-ledger rows, and a passing storage policy;
- a direct v5-to-v6 comparison found exactly two numeric changes, both in the
  intended Gaussian `p = 0.05` exQ-DESN MCMC forecast criteria;
- the article builder and strict checker passed with 36 VB rows, 36 MCMC rows,
  zero ridge rows, and 108 figure cells;
- `main.tex` compiled to 43 pages and `qdesn-supplement.tex` compiled to 39
  pages under the documented `pdflatex`/`bibtex` fallback;
- final compile logs contained no unresolved references or citations,
  overfull boxes, or fatal errors; and
- visual inspection of the three MCMC tables and comparison heatmap found no
  clipping, overlap, or unreadable labels.
