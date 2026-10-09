# Q--DESN editorial review implementation

Prepared 2026-10-09. Scientific baseline:
`77326d62870f69d7c1a56955dd5b5a05d17ddece`.
Editorial source branch:
`work/pro-technometrics-review-implementation-20261008`.

## Scope and evidence

This revision implements the supported recommendations in the author's PRO
review. It changes exposition, bibliography, displays and presentation
derivatives, not a scientific posterior target or empirical authority. No model
was refitted, no forecast rescored, no prior/initialization changed, and no
new model-selection or posterior-draw campaign was launched. The original
review and tab-separated correction register are retained in ignored working
records, not published as manuscript dependencies. Their SHA-256 values are,
respectively,
`f0599ec069e12aac2773e67b84a49a9222572fd5fa8226e5ff5dd20cacf28a39` and
`25f6bb7f96a4942ced9fff51ae7081e775a9e7870dbfc36c6a886c181879c333`.

All 28 requested corrections and 11 additional findings have a disposition.
The following groups provide a concise implementation record; the ignored
working record retains the complete report and detailed decisions.

| Register entries | Implemented treatment |
|---|---|
| C01--C03 | Compact abstract; AL/exAL terminology; heterogeneous simulation findings, GloFAS undercoverage and adverse PriceFM aggregate retained. |
| C04--C05 | Complete expressions beside purposeful left labels; fixed-feature regularized regression contribution without a first-use or measured speed claim. |
| C06--C11 | Scoped misspecification discussion, priors with the regression, bounded predecessor comparisons, projection versus sorting, earlier hydrology's MCMC/VB, and study-specific roadmap. |
| C12--C16 | Local feature dimensions, study-specific readout choices, separately specified intercept prior, and concise global-scale reference with supplementary derivations. |
| C17--C18 | Parameter-normalized composite posterior; repeated-response density interpretation; random first slope block; optional baseline remains supplementary and is not attributed to the fitted joint study. |
| C19--C20 | Named update laws; generic versus executed variational families; analytic scale integral and shape quadrature; covariance retention, point-intercept uncertainty and coordinate-monitor qualifications. |
| C21--C24 | Origin/horizon definitions; recursive conditional location versus marginal predictive quantile; equal-weight projection versus scoring weights; DGP expectation and averaged-feature interval scope. |
| C25--C26 | Selection, prior calibration, starting values and inference distinguished; PriceFM independent-only VB; matching-model MCMC transfer; readable single-quantile DGP. |
| C27 | Authenticated three-panel GloFAS figure, unchanged seven-family score table without internal status column, full-family supplementary figure, and no invented credible ribbons. |
| C28 | First-reader consistency pass, public dependency/execution map and explicit reproducibility boundaries. |
| N01--N03 | Seven bibliography records corrected from primary metadata; archived exdqlm 1.1.1 DESCRIPTION and automatic R citation resolve the historical package-credit conflict. |
| N04--N08 | Full auxiliary prior, explicit variational factor independence, transformed entropy/Jacobian, stacked density evaluation and a numbered ELBO with correct semantic reference. |
| N09--N10 | Simulation graphics readable at insertion size; unchanged plotted summaries; numerically regularized GloFAS driver covariance accurately described. |
| N11 | Official author contact/address, author-confirmed funding and disclosure, identified/anonymous materials and factual availability statement; unresolved journal-specific requirements are not certified. |

The written mathematical corrections do not establish an additional historical
fitting defect. The correct global inverse-gamma shape `(r+1)/2` is preserved.
Equal conditional coefficient variances do not make the normalized direct RHS
and Nishimura--Suchard product hierarchies interchangeable. Gaussian prior
calibration is described as calibration, not concealed as initialization;
chain starting values do not redefine the documented prior centres.

## Presentation and manuscript verification

The new simulation graphics and GloFAS drawing have separate names and a
separate hash manifest. Original scientific CSVs, PDFs, wrappers, registries
and authority manifests are retained unchanged. The six simulation graphics
retain scores, intervals, oracle references and crossing definitions.
The GloFAS drawing uses 30 authenticated consecutive historical dates, 51
issued members over 28 dates, and unchanged seven-level quantile curves. Its
model panels share a vertical scale and keep Normal Ridge's poor coverage
visible. The supplementary full-family plot remains available.

`tables/qdesn_pro_review_presentation_manifest.json` records all thirteen
presentation outputs and their sources. A disposable rebuild reproduced that
manifest and all thirteen output hashes exactly in the recorded R 4.6.0
environment. At the actual insertion widths, ordinary labels are approximately
9.17 bp for independent figures, 9.04 bp for joint figures and 9.18 bp for
GloFAS. No raster images are embedded in these PDFs. See the companion
`pro_review_presentation_revision_20261008.md` for extraction and figure checks.

The bounded supplementary-mathematics test checks 29 identities/assertions,
including the auxiliary hierarchy, factorization, GIG normalizer and
scale/shape moments. Its largest numerical discrepancy is `2.24e-10`.
The bibliography/initialization regression and five presentation tests pass.
The final-manuscript checker preserves its nineteen frozen scientific hashes
and verifies 216 independent interval roles and both sets of 32 joint metric
rows. Projection checkers retain their original scientific invariants while
checking the new active presentation references and derivative hashes.

Four isolated manuscript proofs build with settled references and clean final
LaTeX/BibTeX logs: identified main/supplement, 36/84 pages; anonymous
main/supplement, 34/83 pages. The ELBO reference resolves to equation `S56`,
not section `S7`. Author text and identifying PDF metadata are absent from the
anonymous proofs. The larger-label graphics and additional mathematical
account increase pages relative to the reviewed baseline (35/78 and 33/77);
this record does not claim a page reduction. The abstract contains 160 words.

The principal bounded commands, from the article repository root, are:

```bash
Rscript application/tests/test_pro_review_supplement_math.R
Rscript application/tests/test_pro_review_bibliography_initialization.R
python application/tests/test_pro_review_presentation.py
Rscript scripts/check_qdesn_final_manuscript_revision.R
Rscript scripts/check_joint_qdesn_pure_desn_article_projection.R
Rscript scripts/check_independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.R --validation-root AUTHENTIC_FROZEN_EXDQLM_VALIDATION_WORKTREE
Rscript application/scripts/448_check_glofas_search3_article_projection.R
python scripts/check_pricefm_r98_article_projection.py
python scripts/audit_qdesn_article_dependencies.py --check docs/reproducibility/article_dependency_inventory.csv
bash scripts/build_technometrics_review.sh
git diff --check
```

Use R 4.6.0 and Python 3.11. The PDF inspection test requires PyMuPDF; without
it, that specific test is reported as skipped, not passed. The review used an
environment containing it. These are editorial, algebra and summary/projection
checks, not a claim that all historical scientific suites or unavailable
runtime fixtures were rerun. The full scientific harness was not executed for
this no-refit editorial revision.

## Author and journal preparation

Official UCSC sources authenticate the affiliations and institutional emails;
the existing professional byline is retained: Antonio De Leon
(`jaguir26@ucsc.edu`), Raquel Prado
(`rprado@ucsc.edu`) and Bruno Sansó (`bsanso@ucsc.edu`). The shared affiliation
is the Department of Statistics, Baskin School of Engineering, University of
California, Santa Cruz, 1156 High Street, Santa Cruz, CA 95064, USA. Antonio is
designated corresponding author, an assumption explicitly presented to the
author. The author confirmed no funding and no competing interests; those
statements appear only in the identified version.

Sources checked on 2026-10-09:

- [Antonio's UCSC directory record](https://directory.ucsc.edu/cd_detail?guid=G088881512)
  and [Baskin graduate directory](https://engineering.ucsc.edu/people/grads/).
- [Raquel's UCSC directory record](https://directory.ucsc.edu/cd_detail?guid=G001099541).
- [Bruno's UCSC directory record](https://directory.ucsc.edu/cd_detail?uid=bsanso).
- [UCSC Statistics](https://engineering.ucsc.edu/departments/statistics/)
  and [Baskin contact address](https://engineering.ucsc.edu/contact-us/).
- [ASA preparation guidance](https://files.taylorandfrancis.com/asa-style-guide.pdf)
  and [Technometrics scope](https://asq.org/quality-resources/pub/technometrics).

The journal-specific
[Instructions for Authors](https://www.tandfonline.com/action/authorSubmission?show=instructions&journalCode=utch20)
remained inaccessible (HTTP 403) during this audit. Letter paper, 12-point
text, double spacing, a compact abstract, keywords, author contacts and
anonymous proof support are retained under the accessible ASA guidance.
These checks do not certify current journal-specific page limits, portal
anonymity requirements or all submission declarations. No page limit was
invented, and no journal submission was made.

## Evidence boundaries and publication

The independent-study missing historical requests/runtime identities,
GloFAS issued-product version/time and effective fitting-row count, and
PriceFM complete lead-specific/vintage records remain explicit gaps. They
were not fabricated or converted into passing reproducibility claims. The
partial independent `rhs_ns` authentication does not certify every inherited
fit. No old 72-case PriceFM horizon table was relabelled as 114 cases.

This source record precedes remote integration. Exact publication commits and
readback receipts are recorded separately: only a clean, tested two-parent
integration merge may advance `origin/main`; only its verified allowlisted
article projection may advance the canonical snapshot and direct Overleaf.
No Overleaf-to-main merge, GitHub extension, force push, runtime object,
posterior draw, private review bundle or log is included.
