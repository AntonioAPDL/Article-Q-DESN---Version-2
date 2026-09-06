# PriceFM R91 Coordinator Execution Handoff

Status: **READY_FOR_INTEGRATION**

This is the execution packet for the sole ARTICLE QDESN INTEGRATION
coordinator. It supersedes informal PriceFM integration suggestions but does
not supersede the frozen scientific evidence in
`pricefm_r57_r91_integration_handoff_20260905.md`.

## Executive decision

Integrate the complete PriceFM reproducibility branch, then promote exactly
the 12 R91 rows that satisfy the pre-registered dual-reference gate. Do not
replace the full 56-case candidate surface. Build a new immutable 114-cell
registry generation from the historical 114-cell authority plus those 12
replacements, regenerate every dependent PriceFM table and figure, add a
transparent supplementary promotion table, compile both manuscripts, and
publish the article-only snapshot through the coordinator workflow.

No new model fitting, MCMC, joint fitting, calibration, or launch is required.
No other scientific lane may be touched.

## Audited authorities

| Item | Value observed 2026-09-05 |
|---|---|
| Full repository | `/data/jaguir26/local/src/Article-Q-DESN---Version-2` |
| GitHub remote | `git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git` |
| Integration target | `origin/main` |
| Observed `origin/main` | `29a4be48806dcf2f9ae421c7d8a62936387cb19e` |
| PriceFM task branch | `origin/work/pricefm-joint-quantile-20260824` |
| Frozen scientific payload | `35c82f8751bb792cf2d42298a3655f3c61ca4a57` |
| Scientific result commit | `a423a77bbf8fc0abfe16d95eabf9d3d3bf1f4087` |
| Execution commit | `bcbb71c5e57d5664bf517d9386e67bf61ea860a3` |
| Merge base | `266db91bd2028b480f397ed44b67419dc005f610` |
| Observed divergence | main-only 118; lane-only 30 |
| PriceFM transcript | `/home/jaguir26/.codex/sessions/2026/07/04/rollout-2026-07-04T05-16-46-019f2c6a-854f-7583-82aa-cdbb87d1f0e1.jsonl` |
| Coordinator transcript candidate | `/home/jaguir26/.codex/sessions/2026/09/02/rollout-2026-09-02T23-53-12-01a06566-37ba-7a83-a6a1-23576c70ecc8.jsonl` |
| Article-only branch | `overleaf/article-snapshot` |
| Snapshot builder | `scripts/build_overleaf_article_snapshot.sh` |
| Snapshot manifest | `overleaf/article_files.txt` |
| Direct Overleaf remote | `overleaf-direct` |

The coordinator must fetch again. All observed hashes are stop-on-change
anchors, not permission to overwrite a remote that moved.

The old repository
`/data/jaguir26/local/src/Article-Q-DESN` is a protected, non-authoritative
runtime artifact store. Read the frozen PriceFM evidence there, but do not
merge from it, clean it, reset it, commit in it, or overwrite a historical
output directory. Materialize any new R92 ignored output inside the fresh
integration worktree.

## Pre-integration audit result

At the observed heads, no path was modified by both the PriceFM branch and
`origin/main` after their merge base. A three-way `git merge-tree` produced no
conflict marker. The PriceFM branch changes 190 tracked paths through
`35c82f8`: three `application/R` files, 103 PriceFM scripts, 62 tests, and 22
implementation notes. There are no out-of-lane tracked paths.

This makes a clean textual merge likely, but the coordinator must still test
semantic compatibility. In particular, review:

- `application/R/joint_exqdesn_exact_structured_inference.R`
- `application/R/joint_qvp_qdesn.R`
- `application/R/pricefm_joint_quantile_inference.R`
- `application/scripts/pricefm/08_run_desn_model_smoke.R`

The task worktree contains an unrelated untracked
`debug_xis_bad_iter_0041.rds`. It is excluded and must not be copied, added,
removed, or interpreted as integration evidence.

## Frozen scientific result

| Gate | Result |
|---|---:|
| R87 exAL atom fits | 280/280 complete, 0 failed |
| R88 complete exAL cases | 42 |
| R88 numerically eligible exAL cases | 32 |
| R88 AL fallbacks | 10 |
| R89 family selection | 32 exAL, 24 AL |
| R89 selected atoms | 392 |
| R90 scoring-only cases | 56/56 complete, 0 failed, 0 refits |
| R91 cases beating current Q-DESN | 16 |
| R91 cases beating cached PriceFM | 30 |
| R91 cases beating both | 12 |
| Registry/article/model mutation during R87-R91 | 0 |

The full 56-case selected candidate surface has test AQL `6.7042093434`,
versus `6.6076371132` for current Q-DESN and `6.8970558293` for cached
PriceFM on the same subset. The full candidate surface must not be promoted.

The 12 strict replacements reduce the matched 56-case authority mean from
`6.6076371132` to `6.6028694324`. Embedded in the 114-cell article authority,
they reduce mean Q-DESN AQL from `6.8260194391` to `6.8236774205`.

## Frozen evidence and hashes

Read-only artifact roots:

- `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r88_repaired_exal_surface_closeout_20260905`
- `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r89_validation_family_selection_20260905`
- `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/experiment_grids/pricefm_stage_r90_scoring_only_test_audit_20260905`
- `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runs/pricefm_stage_r90_scoring_only_test_audit_20260905`
- `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r91_test_audit_and_promotion_20260905`
- `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_full_surface_decision_closeout_20260704`

Required hashes:

| Evidence | SHA-256 |
|---|---|
| Historical 114-row registry | `d45c43b6d2dd3b163ca1d3cd0b140ce0e582797aaea0a3db012a7d74293e4802` |
| Historical 288-row horizon diagnostics | `2455116d61d62607819f3013e484a7c0fa1b0fc47a2052e6b29d17ba786a81eb` |
| R88 source manifest | `9d4ed86f90d281353f9e9dfa33143140d3ffc7ac26090977db819fffda5dd60e` |
| R89 source manifest | `445c32bbebebdc9998baf41f4183158e2aa5ca843b64a1cef28f7e99eec6e936` |
| R90-prep source manifest | `e221a80c28e1c46f35d5c3574ca585ed098deb9074f9b9948dd5e00684e94fe5` |
| R91 source manifest | `a4bf9a752f5d37aefb95455d9da80a78736f59d758df995a04da66fb6f909bd5` |
| R91 promotion queue | `3a5f4899ed1e01421af2376f723d6b95d44220d604304e64844cbb232ee7ef3d` |

All 56 R91 Q-DESN and PriceFM reference pairs match the historical 114-row
registry exactly. R90 regenerated all frozen validation predictions with
maximum absolute difference `1.8189894035458565e-12`. Its 56 terminal files
record `model_fitted=false` and `selection_changed=false`.

## Exact promotion set

Promote all 12 rows because they pass the registered strict gate. Do not add a
post-hoc effect-size threshold to registry authority. Article prose may and
should distinguish larger from negligible effects.

| Region/fold | Family | Candidate AQL | Old Q-DESN AQL | PriceFM AQL | Gain vs old Q-DESN |
|---|---|---:|---:|---:|---:|
| IT_NORD / 3 | exAL | 4.455446 | 4.584470 | 5.840089 | 0.129024 |
| SE_3 / 1 | exAL | 7.563096 | 7.620994 | 7.628088 | 0.057899 |
| IT_CNOR / 1 | exAL | 4.692527 | 4.723481 | 5.940016 | 0.030955 |
| DK_2 / 2 | exAL | 6.314902 | 6.331814 | 8.251471 | 0.016913 |
| HU / 1 | exAL | 7.871386 | 7.884141 | 8.500270 | 0.012755 |
| ES / 1 | AL | 5.232137 | 5.243147 | 5.959308 | 0.011010 |
| DK_2 / 3 | exAL | 7.407690 | 7.411013 | 9.368512 | 0.003323 |
| AT / 1 | exAL | 6.739250 | 6.741377 | 7.402188 | 0.002127 |
| LV / 3 | exAL | 12.838358 | 12.840327 | 13.756953 | 0.001969 |
| FR / 3 | exAL | 5.719495 | 5.720239 | 6.817623 | 0.000743 |
| BE / 2 | exAL | 6.396754 | 6.396922 | 6.496657 | 0.000167 |
| DK_1 / 3 | exAL | 7.212994 | 7.213099 | 7.943293 | 0.000105 |

Eleven replacements are exAL and one is AL. Only IT_NORD fold 3 changes the
current likelihood family, from AL to exAL; the other 11 retain their current
family. All case-specific DESN structures, feature policies, seeds, and tau0
anchors are preserved from the frozen R69B configuration.

## Required R92 registry materializer

After merging and testing the scientific branch, implement a deterministic
integration-only script and focused test:

- `application/scripts/pricefm/289_materialize_pricefm_stage_r92_selective_promotion.py`
- `application/tests/test_pricefm_stage_r92_selective_promotion.py`

The script must require an explicit `--authorize-registry-promotion` flag. It
must not fit, launch, select, or inspect any test artifact not already frozen
by R90/R91. It must write to a new ignored directory in the fresh integration
worktree, for example:

`application/data_local/pricefm/authoritative/pricefm_stage_r92_selective_promotion_20260905`

Inputs are the hash-pinned historical 114-row authority, R89 selected-atom
manifest, retained R90 predictions/rows/terminal files, and R91 queue and
diagnostics. The old artifact repository is read-only.

Required outputs:

- `pricefm_full_surface_decision_registry.csv`
- `pricefm_full_surface_method_summary.csv`
- `pricefm_full_surface_horizon_diagnostics.csv`
- `pricefm_full_surface_horizon_summary.csv`
- `pricefm_stage_r92_promoted_case_metrics.csv`
- `pricefm_stage_r92_promotion_ledger.csv`
- `source_manifest.csv`
- `summary.json`
- `pricefm_stage_r92_selective_promotion_report.md`

Required registry rules:

1. Keep all 114 unique region/fold keys and all PriceFM columns unchanged.
2. Keep all 102 non-promoted rows semantically unchanged.
3. Replace only the 12 Q-DESN case metrics and Q-DESN provenance fields.
4. Require candidate AQL to be strictly lower than both old Q-DESN and cached PriceFM for every replacement.
5. Set the selected method to `qdesn_al_rhs_ns_exact_chunked` or `qdesn_exal_rhs_ns_exact_chunked` from the frozen R89 family.
6. Preserve feature policy, input scope, spatial information set, and DESN specification, and verify them against the source case configuration.
7. Record selection as validation-only and test as audit-only.
8. Point evidence to the R91 queue/decision artifact and record its hash; never fabricate a self-referential hash.
9. Recompute delta, relative delta, decision, recommendation, and finite baseline flags deterministically.
10. Preserve the existing `66 qdesn_wins / 12 qdesn_close / 36 pricefm_wins` counts. All 12 replacements were already Q-DESN wins over PriceFM.

Five promoted cases have matched historical PriceFM horizon references: ES/1,
FR/3, IT_CNOR/1, IT_NORD/3, and SE_3/1. Replace their 20 horizon rows using
the R91 candidate horizon AQL averaged across the seven quantiles and the
unchanged matched PriceFM horizon AQL. Preserve the other 268 horizon rows.
The seven promoted cases without historical subgroup comparator authority
must remain absent from the horizon comparison. Do not invent comparator
values.

Expected R92 gates:

| Quantity | Expected value |
|---|---:|
| Registry rows / unique keys | 114 / 114 |
| Promoted / unchanged rows | 12 / 102 |
| Decision counts | 66 / 12 / 36 |
| Mean Q-DESN AQL | 6.823677420470439 |
| Mean PriceFM AQL | 7.038685346534470 |
| Mean Q-DESN minus PriceFM AQL | -0.215007926064031 |
| Median delta | -0.0828156 approximately; preserve full precision in output |
| Horizon rows / cases | 288 / 72 |
| Replaced horizon rows / cases | 20 / 5 |
| Horizon 1-24 lower count / mean delta | 22 / 0.415155 approximately |
| Horizon 25-48 lower count / mean delta | 45 / -0.683553 approximately |
| Horizon 49-72 lower count / mean delta | 34 / -0.198302 approximately |
| Horizon 73-96 lower count / mean delta | 42 / -0.155475 approximately |

The script must also reconstruct candidate AQL, AQCR, MAE, and RMSE from
retained R90 predictions, rows, and pinned target scalers. It must reproduce
R91 AQL to `1e-10` or stop.

## Article-level metric contract

The direct fold-aligned 114-cell Q-DESN row must become:

| Metric | Old | R92 expected |
|---|---:|---:|
| AQL | 6.8260194391 | 6.8236774205 |
| AQCR (%) | 2.6443754958 | 2.5792930320 |
| MAE | 16.7276511411 | 16.7219977076 |
| RMSE | 25.4530916576 | 25.4492314197 |

The direct released-PriceFM row remains AQL `7.0386853465`, AQCR `0`, MAE
`17.2736667198`, and RMSE `26.3355383937`. The corresponding Q-DESN
reductions are 3.0547% AQL, 3.1937% MAE, and 3.3654% RMSE. The 14 published
PriceFM Table II context rows and their provenance must remain byte-for-byte
numerically unchanged.

Implement deterministic paper-aligned regeneration rather than manually
editing numbers. Add a focused builder/test if no current builder exists. The
audit found no tracked builder for the paper-aligned CSV/TEX/manifest, so the
coordinator should create one, for example:

- `application/scripts/pricefm/290_build_pricefm_stage_r92_article_assets.py`
- `application/tests/test_pricefm_stage_r92_article_assets.py`

It should consume only R92 outputs and the current tracked contextual table,
preserve the paper rows, regenerate the direct Q-DESN row, regenerate hashes,
and write a compact 12-row supplementary promotion table.

## Article-safe files

Regenerate the existing PriceFM full-surface assets with script 115 pointed at
R92. Review every changed file, but expect these tracked outputs:

- `tables/pricefm_full_article_asset_manifest.json`
- `tables/pricefm_full_article_asset_summary.json`
- `tables/pricefm_full_current_outputs.tex`
- `tables/pricefm_full_decision_summary.tex`
- `tables/pricefm_full_feature_summary.tex`
- `tables/pricefm_full_fold_summary.tex`
- `tables/pricefm_full_horizon_diagnostic_summary.tex`
- `tables/pricefm_full_horizon_summary.tex`
- `tables/pricefm_full_input_set_summary.tex`
- `tables/pricefm_full_main_summary.tex`
- `tables/pricefm_full_method_summary.tex`
- `tables/pricefm_full_priority_rescue.tex`
- `tables/pricefm_full_source_summary.tex`
- `tables/pricefm_full_top_wins_losses.tex`
- `figures/pricefm_application/pricefm_full_qdesn_pricefm_delta.png`
- `figures/pricefm_application/pricefm_full_horizon_delta_heatmap.png`

Regenerate the paper-aligned assets:

- `tables/pricefm_paper_aligned_current_outputs.tex`
- `tables/pricefm_paper_aligned_main_comparison.csv`
- `tables/pricefm_paper_aligned_main_comparison.tex`
- `tables/pricefm_paper_aligned_main_comparison_manifest.json`

Add:

- `tables/pricefm_r91_selective_promotions.tex`
- `tables/pricefm_r91_selective_promotions.csv`
- a concise R92 implementation note under `docs/implementation_notes/`

Update `overleaf/article_files.txt` for the new TeX table only if the
manuscripts consume it. Do not publish CSV, JSON, scripts, tests, or runtime
artifacts to the article-only snapshot.

Surgical manuscript changes:

1. Keep the 114-cell scope and `66/12/36` counts unchanged.
2. Let regenerated macros update the aggregate AQL and delta values.
3. Add one restrained paragraph explaining that validation-only AL/exAL family selection followed by a frozen test audit yielded 12 case-specific replacements.
4. State that the full 56-case candidate surface was worse than current Q-DESN and that only strict case-level improvements were retained.
5. Add the 12-row promotion ledger to the supplement for transparency.
6. Emphasize IT_NORD/3, SE_3/1, and IT_CNOR/1 as the clearest gains.
7. Do not claim uniform dominance, statistical significance, joint-model evidence, MCMC confirmation, or an unbiased new test after R91.
8. Keep the PriceFM Table II value `5.80` explicitly contextual and distinct from the released-checkpoint replay `7.039`.

## Required coordinator procedure

1. Start with a read-only audit of the authoritative clone and every relevant remote.
2. Fetch `origin` and verify the PriceFM task branch contains the frozen payload and this handoff.
3. Recompute ancestry, pairwise path overlap, and `git merge-tree`. Stop on an unexpected overlap or moved source branch.
4. Create a fresh integration worktree and branch from the latest `origin/main`; never work directly in another lane's worktree.
5. Merge `origin/work/pricefm-joint-quantile-20260824` with an explicit `--no-ff` integration commit.
6. Run `git diff --check`, the focused PriceFM tests, and the shared-R integration tests before creating R92.
7. Implement and test the R92 materializer and article builder under the contracts above.
8. Materialize R92 inside the ignored integration-worktree data root. Treat the old artifact repository as read-only.
9. Verify all expected R92 values and source hashes before changing article files.
10. Regenerate all PriceFM full-surface and paper-aligned tables/figures from R92; do not hand-edit generated values.
11. Apply only the surgical prose and supplementary-table changes listed above.
12. Run the PriceFM asset tests, article integration contracts, manifest checks, and deterministic second-generation diff check.
13. Compile `main.tex` and `qdesn-supplement.tex` to convergence and inspect the affected PriceFM pages visually.
14. Commit the coherent integration result, push the dedicated integration branch, fetch again, and update `origin/main` only by a non-force fast-forward if the audited main anchor still permits it.
15. Build the article-only snapshot from the final verified main commit using `scripts/build_overleaf_article_snapshot.sh` and `overleaf/article_files.txt`.
16. Commit the snapshot as `Publish article-only snapshot from <main SHA>` and push it through ordinary Git to both `origin/overleaf/article-snapshot` and `overleaf-direct/main`.
17. Fetch/read back all remotes and report final integration, main, snapshot, GitHub, and direct-Overleaf hashes.

Suggested fresh branch/worktree names:

```text
branch:   integration/pricefm-r91-selective-promotion-20260905
worktree: /data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__integration_pricefm_r91_20260905
```

## Test floor

At minimum rerun the frozen R80-R91 Python suite from the scientific handoff;
it passed `41` tests at `35c82f8`. Also run:

```text
application/tests/test_pricefm_joint_quantile_compact_kernel.R
application/tests/test_pricefm_joint_quantile_continuation.R
application/tests/test_pricefm_stage_r61_joint_mechanism_controls.R
application/tests/test_pricefm_stage_r65_structured_exal_vb.R
application/tests/test_pricefm_stage_r66_corrected_structured_exal_vb.R
application/tests/test_pricefm_stage_r67_cran111_adapter.R
application/tests/test_pricefm_stage_r70_cran111_independent_vb.R
application/tests/test_pricefm_stage_r72_spd_repair.R
application/tests/test_pricefm_stage_r75_large_n_gig_repair.R
application/tests/test_pricefm_stage_r78_failure_observability.R
application/tests/test_pricefm_full_surface_manuscript_assets.py
application/tests/test_qdesn_corrected_reaudit_contracts.R
```

Run the new R92 tests, every test directly affected by conflict resolution,
and the repository's article/snapshot checks. Compilation is mandatory because
article files will change.

## Stop conditions

- Stop if task-branch HEAD does not contain `35c82f8` or scientific-result commit `a423a77`.
- Stop if any frozen source hash changes.
- Stop if the 56 R91 comparator rows no longer exactly match the base 114-row registry.
- Stop if the R92 registry is not 114 unique rows or changes any of the 102 non-promoted decisions.
- Stop if the promotion set differs from exactly 12 rows.
- Stop if full-surface decision counts differ from `66/12/36`.
- Stop if R92 AQL does not reproduce `6.823677420470439` within floating-point tolerance.
- Stop if any article number is edited manually rather than generated from R92.
- Stop if `origin/main` moves after final testing; fetch, reconcile in the integration branch, and retest.
- Stop rather than touching GloFAS, independent validation, joint validation, active jobs, or ambiguous runtime artifacts.
- Never use reset, force push, blanket cleanup, or an embedded Overleaf token.

## Final reporting requirements

Report:

- source task branch and full source HEAD;
- integration branch and merge commit;
- pre/post `origin/main` hashes;
- exact R92 registry and promotion hashes;
- 114/12/102 registry counts and 66/12/36 decision counts;
- final AQL, AQCR, MAE, and RMSE values;
- exact files changed;
- test commands and results;
- main and supplement page counts and warning audit;
- visual-inspection result;
- final article snapshot hash;
- GitHub main, GitHub snapshot, and direct-Overleaf hashes;
- confirmation that runtime artifacts and other lanes were untouched.

End with either `PRICEFM_R91_INTEGRATED_AND_PUBLISHED` or a precise blocked
status that names the failed gate.

**READY_FOR_INTEGRATION**
