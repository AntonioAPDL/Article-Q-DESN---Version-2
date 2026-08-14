# GloFAS distributional selection after historical-fit recovery

The historical-fit recovery grid established that the previously strong median
fit is reproducible and that its dominant mechanism is the direct lagged
response/precipitation/soil readout block. It did not identify an article-facing
distributional winner: all ten recovery candidates were fitted only at
`p = 0.50`, and the reported absolute-error quantity is not a synthesized CRPS.

## Frozen shortlist

The follow-up preserves four distinct roles instead of promoting the smallest
median loss mechanically:

| Candidate | Role |
|---|---|
| `fr08_direct360_tight_prior` | Best full-history median fit |
| `fr06_direct360_alpha010` | Best recent median fit |
| `fr09_direct180_alpha010` | Lower-cost recent-fit safeguard |
| `fr01_historical_parity` | Exact historical reproduction control |

The differences between the first two candidates are too small to interpret as
a substantive ranking before tail behavior and calibration are observed.

## Selection sequence

1. Fit only the missing `p05` and `p95` components for each shortlisted
   candidate. The existing `p50` fit is reused through an explicit source
   manifest. Tail fits may initialize the coefficient state from the matching
   p50 object, but they must optimize independently and may not reuse its future
   latent path or scale state.
2. Combine the three independently fitted quantiles on common pre-cutoff dates.
   Report independent and isotonic-adjusted pinball loss, interval diagnostics,
   crossings, and a clearly labelled three-point integrated quantile score.
   This stage is a screening approximation, not full CRPS.
3. Subject at most two finalists to cold-start median replay at the audited
   2021-12-21 and 2022-05-11 forecast origins. Those bundles use the same
   long-history GloFAS v3.1 source as the 2022-12-25 application. Realized
   precipitation and soil moisture may be used only under the explicit oracle
   diagnostic contract. No final-cutoff fit may initialize a historical replay.
4. Prepare the missing `p15`, `p35`, `p65`, and `p80` components for at most two
   finalists. Full-seven synthesis then supplies the first defensible
   observed-window grid CRPS comparison.
5. Freeze the observed-window winner before inspecting the held-out forecast
   window. Article promotion requires complete full-seven evidence and the
   usual provenance, diagnostics, figure, and compilation gates.

## Reproducibility and artifact policy

Tracked shortlist/cutoff registries define scientific intent. Preparation
scripts materialize immutable runtime configs and record source hashes. Every
fit runs in a bounded scheduler with a unique run ID, core assignment, status
record, and completion marker. Runtime objects remain outside Git. Heavy fit and
design objects are retained until the corresponding synthesis has passed; any
later cleanup requires an explicit completed-run check and preserves configs,
logs, tables, figures, and provenance.

The workflow deliberately separates preparation, launch, health reporting,
triage finalization, blocked validation, and full-seven confirmation. A stage
may prepare its successor, but it may not silently launch across an unresolved
scientific gate.

## Implemented workflow

The implementation is split into one reusable scoring module and explicit
stage entry points:

- `application/R/glofas_fit_recovery_selection.R` validates quantile-source
  manifests, aligns fitted histories, applies the declared post-hoc isotonic
  projection, computes per-date and window summaries, audits convergence and
  warm starts, and ranks Stage A candidates.
- `glofas_fit_recovery_triage_prepare.R` and
  `glofas_fit_recovery_triage_finalize.R` materialize and close Stage A. The
  watcher runs the finalizer only after all eight missing tail fits complete.
- `glofas_fit_recovery_blocked_prepare.R` materializes cold-start historical
  replays only for explicitly approved finalists. The corresponding finalizer
  verifies the oracle covariate label before scoring.
- `glofas_fit_recovery_full7_prepare.R` and its finalizer require an explicit
  full-seven approval, cap the comparison at two finalists, and retain the
  held-out 2022-12-25 forecast score outside observed-window selection.

The p50 recovery scorer now accepts any single quantile level. Its generic
columns are `check_loss_mean` and `absolute_error_mean`; the legacy p50 aliases
are populated only for `p = 0.50`, which prevents a tail loss from being
misreported as a median score.

## Validation evidence

The Stage A runtime root is
`local_trackers/runtime_configs/glofas_fit_recovery_triage_20260731`. Its
prepared manifest contains eight fits, two tails for each shortlisted
candidate. The copied application panel has SHA-256
`a815c093733ea411dffb40a678c50454d0291c60fa393b73b68d15ddfdb9ca1c`,
identical to the audited p50 panel. A real p05 design preflight verified the
two-block contract, 1,383 coefficients per block, 2,766 coefficients in total,
and the expected independent reservoir seeds.

Stage A inherits the current final-cutoff application policy
`gefs_realized_blend`, which uses realized-future covariate corrections and is
therefore not a deployable forecast-covariate contract. The policy and provider
are recorded in the source manifest and ranking. Stage A remains useful as an
in-sample distributional triage, but it must not be presented as clean
out-of-sample or operational validation; blinding here concerns the withheld
USGS forecast score, not all future covariates.

The historical-replay preparer was also exercised without launching a fit. It
built separate panels for the 2021-12-21 and 2022-05-11 cutoffs, with no missing
reference or GloFAS observations. Both generated configs are cold-started and
carry `future_policy: oracle_realized` with provider
`realized_future_oracle`. This test demonstrates wiring only; it is not
scientific approval to run Stage B.

Targeted R tests cover arbitrary-quantile scoring, isotonic adjustment,
crossing diagnostics, integrated quantile loss, window summaries, and ranking.
Python tests cover scheduler state, restart reconciliation, process identity,
completion-marker handling, and manifest-integrity failures. Before launching,
the scheduler verifies config, model-grid, and warm-start hashes; it also
requires run and log paths to remain inside the owned runtime root. All new R
scripts pass parser checks, the watcher passes `bash -n`, and the Python
scheduler/health scripts pass bytecode compilation. The Stage A finalizer and
full-seven preparer were additionally verified to fail closed when their
completion or approval gates are absent.

## Decision boundary

Only Stage A is eligible for immediate execution. Completion of Stage A creates
a recommendation, not an approval. Stage B and Stage C remain separate human
decisions because they answer different questions: historical portability and
full-grid distributional quality, respectively. No article table, figure, or
claim should change until a complete seven-quantile candidate has passed the
declared provenance and diagnostic gates.
