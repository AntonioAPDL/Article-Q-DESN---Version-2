# GloFAS Application Forward Plan

Date: 2026-05-11

## Purpose

This note records the next reproducibility gates for the GloFAS Q--DESN
application. The current repository has a tested article-side path for importing
the audited jerez inputs, materializing the December 25, 2022 cutoff, checking
the input contract, building the application panel, producing pre-model source
diagnostics, and collecting GEFS/NWM precipitation and soil-moisture handoff
figures. The next work should preserve the same rule: no model fit or
manuscript-facing claim is promoted unless its input, configuration, code, and
output provenance are recorded in the run directory.

## Current Checkpoint

The current manuscript-facing data checkpoint is the audited jerez source
workflow for cutoff `2022-12-25`. It verifies:

- the reference gauge input;
- the GloFAS historical retrospective path;
- the issued GloFAS ensemble forecast at the cutoff;
- GEFS precipitation and soil-moisture forecast inputs;
- local soil-moisture and blended or weighted forecast lineage;
- retrospective source-family evidence;
- the expected post-2021 GloFAS LISFLOOD source for the cutoff;
- generated input diagnostic figures;
- collected GEFS/NWM precipitation and soil-moisture handoff figures.

The local legacy Dec 25 workflow remains available only as a code-path smoke
test. It is not an application data source.

On 2026-05-12 the same source-diagnostic workflow was repeated for all copied
authoritative cutoffs with run ID `authoritative_source_cutoffs_20260512`. The
run completed for cutoffs `2021-01-23`, `2021-11-12`, `2021-12-21`,
`2022-05-11`, and `2022-12-25`. The January 2021 cutoff uses the audited
`glofas_hist_v21_htessel_cons` retrospective source, while the later cutoffs
use `glofas_hist_v31_lisflood_cons`. Each cutoff produced a checked input
manifest, panel summary, source diagnostic figures, and collected handoff
figures in an ignored run directory.

## Gate 1: Human Review of Source Diagnostics

Before model fitting, inspect the Dec 25 diagnostics:

```text
application/runs/dec25_source_figures_authoritative_20260511/figures/input_diagnostics/
application/runs/dec25_source_figures_authoritative_20260511/figures/handoff_diagnostics/cutoff_date=2022-12-25/
```

The review should answer four questions:

1. Does the USGS reference series have the expected timing and scale?
2. Does the GloFAS retrospective path use the audited LISFLOOD source and align
   with the reference calendar?
3. Does the issued GloFAS ensemble begin after the cutoff and cover the intended
   horizon range?
4. Do the GEFS/NWM precipitation and soil-moisture handoff figures match the
   revised-article data-lineage interpretation?

If any answer is negative, stop before fitting models and repair the input
contract or copied upstream lineage.

## Gate 2: Repeat the Source Audit Across Cutoffs

The Dec 25 cutoff is only the checked example. The full application should run
the same source audit for each forecast origin in the final cutoff file.

Required checks for each cutoff:

- `snapshot_source_map.json` and `data_start_filter_summary.txt` are present;
- reference gauge, GloFAS retrospective, issued GloFAS ensemble, GEFS
  precipitation, GEFS soil moisture, blended-input, and retrospective-family
  evidence are found;
- the GloFAS hydrological-model version matches the cutoff date rule in
  `application/config/authoritative_source_requirements.yaml`;
- the materialized bundle has unique keys and positive forecast horizons;
- the input figure workflow produces readable PDF diagnostics;
- the run directory records the input manifest, panel summary, figure manifest,
  git state, and session information.

This gate should produce one audit table per cutoff and one combined summary
table before the main model run is scheduled.

The implemented all-cutoff command is:

```sh
Rscript application/scripts/02_run_authoritative_source_diagnostics.R \
  --run_id authoritative_source_cutoffs_20260512
```

It writes one run directory per cutoff and a combined summary table under:

```text
application/runs/authoritative_source_cutoffs_20260512/tables/
```

## Gate 3: Freeze the Final Application Configuration

After the source audits pass, freeze the final configuration files:

- `application/config/glofas_discrepancy_application.yaml`;
- `application/config/input_bundle.yaml`;
- `application/config/cutoffs.csv`;
- `application/config/quantile_grid.csv`;
- `application/config/model_grid.csv`;
- `application/config/figure_specs.yaml`.

The final configuration must state:

- forecast system: GloFAS;
- reference process and transform convention;
- forecast-origin and horizon protocol;
- prediction contract, including GloFAS quantile source, discrepancy feature
  strategy, and whether the run is limited to issued GloFAS horizons;
- quantile grid;
- reservoir architecture and random seed policy;
- likelihood families to fit;
- regularized horseshoe as the default readout prior;
- ridge only as a dense baseline, if retained;
- MCMC diagnostic fits and VB--LD production fits, if both are used;
- score tables and manuscript-output promotion rules.

Every final configuration file should be copied into the run manifest at launch
time, and its hash should be recorded.

## Gate 4: Package-Backed Dry Run

Before the main launch, run one small package-backed dry run:

- one cutoff;
- one or two quantile levels;
- AL working likelihood first;
- regularized horseshoe prior;
- MCMC inference;
- fixed input manifest;
- fixed reservoir seed;
- no manuscript performance claim.

The run must pass `application/scripts/06_preflight_launch.R`. A passing dry run
requires:

- input and model manifests copied into the run directory;
- article git SHA and engine git SHA recorded;
- configuration hash and design hash recorded;
- fit status table present;
- prediction and score tables nonempty;
- the current pilot prediction tables record `q_g_hat`, `d_g_hat`, `qhat`, and
  contract metadata, and discrepancy rows satisfy `qhat = q_g_hat - d_g_hat`;
- the final application prediction outputs record matched posterior draws
  satisfying `q_y_draw = q_g_draw - d_g_draw`, with point summaries computed
  after draw-level subtraction;
- final discrepancy prediction outputs record
  `q_g_source = posterior_model_quantile`;
- a final application run writes `tables/posterior_draw_predictions.csv` and
  passes posterior-draw table validation;
- engine contract table present;
- diagnostic figures present and readable;
- article repo and engine repo git states recorded;
- run marked as pilot or dry run.

The dry run is a workflow validation, not a scientific result.

See `docs/implementation_notes/glofas_bayesian_workflow_audit_20260512.md`
for the decision record separating the current point bridge from the final
posterior-draw Bayesian prediction contract.

Current environment gate: the article workflow now supports a local-source
engine mode. The pilot and prelaunch configurations load the checked-out
`exdqlm` branch named by `qdesn_engine_repo_hint` and record that branch SHA;
they do not install `exdqlm` from CRAN. The local-source path requires `Rcpp`
because the branch's compiled sampler is called through `RcppExports.R`. A
prelaunch run should be repeated after any code change is committed so that the
fit manifest and launch-readiness report point to a clean article commit.

## Gate 5: Main Launch Decision

The main application launch is allowed only after Gates 1--4 pass. The launch
should use a new run ID of the form:

```text
glofas_qdesn_YYYYMMDD_HHMMSS__git-<shortsha>__cfg-<hash>
```

Before starting the final run, record:

- article commit SHA;
- Q--DESN engine commit SHA;
- input manifest hash;
- application config hash;
- model grid hash;
- quantile grid hash;
- cutoff file hash;
- reservoir seed policy;
- R session information;
- whether the run is final, pilot, smoke, or diagnostic.
- the prediction contract name, contract version, and whether the contract is
  allowed for final manuscript scoring.

No final table or figure should be copied into `tables/` or `figures/` unless it
has a provenance row linking it to the final run directory.

## Minimum Test Suite

Run these checks before committing changes to the application workflow:

```sh
Rscript application/tests/run_tests.R
git diff --check
```

For the audited Dec 25 source path, rerun:

```sh
Rscript application/scripts/00_audit_authoritative_source_bundle.R \
  --bundle_root application/data_local/upstream_jerez/frozen_shared_inputs/exalm_t1_authoritative_20260505 \
  --cutoff_date 2022-12-25 \
  --extra_root application/data_local/upstream_jerez/gefs_nwm_forecast_runs/gefs_nwm_forecast_manifest_source_native_tranche1_20260406T194500Z \
  --run_id authoritative_source_audit_20260511

Rscript application/scripts/materialize_authoritative_cutoff_bundle.R

Rscript application/scripts/00_register_input_bundle.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --bundle_config application/config/input_bundle_authoritative_dec25.yaml \
  --run_id dec25_source_figures_authoritative_20260511

Rscript application/scripts/00_check_inputs.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --run_id dec25_source_figures_authoritative_20260511

Rscript application/scripts/00_audit_input_bundle.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --run_id dec25_source_figures_authoritative_20260511

Rscript application/scripts/01_build_panel.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --run_id dec25_source_figures_authoritative_20260511

Rscript application/scripts/02_make_input_figures.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --run_id dec25_source_figures_authoritative_20260511

Rscript application/scripts/02_collect_handoff_figures.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --run_id dec25_source_figures_authoritative_20260511 \
  --cutoff_date 2022-12-25
```

Generated inputs, caches, manifests, run directories, and copied upstream data
must remain ignored by git. Only source code, configuration, tests, and
documentation should be committed.
