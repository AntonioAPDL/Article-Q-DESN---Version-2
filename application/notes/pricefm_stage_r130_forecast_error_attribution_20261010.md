# R130: held-out same-fit forecast error attribution

## Audit and scope

R129B completed 36 new public CRAN 1.1.1 independent AL VB fits, six reused
median certificates and 64 forecast batches. The combined pilot is complete.
Frozen source is 04792b20e42349514f918f05917cdbc70bed5a77; R128 source is
42860a864c1d9f81a412ea313cb2b899b1e2ea89; R127 dependency is
1e24342e1ecd2dd7a99d8df2445f29be7f7a03d2. No fitted posterior is changed.

The two-region equal-fold mean AQL is 9.035371 versus R98 10.255699,
cached PriceFM 9.070443 and local Phase-I/II 6.548658. HR improves over
R98, DK_1 worsens. This chosen developmental cohort is not evidence of
all-region superiority. Raw package convergence flags stay false; independent
stationarity certificates pass. There is no automatic larger iteration budget.

## Necessary correction to the earlier diagnostic proposal

Full-fold quantile fits cannot serve as untrained receivers on earlier internal
validation inside their own fitted observations. R130 therefore uses the
temporally held-out post-fit validation gaps before each official test window.
No test forecasts are regenerated and no new AL/Normal fits are needed.
This explicit correction prevents a superficially cheap but contaminated replay.

Midnight-only scoring confounds lead with hour of day. Twelve eligible days
at four shifted origin clocks, two regions and three folds give 288 origins.
H96 is 96 quarter-hour steps, or 24 hours. Every shifted response is contained
in its own validation gap. Overlapping windows are not independent replicates.

## Controls and target separation

Frozen R127 `replay` supplies stochastic Normal, parameter-only Normal,
posterior-mean Normal and diagnostic oracle price paths. Receiving AL draws
are shared across controls. Parameter and likelihood-scale draws are fixed
within a path. States advance at every step, observations enter causal inputs
only before each origin, and oracle truth enters a separate state bank only.
Future-truth poisoning and first-step identity are tested numerically.

No optimizer, prior, DESN, tau0, model family, coefficient covariance or scale
is changed. Scalers are fitted on each corresponding training window and reused.
Retrospective future exogenous covariates remain explicitly declared.
The predictive distribution is the frozen sorted seven-knot clipped CDF pool,
not an identified true density or an AL likelihood draw. Oracle scores do not
constitute a promotable method and never select an architecture on test data.

## Reproducibility and operational safeguards

The successor branch starts from fetched origin/main. Only new PriceFM-owned
files are committed; frozen scientific dependencies are loaded by exact paths.
The ignored master plan is
`local_trackers/pricefm_stage_r130_master_diagnosis_plan_20261010.md`.

Entrypoint: `460_run_pricefm_stage_r130_attribution.py`. Run `release` with
`--dependency` and `--r128`; run `prepare` with these, `--parent` and a matching
`--release`; run `controller --workers 15`. Clean committed source, source-
matched test releases, complete parent seals and fixed validation boundaries
are mandatory. Each fit and input remains frozen and hash-protected.

Schedule: 24 first-origin smoke tasks, then 96 continuation tasks; 120 tasks
cover 288 origins. At most 15 sufficiently idle physical cores are admitted,
one numerical thread per process, with 200 GiB RAM/disk reserves and 0.75 GiB
output cap. The controller locks, excludes duplicate live workers, drains
active children on failure and leaves pending work/evidence intact. Unsealed
partials block a restart instead of being silently deleted or overwritten.

Automatic closeout writes origin-verified validation/lead/clock/driver tables,
an interpretation and PDF. Existing official scores are copied for descriptive
context without selecting a new operator. Runtime, banks, PDFs and model states
remain ignored. No registry/article/main/Overleaf mutation or automatic wider
launch is authorized. The next correction depends on the paired controls, not
on an assumed cause of poor forecasting.
