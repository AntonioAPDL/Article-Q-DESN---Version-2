# PriceFM Stage R145: AT Recovery and Muscat Utilization

## Decision

R145 is a computational recovery and orchestration stage. The frozen R141
scientific protocol remains authoritative for every model fit. R145 changes no
DESN specification, training row, internal-validation rule, likelihood, prior,
`tau0`, quantile, random seed, certificate threshold, forecast operator, or
test-data rule.

AT stopped after 46 of 54 training-only quantile-finalist tasks. A complete
enumeration found eight finite, prior-clean AL fits at the fixed 300-iteration
budget: for each of the two shortlisted `tau0` values, split 1 at `tau = 0.10`,
split 2 at `tau = 0.90`, and split 3 at `tau = 0.25` and `tau = 0.90`. Their
RHS scale blocks are stationary, while at least one coefficient, predictor,
covariance, scale, or ELBO fixed-point measure remains above its predeclared
tolerance. The controller correctly withheld the eight dependent scores and
two split-3 `tau = 0.10` fits.

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

- cores `0-7`: the eight-way AT rescue and completion lane;
- cores `8-14`: independent continuation queue for `DE_LU`, `FI`, `IT_CALA`,
  `IT_SICI`, `NL`, `NO_4`, `RO`, and `SE_4`.

The 8+7 split removes the four-wave AT bottleneck that a 2+13 split would
create, while still advancing a second region concurrently. The two lanes are
failure-isolated and use exactly 15 distinct physical cores.
Together with the unchanged slot-B allocation, Muscat continues to reserve 30
physical cores without oversubscription. Jerez is not modified because its two
live controllers already own its 30 audited physical cores.

An initial short-lived 2+13 launch was stopped when exhaustive enumeration
revealed eight eligible AT fits rather than the two split-3 `tau = 0.25` fits
first highlighted by the blocked-run summary. No source R141 artifact was
changed. R145 preserves any unsealed partial rescue attempt under an explicit
`interrupted_attempts/` receipt before restarting it; partial evidence is never
accepted as a completed fit.

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
