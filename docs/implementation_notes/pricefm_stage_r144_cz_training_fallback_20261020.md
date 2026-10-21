# PriceFM R144 CZ training-only fallback

R144 is a narrow completion stage for the only region withheld from the R141
all-region campaign. It does not change the R141 model, screening space,
forecast operator, numerical certificate, iteration budget, or comparison
rule.

## Why a fallback is required

Both top-ranked CZ Normal-RHS configurations refer to the same DESN and differ
only in `tau0`. Their independent-AL confirmation stopped at the fixed
300-iteration limit with accurate linear solves but nonstationary coefficient
blocks on internal splits 1 and 2. The bounded R142 continuation certified the
split-3 fits but did not certify all three splits, so its all-or-nothing bridge
correctly remained closed.

R143 quarantined CZ and resumed the unaffected Jerez queue. Its diagnosis
identified the next distinct DESN/tau0 pair in the already frozen, training-only
Normal-RHS ranking:

* candidate `r134_56a8ee2629e2b168`;
* `tau0 = 1.8443953471560665e-4`;
* training-only mean Normal-RHS AQL `6.922431769877396`;
* rank 3 overall and rank 1 among DESNs not already attempted by R141.

The fallback was fixed before its quantile fits or official test forecasts were
opened. R144 therefore does not use test performance to select a model.

## Execution contract

1. Wait for `R143_QUEUE_COMPLETE_NOT_PROMOTED`. R144 never competes with the
   live Jerez slot-B queue.
2. Verify the frozen R141 HEAD and source hashes, R143 predecessor identity,
   R141 CZ preparation and RHS-closeout hashes, fallback rank/specification,
   and six sealed train-only prerequisite tasks.
3. Hard-link the three certified statistics packets and three matching
   Normal-RHS fits into an isolated R144 campaign. No Ridge or RHS refit is
   performed.
4. Run the exact R141 seven-quantile nested AL confirmation for the one
   predetermined fallback candidate over all three internal splits.
5. Continue only if all confirmation fits are computationally certified. Fit
   the three official folds and generate the same four forecast operators using
   the exact R141 engine.
6. Seal R144 as `R144_CZ_FALLBACK_COMPLETE_NOT_PROMOTED` and leave authority,
   registry, article, and Overleaf files unchanged.
7. The R144 all-region closeout combines four frozen R137 regions, 33 completed
   R141 regions, and the isolated R144 CZ result. It requires exactly 114
   primary fold rows before producing an aggregate comparison.

## Resource policy

The successor uses Jerez CPUs 15-29, one process per distinct physical core,
only after R143 releases that slot. CPUs 0-14 remain assigned to the other R141
Jerez queue and physical cores 30-31 remain unallocated for host health. The
Muscat queues are not changed. A 50 GiB free-disk floor and 180 GiB available
memory floor are checked before launch.

## Scientific boundary

R144 is a completion mechanism, not another screening stage. It does not relax
the fixed-point threshold, add blind iterations, choose among official-test
scores, introduce MCMC/exAL/joint fits, or decide promotion. The final decision
remains the predeclared equal-region, equal-fold aggregate across all 38
regions.
