# GloFAS FR09 Authoritative Full-Seven Promotion

Date: 2026-08-11

## Decision

The user reviewed the full-seven figures and approved
`fr09_persistence_innovation` as the current authoritative GloFAS reference
case. The promotion reuses the seven completed component fits; it does not
refit any quantile model.

The authoritative component registry is tracked at
`tables/glofas_application_authoritative_component_registry__glofas_fr09_authoritative_full7_20260811.csv`.
It records one immutable fit and design hash for each of the quantile levels
0.05, 0.15, 0.35, 0.50, 0.65, 0.80, and 0.95. The corresponding integrity
audit must pass before synthesis or promotion.

## Model Contract

The application uses separate deterministic DESN feature maps for the
reference and discrepancy readouts. Both maps use `D = 1`, `n = 300`, no
inter-layer reducer, memory 360, washout 500, leak rate 0.1, spectral radius
0.95, recurrent inclusion probability 0.03, input inclusion probability 1,
and global/bias input scales 0.18. Their seeds are 20260512 and 20261521,
respectively.

The reference and discrepancy coefficient blocks have separate
regularized-horseshoe global scales, 0.1 and 0.001. The discrepancy forecast
uses the persistence-anchored innovation transition. The seven AL models are
fit independently by VB-LD and combined only at the reporting stage. No
reporting-time spread calibration is applied.

## Synthesis Contract Repair

The first synthesis attempt exposed a model-identity defect: quantile-specific
fit identifiers were treated as distinct models, so each apparent model had
only one quantile. Synthesis now maps source fit identifiers to one canonical
raw-GloFAS model and one canonical Q-DESN model before monotone processing.
The new `synthesis_model_grid_audit.csv` gate requires every
model/origin/target/horizon group to contain all seven requested quantiles.

The corrected synthesis contains exactly two models and 28 complete
seven-quantile forecast groups per model. Q-DESN has three pre-monotone
crossings, with maximum magnitude 0.0525, and no post-monotone crossings.
Raw GloFAS has no crossings in this forecast window.

## Evidence

Across 12,495 observed dates through the forecast origin, the monotonized
Q-DESN grid has mean quantile-grid CRPS 0.0445 and 90% interval coverage
0.906. In the 28-day held-out forecast window, the promoted summaries are:

| Model | Mean check loss | 90% interval score | Quantile-grid CRPS | 90% coverage |
|---|---:|---:|---:|---:|
| Q-DESN calibration | 0.5654 | 10.8032 | 1.1319 | 0.357 |
| Raw GloFAS | 0.7639 | 25.2028 | 1.4424 | 0.000 |

The corresponding Q-DESN reductions are 26.0% for mean check loss, 57.1%
for interval score, and 21.5% for quantile-grid CRPS.

The retrospective upper-tail audit flags occasional extreme fitted values in
the 0.95 path. The approved registry therefore marks that component as
authoritative for the current reference case but eligible for targeted
replacement. A future repair must replace only the affected registry row,
verify its fit and design hashes, and rerun synthesis and diagnostics. The
other six component fits must not be refit merely to repair the upper tail.

## Promoted Outputs

The stable manuscript aliases are generated in
`tables/glofas_application_current_outputs.tex`. The selection manifest hashes
the current aliases, score table, figures, model specification, component
registry, promotion decision, integrity audit, and observed-history ranking.

The promotion includes independent and monotonized forecast quantiles,
raw-GloFAS quantiles, discrepancy-identity checks, the observed-history audit,
the forecast score tables, and all diagnostic PDFs. Posterior draw payloads and
fit objects remain outside Git; they are referenced by immutable hashes in the
component registry.

## Reproduction

The synthesis source manifest maps each quantile-specific fit identifier to a
canonical synthesis model identifier. Run
`application/scripts/10_synthesize_glofas_quantile_runs.R`, followed by
`application/scripts/12_generate_glofas_quantile_diagnostics.R`. The no-refit
cutoff-context stage is then generated with
`application/scripts/22_make_glofas_authoritative_context_figures.R`. It
validates and plots the final 60 observed dates, the 28 issued forecast dates,
and the complete 51-member GloFAS ensemble. Its compact 60-by-7 historical
quantile source is promoted with the packet, so regeneration does not depend on
the 42 MB recovery table or its former worktree.

Promote with `application/scripts/21_promote_glofas_synthesis_outputs.R`,
passing
`--context_run_id glofas_fr09_authoritative_full7_20260811_context60_members`.
Finally run
`application/scripts/09_select_application_outputs.R` against the generated
promotion manifest.

Promotion is allowed only when synthesis readiness, the complete-grid audit,
discrepancy-identity checks, diagnostic readiness, component integrity, tests,
and manuscript compilation pass.

## Validation

The promotion contains 79 tracked outputs; all 79 promoted SHA-256 hashes match
their source hashes and no required destination is missing. All seven synthesis
readiness checks, all six diagnostic readiness checks, and all five
discrepancy-identity checks pass. The complete-grid audit contains two models,
28 forecast groups per model, and seven quantiles per group. All 24 promoted
PDF rows pass structural inspection. All 13 cutoff-context
checks pass, including exact cutoff alignment, complete historical and forecast
quantile grids, 51 members at each of 28 targets, and agreement between the
direct member median and the stored raw-GloFAS median.

The focused application-output registry and quantile-grid regression tests
pass. The unmodified full application suite is currently blocked by two
pre-existing external validation-state drifts:

- the configured shared-validation engine expects commit f4956ddd, while its
  active checkout is at 67c2dd84;
- after excluding only that engine assertion, the suite reaches a
  shared-validation fixture that expects 18 promoted rows but reads a
  differently sized current packet.

Neither failure is in the GloFAS promotion code, and no validation-study or
engine files were changed to suppress them.

The latexmk utility is unavailable. The documented fallback of pdflatex,
bibtex, and repeated pdflatex passes produced a 40-page main article and a
39-page supplement. Final log scans contain no LaTeX errors, undefined
references, undefined citations, rerun warnings, overfull boxes, or underfull
boxes. The Git whitespace check also passes.
