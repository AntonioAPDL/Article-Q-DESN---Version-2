# Documentation Guide

The documentation is organized for readers who want to understand why the
current manuscript looks the way it does, without needing the whole editing
history.

## Audits

- `audits/initial_style_audit.md`: first broad audit of the manuscript,
  supplement, bibliography, and simulation tables.
- `audits/reader_focused_style_audit.md`: reader-facing pass focused on
  clarity, notation, and anti-generic prose.
- `audits/reviewer_reading_audit.md`: fresh-reader pass from the perspective of
  a potential reviewer.
- `audits/full_manuscript_style_audit.md`: whole-document style and scope audit
  after the major framing changes.

## Revision Logs

- `revision_logs/initial_style_revision_log.md`: changes from the first style
  pass.
- `revision_logs/reader_focused_revision_log.md`: later changes from the
  reader-focused, reviewer, introduction, related-work, and compact-abstract
  passes.

## Implementation Notes

- `implementation_notes/regularized_horseshoe_update_report.md`: record of the
  regularized-horseshoe implementation update and the supporting citation
  changes.
- `implementation_notes/glofas_application_reproducibility_blueprint.md`:
  design contract for the planned GloFAS Q-DESN application workflow,
  including the current local R 4.6.0 runtime requirement for validation and
  application gates.
- `implementation_notes/glofas_model_contract_20260511.md`: frozen
  discrepancy-calibration model contract connecting the main article,
  supplement, and future code.
- `implementation_notes/glofas_implementation_spec_20260511.md`: code-facing
  object map, API boundary, validation checks, and run-artifact contract for
  the GloFAS implementation.
- `implementation_notes/glofas_prelaunch_runbook_20260511.md`: final dry-run
  and preflight procedure before any manuscript-scale application launch.
- `implementation_notes/glofas_large_vb_launch_protocol_20260512.md`:
  companion VB protocol for the large Dec. 25 GloFAS discrepancy profile,
  including the inference-support gate that requires engine-reported
  discrepancy `AL + VB` support before posterior computation.
- `implementation_notes/glofas_large_gate_and_vb_p50_pilot_20260512.md`:
  record of the full large MCMC and VB design gates and the first median-only
  large AL-VB pilot.
- `implementation_notes/glofas_phase3_derivation_plan_20260511.md`: derivation
  plan for the application-specific posterior, MCMC, VB, and ELBO supplement
  material.
- `implementation_notes/glofas_application_model_families_20260513.md`:
  separation between the frozen origin-state bridge and the latent-path
  ensemble-likelihood target model.
- `implementation_notes/glofas_latent_path_ensemble_likelihood_contract_20260513.md`:
  initial statistical contract, likelihood ownership, future-state recursion,
  and derivation gates for the latent-path GloFAS model.
- `implementation_notes/glofas_latent_path_vb_first_plan_20260513.md`:
  revised implementation plan prioritizing AL-VB, then AL-MCMC, then exAL,
  with effective-horizon handling and synthetic validation requirements.
- `implementation_notes/glofas_latent_path_four_case_derivations_20260513.md`:
  pre-implementation derivation note for the AL-VB, AL-MCMC, exAL-VB, and
  exAL-MCMC latent-path GloFAS targets under one shared notation.
- `implementation_notes/application_selected_reference_run_20260524.md`:
  current manuscript-facing GloFAS application run, promoted-output registry,
  compact score table, selection command, and replacement protocol.
- `implementation_notes/glofas_candidate_batch_20260524.md`: focused
  reservoir-candidate launch batch after the selected reference GloFAS run,
  holding the prior and inference settings fixed while varying screened D1 n300
  reservoir controls.
- `implementation_notes/glofas_capacity1000_candidate_batch_20260524.md`:
  capacity-controlled depth/width candidate batch with total reservoir units
  fixed at 1000, identity/no-reduction inter-layer state maps, and a required
  `diagnostic_target=both` reservoir-validity gate before launch.

These notes are descriptive. The authoritative manuscript sources are
`../main.tex`, `../qdesn-supplement.tex`, and `../refs.bib`.
