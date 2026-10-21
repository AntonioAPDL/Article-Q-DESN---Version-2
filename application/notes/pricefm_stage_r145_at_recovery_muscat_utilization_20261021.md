# PriceFM Stage R145: AT Recovery and Muscat Utilization

## Decision

R145 is a computational recovery and orchestration stage. The frozen R141
scientific protocol remains authoritative for every model fit. R145 changes no
DESN specification, training row, internal-validation rule, likelihood, prior,
`tau0`, quantile, random seed, certificate threshold, forecast operator, or
test-data rule.

AT stopped after 46 of 54 training-only quantile-finalist tasks because both
split-3 `tau = 0.25` fits reached the fixed 300-iteration budget without
passing the independent same-state fixed-point certificate. Both fits are
finite and prior-clean. Their RHS scale block is stationary, while the
coefficient/covariance block remains above the predeclared tolerance. The
controller correctly withheld the dependent `tau = 0.10` fits and finalist
scores.

## Recovery contract

R145 reuses the tested R142 same-target rescue algorithm. Each eligible fit is
optimized again against the identical posterior target, warm-started only with
the saved coefficient mean and likelihood scale. These quantities initialize
the optimizer and never become prior centers. Exact optimizer continuation is
not claimed because the full variational state was not retained.

The recovery is bounded to at most two additional 300-iteration attempts per
eligible task. A replacement is accepted only when it passes the original
formal convergence or independent fixed-point certificate. Thresholds are not
relaxed. Original uncertified evidence is retained under
`uncertified_attempts/`, and replacements are bridged atomically only after all
eligible tasks in a recovery cycle certify.

## Resource layout

Muscat cores `15-29` remain owned by the healthy original R141 slot-B queue.
R145 partitions the failed and otherwise idle slot-A allocation:

- cores `0-1`: AT rescue and completion lane;
- cores `2-14`: independent continuation queue for `DE_LU`, `FI`, `IT_CALA`,
  `IT_SICI`, `NL`, `NO_4`, `RO`, and `SE_4`.

The two lanes are failure-isolated and use exactly 15 distinct physical cores.
Together with the unchanged slot-B allocation, Muscat continues to reserve 30
physical cores without oversubscription. Jerez is not modified because its two
live controllers already own its 30 audited physical cores.

All R145 orchestration and inherited R141 controllers use the campaign's pinned
Python 3.11 environment. BLAS, OpenMP, data.table, and numerical-expression
thread counts remain fixed at one per worker.

## Failure policy

Each lane preserves completed R141 evidence and resumes from sealed task
boundaries. Any later finite 300-iteration AL cap failure is eligible for the
same bounded, target-preserving rescue. A numerical crash, changed target,
test-opened fit, exhausted bounded rescue, or non-AL failure is quarantined and
does not block the other lane. No registry, article, authority, or Overleaf
mutation is authorized.

## Completion gate

R145 is complete only when AT and every continuation region has a certified
R141 regional closeout, or when all healthy work has drained and unresolved
regions are explicitly quarantined. Final scientific comparison remains the
responsibility of the existing R144 all-region closeout after all 38 regions
and 114 folds are reconciled.
