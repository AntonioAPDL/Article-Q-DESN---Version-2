# Joint QDESN article evidence pack: audit, diagnosis, and implementation plan

Date: 2026-07-06

This note gives the recommended next implementation stage after the completed article-scale VB fit and no-refit forecast validation, the post-VB compact audit, the independent exAL failure diagnostic, and the convergence-readiness audit. The purpose is to turn the validated artifacts into manuscript-ready tables, figures, and reproducibility records without launching another model-fitting campaign.

## Scope

This stage is scoped to the new joint QDESN simulation study only. It should not modify TT500, GloFAS, PriceFM, or the older joint-QVP calibration lanes.

The next script should be:

`application/scripts/105_prepare_joint_qdesn_article_validation_tables_figures.R`

The script should consume completed artifacts and write article assets. It should not fit models, regenerate fixtures, change validation outputs, tune hyperparameters, or rerun VB.

## Evidence Sources Audited

| Source | Role | Audit result |
|---|---|---|
| `application/cache/joint_qdesn_simulation_dgp_fixtures_20260706` | Frozen DGP fixtures, oracle quantiles, split metadata, forecast-origin plan | 9 scenarios, 12000 simulated rows, 2000 DGP warmup rows, last 2000 effective rows split into 500 DESN washout, 500 fit, 1000 validation; fixture validation rows pass. |
| `application/cache/joint_qdesn_simulation_vb_fit_validation_article_20260706` | Fit-window VB validation | 21 manifest files, hashes verified by post-VB audit; 0 contract crossings; finite scores. |
| `application/cache/joint_qdesn_simulation_vb_forecast_validation_article_20260706` | No-refit held-out forecast validation | 21 manifest files, hashes verified by post-VB audit; 0 contract crossings; finite scores. |
| `application/cache/joint_qdesn_simulation_post_vb_validation_audit_20260706` | Compact fit/forecast health, model ranking, scenario summaries | Manifest verified; identifies primary article candidates and review flags. |
| `application/cache/joint_qdesn_independent_exal_tail_failure_diagnostic_20260706` | Targeted independent exAL pathology diagnostic | Manifest verified; confirms localized `exQDESN RHS` failure at `asymmetric_laplace_tail`, `tau=0.75`. |
| `application/cache/joint_qdesn_vb_convergence_readiness_20260706` | Representative 480/720/960 VB iteration audit | Manifest verified; 11 `pass_with_note`, 1 `review`, 0 `fail`; score movement is negligible. |

The completed source artifacts are sufficient for article asset generation. No additional full validation launch is justified before preparing the evidence pack.

## Manuscript Context

The current simulation section contains the single-quantile TT500 study and states that the joint multi-quantile QDESN extension is not yet included in the simulation summaries. That was accurate before the new VB validation artifacts. The evidence-pack stage should prepare a controlled update path:

1. generate standalone joint-QDESN tables and figures under `tables/` and `figures/joint_qdesn_simulation/`;
2. generate a wrapper file, for example `tables/joint_qdesn_simulation_vb_article_tables.tex`;
3. verify the wrapper compiles independently through `main.tex` only after table assets are complete;
4. replace the old manuscript sentence with a modest transition explaining that the following subsection reports a separate multi-quantile validation under known oracle quantile paths.

This preserves the existing TT500 validation block and avoids blending the two studies. TT500 remains the single-quantile comparison against DQLM and exDQLM baselines. The joint-QDESN study is a separate multi-quantile recovery and held-out forecast validation over bridge and stress synthetic data-generating processes.

## Diagnosis of the Current Evidence

### Article-candidate models

The forecast audit ranks models as follows:

| Role | Internal label | Article-facing label | Forecast truth MAE | Check loss | CRPS-grid | Treatment |
|---|---|---|---:|---:|---:|---|
| Primary joint AL model | `JOINT QDESN RHS` | Joint QDESN RHS | 0.103 | 0.161 | 0.369 | Main table. |
| Independent AL comparator | `QDESN RHS` | Independent QDESN RHS | 0.104 | 0.161 | 0.368 | Main table. |
| Stable joint exAL comparator | `JOINT exQDESN RHS` | Joint exQDESN RHS | 0.155 | 0.163 | 0.371 | Main table, interpreted cautiously. |
| Unstable independent exAL comparator | `exQDESN RHS` | Independent exQDESN RHS | 58.502 | 19.417 | 55.303 | Exclude from main article table; retain in diagnostic appendix or audit note. |

The article-facing labels should avoid all-caps model names in prose. Use `Joint QDESN RHS`, `Independent QDESN RHS`, `Joint exQDESN RHS`, and `Independent exQDESN RHS`. Define QDESN as the AL working likelihood and exQDESN as the exAL working likelihood before presenting the tables.

### Independent exAL pathology

The independent `exQDESN RHS` failure is severe but localized:

- DGP: `asymmetric_laplace_tail`;
- target: `tau = 0.75`;
- exAL `alpha_mean`: about 3432;
- exAL `sigma_mean`: about 0.0094;
- raw truth MAE at `tau=0.75`: about 2724.6;
- contract truth MAE at `tau=0.75`: about 545.5;
- max monotone adjustment at `tau=0.75`: about 2537.0.

The neighboring sensitivity fits at `tau=0.70` and `tau=0.80` are numerically reasonable, and shrinking the empirical alpha prior standard deviation does not repair the `tau=0.75` failure. The best current diagnosis is a K=1 exAL coordinate-update or local-approximation instability, not a global exAL failure and not a fixture problem.

Optimal decision: do not spend the next stage repairing independent exAL. The main article can proceed with the three stable rows, while independent exAL is disclosed as a diagnostic limitation or deferred to a method-development appendix.

### VB convergence

The original fit and forecast audits contain many review flags because 34 of 36 validation rows reached the adaptive 480-iteration cap. The targeted convergence audit compared representative fits at 480, 720, and 960 iterations:

- 11 of 12 scenario-model combinations are `pass_with_note`;
- the only review is `Joint QDESN RHS` on `persistent_heavy_tail`;
- the review is caused by a maximum fitted-quantile delta of about 0.059 from 480 to 720;
- the mean fitted-quantile delta is about 0.0067;
- truth MAE improves only from 0.11835 to 0.11748;
- check-loss movement is about 0.000014;
- contract crossings remain 0.

Optimal decision: keep the completed 480-iteration article-scale VB artifacts and add a convergence note. A full rerun at 960 iterations is not currently justified because it would be expensive, would not address independent exAL, and is unlikely to change the article-level conclusions.

## Alternatives Reconsidered

| Alternative | Evidence for | Evidence against | Decision |
|---|---|---|---|
| Launch another full VB validation with larger iteration caps | Would reduce concern about max-iteration flags | Targeted 960 audit shows negligible score movement; expensive; does not fix independent exAL | Do not launch now. |
| Repair independent K=1 exAL before article tables | Could rescue a fourth comparator | Failure is isolated and severe; repair requires algorithmic development and new validation; main article can proceed with stable joint exAL | Defer; keep diagnostic record. |
| Move immediately to MCMC | Provides posterior reference layer | MCMC should be initialized from stable VB; independent exAL instability is unresolved; article VB evidence is not yet packaged | Defer until VB evidence pack is frozen. |
| Add all current outputs directly to `main.tex` | Fast | Risks manuscript clutter, unstable row inclusion, and unsupported claims | Generate asset pack first, then update manuscript. |
| Build a compact article evidence pack from existing artifacts | Reproducible, scoped, uses validated outputs, supports manuscript integration | Requires one careful asset-builder script | Recommended. |

## Recommended Implementation

### 1. Asset-builder script

Create `application/scripts/105_prepare_joint_qdesn_article_validation_tables_figures.R`.

Required CLI arguments:

- `--fit-dir`
- `--forecast-dir`
- `--post-vb-audit-dir`
- `--tail-diagnostic-dir`
- `--convergence-audit-dir`
- `--fixture-dir`
- `--tables-dir`
- `--figures-dir`
- `--output-dir`
- `--include-independent-exal-main false` by default

Default paths should point to the completed 20260706 artifacts.

The script should:

1. verify every source artifact manifest before reading source tables;
2. check fixture validation rows are all `pass`;
3. check source fit and forecast assessments have 0 `fail` rows;
4. check source contract crossings are 0;
5. check source scores are finite;
6. enforce the model-inclusion policy;
7. write CSV assets, LaTeX tables, figures, README, provenance, and an asset manifest.

### 2. Main table assets

Write these CSV and LaTeX outputs:

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

Recommended main text tables:

1. protocol table: scenarios, tau grid, fit and validation geometry, no-refit forecast protocol, VB controls, scoring metrics;
2. model summary table: fit and forecast truth MAE/RMSE, check loss, CRPS-grid, hit-rate error, runtime, status;
3. scenario summary table: forecast truth MAE/RMSE by scenario for the three main models;
4. compact diagnostic table: raw crossing count, max adjustment, max-iteration note, and the independent exAL exclusion reason.

The independent `exQDESN RHS` row should not appear in the primary model-performance table unless the user explicitly requests a failure-disclosure row. If included anywhere, it should be in a diagnostic table clearly labeled as excluded from the main comparison.

### 3. Figure assets

Create `figures/joint_qdesn_simulation/` and write:

- `joint_qdesn_simulation_forecast_truth_mae_heatmap.pdf`
- `joint_qdesn_simulation_check_loss_heatmap.pdf`
- `joint_qdesn_simulation_truth_by_tau.pdf`
- `joint_qdesn_simulation_raw_adjustment_diagnostics.pdf`
- `joint_qdesn_simulation_overlay_normal_bridge.pdf`
- `joint_qdesn_simulation_overlay_asymmetric_laplace_tail.pdf`
- `joint_qdesn_simulation_overlay_regime_shift.pdf`

Figure design:

- heatmaps should compare scenarios by model using stable color scales and readable labels;
- overlay figures should show observed data, true quantile paths, and fitted or forecast quantiles for the main joint model;
- raw adjustment diagnostics should separate raw crossing behavior from the monotone contract used for scoring;
- no figure should imply that monotone post-processing hides model instability.

### 4. Metrics and claims

Primary reported metrics:

- truth MAE and truth RMSE against oracle conditional quantiles;
- check loss for realized observations;
- CRPS-grid score computed from the quantile-grid representation;
- empirical hit-rate error;
- central interval coverage error and interval width where paired tau levels are available;
- runtime and VB convergence status;
- raw crossing and monotone-adjustment diagnostics.

Do not report WIS as a primary metric for this section. CRPS-grid and check loss are sufficient and align with the user's stated preference. If interval scores are retained, present them as secondary interval diagnostics rather than the organizing score.

Claims allowed:

- the joint AL readout gives the strongest overall evidence in this fixed synthetic design;
- the independent AL comparator is close in aggregate accuracy but needs more monotone repair;
- the joint exAL comparator is stable but less accurate in this run;
- the independent exAL comparator is excluded from the main table because of a localized K=1 exAL instability;
- the results are conditional on the frozen scenario collection, one seed per base DGP, the fixed reservoir design, and VB inference.

Claims not allowed:

- universal superiority of joint QDESN;
- final MCMC confirmation;
- claims that monotone rearrangement solves model-crossing behavior;
- claims that independent exAL is globally invalid;
- claims that 480-iteration VB fully converged in all coordinates.

### 5. Manuscript update path

After generated assets verify, update `main.tex` cautiously:

1. keep the TT500 section unchanged except for replacing the outdated sentence that says the joint multi-quantile extension is not reported;
2. add a new subsection after `TT500 Reproducibility and Limitations`, for example `Joint Multi-Quantile Synthetic Validation`;
3. define the model labels before the first table:
   - QDESN denotes the AL working likelihood;
   - exQDESN denotes the exAL working likelihood;
   - `Joint` and `Independent` distinguish a joint quantile-vector readout from separately fit single-quantile readouts assembled over the same tau grid;
4. input `tables/joint_qdesn_simulation_vb_article_tables.tex`;
5. include one or two figures only if they materially improve readability.

The prose should follow the repository writing profile: define the statistical target first, describe the protocol, report diagnostics, and make modest claims.

### 6. Tests and verification

Add focused checks, either as an R test or as built-in script assertions:

- source manifest verification passes;
- all expected source files exist;
- model-inclusion policy excludes independent `exQDESN RHS` by default;
- generated tables include only allowed main rows;
- generated numeric table values are finite;
- generated LaTeX files contain labels and captions;
- generated figure files exist and have nonzero size;
- generated asset manifest has complete SHA-256 hashes;
- the script is deterministic when source artifacts are unchanged.

Verification commands:

```bash
Rscript application/scripts/105_prepare_joint_qdesn_article_validation_tables_figures.R
Rscript -e 'parse(file="application/scripts/105_prepare_joint_qdesn_article_validation_tables_figures.R")'
git diff --check
pdflatex -interaction=nonstopmode main.tex
bibtex main
pdflatex -interaction=nonstopmode main.tex
pdflatex -interaction=nonstopmode main.tex
```

If manuscript compilation is slow, first verify the generated wrapper by checking that the table files are syntactically balanced and then run the full LaTeX build once after manuscript insertion.

## Closeout Criteria

The stage is complete when:

- the evidence-pack script exists and runs without fitting models;
- all source manifests and generated asset hashes verify;
- all table and figure assets are written under stable names;
- the main table excludes independent `exQDESN RHS` by default;
- a compact diagnostic table records why independent exAL is held out;
- the generated wrapper can be inserted into `main.tex`;
- the manuscript language is modest and consistent with the writing profile;
- final documentation records artifact paths, commands, and allowed claims.

## Recommended Next Action

Implement `105_prepare_joint_qdesn_article_validation_tables_figures.R`, generate the evidence pack, then update the simulation section with a compact joint multi-quantile subsection. Do not launch MCMC or a new VB rerun until this evidence pack is frozen and the manuscript-facing results have been inspected.
