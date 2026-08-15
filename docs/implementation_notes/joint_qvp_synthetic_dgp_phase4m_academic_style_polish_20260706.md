# Joint Multi-Quantile Synthetic DGP Phase 4m Academic Style Polish

Date: 2026-07-06

## Scope

This pass applies `Academic_Writing_Style_Profile_v0.2.md` to the
manuscript-facing joint multi-quantile synthetic DGP validation material added
in Phase 4l.  The scope is intentionally narrow:

- `main.tex` abstract, contribution paragraph, simulation opening, and joint
  multi-quantile validation subsections;
- `tables/joint_qvp_synthetic_dgp_phase4k_tables.tex`, the compact manuscript
  wrapper for the frozen validation assets;
- manuscript integration only, with no changes to TT500, GloFAS, PriceFM, or
  the numerical validation artifacts.

## Style Criteria Applied

The academic writing profile emphasizes:

1. definition-first statistical exposition;
2. restrained, evidence-bounded claims;
3. explicit separation between model output, post-processing, diagnostics, and
   statistical interpretation;
4. simulation sections that state the goal, DGPs, sample sizes, competitors,
   metrics, results, and limitations;
5. avoidance of generic or workflow-centered prose when object-level
   statistical language is available.

The earlier reader-focused audits also flagged a recurring risk: reproducible
engineering details are valuable, but they should not replace the manuscript's
statistical argument.  Hashes, manifests, gates, and internal phase labels
belong primarily in reproducibility statements and audit notes, not in the main
result narrative.

## Audit Findings

1. **Internal workflow vocabulary was too visible.**  Phrases such as
   "Phase 4k article-candidate freeze," "freeze gate," "promoted," "handoff,"
   and "review evidence" made the article sound like an internal validation log.
   The manuscript should instead describe the reported validation run, frozen
   reproducibility bundle, diagnostic status, and limitations.

2. **The acronym `joint-QVP` was underdefined for manuscript readers.**  The
   code and implementation notes use `joint-QVP`, but the manuscript section can
   be clearer by saying "joint multi-quantile" or "reported quantile grid"
   unless the acronym is formally introduced.

3. **Claims needed to be tied to the design.**  Statements about the selected
   \(\tau_0\) arm should be phrased as a two-arm sensitivity result under the
   declared synthetic DGP registry, not as a general tuning conclusion.

4. **Raw versus reported quantiles needed cleaner language.**  The important
   distinction is that raw quantile-specific forecasts are preserved for
   diagnostics, while forecast scores use the monotone rearranged quantile grid.
   The manuscript should not imply that the raw readouts are intrinsically
   noncrossing.

5. **Tables and captions needed reader-facing labels.**  Table labels such as
   "Freeze gate," "hard gate passes," and "article-candidate freeze" are useful
   for audit artifacts but too operational for the manuscript.  They were
   mapped to diagnostic-status, monotonicity, and reproducibility-bundle
   language.

## Revision Plan

1. Replace internal phase/freeze/handoff prose in the abstract, simulation
   opening, and joint multi-quantile section with statistical validation
   language.
2. Keep reproducibility facts, but consolidate them in the reproducibility and
   limitations paragraph.
3. Rephrase the \(\tau_0=0.15\) selection as a bounded sensitivity result.
4. Make raw-versus-reported quantile language consistent in text, table
   captions, and figure captions.
5. Recompile the manuscript and scan the log for undefined references,
   rerun warnings, and box warnings.

## Closeout

The manuscript polish was applied to:

- the abstract and contribution paragraph;
- the simulation-study opening;
- the single-quantile TT500 manuscript prose where it used internal handoff
  language;
- the joint multi-quantile validation and reproducibility subsections;
- the GloFAS and PriceFM manuscript-facing captions/prose where "promoted" or
  similar workflow language appeared;
- the compact joint multi-quantile table wrapper.

No numerical validation artifacts were changed.  The generated Phase 4k table
and figure assets remain governed by
`tables/joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv`; the edited wrapper
`tables/joint_qvp_synthetic_dgp_phase4k_tables.tex` is manuscript prose around
those assets and is not an entry in that asset manifest.

## Verification

Commands completed:

```text
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
rg -n "Warning:|undefined references|Label\\(s\\) may have changed|Overfull|Underfull|Rerun|LaTeX Warning|Package natbib Warning" main.log
Rscript -e '<Phase 4k asset-manifest hash check>'
Rscript -e '<joint-QVP-only Phase 4k article freeze/assets tests>'
```

Results:

- `main.pdf` built successfully with 44 pages.
- The final log scan reported only the `rerunfilecheck` package loading line,
  not an unresolved-reference or rerun warning.
- The Phase 4k article asset manifest has 12 rows; all referenced files exist
  and all SHA-256 hashes match.
- The focused Phase 4k article-candidate freeze and article-asset tests passed
  when run with the joint-QVP helper stack loaded.

The full `application/tests/run_tests.R` harness was also attempted.  It stopped
at the unrelated GloFAS engine contract check because the external engine
worktree at
`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0` is currently
at SHA `21cac1364873e0bb1a76a1aada4a8ae7fe775846`, while the pinned config
requires SHA `4d77027184df369a0607f3ac78eb7eae2687a5ed`.  Required exports were
present, but the source-policy check correctly failed on the pinned commit.  This
is outside the Phase 4m writing polish.
