# PriceFM R123 Certified Successor

## Scope and diagnosis

This successor completes only BG Fold-1 training-internal selection. It reuses
1,298 completed Ridge decisions and continues the 63 saved Normal RHS states
belonging to 21 complete three-split candidates. It excludes incomplete groups;
it does not repeat screening, reopen test folds, modify authority or publish.

The frozen diagnosis found an overly permissive coefficient-only convergence
shortcut and severe conditioning in two rejected designs. The RHS global
shape itself is correct: excluding the intercept gives d=p-1 shrunk
coefficients and the half-Cauchy inverse-gamma auxiliary shape (d+1)/2=p/2.
Prior centres remain fixed at zero; transferred states are initialization only.
The successor requires full-state stability and an unjittered inverse residual
at most 1e-5. No diagonal regularization is accepted as a new posterior target.

An additional executed-interface audit found that the historical R123 AL
wrapper sends an unsupported stage label. The shared public-CRAN atom accepts
R122_internal_selection. The successor retains that engine label, records its
own scientific_stage and unique tag, and tests the actual median AL interface.
Frozen predecessor source and outputs are never edited.

## Bounded automatic progression

1. Verify parent, source, runtime, preparation and every saved-state hash.
2. Continue 63 Normal states within the original 2,000-total-iteration cap.
   Require at least ten new stable iterations. Six stronger diagnostic states
   replace their earlier starts. Finite caps retain complete state and traces;
   recognized numerical failures retain explicit failure receipts.
3. Score only fully certified three-split groups. Require at least three
   distinct candidates, rather than the historical unattainable 30-of-30 gate.
   Use at most 64 internal validation origins per split, with unchanged scaling.
4. For up to ten selected structures, fit fixed tau0 multipliers .3 and 3 on
   the same three training splits (at most 60 new Normal fits). Changed tau0
   changes the target deliberately; reuse cached statistics, not the full old
   RHS posterior state. Retain certified centre results if alternatives fail.
5. Select three distinct structures and one tau0 each using complete certified
   groups, mean AQL, late AQL, worst AQL, then candidate ID.
6. Automatically fit nine independent AL ladders through .50, .45/.55,
   .25/.75, .10/.90. Fixed zero RHS prior centres and unfrozen blocks remain
   unchanged. Only matching admissible posterior summaries supply starts.
7. Preserve the established public CRAN exdqlm 1.1.1 fitting interface and
   score-blind raw or paired-cap predictive acceptance. AL predictive eligibility
   is NOT a claim of full variational stationarity. No exAL/joint/MCMC.
8. Forecast all internal origins with 500 Normal RHS recursive price-driver
   paths and the established mean-feature conditional quantile operator.
   Teacher force between origins, never future price within a fixed origin.
   Known-future exogenous inputs keep the existing retrospective convention.
9. Freeze a training-internal choice and evidence ledger. Official validation,
   official test, registry, article and Overleaf remain blocked.

Normal screening uses a cheap conditional-mean recursive score; AL selection
uses stochastic Normal-driven paths. These operators are not interchangeable
and their training-internal AQLs are not official article AQLs. This phase tests
the already agreed pipeline, not every possible forecasting alternative.

## Source, resources and safe resumption

Entrypoint: application/scripts/pricefm/441_run_pricefm_stage_r123_certified_successor.py
Normal atom: application/scripts/pricefm/442_fit_pricefm_stage_r123_certified_normal.R
Protocol: application/config/pricefm_stage_r123_certified_successor_protocol_20261005.json
Run tag: pricefm_stage_r123_certified_successor_20261005

Preparation freezes the clean dedicated branch HEAD, exact runtime source,
processed training windows, parent evidence, targets and contracts. Native
source hashes are checked before scoring and after closeout. Target differences,
corrupt artifacts, ambiguous status and partial evidence block resumption;
no deletion, silent refit or overwrite is permitted. Parent locks are acquired
read-only. A completed-run ledger is verified before returning a frozen result.

Jerez: 15 idle physical cores maximum, allowed 9..15; all numerical thread pools
set to one. Whole physical sibling groups must show <=20% use in a ten-second
sample. Available RAM and disk must remain >=200 GiB. Gates repeat before each
phase. At most nine AL ladders run concurrently, with dependent quantiles
sequential inside each ladder. Bounded resource waiting ends in a clear block.

Launch preparation example, from a clean committed task checkout and pinned
Python environment:

```bash
python application/scripts/pricefm/441_run_pricefm_stage_r123_certified_successor.py \
  --mode prepare --workers 15 \
  --frozen-code-root /data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_r123_connectivity_20261003
```

The same command with --mode controller runs all automatic stages. Detach with
an explicit PID, argv, HEAD and log receipt; inspect initial progress before
leaving it overnight. Never start a second controller on the same namespace.

## Verification and handoff

Focused successor tests cover scope, bounds, incomplete groups, target-preserving
continuation, explicit caps, corruption, no-overwrite, stage compatibility,
score identity, physical CPU siblings and gated automatic progression.
Small real tests exercise both precision acceptance/rejection in the Normal
atom and a median AL fit through the exact CRAN public adapter. They use only
synthetic data in temporary pytest directories, not campaign artifacts.

Run the established R121/R122/R123 regression suites, the Normal/stationarity
R suites and the source-explicit prior gate with pinned R 4.6. Repeat on Jerez.
Reproducibility code and protocol are committed only to a dedicated PriceFM
branch. Ignored local_trackers/ holds the working plan; application/data_local/
holds all generated contracts, states, logs and receipts. No heavy fits or
article assets belong in this commit.

Scientific status remains NOT_READY_FOR_INTEGRATION until the new campaign is
complete, audited and separately frozen. An automatic launch is not a completed
scientific phase, nor evidence of improved official forecast performance.

## Local validation on 2026-10-05

Muscat: 268 Python tests passed, zero failures in 71.46 seconds. The successor's
24 tests also passed independently in 14.85 seconds. All three focused R suites passed
using the pinned R 4.6 executable and single-thread numerical environment.
The stationarity suite checked exact fresh/resumed equality and an independent
Monte Carlo objective check. The real AL smoke fit verified finite parameters,
CRAN 1.1.1 identity and unchanged prior centres, not official forecast quality.
Repeat the complete validation on Jerez before launch and keep its exact test
receipt with the ignored run evidence; do not mutate committed scientific source
after freezing preparation.
