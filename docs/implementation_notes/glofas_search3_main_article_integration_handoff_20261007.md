# GloFAS Search III Part 1-4 Main Article Integration Handoff

Date: 2026-10-07

## Coordinator Role

You are the official integration coordinator for the completed GloFAS Search III
Part 1-4 authority. Integrate the reviewed scientific authority into the latest
main article, supplement, tables, figures, manifests, tests, and Overleaf source
closure. Do not rerun or retune any model. Do not use the protected final window
for model selection. Do not delete runtime evidence during integration.

The scientific computation is complete. The integration task is to project the
frozen evidence into article-safe tracked assets, reconcile the source code onto
the latest main branch, update every manuscript claim that depends on the old
GloFAS authority, and independently prove that the resulting article snapshot is
internally consistent.

## Final Verdict

`READY_FOR_COORDINATOR_INTEGRATION`

The closeout checker was rerun on 2026-10-07 and returned:

```text
GLOFAS_SEARCH3_FINAL_CLOSEOUT_VERIFY_PASS 11/11
READY_FOR_COORDINATOR_INTEGRATION
```

No GloFAS fit, continuation, search worker, or controller remains active. Search
III is complete at `133/133`; the Part 4 source family is complete at `18/18`;
the corrected Joint AL and Joint exAL authorities are strictly converged.

## Nonnegotiable Boundaries

1. Do not launch model fits, continuations, screens, forecasts, or calibration.
2. Do not call any family a protected-window-selected winner.
3. Do not merge the science branch wholesale into main without a path-level
   reconciliation audit. Main and the science branch have substantial parallel
   development.
4. Do not copy RDS objects, logs, status markers, machine-local paths, or ignored
   runtime directories into the article or Overleaf projection.
5. Do not use stale September Part 4 aliases, scores, figures, specifications, or
   convergence language.
6. Do not apply an unregistered quantile-crossing correction.
7. Do not score Part 2 after the cutoff. Retrospective GloFAS ends at the cutoff.
8. Do not treat Part 4 as an ordinary post-fit forecast. It is a latent-path
   issued-ensemble experiment fitted with future USGS hidden.
9. Do not publish to Overleaf until the tracked article projection, manuscript
   builds, source closure, and final checker all pass from the integration branch.
10. Do not remove old tracked versioned assets during this integration unless a
    separate reference and manifest audit proves they are unreferenced. Remove
    them from the active aliases and Overleaf file list instead.

## Authority Coordinates

### Source repository and branch

- Repository: `/data/jaguir26/local/src/Article-Q-DESN---Version-2`
- Science worktree:
  `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_search3_dependency_rebuild_20260928`
- Science branch: `work/glofas-search3-adjacent-tau-recovery-20260930`
- Scientific authority HEAD: `6aa44a71a4914872d6b0bc6a754920e7f805b9d4`
- Closeout implementation commit: `fe2ca22c564bf240f5e566e920edd6c2a824fce1`
- Main HEAD observed during handoff preparation:
  `e721bfddee81269864febea0eca0bbd0c5eba369`
- Observed merge base:
  `757522db0f85815244370ec92a194de132268883`
- Observed divergence at handoff preparation: main-only `44`, science-only `39`.

Always fetch again and record the actual `origin/main` used by integration. The
observed hash above is provenance, not permission to integrate against a stale
main.

### Frozen closeout runtime

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_search3_dependency_rebuild_20260928/local_trackers/runtime_configs/glofas_search3_part1234_final_closeout_20261007
```

This ignored directory is the numerical and graphical source of truth. Keep it
read-only during article integration.

### Closeout artifact hashes

| Artifact | SHA256 |
|---|---|
| `manifests/output_manifest.csv` | `968096fe310b61c4b05423890cad529e7c891e51691cd997ef253753c7c9de9f` |
| `figures/glofas_search3_part1234_final_comparison.pdf` | `799d05536f7331d80ff534f4198e5977c08344d97d8f83167c52b8534e82ae31` |
| `reports/final_closeout_report.md` | `b5f8a82c1fe02a74d2dfc8c3b654361c67bc9a1c01bff32f11d4245aeea33eef` |
| `reports/coordinator_integration_handoff.md` | `a02a663098c41004573992a9d91fd129b134044d978041f580fdbd5b21be416f` |
| Tracked final-closeout handoff | `306f22c7d84de63d97e3a05b51c00853f6130a4758b59560a4286c68867f51c2` |

### Canonical terminal fits

| Family | Fit SHA256 | Stored outer | Parameter change | Maximum RHS change | Consecutive passes |
|---|---|---:|---:|---:|---:|
| Joint AL | `0ac25ad186fa660d7958484db822c0e2c7ce60ae933928498dfd42180e439274` | 11 | `8.9279687e-04` | `7.7748371e-04` | 3 |
| Joint exAL | `0784549437365dc239e123fe0fd660d4212fa0e7a72dc1034765b5ba73e6e823` | 28 | `2.6080582e-04` | `3.8253514e-04` | 3 |

Both pass the outer, inner, RHS, and three-consecutive-full-state release
contract. The exAL repair preserved complete local state across outer sweeps and
removed a diagnostic-only discontinuous indicator from the operative quadrature
stopping norm. It did not change the likelihood, prior, ELBO, or posterior
target.

## Phase 1: Independent Preflight

Perform these checks before editing tracked files.

```bash
set -euo pipefail

REPO=/data/jaguir26/local/src/Article-Q-DESN---Version-2
SRC_WT=/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_search3_dependency_rebuild_20260928
SRC_BRANCH=work/glofas-search3-adjacent-tau-recovery-20260930
SCIENCE_HEAD=6aa44a71a4914872d6b0bc6a754920e7f805b9d4
RUNTIME="$SRC_WT/local_trackers/runtime_configs/glofas_search3_part1234_final_closeout_20261007"

git -C "$REPO" fetch origin --prune
git -C "$SRC_WT" merge-base --is-ancestor "$SCIENCE_HEAD" HEAD
test -z "$(git -C "$SRC_WT" status --porcelain)"

sha256sum "$RUNTIME/manifests/output_manifest.csv"
sha256sum "$RUNTIME/figures/glofas_search3_part1234_final_comparison.pdf"
sha256sum "$RUNTIME/reports/final_closeout_report.md"
sha256sum "$RUNTIME/reports/coordinator_integration_handoff.md"

cd "$SRC_WT"
Rscript application/scripts/446_check_glofas_search3_final_closeout.R \
  --runtime_root "$RUNTIME"
```

Require the two terminal lines shown in the verdict. Stop if any source hash,
fit hash, manifest row, family score, selection identity, PDF property, or
authority ledger check fails.

Also record read-only process health. An active GloFAS process at this stage is
an unexpected state that must be investigated before integration; do not stop it
automatically.

## Phase 2: Create a Fresh Integration Worktree

Do not use a dirty main checkout and do not update article files in the science
worktree.

```bash
set -euo pipefail

REPO=/data/jaguir26/local/src/Article-Q-DESN---Version-2
INT_WT=/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_search3_article_integration_20261007
INT_BRANCH=work/glofas-search3-article-integration-20261007

git -C "$REPO" fetch origin --prune
git -C "$REPO" worktree add -b "$INT_BRANCH" "$INT_WT" origin/main

git -C "$INT_WT" status --short --branch
git -C "$INT_WT" rev-parse HEAD
git -C "$INT_WT" rev-parse origin/main
```

If the branch or worktree already exists, inspect it rather than overwriting it.
The integration branch must begin clean and exactly at the freshly fetched main
head.

## Phase 3: Reconcile the Scientific Source Surface

Excluding this documentation-only integration handoff, the observed science
delta at `6aa44a7` contains `133` paths: `102` additions and `31`
modifications. It spans `28` `application/R` paths, `4` configuration paths,
`57` scripts, `2` C++ files, `37` tests, and `5` documentation paths. At the
observed heads, only these four paths were modified on both branches:

```text
application/R/README.md
application/scripts/README.md
application/tests/README.md
application/tests/run_tests.R
```

Recompute that overlap after the fresh fetch. Do not assume it is still four.

### Required reconciliation algorithm

1. Compute the merge base between fresh `origin/main` and the source branch.
2. Create a machine-readable inventory of every added, modified, renamed, or
   deleted source-side path.
3. Create the equivalent main-side inventory.
4. Classify each source path as source-only, both-sides, deleted, or unresolved.
5. Import source-only additions exactly from the source commit.
6. Apply source-only modifications with three-way ancestry preserved.
7. Manually reconcile every both-sides path, preserving current-main entries and
   adding all Search II, Search III, continuation, closeout, and regression-test
   registrations.
8. Treat a source-side deletion as a stop condition requiring explicit review.
9. Write a tracked integration manifest containing path, source status, source
   blob hash, integration blob hash, and merge disposition.
10. Require every imported source blob either to match the source branch exactly
    or to carry a documented manual-merge disposition.

Use a path-scoped integration, not an unreviewed branch merge. The required
scientific surface includes the GloFAS Search II/III modules, fixed Dec-25
workflow, recursive forecast operators, Part 4 latent-path modules, joint
continuation repairs, C++ recursion, launch/check scripts, frozen fold files,
tests, and closeout builder/checker. It does not include ignored runtime output.

Current high-risk shared implementations that require direct review include:

```text
application/R/joint_exqdesn_exact_structured_inference.R
application/R/latent_path_vb_al.R
application/R/latent_path_vb_exal.R
application/R/latent_path_vb_joint.R
application/scripts/381_run_glofas_dec25_final_refit_job.R
application/scripts/386_run_glofas_part4_latent_family_job.R
application/scripts/389_continue_glofas_part4_joint_fit.R
application/src/glofas_oracle_desn_forecast.cpp
application/tests/test_joint_exqdesn_exact_structured_inference.R
```

The integration must preserve unrelated JOINT simulation and PriceFM work from
current main. Never resolve a conflict by replacing the entire main-side file
with the science-branch version.

### Source integration test gate

Before article projection, run at minimum:

```bash
Rscript application/tests/test_glofas_search3_final_closeout.R
Rscript application/tests/test_glofas_part4_exal_inner_audit.R
Rscript application/tests/test_glofas_part4_latent_family.R
Rscript application/tests/test_joint_exqdesn_exact_structured_inference.R
python3 application/tests/test_glofas_part4_joint_release_controller.py
python3 application/tests/test_glofas_search3_dependency_closure.py
Rscript application/tests/run_tests.R
```

If the full application test suite is too long for one interactive command, run
it in a logged foreground or managed session and do not proceed until its exit
status is known. Do not weaken a test to make integration pass.

## Phase 4: Build a Deterministic Article Projection

Do not copy runtime CSVs directly into `tables/`. Several contain absolute paths
and operational fields. Add a new tracked builder, independent checker, focused
test, and implementation note following the established GloFAS and PriceFM
projection patterns. Allocate the next free script numbers on fresh main; do not
overwrite an existing script number.

Recommended article tag:

```text
glofas_search3_part1234_final_20261007
```

### Builder contract

The builder must:

1. Accept the closeout runtime as an explicit argument.
2. Run or reproduce all 11 closeout gates before generating anything.
3. Verify the expected output-manifest hash and canonical terminal-fit hashes.
4. Write to a temporary staging directory first.
5. Generate article-safe CSV, TeX, and PDF derivatives deterministically.
6. Strip absolute paths, hostnames, tmux/session data, ignored-runtime paths,
   RDS references, and logs from public assets.
7. Preserve full numeric precision in CSVs and format only TeX display values.
8. Atomically replace all four stable GloFAS aliases only after every staged
   artifact passes its checker.
9. Write a publication manifest with repository-relative paths, file sizes,
   SHA256 hashes, source-role hashes, Git inclusion, and Overleaf inclusion.
10. Be idempotent: rebuilding from unchanged authority must reproduce identical
    hashes.

### Required versioned tables

Create article-safe versioned derivatives for at least:

- Part 1 and Part 3 family scores, with the Part 2 no-score boundary stated;
- Part 4 seven-family common-grid scores;
- Part 4 level-specific calibration;
- selected Search III reference and discrepancy specifications;
- corrected Joint AL and Joint exAL convergence;
- an authority and supersession summary with no machine-local paths;
- an interpretation/decision ledger that distinguishes internal selection from
  protected-window descriptive ranking.

The main Part 4 score table should report:

```text
family, mean check loss, grid aCRPS, 90% coverage,
aCRPS reduction versus raw GloFAS, numerical status
```

Do not carry forward the old interval-score column unless it is recomputed by a
new deterministic, independently checked method for all seven current families.
Do not splice old interval scores into the new comparison.

The supplement should contain a compact Part 1/Part 3 comparison table and an
explicit Part 2 row or note that the post-cutoff discrepancy paths are unscored.

### Required figures

The reviewed comprehensive source PDF is six-page, vector-only, and ordered as:

1. Part 1 univariate USGS recursive forecast;
2. Part 2 retrospective-GloFAS discrepancy recursive path, unscored;
3. Part 3 joint historical USGS recursive forecast;
4. Part 4 issued-ensemble latent-path experiment;
5. corrected Part 4 joint-model convergence;
6. Part 4 issued-window quantile calibration.

Create deterministic single-page vector derivatives for article inclusion. A
page extraction is acceptable only if page count, bounding boxes, fonts, text,
and absence of embedded raster images are independently checked. Suggested
article roles are:

- main article: Part 4 family comparison;
- supplement: Parts 1, 2, and 3 comparisons;
- supplement: corrected joint convergence;
- supplement: Part 4 calibration.

Keep the six-page comprehensive PDF as a tracked reviewed diagnostic only if the
publication manifest marks its role clearly. Do not make the manuscript depend
on a machine-local PDF.

### Stable aliases that must move atomically

```text
tables/glofas_application_current_outputs.tex
tables/glofas_application_current_score_summary.csv
tables/glofas_application_current_score_summary.tex
tables/glofas_application_current_selection_manifest.csv
```

Preserve existing macro names needed by the manuscript where sensible, but
replace stale values and add explicit macros for the Search III selection,
descriptive Part 4 leader, corrected joint statuses, Part 1-3 scopes, and Part 2
no-score boundary. The stable selection manifest must point only to new
article-safe tracked assets and reproduce all hashes.

## Phase 5: Scientific Content to Integrate

### Fixed common contract

- response scale: `log(1 + flow)`;
- cutoff and forecast origin: `2022-12-25`;
- seven quantiles: `0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95`;
- future USGS truth: excluded from fitting, scoring only;
- future PRISM/ERA5 precipitation and soil moisture: realized oracle covariates;
- crossing correction: none;
- application inference: VB; no GloFAS MCMC fit is reported;
- Parts 1-3: 30-day recursive paths;
- Part 4: 28 issued GloFAS horizons, 51 members per horizon, each weighted
  `1/51`.

### Four application components

1. **Part 1, reference process.** Univariate USGS model and 30-day recursive
   forecast using the internally selected reference DESN.
2. **Part 2, discrepancy process.** Retrospective GloFAS-minus-USGS discrepancy
   model and 30-day recursive path using the internally selected discrepancy
   DESN. The post-cutoff path is not scoreable because retrospective GloFAS ends
   at the cutoff.
3. **Part 3, joint historical process.** Reference and discrepancy components
   combined in a 30-day recursive USGS forecast.
4. **Part 4, issued-ensemble latent path.** Unknown future USGS values are latent
   during fitting; issued GloFAS members contribute through the weighted
   ensemble likelihood for 28 horizons. This is not an ordinary post-fit
   forecast stage.

### Frozen Search III specifications

| Component | Candidate | Decision | Geometry |
|---|---|---|---|
| Reference | `search3_ref_001` | retain Search II incumbent | `D=1`, `n=1500`, output lags `m=540`, covariate lags `mx=90`, `alpha=0.75`, `rho=0.60`, `m0=40`, seed `20260512` |
| Discrepancy | `search3_dis_007` | adopt Search III rainy-season challenger | `D=1`, `n=1000`, output lags `m=180`, covariate lags `mx=180`, `alpha=0.85`, `rho=0.20`, `m0=60`, fixed `zeta2=16`, seed `20261521` |

Selection used internal rainy-season training evidence across frozen folds and
seeds. The protected December 2022 to January 2023 window was not used to select
reservoirs, priors, stopping rules, or model families.

Do not infer or copy old `tau0` values. Derive every reported prior or learned
scale from the executed Search III and Part 4 manifests and canonical fits.
Distinguish a fixed prior hyperparameter from a learned posterior scale. If the
current families use model-specific values, report that rather than inventing a
single shared value.

### Part 1 and Part 3 scores

| Part | Family | Grid aCRPS | 90% coverage | Crossing pairs |
|---|---|---:|---:|---:|
| Part 1 | Normal Ridge | `0.4135195` | `0.4333` | 0 |
| Part 1 | Normal RHS/VB | `0.4124461` | `0.5000` | 0 |
| Part 1 | Independent AL | `0.5028073` | `0.6000` | 3 |
| Part 1 | Independent exAL | `0.5887606` | `0.6000` | 1 |
| Part 1 | Joint AL | `0.4975837` | `0.7000` | 0 |
| Part 1 | Joint exAL | `0.5808675` | `0.6000` | 0 |
| Part 3 | Normal Ridge | `0.5242387` | `0.4000` | 0 |
| Part 3 | Normal RHS/VB | `0.5268873` | `0.4333` | 0 |
| Part 3 | Independent AL | `0.6251856` | `0.6333` | 0 |
| Part 3 | Independent exAL | `0.7069375` | `0.5000` | 0 |
| Part 3 | Joint AL | `0.6457069` | `0.6333` | 0 |
| Part 3 | Joint exAL | `0.7556569` | `0.4333` | 0 |

Use the source CSV for full precision. The table above is a claim guide, not a
replacement for the authority table.

### Part 4 descriptive issued-window comparison

| Rank | Family | Mean check loss | Grid aCRPS | 90% coverage | Reduction vs raw |
|---:|---|---:|---:|---:|---:|
| 1 | Independent AL | `0.3595153` | `0.7156034` | `0.7500` | `50.17%` |
| 2 | Independent exAL | `0.4226710` | `0.8265749` | `0.5357` | `42.44%` |
| 3 | Normal Ridge | `0.4531275` | `0.8471424` | `0.1071` | `41.01%` |
| 4 | Joint AL | `0.4717985` | `0.9490480` | `0.7857` | `33.91%` |
| 5 | Joint exAL | `0.6037158` | `1.1765488` | `0.2857` | `18.07%` |
| 6 | Raw GloFAS | `0.7713120` | `1.4359771` | `0.0000` | `0.00%` |
| 7 | Normal RHS/VB | `0.8038357` | `1.4789848` | `0.1071` | `-3.00%` |

The article may say that Independent AL is the descriptive issued-window leader.
It may not say that Independent AL was selected on the protected window. Joint
AL is the corrected joint comparator; Joint exAL is the corrected sensitivity
model. Numerical certification does not imply competitive calibration.

### Required limitations

- Part 1 Independent AL has three adjacent-quantile crossing pairs; Part 1
  Independent exAL has one. Part 1 Joint AL, Part 1 Joint exAL, and all Part 3
  families have zero.
- Part 2 post-cutoff paths are forecast products without a future discrepancy
  score.
- Part 4 shows material upper-tail undercoverage. Joint exAL has `q0.95`
  empirical coverage `0.2857`; Independent AL has `q0.95` coverage `0.75`.
- One origin and oracle future covariates do not establish operational forecast
  performance.
- The 30-day Parts 1-3 scope and 28-horizon Part 4 scope must remain distinct.

## Phase 6: Rewrite the Main Article Coherently

Update `main.tex` as one coherent GloFAS revision, not scattered substitutions.

1. Introduce the four-part framework and explain why Parts 1 and 2 supply the
   fixed reference and discrepancy DESN specifications used downstream.
2. State the internal Search III selection protocol and protected-window
   firewall before presenting final-window results.
3. Preserve the Part 4 latent-path likelihood description, `1/51` ensemble
   weights, future-truth exclusion, and oracle-covariate qualification.
4. Replace the old selected-Joint-AL paragraph with the complete seven-family
   descriptive comparison.
5. Report corrected Joint AL and Joint exAL as strictly converged.
6. Discuss score and calibration together. In particular, explain that the best
   aCRPS does not provide nominal 90% coverage and that Joint exAL remains weak
   in the upper tail.
7. Add a concise Part 1-3 summary and direct the reader to supplement tables and
   figures for complete results.
8. Replace the old figure with the new Part 4 page and write a caption that
   describes only elements actually present in that page.
9. Update the discussion and conclusion so they no longer state that Joint AL
   was selected, cap-stabilized, or near-nominally calibrated.
10. Preserve the single-origin retrospective interpretation and avoid causal or
    operational claims.

The main text should prioritize the Part 4 comparison and methodology. Full
Part 1-3 family tables, convergence detail, and calibration belong in the
supplement to avoid overloading the article.

## Phase 7: Rewrite the Supplement Completely Where Needed

Update `qdesn-supplement.tex` to:

1. describe all four parts and their different evaluation scopes;
2. replace the old `n=3000` reference and `n=2500` discrepancy geometries with
   the frozen Search III specifications;
3. derive and report the executed prior/scale settings from frozen manifests,
   not old aliases;
4. document the rainy-season Search III selection and protected-window firewall;
5. retain the weighted augmented-likelihood qualification;
6. report the corrected full-state convergence contract and terminal metrics;
7. explain the exAL computational root cause without implying a change to the
   posterior target;
8. include Part 1-3 score evidence, Part 2 no-score status, Part 4 calibration,
   and all relevant single-page figures;
9. disclose Part 1 crossings without applying a correction;
10. remove the old statements that the selected application result is Joint AL,
    that Joint exAL failed qualification, or that the terminal Joint AL fit did
    not satisfy strict convergence.

## Phase 8: Remove Stale Active Authority

The latest main observed during handoff still points to the September authority
`glofas_part4_joint_al_sweep10_20260911`. Its active aliases contain obsolete
claims, including:

```text
Joint AL selected
aCRPS 0.8374
parameter change 0.0041539
cap-stabilized / not strictly outer-converged
reference D1 n3000 m360 alpha0.5 rho0.9
discrepancy D1 n2500 m360 alpha0.8 rho0.7
reference tau0 1 and discrepancy tau0 0.001
near-nominal 0.929 coverage
```

After building the new projection, search all tracked article surfaces for these
stale identifiers and prose fragments. Every remaining occurrence must be
either removed, clearly historical in an implementation note, or explicitly
excluded from the Overleaf source closure.

At minimum audit:

```bash
rg -n \
  'glofas_part4_joint_al_sweep10_20260911|0\.8374|0\.004153|cap-stabilized|not strictly outer-converged|selected Joint AL|near-nominal' \
  main.tex qdesn-supplement.tex tables figures overleaf scripts application
```

Do not delete old versioned assets merely to make this search empty. The pass
criterion is that no active alias, manuscript include, current manifest, or
Overleaf-listed file uses them.

## Phase 9: Update Global Article Contracts

### Final manuscript checker

`scripts/check_qdesn_final_manuscript_revision.R` currently hard-codes the old
GloFAS score-summary and selection-manifest hashes. Update those expected hashes
only after the new deterministic projection is final. Add checks for:

- the Search III article tag;
- `search3_ref_001` and `search3_dis_007`;
- the seven-family Part 4 table;
- strict convergence for both joint fits;
- the Part 2 no-score boundary;
- the 28-versus-30-horizon distinction;
- forbidden stale authority tokens;
- article-safe paths only.

### Overleaf source closure

Update `overleaf/article_files.txt` as an exact, sorted dependency closure.
Remove the active old sweep-10 GloFAS entries and add only the new versioned
tables, single-page figures, stable aliases, and any caption/protocol fragments
actually included by the article or supplement.

Run `scripts/build_arxiv_source_bundle.sh` and compile both manuscripts from the
resulting clean bundle. This catches accidental dependencies on ignored runtime
files or unlisted local assets.

## Phase 10: Validation Matrix

All gates below are required.

### Numerical and provenance gates

- closeout checker: `11/11`;
- output manifest hash equals the frozen hash;
- canonical terminal fit hashes reproduce;
- Search III component identities reproduce;
- no protected-window quantity is used in a selection field;
- article projection rebuild is hash-idempotent;
- publication manifest contains no absolute path.

### Table and figure gates

- seven Part 4 families and exactly 28 scored horizons;
- 18 Part 1-3 family rows, with Part 2 scores missing by design;
- 49 Part 4 family-by-quantile calibration rows;
- both joint convergence rows pass all strict gates;
- six source-PDF pages and six expected article roles;
- every article PDF is one page, vector-only, nonblank, and correctly cropped;
- CSV values agree with runtime sources at full precision;
- displayed TeX rounding is reproducible and internally consistent.

### Manuscript gates

- `main.tex` compiles from a clean tree;
- `qdesn-supplement.tex` compiles from a clean tree;
- labels and references resolve;
- no table exceeds the text width;
- no figure is clipped or blank;
- captions and alt text match the actual graphics;
- no stale sweep-10 claim remains active;
- no absolute path appears in tracked article assets;
- `scripts/check_qdesn_final_manuscript_revision.R` passes;
- the arXiv/Overleaf source bundle compiles independently.

Use the repository build instructions:

```bash
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex

pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
bibtex qdesn-supplement
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
```

Also run `git diff --check`, inspect `git status`, and perform visual PDF review
of every changed article page.

## Phase 11: Commit and Promotion Sequence

Use small auditable commits in this order:

1. reconcile GloFAS source code and tests onto fresh main;
2. add the deterministic article-projection builder, checker, test, and note;
3. generate and verify versioned article-safe tables and figures;
4. atomically switch current aliases and update the Overleaf closure;
5. update main and supplement scientific text;
6. update global hash contracts and complete full validation;
7. add the final integration report and promotion manifest.

Push the integration branch. Do not force-push. Request coordinator review of
the final diff against the fresh main base. Merge or promote only after all
gates pass. After main integration, rerun the projection checker, final
manuscript checker, both LaTeX builds, and source-bundle compilation from the
actual integrated main commit before updating Overleaf.

## Required Final Coordinator Report

Report a compact table with:

- fresh main base and final integration commit;
- source branch and source HEAD;
- closeout checker result;
- source-path inventory and conflict dispositions;
- article projection manifest path and hash;
- stable alias hashes;
- main/supplement build status and page counts;
- final manuscript checker status;
- Overleaf source-closure status;
- stale-authority audit status;
- any remaining scientific limitation;
- exact paths to final tables and figures.

End with exactly one of:

```text
GLOFAS_SEARCH3_ARTICLE_INTEGRATION_PASS
READY_FOR_MAIN_PROMOTION
```

or, if any gate is unresolved:

```text
GLOFAS_SEARCH3_ARTICLE_INTEGRATION_BLOCKED
```

Do not emit `READY_FOR_MAIN_PROMOTION` unless the integrated tracked branch,
article projection, manuscript PDFs, and clean source bundle all pass.

## Coordinator Interpretation Summary

The integration is a promotion of complete evidence, not a promotion of one
model chosen on the final window. Search III retained the reference reservoir
and adopted a rainy-season discrepancy challenger using internal training
evidence. The final issued window then showed that Independent AL had the lowest
Part 4 grid aCRPS, while corrected Joint AL offered the best 90% coverage among
the modeled Part 4 families. Corrected Joint exAL is numerically valid but
scientifically weak in the upper tail. Parts 1 and 3 provide separate recursive
forecast evidence, and Part 2 provides an unscored discrepancy path. That full,
qualified story is the article authority.
