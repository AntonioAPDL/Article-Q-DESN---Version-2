# Joint QDESN Phase 126 Article-Asset Rebuild Plan

Date: 2026-07-12

## Executive Decision

The optimal next stage is **not another VB screen, not another MCMC launch, and not a manual manuscript edit first**.

The optimal next stage is a controlled Phase 126 article-asset rebuild from the frozen Phase 125 balanced MCMC audit:

```text
application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712
```

Phase 125 shows that the balanced MCMC evidence is complete:

- 32/32 scenario-model MCMC rows are present.
- 8/8 scenarios are represented.
- 4/4 model classes are represented per scenario.
- 0 worker failures.
- 0 contract quantile crossings.
- 0 hard implementation failures.
- 22 pass and 10 review case gates.
- 40/40 Phase 125 output hashes verified.

Therefore, the next scientific task is to make the article assets and prose match this new evidence packet.

## Current State Audit

### Repository State

The authoritative repository is:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2
```

At the time of this planning audit, the repository is on `main` and synced with `origin/main`.

The Phase 125 implementation files are present but not yet committed in this chat:

- `application/R/joint_qdesn_phase125_balanced_mcmc_audit.R`
- `application/scripts/129_freeze_joint_qdesn_phase125_balanced_mcmc_audit.R`
- `application/tests/test_joint_qdesn_phase125_balanced_mcmc_audit.R`
- `docs/implementation_notes/joint_qdesn_phase125_balanced_mcmc_audit_20260712.md`

Before Phase 126 article edits are committed, these Phase 125 files should be included in the same coherent validation-workflow commit or committed first.

### Phase 125 Evidence

Phase 125 merges:

```text
application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711
application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711
```

The merged evidence has:

| Model | Cases | Pass | Review | Fail | MCMC Forecast MAE | MCMC Check Loss | Raw Forecast Crossings | Contract Crossings |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Joint QDESN RHS | 8 | 6 | 2 | 0 | 0.103 | 0.160 | 1 | 0 |
| Independent QDESN RHS | 8 | 1 | 7 | 0 | 0.098 | 0.160 | 37 | 0 |
| Joint exQDESN RHS | 8 | 8 | 0 | 0 | 0.123 | 0.161 | 0 | 0 |
| Independent exQDESN RHS | 8 | 7 | 1 | 0 | 0.107 | 0.160 | 0 | 0 |

Main interpretation:

1. **Joint QDESN RHS remains the cleanest primary AL article anchor** because it has strong fit/forecast accuracy with only one MCMC forecast raw crossing and zero contract crossings.
2. **Independent QDESN RHS is forecast-competitive but diagnostically less clean** because it carries most raw crossings.
3. **Joint exQDESN RHS is the most stable joint extension** because it has 8/8 pass gates and zero raw MCMC forecast crossings, but it is less accurate on average.
4. **Independent exQDESN RHS is stable and useful as a comparator**, but not the main headline row.

### Existing Article-Asset Mismatch

The current article asset builder:

```text
application/R/joint_qdesn_article_assets.R
application/scripts/110_build_joint_qdesn_article_validation_assets.R
```

is still organized around the older Phase 113/114/115 evidence shape:

- selected VB source;
- primary Joint QDESN RHS MCMC reference only;
- nine-mechanism language;
- MCMC as fit-window reference for one selected joint row.

The current manuscript section also still says:

- the main article reports the MCMC reference layer for the selected joint QDESN RHS specification;
- the validation uses nine synthetic mechanisms;
- the MCMC table has nine scenario rows and zero raw crossings.

This is now outdated relative to Phase 125.

### Scenario Count Correction

The Phase 121 through Phase 125 chain consistently uses **eight** scenarios:

```text
normal_bridge
laplace_bridge
gaussian_mixture_bridge
student_t_location_scale
asymmetric_laplace_tail
persistent_heavy_tail
regime_shift
nonlinear_reservoir_friendly
```

The older article assets mention nine mechanisms because they were based on the earlier Phase 115 article packet that included `heteroskedastic_seasonal`.

Phase 126 must correct this. The article should not claim nine mechanisms unless a new balanced MCMC campaign is launched for the missing heteroskedastic-seasonal rows. Since Phase 125 already gives a complete and coherent eight-scenario grid, launching another campaign is not optimal unless the scientific argument specifically requires heteroskedastic seasonality in the main table.

## Why Phase 126 Is the Optimal Next Stage

### Reason 1: The Computational Objective Is Complete

The current bottleneck is no longer computation. The balanced MCMC grid is complete and hard gates pass. More computation would delay article integration without addressing the current mismatch between manuscript claims and source evidence.

### Reason 2: The Article Needs a New Evidence Hierarchy

The old hierarchy was:

```text
VB/VB-LD selected candidate -> one primary MCMC reference row -> article tables
```

The new hierarchy should be:

```text
VB/VB-LD screening/calibration -> selected per-case winners -> balanced MCMC confirmation -> article-facing table
```

This better matches the user's intended final direction:

- VB/VB-LD for calibration, screening, and initialization.
- MCMC for final validation evidence.
- Four model classes included:
  - Joint QDESN RHS under AL;
  - Independent QDESN RHS under AL;
  - Joint exQDESN RHS under exAL;
  - Independent exQDESN RHS under exAL.

### Reason 3: The Current Article Tables Are Now Understating the Evidence

The existing MCMC article table only presents the selected Joint QDESN RHS row. Phase 125 now supports a balanced four-model MCMC comparison. The main article should use that improvement.

### Reason 4: The Current Article Text Would Be Misleading If Left Unchanged

Leaving the manuscript as-is would imply:

- nine mechanisms instead of eight;
- MCMC reference for one selected joint row instead of balanced MCMC confirmation;
- zero raw crossings as a global MCMC diagnostic, whereas Phase 125 has 38 MCMC forecast raw crossings across the balanced four-model grid;
- older Phase 113/114 source paths instead of Phase 125.

These are not small copy edits. They are evidence-structure edits.

## Phase 126 Objective

Implement an article-safe rebuild layer that consumes Phase 125 and writes updated joint QDESN article assets.

Recommended script:

```text
application/scripts/130_build_joint_qdesn_phase126_article_assets.R
```

Recommended helper module:

```text
application/R/joint_qdesn_phase126_article_assets.R
```

Recommended output artifact:

```text
application/cache/joint_qdesn_phase126_article_assets_20260712
```

The script should optionally write final article tables into:

```text
tables/
figures/joint_qdesn_simulation/
```

but the safer design is:

1. write all regenerated tables/figures into the Phase 126 cache first;
2. verify the cache manifest;
3. copy only approved article-safe tables/figures into `tables/` and `figures/`;
4. compile;
5. commit/push only after the compile and QA pass.

## Recommended Article Assets

### Main Text Table

Use one compact main MCMC model table from Phase 125:

```text
tables/joint_qdesn_article_validation_mcmc_balanced_model_summary.tex
```

Rows:

- Joint QDESN RHS;
- Independent QDESN RHS;
- Joint exQDESN RHS;
- Independent exQDESN RHS.

Recommended columns:

- Model;
- Cases;
- Fit MAE;
- Forecast MAE;
- Check loss;
- Grid CRPS;
- Hit-rate error;
- Raw crossings;
- Contract crossings;
- Status.

This table directly supports the main article message and avoids overwhelming the reader with 32 scenario rows in the main text.

### Supplement or Provenance Tables

Keep the detailed scenario table out of the main text unless the manuscript needs it for a specific argument:

```text
tables/joint_qdesn_article_validation_mcmc_balanced_scenario_summary.tex
tables/joint_qdesn_article_validation_mcmc_balanced_gate_summary.tex
tables/joint_qdesn_article_validation_mcmc_balanced_winner_summary.tex
```

These should be included through the provenance/supplement wrapper, not necessarily the main article wrapper.

### Figures

Do not add new main-text figures by default. The Phase 125 table is clearer than a bar chart for the main message. If figures are generated, they should be provenance/support figures:

- model-level fit/forecast MAE bar chart;
- raw-vs-contract crossing diagnostic chart;
- scenario winner heatmap.

The main text should remain table-led unless a figure conveys something the table cannot.

## Manuscript Changes Required

The subsection:

```text
\subsection{Joint Multi-Quantile Frozen-Feature Validation}
```

should be updated to state:

1. The study uses eight synthetic mechanisms in the balanced MCMC confirmation grid.
2. VB/VB-LD was used for screening, calibration, and initialization.
3. The main article now reports balanced MCMC confirmation for four model classes.
4. The MCMC rows score quantile-grid/readout paths; they do not validate a scalar posterior predictive density.
5. Reported scores use monotone contract quantile grids.
6. Raw crossings are diagnostics before monotone rearrangement.
7. The evidence supports Joint QDESN RHS as the primary AL anchor, while Joint exQDESN RHS provides the cleanest stable exAL joint extension.
8. Independent QDESN RHS remains a useful comparator but carries most raw crossing diagnostics.

The current text around lines 1854--1890 should be rewritten because it still refers to the older one-row MCMC reference structure.

## Proposed Phase 126 Implementation Tasks

### Task 1: Source Verification

Load Phase 125 and verify:

- `artifact_manifest.csv` is complete;
- `source_artifact_manifest_verification.csv` has all pass rows;
- `source_vb_freeze_manifest_verification.csv` has all pass rows;
- `fixture_source_manifest_verification.csv` has all pass rows;
- `balanced_scope_matrix.csv` has 32/32 expected rows;
- `balanced_gate_summary.csv` has no fail rows.

Hard fail if any source gate fails.

### Task 2: Article Table Construction

Construct tables from Phase 125:

- compact model table for main text;
- scenario-level table for supplement/provenance;
- gate table for supplement/provenance;
- scenario-winner table for supplement/provenance.

Use article-facing language:

- `QDESN` means AL working likelihood;
- `exQDESN` means exAL working likelihood;
- `Joint` versus `Independent` describes readout structure;
- `RHS` denotes the regularized horseshoe prior.

Avoid internal labels such as:

- `phase122`;
- `phase124c`;
- `source_model_id`;
- `case_id`;
- `VB-LD candidate_id`;
- `selected_controls`.

These should remain in provenance files only.

### Task 3: Article Wrapper Update

Update:

```text
tables/joint_qdesn_article_validation_tables.tex
tables/joint_qdesn_article_validation_provenance_tables.tex
```

Recommended main wrapper:

```tex
\input{tables/joint_qdesn_article_validation_mcmc_balanced_model_summary.tex}
```

Recommended provenance wrapper:

```tex
\input{tables/joint_qdesn_article_validation_mcmc_balanced_scenario_summary.tex}
\input{tables/joint_qdesn_article_validation_mcmc_balanced_gate_summary.tex}
\input{tables/joint_qdesn_article_validation_mcmc_balanced_winner_summary.tex}
```

The older VB tables can be retained only as screening/provenance tables if the article still needs them. They should not be presented as the final evidence layer now that balanced MCMC is complete.

### Task 4: Manuscript QA

Patch `main.tex` only after table assets are generated.

Required corrections:

- Replace nine-mechanism language with eight-scenario balanced grid language.
- Replace selected-primary-row MCMC wording with balanced four-model MCMC confirmation wording.
- Make clear that VB/VB-LD is screening/calibration/initialization, not final article evidence.
- State that MCMC confirmation is the final article-facing evidence.
- Report the key Phase 125 numeric results:
  - 32/32 rows complete;
  - 0 contract crossings;
  - 38 MCMC forecast raw crossings across the full balanced grid;
  - Joint QDESN RHS has 1 MCMC forecast raw crossing;
  - Independent QDESN RHS has 37 MCMC forecast raw crossings;
  - Joint and Independent exQDESN RHS have 0 MCMC forecast raw crossings.
- Avoid scalar posterior predictive-density language.

### Task 5: Compile and Audit

Run:

```bash
latexmk -pdf -interaction=nonstopmode -halt-on-error \
  -outdir=local_trackers/codex_compile_$(date +%Y%m%d_%H%M%S) main.tex
```

If `latexmk` is unavailable, use the documented repository compile pattern.

Then run a focused article QA script or add one if needed:

```text
application/scripts/131_audit_joint_qdesn_phase126_article_assets.R
```

The audit should verify:

- Phase 126 asset manifest exists and hashes pass;
- `tables/joint_qdesn_article_validation_asset_manifest.csv` points to Phase 125 or Phase 126, not Phase 113/114;
- main table source is the balanced MCMC model table;
- no stale nine-mechanism language remains in the joint validation subsection;
- raw crossing wording separates full-grid, primary joint, independent AL, and contract counts;
- the manuscript still compiles.

## Gates for Phase 126

Hard fail:

- Phase 125 manifest failure;
- source-manifest failure inherited from Phase 125;
- missing balanced model table;
- stale Phase 113/114 source references in regenerated asset manifest;
- manuscript compile failure;
- any claim that the composite AL/exAL likelihood is a scalar posterior predictive density;
- any claim that all raw crossings are zero in the balanced MCMC grid.

Review:

- raw crossings remain present;
- independent AL comparator remains review-heavy;
- exQDESN rows are stable but less accurate on average;
- article text becomes too long or table-heavy.

Pass:

- all hard gates pass;
- article tables are generated from Phase 125;
- prose matches the eight-scenario balanced MCMC evidence;
- compile succeeds;
- review qualifications are explicit and concise.

## Recommended Final Message After Phase 126

The article-facing message should be:

> The final joint multi-quantile validation uses VB/VB-LD only for screening, calibration, and MCMC initialization. The article-facing evidence is the balanced MCMC confirmation grid over eight synthetic mechanisms and four readout/likelihood combinations. Joint QDESN RHS is the primary AL anchor because it gives strong fit and forecast recovery with minimal raw crossing diagnostics. Joint exQDESN RHS gives the cleanest stable exAL joint extension. Independent QDESN RHS is forecast-competitive but carries most raw pre-contract crossings, which supports the value of the joint readout and the monotone output contract.

## What Not To Do Next

Do not launch more broad screening before article integration.

Do not run another MCMC campaign unless the article must include the omitted heteroskedastic-seasonal scenario in the balanced table.

Do not manually edit the article tables without regenerating manifests.

Do not overwrite PriceFM, GloFAS, TT500, or unrelated validation assets.

Do not reintroduce local implementation labels into the manuscript-facing text.

## Exact Next Command Sequence

After approving this plan, implement Phase 126 with a new article-asset builder:

```bash
Rscript application/tests/test_joint_qdesn_phase125_balanced_mcmc_audit.R

Rscript application/scripts/129_freeze_joint_qdesn_phase125_balanced_mcmc_audit.R

Rscript application/scripts/130_build_joint_qdesn_phase126_article_assets.R \
  --phase125-dir application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712 \
  --output-dir application/cache/joint_qdesn_phase126_article_assets_20260712 \
  --tables-dir tables \
  --figures-dir figures/joint_qdesn_simulation

Rscript application/scripts/131_audit_joint_qdesn_phase126_article_assets.R \
  --phase126-dir application/cache/joint_qdesn_phase126_article_assets_20260712

latexmk -pdf -interaction=nonstopmode -halt-on-error \
  -outdir=local_trackers/codex_compile_$(date +%Y%m%d_%H%M%S) main.tex
```

Commit and push only after:

1. Phase 125 files are included;
2. Phase 126 assets are regenerated from Phase 125;
3. the manuscript prose is updated;
4. the compile passes;
5. the article asset audit passes.
