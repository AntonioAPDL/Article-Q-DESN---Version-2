# Sections 1–4 reader audit and MQ–DESN display revision

## Scope and authority

The editorial source is `origin/main` at
`a5fe5ad258b6563aac14020cec0e34eaa757187f`. The dedicated branch is
`work/qdesn-sections1-4-reader-flow-20261013`. The author authorized both a
sentence-by-sentence reader audit of the first four main sections and the
publication-wide MQ–DESN rename, including tables and figures.

The audit follows the repository's academic-writing profile and the author's
Wikle-style preferences: place the statistical question before its machinery,
define unfamiliar terms where needed, connect sentences only when the logical
relation benefits from an explicit connection, and preserve concise passages
that already read naturally. No universal connecting phrase or blanket rewrite
is warranted. The deeper sentence ledgers are retained in the ignored
`local_trackers/editorial_revision/` directory of the source worktree.

## Reader audit and corrections

| Location | Correction | Reason |
|---|---|---|
| Abstract and introduction | Define MQ–DESN as the multiquantile deep echo state network; identify PriceFM's role in the abstract | Both summaries must stand alone without introducing unexplained model names |
| Introduction | Define a forecast origin and the final regression layer, or readout | Later quantile and computation statements refer to these quantities |
| Introduction | Group the hydrologic reference with the two ordering-method references; retain the concise noncrossing qualification | Avoid a detached literature sentence without overstating adjacent-difference shrinkage |
| Section 2.1 | State the fitting index and predictor dimension; identify the bounded interval as the shape parameter's interval | Avoid confusion with response support and distinguish coefficients from predictors |
| Section 2.2 | Introduce the number of layers, response lags, componentwise activation, feature transformation, reducer dimensions and washout meaning | The recursion becomes readable without requiring the supplement first |
| Section 2.3 | Define the ridge prior standard deviation and the penalized slope index; distinguish fixed hyperprior scale from random global scale | Prior calibration is not a numerical warm start; the product hierarchy is not silently replaced by another RHS construction |
| Section 2.3 | State the coefficient-variance bound as the squared slab scale | The effective variance is at most the slab scale squared |
| Section 2.4 | Identify the multiquantile coefficient vectors as slope-only vectors; define the response vector, prior and level-specific scale/shape | Separate notation for the regression intercept is explicit |
| Section 2.4 | Preserve the proportional composite posterior and the nonnormalized repeated-response interpretation | The model target and its statistical qualifications are unchanged |
| Section 3 | Connect to the specified composite target; define positive-truncated Normal variables and distinguish their support from the signed latent shift | The augmentation should not imply that the whole shape shift is positive |
| Section 3 | State updates for squared scales and auxiliaries, retaining the structured scale–shape distinction | Avoid conflating conjugate blocks with the nonconjugate exAL block |
| Section 4.1 | Distinguish a rolling forecast origin from the fitting endpoint; define probability level and draw index | Forecasting locations and marginal predictive quantiles remain distinct |
| Section 4.2 | Define check-loss error/indicator, CRPS, the finite-grid approximation and its grid-size condition | A single quantile regression is valid, but trapezoidal grid scoring requires at least two levels |
| Section 4.2 | Expand DGP and identify the origin history, evaluation pairs and adjusted forecast in the oracle score | The expected-loss integral and displayed uncertainty are interpretable without internal implementation terminology |
| Section 4.3 | Explain Gaussian-DESN screening as inexpensive mean regression; name all four shared-design comparisons | The selected feature map is common to Q–DESN and MQ–DESN under AL and exAL |
| Section 4.3 | Define the echo state property in terms of loss of initialization effects under common input history | Distinguish feature diagnostics from a universal stability guarantee |
| Supplementary initialization figure | Use the existing median index consistently and rename the right-hand model boxes | Avoid reusing the response-lag count as the quantile median index |

The recent approved transitions explaining the fixed-feature regression,
regularization, AL computation, variational inference, direct interval
estimation, and linear-dynamics comparison remain. Equations retain the
author's compact left-hand descriptions. No findings placeholders are filled.

## Naming policy and reproducibility

Q–DESN denotes the independent quantile regression. MQ–DESN denotes the
multiquantile regression; AL and exAL remain likelihood qualifiers. Neither
`exMQ–DESN` nor an ambiguous additional “joint” prefix is introduced.

The twelve-row public display registry maps existing simulation model IDs and
GloFAS family keys to these labels. The frozen scientific identifiers and
filenames remain unchanged. Ordinary statistical uses of “joint” are retained,
including joint priors, posteriors, latent scale–shape blocks and GloFAS's
historical reference–discrepancy construction. PriceFM remains independent-only.

The two multiquantile simulation PDFs and six GloFAS PDFs are presentation
derivatives, not replacement scientific results. Original PDFs, tables, CSVs,
manifests, renderers and numerical values remain intact. The table and legend
mapping is verified against the original sources, with numerical tokens and
model ordering preserved. The historical Phase153 table is explicitly labelled
historical rather than represented as evidence for the current corrected target.

The effective publication graph selects the new derivative assets. The sorted
article allowlist removes superseded display copies from the upload, not from
Git. This prevents stale names from being mistaken for current output in
Overleaf. Main forecast figures and supplementary fitting figures retain their
existing placement. The common-window main GloFAS Figure 4 is unchanged.

## Verification and publication procedure

Run under pinned R 4.6.0 and Python 3.11:

1. Reader-focused editorial, bibliography/initialization and supplementary
   mathematics tests, then the full editorial/scientific-invariance checker.
2. Independent v14 and current multiquantile v2 article checks; GloFAS Search
   III authority check. Keep the scientific hashes unchanged.
3. Deterministic MQ presentation rebuild checks, the effective-name checker,
   and isolated mutation tests, including swapped AL/exAL or independent/MQ
   labels and stale alias inputs.
4. Regenerate and check the article dependency inventory after all edits.
5. Build identified and anonymous main/supplement proofs; check final logs,
   anonymization, cross-references and enlarged figure/TikZ views.
6. Check Git scope and whitespace; forbid model-source, cache, runtime, posterior
   draw, original frozen display, numerical summary and bibliography changes.
7. Commit and push this source branch. Integrate by a two-parent `--no-ff`
   merge in a fresh integration worktree based on freshly fetched main. Repeat
   the release checks there before the guarded main push and remote readback.
8. Materialize and compile the article-only source bundle. Publish through the
   existing guarded one-way Git snapshot workflow only; verify both snapshot
   refs and trees before declaring Overleaf updated. Authentication failure
   leaves publication pending, with a pinned interactive Git command supplied
   to the author. Tokens are entered only at Git's password prompt.

No fitting, selection, scoring, retuning, scientific campaign, Jerez transfer or
runtime cleanup is part of this revision. Passing these editorial gates does
not settle any separate historical-fixture or journal-submission requirement.
Release receipts record the actually executed checks, not unexecuted claims.

### Executed source-tree checks

All three bounded display rebuilds pass. The MQ consistency tests pass eleven
cases; the GloFAS overlay tests pass seven and the historical overlay tests
pass four. The current v2 multiquantile projection checker passes 530 checks
and rejects all nineteen expected mutations. The reader-focused test passes
47 assertions; bibliography/initialization, all 29 supplementary mathematics
checks, GloFAS Search III projection and all five preceding presentation tests
pass. The final manuscript checker retains all nineteen immutable scientific
input hashes. The dependency inventory covers 100 allowlisted files.

Identified main and supplement proofs compile to 36 and 84 pages; anonymous
proofs to 34 and 83 pages. Final logs are clean and anonymization passes.
The MQ forecast figure, full-family GloFAS figure and initialization diagram
were enlarged and visually inspected. The diagram uses the same median index
as the accompanying mathematical description. These are manuscript proofs,
not a claim of complete journal-submission readiness.

The two independent v14 source-worktree integration tests report explicit
skips because their frozen validation fixture is unavailable in this isolated
article worktree. Their inputs and original graphics are unchanged and remain
hash checked. No skip is counted as a scientific test pass. The full scientific
repository suite is not claimed to have passed by this editorial revision.
The subsequent combined-tree release receipt records integration and
publication checks separately.
