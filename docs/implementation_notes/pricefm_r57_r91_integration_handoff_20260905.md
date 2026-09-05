# PriceFM R57-R91 Scientific-Lane Freeze and Integration Handoff

Status: `READY_FOR_INTEGRATION`

## Scope and decision

This document freezes the PriceFM scientific lane after the repaired
independent seven-quantile VB comparison. The final R87-R91 chain is complete:
R87 refitted the 280 exAL atoms affected by the invalid historical
initialization, R88 applied the frozen numerical gates, R89 selected one
complete AL or exAL family per region/fold using validation AQL only, R90
performed a scoring-only test audit with no refits, and R91 produced a
read-only promotion queue.

The scientifically justified action is selective case-level promotion, not
replacement of the full Q-DESN surface. Twelve of 56 region/fold cases beat
both the current authoritative Q-DESN reference and cached fold-aligned
PriceFM. The complete candidate surface is 1.462% worse than authoritative
Q-DESN on mean test AQL, although it is 2.796% better than cached PriceFM.
Replacing only the 12 dual winners would improve the authoritative mean AQL by
0.004768, or 0.072%. The article must therefore describe targeted gains and
must not claim uniform dominance.

No registry, article, joint-model, or MCMC authority was changed. Integration
belongs to the ARTICLE QDESN INTEGRATION coordinator.

## Lane identity

| Field | Frozen value |
|---|---|
| Scientific lane | PriceFM |
| Canonical transcript | `/home/jaguir26/.codex/sessions/2026/07/04/rollout-2026-07-04T05-16-46-019f2c6a-854f-7583-82aa-cdbb87d1f0e1.jsonl` |
| Task worktree | `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_joint_quantile_20260824` |
| Artifact repository | `/data/jaguir26/local/src/Article-Q-DESN` |
| Branch | `work/pricefm-joint-quantile-20260824` |
| Upstream | `origin/work/pricefm-joint-quantile-20260824` |
| Frozen lane HEAD | `a423a77bbf8fc0abfe16d95eabf9d3d3bf1f4087` |
| Frozen execution HEAD | `bcbb71c5e57d5664bf517d9386e67bf61ea860a3` |
| Fetched `origin/main` | `29a4be48806dcf2f9ae421c7d8a62936387cb19e` |
| Merge base | `266db91bd2028b480f397ed44b67419dc005f610` |
| Divergence from `origin/main` | main-only 118; lane-only 29 |
| Upstream divergence | 0 behind; 0 ahead |
| Tracked worktree state | Clean |
| Excluded untracked file | `debug_xis_bad_iter_0041.rds` (pre-existing, not owned or modified by this closeout) |

The branch must be integrated by commit, not by copying the dirty worktree.
The immutable exact changed-file set is:

```bash
git diff --name-status \
  266db91bd2028b480f397ed44b67419dc005f610..\
  a423a77bbf8fc0abfe16d95eabf9d3d3bf1f4087
```

That set contains 189 tracked paths: three under `application/R`, 103 under
`application/scripts/pricefm`, 62 focused tests, and 21 implementation notes.
There are no files outside those four owned groups. The three shared-R paths
are `application/R/joint_exqdesn_exact_structured_inference.R`,
`application/R/joint_qvp_qdesn.R`, and the new
`application/R/pricefm_joint_quantile_inference.R`. The PriceFM script set
contains `08_run_desn_model_smoke.R`, numbered stages 200 through 288, and the
R65-R75 package/runtime helper and patch files. The exact commit series is
listed below, so the coordinator can review or cherry-pick a bounded prefix.

## Unique commit series

1. `9b497603be13739133e770f41cb21a65af3b920a` Prepare PriceFM Stage-R57 joint quantile campaign
2. `dcb87f48bf6fa9dbdf329ffae45563911478a4a7` Preserve PriceFM virtualenv in R57 configs
3. `8443f7f062283a7e29f54cefed1a92c8e54437ff` Recover PriceFM Stage-R57 joint validation
4. `e13164b7c755a0027418d1f2cf5da9529cd086da` Accelerate PriceFM Stage-R57 postfit recovery
5. `19c6af6b9ed7ee63589ae02aa8530d27d6922e34` Harden PriceFM recovery artifact writes
6. `887fc16519119c3616f4d7b8dcad6e426e1f4828` Record PriceFM Stage-R58 recovery snapshot
7. `ce4b128bff0b22cf79f3ac320749de0795f7ee06` Prepare PriceFM joint scoring repair
8. `9c41caa4a1bc5dfd1341fb14da0f52fa767b41b7` Handle R60 authority metric overlap
9. `00879f3e3bcf6b3da7c69a32afdcaa2429732fd5` Rebuild PriceFM seven-quantile authority
10. `677ae323e98288b8bf5c96f702f19e5d89c66fe0` Make PriceFM smoke Python environment portable
11. `aeda1b78986ab16beab116ed115ff3e68563fd5e` Preserve PriceFM virtualenv in R62 configs
12. `49f15c43e193a12d7367ff115893426f15c9cf2e` Make R62 historical data paths portable
13. `04d6566aab56206619a2b3030d174b6dcc50089e` Validate portable R62 runtime data contracts
14. `bf7eb860806c62d9c3de2906e297373c84a425e3` Preserve PriceFM virtualenv in R62 postfit
15. `90e83e08021382d189d85d8bc90b39193e0a4820` Prepare corrected PriceFM R63 joint campaign
16. `b6434e797e0afac376e5891ffe3f635107e31b77` Wire R63 through shared PriceFM postfit
17. `2ec22704344b9d6848ab8d3fb761cd46667d6f3c` Recover PriceFM R63 and freeze R64 confirmation
18. `77d7dfbcf9a7897d019c6430e33fbc2122720b8d` Correct PriceFM structured exAL VB continuation
19. `e54c7a71a23357bf704e82db6a242dd752d95824` Add PriceFM R67-R69A readiness audits
20. `a3901f5bf84c3a5ce5da90f72338f610ecf2a6bc` Prepare PriceFM R69B CRAN launch manifest
21. `cfeb050a5d30c2b25c4a18020a153bcb9bac177e` Launch PriceFM R70 CRAN independent VB
22. `09943ca0b32d4c5f6e320f8fd1cee2d81d450aae` Fix PriceFM R70 venv adapter invocation
23. `7f8ded379ecc8dcc4e339115c9323635a2cff60b` Repair PriceFM exAL and prepare R76 surface
24. `62bf72529fa2a34c9ddb55891ac2553692de6f22` Record PriceFM R76 background launch
25. `8c67be8ed52e382e02dd6234f0fa3a65a0fd654d` Repair PriceFM structured exAL initialization
26. `d59d8bc2e077c68e61d9281d94418247855d37df` Prepare homogeneous PriceFM exAL refit
27. `80100d0a42f1353000ed7fffa9496ae6655bd0a8` Complete PriceFM repaired VB audit pipeline
28. `bcbb71c5e57d5664bf517d9386e67bf61ea860a3` Repair PriceFM R87-R91 finalizer recovery
29. `a423a77bbf8fc0abfe16d95eabf9d3d3bf1f4087` Record PriceFM R91 promotion audit

## Scientific dependency map

| Stage | Purpose | Frozen result | Authority consequence |
|---|---|---|---|
| R57-R64 | Joint seven-quantile exploration and repaired scoring | Diagnostic/non-promoted | Established that joint work was not ready to replace the independent authority |
| R65-R69A | Structured exAL and CRAN 1.1.1 reproducibility audits | 56 launch-grade independent anchors | Defined the comparable AL/exAL independent target surface |
| R69B-R73 | Exact-API independent VB launch and AL completion | AL 392/392 | Reused as the complete AL reference; no later AL refit |
| R75-R83 | exAL mechanism diagnosis and structured-initialization repair | 14 repaired R83 atoms | Identified invalid historical initialization and validated the replacement |
| R85-R87 | Surface audit and homogeneous exAL refit | R87 280/280, zero process failures | Replaced every remaining atom using the invalid initializer |
| R88 | Numerical/provenance closeout | 294 atoms; 256 eligible; 32 eligible cases; 10 fallbacks | Froze which complete exAL case surfaces could compete with AL |
| R89 | Validation-only family selection | 32 exAL cases, 24 AL cases; 392 atoms | Froze one full seven-quantile family per case before test access |
| R90 | Scoring-only test audit | 56/56 cases; zero refits; exact validation replay | Opened test once without reselection |
| R91 | Dual-reference decision closeout | 12/56 strict dual winners | Created the read-only promotion queue; no mutation |

## Completed-run ledger

| Run tag | Units | Completed | Failed | Workers | Test opened | Fit performed |
|---|---:|---:|---:|---:|---|---|
| `pricefm_stage_r87_homogeneous_exal_refit_20260904` | 280 atoms | 280 | 0 | 32 | No | Yes, exAL VB only |
| `pricefm_stage_r90_scoring_only_test_audit_20260905` | 56 cases | 56 | 0 | 20 | Yes | No |

R87 consumed 452.91 core-hours. It produced 243 atoms passing every frozen
numerical gate and 37 atom-level failures: 36 first-state-step violations, one
tail-state violation, and one beta-norm-ratio violation, with one overlap.
Formal convergence was recorded for 88/280 atoms, while 192 reached the fixed
iteration budget; formal convergence was diagnostic rather than a
post-observation promotion gate. All accepted atoms pass the pre-registered
finite-value, trajectory, provenance, and hash checks.

## Final comparison

| Quantity | Value |
|---|---:|
| Cases | 56 |
| Quantile atoms | 392 |
| Validation-selected exAL cases | 32 |
| Validation-selected AL cases | 24 |
| Cases beating authoritative Q-DESN | 16 |
| Cases beating cached PriceFM | 30 |
| Cases beating both | 12 |
| Candidate mean test AQL | 6.704209 |
| Authoritative Q-DESN mean test AQL | 6.607637 |
| Cached PriceFM mean test AQL | 6.897056 |
| Candidate relative to Q-DESN | 1.462% worse |
| Candidate relative to PriceFM | 2.796% better |
| Selective 12-case authority mean after replacement | 6.602869 |
| Selective gain over current authority | 0.004768 AQL, 0.072% |

The 12 strict dual winners are:

| Region/fold | Family | Candidate | Q-DESN | PriceFM | Gain vs Q-DESN |
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

Six wins exceed 0.1% against Q-DESN, three exceed 0.5%, and one exceeds 1%.
The smallest deterministic wins meet the registered strict rule but require
careful presentation because their practical effect is negligible.

## Reproducibility evidence

The authoritative generated roots are:

- R88: `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r88_repaired_exal_surface_closeout_20260905`
- R89: `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r89_validation_family_selection_20260905`
- R90 prep: `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r90_scoring_only_test_prep_20260905`
- R90 scores: `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runs/pricefm_stage_r90_scoring_only_test_audit_20260905`
- R91: `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r91_test_audit_and_promotion_20260905`

Frozen SHA-256 values:

| File | SHA-256 |
|---|---|
| R88 `source_manifest.csv` | `9d4ed86f90d281353f9e9dfa33143140d3ffc7ac26090977db819fffda5dd60e` |
| R89 `source_manifest.csv` | `445c32bbebebdc9998baf41f4183158e2aa5ca843b64a1cef28f7e99eec6e936` |
| R90 prep `source_manifest.csv` | `e221a80c28e1c46f35d5c3574ca585ed098deb9074f9b9948dd5e00684e94fe5` |
| R91 `source_manifest.csv` | `a4bf9a752f5d37aefb95455d9da80a78736f59d758df995a04da66fb6f909bd5` |
| R91 `pricefm_stage_r91_promotion_queue.csv` | `3a5f4899ed1e01421af2376f723d6b95d44220d604304e64844cbb232ee7ef3d` |

The finalizer records Python 3.11.13, NumPy 2.4.6, pandas 3.0.3,
scikit-learn 1.8.0, PyYAML 6.0.3, and joblib 1.5.3 under the dedicated
PriceFM virtual environment. All 392 validation replays pass with maximum
absolute difference `1.8189894035458565e-12`. All 392 quantile metrics and
1,568 quantile-by-horizon metrics are finite and uniquely keyed. R90 terminal
states record `model_fitted=false` and `selection_changed=false` for all 56
cases. Temporary validation/test matrices were removed after scoring.

The R87 artifact roots occupy approximately 336 MB and R90 approximately
371 MB. R91 is approximately 192 KB. `/data` had 539 GB free at freeze time.
No active PriceFM tmux session or R87-R91 process remained. Other lanes had
active jobs and were neither inspected beyond process names nor modified.

## Validation performed

The final implementation was validated with:

```bash
application/data_local/pricefm/venv/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r80_diagnostic_replay.py \
  application/tests/test_pricefm_stage_r80_r81_zero_freeze_gate.py \
  application/tests/test_pricefm_stage_r82_r83_structured_init_gate.py \
  application/tests/test_pricefm_stage_r84_independent_vb_closeout.py \
  application/tests/test_pricefm_stage_r85_surface_wide_numerical_validity.py \
  application/tests/test_pricefm_stage_r86_r87_homogeneous_exal_refit.py \
  application/tests/test_pricefm_stage_r87_to_r91_finalizer.py \
  application/tests/test_pricefm_stage_r88_repaired_exal_surface.py \
  application/tests/test_pricefm_stage_r89_validation_family_selection.py \
  application/tests/test_pricefm_stage_r90_scoring_only_case.py \
  application/tests/test_pricefm_stage_r90_scoring_only_launcher.py \
  application/tests/test_pricefm_stage_r90_scoring_only_prep.py \
  application/tests/test_pricefm_stage_r91_test_audit_and_promotion.py
```

Result at the frozen handoff HEAD: `41 passed in 3.24s`. The earlier recovery
gate, which included additional predecessor coverage, recorded `50 passed in
3.50s`; the command above is the concise integration suite to reproduce.

Scripts 282 through 288 passed `py_compile`, and
`Rscript application/tests/test_pricefm_stage_r78_failure_observability.R`
passed. The exact PriceFM environment probe passed. All R88-R91 source
manifests re-hashed without discrepancy, and the branch passed
`git diff --check` before the freeze commits.

## Article-safe handoff

No article source file was changed on this branch. The following ignored R91
outputs are inputs for coordinator review, not files to publish verbatim:

- `pricefm_stage_r91_article_candidate_table.csv`
- `pricefm_stage_r91_figure_data.csv`
- `article_prose_recommendation.md`
- `pricefm_stage_r91_case_decisions.csv`
- `pricefm_stage_r91_promotion_queue.csv`

The coordinator should first decide whether to apply the exact 12-row
registered queue or a more conservative, effect-size-qualified article subset.
Registry authority and article assets must then be regenerated from one frozen
decision source. The article should report the complete-surface comparison as
a negative result and the 12 replacements as targeted improvements. It should
emphasize IT_NORD fold 3, SE_3 fold 1, and IT_CNOR fold 1, while avoiding a
claim that AL/exAL uniformly dominates the existing Q-DESN surface.

## Runtime paths that remain excluded

Do not copy, add, or publish any path under:

- `application/data_local/pricefm/experiment_grids/`
- `application/data_local/pricefm/runs/`
- `application/data_local/pricefm/logs/`
- `application/data_local/pricefm/authoritative/`
- `application/data_local/pricefm/venv/`

Do not add model objects, predictions, adapters, temporary matrices, `.rds`,
`.rda`, or `.RData` files. The untracked `debug_xis_bad_iter_0041.rds` is not
part of this handoff.

## Integration order

1. Fetch the task branch and verify HEAD `a423a77bbf8fc0abfe16d95eabf9d3d3bf1f4087`.
2. Review the 29-commit branch diff against merge base `266db91b`, paying special attention to the three shared `application/R` files because `origin/main` is 118 commits ahead.
3. Integrate the lane on a coordinator worktree based on the latest `origin/main`; resolve conflicts by preserving newer unrelated-lane behavior and the bounded PriceFM interfaces.
4. Run the combined repository tests plus the exact focused suite above. Do not use the artifact worktree as the merge source.
5. Re-hash the five frozen R88-R91 evidence files and verify the 12-row queue before any mutation.
6. If the registered promotion rule remains authoritative, mutate only the 12 case decisions in the PriceFM registry and regenerate dependent PriceFM tables and figures from that frozen registry.
7. Compile the complete article and supplement. Publish the article-only snapshot through the integration coordinator after reviewing claims and values.
8. Preserve the R87/R90/R91 artifacts until integration and article regeneration are independently verified; perform any later storage cleanup from a manifest, never by broad extension-based deletion.

## Open risks and decisions

- `origin/main` has advanced substantially. Shared-R conflict resolution needs
  combined testing; a blind merge is not appropriate.
- The full candidate surface does not beat authoritative Q-DESN. Only the
  frozen case-specific replacements are scientifically promotable.
- Half of the dual wins are below 0.1% against Q-DESN. They satisfy the strict
  deterministic contract, but effect-size language must remain restrained.
- Formal VB convergence is limited even though every accepted atom passes the
  frozen numerical gates. The article should describe the actual numerical
  contract rather than implying universal formal convergence.
- Q-DESN and PriceFM comparator authority is complete at the case-level
  seven-quantile AQL, not uniformly at every quantile and horizon block.
  Candidate subgroup diagnostics cannot be presented as direct comparator
  wins where no matched historical subgroup reference exists.
- Test data have now been opened for this frozen selection. Further tuning of
  these same cases would constitute a new experiment generation and cannot be
  folded back into R89 selection.
- Joint and MCMC work remains non-authoritative and is not required to close
  this independent-VB result. It should not delay integration of the valid
  selective result.

## Final recommendation

Integrate the reproducibility branch first, preserve the R91 queue unchanged,
and apply the 12 replacements only after combined tests and hash verification.
Regenerate the PriceFM article assets from the resulting registry in the
coordinator lane. Do not launch another broad fit before this evidence is
integrated and its article claim is settled. Any future work should begin on a
new dedicated PriceFM branch from the then-current `origin/main`, with a new
validation protocol because the R91 test surface is no longer sealed.

`READY_FOR_INTEGRATION`
