# Joint QDESN Phase 118 exAL Tail-Calibration Readiness

## Purpose

Phase 118 prepares the next joint-QDESN validation stage after the manuscript
integration and Phase 116/117 article-readiness work.  The current article
evidence is reproducible and table-ready under conservative wording, but the
exQDESN rows remain less accurate than the AL QDESN rows in the oracle
quantile-path summaries.  The main diagnostic pattern is not a noncrossing
failure: exQDESN is raw-noncrossing in the committed article table.  The issue
is tail geometry, especially tail fan width and calibration.

The goal of Phase 118 is therefore to write a targeted, pre-registered VB
calibration screen for exAL tail behavior.  It is not an unconstrained model
search and it is not a reason to overwrite the current article assets before a
fresh validation confirmation.

## Current Diagnosis

The committed article summary reports:

| Row | Forecast MAE | Raw crossings | Diagnosis |
|---|---:|---:|---|
| Joint QDESN RHS | 0.096 | 2 | Primary article anchor. |
| Independent QDESN RHS | 0.098 | 71 | Similar realized scores, larger raw monotone-adjustment burden. |
| Joint exQDESN RHS | 0.145 | 0 | Stable/noncrossing, but farther from oracle quantile paths. |
| Independent exQDESN RHS | 0.133 | 0 | Better than joint exAL here, still behind AL on oracle recovery. |

When a Phase 114/116 tau summary is supplied, Phase 118 records the specific
tail rows that motivate the next screen.  In the latest historical audit, the
largest exAL gaps were at the tails, especially tau 0.95.  If the tau summary is
not present in the v2 clone, the readiness layer falls back to the committed
model-level table and labels the tail audit as aggregate-only.  This keeps the
new repository portable while allowing deeper local caches to be used when
available.

## Implemented Files

- `application/R/joint_qdesn_calibration_screening.R`
  - Adds Phase 118 helpers for article-asset verification, current metric
    diagnosis, scenario winner diagnosis, optional tau-gap ingestion, candidate
    registry construction, selection policy, launch commands, and artifact
    writing.
- `application/scripts/118_prepare_joint_qdesn_phase118_exal_tail_calibration_readiness.R`
  - Regenerates the Phase 118 readiness artifact.
- `application/tests/test_joint_qdesn_phase118_exal_tail_calibration_readiness.R`
  - Verifies registry validity, article asset hashes, optional tau-summary
    ingestion, launch-command schema, and artifact manifest completeness.

The default output is ignored by git:

```text
application/cache/joint_qdesn_phase118_exal_tail_calibration_readiness_20260709
```

## Candidate Registry

The Phase 118 registry keeps the current selected controls as the baseline:

```text
tau0 = 0.5
zeta2 = 16
alpha_prior_sd = 0.5
gamma_init_policy = zero
rhs_vb_inner = 10
adaptive_vb_max_iter_grid = 1440,1920
```

It then tests a broad but targeted set of common-control candidates:

- scalar alpha-prior width: 0.60, 0.75, 1.0, 1.25, and 1.5;
- zero, half-default, and default gamma initialization under selected
  promising alpha widths;
- stronger and looser RHS global shrinkage with `tau0 = 0.35`, `0.75`, and
  `1.0`;
- finite beta-cap alternatives `zeta2 = 8`, `16`, `32`, and `Inf`;
- one combined promising-region probe with wider alpha prior, looser RHS
  shrinkage, and weaker finite beta cap;
- a higher RHS/VB inner-loop budget.

These controls are already wired in the existing screening runner.  Tail-specific
alpha vectors, gamma damping, and model-specific exAL controls are explicitly
deferred because they would change the optimizer or comparison contract.

## Selection Rules

The new screen should use gates before metrics.

Hard fail:

- missing or mismatched manifests;
- worker failures;
- nonfinite quantiles, scores, or scale summaries;
- train/validation leakage;
- reported contract quantile crossings.

Review:

- raw crossings or large monotone adjustments;
- high VB max-iteration pressure;
- exAL tail gaps that improve only marginally;
- runtime too large for a later MCMC reference.
- any apparent exAL improvement that also degrades the AL Joint QDESN anchor or
  worsens realized-score diagnostics.

Promotion candidate:

- exAL tail truth-MAE gaps at tau 0.05, 0.90, and 0.95 decrease materially;
- Joint QDESN RHS does not degrade by more than the declared tolerance;
- check loss, CRPS-grid, hit rates, and coverage remain stable or improve;
- the selected candidate is confirmed on a fresh validation split or fresh
  replicate seeds before article tables are replaced.

## Commands

Prepare readiness:

```sh
Rscript application/scripts/118_prepare_joint_qdesn_phase118_exal_tail_calibration_readiness.R
```

If a local Phase 116 tau summary is available, pass it explicitly:

```sh
Rscript application/scripts/118_prepare_joint_qdesn_phase118_exal_tail_calibration_readiness.R \
  --tau-summary-path /path/to/tau_sensitivity_summary.csv
```

If fixtures are missing in the v2 clone, regenerate them before launching the
screen:

```sh
Rscript application/scripts/98_generate_joint_qdesn_simulation_dgp_fixtures.R \
  --output-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --registry application/config/joint_qdesn_simulation_dgp_registry_20260706.csv
```

Then run the command recorded in:

```text
application/cache/joint_qdesn_phase118_exal_tail_calibration_readiness_20260709/launch_commands.csv
```

## Why This Is the Right Next Step

A broad search that tries to make exAL look best would be scientifically weak.
The current evidence already supports the main article message for Joint QDESN
RHS, while exQDESN has a specific and interpretable weakness: tail calibration.
Phase 118 targets that weakness with controls that are already implemented and
auditable, while protecting the current AL anchor and requiring fresh
confirmation before any article replacement.

## Next Step

Review the Phase 118 readiness artifact.  If the registry and selection policy
look acceptable, launch the targeted VB screen in the background.  Do not launch
exAL MCMC until the VB screen selects a stable candidate under the declared
gates.
