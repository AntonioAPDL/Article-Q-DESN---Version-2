# PriceFM Stage-R108 recursive-driver decomposition

## Purpose

Stage-R108 diagnoses why validation forecasts from the recursive PriceFM
Q-DESN workflow remain worse than the frozen direct-design reference. It does
not fit or select a new model. It reuses the 27 complete Stage-R103 cases for
AT, BE, BG, CZ, DE_LU, DK_1, DK_2, EE, and ES across all three folds and varies
only the future endogenous-price driver supplied after each forecast horizon.

The implementation follows the ignored execution plan at
`local_trackers/pricefm_stage_r108_oracle_driver_execution_plan_20260920.md`.

## Scientific contract

Each policy predicts horizon `h` before the driver value at `h` updates the
reservoir for horizon `h + 1`. Same-horizon truth is therefore never visible to
the Q-DESN forecast. All comparisons use the same 500 beta draws and paired
stratified uniforms inside a region-fold-origin.

The policies are:

1. frozen Stage-R97 direct-design reference;
2. Q-DESN self recursion with Normal-RHS neighbor paths;
3. a target noisy-oracle ladder with lambda 0, 0.25, 0.50, 0.75, and 1;
4. exact-oracle drivers for every active region;
5. PriceFM median for the target with Normal-RHS neighbors;
6. PriceFM medians for every active region;
7. PriceFM quantile pseudo-paths for every active region.

For the noisy-oracle ladder,

```text
z_lambda(h) = y(h) + lambda * (z_self(h) - y(h)).
```

Thus lambda zero is the exact target oracle and lambda one must reproduce the
self-recursive policy under paired random numbers. PriceFM pseudo-paths use the
seven released quantiles, monotone rearrangement, bounded interpolation over
0.10--0.90, shared cross-region ranks, and independent ranks across horizons.
They are diagnostics, not native PriceFM posterior paths. Any PriceFM-driven
Q-DESN row is a hybrid oracle-strength diagnostic and cannot be promoted as a
standalone model.

## Implementation

- `application/scripts/pricefm/pricefm_recursive_driver_diagnostics.py`
  implements oracle bridges, PriceFM pseudo-paths, training-state support, and
  the generic causal recursive Q-DESN operator.
- `application/scripts/pricefm/363_prepare_pricefm_stage_r108_pricefm_driver_cache.py`
  evaluates the frozen public PriceFM Phase-I checkpoint once over the exact
  Stage-R97 fold-aligned L96 validation windows and writes a hash-bound compact
  cache.
- `application/scripts/pricefm/364_audit_pricefm_stage_r108_recursive_driver_decomposition.py`
  runs resumable region-fold cases, records source hashes, computes forecast,
  state-support, uncertainty, and horizon diagnostics, and finalizes the
  complete packet.
- `application/tests/test_pricefm_stage_r108_recursive_driver_decomposition.py`
  tests oracle endpoints, causal timing, paired lambda-one equivalence,
  PriceFM path bounds, state support, and mutation/fitting prohibitions.

The scripts hard-block non-validation inputs, preserve 500 posterior paths,
write no launch YAML, and never mutate the registry or article. Test, joint,
MCMC, and model-fitting work remain outside this stage.

## Validation

The focused plus related regression suite passed:

```text
22 passed in 3.60s
```

The same 22 tests passed on Jerez in 3.00 seconds after migration. The frozen
PriceFM driver cache completed in 74 seconds. Its checkpoint SHA-256 is
`387f1ba06dc42235d23267d0b2228225e33efffb20aeca9c94094f9fef4d19a5`
and the pinned public PriceFM source revision is
`c72d1228bde80417d5cc782521328e02ab5401c3`.

A BG fold-1 preflight completed in 16 minutes 58 seconds with 590 MB peak RAM.
It produced validation AQL 23.19728 for self recursion, 9.22777 for exact-oracle
recursion, and 14.14088 for the direct Stage-R97 reference. This makes the
full decomposition scientifically informative and makes parallel execution
on Jerez worthwhile.

## Jerez execution

The isolated Jerez worktree is:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_r108_driver_jerez_20260920
```

It is detached at `21128b0630c644e78943cc7a0c9106e3b02a17b9`, with only the
four validated R108 implementation files copied into it. Frozen R97, R102,
R102B, and R103 evidence was transferred to the same absolute artifact paths;
unrelated campaigns were not modified.

The background session is `pricefm_r108_20260920`. The scheduler ceiling is 30
single-thread workers. There are 27 scientific tasks, so 27 workers are active
and three process-pool slots remain idle. The log is:

```text
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/logs/pricefm_stage_r108_recursive_driver_decomposition_20260920.jerez.log
```

The final output directory is:

```text
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r108_recursive_driver_decomposition_20260920
```

No result should be interpreted until all 27 case terminals exist and the
finalizer writes `summary.json`, pooled CSVs, the Markdown report, and the PDF.
After completion, copy the complete output directory back to Muscat, verify all
hashes, and perform the scientific closeout before authorizing any refit.

## Completed closeout

R108 completed all 27 region-fold cases on Jerez with no failures. The final
packet was hash-verified and synchronized back to Muscat. No PriceFM R108
process remains active.

The pooled validation AQL results identify endogenous-driver quality as the
dominant mechanism:

| Policy | Validation AQL |
|---|---:|
| exact oracle, all active regions | 3.06059 |
| exact target oracle, RHS neighbors | 4.03976 |
| frozen R97 direct reference | 7.77501 |
| PriceFM quantile pseudo-path driver | 8.49614 |
| Q-DESN self recursion | 23.95723 |

Exact target drivers improve 26 of 27 cases relative to the direct reference,
and exact all-region drivers improve all 27. Self recursion is worse than the
direct reference in all 27. The current saved Normal-RHS driver is therefore
not a viable default: its directly scored validation AQL is about 27.19 and its
driver/downstream AQL association is approximately 0.98.

## External-reference enhancement

The regenerated PDF also displays the current R98 Q-DESN authority and cached
PriceFM for the same nine regions and three folds. These are outer-test values,
not R108 validation values, so the PDF renders them in separate panels and
labels them as contextual references. Across these 27 cases, mean outer-test
AQL is 7.75015 for R98 Q-DESN and 8.14031 for cached PriceFM. The corresponding
full 38-region values remain 7.21701 and 7.03869, respectively.

The exact case-level references are materialized as
`pricefm_stage_r108_external_test_references.csv`. They are audit/reporting
context only and do not authorize cross-split ranking, model selection, test
retuning, registry mutation, or article mutation.
