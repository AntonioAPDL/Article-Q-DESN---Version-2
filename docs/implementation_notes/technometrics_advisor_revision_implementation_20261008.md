# Advisor and Technometrics-oriented manuscript revision

Date: 2026-10-08

## Authority and scope

Starting main: e2a3be97853b1af9c8cb269a3e065336ca5590f3.

Editorial branch: work/technometrics-advisor-revision-20261008.

The authorized work implements the final advisor-revision plan, SHA-256
851cf19e71b4db127ff956e7d054714717cbe72ddd2929ccf2caf8723d300cad.
The plan remains an ignored working document, not an article input.

This revision changes exposition, mathematical descriptions, references,
presentation assertions, and dependent manuscript hashes. It does not change
an inference routine, prior setting used by a fit, model selection, scoring
rule, simulation data, table value, or scientific figure. No fit, campaign,
refit, rescoring, runtime transfer, or scientific cleanup is authorized.

## Changes and their reasons

| Location | Revision | Reason |
|---|---|---|
| Title and abstract | Identify Bayesian quantile regression on DESN features; describe contributions and bounded findings. | State the statistical construction rather than foreground the network name alone. |
| Introduction | Put problem and contribution first; distinguish Bayesian DESN and quantile-reservoir precedents; cite the authors' separate hydrologic preprint. | Avoid a first-Bayesian-reservoir claim and make the methodological difference explicit. |
| Main model | Introduce working quantile regression before the reservoir; make coefficient linearity conditional on the features explicit. | Meet the model-first advisor request without implying linear dynamics. |
| DESN description | State dimensions, fixed first-layer input bias, regression intercept, lag convention, and readout options separately. | Match the executed feature construction without imposing one readout on every study. |
| Priors | Distinguish the Nishimura--Suchard Gaussian-product prior from normalized direct RHS coefficients with independent half-Cauchy scales. | Equal conditional coefficient variances do not imply equal joint priors. |
| Joint model | Present the fitted first-slope anchor before the optional estimated-baseline extension. | Do not attribute an additional latent baseline to the fitted comparison. |
| Computation | Separate generic VB--LD, structured quadrature, ordered-intercept MCMC, constrained-point VB, and GloFAS Gaussian--Delta updates. | A generic derivation must not be presented as every analysis's implementation. |
| Scores and forecasts | Retain integrated check-loss CRPS; clarify evaluation range, posterior quantiles, recursive features, projection and coupling. | Avoid conflating a conditional location summary with a marginalized predictive quantile. |
| Simulations | Consolidate fragmented design subsections; retain criterion-specific selection, uncertainty scope, raw crossings and qualifications. | Make the comparison readable without silently redefining it. |
| Historical sensitivities | Remove an initialization-stability conclusion from a comparison that also changed specification and estimator; label the old replicated VB analysis as unverified under the corrected target. | Historical evidence does not certify corrected current fits. |
| GloFAS | Introduce the local correction problem, gauge and units; distinguish product combination from quantile-level joint fitting. | Explain the application for readers unfamiliar with its data or additive location assumption. |
| PriceFM | Correct released lead covariates to forecasts; retain unaudited issue-time vintages and historical-period viewing; record actual nested selection and folds. | Authenticate the information description without asserting operational parity. |
| Discussion | Synthesize coherence/performance and information limitations rather than repeat the model and every result. | Keep conclusions proportional to evidence. |
| Supplement | Move reservoir selection and initialization after derivations; add a compact computation map and fold-design table. | Separate theory, computational variants, selection details and empirical support. |
| Disclosure and availability | Identify actual writing assistance and public code/source availability, without claiming that private model objects are in the article bundle. | Support transparent submission preparation. |

The main retains eight numbered sections. Authors and affiliation are placed in
the author block; the arbitrary manuscript date and negative title spacing
are removed. A single balanced title line break keeps the DESN-feature phrase
together rather than leaving "Features" on an isolated second line. The title
check normalizes that layout break without changing the title wording.
Latin Modern, one-inch margins, 11-point type, one-and-a-half
spacing, author-year citations and the existing bibliography style are retained.
These are working-manuscript choices, not a claim of verified journal compliance.

## Mathematical clarification

For a = tau^2 lambda_j^2 and b = zeta^2, the product of the two Gaussian
densities equals N(0;0,a+b) times N(beta_j;0,ab/(a+b)).
The first density depends on the scales. The complete joint posterior now
retains its product over every adjacent-difference block, and over the optional
baseline block if estimated. Conditional Gaussian coefficient updates are
unchanged. The displayed inverse-gamma auxiliary hierarchy belongs inside this
product prior; it is not an assertion of independent marginal scale laws.

The fitted anchor convention is beta_base = 0 for any number of levels.
Ordered-intercept MCMC uses neighbor-bounded Gaussian full conditionals.
The executed joint VB intervals omit intercept uncertainty because intercepts
are constrained point estimates. Starting values remain distinct from fixed
prior centers and hyperparameters.

The applicable d-dimensional global-variance update has shape (d+1)/2;
unshrunk intercepts do not count toward d. No update code was changed here.

## Scientific disposition, not a new promotion

| Evidence | Disposition |
|---|---|
| Independent rolling-state v14 | Retained complete current projection; separate implementation. |
| Expanded pure-DESN joint comparison | Retained complete 32-cell MCMC and supporting VB evidence. Its frozen fitted source is e39b061e69e176c35369fae9df0657e7b484e443, descended from the RHS correction. Preserve the one recursive-design stability review and scalar-mixing limitations. |
| GloFAS Search III | Retained all Parts 1--4 and protected-window rules. Executed source 82ca91811fc2c4242068e097dd4c05f66834f99c contains the corrected global shape; partitioned block updates also include the half-Cauchy contribution. |
| PriceFM R98 | Retained all 114 cases; no favorable historical rows restored. |
| Historical Phase181/Jerez headline results | Superseded by their complete corrected replacements; not revived by this revision. |
| Historical 50-replicate VB analysis | Retained separately as historical; corrected-target equivalence unresolved. |
| Phase182 dense-grid work | Separate, untouched, not certified here. |

The historical obligation in
docs/implementation_notes/joint_qvp_rhs_deferred_rerun_register_20260908.md
remains open. A current unit-test pass is not provenance for an old fit. The
revision does not close every historical exposure or authorize reruns.

## Application evidence decisions

GloFAS uses USGS gauge 11160500, San Lorenzo River at Big Trees, California.
Flow is in cubic metres per second before log(1+x). Historical product metadata
identify v3.1 LISFLOOD consolidated GloFAS; they do not authenticate the issued
product's version. Parts 2 and 3 retain 12,455 dates, with 24,910 stacked
observations in Part 3. Do not infer Part 4's count from these certificates.
The main retains the 30-day recursive versus 28-horizon issued-window distinction,
future USGS scoring-only status, realized-weather limitation, Part 1 raw
crossings, Part 2 no-score boundary, strict joint convergence and undercoverage.
The 1/51 member weighting is an augmented working-likelihood operation, not an
identity with a fractionally powered marginal AL posterior.

The PriceFM FINAL.csv hash was authenticated against the frozen release:
98f596deba7ffaf0edd21e78e1a779256ab24dda5463d445f081e1ee4ab3a54a.
The converter preserves the released load, solar and wind forecast columns,
and all 114 executed scoring manifests use them as leads. Forecast issue-time
vintages were not independently verified. Three temporal validation periods
inside Fold 1 training select reservoir/shrinkage specifications; Fold 1 outer
validation selects AL/exAL. The region specification remains fixed across
three folds before R98 scoring, without subsequent test-driven changes.
Prior historical evaluations viewed overlapping periods.

The supplementary fold table records the actual half-open 2025 test periods,
96 quarter-hour targets per daily origin, fixed UTC+1 calendar, training-only
median/IQR scaling, executed lag-length range and spatial feature policies.
The old 72-case horizon summary is not relabeled as a complete R98 analysis.

## Verification and reproducibility

Before derivative finalization, SHA-256 equality held for all 2,532 tracked
files under tables, figures, application/config, application/R,
application/scripts and application/tests. The baseline inventory is retained
with the ignored verification receipts. Thus the manuscript work did not change
scientific inputs, source routines, test fixtures or numerical assets.

The existing independent DGP-reference manifest requires new hashes for main,
supplement and the extended manuscript checker.
The other two manifests written by the existing finalizer remain byte-identical.
Frozen input pins must not change.

The historical five-chain table has one caption-only correction. Its reference
values reproduce that sensitivity's historical comparison, not today's
draw-wise v14 summaries. All numerical cells and its CSV remain identical.
Only `article_tex_sha256` changes in the matching historical manifest; all
source, registry and numerical pins remain unchanged. The article caption is
an editorial derivative, not an output of a current repository generator.

Verification uses R 4.6.0 with that R bin first on PATH for nested processes,
and Python 3.11 with the existing pytest dependency directory. Single-threaded
BLAS settings apply only to these checks. Commands:

    Rscript scripts/finalize_independent_validation_dgp_oracle_figures_v14.R
    Rscript scripts/check_independent_validation_dgp_oracle_figures_v14.R
    Rscript application/tests/test_independent_validation_dgp_oracle_figures_v14.R
    Rscript scripts/check_independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.R
    Rscript application/tests/test_independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.R
    Rscript scripts/check_joint_qdesn_pure_desn_article_projection.R
    Rscript application/tests/test_joint_qdesn_pure_desn_article_projection.R
    Rscript application/tests/test_joint_qvp_rhs_global_shape.R
    Rscript application/scripts/448_check_glofas_search3_article_projection.R
    Rscript application/tests/test_glofas_search3_article_projection.R
    Rscript scripts/check_qdesn_final_manuscript_revision.R
    python3.11 -m pytest -q application/tests/test_pricefm_r98_article_projection.py
    Rscript application/tests/run_tests.R
    git diff --check

The global-scale reference test is sourced after 00_packages.R,
app_set_repo_root(getwd()), and rhs_global_scale_reference.R, not invoked
standalone without dependencies. The frozen independent validation root must
be supplied explicitly when using a temporary worktree.

The extended final manuscript checker adds model-first order, matching titles,
first-layer bias, complete product-prior factors, anchor hierarchy, executed
PriceFM covariate/fold descriptions, predecessor citation and historical
qualification checks. All earlier numerical, provenance, privacy and
figure-placement assertions are retained.

Both documents are built with pdflatex -recorder, BibTeX and repeated LaTeX
passes in isolated directories. Final logs, page counts, visible layout and
recorder input closure must be reviewed before publication. No scientific figure
is regenerated merely to refresh a manuscript hash.

### Results at the editorial freeze

The registered combined repository harness completed successfully under pinned
R 4.6.0 with Python 3.11 dependencies available to subprocesses. Its configured
real-data smoke check and unavailable discrepancy-engine adapter remained
explicit skips, not passes. The historical standalone missing-September-fixture
check was not used to manufacture a claim that every historical test is runnable.
The harness emitted one harmless degenerate-axis plotting warning in a synthetic
fixture; final manuscript LaTeX logs have no warnings or overfull/underfull boxes.

Initial receipts are retained: sandbox tmux visibility and missing PyYAML caused
environmental failures, and a late manuscript edit invalidated a dependent
manifest. The final rerun used read-only host visibility, the existing Python
dependency directory and the refreshed manifest. No scientific assertion was
weakened and no inference/source routine was changed to obtain a pass.

Focused independent v14, DGP-reference, JOINT projection, GloFAS Search III and
RHS checks passed. The global-scale reference check was correctly suite-loaded.
PriceFM's R98 projection pytest passed. The final editorial checker verifies 19
pinned scientific inputs, 216 independent roles and 32 JOINT forecast/fit rows;
its abstract count is 173 words. The DGP figure checker reports 132 checks and
four active vector figures. `git diff --check` passed.

The final protected-file comparison preserves 2,529 of 2,532 files byte for byte.
The three intentional differences are the manuscript/checker hash manifest,
the historical caption and its TeX hash manifest. All numerical CSVs, inference
sources, configurations, scientific tests and figure binaries are unchanged.
No runtime, model objects, logs, local trackers or unrelated lane files are in
the commit surface.

With identical working-manuscript layout, baseline builds were 22 main and 54
supplementary pages; revised builds are 22 and 55 pages. The main is not longer,
and the extra supplementary page records necessary model/application precision.
This is not a claim of an overall length reduction or compliance with an
unverified journal page limit. Main and supplement compile with resolved
citations/references. Supplemental figures now use S-prefixed numbering.

The exact eight-file source surface is:

- `main.tex`
- `qdesn-supplement.tex`
- `refs.bib`
- `scripts/check_qdesn_final_manuscript_revision.R`
- `tables/qdesn_validation_500obs_dgp_oracle_figures_v14_manifest.txt`
- `tables/qdesn_validation_mcmc_five_chain_sensitivity.tex`
- `tables/qdesn_validation_mcmc_five_chain_sensitivity_manifest.txt`
- `docs/implementation_notes/technometrics_advisor_revision_implementation_20261008.md`

The final isolated article-bundle check, merge-parent checks, remote read-backs
and publication state are recorded separately after this source commit is
frozen; their success must not be inferred from this prepublication record.

## Remaining submission decisions

The exact current Technometrics instructions could not be retrieved from
the official author-instructions endpoint. Length/count exclusions, review
blinding, required class/template, keywords and final submission-file rules
remain to be checked before journal submission. Do not label this manuscript
as fully certified for submission on the basis of generic examples.

### Verified figure typography follow-up

Insertion-size inspection found that the six frozen Search III GloFAS vector
figures have small axes/legend text, approximately 3--3.2 points. Their
1120-by-424-point canvas is reduced to article width. The curves, probability
levels, legends and captions remain present, but these labels need a separate
print-legibility correction before journal submission. Other inspected active
figures/tables are readable without clipping. The frozen GloFAS PDFs and their
scientific/publication hashes are preserved in this editorial revision.

Affected assets are the part1, part2, part3, part4, convergence and calibration
PDFs with prefix `glofas_search3_part1234_final_20261007` in
`figures/glofas_application/`.

A complete font-only redraw needs authenticated display inputs. Tracked
`source_quantiles.csv` contains Parts 1, 3 and 4 but not Part 2 or all historical
context/traces. Bounded inspection found historical pins for Normal/history
CSVs and small convergence traces, but no original inventory/hash entries for
the 16 Part 2 quantile forecast RDS inputs. Current-file hashes or completion
timestamps cannot substitute for historical authentication. No model or
forecast RDS was opened, and the scientific closeout builder was not rerun.

Follow-up acceptance: authenticate missing original display inputs, or derive
the presentation directly from the authenticated vector curves; use a bounded
renderer with no fitting/selection/scoring; retain every original curve and
probability/date scale; preserve the old source PDFs; give new presentation
derivatives a separate manifest; verify numerical equality, vector fonts and
final-size legibility in both documents. Do not simply relax existing frozen
hash checks or certify the present font size as journal-ready. This does not
prevent publishing the clearly identified editorial update, but it remains an
open submission-quality gate.

The publisher's public AI policy calls for tool name/version, use and reason.
The article names actual assistance and its purpose. The authors must confirm
the final wording and supply accurate relevant version information before
submission; this revision does not invent historical tool/model versions.

Primary sources used for these decisions:

- https://taylorandfrancis.com/our-policies/ai-policy/
- https://www.tandfonline.com/action/authorSubmission?show=instructions&journalCode=utch20
- https://arxiv.org/abs/2608.11222v2
- https://arxiv.org/html/2508.04875v4
- https://waterdata.usgs.gov/monitoring-location/USGS-11160500/

## Publication gate

Commit and push the editorial branch only after reviewed checks. Fetch latest
main, create a separate integration worktree, and preserve a no-ff merge with
the recorded main and exact editorial commit as its two parents. Recheck the
combined tree. Use only the guarded command-line Git main publisher.

Build and check the article-only projection before the guarded snapshot/direct
Overleaf publisher. Never merge Overleaf back to main, force-push, expose
credentials, or copy runtime objects into the article bundle. Owner confirmation
that legacy automatic synchronization is disconnected is required. Final
remote hashes and read-back results belong in the ignored publication receipt;
a successful fetch alone is not evidence of publication.
