# PriceFM R128 Reproducibility Contract

This is a bounded development pilot, not an article promotion or a complete
cohort replacement. It reuses 111 certified BG Normal RHS fits for forecast-only
rescoring and fits HR/DK_1 with a train-only selected pure all-layer DESN.
No MCMC, joint or exAL fits are launched. The old R98 exAL method remains a
separately labeled reference. All three official folds are reported.

## Source Dependency

Base: `origin/main` at `e2a3be97853b1af9c8cb269a3e065336ca5590f3`.
Main does not yet include the frozen PriceFM numerical helpers. R128 therefore
requires a clean read-only worktree at
`1e24342e1ecd2dd7a99d8df2445f29be7f7a03d2`, available on
`origin/work/pricefm-r127-closeout-20261008`. No merge is performed here.
The complete dependency's executable source hashes are sealed at preparation.

The detailed locally ignored plan is
`local_trackers/pricefm_stage_r128_stochastic_regional_pilot_master_plan_20261008.md`.
The protocol, source and tests are tracked; all raw data, fitted objects,
predictions, traces, resource snapshots and release receipts remain below the
ignored `application/data_local/pricefm` root. Do not publish these to Overleaf.

## Execution

Use the pinned PriceFM venv Python and R4.6.0, one numerical thread per worker.
Supply `PRICEFM_R128_DEPENDENCY` when running focused pytest tests. Without that
explicit external runtime, generic repository tests skip the integration suite;
the launch release rejects any skipped test or missing dependency.

1. Commit the dedicated branch; run `pricefm_r128_release.py --dependency WT
   --output RELEASE_DIR` on both hosts.
2. On Jerez run `456_run_pricefm_stage_r128_stochastic_pilots.py prepare
   --dependency WT --release RELEASE_DIR/validation.json`.
3. Run its `controller --workers 15` detached. It admits distinct idle physical
   cores, passes the reusable three-task smoke gate, then automatically schedules
   ridge, certified Normal RHS, nested AL, official forecasts and closeout.
4. Read campaign `progress.json`, `heartbeats/`, `blocked.json` if present and
   `terminal.json`. A failed certification is not a successful fit.

One controller lock prevents concurrent dispatch. Live own workers block an
interrupted-controller restart; sealed completed tasks are reused. Unsealed
partial artifacts are preserved for explicit audit, never silently overwritten.
Exact AL optimizer continuation is not supported by compact summaries; only
the declared beta/sigma warm-start mapping is supported.

## Interpretation

The screening change compares genuinely generated stochastic Normal paths
with the old mean-recursion proxy. For conjugate ridge, beta and omega retain
their correct dependence; for Normal RHS VB, the declared mean-field draws
are independent. Parameter draws stay fixed within a trajectory. Both move
the reservoir each step and teacher force only between origins.

No official test score chooses a winner. Region inputs, architecture and tau0
are frozen using three expanding splits inside fold1 training. The two pilots
are deliberately chosen development regions, not a random confirmatory cohort.
The final quantile forecast is the clipped-tail pooled-CDF inverse of seven
independent AL readouts using a Normal driver, not a joint posterior predictive
draw or an MCMC result. Future exogenous quantities are the released realized
values. These limitations must accompany any later scientific comparison.

Authority and manuscript integration remain explicitly deferred. A future
coordinator handoff requires all intended regional fits, forecasts, metrics,
source/result hashes and completion/exclusion counts, and a fresh clean Git
state. R128 alone does not authorize the complete 38-region launch.
