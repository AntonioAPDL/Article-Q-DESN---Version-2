# PriceFM Stage-R112A: Normal-extension launch preparation

## Purpose

Stage R112A implements the first executable preparation step of the R112
direct, region-adaptive campaign. It prepares the expanded Normal Ridge/RHS
search for the 21 regions that were not screened in R100. It does not fit a
model or start a process. The 17 completed R100 Normal winner specifications
remain frozen and are not rerun.

The package is written to:

```text
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/
launch_prep/pricefm_stage_r112a_normal_extension_prep_20260922
```

## Scientific contract

The campaign is prospective and region-adaptive:

- one Normal specification is selected per region;
- selection uses three embargoed temporal pseudo-folds wholly contained in
  fold-1 training;
- the selected regional specification is later frozen across outer folds
  1--3;
- outer validation and test metrics cannot rank candidates;
- the final comparison must use one complete 38-region by 3-fold surface;
- no favorable case can be mixed into R98 after scoring;
- the forecast operator remains direct over all 96 horizons, with no
  recursively generated target prices entering later inputs.

This stage authorizes neither quantile fits nor joint/MCMC work. Registry and
article mutation remain reserved for the integration coordinator after the
complete-surface R112E closeout.

## Generator-equivalence audit

The R100 search was originally restricted to 17 regions. Extending it safely
requires more than copying its nominal hyperparameter bounds: the all-region
implementation must preserve the exact deterministic candidate-generation
algorithm.

R112A therefore:

1. verifies the completed R112 design and all of its output hashes;
2. verifies the 114-row R98 authority and 17 frozen R100 winners;
3. hashes the 88 MB raw PriceFM panel and compares it with the frozen R99
   source record;
4. recomputes graph-neighbor level and first-difference correlations using
   observations from 2022-01-01 through, but not including, 2024-09-01;
5. reproduces the original R99 neighbor records for the 17 completed regions;
6. regenerates every completed R100 bank and requires all candidate IDs and
   semantic fingerprints to match exactly;
7. applies that same generator to the 21 missing regions.

This closes the main comparability risk: the new regions cannot silently
receive a different policy allocation, graph-neighbor ranking, random seed
schedule, or geometry sampler.

## Prepared search

Each of the 21 new regional banks contains exactly 240 Ridge candidates,
including the region's current R98 geometry as a mandatory control. The policy
quotas, DESN geometries, lags, `alpha`, `rho`, input scales, and reservoir seeds
are inherited exactly from R100.

The planned train-only workload is:

| Phase | Models | Inner fit cells |
|---|---:|---:|
| Normal Ridge | 5,040 | 15,120 |
| Normal RHS after regional top-30 Ridge selection | at most 1,890 | at most 5,670 |

For each selected Ridge candidate, the RHS stage evaluates relative `tau0`
multipliers 0.25, 1, and 4 around the dimension-adjusted reference

```text
tau_candidate = tau_R98
                * sqrt(R98 readout dimension / candidate readout dimension)
                * multiplier.
```

Convergence across all three inner folds is required for RHS eligibility.

## Host partition

The R112 design deterministically assigns 14 pending regions to Jerez and 7 to
Muscat. Region ownership remains fixed through Ridge and RHS so dependent
artifacts do not need to move during the screen. CPU identifiers are not
stored in the prep package because they are runtime state. R112B must perform a
fresh host-local CPU, memory, disk, branch, and source-hash preflight.

Every fit must use one model process per logical CPU with all BLAS/OpenMP
thread counts fixed to one. The launch must be resumable and use a distinct
R112B campaign root; it must not append to the completed R100 campaign.

## Outputs

The materialized package contains:

- an all-region train-only neighbor-signal table;
- an exact 17-region R100 generator-regression ledger;
- 21 candidate manifests;
- 21 Ridge grid/config bundles;
- a deterministic Muscat/Jerez ownership manifest;
- launch-preparation gates and a blocked launch control;
- complete SHA-256 source and output provenance;
- a Markdown decision report and JSON summary.

The control status is `prepared_not_authorized`. It requires the explicit
R112B approval token and an execution controller that validates the package
before launching.

## Validation

Focused tests exercise the train-only neighbor calculation, real frozen R112,
R99, R100, and R98 inputs, exact R100 candidate identity, all 21 generated
banks, the host partition, leakage controls, idempotent reuse, and the absence
of a model-execution path.

## Next step

Implement and validate the R112B host-local controller against this immutable
prep package. A launch remains a separate operational decision. R112C must
remain blocked until R112B freezes valid Normal winners for all 21 missing
regions and the resulting 38-region union passes a hash and completeness
closeout.

