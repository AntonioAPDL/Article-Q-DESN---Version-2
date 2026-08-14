# Independent exAL M0 validation promotion

## Scope

This update promotes completed independent single-quantile Q-DESN exAL-RHS
MCMC evidence into the article-facing 500-observation metric envelope. It does
not modify validation code, model specifications, DQLM/exDQLM baselines, VB
evidence, AL-RHS evidence, joint-QDESN material, or application pipelines.

## Frozen authority

- Validation worktree:
  `/data/jaguir26/local/src/exdqlm__wt__independent_exal_m0_relaunch_v1_1p0p0`
- Validation branch:
  `validation/independent-exal-m0-relaunch-v1-1.0.0`
- Campaign commit:
  `89d214e94f97a2cf0ac606f5ae424225f36ad98b`
- Run tag:
  `ind-exal-m0-v1-20260809_161838__git-89d214e`
- Inference method:
  `M0_v_collapsed_support_logit`
- Source registry SHA-256:
  `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`
- Article interface SHA-256:
  `3cc65a3ec8d572e91ff2b69b37f53ee47ce9ebd0fec1fe370a1e6bf24c757c23`

The campaign completed 45 of 45 chains across 15 case-specific anchors. Each
anchor pools three chains and 60,000 retained draws. Thirteen anchors have PASS
diagnostics and two have WARN diagnostics. No worker failed and no binary model
payload is retained.

## Selection decision

The v3 article authority was checked role by role against the M0 closeout. M0
was promoted only when its pooled value was strictly lower for the same model,
family, quantile, inference method, and metric. Diagnostic grade was preserved
but was not used as an exclusion rule.

- 22 of 27 exAL-RHS MCMC metric roles were replaced;
- five non-improving roles retained their previous value and provenance;
- exAL-RHS within-table minima increased from 10 to 16 of 27;
- 11 nonwinning roles remain in the targeted gap ledger.

The next calibration stage should not repeat a broad sampler-method search. It
should use the remaining-gap ledger to target the three lower-quantile fit-RMSE
gaps first, followed by Gaussian and Gaussian-mixture (p=0.25) forecast gaps.
Median forecast gaps are secondary.

## Generated article assets

The pinned v4 interface regenerates:

- the 72-row article and compatibility summaries;
- three main-text MCMC family tables;
- three VB/MCMC companion family tables;
- the consolidated companion table and protocol table;
- the 108-cell MCMC heatmap data and PDF;
- table, MCMC, and figure provenance manifests.

The figure generator now writes workspace-relative metric paths and the figure
checker validates the exact 36-row MCMC authority, all 108 plotted values,
metric-level source hashes, within-cell minima, and the common source registry.

## Verification commands

```bash
Rscript scripts/build_independent_validation_trainonly_article.R
Rscript scripts/check_independent_validation_trainonly_article.R
Rscript scripts/check_qdesn_mcmc_validation_figure.R
mkdir -p local_trackers/codex_compile_20260809_exal_m0/main
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=local_trackers/codex_compile_20260809_exal_m0/main main.tex
bibtex local_trackers/codex_compile_20260809_exal_m0/main/main
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=local_trackers/codex_compile_20260809_exal_m0/main main.tex
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=local_trackers/codex_compile_20260809_exal_m0/main main.tex
```

`latexmk` was unavailable in the verification environment, so the documented
`pdflatex`/`bibtex` fallback was used for both the main article and supplement.
Both compiled to 39 pages. Their final logs contain no undefined-reference,
overfull-box, package-warning, or fatal-error messages; visual inspection of
the regenerated tables and heatmap found no clipping or overlap.

The invalid tags
`ind-exal-m0-v1-20260809_160325__git-1ac48bd` and
`ind-exal-m0-v1-20260809_160714__git-0541583` remain non-consumable.
