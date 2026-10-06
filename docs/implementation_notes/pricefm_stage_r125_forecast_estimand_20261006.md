# PriceFM R125: forecast estimand diagnosis

R125 is a bounded no-refit diagnostic of completed R124 forecasts. It does not
change fitted priors, learned coefficients, reservoirs, selection or article
authority. Its fixed protocol is
`application/config/pricefm_stage_r125_forecast_estimand_protocol_20261006.json`.

The primary distinction is average conditional quantiles versus quantiles of a
predictive mixture. Seven quantile knots do not identify a full distribution.
The new CDF pools therefore use two explicit diagnostic tail conventions and
unweighted knot sorting, with a sorted-mean control. Oracle-state arms are
strictly diagnostic and ineligible for selection/promotion. The shared Normal
recursive driver is held fixed; S=500 and original R124 innovation seeds are
preserved. No AL scale posterior is invented from compact saved scale means.

The scope is three fixed BG candidates, three outer-Fold-1 training-internal
splits and twelve predetermined origins per cell. All new operators must
reproduce matched original control forecasts. Their AQL is in training-scaled
units and cannot be ranked against official EUR/MWh article scores.

Entry points:

```bash
python -B application/scripts/pricefm/pricefm_r125_release.py --output RELEASE --cpu CPU
python -B application/scripts/pricefm/446_run_pricefm_stage_r125_forecast_estimand.py \
  --mode prepare --owner-root OWNER --frozen-code-root RESERVOIR \
  --validation-receipt RELEASE/validation.json
python -B application/scripts/pricefm/446_run_pricefm_stage_r125_forecast_estimand.py \
  --mode smoke --owner-root OWNER --frozen-code-root RESERVOIR --config JOB
python -B application/scripts/pricefm/446_run_pricefm_stage_r125_forecast_estimand.py \
  --mode controller --owner-root OWNER --frozen-code-root RESERVOIR --workers 15
```

OWNER is the clean R123 certified fit source at
`40d42d15a477c2f9d50dbc69b4eb9885da91ec29`; RESERVOIR is frozen at
`7ae8d6f578000ab17cd30567a23f7b806028cee0`. Prepare also verifies complete R124
source `0924e857ba74a499a22712db0f99b6de711d7d01` and its evidence ledger.
Run commands from a clean dedicated committed R125 checkout. Canonical output
and preparation paths use the R125 tag, never another campaign's directory.
The scheduler selects unused distinct physical cores, caps concurrent cells at
nine, uses single-threaded BLAS and preserves RAM/disk reserves.

`test_pricefm_stage_r125_forecast_estimand.py` checks normalized CDFs, repeated
knots/atoms, inverse quantiles, affine units, Monte Carlo agreement, causal
truth poisoning, original-position seeds, scope rejection, atomic evidence and
strict matched comparison. Release runs all inherited checks and four pinned
R suites. Partial results block overwrite; hash-verified complete cells can be
reused. Runtime evidence and plans remain Git-ignored.

The reusable `matched_comparison` function permits a performance claim only
for complete aligned region/fold predictions, fixed specifications and no
oracle/test-informed selection. It reports prespecified whole-cohort mean
AQL; it does not impose a per-case dual-comparator gate or authorize article
promotion. A later full-fold benchmark needs 3 Normal plus 21 AL BG fits,
not relabelled internal split fits. Historical test exposure must be disclosed.
R125 alone cannot establish superiority over PriceFM/current QDESN or justify
an all-region launch. Coordinator integration/publication remains separate.
