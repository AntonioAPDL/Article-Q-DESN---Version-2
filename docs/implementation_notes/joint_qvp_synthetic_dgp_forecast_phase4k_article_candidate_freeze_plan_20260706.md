# Joint-QVP Synthetic DGP Forecast Phase 4k Article-Candidate Freeze Plan

Date: 2026-07-06

## Executive Recommendation

Move to a Phase 4k article-candidate freeze and article-asset stage.

Do not launch another full calibration or tau0 screen before freezing the
current Phase 4j result.  The Phase 4j launch completed successfully, the
implementation gates pass, all manifests verify, contract forecast quantiles
are noncrossing, and the audit already recommends promoting the selected
`tau0 = 0.15` arm without duplicate compute.

The next stage should therefore be:

1. freeze the selected Phase 4j arm as the article-candidate synthetic DGP
   forecast validation artifact;
2. build article-ready storage-light tables and figures from that frozen
   artifact;
3. preserve raw crossing and VB diagnostics as transparent review evidence;
4. only then integrate carefully bounded manuscript text.

This is the optimal next move because it preserves the expensive completed
launch, avoids test-oracle-style retuning, and creates a stable source of truth
for article tables before any manuscript edits are made.

## Evidence Audited

Primary launch directory:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704
```

Primary audit directory:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704/phase4j_launch_audit
```

Audit and launch artifacts inspected:

- `phase4j_launch.exitcode`
- `phase4j_launch.log`
- `artifact_manifest.csv`
- `launch_run_config.csv`
- `launch_metric_summary.csv`
- `launch_ranking.csv`
- `launch_recommendation.csv`
- `launch_tail_tradeoff_summary.csv`
- `launch_vb_runtime_summary.csv`
- `launch_crossing_by_arm.csv`
- `launch_crossing_by_scenario.csv`
- `launch_crossing_by_family.csv`
- `launch_crossing_by_tau_pair.csv`
- nested Phase 3 artifacts for both tau0 arms;
- `phase4j_launch_audit/phase4j_launch_health_summary.csv`
- `phase4j_launch_audit/phase4j_tau0_decision_summary.csv`
- `phase4j_launch_audit/phase4j_article_candidate_promotion_plan.csv`
- `phase4j_launch_audit/phase4j_truth_distance_by_arm_tau.csv`
- `phase4j_launch_audit/phase4j_hit_coverage_by_arm_tau.csv`
- `phase4j_launch_audit/phase4j_vb_convergence_runtime_audit.csv`

The working tree currently contains unrelated local changes in `main.tex`,
PriceFM scripts/tests/tables/figures, and two joint exAL derivation notes.
Phase 4k should not touch those unless explicitly requested.

## Current Health Summary

| Check | Status | Evidence | Interpretation |
|---|---:|---|---|
| Phase 4j process | pass | exit code `0`; launch log ended `PHASE4J_EXIT_CODE=0` | The actual launch completed. |
| Launch labels | pass | phase `phase4j_tau0_candidate_launch`, tier `tau0_candidate_launch` | No smoke/pilot labels in the launch contract. |
| Registry scale | pass | 90 replicated scenario rows | 9 base scenarios times 10 replicates. |
| Candidate arms | pass | 2 arms: `tau0_0p10_primary`, `tau0_0p15_comparator` | Launch compared only the two intended candidates. |
| Root manifest | pass | 17 rows, 0 missing, 0 hash mismatches | Root launch artifacts are reproducible. |
| Fixture manifest | pass | 12 rows, 0 missing, 0 hash mismatches | Shared fixture layer is reproducible. |
| Nested Phase 3 manifests | pass | both arms have 21 rows and verified hashes | Forecast artifacts are reproducible. |
| Audit manifest | pass | 9 rows, 0 missing, 0 hash mismatches | Audit output is reproducible. |
| Contract crossings | pass | total contract crossing pairs `0` | Scored forecast quantiles satisfy the noncrossing contract. |
| Raw crossings | review | total raw crossings `54`; selected arm has `27` | Raw output still needs transparent diagnostic language. |
| VB convergence | pass/review | selected arm max-iter rate `0.03783784` | Below the Phase 4j review threshold; still worth reporting. |
| Launch gate | review | raw crossings remain diagnostic evidence | No implementation blocker. |
| Promotion plan | ready | selected arm `tau0_0p15_comparator`; duplicate compute `FALSE` | Freeze selected arm instead of rerunning. |

## Tau0 Decision Diagnosis

The selected arm is:

```text
tau0_0p15_comparator
```

with selected `tau0 = 0.15`.

The decision is pragmatic, not a claim of overwhelming statistical dominance.
Both arms are extremely close in forecast accuracy.  The comparator wins because
it keeps the noncrossing contract intact, ties the raw crossing count, slightly
reduces raw crossing magnitude, reduces VB max-iteration rate, and materially
reduces runtime.

| Metric | tau0 0.10 primary | tau0 0.15 comparator | Diagnostic conclusion |
|---|---:|---:|---|
| Scenarios | 90 | 90 | Matched launch scale. |
| Forecast origins | 9000 | 9000 | Matched forecast evidence. |
| Raw crossing pairs | 27 | 27 | Tie. |
| Contract crossing pairs | 0 | 0 | Both pass implementation gate. |
| Max raw crossing magnitude | 0.2469527 | 0.2438035 | Comparator is slightly better. |
| Mean truth MAE | 0.0918408 | 0.0921846 | Comparator is 0.37 percent worse. |
| Mean truth RMSE | 0.1216018 | 0.1219993 | Comparator is 0.33 percent worse. |
| Pinball mean | 0.1595237 | 0.1595253 | Essentially tied. |
| WIS mean | 0.3190475 | 0.3190506 | Essentially tied. |
| CRPS-grid mean | 0.3641409 | 0.3641354 | Comparator is microscopically better. |
| VB refits | 377 | 370 | Comparator needs fewer refits. |
| VB max-iter count | 20 | 14 | Comparator improves convergence. |
| VB max-iter rate | 0.0530504 | 0.0378378 | Comparator improves convergence. |
| Runtime seconds | 24709.61 | 19872.53 | Comparator is about 19.6 percent faster. |
| Scenario pass/review/fail | 60 / 30 / 0 | 63 / 27 / 0 | Comparator has fewer review rows. |

The conservative freeze rationale should therefore be:

> Select `tau0 = 0.15` for the article-candidate freeze because it preserves
> zero contract crossings, keeps forecast scores within a negligible tolerance
> of the primary arm, improves convergence/runtime, and has fewer scenario-level
> reviews.  Raw crossings remain diagnostic review evidence and are not hidden.

## Raw Crossing Diagnosis

For the selected arm, raw crossings are sparse but not absent:

| Base scenario | Tau pair | Raw crossing pairs | Max adjustment | Diagnosis |
|---|---:|---:|---:|---|
| `regime_shift` | 0.05-0.10 | 15 | 0.0904560 | Main stress-case crossing source. |
| `laplace_bridge` | 0.05-0.10 | 6 | 0.1094543 | Lower-tail bridge sensitivity. |
| `heteroskedastic_seasonal` | 0.05-0.10 | 2 | 0.1219018 | Largest selected-arm adjustment. |
| `student_t_location_scale` | 0.90-0.95 | 3 | 0.0294156 | Upper-tail heavy-tail sensitivity. |
| `persistent_heavy_tail` | 0.90-0.95 | 1 | 0.0198605 | Isolated upper-tail sensitivity. |

All selected-arm raw crossing events occurred on reused fits:

| Refit status | Crossing events |
|---|---:|
| fresh refit | 0 |
| reused fit | 27 |

This is an important diagnosis.  The crossing events are less consistent with
fresh optimizer failure at the crossing origin and more consistent with
extreme-tail drift between refit points.  The raw/contract forecast policy is
therefore appropriate: preserve raw diagnostics, score only the monotone
contract forecast quantiles, and mark large or frequent adjustments as review
evidence.

## Selected-Arm Forecast Diagnosis

Selected-arm truth distance by tau:

| Tau | Mean truth MAE | Mean truth RMSE | Interpretation |
|---:|---:|---:|---|
| 0.05 | 0.1106708 | 0.1428564 | Lower-tail stress visible. |
| 0.10 | 0.0908531 | 0.1205619 | Moderate lower-tail error. |
| 0.25 | 0.0675731 | 0.0928678 | Good interior performance. |
| 0.50 | 0.0629566 | 0.0873999 | Best central performance. |
| 0.75 | 0.0768787 | 0.1042999 | Good upper-interior performance. |
| 0.90 | 0.1059168 | 0.1383681 | Upper-tail stress visible. |
| 0.95 | 0.1304432 | 0.1676412 | Hardest tau level. |

Selected-arm truth distance by base scenario:

| Base scenario | Mean truth MAE | Mean truth RMSE | Interpretation |
|---|---:|---:|---|
| `regime_shift` | 0.2735502 | 0.4069730 | Hardest stress scenario by far. |
| `nonlinear_reservoir_friendly` | 0.0915622 | 0.1143490 | Moderate stress. |
| `heteroskedastic_seasonal` | 0.0891700 | 0.1127381 | Moderate stress with lower-tail crossings. |
| `persistent_heavy_tail` | 0.0667589 | 0.0827867 | Stable except isolated upper tail. |
| `laplace_bridge` | 0.0643755 | 0.0799885 | Bridge family mostly stable. |
| `asymmetric_laplace_tail` | 0.0638989 | 0.0794285 | Tail DGP performs well after earlier work. |
| `gaussian_mixture_bridge` | 0.0630351 | 0.0781445 | Stable bridge. |
| `student_t_location_scale` | 0.0589939 | 0.0729833 | Strong despite some upper-tail crossings. |
| `normal_bridge` | 0.0583168 | 0.0706022 | Easiest bridge scenario. |

The stress hierarchy is coherent.  `regime_shift` is the dominant source of
forecast difficulty, hit-rate review, and raw crossing events.  This should be
reported as a stress-test limitation rather than tuned away after seeing the
launch result.

## Alternatives Considered

### Alternative 1: Rerun the full launch

Reject for now.

The run completed with verified manifests and no implementation failures.
Rerunning would duplicate expensive compute without changing the decision
criteria.  A duplicate run is justified only if a reviewer asks for independent
confirmation or if a manifest/provenance defect is discovered.

### Alternative 2: Tune tau0 or refit stride again

Reject as the next stage.

Phase 4g-4j already moved from broad screening to launch-labelled candidate
selection.  Further tuning after the full launch would risk overfitting the
held-out synthetic validation evidence.  A small targeted refit-stride
diagnostic can be run later as reviewer-support evidence, but it should not
block the freeze.

### Alternative 3: Edit manuscript tables immediately

Reject as the next stage.

The current manuscript simulation section still consumes the older TT500
handoff.  Editing claims before creating stable joint-QVP article assets would
make provenance fragile.  The manuscript should consume freeze outputs, not
the large working launch directory directly.

### Alternative 4: Promote the selected arm into a storage-heavy copy of every
large file

Reject as the default.

The selected nested Phase 3 directory contains useful large CSVs, including raw
and contract forecast quantiles.  The article freeze should be storage-light by
default: copy summaries, manifests, provenance, decision tables, and figure/table
assets, while recording source paths and hashes for large raw forecast files.
Large-file copying can be enabled explicitly if archival policy requires it.

### Alternative 5: Freeze selected arm and build article assets

Accept.

This is the only option that is reproducible, conservative, efficient, and
aligned with the existing pass/review/fail policy.

## Phase 4k Objectives

Phase 4k should create a stable article-candidate evidence layer from the
completed Phase 4j launch.

It should not run new model fits.

It should:

- verify the Phase 4j root, fixture, audit, and selected-arm manifests;
- freeze the selected `tau0 = 0.15` arm decision;
- preserve exact source paths and SHA-256 hashes;
- write storage-light article-candidate summaries;
- produce article-ready tables and figures;
- retain raw crossing diagnostics and monotone-contract scoring diagnostics;
- leave TT500, GloFAS, and PriceFM lanes untouched.

Recommended freeze directory:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704
```

Recommended article table prefix:

```text
tables/joint_qvp_synthetic_dgp_phase4k_*
```

Recommended article figure directory:

```text
figures/joint_qvp_synthetic_dgp/
```

## Implementation Plan

### Step 1: Add Freeze Helper

Add a helper in `application/R/joint_qvp_qdesn.R`, for example:

```r
app_joint_qvp_freeze_synthetic_dgp_phase4k_article_candidate()
```

Inputs:

- `launch_dir`
- `audit_dir`
- `freeze_dir`
- `copy_large_forecast_files = FALSE`

Required validations:

- launch exit code is `0`;
- root launch manifest verifies;
- fixture manifest verifies;
- audit manifest verifies;
- selected nested Phase 3 manifest verifies;
- selected arm in audit matches selected arm in launch recommendation;
- selected arm has `contract_crossing_pairs == 0`;
- no nonlaunch labels are present;
- selected arm is `tau0_0p15_comparator` unless explicitly overridden with a
  documented reason.

Required freeze outputs:

- `freeze_decision_summary.csv`
- `freeze_source_manifest_verification.csv`
- `freeze_selected_arm_metric_summary.csv`
- `freeze_selected_arm_truth_by_tau.csv`
- `freeze_selected_arm_crossing_summary.csv`
- `freeze_selected_arm_hit_coverage_summary.csv`
- `freeze_selected_arm_vb_runtime_summary.csv`
- `freeze_selected_arm_scenario_assessment.csv`
- `freeze_large_file_registry.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

Storage policy:

- copy small summary CSVs into the freeze;
- copy or reference the selected nested `artifact_manifest.csv`;
- reference large raw/contract forecast quantile files by path and hash unless
  `copy_large_forecast_files = TRUE`;
- record source paths for every referenced large file.

### Step 2: Add Freeze Script

Add:

```text
application/scripts/91_freeze_joint_qvp_synthetic_dgp_phase4k_article_candidate.R
```

Required CLI:

- `--launch-dir`
- `--audit-dir`
- `--freeze-dir`
- `--copy-large-forecast-files`

Default paths should use the existing Phase 4j default helpers.

The script should print:

- freeze directory;
- selected arm;
- selected tau0;
- gate status;
- manifest path.

### Step 3: Add Article Asset Builder

Add a storage-light article asset helper, for example:

```r
app_joint_qvp_build_synthetic_dgp_phase4k_article_assets()
```

and script:

```text
application/scripts/92_build_joint_qvp_synthetic_dgp_phase4k_article_assets.R
```

The builder should consume the freeze directory, not the working launch
directory directly.

Recommended tables:

- `tables/joint_qvp_synthetic_dgp_phase4k_protocol.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_tau0_decision.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_selected_forecast_scores.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_selected_truth_by_tau.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_selected_scenario_summary.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_crossing_diagnostics.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_runtime_convergence.tex`
- `tables/joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv`

Recommended figures:

- `figures/joint_qvp_synthetic_dgp/phase4k_truth_error_by_tau.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_scenario_truth_error.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_raw_crossing_adjustments.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_hit_coverage_by_tau.png`
- `figures/joint_qvp_synthetic_dgp/phase4k_runtime_convergence.png`

Figure rules:

- show contract forecast scoring metrics separately from raw crossing
  diagnostics;
- label raw crossings as diagnostic review evidence;
- do not imply that monotone projection hides model failures;
- prioritize legibility and article-scale typography.

### Step 4: Add Article Asset Audit

Add:

```text
application/scripts/93_audit_joint_qvp_synthetic_dgp_phase4k_article_assets.R
```

The audit should verify:

- freeze manifest hashes;
- table/figure asset hashes;
- no missing source file references;
- no stale Phase 4i/pilot labels;
- selected-arm identity and selected tau0 are consistent across all outputs;
- tables do not report uncontracted raw quantiles as scored forecasts;
- manuscript-ready table row counts are stable.

Recommended audit outputs:

- `phase4k_article_asset_audit.csv`
- `phase4k_article_asset_manifest_verification.csv`
- `phase4k_manuscript_integration_checklist.csv`
- `README.md`
- `artifact_manifest.csv`

### Step 5: Tests

Add focused tests:

```text
application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_candidate_freeze.R
application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_assets.R
```

Test cases:

- freeze helper refuses missing or failing manifests;
- freeze helper preserves selected arm and selected tau0;
- freeze helper refuses contract crossings;
- freeze helper writes complete SHA-256 manifest;
- large-file registry records hashes for referenced forecast files;
- article asset builder reads only freeze artifacts;
- article tables have stable schemas and finite metrics;
- article figures are created and nonempty;
- audit catches nonlaunch labels;
- existing Phase 4j test still passes.

Keep tests fast by constructing a tiny local Phase 4j-like fixture in a
temporary directory or reusing the small Phase 4j smoke contract from
`test_joint_qvp_qdesn_synthetic_dgp_phase4j_tau0_candidate_launch.R`.

### Step 6: Manuscript Integration

Do not edit `main.tex` during the freeze implementation unless explicitly
asked.  After the Phase 4k freeze and article assets pass audit, integrate the
joint-QVP synthetic DGP validation as one of two safe options:

1. add a new subsection after the current TT500 simulation results explaining
   the joint multi-quantile synthetic DGP forecast validation; or
2. keep the existing TT500 section as the single-quantile benchmark and add
   the joint-QVP synthetic DGP validation as a supplementary/appendix-style
   multi-quantile validation block.

The manuscript language should state:

- VB is the primary engine for the synthetic DGP forecast validation;
- selected `tau0 = 0.15` is an article-candidate freeze from Phase 4j;
- scored forecast quantiles use the monotone contract;
- raw model quantiles are preserved and reviewed;
- raw crossings remain sparse, extreme-tail, and mostly stress-scenario events;
- `regime_shift` is the dominant stress-case limitation;
- no final claim is made that raw model output is intrinsically noncrossing.

## Commands For The Next Stage

After implementing Phase 4k:

```bash
Rscript application/scripts/91_freeze_joint_qvp_synthetic_dgp_phase4k_article_candidate.R \
  --launch-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704 \
  --audit-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704/phase4j_launch_audit \
  --freeze-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704
```

Then:

```bash
Rscript application/scripts/92_build_joint_qvp_synthetic_dgp_phase4k_article_assets.R \
  --freeze-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704
```

Then:

```bash
Rscript application/scripts/93_audit_joint_qvp_synthetic_dgp_phase4k_article_assets.R \
  --freeze-dir application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704
```

Focused tests:

```bash
Rscript application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4j_tau0_candidate_launch.R
Rscript application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_candidate_freeze.R
Rscript application/tests/test_joint_qvp_qdesn_synthetic_dgp_phase4k_article_assets.R
```

## Pass/Review/Fail Gates

Hard fail:

- missing or unverifiable Phase 4j root manifest;
- missing or unverifiable fixture manifest;
- missing or unverifiable audit manifest;
- missing or unverifiable selected nested Phase 3 manifest;
- selected arm mismatch between launch, audit, and freeze;
- contract forecast crossings in selected arm;
- nonfinite selected-arm scores;
- stale smoke/pilot/calibration-pilot labels in freeze outputs;
- article asset table or figure hashes missing;
- manuscript asset builder reads directly from a mutable non-freeze source.

Review:

- raw crossing diagnostics remain nonzero;
- monotone adjustments are large for some extreme-tail stress origins;
- selected tau0 is slightly worse in truth MAE/RMSE than the primary arm;
- regime-shift stress scenario dominates truth error and coverage reviews;
- VB max-iteration rows remain nonzero.

Pass:

- implementation gates pass;
- selected-arm contract crossings are zero;
- scores and summaries are finite;
- freeze artifacts are hash-complete;
- article tables and figures are generated from the freeze;
- raw crossing diagnostics are preserved and clearly labeled.

## Recommended Next Action

Implement Phase 4k freeze and article asset generation.

The first concrete deliverable should be
`application/scripts/91_freeze_joint_qvp_synthetic_dgp_phase4k_article_candidate.R`.
It should be small, auditable, and should not trigger any new model fitting.

Once the freeze passes, build tables and figures from the freeze, audit them,
and only then decide how to weave the joint-QVP synthetic validation into the
manuscript.
