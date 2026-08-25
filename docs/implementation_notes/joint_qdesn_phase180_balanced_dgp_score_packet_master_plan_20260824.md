# Joint QDESN Phase180 Balanced DGP-Score Packet Master Plan

Date: 2026-08-24

Status: audited implementation and execution plan. Phase179 is complete and
integrated. No production run or article mutation is authorized by this
document. The next implementation must occur on a dedicated JOINT branch and
must freeze the final source registry, score contract, compute budget, and seed
plan before any new article-fixture result is inspected.

## 1. Executive Decision

The next stage is not another DESN or `tau0` screen. Phase179 already completed
the case-specific post-M0 selection task on fresh protected replicates. The
next stage is a finite source-completion and article-evidence task:

1. reuse the 11 Phase172 exAL article cells that are both exact-M0 and still
   authoritative after the Phase173B/174 audit;
2. rerun the five exAL article cells whose final Phase179 decisions differ
   from, or complete, the historical Phase174 source contract;
3. rerun all 16 AL article cells because their retained Phase154 artifacts do
   not contain posterior parameter draws;
4. reconstruct and score all 32 final scenario-model cells under one frozen
   seven-level DGP-integrated score contract;
5. produce posterior score means, medians, equal-tailed 95% credible
   intervals, canonical-action scores, joint-minus-independent contrasts, and
   the existing diagnostics;
6. stage a Phase180 article packet only after all source, functional,
   crossing, and manifest gates pass.

This design requires 21 final article cells and 168 chain workers: five exAL
cells times eight chains plus 16 AL cells times eight chains. It avoids the
previous 224-worker proposal, which would have rerun matched parity rows after
selection and would still have treated all Phase172 rows as though they were
the Phase174 article authority. It also avoids a 32-cell refit, because 11
exact-M0 exAL cells already have complete, verified draws.

The current seven-level packet must close before any 19-level dense-grid
campaign. Dense-grid work remains a separate model-refitting study.

## 2. Audited Repository and Runtime State

The audit was performed against the authoritative repository:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2
```

After fetching on 2026-08-24, the latest remote state was:

```text
origin/main: 38caf04c44b2102697db41834484370fd5fd5c59
tree:        d56db431c3003de0f1b441d0fe40366e13c35480
```

The two newest Overleaf synchronization commits have the same tree as the
previous integrated scientific state. Phase179 entered `main` through merge
commit `5e00f6a`; the later integration and Overleaf commits do not change the
scientific tree relevant to this plan.

The planning branch is:

```text
work/joint-qdesn-phase180-score-packet-master-plan-20260824
```

and was created directly from the fetched `origin/main`. It must not merge or
push `main`, touch Overleaf branches, or alter another scientific lane.

No Phase178, Phase179, or Phase180 JOINT computation is active. The old tmux
name `joint_qdesn_phase112_vb_screening_20260708_resumed_clean` remains visible
without a corresponding JOINT worker process and is outside this stage. It is
not evidence of unfinished Phase179 work and must not be killed as part of
this task. Active PriceFM and other-lane jobs are unrelated and must remain
untouched.

## 3. What the Last Week Achieved

The last week resolved the scientific and computational questions that had
previously motivated repeated exAL screening.

### 3.1 Phase178 preserved its original authority

Phase178 completed its exact-M0 candidate ranking under the frozen original
oracle-recovery contract:

- 180/180 workers completed;
- zero worker failures;
- 45 candidate-replicate cells were complete;
- manifests, source hashes, and contract paths verified;
- the original forecast-oracle-MAE ranking remained immutable.

The campaign was not retrospectively relabeled as a DGP-score campaign.

### 3.2 The post-Phase178 score engine was implemented

The repository now contains a tested DGP-integrated finite-grid quantile-score
engine. It:

- evaluates the issued quantile vector under the known conditional DGP;
- supports Gaussian, Laplace, Student-t, Gaussian-mixture, and asymmetric-
  Laplace innovations with the registry's parameterizations;
- uses the exact seven-level trapezoidal weights;
- distinguishes the score of the canonical reported action from the
  posterior distribution of scores;
- preserves joint cross-quantile posterior dependence;
- uses a seeded, chain-balanced product-posterior construction for independent
  quantile fits;
- preserves raw crossings and scores the declared monotone contract;
- reports score-functional R-hat, ESS, MCSE, chain-allocation sensitivity, and
  independent coupling sensitivity.

This score evaluates a finite quantile action. It does not construct a scalar
posterior predictive density from the joint AL/exAL composite working
likelihood.

### 3.3 Phase179 completed case-specific post-M0 confirmation

Phase179 completed 384/384 chain workers over 24 candidate-replicate cases,
with zero worker failures. It used three fresh protected DGP replicates and
16 chains per candidate-replicate. The closeout manifest verifies 10/10 files
and has SHA-256:

```text
db0f35483b479c0e15ac21dbe4127612cff4f640a333e9873f557573b3418675
```

The final decisions are deliberately case-specific:

| Scenario/readout | Final decision | `tau0` | `zeta2` | Alpha prior SD | Protected median gain |
|---|---|---:|---:|---:|---:|
| Laplace bridge, independent exQDESN | retain parity | 0.5000 | 32 | 1.25 | 0 |
| Normal bridge, independent exQDESN | promote `tau0_upper` | 0.9975 | 16 | 0.75 | 0.01884% |
| Persistent heavy tail, independent exQDESN | retain parity | 0.5000 | 16 | 1.00 | 0 |
| Regime shift, independent exQDESN | promote `tau0_lower` | 0.3350 | 32 | 1.25 | 0.05229% |
| Regime shift, joint exQDESN | promote `tau0_lower` | 0.1005 | 64 | 1.00 | 0.00968% |

The three improvements are small but satisfy the prospectively frozen
any-positive-gain rule on at least two of three protected replicates. They are
not evidence for one universal specification.

### 3.4 M0 resolved the main gamma/sigma bottleneck

The exact M0 parameterization materially improved the gamma/sigma geometry:

- worst gamma rank R-hat was approximately 1.007;
- minimum gamma bulk ESS was approximately 2,092;
- worst sigma rank R-hat was approximately 1.006;
- minimum sigma bulk ESS was approximately 2,601.

The remaining review-level scalar behavior is concentrated in alpha/intercept
and trend blocks. Phase179 nevertheless obtained 23 passing score functionals
and one review-level score functional, with zero contract crossings. This is
why another gamma screen is not the next task.

## 4. Reconciliation of Previous Plans

The prior records remain valuable, but their execution states differ.

| Record | What remains authoritative | What is now superseded |
|---|---|---|
| Phase178 frozen ranking | Original oracle-MAE history, sources, and diagnostics | Using that ranking as the article headline |
| Post-Phase178 DGP-score plan | Score definition, quadrature, coupling, uncertainty, and dense-grid separation | Its initial parity-only recommendation |
| Phase179 case-specific plan | Fresh protected selection and any-positive-gain decisions | Any suggestion that Phase179 is still running |
| Phase179/180 unified closeout plan | Need for a complete 32-row draw-backed packet and delayed dense grid | Its claim that all 16 Phase172 exAL rows are reusable article authority; its 224-worker execution route |
| Legacy scripts 257--260 | Reusable low-level fixture/M0 machinery after audit | Their MAE-centered article-fixture promotion logic |

The precedence for future work is:

1. immutable Phase178 original contract;
2. frozen post-Phase178 score definition;
3. completed Phase179 case-specific decisions;
4. this corrected Phase180 source-completion plan;
5. dense-grid work only after the current-grid packet closes.

## 5. Corrected Source-Completeness Audit

The current article source table has exactly 32 rows: eight scenarios for each
of four model/readout combinations. All 32 current realized finite-grid aCRPS
values are finite. However, draw availability and article authority are not
the same thing.

### 5.1 Phase172 availability is not blanket authority

Phase172 contains all 16 exAL article-fixture cells at eight chains, 24,000
iterations, 4,000 burn-in iterations, and thinning by four. It retains 128
compressed posterior-draw checkpoints, and all 128 worker manifests are
verified.

Phase173B/174 nevertheless retained historical sources for five exAL cells.
Therefore, substituting all 16 Phase172 draw sets merely because they exist
would silently reverse a prior source-selection decision.

The 11 exAL cells that remain exact-M0 Phase172/173 authority and may be reused
are:

| Scenario | Joint exQDESN | Independent exQDESN |
|---|---|---|
| Asymmetric Laplace tail | reuse | reuse |
| Gaussian-mixture bridge | reuse | reuse |
| Laplace bridge | reuse | rerun final cell |
| Nonlinear reservoir friendly | reuse | reuse |
| Normal bridge | reuse | rerun final cell |
| Persistent heavy tail | reuse | rerun final cell |
| Regime shift | rerun final cell | rerun final cell |
| Student-t location-scale | reuse | reuse |

### 5.2 Five final exAL cells require article-fixture draws

The five nonreusable exAL cells are exactly the five cells resolved by
Phase179:

- independent Laplace bridge, retained parity;
- independent normal bridge, promoted `tau0_upper`;
- independent persistent heavy tail, retained parity;
- independent regime shift, promoted `tau0_lower`;
- joint regime shift, promoted `tau0_lower`.

The old Phase150/154 source directories retain summary tables but no raw
posterior parameter draws. These five cells must therefore be rerun under
their final Phase179 controls and exact M0 on the frozen article fixture.

### 5.3 All 16 AL cells require retained draws

The Phase154 Joint QDESN AL and Independent QDESN AL manifests verify, and the
existing canonical point summaries remain historical evidence. Their raw
posterior parameter draws were not retained. Posterior score intervals cannot
be reconstructed from `mcmc_draw_summary.csv` or point quantile tables.

All 16 AL cells must be rerun with their already frozen case-specific DESN and
RHS controls. This is draw completion, not calibration.

### 5.4 Final source count

| Final source class | Cells | Chains per cell | Chain workers | Action |
|---|---:|---:|---:|---|
| Reuse exact-M0 Phase172 exAL | 11 | 8 | 0 new | Verify and rescore |
| Final Phase179-resolved exAL | 5 | 8 | 40 | Run exact M0 |
| Joint QDESN AL | 8 | 8 | 64 | Rerun with retained draws |
| Independent QDESN AL | 8 | 8 | 64 | Rerun with retained draws |
| **Total** | **32** | **8 effective chains each** | **168 new** | Complete one balanced packet |

## 6. Why This Is the Minimum Scientifically Complete Design

Four alternatives were considered.

### 6.1 Another broad screen: rejected

Phase179 already selected scenario/readout-specific DESN and `tau0` controls
after M0 repaired the main gamma/sigma geometry. Screening again would reuse
the same scientific question, spend substantial compute, and expose the study
to repeated-selection bias. No unresolved evidence currently points to a new
control dimension that must be screened before article scoring.

### 6.2 Rerun all 32 cells: rejected

Eleven exAL cells have complete, exact-M0, article-fixture draws with verified
worker manifests. Rerunning them would add 88 unnecessary chain jobs and would
not answer a missing scientific question.

### 6.3 Reuse all 16 Phase172 exAL cells: rejected

This is computationally attractive but scientifically incorrect. Five rows
were not selected as Phase172 authority by Phase173B/174, and Phase179 now
provides their final case-specific decisions. Draw availability cannot replace
source lineage.

### 6.4 Rerun promoted challengers and matched parity on the article fixture:
not part of final selection

The protected three-replicate Phase179 campaign already selected the final
controls. Reopening selection on the single article realization would make the
article fixture part of tuning. The final article run therefore evaluates the
five frozen final cells only. Historical parity values remain provenance; a
matched article-fixture parity sensitivity can be added later only as a
separately labeled, nonselective diagnostic.

### 6.5 Recommended design

Run only the 21 missing final cells. This satisfies source completeness,
preserves prior decisions, and keeps the article fixture out of selection.

## 7. Frozen Score Contract

The final packet must use a new Phase180 contract derived from, but not
silently coupled to, the Phase178 source-count fields in
`joint_qdesn_post_phase178_dgp_score_contract_v1.csv`.

### 7.1 Quantile grid and quadrature

The current fitted grid is:

```text
0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95
```

The trapezoidal weights applied to `QS_tau = 2 * rho_tau` are:

```text
0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025
```

They sum to 0.90 and are not renormalized. The internal primary metric remains
`dgp_integrated_acrps`; the article-facing term is **DGP-integrated finite-grid
quantile score**, shortened after definition to **DGP-integrated score**.

Do not call this exact continuous CRPS, WIS, or the CRPS of a scalar posterior
predictive density. The existing realized score against held-out observations
remains **realized aCRPS** and is secondary.

### 7.2 Reported posterior summaries

For every model-scenario cell report:

- posterior mean DGP-integrated score;
- posterior median DGP-integrated score;
- equal-tailed 2.5% and 97.5% posterior quantiles;
- score of the canonical monotone posterior-mean quantile action;
- score-functional rank R-hat, bulk ESS, tail ESS, and MCSE;
- realized aCRPS as compatibility evidence;
- check loss by tau;
- fit and forecast oracle quantile MAE/RMSE;
- raw crossing rate, magnitude, and monotone-adjustment burden;
- contract crossing count, which must be zero.

The posterior interval is uncertainty in the score induced by the posterior
quantile-path distribution conditional on the fitted data. It is not a
replacement for the protected-replicate evidence used in Phase179.

### 7.3 Coupling and contrasts

- Joint rows preserve retained within-draw cross-quantile dependence.
- Independent rows use the frozen seeded, within-chain, per-tau product-
  posterior permutation.
- Each independent score must pass pairing-seed sensitivity.
- Joint-minus-independent score contrasts are constructed separately within
  each likelihood and scenario using a frozen within-chain scalar-score
  product coupling.
- Report contrast mean, median, 95% interval, and
  `Pr(score_joint - score_independent < 0)`.
- Do not treat nonoverlap of marginal score intervals as a formal superiority
  test.

### 7.4 Canonical action and monotonicity

Preserve raw quantile paths. Apply the declared rowwise isotonic contract to
each posterior draw before score calculation. The canonical action remains
the monotone posterior-mean-parameter quantile path. Raw crossings are
diagnostic; nonzero contract crossings are a hard failure.

## 8. Production MCMC Contract

### 8.1 exAL completion budget

Run the five final exAL cells with the Phase172-compatible budget:

```text
8 chains per cell
24,000 iterations per chain
4,000 burn-in iterations
thin = 4
exact M0
structured-VB initialization
```

This yields 5,000 retained parameter draws per chain before deterministic
score reduction.

### 8.2 AL completion budget

Run the 16 AL cells with:

```text
8 chains per cell
8,000 iterations per chain
2,000 burn-in iterations
thin = 4
structured-VB initialization
```

The AL rows do not contain the gamma block that motivated the 24,000-iteration
M0 budget. This budget yields 1,500 retained draws per chain and is sufficient
for the frozen selection of 1,000 evenly spaced score draws per chain. Eight
chains permit rank-normalized and chain-allocation diagnostics while avoiding
an unnecessary threefold AL compute increase.

### 8.3 Uniform score reduction

For every one of the 32 final cells, select exactly 1,000 equally spaced
retained draws from each of eight chains. Every reported posterior score
summary therefore uses 8,000 chain-balanced score draws, even though the
underlying sampler budgets differ by likelihood complexity.

### 8.4 Predeclared convergence escalation

This is a production campaign, not a pilot. A cell that fails only the score-
functional convergence thresholds is not retuned. It enters a deterministic
same-specification extension tier:

- AL: rerun the affected cell at 24,000/4,000/4 with eight chains;
- exAL: rerun the affected cell at 48,000/8,000/8 and, if required by the
  frozen diagnostics rule, 16 chains;
- controls, fixture, quantile grid, and prior remain unchanged;
- the original failed functional packet remains retained and labeled;
- no metric value may determine whether DESN or `tau0` changes.

The exact escalation thresholds must be copied into the Phase180 contract
before launch. Preferred score-functional thresholds are rank R-hat <= 1.05,
bulk ESS >= 400, and tail ESS >= 200.

### 8.5 Parallel execution

Use one R process and one BLAS thread per chain worker. Use the existing JOINT
CPU lease/queue mechanism rather than competing with unrelated active lanes.
The launcher must be completion-aware and idempotent:

- skip only workers with a verified manifest;
- quarantine or fail closed on malformed partial directories;
- write per-worker exit metadata;
- never aggregate before all required workers complete;
- publish final directories atomically;
- allow safe resumption after interruption without rerunning verified workers.

The frozen compute plan should target 32-48 concurrent workers only when the
CPU lease confirms capacity. Worker count is an operational setting, not a
scientific control.

## 9. Implementation Architecture

Before using script numbers, recheck the latest `origin/main`. At the audit
checkpoint, 268 onward were available.

### 9.1 Preferred new module

Add:

```text
application/R/joint_qdesn_phase180_balanced_dgp_score_packet.R
```

It should provide small adapters for:

- final 32-cell source registry construction;
- row-level Phase174/Phase179 lineage reconciliation;
- Phase172 draw-source verification;
- 21-cell rerun planning;
- generic AL and exact-M0 exAL chain checkpointing;
- final source collection;
- 32-cell score reconstruction;
- joint-independent contrast construction;
- article staging and frozen handoff.

Reuse the score mathematics in
`application/R/joint_qdesn_dgp_integrated_acrps.R`. Do not duplicate expected-
loss formulas, isotonic rearrangement, coupling rules, or score diagnostics.

### 9.2 Configuration

Add a versioned contract, for example:

```text
application/config/joint_qdesn_phase180_balanced_dgp_score_contract_v1.csv
```

It must record the grid, weights, posterior summaries, score draw count,
coupling seeds, diagnostic thresholds, AL/exAL budgets, source policy, and
article terminology. Keep source-dependent counts in this Phase180 contract
rather than changing the historical Phase178 contract.

### 9.3 Scripts

Reserve a narrow sequence, subject to a filename-conflict check:

```text
268_prepare_joint_qdesn_phase180_balanced_score_packet.R
269_run_joint_qdesn_phase180_balanced_score_chain.R
270_check_joint_qdesn_phase180_balanced_score_completion.R
271_launch_joint_qdesn_phase180_balanced_score_completion.sh
272_finalize_joint_qdesn_phase180_balanced_score_packet.R
273_stage_joint_qdesn_phase180_article_assets.R
274_freeze_joint_qdesn_phase180_integration_handoff.R
```

The preparation script must not launch. It must first write and verify the
source registry, fixture identity, control hashes, chain/component seeds,
worker plan, compute budget, and expected manifests.

Preparation caches each compact VB initializer separately. Reuse requires a
valid SHA-256 manifest and exact agreement on code commit, frozen control-row
hash, and fixture-manifest hash. This cache stores no fitted R workspace and
exists only to make a late preparation failure resumable without weakening the
frozen initialization controls.

The independent-AL starts are reconstructed from the manifest-verified
Phase154 VB quantile paths, intercept means, and scale means under the same
case-specific controls. Coefficient means are recovered against the frozen
design by rank-aware least squares; aliased coefficients use a finite zero
representative. The result is accepted only when it reproduces the retained raw
VB quantile path within a relative numerical tolerance of `1e-8`. This avoids
treating a numerically invalid duplicate VB refit as evidence against the
already frozen independent-AL specification.

The chain runner must preserve compact posterior parameter draws in
`checkpoint/posterior_draws.csv.gz`; no `.RData` or `.rds` model object is
required. Worker manifests must hash the checkpoint metadata, draws, sampler
diagnostics, runtime, provenance, and README.

### 9.4 Files that should not change

Do not modify:

- the Phase178 or Phase179 frozen artifacts;
- the M0 mathematical kernel unless an isolated correctness defect is found;
- Phase154, Phase172, Phase173B, or Phase174 historical outputs;
- PriceFM, GloFAS, TT500, or unrelated QDESN workflows;
- `main.tex`, article tables, figures, or PDFs before Phase180 passes;
- `origin/main` or Overleaf branches from the scientific lane.

Legacy scripts 257--260 must not be run unchanged because their article-
fixture decision is forecast-MAE centered. Low-level fixture and exact-M0
helpers may be reused only through the new frozen score-centered adapter.

## 10. Frozen Artifacts

### 10.1 Preparation freeze

The freeze directory should contain at least:

- `phase180_score_contract.csv`
- `final_selected_cell_registry.csv`
- `source_reuse_inventory.csv`
- `rerun_cell_plan.csv`
- `worker_plan.csv`
- `chain_seed_plan.csv`
- `component_seed_plan.csv`
- `fixture_identity_audit.csv`
- `control_hash_audit.csv`
- `source_manifest_verification.csv`
- `compute_budget.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

The final selected registry must contain exactly 32 unique
`scenario_id x model_id` rows, exactly 11 reused rows, exactly 21 rerun rows,
and exactly 168 new chain workers.

### 10.2 Final score packet

The final audit should contain at least:

- `final_source_registry.csv`
- `source_manifest_verification.csv`
- `worker_health_summary.csv`
- `posterior_dgp_integrated_acrps_draws.csv.gz`
- `posterior_dgp_integrated_acrps_summary.csv`
- `canonical_action_dgp_integrated_acrps.csv`
- `dgp_integrated_score_by_tau.csv`
- `joint_independent_score_contrast_draws.csv.gz`
- `joint_independent_score_contrast_summary.csv`
- `realized_expected_score_comparison.csv`
- `oracle_recovery_diagnostics.csv`
- `raw_contract_crossing_summary.csv`
- `monotone_adjustment_summary.csv`
- `score_functional_mcmc_diagnostics.csv`
- `chain_allocation_sensitivity.csv`
- `independent_pairing_seed_sensitivity.csv`
- `parameter_block_diagnostics.csv`
- `runtime_summary.csv`
- `final_gate_assessment.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

### 10.3 Article staging packet

After the final score packet passes, stage:

- a 32-row scenario-model CSV;
- an eight-scenario article table whose entries are posterior mean
  DGP-integrated score with 95% credible interval;
- a compact winner/contrast summary;
- supplemental oracle MAE/RMSE and realized-aCRPS tables;
- crossing and adjustment provenance tables;
- table/figure source manifests;
- exact manuscript wording guidance;
- a Phase180 integration handoff.

Do not create a new main-text figure by default. The primary eight-scenario
table and the joint-minus-independent contrast summary are sufficient for the
current seven-level result. A dense-grid crossing figure belongs to the later
19-level study.

## 11. Gates

### 11.1 Hard fail

- source, control, fixture, seed, or output manifest mismatch;
- any missing or duplicated final cell;
- any missing required posterior draw checkpoint;
- nonfinite parameter draws, quantiles, DGP paths, or scores;
- train/forecast leakage or row/origin misalignment;
- invalid exact-M0 support;
- nonzero contract crossings;
- source-incomplete row represented as complete;
- article fixture used to change a Phase179 control;
- partial output published as final.

### 11.2 Targeted extension required

- score-functional rank R-hat, bulk ESS, or tail ESS outside the frozen
  thresholds;
- material chain-allocation sensitivity;
- material independent coupling-seed sensitivity;
- unstable canonical-action versus posterior score summaries.

These conditions trigger same-specification computation, not another DESN or
`tau0` screen.

### 11.3 Review

- alpha/intercept or trend mixing is weak while score/path functionals pass;
- raw crossing rate or monotone-adjustment burden exceeds its threshold;
- posterior mean, median, and canonical-action rankings differ;
- a numerical model winner has a small contrast or incomplete practical
  separation;
- runtime is an outlier.

### 11.4 Pass

- 32 unique source-complete rows;
- all required workers and manifests verify;
- 32 finite posterior score summaries and canonical scores;
- 16 finite joint-minus-independent contrasts;
- zero contract crossings;
- adequate score-functional diagnostics;
- complete provenance and hashes.

Poor model performance is scientific evidence, not an implementation failure.

## 12. Tests

Add one focused suite, for example:

```text
application/tests/test_joint_qdesn_phase180_balanced_dgp_score_packet.R
```

It must cover:

1. Phase174 contains exactly 32 unique article cells.
2. Phase179 contributes exactly five final case-specific decisions.
3. The source resolver selects exactly 11 Phase172 reuses and 21 reruns.
4. The three promoted controls and two retained parity controls match their
   frozen hashes.
5. All 128 Phase172 worker manifests verify before reuse.
6. Phase150/154 summary-only cells cannot masquerade as draw-complete.
7. The 168-worker plan has unique chain and component seeds.
8. AL and exAL worker checkpoints retain finite parameter draws.
9. Interrupted execution reuses only manifest-verified workers.
10. The seven-level grid and trapezoidal weights are exact and unrenormalized.
11. Joint reconstruction preserves draw identity.
12. Independent reconstruction uses the frozen product-posterior coupling.
13. Score chunk size and worker ordering do not change stable summaries.
14. Every final posterior score interval is finite and ordered.
15. Exactly 32 final rows and 16 within-likelihood contrasts are produced.
16. Contract crossings are zero; raw crossings remain visible.
17. Article winners are selected by posterior mean DGP-integrated score.
18. Article-facing labels distinguish DGP-integrated score from realized
    aCRPS and oracle MAE/RMSE.
19. All final and article-staging manifests verify by SHA-256.
20. Existing Phase155, Phase171-175, Phase176-180, postscore, and Phase179
    focused tests remain green.

No large production launch is part of the test suite.

## 13. Article Contract

Only after Phase180 passes:

1. headline the synthetic multi-quantile forecast comparison with the
   DGP-integrated finite-grid quantile score;
2. display posterior mean and 95% credible interval, retaining posterior
   median in provenance or supplement;
3. bold the lowest posterior mean within each scenario, while describing
   numerical winners as descriptive when contrasts are uncertain;
4. report the within-likelihood joint-minus-independent contrast and its
   probability of favoring the joint readout;
5. retain realized aCRPS and check loss as secondary forecast evidence;
6. describe fit/forecast MAE and RMSE as oracle quantile-path recovery
   diagnostics;
7. retain raw crossings as pre-contract coherence diagnostics and require
   zero reported-contract crossings;
8. do not claim a scalar posterior predictive density for the joint composite
   AL/exAL working likelihood.

The existing 32-row article source is valid historical evidence but still
headlines forecast oracle MAE. It must remain untouched until the new packet
is complete and hash-verified.

## 14. Dense-Grid Deferral

The future 19-level grid is:

```text
seq(0.05, 0.95, by = 0.05)
```

It changes the fitted models and must not be approximated by interpolating
the seven fitted paths. Begin it only after this current-grid packet and
article handoff close. It requires its own case-specific VB/VB-LD calibration,
MCMC qualification, grid-aware crossing opportunity rates, seeds, budgets,
and score contract.

The seven-level Phase180 packet remains the main current authority even after
dense-grid sensitivity work begins.

## 15. Git and Integration Boundary

- Work only on a dedicated JOINT branch from the latest `origin/main`.
- Use command-line Git.
- Push only the dedicated task branch.
- Do not merge or push `origin/main`.
- Do not modify `overleaf/article-snapshot` or `overleaf-direct/main`.
- Do not publish Overleaf from this scientific lane.
- Do not touch another lane's worktree, jobs, caches, or runtime artifacts.
- Keep all runtime caches, posterior checkpoints, and score workspaces ignored.
- Provide a frozen integration handoff with branch, upstream, full HEAD,
  merge-base relation, unique commits, exact files, run counts, manifests,
  hashes, tests, storage status, article-safe files, exclusions, risks, and
  recommended merge order.
- State `READY_FOR_INTEGRATION` only after the final handoff worktree is clean
  and exactly synchronized with its upstream.

## 16. Ordered Checklist

### Already complete

- [x] Preserve and close Phase178 under its original contract.
- [x] Freeze and test the seven-level DGP-integrated score engine.
- [x] Complete Phase179 fresh protected confirmation.
- [x] Freeze three case-specific promotions and two parity decisions.
- [x] Verify Phase179 manifests and diagnostics.
- [x] Integrate Phase179 into authoritative `main`.
- [x] Audit Phase174 source lineage against retained Phase172 draws.
- [x] Identify the exact 11 reusable and 21 missing final cells.

### Implementation, before launch

- [x] Add the Phase180 balanced packet module and versioned contract.
- [x] Add source-registry, chain-worker, health, finalizer, staging, and handoff
      scripts.
- [x] Add focused tests and run all adjacent JOINT tests.
- [ ] Freeze the 32-cell source registry and 21-cell rerun plan.
- [ ] Verify all reused Phase172 manifests.
- [ ] Freeze article fixture identity and all control-row hashes.
- [ ] Freeze globally unique chain and component seeds.
- [ ] Verify exactly 168 planned chain workers.
- [ ] Freeze the CPU lease and compute budget.
- [ ] Review the freeze before `--execute`.

### Production and closeout

- [ ] Launch the five final exAL cells and 16 AL cells.
- [ ] Monitor completion without inspecting metrics for retuning.
- [ ] Require 168/168 workers and zero failures, or invoke only the frozen
      completion-aware recovery path.
- [ ] Apply same-specification extension only where score-functional gates
      require it.
- [ ] Reconstruct all 32 final score cells.
- [ ] Produce 32 posterior summaries and 16 contrasts.
- [ ] Verify finiteness, zero contract crossings, diagnostics, and manifests.
- [ ] Freeze the Phase180 score packet.
- [ ] Stage article-safe tables and wording for integration review.
- [ ] Run focused tests and compile checks required by the integration handoff.
- [ ] Commit and push only the JOINT task branch.
- [ ] Leave merge and Overleaf publication to the integration coordinator.

### Later

- [ ] Freeze and implement the separate 19-level dense-grid study.

## 17. Immediate Next Action

The Phase180 module, versioned contract, resumable workers, completion-aware CPU
queue, finalizer, article staging, handoff, and focused tests are implemented.
All four sampler routes (joint and independent under AL and exact-M0 exAL) pass
a deterministic interface regression, and the adjacent Phase155, Phase171--180,
Phase179, post-Phase178 score, and article-asset tests pass. The next command
must prepare and validate the real freeze from committed code without launching.
Production execution begins only after the freeze proves:

- exactly 32 final cells;
- exactly 11 verified reuses;
- exactly 21 rerun cells;
- exactly 168 unique chain workers;
- correct case-specific controls;
- unchanged seven-level fixtures;
- complete, collision-free seed and source hashes.

There is no scientific reason to wait for another JOINT job, and there is no
scientific reason to launch another broad screen. The remaining work is a
bounded final-evidence completion campaign followed by deterministic scoring
and article staging.
