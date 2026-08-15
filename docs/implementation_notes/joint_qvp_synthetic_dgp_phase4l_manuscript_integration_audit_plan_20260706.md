# Joint-QVP Synthetic DGP Phase 4l Manuscript Integration Audit And Plan

Date: 2026-07-06

## Executive Recommendation

Move next to a manuscript-integration and reproducibility-closeout stage, not
to another validation launch.

The Phase 4k article-candidate freeze is complete, storage-light,
hash-backed, and ready for manuscript consumption.  The remaining work is to
integrate the frozen joint multi-quantile synthetic DGP validation into
`main.tex` with conservative language, verified table/figure wiring, and a
final reproducibility closeout.

The optimal path is:

1. keep the current TT500 section as the single-quantile benchmark and legacy
   comparison evidence;
2. add a distinct joint-QVP multi-quantile synthetic DGP validation subsection
   that consumes Phase 4k assets;
3. state the raw/contract quantile policy explicitly;
4. compile and visually audit the manuscript;
5. commit only the Phase 4k/Phase 4l joint-QVP work, leaving TT500, GloFAS,
   PriceFM, and unrelated dirty files untouched unless explicitly requested.

This is preferable to rerunning calibration because the computation is already
verified, the selected arm is frozen, and more tuning after the article
candidate launch would risk turning validation evidence into a selection
oracle.

## Evidence Audited

Primary freeze directory:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704
```

Article asset audit directory:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704/phase4k_article_asset_audit
```

Article assets:

```text
tables/joint_qvp_synthetic_dgp_phase4k_*.tex
tables/joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv
figures/joint_qvp_synthetic_dgp/phase4k_*.png
```

Manuscript section inspected:

```text
main.tex, Section "Simulation Validation Study"
```

The current simulation section still consumes the finalized TT500 handoff via:

```tex
\input{tables/qdesn_validation_tt500_final_tables.tex}
```

No Phase 4k table or figure is currently included by `main.tex`.

## Current Health Summary

| Area | Status | Evidence | Diagnosis |
|---|---:|---|---|
| Freeze status | ready | `freeze_decision_summary.csv` | Selected arm is frozen without duplicate compute. |
| Freeze gate | review | raw crossings remain diagnostic evidence | Not an implementation blocker. |
| Selected arm | pass | `tau0_0p15_comparator`, `tau0 = 0.15` | Matches Phase 4j promotion decision. |
| Source manifests | pass | 17, 12, 21, and 9 source-manifest rows verified | Launch, fixtures, selected Phase 3 arm, and audit are reproducible. |
| Freeze manifest | pass | 17 rows, all hashes verified | Freeze is reproducible. |
| Asset manifest | pass | 12 assets, all hashes verified | 7 tables and 5 figures are article-ready artifacts. |
| Contract crossings | pass | selected contract crossing pairs = 0 | Scored forecast quantiles satisfy the declared noncrossing contract. |
| Raw crossings | review | selected raw crossing pairs = 27 | Must be disclosed as diagnostic evidence. |
| Scenario gates | review | 63 pass, 27 review, 0 fail | Reviews are statistical/diagnostic, not implementation defects. |
| Truth-distance gates | pass | 90 pass, 0 review/fail | Forecast quantiles are finite and within calibrated truth-distance gates. |
| Objective gates | pass | 90 pass, 0 review/fail | No objective-status blocker. |
| VB convergence | review/pass | max-iteration rate 0.03783784 | Low enough for article-candidate freeze, worth reporting. |
| Manuscript wiring | incomplete | Phase 4k assets not included | This is now the main work. |

## Key Numerical Evidence To Preserve

Selected arm:

| Metric | Value |
|---|---:|
| arm | `tau0_0p15_comparator` |
| selected `tau0` | 0.15 |
| replicated scenario rows | 90 |
| forecast origins | 9000 |
| tau grid size | 7 |
| raw crossing pairs | 27 |
| contract crossing pairs | 0 |
| mean truth MAE | 0.09218461 |
| mean truth RMSE | 0.1219993 |
| mean pinball loss | 0.1595253 |
| mean WIS | 0.3190506 |
| mean CRPS-grid score | 0.3641354 |
| mean absolute hit-rate error | 0.0342381 |
| maximum absolute hit-rate error | 0.29 |
| VB refits | 370 |
| VB max-iteration count | 14 |
| VB max-iteration rate | 0.03783784 |
| total runtime seconds | 19872.53 |
| scenario pass/review/fail | 63 / 27 / 0 |

Truth-distance by tau:

| tau | mean MAE to truth | mean RMSE to truth | Diagnosis |
|---:|---:|---:|---|
| 0.05 | 0.11067081 | 0.14285643 | Lower-tail stress visible. |
| 0.10 | 0.09085312 | 0.12056190 | Lower-tail error remains moderate. |
| 0.25 | 0.06757311 | 0.09286783 | Interior quantile performance is strong. |
| 0.50 | 0.06295655 | 0.08739994 | Central quantile is strongest. |
| 0.75 | 0.07687870 | 0.10429989 | Upper-interior performance is stable. |
| 0.90 | 0.10591678 | 0.13836807 | Upper-tail stress visible. |
| 0.95 | 0.13044323 | 0.16764122 | Hardest tau level. |

Scenario difficulty:

| Base scenario | mean MAE to truth | mean RMSE to truth | Diagnosis |
|---|---:|---:|---|
| `regime_shift` | 0.27355016 | 0.40697304 | Dominant stress-case limitation. |
| `nonlinear_reservoir_friendly` | 0.09156222 | 0.11434902 | Moderate stress. |
| `heteroskedastic_seasonal` | 0.08917001 | 0.11273812 | Moderate stress and some lower-tail raw adjustment. |
| `persistent_heavy_tail` | 0.06675889 | 0.08278668 | Mostly stable, isolated upper-tail raw crossing. |
| `laplace_bridge` | 0.06437554 | 0.07998851 | Bridge family is stable, with lower-tail raw crossings. |
| `asymmetric_laplace_tail` | 0.06389892 | 0.07942851 | Stable after earlier tail calibration work. |
| `gaussian_mixture_bridge` | 0.06303507 | 0.07814450 | Stable bridge. |
| `student_t_location_scale` | 0.05899391 | 0.07298333 | Strong despite a few upper-tail raw crossings. |
| `normal_bridge` | 0.05831682 | 0.07060222 | Easiest bridge scenario. |

Raw monotone adjustments:

| Base scenario | Tau pair | Raw crossing pairs | Max adjustment | Diagnosis |
|---|---:|---:|---:|---|
| `regime_shift` | 0.05-0.10 | 15 | 0.09045602 | Main raw crossing source. |
| `laplace_bridge` | 0.05-0.10 | 6 | 0.10945428 | Lower-tail bridge sensitivity. |
| `student_t_location_scale` | 0.90-0.95 | 3 | 0.02941557 | Upper-tail heavy-tail sensitivity. |
| `heteroskedastic_seasonal` | 0.05-0.10 | 2 | 0.12190176 | Largest selected-arm raw adjustment. |
| `persistent_heavy_tail` | 0.90-0.95 | 1 | 0.01986053 | Isolated upper-tail sensitivity. |

## Diagnosis Of Each Forward Step

### 1. Lock the validation evidence

Status: done, but should be rechecked before manuscript editing.

The freeze is already created and hash-verified.  The selected Phase 3 arm is
not copied into the freeze because the freeze is storage-light by design; large
files are referenced by path and SHA-256 in `freeze_large_file_registry.csv`.

This is the right design because it avoids duplicating large forecast CSVs
while preserving reproducibility.  The only time to rerun Phase 4k is if any
source artifact changes or the selected-arm source path becomes unavailable.

### 2. Decide whether to replace or extend the TT500 simulation section

Recommended decision: extend, do not replace.

The current TT500 section answers a different and still useful question:
single-target quantile benchmark comparison against DQLM/exDQLM and Q--DESN
variants.  The Phase 4k evidence answers the newer joint multi-quantile QVP
question: registry-driven DGPs, seven tau levels, forecast-origin validation,
monotone contract scoring, and raw crossing diagnostics.

Replacing TT500 entirely would discard comparison evidence that the manuscript
already explains.  Adding a distinct subsection is cleaner, lower risk, and
scientifically more honest.

### 3. Update manuscript framing

Required.

The abstract and simulation introduction currently say the simulation protocol
is tied to the finalized TT500 shared validation handoff.  That will become
stale after Phase 4k integration.  The text should be revised to say that the
article reports two simulation layers:

- a finalized TT500 single-quantile benchmark handoff;
- a Phase 4k joint multi-quantile synthetic DGP article-candidate forecast
  validation.

The text should avoid implying that the raw model output is intrinsically
noncrossing.  The correct statement is that scored forecast quantiles satisfy a
declared monotone forecast-output contract, while raw quantiles are preserved
and audited.

### 4. Integrate tables and figures

Required.

The current Phase 4k table files have stable labels:

```text
tab:joint-qvp-phase4k-protocol
tab:joint-qvp-phase4k-tau0-decision
tab:joint-qvp-phase4k-selected-scores
tab:joint-qvp-phase4k-truth-by-tau
tab:joint-qvp-phase4k-scenario-summary
tab:joint-qvp-phase4k-crossing-diagnostics
tab:joint-qvp-phase4k-runtime-convergence
```

The figure assets are nonempty PNG files:

```text
figures/joint_qvp_synthetic_dgp/phase4k_truth_error_by_tau.png
figures/joint_qvp_synthetic_dgp/phase4k_scenario_truth_error.png
figures/joint_qvp_synthetic_dgp/phase4k_raw_crossing_adjustments.png
figures/joint_qvp_synthetic_dgp/phase4k_hit_coverage_by_tau.png
figures/joint_qvp_synthetic_dgp/phase4k_runtime_convergence.png
```

Recommended manuscript placement:

- include the protocol and selected-score tables in the main text;
- include truth-by-tau and crossing diagnostics in the main text if space
  permits;
- move scenario summary and runtime/convergence to the appendix if the
  simulation section becomes too dense;
- use figures for interpretability, but do not duplicate every table result
  in prose.

### 5. Preserve conservative claims

Required.

Use this claim boundary:

- Supported: the Phase 4k selected arm produces finite, noncrossing contract
  forecast quantiles over 90 replicated synthetic DGP scenarios and 9000
  forecast origins.
- Supported: raw crossings are sparse, concentrated in extreme adjacent tails,
  and preserved as diagnostic review evidence.
- Supported: `tau0 = 0.15` is preferred because it preserves contract
  noncrossing and improves runtime/convergence relative to `tau0 = 0.10` with
  negligible score differences.
- Not supported: raw model quantiles are guaranteed noncrossing.
- Not supported: the validation is a universal proof of calibration under all
  possible reservoir designs or DGPs.
- Not supported: Phase 4k replaces application evidence from GloFAS or PriceFM.

### 6. Build and visual QA

Required after manuscript edits.

The repository build instructions are:

```bash
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

Before building, run a scoped reference check:

```bash
rg -n "joint-qvp-phase4k|phase4k_|qdesn_validation_tt500_final_tables" main.tex tables figures
```

After building, check for:

- undefined references;
- overfull boxes caused by wide Phase 4k tables;
- figure readability in the generated PDF;
- duplicate labels;
- stale text that still says the simulation section only consumes TT500.

### 7. Reproducibility closeout

Required after manuscript integration.

Create or update a closeout note that records:

- exact Phase 4k freeze directory;
- exact selected arm and selected `tau0`;
- source manifest verification status;
- article asset manifest hash status;
- manuscript build commands and result;
- final table/figure labels consumed by `main.tex`;
- raw crossing disclosure language;
- any tables moved to appendix or supplement.

### 8. Git hygiene

Required before commit.

The worktree contains unrelated dirty files from other lanes, including
GloFAS, PriceFM, `main.tex`, and some joint exAL derivation notes.  The next
commit should stage only intentional joint-QVP Phase 4k/Phase 4l files.

Recommended pre-commit audit:

```bash
git status --short
git diff -- main.tex
git diff -- application/R/joint_qvp_qdesn.R application/tests/run_tests.R
git diff -- docs/implementation_notes/joint_qvp_synthetic_dgp_phase4l_manuscript_integration_audit_plan_20260706.md
```

If manuscript edits are made, inspect `main.tex` carefully before staging so
parallel GloFAS or PriceFM edits are not accidentally bundled.

## Start-To-Finish Implementation Plan

### Stage A: Pre-edit reproducibility guard

Run:

```bash
Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root("."); dirs <- c("application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704", "application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704/phase4k_article_asset_audit"); for (d in dirs) { mf <- read.csv(file.path(d,"artifact_manifest.csv"), check.names=FALSE); ok <- logical(nrow(mf)); for (i in seq_len(nrow(mf))) { p <- file.path(d, mf$relative_path[[i]]); ok[[i]] <- file.exists(p) && identical(app_sha256_file(p), mf$sha256[[i]]) }; cat(d, "rows=", nrow(mf), "all_hashes=", all(ok), "\n") }; am <- read.csv("tables/joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv", check.names=FALSE); ok <- logical(nrow(am)); for (i in seq_len(nrow(am))) { p <- if (grepl("^/", am$path[[i]])) am$path[[i]] else file.path(getwd(), am$path[[i]]); ok[[i]] <- file.exists(p) && identical(app_sha256_file(p), am$sha256[[i]]) }; cat("asset_manifest rows=", nrow(am), " tables=", sum(am$artifact_type=="table"), " figures=", sum(am$artifact_type=="figure"), " all_hashes=", all(ok), "\n", sep="")'
```

Pass condition:

- freeze manifest hashes all verify;
- asset audit manifest hashes all verify;
- article asset manifest hashes all verify.

### Stage B: Add manuscript wrapper for Phase 4k tables

Add a small wrapper, for example:

```text
tables/joint_qvp_synthetic_dgp_phase4k_tables.tex
```

The wrapper should include the table files in the intended manuscript order.
This avoids a long block of table inputs in `main.tex` and makes future audits
easier.

Suggested main-text wrapper order:

```tex
\input{tables/joint_qvp_synthetic_dgp_phase4k_protocol.tex}
\input{tables/joint_qvp_synthetic_dgp_phase4k_tau0_decision.tex}
\input{tables/joint_qvp_synthetic_dgp_phase4k_selected_forecast_scores.tex}
\input{tables/joint_qvp_synthetic_dgp_phase4k_selected_truth_by_tau.tex}
\input{tables/joint_qvp_synthetic_dgp_phase4k_crossing_diagnostics.tex}
```

Then decide whether to include scenario summary and runtime/convergence in the
main text or appendix:

```tex
\input{tables/joint_qvp_synthetic_dgp_phase4k_selected_scenario_summary.tex}
\input{tables/joint_qvp_synthetic_dgp_phase4k_runtime_convergence.tex}
```

### Stage C: Edit simulation section

Modify Section `Simulation Validation Study` so it has two clear evidence
blocks:

1. TT500 single-quantile benchmark validation.
2. Joint-QVP multi-quantile synthetic DGP validation.

Recommended subsection structure:

```text
Simulation Validation Study
  Single-Quantile TT500 Benchmark
    Data-Generating Processes
    Fit and Forecast Protocol
    Competing Methods
    Criteria for Comparison
    TT500 Fit and Forecast Results
  Joint Multi-Quantile Synthetic DGP Forecast Validation
    Registry and forecast protocol
    Phase 4k article-candidate freeze
    Forecast scores and truth recovery
    Raw/contract crossing diagnostics
    Reproducibility and limitations
```

Do not make the Phase 4k subsection sound like a new application.  It is a
controlled synthetic validation layer.

### Stage D: Add figures with compact interpretation

Recommended figure order:

1. `phase4k_truth_error_by_tau.png`
2. `phase4k_scenario_truth_error.png`
3. `phase4k_raw_crossing_adjustments.png`
4. optionally `phase4k_hit_coverage_by_tau.png`
5. optionally `phase4k_runtime_convergence.png`

Use captions that state the artifact source and gate interpretation.  Example
claim boundary:

```text
The plotted quantiles are contract forecasts used for scoring; raw model
quantiles are audited separately and summarized in the crossing diagnostics.
```

### Stage E: Compile and repair layout only

Run:

```bash
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

If tables are too wide, fix presentation only:

- reduce to the most interpretable columns;
- use `\scriptsize` for dense tables;
- move supporting tables to appendix;
- do not change generated validation values by hand.

If labels are undefined, fix wiring.  If prose still refers to TT500 as the
only simulation evidence, revise the framing.

### Stage F: Rerun focused validation tests

Run:

```bash
Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root("."); source(app_path("application/R/input_contract.R")); source(app_path("application/R/synthesize_quantiles.R")); source(app_path("application/R/score_forecasts.R")); source(app_path("application/R/joint_qvp_qdesn.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4j_tau0_candidate_launch.R")); cat("phase4j test passed\n")'

Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root("."); source(app_path("application/R/input_contract.R")); source(app_path("application/R/synthesize_quantiles.R")); source(app_path("application/R/score_forecasts.R")); source(app_path("application/R/joint_qvp_qdesn.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_candidate_freeze.R")); cat("phase4k freeze test passed\n")'

Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root("."); source(app_path("application/R/input_contract.R")); source(app_path("application/R/synthesize_quantiles.R")); source(app_path("application/R/score_forecasts.R")); source(app_path("application/R/joint_qvp_qdesn.R")); source(app_path("application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_assets.R")); cat("phase4k assets test passed\n")'
```

### Stage G: Write final closeout

After the manuscript compiles, add a short closeout note:

```text
docs/implementation_notes/joint_qvp_synthetic_dgp_phase4l_manuscript_integration_closeout_20260706.md
```

The closeout should record:

- files edited;
- build commands run;
- focused tests run;
- asset manifest status;
- PDF result;
- remaining review caveat;
- exact commit scope recommendation.

### Stage H: Commit cleanly

Stage only the relevant files.  Suggested scope:

```text
application/R/joint_qvp_qdesn.R
application/scripts/91_freeze_joint_qvp_synthetic_dgp_phase4k_article_candidate.R
application/scripts/92_build_joint_qvp_synthetic_dgp_phase4k_article_assets.R
application/scripts/93_audit_joint_qvp_synthetic_dgp_phase4k_article_assets.R
application/tests/run_tests.R
application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_candidate_freeze.R
application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_assets.R
docs/implementation_notes/joint_qvp_synthetic_dgp_forecast_phase4k_article_candidate_freeze_plan_20260706.md
docs/implementation_notes/joint_qvp_synthetic_dgp_forecast_phase4k_article_candidate_freeze_implementation_20260706.md
docs/implementation_notes/joint_qvp_synthetic_dgp_phase4l_manuscript_integration_audit_plan_20260706.md
tables/joint_qvp_synthetic_dgp_phase4k_*.tex
tables/joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv
figures/joint_qvp_synthetic_dgp/phase4k_*.png
main.tex
```

Include `main.tex` only if Phase 4l manuscript edits have been made and
reviewed.  Do not stage PriceFM, GloFAS, or unrelated derivation notes in the
same commit.

## Risk Register

| Risk | Severity | Mitigation |
|---|---:|---|
| Wide generated tables overflow manuscript pages | medium | Use wrapper and move dense support tables to appendix if needed. |
| Prose overclaims raw noncrossing behavior | high | State raw/contract policy explicitly in text and captions. |
| TT500 and Phase 4k evidence are conflated | high | Use separate subsections with separate scientific questions. |
| Stale TT500-only language remains in abstract/introduction | medium | Search for `TT500`, `handoff`, and `simulation protocol` after edits. |
| Parallel GloFAS/PriceFM dirty files get staged accidentally | high | Use path-limited `git diff` and `git add` commands. |
| Another full launch is started unnecessarily | medium | Treat Phase 4k as frozen unless source manifests fail or reviewer policy demands replication. |
| Asset values are hand-edited in LaTeX tables | high | Rebuild assets from freeze instead of manual value edits. |

## Final Decision

Proceed with Phase 4l manuscript integration.

Do not run another calibration, tau0 screen, or full forecast launch before the
manuscript integration pass.  The validation evidence is already frozen and
verified.  The correct next work is to write the article-facing interpretation
around the frozen evidence, compile the paper, and close the reproducibility
loop.
