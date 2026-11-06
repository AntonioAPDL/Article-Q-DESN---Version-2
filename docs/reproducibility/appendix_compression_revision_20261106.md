# Online Appendix compression: 6 November 2026

## Scope and measured length

This editorial revision starts from the authoritative baseline
`a9220a25e978b50180beabe3e243bcab963f2ca1`. The identified review proofs
change from a 37-page article and 70-page Online Appendix to 37 and 56
pages, respectively. The appendix reduction is 14 pages, or 20%. The
corresponding anonymous proofs contain 36 article pages and 55 appendix
pages. Counts include references and the applicable title treatment.

The provisional 52-page appendix target was a planning estimate, not a
journal limit or a condition requiring removal of essential content. The
56-page result retains all eight appendix figures at their original
dimensions and preserves the specialized mathematics and qualifications
needed to interpret the results. Compression removes duplicate displays,
repeated explanations and unnecessary float barriers; it does not obtain
the reduction by changing fonts, line spacing or scientific figures.

The [92-entry disposition map](appendix_compression_disposition_20261106.csv)
records the retained, consolidated and public-archive destinations. The
[archive index](appendix_compression_archive_20261106.md) supplies immutable
links to the complete preceding account, full numerical tables and source
provenance. In particular, the
[baseline appendix](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/qdesn-supplement.tex)
and its original tables remain recoverable at the exact baseline commit.
The archive explicitly identifies the written error described below;
the earlier source must not be treated as uniformly corrected mathematics.

## Retained specification and evidence

The reader appendix retains the full NS joint prior and scale-dependent
Gaussian product mass; the distinct global and slab update shapes;
structured exAL scale integration, supported shape quadrature and mixed
moments; the defining Laplace--Delta approximation; and the anchored
multiquantile prior with its covariance contributions. Its forecast
construction continues to distinguish averaged future predictors from
trajectory-specific predictors and fully marginalized response quantiles.

The single-quantile generating design, selection history, inference
allocations and reconstructed-draw dependence limitations remain explicit.
All fitting-recovery, forecast-recovery, longer-period sensitivity and
empirical-frequency figures remain selected. The combined multiquantile
score table retains all 32 MCMC model--mechanism rows, including both sets
of means and all interval endpoints. The complete median and
posterior-mean-grid score fields remain in the unchanged public sources.

For GloFAS, the unit-member target, 12,483 reference-source factors and
13,883 GloFAS-source factors remain explicit. The source-specific update
map retains the response--design moment and coefficient covariance; the
future-path calculation remains a local Gaussian--Delta approximation,
not an exact joint Gaussian posterior. All seven issued-window families,
all-level empirical frequencies and adverse loss, inclusion, crossing,
inversion and negative-flow findings remain. The historical table retains
all 12 scored rows. Six all-dash discrepancy-only rows are replaced by an
explicit unscored-by-design note, not by zeros.

The PriceFM evaluation dates, input construction, selection chronology,
direct-horizon forecast rule and unverified covariate-vintage limitation
are retained. Duplicate aggregate-result prose is replaced by navigation
to the main article; no adverse comparison is reversed or omitted from
the scientific account.

## Presentation derivatives and checks

The bounded producer
[`scripts/build_appendix_compact_tables_20261106.py`](../../scripts/build_appendix_compact_tables_20261106.py)
creates exactly 11 new TeX derivatives: six numerical table displays and
five figure wrappers, one of which contains two figures. It reads only
an explicit SHA-256-pinned set of frozen CSV and TeX inputs. It neither
opens model objects nor invokes fitting, forecasting or scientific asset
builders. Original tables, wrappers, aliases, numerical CSVs and
scientific PDFs remain unchanged.

Numerical derivative checks use scientific keys rather than assumed row
positions. The 32 combined MQ rows match the frozen score CSV for 64
means and 128 interval endpoints. Independent read-only checks also match
all 14 additional-diagnostic cells across seven issued families and all
36 displayed historical score, coverage and crossing cells across 12
rows to their frozen CSVs. The compact convergence table preserves each
independent fit's iterations and worker elapsed hours, plus 19 and 22 MQ
outer sweeps, three complete passes and 22.72 and 33.99 worker hours.
Worker elapsed hours are not campaign wall-clock time.

The wrapper checks preserve graphic paths, dimensions, labels and alt
text. The actual TeX input recorder selects all eight appendix figures.
The semantic successor requires live selection of the retained evidence,
authenticates unchanged scientific assets and outer receipt hashes, and
rejects missing roles or altered numerical derivatives. Historical prose
fixtures are limited to dated wording assertions; they cannot replace
live scientific evidence or authorize changed routes by file existence.

## Written and reporting corrections

M01 corrects the source-specific exAL expression to
`psi_c = (D_gamma^2 / B_gamma) * sum_i(s_i^2 / v_i)`. The pinned producer
already includes `1/B_gamma` under the manuscript's **v augmentation**.
This is a written-formula correction, not a fitting-code repair, new fit
or revised scientific result. The archive index gives the exact source
trace and warns about the preceding written formula.

R05 separates issued-window priors from historical settings. A bounded
read-only trace authenticated all 16 small task configurations against
the input-manifest identity published for producer
`fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6`. The executed quantile-fit
settings are reference `tau0=5.2043087e-05`, discrepancy `tau0=0.0001159`,
learned slab variances under IG(2,4), intercept precision `1e-9` and
source likelihood scales under IG(2,1). The configuration's `s2=4`
initialization does not fix the slab at 4. These rounded executed
constants are not replaced by the more precise historical constants or
the historical fixed discrepancy slab. The separately reused Gaussian
baselines are not asserted to share these quantile-fit priors. Exact
manifest and prior digests are recorded in the archive index.

R01 reports the available diagnostics for the 32 primary **score
sequences**: rank-normalized R-hat 0.999314--1.037713, folded R-hat
0.999134--1.016747, bulk ESS 177.518--6845.861 and tail ESS
275.381--7423.005. These do not establish scalar-parameter convergence.
Independent level permutations and imperfect scale--shape mixing remain
limitations; the main article's diagnostic promise is narrowed to the
evidence actually available.

## Validation and remaining gates

Use Python 3.11 and the pinned R 4.6.0 environment. Review proof production
uses `pdflatex`, BibTeX and repeated LaTeX passes. The bounded derivative
check, successor admission through the reader adapter, independent
numerical comparisons and identified-proof reference/box checks have
passed at the revision checkpoint. This is not a claim that every final
integration or publication gate has completed.

The following commands document the reproducible checks. Run them from
the repository root against the final source state; any subsequent
authorized source edit requires the applicable checks and receipt
authentication to be repeated.

```sh
python3.11 scripts/build_appendix_compact_tables_20261106.py --check
python3.11 scripts/appendix_compression_validation_20261106.py --check
python3.11 scripts/refresh_reader_online_appendix_receipts_20261106.py --check
python3.11 application/tests/test_appendix_compression_20261106.py
python3.11 application/tests/test_reader_online_appendix_receipts_20261106.py
python3.11 scripts/check_qdesn_mq_nomenclature.py
python3.11 scripts/check_qdesn_sections5_7_presentation.py
python3.11 scripts/audit_qdesn_article_dependencies.py --check docs/reproducibility/article_dependency_inventory.csv
Rscript application/tests/test_independent_reporting_authority_checks.R
Rscript scripts/check_independent_forecast_300_500_v1.R
git diff --check
bash scripts/build_technometrics_review.sh
```

Before integration, finish the applicable negative tests and compatibility
checks; rebuild identified and anonymous proofs after the last edit;
inspect revised mathematics, tables, captions and float order; and confirm
the article-only dependency closure in isolation. A successful local
proof does not authorize journal submission, scientific-result promotion
or publication. Git integration and any later Overleaf deployment remain
subject to `CONTRIBUTING.md` and their fresh-source, clean-worktree,
authentication and remote-readback gates.

No model fitting, forecast generation, tuning, rescoring or scientific job
management is part of this revision. Original scientific data, settings,
outputs and figure PDFs remain unchanged; concurrent scientific work and
the private illustrative preview are untouched. To resume validation,
start from the exact baseline above, inspect the disposition map and
archive index, verify the current semantic manifest and run the bounded
checks. Do not run a broad scientific builder to refresh editorial
captions or treat an incomplete check as a successful gate.
