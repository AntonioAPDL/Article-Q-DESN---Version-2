# PriceFM Stage-R38 Partial-Pooling Capability Audit

Stage-R38 is a read-only decision stage after the negative R37 closeout. It uses
paired R36 outer-validation predictions to calculate an oracle capability bound
for convex partial pooling between shared and fully separate horizon-block
readouts. These oracle weights are diagnostic only and cannot select or promote
a model.

The audit also records the limits of R36 convergence evidence, inventories the
latest local observation window, checks for comparable post-2025 PriceFM
forecasts, and pre-registers the R39 hierarchical partial-pooling contract.

R39 is justified only when a majority of R36 cases exhibit partial-pooling
headroom. Its prospective stability rule permits at most 0.5% relative AQL harm
in the worst inner fold, declared before R39 outcomes exist. R39 must freeze each
case's R34 reservoir, use embargoed nested validation, prefer stronger pooling
under a one-standard-error rule, and emit per-block convergence diagnostics.

Independent article confirmation requires both post-2025 observations and
comparable PriceFM forecasts. If those cannot be acquired, future evidence must
be described as rolling-origin cross-validation rather than an untouched holdout.

Implementation:

`application/scripts/pricefm/163_audit_pricefm_stage_r38_partial_pooling_capability.py`

Default output:

`application/data_local/pricefm/authoritative/pricefm_stage_r38_partial_pooling_capability_20260805`
