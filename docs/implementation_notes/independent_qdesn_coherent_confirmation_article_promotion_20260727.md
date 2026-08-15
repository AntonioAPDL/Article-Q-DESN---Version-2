# Independent Q-DESN Coherent-Confirmation Article Promotion

Date: 2026-07-27

## Scope

This note records the article-safe promotion of the independent single-quantile
Q-DESN/DQLM validation evidence. It changes no validation logic, application
pipeline, joint-QDESN code, PriceFM code, or GloFAS code.

## Frozen Validation Evidence

- Validation worktree:
  `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Validation branch:
  `validation/shared-fitforecast-v2-1.0.0`
- Pushed validation head:
  `ca2917a9eda28a4b8d3d1b6c346f24fd8e6a1847`
- Clean materialization commit:
  `57634838055b271fc99c61f584dab31b1ddfb0c1`
- Package version: `1.0.0`
- Promotion id:
  `qdesn_dqlm_500obs_mcmc_metric_envelope_20260727`
- Shared source-registry SHA-256:
  `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`
- Candidate ledger: 129 rows
- Article-facing envelope: 36/36 cells
- New metric-wise minima: 0
- Coherent full-budget confirmations: 1

The immutable promotion root is:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/
  validation/fitforecast_v2/promotions/
  qdesn_dqlm_500obs_mcmc_metric_envelope_20260727/
```

## Coherent Confirmation

The added row is the Laplace, \(p=0.25\), exAL-RHS candidate:

```text
qdesn__laplace__0p25__tt500__rhs_ns__mcmc__exal__020293d289bcb0
```

Its full-budget run tag is:

```text
qdesn-tt500-mcmc-external-coherent-confirmation-v1-full-
  20260727__git-5787212
```

It completed one root and one fit successfully and passed the frozen external,
stability, source-hash, source-window, and storage-light gates. The retained
diagnostic grade is `WARN` with reason `chain_marginal_but_usable`.

| Metric | Coherent confirmation | Existing metric-wise minimum |
|---|---:|---:|
| Fit RMSE | 1.747288 | 1.727325 |
| Forecast MAE, \(H=1000\) | 1.367163 | 1.355324 |
| Forecast check loss, \(H=1000\) | 4.388165 | 4.378391 |

The coherent candidate is therefore supporting evidence, not a replacement
for a lower metric-wise minimum. The manuscript table values remain unchanged.

## Article Integration Contract

The article builder:

```bash
Rscript scripts/build_qdesn_mcmc_current_best_validation_tables.R
```

must verify:

- the exact promotion id and package version;
- the source-registry hash;
- all promotion input and output hashes;
- 129 candidate rows and 36 complete envelope rows;
- one coherent confirmation and zero metric promotions;
- clean validation materialization provenance;
- the exact confirmation run, specification, decision, and diagnostic grade;
- no active `/home/jaguir26/local/src` paths.

It regenerates the three family tables and
`tables/qdesn_validation_tt500_mcmc_current_best_manifest.txt`. The generated
manifest records both the metric-wise envelope and the separate coherent
confirmation.

## Article-Safe Files

- `main.tex`
- `scripts/build_qdesn_mcmc_current_best_validation_tables.R`
- `tables/qdesn_validation_tt500_final_mcmc_normal.tex`
- `tables/qdesn_validation_tt500_final_mcmc_laplace.tex`
- `tables/qdesn_validation_tt500_final_mcmc_gausmix.tex`
- `tables/qdesn_validation_tt500_mcmc_current_best_manifest.txt`
- this implementation note

Unrelated dirty joint-QDESN files in the authoritative article worktree are
outside this promotion and must remain untouched.

## Verification

The guarded builder completed successfully and a direct comparison with the
previous tracked tables confirmed that all three table bodies are unchanged;
only their generated source comments now identify the 2026-07-27 promotion.

`latexmk` was unavailable, so the documented fallback was run:

```bash
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=local_trackers/codex_compile_20260727_independent_promotion \
  main.tex
bibtex local_trackers/codex_compile_20260727_independent_promotion/main
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=local_trackers/codex_compile_20260727_independent_promotion \
  main.tex
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=local_trackers/codex_compile_20260727_independent_promotion \
  main.tex
```

The final 38-page PDF is:

```text
local_trackers/codex_compile_20260727_independent_promotion/main.pdf
```

The final log contains no undefined references or citations, overfull or
underfull boxes, package warnings, fatal errors, or emergency stops.
