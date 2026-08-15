# Joint QDESN Validation Manuscript Polish

Date: 2026-07-07

## Purpose

This note records the manuscript-facing polish pass for the joint QDESN
validation assets. The pass does not rerun inference, regenerate fixtures, or
change reported metrics. It changes how the completed validation evidence is
presented in the article.

The goal is to keep the main article focused on statistical design, fit and
forecast metrics, and qualified interpretation, while retaining run-level
provenance in generated manifests and provenance tables.

## Inputs

- `application/R/joint_qdesn_article_assets.R`
- `application/scripts/110_build_joint_qdesn_article_validation_assets.R`
- `application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707`
- `application/cache/joint_qdesn_mcmc_article_phase109_20260707`
- `main.tex`

The ignored working audit is:

`application/cache/joint_qdesn_validation_manuscript_polish_audit_20260707.md`

## Implemented Changes

- Split generated joint-validation tables into a compact main-article wrapper
  and a provenance wrapper.
- Kept `tables/joint_qdesn_article_validation_tables.tex` as the main article
  input, now containing only:
  - `tables/joint_qdesn_article_validation_protocol.tex`
  - `tables/joint_qdesn_article_validation_vb_model_summary.tex`
- Added `tables/joint_qdesn_article_validation_provenance_tables.tex` for
  protocol provenance, scenario summaries, MCMC scenario diagnostics, and gate
  summaries.
- Rewrote the main protocol table to report statistical design fields rather
  than source paths, phase labels, candidate IDs, and gate policy.
- Rewrote the VB model table headers and caption with reader-facing metric
  language:
  - fit MAE,
  - forecast MAE and RMSE,
  - check loss,
  - grid CRPS,
  - hit-rate error,
  - pre-rearrangement crossings.
- Rewrote the MCMC scenario table as a provenance diagnostic table with
  path-distance and diagnostic-note language rather than main-text gate labels.
- Revised the simulation-section prose in `main.tex` to:
  - state the TT500 and joint-validation goals more clearly;
  - define the distinction between \(p\) and \(\tau\);
  - remove phase, freeze, launch, rescue, and worker-failure language from the
    main article narrative;
  - describe the nine joint-validation mechanisms in bridge and stress classes;
  - describe monotone rearrangement as the reported quantile-grid policy;
  - keep claims conditional on the fixed reservoir, scenarios, quantile grid,
    and forecast protocol.

## Generated Assets

Main article wrapper:

- `tables/joint_qdesn_article_validation_tables.tex`

Provenance wrapper:

- `tables/joint_qdesn_article_validation_provenance_tables.tex`

New provenance table files:

- `tables/joint_qdesn_article_validation_protocol_provenance.csv`
- `tables/joint_qdesn_article_validation_protocol_provenance.tex`
- `tables/joint_qdesn_article_validation_vb_model_summary_provenance.tex`

The asset manifest remains:

- `tables/joint_qdesn_article_validation_asset_manifest.csv`

## Verification Plan

Completed commands:

```bash
Rscript application/scripts/110_build_joint_qdesn_article_validation_assets.R
Rscript application/tests/test_joint_qdesn_article_validation_assets.R
mkdir -p /tmp/qdesn_joint_validation_polish_compile
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=/tmp/qdesn_joint_validation_polish_compile main.tex
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=/tmp/qdesn_joint_validation_polish_compile main.tex
rg -n "Warning|Undefined|Overfull|Underfull|Error|Missing" \
  /tmp/qdesn_joint_validation_polish_compile/main.log
```

Results:

- Asset regeneration completed without rerunning inference.
- Focused article-asset test passed.
- Two-pass `pdflatex` compilation completed in
  `/tmp/qdesn_joint_validation_polish_compile`.
- The final log scan produced no warning, undefined-reference, overfull,
  underfull, error, or missing-file hits. The only match to the broad scan was
  the package banner for `rerunfilecheck`.
- A visible-main local-term search returned no hits for phase labels, cache
  paths, selected-candidate IDs, worker-failure language, contract-crossing
  jargon, or the prior Stage/confirmation-rescue labels in the main joint
  validation input.

The focused test enforces that the main-rendered joint validation tables do not
contain local phase IDs, cache paths, selected-candidate IDs, worker-failure
language, or contract-crossing jargon, while the provenance wrapper remains
available for reproducibility.

## Interpretation

The numerical evidence is unchanged. The main article now reports the
joint-validation evidence as a simulation study rather than a run ledger. The
provenance tables and manifests still preserve the implementation diagnostics
needed to reproduce and audit the results.
