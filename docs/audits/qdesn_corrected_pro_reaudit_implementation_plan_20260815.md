# Corrected PRO Reaudit: Implementation Audit and Plan

Date: 2026-08-15
Branch: `integration/corrected-pro-reader-revision-20260815`
Starting commit: `60fe289e8586078a9cc6c939ee3877a498acfadf`
Starting tree: `1a308c1a4ba9fda1542d0cb4d2b3888f9dc47494`

## Authority

This implementation starts from the recovered Article-v2 main branch, not from
the damaged `c1451d0` projection merge and not from an article-only Overleaf
tree. The corrected PRO packet was uploaded under ignored local trackers and
verified before this plan was written:

- `QDESN_CORRECTED_FULL_AUDIT_AND_RECOMMENDATIONS.md`;
- `QDESN_CORRECTED_CLAIM_EVIDENCE_MATRIX.csv`;
- `QDESN_CORRECTED_IMPLEMENTATION_PROMPT_AND_PLAN.md`.

The claim matrix has 71 material rows: 19 verified source defects, 22 verified
evidence limits, 7 proposed new scientific-work items, and 23 editorial
recommendations. Proposed new scientific work is not part of this manuscript
correction pass unless separately authorized.

## Diagnosis

The revised audit identifies a manuscript-and-packaging problem rather than a
failed scientific project. The supported contribution is a Bayesian quantile
readout on a fixed deep echo-state-network feature map. The current source
sometimes describes broader objects than the implementation reports:

1. forecast-origin marginal quantiles are defined early, but key algorithms and
   applications report path- or draw-conditional readout summaries;
2. independent quantile levels are summarized and isotonic-projected as a point
   grid, not combined into a joint posterior quantile curve;
3. the score historically called grid CRPS is a finite-grid trapezoidal
   integrated pinball score;
4. selected GloFAS FR09 uses a persistence-anchored discrepancy innovation,
   not the older empirical-ensemble-minus-latent-reference recursion described
   in parts of the manuscript;
5. GloFAS and PriceFM are retrospective application studies with restricted
   information sets and should not be described as broad operational
   calibration evidence;
6. exAL retains exact AL nesting at `gamma = 0`, but its map is only branchwise
   smooth there for nonmedian quantile levels;
7. repository packaging still contains a stale arXiv builder and a stale
   tracked `main.pdf`.

These are source and claim-alignment defects. They can be fixed without changing
promoted numerical evidence.

## Route Decision

This pass adopts the low-risk readout-focused route. The article target is a
Bayesian conditional-quantile readout under a declared fixed-reservoir and
history-propagation contract. Forecast-origin marginal predictive quantiles are
reserved for a future method that explicitly forms a response-level marginal
predictive distribution.

Working title:

`Bayesian Quantile Readouts for Deep Echo State Networks`

## Implementation Phases

1. Record the authority, terminology contract, and claim ledger.
2. Add semantic tests for aCRPS, readout summaries, isotonic reporting, and exAL
   branchwise regularity.
3. Correct the main article target, title, abstract, contribution hierarchy,
   prediction terminology, simulation scope, GloFAS scope, PriceFM scope, and
   discussion.
4. Correct the supplement so it verifies the main article: branchwise exAL
   regularity, independent-grid point summaries, selected GloFAS FR09 contract,
   aCRPS, and retrospective PriceFM information sets.
5. Update application-facing labels from grid CRPS to aCRPS while preserving
   backward-compatible internal column names where frozen artifacts depend on
   them.
6. Refresh README and documentation authority maps so current FR09/PriceFM
   records are not confused with historical candidates.
7. Replace the hand-maintained arXiv source builder with a manifest-derived
   source packager.
8. Verify the article dependency manifest after TeX edits and rebuild tracked
   `main.pdf` from the final source.
9. Run focused tests, isolated TeX builds, source-bundle builds, and Git gates.

## Non-Campaign Boundary

This pass does not launch simulations, MCMC/VB refits, GloFAS multi-origin
studies, PriceFM operational reruns, learning-rate experiments, or new
posterior-predictive methods. Those remain deferred scientific work.

## Acceptance Gates

- `git diff --check` passes;
- no protected worktree, cache, tmux session, or old-repo runtime root is
  modified;
- all P0 verified source defects are corrected or explicitly deferred;
- every article-facing use of predictive, posterior predictive, calibration,
  coherent, and CRPS/aCRPS names the right object;
- focused aCRPS, synthesis, exAL, GloFAS, and PriceFM contract tests pass;
- main and supplement compile in isolated temporary directories;
- the article manifest matches the final TeX closure;
- the arXiv/source bundle compiles both entry points in isolation;
- no absolute local path or credential enters tracked source;
- the release commit records source corrections, documentation updates, tests,
  packaging, and deferred-science boundaries as one auditable revision;
- updates are pushed with command-line Git only.

## Implementation Disposition

The implemented route closes source defects and evidence-scope issues by
renaming the scientific object, relabeling finite-grid scores as `aCRPS`,
scoping the simulation and application evidence, and wiring semantic tests
around the selected GloFAS and PriceFM contracts. Rows classified as proposed
new scientific work remain deferred in
`docs/audits/qdesn_corrected_claim_ledger_20260815.csv`; no new campaign was
started and no promoted numerical result was recomputed.
