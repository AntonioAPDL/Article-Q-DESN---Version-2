# GloFAS Q-DESN Application Reproducibility Blueprint

Date: 2026-05-11

## Decision

The GloFAS application should be implemented as an article-owned
reproducibility pipeline under `application/`. The article repo should not
absorb the full Q-DESN validation repo. Instead, it should define the frozen
input contract, application panel, model grid, forecast-origin protocol,
scoring outputs, and manuscript provenance. The Q-DESN computational engine
should be pinned as a dependency, or later vendored as a small audited module
if installation or stability becomes a barrier.

The current frozen model contract is
`docs/implementation_notes/glofas_model_contract_20260511.md`. The
code-facing object map and API boundary are recorded in
`docs/implementation_notes/glofas_implementation_spec_20260511.md`.

Runtime update, 2026-05-15:

- application and validation-facing article commands should use the local
  R 4.6.0 runtime at `/home/jaguir26/.local/bin/Rscript`;
- the expected `R_HOME` is
  `/data/jaguir26/local/opt/R/4.6.0/lib64/R`;
- `/usr/bin/R` may still be the system R 4.5.3 and should not be used for new
  Q-DESN source-sync, validation, or application-launch gates;
- legacy R-4.4 `R_LIBS_USER` prefixes are obsolete for this workflow.

This is the strongest structure for a statistical article because it separates
three responsibilities:

1. the manuscript states the model and scientific claims;
2. the application pipeline produces the data evidence for those claims;
3. the computational package supplies reusable Q-DESN fitting routines.

## Verification Against Current Repositories

Current article repo:

- The repository is manuscript-focused and clean.
- It already tracks the article, supplement, bibliography, simulation tables,
  writing-style profile, audits, and simulation-table builder.
- It had no application scaffold before this blueprint.
- Local-only literature artifacts are ignored; application artifacts now follow
  the same rule.

Current Q-DESN validation code:

- The active Q-DESN implementation lives in an `exdqlm` development repo.
- Exported functions include `qdesn_fit_vb()`, `qdesn_fit_mcmc()`,
  `qdesn_fit()`, `qdesn_build_design()`, `forecast_paths.qdesn_fit()`,
  `forecast_lattice.qdesn_fit()`, and `quantileSynthesis()`.
- The validation repo contains a large historical benchmark and validation
  apparatus. It is valuable as a code source and audit trail but too broad to
  be the article application workflow.
- The validation audit records that post-fix Q-DESN RHS-family evidence was
  refreshed after the final `rhs_ns` routing and intercept-policy changes.

Implication:

- Reuse stable Q-DESN engine functions.
- Reuse result-manifest ideas and health-check discipline.
- Do not copy benchmark-specific M4, Monash, or historical validation logic
  into the article application.

## Repository Boundary

The article repo owns:

- `application/config/`: cutoffs, quantile grids, model grids, run profiles.
- `application/manifests/`: input and schema contracts.
- `application/R/`: application-specific functions only.
- `application/scripts/`: executable workflow stages.
- `application/tests/`: input, leakage, and reproducibility checks.
- `tables/` and `figures/`: promoted manuscript outputs.
- `docs/figure_table_provenance.md`: article-facing provenance.

The article repo does not own:

- raw GloFAS data;
- raw gauge records;
- large frozen handoffs;
- fitted model objects;
- large posterior draw files;
- exploratory validation campaigns.

Those live in ignored local directories and are represented in Git only through
manifests, hashes, schemas, and promoted table or figure outputs.

## Proposed Application Tree

```text
application/
  README.md
  config/
    README.md
    glofas_discrepancy_application.yaml
    input_bundle.yaml
    cutoffs.csv
    quantile_grid.csv
    model_grid.csv
    figure_specs.yaml
  manifests/
    expected_schema.yaml
    input_manifest_TEMPLATE.csv
    input_bundle_manifest_TEMPLATE.csv
    input_manifest.csv
  R/
    00_packages.R
    input_contract.R
    register_input_bundle.R
    audit_input_bundle.R
    build_application_panel.R
    build_qdesn_features.R
    fit_qdesn_reference.R
    fit_qdesn_discrepancy.R
    figure_provenance.R
    plot_input_diagnostics.R
    synthesize_quantiles.R
    score_forecasts.R
    make_manuscript_outputs.R
  scripts/
    00_register_input_bundle.R
    00_check_inputs.R
    00_audit_input_bundle.R
    01_build_panel.R
    02_make_input_figures.R
    03_fit_models.R
    04_score_models.R
    05_make_outputs.R
    06_preflight_launch.R
    run_all.R
  tests/
    test_input_contract.R
    test_no_leakage.R
    test_quantile_grid.R
    test_reproducibility.R
  data_local/          # ignored
  cache/               # ignored
  runs/                # ignored
  logs/                # ignored
  outputs/             # ignored
```

## Naming Conventions

Use names that reveal the role of each file without needing project memory.

Configuration:

- `glofas_discrepancy_application.yaml`: main application config.
- `input_bundle.yaml`: local frozen-input bundle contract.
- `cutoffs.csv`: forecast origins, training windows, validation windows.
- `quantile_grid.csv`: target levels fitted separately.
- `model_grid.csv`: model--quantile fit rows and inference settings.
- `figure_specs.yaml`: pre-model input diagnostic figures.
- `fit_id`: unique identifier for a single model--quantile fit.
- `model_id`: identifier shared across the fitted quantile grid for one
  forecast model, used for monotone synthesis and scoring.

Derived data:

- `application_panel.rds`: derived modeling panel.
- `application_panel_summary.csv`: run-specific summary of the derived panel.
- `input_manifest.csv`: local frozen input manifest used by a run.
- `input_bundle_manifest.csv`: registration record for every configured input,
  including optional inputs that are absent.

Runs:

```text
glofas_qdesn_YYYYMMDD_HHMMSS__git-<shortsha>__cfg-<hash>
```

Run outputs:

- `run_config.yaml`
- `session_info.txt`
- `git_state.txt`
- `input_manifest_used.csv`
- `model_grid_used.csv`
- `input_bundle_audit.csv`
- `input_profile.csv`
- `application_panel_summary.csv`
- `figure_manifest.csv`
- `fit_status.csv`
- `score_by_origin.csv`
- `score_by_horizon.csv`
- `score_summary.csv`
- `manuscript_output_provenance.csv`

Manuscript promotion:

- generated tables are promoted to `tables/`;
- generated figures are promoted to `figures/`;
- every promoted output receives one row in
  `manuscript_output_provenance.csv` and, later,
  `docs/figure_table_provenance.md`.

## Input Contract

The application should consume frozen local handoffs rather than active
runtime directories. The input manifest must record:

- source name;
- source type;
- local path;
- upstream reference or lineage note;
- date range;
- cutoff date, if applicable;
- row and column counts;
- SHA-256 hash;
- creation time;
- notes on transformations.

The check stage should read the registered files and verify that the manifest
metadata matches the data, including required semantic columns, hashes, row
counts, column counts, and date ranges.

Required conceptual inputs:

1. reference gauge streamflow;
2. retrospective GloFAS streamflow product;
3. issued GloFAS ensemble forecasts by origin, horizon, and member;
4. optional climate or hydrologic covariates available at the forecast origin.

The application panel must enforce that target observations and target-time
covariates are not used before the forecast origin.

## Model Contract

The first complete implementation should fit a small, defensible model set:

1. raw GloFAS ensemble quantiles;
2. reference-only Q-DESN;
3. Q-DESN GloFAS discrepancy calibration;
4. DQLM and exDQLM baselines, if the same forecast-origin protocol can be
   used without extra data handling assumptions.

Default inference:

- VB-LD for the full quantile grid;
- MCMC for selected diagnostic fits;
- regularized horseshoe as the default application coefficient prior;
- ridge as the dense baseline.

Default quantile grid:

```text
0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95
```

The quantile grid can be expanded after the smoke workflow passes.

## Forecast-Origin Protocol

Every model must be evaluated on the same forecast origins, horizons, and
reference observations. The protocol should define:

- forecast origin `T`;
- horizon set `h = 1, ..., H`;
- target date `T + h`;
- training window for each origin;
- validation or test label;
- whether the origin belongs to a smoke, pilot, or final run;
- whether all ensemble members are present.

The GloFAS ensemble members should enter the discrepancy model as
conditionally independent likelihood contributions given the forecast-system
quantile path and source-specific likelihood parameters. This is a modeling
factorization motivated by the operational ensemble construction, not a claim
that all hydrologic forecast errors are independent in an unconditional sense.

## Scoring Contract

Primary scores:

- check loss by quantile level;
- interval coverage;
- interval score;
- CRPS approximated from the synthesized quantile grid;
- runtime;
- fit status and failure classification.

Optional event scores:

- Brier score for flood-threshold exceedance;
- reliability summaries for threshold events;
- lead-stratified event performance.

Calibration language in the manuscript should be empirical and score-based.
Do not claim calibrated Bayesian uncertainty from the working likelihood alone.

## Reproducibility Gates

No result should be promoted to the manuscript until these gates pass.

Gate 0: input registration and audit

- all local files listed in the manifest exist;
- hashes match;
- schemas match `expected_schema.yaml`;
- date ranges, row counts, and column counts are recorded and verified against
  the files.
- required inputs are distinguished from optional covariates before modeling.

Gate 1: panel audit

- no duplicate origin-target-member rows;
- no target leakage;
- split labels are mutually exclusive;
- horizon definitions are internally consistent;
- missing ensemble members are either absent by design or flagged.

Gate 2: model-grid audit

- all fit IDs are unique;
- model IDs group the separately fitted quantile levels used for synthesis;
- quantile levels are in `(0,1)` and sorted;
- seeds and reservoir settings are explicit;
- ridge and RHS roles match the manuscript framing.

Gate 3: smoke fit

- one cutoff, one or two horizons, median only;
- raw GloFAS and reference-only Q-DESN complete;
- discrepancy Q-DESN completes;
- fit-status table materializes.

Gate 4: pilot fit

- full quantile grid on a small cutoff set;
- scoring tables materialize;
- quantile synthesis is monotone after post-processing;
- no promoted claim depends on failed cells.

Gate 5: prelaunch dry run

- the AL-MCMC discrepancy bridge completes on the dry-run configuration;
- input diagnostic figures are present and readable;
- prediction, scoring, fit-status, and provenance tables are present;
- article and engine git states are clean;
- R executable path, R version, `R_HOME`, and `.libPaths()` are recorded;
- the run is explicitly marked as a pilot or prelaunch dry run.

Gate 6: final run

- full cutoff set;
- all planned models;
- score tables, diagnostics, and provenance table complete;
- R executable path, R version, `R_HOME`, and `.libPaths()` are recorded;
- manuscript tables and figures regenerated from the final run ID.

## Documentation Standard

Each script should begin with a short header containing:

- purpose;
- input files;
- output files;
- configuration file;
- expected run directory;
- failure behavior.

Each function file should contain application-specific helpers only. If a
function is general Q-DESN machinery, it belongs in the computational package
or in a clearly marked vendored module, not mixed into application glue.

Each run should be restartable. A failed run must write a failure state with
the stage, input manifest, model ID, seed, error message, and traceback when
available.

## Implementation Phases

Phase 1: scaffold and contract

- create the tracked directories;
- complete `expected_schema.yaml`;
- register the frozen bundle and generate `input_manifest.csv`;
- write the input-bundle audit tables;
- add placeholder config files.

Phase 2: input and panel builders

- implement `00_check_inputs.R`;
- implement `01_build_panel.R`;
- implement pre-model input-diagnostic figures;
- write `test_input_contract.R` and `test_no_leakage.R`.

Phase 3: model wrappers

- pin the `exdqlm` dependency or vendor a minimal Q-DESN module;
- implement reference-only and discrepancy Q-DESN wrappers;
- run the median-only smoke workflow.

Phase 4: scoring and synthesis

- implement quantile-grid synthesis;
- implement scoring by origin, horizon, and model;
- generate pilot tables.

Phase 5: manuscript outputs

- generate final table and figure files;
- update Section 9 only from audited outputs;
- update provenance documentation.

## Current Recommendation

This blueprint is the current path: it is reproducible, readable to a new repo
visitor, and strict enough to prevent local exploratory work from leaking into
manuscript claims. Phase 1 and Phase 2 should finish before model-specific
MCMC or VB derivations are wired into the application.
