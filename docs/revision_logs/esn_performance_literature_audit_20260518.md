# ESN Performance Literature Audit, 2026-05-18

## Scope

This note audits six newly added local PDFs under `literature/pdfs/` and records
how they should influence the Q--DESN reservoir specification and selection
section. The PDFs are local-only source material because `literature/` is ignored
by git; manuscript-facing claims are carried through `main.tex` and `refs.bib`.

## Source Map

| Local PDF | Citation key | Article role |
|---|---|---|
| `Performance_optimization_of_echo_state_networks_through_principal_neuron_reinforcement.pdf` | `FanWangJin2017PNR` | Reservoir adaptation after an initial readout fit |
| `2312.15141v2.pdf` | `EhlersNurdinSoh2025StateFeedback` | State-feedback enrichment of a fixed ESN |
| `s43069-025-00514-0.pdf` | `SaadatFarshadEliasiShokoohiMehr2025OnlineESN` | Similar-dynamics pruning and eigenvalue-spread diagnostics |
| `1802.07369v1.pdf` | `WuFokoueKudithipudi2018StatisticalChallengesESN` | Seed variability, weight distributions, perturbations, and ensembles |
| `A_Systematic_Review_of_Echo_State_Networks_From_Design_to_Application.pdf` | `SunEtAl2024SystematicESN` | Published review organizing ESN design levers |
| `2012.02974v1.pdf` | `SunSongHongLi2020ESNReview` | Earlier review preprint; useful background but largely superseded by the 2024 review |

## Verified Takeaways

1. Principal-neuron reinforcement uses trained output-weight magnitudes to
   identify influential reservoir units, then modifies recurrent links associated
   with those units. The paper reports strong benchmark improvements relative to
   the initial reservoirs and Anti-Oja comparisons, but the thresholding and
   update rules are heuristic. For Q--DESN, this is evidence that readout
   information can diagnose reservoir features; it is not a default part of the
   fixed-reservoir model.

2. State feedback replaces the effective ESN update with a low-rank external
   modification of the recurrent dynamics. The paper proves a training-cost
   improvement for almost all fixed ESNs under its assumptions and reports
   empirical gains on Mackey--Glass, channel equalization, and electric drives.
   For Q--DESN, this is a promising future extension, but it changes the feature
   generation rule and should not be folded silently into the current selection
   section.

3. Similar-dynamics pruning gives the most directly actionable diagnostic for the
   current article. The paper links redundant reservoir trajectories to a large
   eigenvalue spread in the state autocorrelation matrix, which slows or prevents
   LMS convergence and also indicates poor readout conditioning. For Q--DESN,
   state correlation, singular-value spectrum, effective rank, condition number,
   and eigenvalue-spread summaries should be part of the design gate.

4. The statistical-remedies preprint treats random reservoir initialization as a
   practical instability source. It explores weight distributions, preprocessing,
   perturbation, dynamic leaking rates, and ensembles. The safest manuscript
   takeaway is that seed sensitivity should be reported and that ensembles can
   stabilize forecasts when the base reservoirs are reasonable. The arcsine-weight
   result is task-dependent and should not be presented as a universal default.

5. The 2024 systematic review supports the broad claim that ESN performance is a
   design problem involving topology, dynamic weights, reservoir connections,
   multiple reservoirs, hyperparameter selection, training regularization,
   DeepESNs, and hybrid models. It is the preferred review citation for the
   related-work paragraph.

6. The 2020 review preprint is useful background, especially for the warning that
   ESN simplicity can be deceptive, but the published 2024 review is the stronger
   main-text citation.

## Manuscript Consequences

- Section 7 should not say or imply that larger reservoirs are automatically
  better. It should say that larger reservoirs are useful only when they add
  nonredundant dynamics and the readout remains numerically controlled.
- The design gate should explicitly include state-matrix diagnostics, not only
  forecast scores.
- Seed variability should be treated as a robustness issue. A single selected seed
  is not evidence of reservoir optimality.
- Reservoir ensembles, if used, should aggregate only reservoirs that passed the
  same diagnostics and should be reported separately from posterior uncertainty
  conditional on a fixed feature map.
- State feedback and PNR should be described as future extensions or ablations,
  because they change the reservoir feature-generation rule.

## Claims To Avoid

- Avoid: "Bigger reservoirs perform better."
  Use: "Larger reservoirs can help when they add nonredundant states and the
  readout remains well conditioned."
- Avoid: "State feedback always improves forecasts."
  Use: "State feedback improves optimized cost under the paper's assumptions and
  gives strong benchmark gains, but it must be validated for held-out forecasts."
- Avoid: "PNR solves reservoir initialization."
  Use: "PNR reduces initialization sensitivity in the reported benchmarks through
  a heuristic reservoir-adaptation rule."
- Avoid: "Arcsine weights are best."
  Use: "Weight distribution affects state behavior, and any distributional choice
  should be validated for the task."

