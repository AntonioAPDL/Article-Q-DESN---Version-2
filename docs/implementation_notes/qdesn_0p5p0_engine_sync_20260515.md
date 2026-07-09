# Q--DESN 0.5.0 Engine Sync Audit

Date: 2026-05-15

## Scope

This audit records the application-side sync from the older GloFAS discrepancy
Q--DESN worktree to the 0.5.0-compatible exdqlm/Q--DESN source. This was a
source, API, wiring, and documentation sync only. It was not a validation
relaunch and not a main application-model launch.

No expensive fit command was run. In particular,
`application/scripts/run_all.R --preflight` was intentionally not used because
that wrapper proceeds into `03_fit_models.R`.

## Article Repository State

Before the sync:

```text
repo: /data/jaguir26/local/src/Article-Q-DESN
branch: application-ensemble-likelihood-redesign
HEAD: eef79ec05a733b3d5e89be66dc36c24937c4a3ae
subject: Update latent path main launch reservoir and RHS prior
upstream: origin/application-ensemble-likelihood-redesign
```

The cancelled run
`latent_path_main_al_vb_n1000_m360_20260515_024133` was inspected only. No
active process matched that run id, and its logs showed early-stage artifacts
with an intentional `03_fit_models` cancellation status. The run directory was
not modified.

## Engine Source

The application now pins the local engine source to:

```text
path: /data/jaguir26/local/src/exdqlm__wt__qdesn_fitforecast_0p5p0
branch: feature/qdesn-fitforecast-validation-0p5p0
commit: 1417a825d24a6ac805b3b4af8033bb8e14a29187
subject: Prepare Q-DESN fit forecast validation on 0.5.0
package version: 0.5.0.9000
runtime: /home/jaguir26/.local/bin/Rscript
R version: 4.6.0
```

The important included base commit is
`10ac1abe455988c3237d7eeda83b001f92351cf3`, subject
`Fix forecast horizon handling for future fGG`.

The new source exports the package Q--DESN feature and readout APIs needed by
the article-side latent-path fitter:

```text
qdesn_build_design
qdesn_fit
qdesn_fit_vb
qdesn_fit_mcmc
```

It does not export the older `qdesn_fit_discrepancy()` function. The
application therefore treats that export as required only for the legacy
origin-state bridge. The current latent-path ensemble-likelihood workflow uses
the engine for fixed DESN feature construction and performs the AL-VB latent
path fit in article-side code.

## Compatibility Gates Added

The engine contract now records and checks:

- configured source path;
- load mode;
- engine branch;
- engine commit;
- package version;
- required exports;
- whether the source-policy gate passed;
- known disallowed stale paths.

The source-policy gate fails loudly if the active engine source is an old
0.4.0-era worktree, an origin-state-only worktree, a stale `/home/...` path, an
unexpected branch, an unexpected commit, or a package version below the
configured minimum.

The helper that decides whether `qdesn_fit_discrepancy()` is required now uses
the model contract. For `latent_path_ensemble_likelihood` rows, the export is
not required; for legacy origin-state rows, it remains required.

## Files Changed

Core wiring:

- `application/R/engine_contract.R`
- `application/R/launch_readiness.R`
- `application/scripts/00_check_inputs.R`
- `application/scripts/03_check_model_design.R`
- `application/scripts/03_fit_models.R`
- `application/scripts/06_preflight_launch.R`

Tests:

- `application/tests/test_engine_contract.R`

Configuration and documentation:

- application configs under `application/config/`
- `application/config/README.md`
- `application/R/README.md`
- `application/README.md`
- `application/scripts/README.md`
- relevant implementation notes under `docs/implementation_notes/`

## Verification Run

Safe checks run:

```text
Rscript -e '<parse every application/config/*.yaml>'
Rscript - <<'RS' ... app_check_qdesn_engine_api(...) ... RS
Rscript - <<'RS' ... tiny qdesn_build_design smoke ... RS
Rscript - <<'RS' ... app_launch_engine_checks(...) ... RS
Rscript application/tests/run_tests.R
```

Observed results:

- all application YAML files parsed;
- the main latent-path config resolved the intended 0.5.0-compatible source;
- the required Q--DESN exports were available;
- `qdesn_fit_discrepancy()` was not required for latent-path rows;
- the stale origin-state worktree failed the source-policy check;
- launch-engine checks passed without writing run artifacts;
- the application test suite completed successfully;
- the legacy discrepancy-fit adapter test skipped because the current engine
  does not expose the legacy `qdesn_fit_discrepancy()` API.

## Checks Intentionally Not Run

The following checks were intentionally not run:

- the cancelled main run id was not resumed;
- `application/scripts/run_all.R --preflight` was not run;
- `03_fit_models.R` was not run;
- `06_preflight_launch.R` was not run on the cancelled run directory because
  that would write into generated run outputs;
- no input/design gate was re-run, because this sync did not require
  regenerating application artifacts.

## Remaining Risks

- Legacy origin-state configs now point at the new source path but should fail
  closed at fit time unless the legacy package-side discrepancy export is
  restored or those configs are revised.
- The current application launch target is still the article-side
  latent-path AL-VB model. Any MCMC or exAL launch should wait for the
  corresponding article-side or package-side implementation gate.
- This sync verifies source compatibility and API wiring. It does not validate
  statistical performance.

## Next Command

Do not run until explicitly approved:

```sh
Rscript application/scripts/run_all.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --run_id latent_path_main_al_vb_n1000_m360_YYYYMMDD_HHMMSS \
  --preflight true \
  --confirm_final_launch true
```

Because `run_all.R --preflight` enters `03_fit_models.R`, this command is the
main launch path, not a harmless readiness check.
