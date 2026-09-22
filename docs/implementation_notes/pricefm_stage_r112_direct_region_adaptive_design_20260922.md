# PriceFM Stage-R112: direct region-adaptive campaign design

## Purpose

Stage R112 converts the completed R98--R111 evidence into a prospective design
for the next PriceFM performance study. It is read-only. It does not fit a
model, create launch YAML, open an outer validation or test split, mutate the
registry, or update the article.

The scientific objective is a complete direct seven-quantile surface for all
38 regions and all three outer folds. The model may adapt by region, but one
DESN, `tau0`, feature policy, and likelihood family must be selected per region
using training-contained temporal pseudo-folds and then frozen across the
three outer folds. The final decision is aggregate over all 114 cases; no
favorable row may be mixed into the current authority after scoring.

## Why this is the correct next direction

The R101--R111 branch investigated recursive endogenous-price forecasting.
R107 showed that extending the same VB objective from 200 to 500 iterations
did not materially alter fitted results. R108 identified endogenous-driver
quality as a major source of recursive loss. R109 rejected both saved Normal
drivers as sufficient. R110C showed that path representation alone did not
close the gap. R111A supported completing active neighbor drivers for EE, but
did not authorize a broad campaign. R111B repaired BG substantially and beat
PriceFM, while R111C showed that the remaining disadvantage against R97 grows
after the first 24 forecast hours across every quantile.

Therefore another recursive all-region launch would repeat a mechanism whose
focus-region gate failed. The direct 96-horizon operator avoids that state
propagation burden and is already represented by the protocol-valid R98/R97
authority. The remaining admissible question is whether a stronger,
training-only regional search can improve that complete direct surface.

## Current authority

R98 contains 114 rows: 38 regions times three folds. It was built from R97
region-frozen fits, uses one region specification and likelihood family across
folds, and has no test-driven case mixing or R92 row fallback. Its mean AQL is
about 7.2170, compared with approximately 7.0387 for the frozen cached PriceFM
surface.

R98 remains authoritative until a complete prospective replacement passes its
global gate. R111A and R111B are retained only as mechanism evidence.

## Reuse audit

The next study must not rerun valid work unnecessarily:

- R100 completed expanded Normal Ridge/RHS screening for 17 regions.
- Each R100 winner specification is converged, eligible, selected without test
  access, and frozen in a hashed regional contract.
- R100 deliberately compacted the binary Normal posterior objects after
  preserving metrics and method summaries. The selected specifications are
  reusable, but the posterior initializers are not.
- The remaining 21 regions completed the earlier R97 regional screen but have
  not received the same expanded R100 search.
- The union of R100 manifests for the 17 completed regions and R97 manifests
  for the remaining 21 contains exactly 240 candidates per region and 9,120
  rows overall.
- Every regional candidate bank contains the current R98 geometry, so the
  current authority is a guaranteed search anchor rather than an after-the-fact
  fallback.

The 17 R100 winner specifications must be reused. R112A will extend the same
deterministic R100 candidate-generation algorithm to the 21 missing regions.
Only those 21 screening ladders require new fitting. After all 38 regional
specifications are frozen, the final Normal RHS model must be refitted on each
outer region-fold training window because an internal-screen fit is not the
correct final training object and the old binary posteriors no longer exist.

## Leakage firewall

The model-selection hierarchy is:

```text
fold-1 training observations
  -> three embargoed temporal pseudo-folds
  -> regional Normal Ridge ranking
  -> regional Normal RHS/tau0 ranking
  -> regional AL versus exAL quantile-family ranking
  -> one frozen regional specification
  -> outer folds 1, 2, and 3 used only for final evaluation
```

Outer-fold validation and test outcomes may not rank candidates, choose a
region, change search depth, choose AL versus exAL, or select a row for
promotion. The earlier R100 target list was informed by observed weak regions;
that is why applying R100 only to those 17 would not support a new complete
authority. Extending the same algorithm to all 38 regions removes the selective
search-depth problem.

## Normal screening contract

Each region has 240 Ridge candidates and the current authority geometry is
mandatory. The audited candidate families cover:

- target-only features;
- graph-neighbor concatenation;
- graph means;
- graph mean and standard deviation summaries;
- graph neighbor-spread summaries;
- lag windows 48, 96, 168, and 240 where present in the frozen bank;
- depths 1--3;
- bounded widths represented by the frozen candidate manifests;
- bounded `alpha`, `rho`, and input-scale values;
- final-layer readout only.

Ridge retains the top 30 candidates per region by median original-scale AQL
over the three internal temporal folds. Normal RHS evaluates those candidates
under relative `tau0` multipliers `0.25`, `1`, and `4`, using

```text
tau_candidate = tau_R98
                * sqrt(R98 readout dimension / candidate readout dimension)
                * multiplier.
```

This scaling respects the dependence of the effective global prior on readout
dimension while preserving a bounded local search around the current regional
prior. Convergence is an eligibility requirement, not a tie breaker.

## Quantile contract

After one Normal RHS winner is frozen per region:

1. initialize the median AL-RHS VB fit from the matching Normal RHS posterior;
2. fit adjacent quantiles outward from the median;
3. fit matching exAL-RHS VB models using the structured/M0 scale treatment;
4. compare AL and exAL only on training-contained pseudo-folds;
5. freeze one likelihood family per region across all outer folds;
6. fit or exactly reuse seven direct quantile models at
   `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90` for each outer fold;
7. forecast all 96 horizons directly, without recursively generated target
   prices entering later inputs.

Upstream posterior summaries are initialization only. They may not become
prior centers or alter `tau0`, the RHS hierarchy, the ELBO, or the destination
posterior target. An existing quantile fit is reusable only when model, data,
prior, feature, source, and code hashes match exactly.

Joint models and MCMC are out of scope. They remain blocked until a complete
independent VB surface passes the authority gate.

## Exact remaining workload

The design computes the following maxima:

| Phase | New fit cells |
|---|---:|
| Ridge inner fits for 21 missing regions | 15,120 |
| Normal RHS inner fits for 21 missing regions | 5,670 |
| Final Normal RHS outer region-fold refits | 114 |
| AL/exAL training-only family-selection fits for 38 regions | 1,596 |
| Selected-family outer direct quantile fits | 798 |

Exact-contract reuse may reduce the quantile counts, but launch preparation
must budget for the maxima and record every reuse decision. The 114 final
Normal fits cannot be replaced by the compacted R100 screening summaries.

## Distributed execution design

Region ownership is deterministic and phase-stable:

- normal extension: 14 regions on Jerez and 7 on Muscat;
- quantile stage: 26 regions on Jerez and 12 on Muscat;
- one model process per logical worker;
- BLAS and OpenMP threads fixed to one;
- target worker ceilings of 50 on Jerez and 25 on Muscat, subject to a fresh
  CPU, memory, and disk preflight;
- all dependent work for a region remains on one server;
- atomic terminal records and contract hashes make every phase resumable;
- results return to Muscat only through a hash-verified manifest.

R112 deliberately does not pin current CPU IDs because resource availability
is runtime state and stale pinning can interfere with other scientific lanes.

## Aggregate decision gates

Authority replacement requires all of the following:

1. exactly 114 complete candidate rows and all 38 regions;
2. folds 1--3 for every region;
3. one regional specification and family frozen across folds;
4. no outer-validation or test-driven selection;
5. zero row-level R98 fallbacks after scoring;
6. complete source, fit, prediction, and metric hashes;
7. candidate complete-surface mean AQL strictly below R98 mean AQL.

A PriceFM-superiority article claim additionally requires candidate
complete-surface mean AQL below the frozen PriceFM mean AQL. These are separate
decisions. Region and fold diagnostics must be reported, but no individual
case is required to beat both comparators and no case can be promoted alone.

## Stage sequence

### R112: design and audit

Implemented here. It materializes the regional inventory, reusable-work audit,
candidate-space audit, workload/host plan, search and quantile contracts,
promotion gates, source hashes, and this decision record. It starts no fit.

### R112A: normal-extension launch preparation

After explicit review, generalize the R100 preparer to all regions and create
candidate manifests only for the 21 missing regions. Validate deterministic
identity against the original R100 algorithm. Produce launch configuration but
do not mix runtime output with the completed R100 campaign.

### R112B: normal-extension execution

Run the 21 missing screens. Reuse the 17 frozen R100 winner specifications.
Close only when all 38 regional Normal winners have complete contracts. Then
fit 114 final outer-training Normal RHS models and retain their posterior
objects as hashed quantile initializers.

### R112C: quantile-family selection

Run training-contained AL/exAL family selection for every region using the
frozen Normal winners. No outer-fold metric may enter this decision.

### R112D: complete direct quantile surface

Fit or exactly reuse the selected seven-quantile models for all 114 cases and
materialize direct 96-horizon predictions.

### R112E: global closeout

Apply the complete-surface R98 and PriceFM gates. Report pooled, equal-case,
region, fold, quantile, horizon-block, coverage, width, crossing, MAE, RMSE,
and paired uncertainty diagnostics.

### Integration

Only the coordinator may mutate the registry or article after R112E. A valid
but non-improving surface remains a documented sensitivity result and does not
replace R98.

## Implementation boundary

The R112 package is intentionally not a launcher. The next stage remains
blocked until this design, its cardinalities, and its leakage firewall are
reviewed. This prevents an expensive campaign from starting before the exact
candidate-generation extension and fit interfaces have their own focused
tests.

## Outputs

The materialized package is written under:

```text
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/
pricefm_stage_r112_direct_region_adaptive_design_20260922
```

It contains CSV, JSON, Markdown, and SHA-256 source-manifest evidence only. It
contains no model objects, predictions, launch YAML, or duplicated heavy data.
