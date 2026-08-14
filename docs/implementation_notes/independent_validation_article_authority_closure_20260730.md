# Independent Validation Article-Authority Closure

## Scope

This note records the no-change closure of the independent single-quantile
Q-DESN/exQ-DESN and DQLM/exDQLM simulation tables. It does not cover the joint
multi-quantile study, GloFAS, PriceFM, or any application implementation.

## Evidence Hierarchy

The displayed numerical authority remains:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/
  validation/fitforecast_v2/promotions/
  qdesn_dqlm_500obs_mcmc_metric_envelope_20260727/
  qdesn_dqlm_500obs_mcmc_metric_envelope_20260727_article_envelope.csv
```

Its SHA-256 is:

```text
aa4399576453ec0e9eeb21fa2166a1aaeed977c976064b13c4dc27f963cbb9a1
```

The current authority overlay is:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/
  validation/fitforecast_v2/promotions/
  qdesn_500obs_mcmc_nested_final_origin9000_v1_evidence_freeze_20260730/
  evidence_freeze_manifest.json
```

The overlay was committed on validation branch
`validation/shared-fitforecast-v2-1.0.0` at
`b24cb53f34863f1ca7a6df95c8508d341de5692d`. It verifies the July 27
numerical envelope, the separate coherent confirmation, the latest July 30
closeout, run-consumption policy, and exposed-origin policy.

## Scientific Decision

The corrected July 30 final-origin campaign completed 8/8 roots and 16/16 MCMC
seed fits. None of its four coherent candidates improved on its parent across
all primary metrics. The decision is therefore:

```text
NO_CONFIRMED_COHERENT_ARTICLE_REFRESH
```

The article keeps the existing 36-row metric envelope and all 108 displayed
values unchanged. The valid July 30 run is retained as negative confirmation
evidence. The earlier short-draw run is permanently rejected. Source origin
9000 is exposed and cannot be reused as an untouched confirmation origin.

## Deterministic Article Build

The article builder now requires both the numerical promotion and the authority
overlay. It verifies:

- package version 1.0.0 and the validation branch;
- source-registry SHA-256
  `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`;
- all source and authority-ledger hashes;
- the 36-row numerical grid and 129-candidate ledger;
- the coherent-confirmation contract;
- zero July 30 article-refresh rows;
- the valid and rejected July 30 run tags;
- origin 9000 as exposed;
- absence of stale `/home/jaguir26/local/src` authority paths.

The generated manifest uses the frozen authority date rather than wall-clock
time, and article artifact paths are repository-relative. Repeated builds are
therefore byte-stable.

## Commands

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla \
  scripts/build_qdesn_mcmc_current_best_validation_tables.R

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla \
  scripts/check_qdesn_mcmc_current_best_validation_tables.R
```

The checker verifies all four source/authority inputs, all four article table
artifacts, their recorded SHA-256 hashes, and all 108 displayed values.

The manuscript compile fallback is:

```bash
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=/tmp/article_qdesn_independent_validation_closure main.tex

cd /tmp/article_qdesn_independent_validation_closure
BIBINPUTS=/data/jaguir26/local/src/Article-Q-DESN---Version-2: bibtex main
```

Return to the repository and run two more `pdflatex` passes with the same
output directory. The final log must contain no unresolved citations or
references, multiply defined labels, overfull boxes, fatal errors, or hyperref
warnings.

## Verification Results

The complete `validation/fitforecast_v2/tests/testthat` directory passed under
R 4.6.0, including all four deferred expressions. On the article side:

- two consecutive table builds were byte-identical;
- four authority inputs and four article artifacts passed SHA-256 checks;
- all 108 displayed numerical values matched the 36-row authority;
- the three table bodies and wrapper were unchanged from article `main`;
- the regenerated article manifest has SHA-256
  `cbf6ecf19f0f8b4360235633231fd988eae8b8021155e7beeb506e8caecc793d`;
- the full article compiled in three `pdflatex` passes with one intervening
  `bibtex` pass;
- the resulting 38-page PDF had SHA-256
  `56e9bb50a69784f34eab5191a17bafc722135fbd839acb5e1e2e563c5368c5ea`;
- the final log scan found zero key diagnostics.

## Future Update Rule

A later screen must create a new immutable promotion and authority overlay. It
must not edit the July 27 numerical promotion or this July 30 no-change
closure. One coherent specification must supply all promoted metrics for a
cell, and confirmation must use source replicates or seeds declared before
fitting. The article tables change only after a new overlay explicitly records
positive refresh rows.
