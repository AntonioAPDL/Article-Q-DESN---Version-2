# PriceFM Stage R142: Certified AL Rescue

## Decision

R141 remains the frozen scientific protocol. R142 changes no likelihood, prior,
DESN specification, training rows, quantile, `tau0`, certificate threshold, or
test-data rule. It repairs only finite AL fits that reached the predeclared
300-iteration cap without passing either formal convergence or the independent
same-state fixed-point certificate.

The original R141 artifacts do not retain the complete variational optimizer
state. Exact continuation is therefore impossible. R142 must not claim to
resume the optimizer. It performs a new, bounded optimization of the identical
posterior target, initialized with only the saved coefficient mean and
likelihood scale. Those values are computational initializers; the coefficient
prior remains zero-centered and all prior hyperparameters remain fixed.

## Bounded policy

1. An eligible source fit must be finite, test-closed, prior-clean, and
   uncertified solely at the 300-iteration cap.
2. The design hash, posterior-target hash, `tau`, `tau0`, CRAN `exdqlm 1.1.1`
   package identity, and fixed-point limits must match exactly.
3. At most two additional 300-iteration warm-start attempts are allowed.
4. The decision to retry or stop uses computational certification only. Test
   AQL is never opened or used.
5. Every original failed task is moved intact to `uncertified_attempts/` only
   after every required replacement is certified. Certified replacements are
   bridged atomically to the task names expected by the frozen R141 DAG, with a
   provenance receipt linking both source histories.
6. If no bounded attempt certifies, the region remains blocked. Thresholds are
   never relaxed and downstream tasks remain withheld.

## Execution and resources

Muscat keeps the existing R141 AT/BG slots on physical cores 0-29. Jerez keeps
the existing BE/slot-A queue on cores 0-14. R142 exclusively owns Jerez cores
15-29, first repairing CZ and then draining the original R141 slot-B queue.
This uses both servers without oversubscription or interference with healthy
work.

## Scientific scope

R142 is inference recovery, not model selection. It does not authorize MCMC,
joint or exAL models, registry/article mutation, authority replacement, or an
article claim. Final comparisons remain deferred until all 38 regions and 114
folds are complete and reconciled.
