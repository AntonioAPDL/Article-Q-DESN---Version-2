# PriceFM R126 Matched BG Comparison

R126 preserves R123/R124/R125 sources and all reference results. No new screening,
MCMC, joint, exAL, registry, article, main or Overleaf changes are authorized.

## Automated Sequence

1. `pricefm_r126_release.py`: inherited scientific tests, R125 tests, R126 tests
   and four pinned R suites. A matching clean-source receipt gates preparation.
2. `447_run_pricefm_stage_r126_matched_comparison.py prepare`: hashes source,
   frozen parent contracts and existing fits; verifies the raw data snapshot.
3. `controller`: replay 1,194 missing internal candidate-origins in chunks,
   reusing 108 R125 results and 72 existing fits. R124 causal controls must agree.
4. Select one certified A/C candidate by equal-split mean clipped-CDF AQL.
   Capped B remains diagnostic. Freeze the full specification, tau0 and operator.
5. Materialize three complete train-only designs. Fit three certified Normal RHS
   parents, then seven AL levels per fold in the median-outward dependency order.
6. After convergence gates pass, forecast all 365 official daily origins with
   500 Normal-RHS recursive paths at H96 (24 hours). States evolve each step;
   observations update history only between daily origins. No future price input.
7. The Muscat `449 ... watch` process automatically imports a hash-verified,
   bounded return containing predictions and diagnostics, leaving heavy fits on
   Jerez. It replays cached PriceFM inference only when retained predictions are
   absent, then compares the candidate, R98, cached Phase I and local Phase I/II.

The controller uses at most 15 workers, one BLAS/R thread each on distinct
physical cores selected from a fresh utilization sample. Resource reserve gates
retain pending tasks and drain existing children. A worker failure prevents later
stages. Complete artifacts are sealed; partial outputs are never overwritten.
No statistical-target-changing fallback or automatic iteration-budget inflation
is allowed. AL full fit objects and raw traces are retained, but the public API's
exact optimizer resumption is not claimed merely because an object was saved.

## Statistical Contract

The selection support is inside official Fold-1 training only. Later fold
validation/test scores cannot choose the shared specification. Each full fold
fits parameters and transformations on its own permitted train interval; actual
likelihood rows begin at the declared common new-model burn-in (Feb 4, 2022).
Those rows differ from R98/PriceFM early fitting rows. Comparability means equal
permitted training dates, raw snapshot and forecast information, not identical
architectures or exact response-row sets.

Independent AL fits use exact public CRAN exdqlm 1.1.1 APIs. Normal inference
uses the separately declared existing Normal adapter. Warm starts supply beta
and scale starting values only; zero-centered destination priors and tau0 remain
fixed. There is no frozen RHS warm-up block in the new AL fits.

CDF pooling is an explicitly completed distribution from seven conditional
quantile knots; it is not an identified true predictive density or the AL working
likelihood. Sorting, independent-level draw coupling and clipped endpoint tails
are declared conventions. Linear tails and mean/path/Normal outputs are secondary
controls and cannot become the winner after official scoring.

All scores use canonical raw EUR/MWh outcomes, exact fixed-market-clock dates,
seven levels and 96 quarter-hour horizons. Existing reference truth differences
are bounded by the previously measured float32 round trips, not arbitrary date
tolerances. Primary BG AQL is the equal three-fold mean, with no factor of two.
Future supplied exogenous values are realized retrospective covariates. Cached
PriceFM's pretraining exposure is unresolved; local Phase-I/II is separately
validation-selected, not the authors' unreleased full search.

Historical tests have already informed development: this is a firewalled
retrospective pilot, not pristine prospective confirmation. Improvement in BG
could justify a prespecified broader cohort, not automatic all-region promotion.
The coordinator alone integrates article-safe results after a frozen handoff.

## Entry Points

On the clean dedicated R126 checkout, using the pinned PriceFM Python:

```bash
python -B application/scripts/pricefm/pricefm_r126_release.py --output RELEASE --cpu CPU
python -B application/scripts/pricefm/447_run_pricefm_stage_r126_matched_comparison.py prepare --receipt RELEASE/validation.json
python -B application/scripts/pricefm/447_run_pricefm_stage_r126_matched_comparison.py controller
python -B application/scripts/pricefm/449_closeout_pricefm_stage_r126_matched_comparison.py watch
```

The controller runs on Jerez; the watcher runs on Muscat. Runtime, mirrors,
models, release receipts and `local_trackers/` stay ignored. The audited private
master plan retains the detailed background and implementation decision record.
