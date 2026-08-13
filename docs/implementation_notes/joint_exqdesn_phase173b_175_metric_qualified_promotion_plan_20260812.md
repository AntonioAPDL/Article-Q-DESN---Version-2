# Joint exQDESN Phase 173B-175 Metric-Qualified Promotion Plan

## Status and scope

This document is a plan, not an implementation record. It refines the
Phase 173-175 closeout after the complete Phase 172 exact-M0 campaign. It must
not alter the running Phase 173 process, its source code, its inputs, or its
atomic output. No article asset may be changed until the staged packet has been
reviewed explicitly.

The scope is limited to the 16 exAL cells in the balanced joint-QDESN
simulation study:

- eight article scenarios under Joint exQDESN RHS;
- the same eight scenarios under Independent exQDESN RHS;
- the frozen, case-specific DESN and RHS specifications from Phase 171;
- the exact `M0_v_collapsed_support_logit` MCMC transition selected before the
  article-fixture campaign.

The 16 AL cells remain frozen. This plan does not introduce another DESN
screen, another sampler-method contest, a denser quantile grid, or a full MCMC
rerun.

## Audit basis

At the time this plan was written:

| Evidence | Observed state | Interpretation |
|---|---:|---|
| Phase 172 top-level workers | 128/128 complete | No MCMC chains remain |
| Physical component runs | 512/512 complete | All joint and independent components exist |
| Worker manifests | 128/128 verified | Chain-level evidence is traceable |
| Phase 172 campaign manifest | 5/5 verified | Campaign packet is intact |
| Finite chain summaries | 128/128 | No chain-level numerical failure |
| Contract crossings | 0 | Reported monotone quantile-grid contract holds |
| Raw forecast crossings | 296 | All occur in three independent chains |
| Raw crossings in joint chains | 0/64 chains | Joint readout is raw-noncrossing on this grid |
| Phase 173 | running | Final pooled values and formal gates are not yet available |

The preliminary chain-average comparison is diagnostic only. It suggests that
M0 lowers forecast oracle-quantile MAE in approximately 5 of the 16 exAL cells
and lowers fit oracle-quantile MAE in all 16 cells. These counts must be
recomputed from the pooled Phase 173 artifact and must never be copied into an
article table from chain-level averages.

The M0 diagnostics also show the expected geometry:

- scalar gamma mixes more slowly away from the median;
- gamma and sigma remain strongly correlated at several quantile levels;
- the transformed, identifiable scale functional `actual_sd` generally mixes
  much better than gamma itself;
- first-four versus last-four chain quantile-path summaries are already much
  more stable than the scalar gamma traces suggest.

This evidence supports a functional rather than scalar-only readiness policy.

## Core decision

Suboptimal nuisance-parameter mixing must not automatically reject an otherwise
stable and improved article estimand. A case may be promoted with a documented
mixing qualification when all of the following hold:

1. source, manifest, fixture, seed, support, finiteness, and leakage checks pass;
2. the scored contract quantiles are finite and noncrossing;
3. beta/alpha readout coordinates and posterior quantile paths are stable enough
   under the predeclared chain partitions;
4. leave-one-chain-out and jackknife analyses show that the reported score is
   not controlled by one chain;
5. posterior mean, median, and trimmed-mean quantile summaries do not imply a
   materially different substantive conclusion;
6. any poor diagnostics are concentrated in gamma, bounded gamma probability,
   or sigma rather than in the reported quantile path or an identifiable scale
   functional;
7. the article-facing metric is computed from the frozen fixture and the same
   scoring contract as the historical row.

An improvement in a realized metric cannot override a broken implementation,
nonfinite output, a contract crossing, an unstable reported quantile path, or a
materially chain-dependent score.

## Avoiding an outcome-selection error

M0 was selected prospectively in Phase 170 as the production exAL transition.
The clean scientific packet therefore uses the accepted M0 result for every
functionally qualified exAL cell, whether its realized score improves or
worsens. Selecting M0 only when its test-window MAE is smaller, while retaining
the historical sampler whenever M0 is larger, would select between Monte Carlo
approximations using the reported outcome. That would exaggerate gains and is
not the recommended authoritative policy.

The requested metric-improvement rule is incorporated as follows:

- every functionally stable M0 case that improves the primary metric remains
  eligible even when scalar gamma/sigma mixing is review-level;
- such a case receives `promote_with_mixing_qualification` when nuisance mixing
  is the only unresolved diagnostic;
- functionally qualified M0 cases without an improvement remain in the
  method-consistent M0 packet and are reported honestly;
- a separate metric-improvement table identifies clear, directional, neutral,
  and worsened cases without controlling which valid M0 estimate is shown;
- a historical row is retained only when the M0 candidate is functionally held
  or rejected, not merely because its score is less favorable.

This policy guarantees that genuine improvements are promoted despite imperfect
scalar mixing while preserving a defensible, prospectively selected inference
method.

## Metric hierarchy

The hierarchy must be frozen before Phase 173 values are inspected for article
promotion:

1. Primary article metric: held-out forecast oracle-quantile MAE.
2. Co-primary scoring diagnostics: forecast check loss and grid-CRPS.
3. Fit diagnostic: fit-window oracle-quantile MAE.
4. Calibration diagnostics: hit-rate error and central-interval coverage.
5. Structural diagnostics: raw crossings, contract crossings, and monotone
   adjustment magnitude.

The primary improvement is

`delta = M0 forecast oracle-quantile MAE - historical forecast oracle-quantile MAE`.

Negative values favor M0. Full-precision values, not rounded table entries, must
be used. The same comparison must also be reported for fit MAE, check loss, and
grid-CRPS, but those secondary directions must not be silently combined into a
new post hoc score.

Improvement strength is descriptive:

- `clear_improvement`: `delta < 0` and the absolute gain exceeds twice the
  available M0 jackknife MCSE;
- `directional_improvement`: `delta < 0` but the gain is within twice the
  available M0 jackknife MCSE;
- `no_material_change`: the full-precision difference is numerically negligible
  under a versioned tolerance;
- `worsened`: `delta > 0` outside that tolerance.

Because a comparable historical jackknife MCSE may be unavailable, these labels
must be described as Monte Carlo sensitivity labels, not formal significance
tests.

## Revised gate hierarchy

### Global packet integrity gate

Any of the following blocks all staging:

- missing or mismatched Phase 171, Phase 172, Phase 173, baseline, or article
  asset hashes;
- fewer than 16 unique exAL cells or fewer than eight chains per cell;
- wrong fixtures, splits, controls, seeds, or inference-method identifiers;
- a malformed Phase 173 artifact or missing provenance.

### Cell implementation gate

The M0 candidate is rejected for that cell when it has:

- nonfinite posterior draws, quantiles, or scores;
- invalid exAL support or nonpositive scale;
- train/test leakage;
- any crossing in the contract quantile grid;
- missing or non-provided initialization;
- a scoring alignment failure.

### Functional stability gate

The M0 candidate is held when any of the following affects the reported
estimand materially:

- beta/alpha readout diagnostics are severe;
- first-four/last-four or odd/even quantile paths exceed the frozen tolerance;
- leave-one-chain-out forecast MAE exceeds the review ceiling;
- posterior mean, median, and trimmed-mean summaries change the substantive
  metric conclusion;
- jackknife MCSE or chain-to-pooled distance indicates that the apparent gain is
  generated by one chain;
- identifiable scale functionals such as `actual_sd` or `sigma_lambda` are
  unstable at multiple quantile levels and that instability propagates to qhat.

### Nuisance mixing qualification

The following do not by themselves block promotion when the functional gate
passes:

- gamma or bounded-gamma R-hat above the preferred threshold;
- gamma or sigma ESS below the preferred threshold;
- strong gamma-sigma posterior correlation;
- slow scalar exploration at isolated quantile levels;
- review-level raw crossings that disappear under the declared monotone
  contract, provided adjustment magnitude remains documented and acceptable.

These cases receive an explicit `mixing_review_accepted` flag and conservative
manuscript wording. They must not be described as fully converged in every
parameter.

## Decision taxonomy

Each of the 16 M0 cells receives exactly one action:

| Action | Required evidence | Article handling |
|---|---|---|
| `promote` | Hard and functional gates pass; supporting diagnostics pass | Use M0 row |
| `promote_with_mixing_qualification` | Hard and functional gates pass; only nuisance mixing is review-level | Use M0 row and retain qualification in provenance |
| `retain_historical_functional_hold` | M0 implementation is intact but reported functionals are unstable | Keep historical row; do not claim M0 improvement |
| `retain_historical_candidate_fail` | M0 cell has a cell-level hard failure | Keep verified historical row and disclose exclusion |
| `block_packet` | Global packet integrity fails | Do not stage or promote anything |

Metric direction is attached separately as `clear_improvement`,
`directional_improvement`, `no_material_change`, or `worsened`.

## Implementation sequence after Phase 173 finishes

### Stage 1: immutable Phase 173 closeout

1. Confirm the detached process exits with code zero.
2. Verify the complete Phase 173 SHA-256 manifest.
3. Confirm 16 cells, eight chains per cell, and 512 unique component seeds.
4. Copy no data and mutate no Phase 173 artifact.
5. Record the exact Phase 173 manifest hash as the sole pooled-audit source.

### Stage 2: Phase 173B decision audit

Add a small postprocessor rather than rerunning Phase 173. It should consume the
immutable Phase 173 artifact and the verified historical Phase 154/155 packet.

Planned artifacts:

- `promotion_policy.csv`;
- `case_promotion_decision.csv`;
- `historical_vs_m0_primary_metric.csv`;
- `historical_vs_m0_secondary_metrics.csv`;
- `nuisance_mixing_exception_audit.csv`;
- `functional_stability_audit.csv`;
- `posterior_summary_decision_audit.csv`;
- `winner_margin_mcse_audit.csv`;
- `retained_historical_cell_audit.csv`;
- `method_consistency_audit.csv`;
- `promotion_readiness_summary.csv`;
- `provenance.csv`;
- `artifact_manifest.csv`;
- `README.md`.

The decision table must include scenario, structure, historical and M0 values,
full-precision deltas, jackknife MCSE, scalar mixing status, functional status,
raw and contract crossings, action, rationale, and exact source hashes.

### Stage 3: Phase 174 method-consistent staging

Refactor staging to consume the Phase 173B decision artifact.

1. Preserve every AL row byte-for-byte.
2. Replace each eligible exAL row with its M0 result.
3. Permit `promote_with_mixing_qualification` without requiring ideal scalar
   gamma diagnostics.
4. Retain a historical exAL row only for a functionally held or rejected M0
   candidate.
5. Recompute winners from full precision after composing the 32-cell packet.
6. Produce explicit source-to-row lineage and old-versus-new differences.
7. Generate tables only in the ignored staging directory.
8. Verify that tracked article files remain unchanged.

Stage both of the following review tables:

- the authoritative method-consistent 32-cell packet;
- a 16-cell M0 diagnostic comparison showing metric direction and mixing
  qualification, which remains provenance or supplement material unless the
  manuscript needs it.

### Stage 4: human review before Phase 175

Review must cover:

- every case-level action and rationale;
- all metric-improving cases, especially those using a mixing qualification;
- all worsened M0 cases, so the article does not imply uniform improvement;
- winner changes and whether margins exceed available Monte Carlo error;
- raw versus contract crossing language;
- posterior-quantile-grid interpretation rather than scalar predictive-density
  claims;
- table captions and manuscript prose;
- a clean LaTeX compile from the authoritative article repository.

### Stage 5: explicit Phase 175 promotion

Only after explicit user approval:

1. verify the staging manifest again;
2. promote only allow-listed table assets atomically;
3. verify target hashes after copying;
4. update manuscript wording surgically if the staged values require it;
5. compile twice and inspect warnings, references, table placement, and PDF;
6. write a promotion manifest and rollback map;
7. commit and push only the related files when explicitly requested.

## Targeted rescue policy

No rescue is launched merely because scalar gamma mixing is imperfect. A rescue
is considered only for a cell that fails the functional stability gate and for
which the instability could plausibly alter the article conclusion.

Any rescue must:

- use the exact frozen fixture, DESN/RHS controls, and M0 transition;
- use new, globally unique seeds;
- remain a separate posterior packet;
- never concatenate rescue draws with the primary deterministic prefix;
- be compared through qhat stability and metric MCSE, not gamma ESS alone;
- be explicitly approved before launch.

A full 128-chain rerun is not part of this plan.

## Planned code and documentation changes

No code change is authorized by this planning step. When implementation is
requested, the expected narrow changes are:

- `application/R/joint_exqdesn_phase171_175_article_confirmation.R`
  - add the post-audit decision classifier;
  - separate nuisance mixing from functional instability;
  - let Phase 174 consume explicit row actions;
- `application/config/joint_exqdesn_phase173b_promotion_policy_v1.csv`
  - version the metric hierarchy, tolerances, and action contract;
- `application/scripts/238_audit_joint_exqdesn_phase173b_metric_qualified_promotion.R`
  - generate the decision artifact without rerunning Phase 173;
- `application/scripts/237_build_joint_qdesn_phase174_article_assets_staging.R`
  - accept and verify the Phase 173B artifact;
- `application/tests/test_joint_exqdesn_phase171_175_article_confirmation.R`
  - add focused classifier and staging tests;
- this implementation note and the Phase 174/175 generated README files.

The MCMC kernels, exAL density, VB implementation, QDESN workflows, PriceFM,
GloFAS, and unrelated article sections must not change.

## Required tests

- scalar gamma-only review plus stable qhat yields
  `promote_with_mixing_qualification`;
- unstable qhat cannot be overridden by improved forecast MAE;
- nonfinite output or contract crossings reject the M0 cell;
- full-precision negative primary delta receives the correct improvement label;
- directional improvements within available MCSE remain promotable but are
  labeled as uncertain;
- a worsened but functionally qualified M0 cell remains in the method-consistent
  packet;
- a functionally held M0 cell retains exactly one verified historical row;
- all 16 AL rows are unchanged;
- the final packet contains exactly 32 unique cells;
- row lineage identifies one source and one manifest hash per row;
- repeated deterministic postprocessing produces stable hashes except for
  explicitly excluded timestamps;
- staging cannot modify tracked article assets;
- Phase 175 still requires `approved=TRUE` and the exact allow-list;
- existing Phase 171-175 and adjacent M0 dispatch tests continue to pass.

## Stop conditions

Stop and request review before any article staging if:

- Phase 173 exits nonzero or its manifest fails;
- any global packet-integrity requirement fails;
- the primary metric cannot be aligned exactly between historical and M0 rows;
- a case appears improved only after rounding;
- posterior summary choice reverses the improvement direction materially;
- source lineage cannot identify the exact fixture, control, and chain packet;
- the implementation would require changing model specifications or rerunning
  AL rows.

## Checklist

### Before implementation

- [x] Phase 172 completed 128/128 workers and 512/512 components.
- [x] Phase 172 worker and campaign manifests verified.
- [x] Preliminary chain-level finiteness and crossing diagnostics audited.
- [x] Current Phase 173 process left untouched.
- [x] Current all-or-nothing Phase 174 behavior identified.
- [x] Metric selection versus method consistency risk documented.
- [ ] Phase 173 exits successfully and publishes its atomic artifact.
- [ ] Phase 173 manifest and all 16 case gates are audited.

### Implementation, only after user approval

- [ ] Add and validate the versioned Phase 173B policy.
- [ ] Implement the deterministic case-decision classifier.
- [ ] Add the Phase 173B postprocessor and artifact manifest.
- [ ] Add nuisance-mixing exception and functional-stability tests.
- [ ] Refactor Phase 174 to consume explicit row actions.
- [ ] Produce the method-consistent staged packet and metric audit.
- [ ] Review all improved, worsened, retained, and qualified cases.
- [ ] Verify tracked article assets remain unchanged.
- [ ] Request explicit approval for Phase 175.
- [ ] Promote atomically, compile, verify, document, and publish only after
  approval.

## Recommended next action

Wait for the currently running Phase 173 audit. Do not launch another MCMC job.
After Phase 173 completes, implement only the Phase 173B deterministic decision
layer, inspect its 16 case-level actions, and then decide whether Phase 174
staging is ready. This is the shortest path that honors the improved cases,
accepts nonideal nuisance mixing when the article estimand is stable, and avoids
another expensive or outcome-selected simulation campaign.
