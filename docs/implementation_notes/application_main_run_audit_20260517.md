# Article-Q-DESN Main Run Audit, 2026-05-17

## Run

- Run id: `latent_path_main_al_vb_n1000_m360_20260515_221729`
- Config: `application/config/glofas_latent_path_al_vb_dec25_main.yaml`
- Article commit recorded by the run: `6b2e4d51af68db2d20db1c194ab45549194833f1`
- Validation worktree: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Validation branch: `validation/shared-fitforecast-v2-1.0.0`

## Health Summary

The expensive application fit completed, scoring completed, manuscript-output staging completed,
and post-fit analysis completed. The original `run_all.R --preflight true` command exited with
code `1` because `06_preflight_launch.R` failed the final readiness gate.

Successful run artifacts include:

- `tables/fit_status.csv`
- `tables/prediction_quantiles.csv`
- `tables/posterior_draw_predictions.csv`
- `tables/score_summary.csv`
- `tables/post_analysis_manifest.csv`
- post-fit diagnostic figures under `figures/post_fit_analysis/`

The fit wrote 56,000 posterior-draw prediction rows and 28 Q-DESN summary prediction rows.

## Root Cause

The Article configuration still pinned the validation engine commit to
`198cff1d6b3a7bb0b7ed3c56460b0c94c9c3fe82`, but the validation worktree advanced during the
long application fit to:

`e4e6dc0f7976c1464e91231557f9212914e7438a`

The current validation worktree is clean, synchronized with
`origin/validation/shared-fitforecast-v2-1.0.0`, and still reports package version `1.0.0`.

The launch-readiness failures were therefore provenance/guard failures, not fit-output failures:

- `qdesn_engine_api`
- `qdesn_engine_source_policy`
- `qdesn_discrepancy_required_fit_support`

The third failure cascaded from the stale commit pin: once the source policy failed, the engine
support check reported the required latent-path AL-VB fit as unsupported.

## Fix Applied

Article configs, docs, and tests were repinned to:

`e4e6dc0f7976c1464e91231557f9212914e7438a`

`application/scripts/03_fit_models.R` now records the engine branch/SHA at fit-stage entry and
checks them again before writing each Q-DESN fit manifest row. A future mid-fit validation-worktree
advance now fails inside `03_fit_models.R` with an explicit engine-drift error instead of allowing
the mismatch to surface only at the final readiness gate.

## Recheck Policy

The original run-level `main_launch_exit_code.txt` remains a historical record of the original
end-to-end command and should not be edited. After repinning, rerun only the targeted
`06_preflight_launch.R` audit against the existing run directory to regenerate
`launch_readiness_report.csv` and `launch_readiness_summary.txt`.

If the targeted preflight passes, the existing fit outputs are usable as the completed application
run artifacts, with this audit note documenting the stale-pin diagnosis and the subsequent
Article-side guard hardening.
