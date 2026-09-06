# PriceFM Stage-R65 independent structured-exAL VB launch

Date: 2026-08-29

Status: full production campaign launched in the background. Validation closeout,
test access, registry mutation, article mutation, joint fitting, and MCMC remain
blocked.

## Scientific contract

- Authority: the complete 114-case Stage-R62 matched seven-quantile surface.
- Unit of fitting: one region/fold case per process, with seven atomic quantile
  components at `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`.
- Existing case-specific DESN and information-set specifications are retained.
- AL is refit only as a parity control and same-quantile warm start.
- The candidate is independent exAL VB with the structured sigma-gamma update.
- Selection is validation-only and compares complete seven-quantile bundles;
  component-wise likelihood-family cherry-picking is prohibited.
- Test data are not loaded by the runner.

The pinned `exdqlm` source is commit
`cc85a75ceca51c6e6a699147c45742591c7e3679`. Each generated case config also
pins SHA-256 hashes for the adapter, metric summarizer, R65 case runner, and R65
VB helper. The package is installed once in the immutable runtime library
`application/data_local/pricefm/runtime_libraries/exdqlm_cc85a75` in the
artifact repository.

## Production surface

| Item | Value |
|---|---:|
| Region/fold jobs | 114 |
| Quantile components | 798 |
| Background workers | 20 |
| Numerical threads per worker | 1 |
| CPU IDs | `3,4,5,6,7,8,9,10,11,15,16,17,18,19,20,21,22,24,25,26` |
| Test access | blocked |
| Registry/article mutation | blocked |
| Joint/MCMC fitting | blocked |

The selected CPU IDs represent 20 distinct physical cores and avoid the CPUs
explicitly pinned by the active joint-validation workers at launch time.

## Paths

- Run tag: `pricefm_stage_r65_independent_structured_exal_vb_20260829`
- Tmux session: `pricefm_stage_r65_20260829`
- Grid: `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/experiment_grids/pricefm_stage_r65_independent_structured_exal_vb_20260829`
- Runs: `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runs/pricefm_stage_r65_independent_structured_exal_vb_20260829`
- Launch log: `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/logs/pricefm_stage_r65_independent_structured_exal_vb_20260829.tmux.log`
- Preparation evidence: `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r65_independent_structured_exal_vb_prep_20260829`

## Validation before launch

- Focused Python suite: `19 passed`.
- R source parse: passed.
- Tiny real AL-to-structured-exAL helper fit against the installed pinned
  package: passed.
- Generated production-case preflight: passed, with exactly seven quantiles,
  train/validation splits only, pinned source hashes, and `test_loaded=false`.

## Attempt history

The first operational attempt exited before adapter construction or fitting.
R's `normalizePath()` resolved the Python virtual-environment symlink to the
system interpreter, which lacks PyYAML. All 114 case commands therefore failed
in approximately two seconds with no model artifacts. Its launch log, status,
summary, and preflight are preserved at:

`/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/logs/pricefm_stage_r65_independent_structured_exal_vb_20260829_attempt_01_early_python_env_failure`

The runner now preserves the configured virtual-environment executable path.
The complete validation gate was rerun, the generated configs were refreshed
with the corrected runner hash, and the same campaign tag was resumed. Initial
post-launch checks found one launcher, 20 case runners, and 20 adapter builders
active on distinct CPUs, with ample memory and disk and no second-attempt error.

## Closeout boundary

After all 114 metric summaries exist, run the Stage-R65 closeout. Do not open
test data or change the registry or article before AL parity, structured-update
telemetry, complete-bundle validation selection, and reproducibility checks all
pass. The closeout itself remains a validation-only decision queue.

## Superseding early-stop decision

R65 was stopped after a structured sigma-gamma production defect was isolated.
Its frozen evidence and the corrected Stage-R66 continuation contract are
documented in
`pricefm_stage_r65_early_stop_r66_corrected_structured_exal_vb_20260829.md`.
R65 must not be resumed, and its exAL fits are not eligible for reuse.
