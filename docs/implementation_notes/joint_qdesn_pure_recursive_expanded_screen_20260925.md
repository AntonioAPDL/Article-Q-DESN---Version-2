# JOINT pure-DESN expanded screening continuation

Date: 2026-09-25

## Decision

The completed narrow ridge/RHS screen is valid, but its selected winners show
material boundary pressure. Five of eight winners use the maximum screened
response lag (`m=10`), seven use the maximum screened leakage (`alpha=0.80`),
and six use a spectral-radius endpoint. Three use the maximum depth (`D=3`).
By contrast, six winners use only 24 retained states and the other two use 48;
none selects the 96- or 192-state options.

The scientifically efficient response is therefore an additive expansion of
memory and reservoir dynamics, with a moderate total-capacity extension. It is
not defensible to discard the completed campaign, nor to allow 300 states in
every layer. Under the pure all-layer readout, four 300-state layers would
create 1,200 coefficients and an 8,400-dimensional seven-quantile joint block.

## Frozen expanded domain

- response lags: `1,2,3,5,8,12,15,24,30,45,60,75,90,120,150`;
- exogenous lags: `0`, because the synthetic registry has no genuine
  exogenous stochastic predictor;
- shared leakage: continuous `[0.01,0.99]`, sampled on a logit scale;
- shared spectral radius: continuous `[0.20,0.99]`;
- depth: `1,2,3,4`;
- total all-layer state budget: `20,40,75,100,150,200,250,300`;
- width shapes: flat and tapered;
- input scale: `0.10,0.25,0.50`;
- recurrent connectivity: `0.05,0.10,0.20`;
- input connectivity: `0.25,0.50,1.00`;
- reservoir seed: fixed at `202609250`.

The search support contains the exact 256 source candidates plus 512 new
deterministic Halton candidates per family. Explicit endpoint and previous-axis
anchors supplement the continuous construction. The combined 768-candidate
pool remains case-specific even though all families use common search support.

## Reuse and leakage contract

The source campaign must finish successfully before this continuation starts.
All 6,144 source ridge workers are imported only after their manifests and
architecture identities verify. Their summaries are rewritten only for target
worker identity and fixture path, and both source and target manifest hashes
are recorded. The 12,288 genuinely new ridge fits are then run.

The combined ridge frontier advances 64 architectures per family through the
unchanged five-value RHS grid and three observational replicates. Any exact
source RHS worker still present on that frontier is imported using the same
identity and manifest checks. All remaining RHS workers are fitted normally.

Selection continues to use only 350 observational training rows and 150
recursive-calibration rows. The 1,000 protected validation rows and article
fixtures remain forbidden. Teacher forcing occurs only when the rolling origin
advances; leads within each 30-step block are recursive.

## Runtime boundary

The deferred scheduler waits for both the source controller exit code `0` and
`COMPLETE_WITH_PATH_AND_MEAN_STATE_SCORE_PACKETS`. It does not modify, stop, or
inspect partial source outputs for selection. Once the source workers release
the lease, the new launcher uses the same 15 distinct physical CPUs `2-16`, one
numerical thread per worker, and at least 100 GiB free under `/data`.

This campaign stops after expanded RHS selection and writes a source-versus-
expanded comparison plus winner-boundary audit. It does not automatically fit
quantile VB, launch MCMC, alter article assets, or publish Overleaf. Those steps
require a separate reviewed freeze.

## Reproducibility surface

- contract: `application/config/joint_qdesn_pure_recursive_expanded_screen_contract_v2.csv`;
- axes: `application/config/joint_qdesn_pure_recursive_expanded_candidate_axes_v2.csv`;
- implementation: `application/R/joint_qdesn_pure_recursive_expanded_screen.R`;
- execution: `application/scripts/launch_joint_qdesn_pure_recursive_expanded_screen.sh`;
- deferred gate: `application/scripts/schedule_joint_qdesn_pure_recursive_expanded_screen_after_current.sh`;
- focused test: `application/tests/test_joint_qdesn_pure_recursive_expanded_screen.R`.

No source campaign, historical JOINT authority, PriceFM, GloFAS, article, main,
or Overleaf file is modified by this continuation.
