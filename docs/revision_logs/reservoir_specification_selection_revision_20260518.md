# Reservoir Specification Selection Revision, 2026-05-18

## Scope

This revision expands the manuscript's forecast evaluation section into a
practitioner-facing protocol for Q--DESN reservoir specification selection.
The selected reservoir is described as a reproducible feature-generation rule,
not as a posterior parameter.

## Manuscript Changes

- Renamed Section 7 to "Forecast Evaluation and Reservoir Specification
  Selection."
- Added a definition of the selected reservoir specification \(\mathcal R\).
- Added literature-grounded guidance on reservoir size, leak rate, spectral
  radius, input scaling, depth, and echo-state stability diagnostics.
- Added a table classifying reservoir components by statistical role,
  recommended selection treatment, and diagnostic risk.
- Added a staged selection protocol: lock forecast-origin design, run design
  gates, search primary reservoir parameters, score candidates on shared
  validation origins, refit top candidates across seeds, and freeze the final
  specification before held-out evaluation.
- Added explicit guardrails against choosing a single lucky seed, treating
  \(\rho_d < 1\) as a complete stability guarantee, or claiming global
  architecture optimality from one validation design.

## Citation Changes

Added references for leaky-integrator ESN time-scale control, echo-state
property diagnostics, and DeepESN design:

- Jaeger, Lukoševičius, Popovici, and Siewert (2007)
- Yildiz, Jaeger, and Kiebel (2012)
- Gallicchio, Micheli, and Pedrelli (2018)

Second-pass ESN performance audit added citations for principal-neuron
reinforcement, state feedback, similar-dynamics pruning, statistical remedies,
and systematic ESN design review:

- Fan, Wang, and Jin (2017)
- Wu, Fokoue, and Kudithipudi (2018)
- Sun, Song, Cai, Zhang, Hong, and Li (2024)
- Ehlers, Nurdin, and Soh (2025)
- Saadat, Farshad, Eliasi, and Shokoohi Mehr (2025)

The 2020 ESN review preprint was added to `refs.bib` for source completeness,
but the published 2024 review is the preferred main-text citation.

## Style Checks

The revision follows the repository writing profile by separating reservoir
selection from posterior inference, tying recommendations to statistical roles
and diagnostics, and avoiding unsupported optimality or superiority claims.

Follow-up style polish tightened Section 7 by:

- replacing generic transition language with task-dependent design statements;
- making the design-gate diagnostics explicit without adding unsupported claims;
- clarifying that state feedback and principal-neuron reinforcement alter the
  feature-generation rule and therefore belong to future validation protocols;
- reducing repeated "should" phrasing in favor of direct reporting and selection
  requirements.

## Open Empirical Items

- A completed application model-selection run is still needed before the paper
  can claim an application-selected final reservoir specification.
- Seed sensitivity should be reported for any final selected architecture.
- State-matrix diagnostics should be reported for any final selected
  architecture, including state redundancy, effective rank, covariance or
  singular-value spectrum, and condition-number or eigenvalue-spread summaries.
- Calibration claims should remain tied to empirical coverage, interval scores,
  CRPS, and PIT diagnostics when those outputs are available.
