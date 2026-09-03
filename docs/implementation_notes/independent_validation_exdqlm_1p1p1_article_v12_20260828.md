# Independent-validation exdqlm 1.1.1 article projection (v12)

Date: 2026-08-28

## Purpose

This revision updates the complete exDQLM portion of the independent
single-quantile validation study after a scoped rerun under exdqlm 1.1.1. The
DQLM and both Q--DESN model families retain their preceding values. The
scientific interpretation is unchanged: the updated exDQLM results confirm the
stability of the forecast comparisons and do not establish a material forecast
improvement.

## Scientific and software authorities

- Frozen validation branch:
  `validation/independent-qdesn-exdqlm-1.1.1-rerun-20260827`
- Frozen validation commit:
  `da7d04272a6f5d53b58dd68fafae9009882b905a`
- Shared-validation merge commit:
  `223b22ab0afe12cdb9d603c0332dd7412921b156`
- exdqlm version: `1.1.1`
- exdqlm source commit:
  `6dba6f2863705e0e90f0ce19e0c75d106d022a52`
- Promotion packet:
  `validation/fitforecast_v2/promotions/independent_exdqlm_1p1p1_scoped_compatibility_v2_20260828`
- Point-candidate SHA-256:
  `b5be6f9eac67f6597c2921f2620208e5f9a4ecad0c2ed6e94ac09f09aac705cb`
- Interval-candidate SHA-256:
  `f2860023bb12ac0eb7273e444aad785b03b39e76c5f1125fa7e807c73b2faf29`

The validation branch was merged into the shared-validation authority with an
explicit merge commit. The package was then built and installed from the
merged committed tree in a clean temporary R library. Version, source commit,
RNG-repeatability behavior, exAL inference configuration, structured
scale--asymmetry variational approximation, MCMC routing, and reduced-AL paths
were checked before the article projection was generated.

## Estimands and reporting rules

The two article interfaces summarize different quantities and remain separate.

- Point tables use `fixed_path_point_metric_chain_mean_v1`. The VB entries are
  based on one fixed fitted path, while the MCMC entries average the three
  chain-level fixed-path scores.
- Interval tables and figures use
  `posterior_mean_draw_metric_equal_tailed_95cri_v1`. Their centers are
  posterior means of draw-wise criteria and their endpoints are equal-tailed
  95% intervals.

No check requires a fixed-path point score to lie inside a posterior interval.
All 18 exDQLM point rows and all 54 exDQLM interval roles are replaced as a
complete block. The remaining 162 interval roles are preserved exactly.

## Generated projection

The reproducible configuration is
`application/config/independent_validation_exdqlm_1p1p1_article_v12.yaml`.
The builder and checker are:

```bash
Rscript scripts/build_independent_validation_exdqlm_1p1p1_article_v12.R
Rscript scripts/check_independent_validation_exdqlm_1p1p1_article_v12.R
```

The projection contains:

- 72 point-table rows, including 18 exDQLM rows;
- 216 posterior-interval roles, including 54 exDQLM roles;
- six posterior-interval family tables;
- six interval figures: three MCMC and three variational-Bayes figures;
- method-specific table and figure wrappers, comparison and diagnostic CSVs,
  prose, and hash manifests.

The active interval assets use the v12 namespace. The preceding v10 assets are
retained as an archival record and pass the archive checker. The preserved
aCRPS sensitivity table has SHA-256
`74c165ad4b29f00808e058750d8f6a320b5454f97ae7133d1260ae9794d5ee2b`.

## Diagnostics

The full MCMC diagnostic surface has 162 criterion comparisons: 158 pass and
four receive warnings. Five displayed summaries carry daggers because the
corresponding source analyses warrant caution. The displayed cautions include
the two required exDQLM Gaussian-mixture, p=0.25 forecast summaries. The
inherited three-chain replay is recomputed from the tracked draw files and the
hash-pinned validation diagnostic code rather than copied from an obsolete
portable row.

The maximum absolute change in an exDQLM posterior forecast-criterion mean is
0.8464%. This supports the stated conclusion that the forecast comparisons are
stable. Some gamma--sigma dependence remains visible, so the manuscript does
not describe exdqlm 1.1.1 as a universal mixing solution.

## Verification

The following checks passed on the final article tree:

- frozen validation packet verifier: 19/19 checks;
- validation output manifest: 31/31 files matched recorded hashes and sizes;
- focused validation tests: 39 tests, zero failures, errors, or warnings, with
  one documented skip for unavailable archived pilot runtime evidence;
- article projection checker: 312 checks, 72 point rows, 216 interval roles,
  and six figures;
- complete application R test harness: exit 0;
- corrected-manuscript and score checks: pass;
- archived v10 interval checker: 72 rows, 36 VB rows, 36 MCMC rows;
- `git diff --check`: pass;
- Overleaf article manifest: sorted, complete, and free of missing files.

The manuscripts were compiled from clean temporary directories. `main.tex`
required the standard bibliography sequence plus one additional `pdflatex`
pass for reference convergence and produced 38 pages. The supplement converged
with the standard sequence and produced 48 pages. The final logs contain no
undefined references or citations, duplicate labels, overfull or underfull
boxes, BibTeX warnings, errors, or rerun requests.

All six interval figures and all six family tables were inspected in their
rendered manuscript context. Axes, panel labels, legends, intervals, dagger
marks, boldface, captions, and table widths are legible and consistent with the
generated values.

No fitted-model objects, caches, logs, checkpoints, scheduler state, or other
runtime payloads are part of this article revision.
