# Joint QDESN Phase 155: Article Promotion from Final Validation Evidence

## Purpose

Phase 155 is the article-integration stage for the completed joint QDESN
validation workflow. It does not fit another model. It verifies and combines:

- Phase 153: 1,600 independent VB/VB-LD fits over 400 fresh synthetic
  fixtures, with 50 replicates for each of 32 scenario-model cells;
- Phase 154: the balanced 32-cell, exact-control, article-grade MCMC
  confirmation packet.

The stage replaces article assets that still reflected the older Phase 125
packet. It preserves the manuscript's posterior-quantile-grid predictive
contract and keeps raw crossings as diagnostics rather than scored outputs.

## Audit Findings

The Phase 154 final packet is complete:

- 32 of 32 scenario-model cells are present;
- all 32 use the Phase 153 frozen scenario-specific controls;
- all 32 satisfy the predeclared MCMC effort tier;
- all source and final manifests verify;
- all retained draws and reported scores are finite;
- all case-level implementation, distance, and chain gates pass;
- the monotone contract quantile grids have zero forecast crossings.

Ten cells retain review labels because of raw pre-contract crossings or an
isolated VB initializer reaching its iteration limit. These are not
implementation failures and do not affect the scored monotone grids.

The Phase 154 scenario-level forecast-MAE winners are:

- Joint QDESN RHS: Gaussian-mixture bridge, Laplace bridge, nonlinear
  reservoir-friendly dynamics, and normal bridge;
- Independent QDESN RHS: regime shift and Student-t location-scale;
- Independent exQDESN RHS: asymmetric-Laplace tail and persistent heavy tail;
- Joint exQDESN RHS: no forecast-MAE wins in this frozen eight-scenario packet.

Joint QDESN RHS has the lowest fit-window MAE in six scenarios. Independent
exQDESN RHS has the lowest fit-window MAE in the asymmetric-tail and
persistent-heavy-tail scenarios. Raw forecast crossings total 25: 24 from the
independent AL readout and one from the joint AL readout. Both exAL readouts
are raw-crossing free in this packet.

Phase 153 provides the generalization check. Its paired fresh-fixture
comparisons show that the frozen AL specifications have lower median forecast
quantile-path MAE than their exAL counterparts in the scenarios considered.
That replicated result prevents the single-fixture MCMC winner pattern from
being interpreted as universal model superiority.

## Design Decision

The optimal article update is therefore:

1. Use the Phase 154 scenario table as the main MCMC evidence.
2. Keep MCMC results scenario-specific rather than averaging away mechanism
   heterogeneity.
3. Retain Phase 153 only as a compact supplementary robustness table.
4. State that Joint QDESN RHS is the principal joint-readout reference because
   it combines strong fit recovery with minimal raw forecast crossings.
5. Present exQDESN as a fully evaluated extension, not as a universally better
   model and not as an invalid sampler result.
6. Avoid a new figure: the scenario table communicates the winner pattern and
   crossing diagnostic more directly and without redundant encoding.
7. Do not launch additional MCMC solely to promote the article. Additional
   simulation would address a new scientific question, not repair incomplete
   Phase 154 computation.

## Implementation

Phase 155 adds:

- `application/R/joint_qdesn_phase155_article_promotion.R`;
- `application/scripts/187_build_joint_qdesn_phase155_article_assets.R`;
- `application/scripts/188_audit_joint_qdesn_phase155_article_assets.R`;
- `application/tests/test_joint_qdesn_phase155_article_promotion.R`.

The builder verifies the Phase 153, Phase 154, and nested MCMC source
manifests before writing any article table. It enriches the frozen Phase 154
case summary with source grid-CRPS, hit-rate, and chain-to-pooled quantile-grid
diagnostics. It then writes:

- the scenario-level main MCMC table;
- the long 32-cell source table;
- protocol and gate tables;
- per-scenario metric winners;
- the Phase 153 paired AL-minus-exAL robustness table;
- article-claim and promotion audits;
- SHA-256 manifests and provenance.

## Commands

Focused regression:

```bash
Rscript application/tests/test_joint_qdesn_phase155_article_promotion.R
```

Build article assets:

```bash
Rscript application/scripts/187_build_joint_qdesn_phase155_article_assets.R
```

Audit manuscript and generated assets:

```bash
Rscript application/scripts/188_audit_joint_qdesn_phase155_article_assets.R
```

Compile:

```bash
latexmk -pdf -interaction=nonstopmode -halt-on-error \
  -outdir=local_trackers/codex_compile_phase155 main.tex
```

## Gates

Hard failure:

- any missing or mismatched source hash;
- a missing or duplicated scenario-model cell;
- a control mismatch from the Phase 153 freeze;
- MCMC effort below the model-specific tier;
- nonfinite draws or scores;
- missing VB/VB-LD initialization;
- any crossing in the scored contract quantile grid;
- a failed implementation, distance, or chain gate.

Review:

- raw crossings before the monotone reporting rule;
- a VB initializer reaching its iteration limit while retaining finite MCMC
  output;
- scientific underperformance of a model under a scenario.

## Interpretation Boundary

The promoted evidence validates conditional quantile paths and their monotone
reported grids using oracle MAE, check loss, grid CRPS, hit-rate diagnostics,
and crossing diagnostics. It does not validate a unique scalar response
predictive density obtained from the composite AL or exAL working likelihood.
