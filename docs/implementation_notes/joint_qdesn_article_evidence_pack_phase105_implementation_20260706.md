# Joint QDESN article evidence pack: implementation record

Date: 2026-07-06

This note records the completed implementation of the joint QDESN article evidence pack described in `joint_qdesn_article_evidence_pack_phase105_audit_plan_20260706.md`. The stage converts completed VB validation artifacts into manuscript-ready tables, figures, and reproducibility records. It does not refit models, regenerate DGP fixtures, tune hyperparameters, or alter TT500, GloFAS, PriceFM, or older joint-QVP outputs.

## Implemented stage

The new asset-builder script is:

`application/scripts/105_prepare_joint_qdesn_article_validation_tables_figures.R`

The script consumes the frozen 20260706 joint QDESN evidence sources:

- `application/cache/joint_qdesn_simulation_dgp_fixtures_20260706`
- `application/cache/joint_qdesn_simulation_vb_fit_validation_article_20260706`
- `application/cache/joint_qdesn_simulation_vb_forecast_validation_article_20260706`
- `application/cache/joint_qdesn_simulation_post_vb_validation_audit_20260706`
- `application/cache/joint_qdesn_independent_exal_tail_failure_diagnostic_20260706`
- `application/cache/joint_qdesn_vb_convergence_readiness_20260706`

Before writing article assets, the script verifies source manifests, fixture validation status, source assessment gates, finite scores, and zero contract crossings. It then writes tracked tables and figures plus an ignored verification cache:

`application/cache/joint_qdesn_article_evidence_pack_phase105_20260706`

The verification cache contains source-manifest checks, source-gate checks, provenance, a compact README, and a cache-level artifact manifest.

## Article-facing model policy

The main manuscript table reports the stable VB evidence rows:

- Joint QDESN RHS
- Independent QDESN RHS
- Joint exQDESN RHS

Here QDESN denotes the asymmetric-Laplace working likelihood and exQDESN denotes the extended asymmetric-Laplace working likelihood. The labels Joint and Independent distinguish a joint quantile-vector readout from separately fit single-quantile readouts assembled over the same tau grid.

Independent exQDESN RHS is excluded from the main performance table by default. The targeted diagnostic shows a localized K=1 exAL instability for the asymmetric-Laplace-tail scenario at tau = 0.75. The evidence pack keeps this failure visible in a diagnostic table rather than letting it dominate the main comparison.

## Generated tracked assets

The table assets are:

- `tables/joint_qdesn_simulation_vb_protocol.csv`
- `tables/joint_qdesn_simulation_vb_protocol.tex`
- `tables/joint_qdesn_simulation_vb_model_summary.csv`
- `tables/joint_qdesn_simulation_vb_model_summary.tex`
- `tables/joint_qdesn_simulation_vb_scenario_summary.csv`
- `tables/joint_qdesn_simulation_vb_scenario_summary.tex`
- `tables/joint_qdesn_simulation_vb_convergence_adjustment_summary.csv`
- `tables/joint_qdesn_simulation_vb_convergence_adjustment_summary.tex`
- `tables/joint_qdesn_simulation_vb_exal_diagnostic_summary.csv`
- `tables/joint_qdesn_simulation_vb_exal_diagnostic_summary.tex`
- `tables/joint_qdesn_simulation_vb_article_tables.tex`
- `tables/joint_qdesn_simulation_vb_asset_manifest.csv`

The figure assets are:

- `figures/joint_qdesn_simulation/joint_qdesn_simulation_forecast_truth_mae_heatmap.pdf`
- `figures/joint_qdesn_simulation/joint_qdesn_simulation_check_loss_heatmap.pdf`
- `figures/joint_qdesn_simulation/joint_qdesn_simulation_truth_by_tau.pdf`
- `figures/joint_qdesn_simulation/joint_qdesn_simulation_raw_adjustment_diagnostics.pdf`
- `figures/joint_qdesn_simulation/joint_qdesn_simulation_overlay_normal_bridge.pdf`
- `figures/joint_qdesn_simulation/joint_qdesn_simulation_overlay_asymmetric_laplace_tail.pdf`
- `figures/joint_qdesn_simulation/joint_qdesn_simulation_overlay_regime_shift.pdf`

The tracked article asset manifest reports 18 assets with complete SHA-256 hashes.

## Manuscript integration

`main.tex` now contains a separate subsection titled `Joint Multi-Quantile Synthetic Validation`. The section is intentionally separate from the TT500 single-quantile simulation study. It defines the model labels, describes the frozen no-refit validation protocol, inputs `tables/joint_qdesn_simulation_vb_article_tables.tex`, reports conservative findings, and includes a compact figure with the forecast-truth-MAE heatmap and the asymmetric-Laplace-tail overlay.

The integration keeps the allowed claims narrow:

- the joint AL readout is the strongest stable row in this frozen VB evidence pack;
- the independent AL comparator is close in aggregate accuracy but needs more monotone repair;
- joint exAL is stable but less accurate in this run;
- independent exAL is treated as a diagnostic limitation, not a main-table comparator;
- MCMC confirmation remains a later stage after the VB evidence pack is frozen.

## Verification

The following verification commands were run from the clean validation worktree:

```bash
Rscript -e 'parse(file="application/scripts/105_prepare_joint_qdesn_article_validation_tables_figures.R")'
pdflatex -interaction=nonstopmode main.tex
bibtex main
pdflatex -interaction=nonstopmode main.tex
pdflatex -interaction=nonstopmode main.tex
git diff --check
rg -n "Undefined references|undefined references|LaTeX Error|Overfull" main.log
```

Results:

- script parse passed;
- source manifest checks passed;
- cache artifact manifest passed for 6 of 6 files;
- tracked article asset manifest passed for 18 of 18 files;
- `main.pdf` built successfully;
- no unresolved references, LaTeX errors, or overfull-box warnings were found in the final log scan;
- `git diff --check` passed.

## Recommended next stage

The immediate next step is editorial review of the new joint multi-quantile subsection in `main.pdf`, with attention to table density and wording. After the VB article evidence pack is accepted, the next methodological stage is to add the MCMC reference layer initialized from the stable VB rows, beginning with Joint QDESN RHS and Joint exQDESN RHS on the most informative bridge and stress scenarios.
