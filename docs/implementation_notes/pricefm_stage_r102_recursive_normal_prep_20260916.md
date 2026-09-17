# PriceFM Stage-R102 recursive Normal preparation

## Decision

Stage R102 is implemented and prepared, but it has not been launched. It is a
bounded causal refit of the R101-frozen R98 control and R100 primary panels,
not another DESN hyperparameter search. The earlier 4,080 Ridge and 1,530 RHS
R100 candidates are not repeated.

The prepared surface contains:

- 48 unique region-specific reservoir structures across three folds;
- 144 causal sufficient-statistic cells;
- 144 exact scaled-Ridge fits;
- 49 structure-plus-`tau0` RHS contracts across three folds, or 147 RHS fits;
- 228 panel-map rows for two complete 38-region, three-fold panels;
- 576 unique train/validation window requirements;
- 500 paired posterior-predictive paths in the later validation-path gate.

## Causal contract

For each training origin, the reservoir is initialized from the first `L-1`
observed rows. The final observed row advances the state used for horizon one.
At later training horizons, the observed previous response is appended only
after its prediction has been formed. The implementation checks that the
horizon-one row is numerically identical to the historical direct design.

The later validation path must replace post-origin responses with recursively
generated Normal paths. Ridge will recurse from Ridge draws and RHS from RHS
draws. All regions at a horizon must be computed from the same previous panel
snapshot before any regional history is updated. No observed validation price
after the origin may enter a path.

## Implementation

- `application/scripts/pricefm/pricefm_recursive_normal.py` builds bounded
  causal sufficient statistics, writes hash-sealed binary packets, and defines
  posterior-target identities.
- `application/R/pricefm_recursive_normal_fit.R` fits exact scaled Ridge and
  Normal RHS_NS VB from the sufficient statistics while retaining draw-ready
  covariance and convergence state. Ridge initializes RHS computation only;
  it does not define an RHS prior center or change `tau0`.
- `application/scripts/pricefm/335_prepare_pricefm_stage_r102_recursive_normal.py`
  verifies R101 and writes the bounded manifests and train/validation-only
  configs.
- `application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R`
  fits one atomic contract from the frozen Normal runtime.
- `application/scripts/pricefm/337_build_pricefm_stage_r102_recursive_statistics.py`
  builds one causal statistic cell.
- `application/scripts/pricefm/338_orchestrate_pricefm_stage_r102_recursive_normal.py`
  is resumable, one-process-per-core, hash-gated, and refuses dirty or
  unsynchronized source, absent approval, forbidden splits, occupied CPUs, or
  insufficient resources.

The reproducibility packet is under:

```text
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/
launch_prep/pricefm_stage_r102_recursive_normal_20260916
```

It records SHA-256 identities for the R101 evidence, frozen Normal runtime,
R102 helpers, workers, and controller. Generated fit and window paths remain
under the ignored PriceFM runtime tree and are not article assets.

## Validation

The focused Python suite passed with `22 passed`. Both focused R suites passed:
the recursive panel contract and the sufficient-statistic fit contract. Python
byte compilation and `git diff --check` passed. A direct numerical smoke using
the frozen PriceFM exdqlm runtime also completed an RHS_NS VB fit and verified
the `scaled_ridge_initialization_only_prior_unchanged` contract.

The materialized packet was independently checked: all six output hashes
matched, all 15 source hashes were recorded, every split was train or
validation, and every test-access flag was false.

## Current gate

A read-only controller preflight returned `preflight_blocked`, as intended:
the R101/R102 source is still uncommitted and has no synchronized task-branch
upstream, no explicit R102 approval token was supplied, and part of the
default CPU set was occupied by an unrelated lane. Disk and memory gates
passed. No R102 statistics or model fit was launched.

Before a production R102 run, the dedicated PriceFM branch must be reviewed,
committed, pushed, and synchronized; an actually idle CPU set must be chosen;
and explicit launch approval must be supplied. The next implemented runtime
milestone is the 291 Normal fits. Synchronized validation paths and complete
panel selection remain a distinct R102B gate after those fits finish.

Quantile fits, test scoring, joint models, MCMC, registry mutation, and article
mutation remain blocked.

## First execution recovery

The first production invocation completed and retained all 576 required
train/validation windows, then stopped before writing any statistic or fit.
The recursive helper expected a `label_col` key that is present in the NPZ
packet but intentionally omitted by the established `load_window()` adapter.
The helper now derives and validates the exact `<region>-price` column from the
adapter's canonical `lag_cols` contract. The focused fixture was changed to
match the real loader surface and a fail-closed missing-price-column test was
added. No model result was created under the defective path; the retained
windows can be reused after the corrected source is committed and rehashed.

The resumed fit stage completed all 144 exact Ridge fits and 97 RHS fits. Eleven
RHS contracts reached the original 100-iteration ceiling and were rejected;
the fail-fast worker buckets left 39 later RHS contracts untouched. Isolated
diagnostics with identical statistics, priors, tolerance, and initialization
showed that all 11 rejected fits converge between iterations 102 and 219. This
is an optimization-budget limitation, not divergence and not a changed
posterior target. R102 therefore uses a 300-iteration RHS ceiling while keeping
`min_iter = 50` and `tol = 1e-5`. Existing converged fits remain authoritative
and are not repeated.

The established window builder evaluates a window before applying its resume
check. The R102 controller now bypasses the builder when every required NPZ and
matching manifest for a lag group already exists. This keeps resumed execution
bounded without weakening the complete-packet requirement.
