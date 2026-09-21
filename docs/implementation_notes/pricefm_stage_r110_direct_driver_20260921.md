# PriceFM Stage-R110 direct-driver implementation

Date: 2026-09-21

Stage R110 implements the bounded standalone future-price driver experiment
authorized by the completed R108/R109 mechanism diagnosis. It is restricted to
BG, EE, and BE and never opens an outer test split.

## Design

The stage preserves each region's frozen R97/R103 reservoir geometry and
feature policy. Three response-time-embargoed pseudo-folds inside fold-1
training select one readout/prior/tau0 policy per region. The selected policy
is then held fixed while fitting and scoring outer validation folds 1--3.

The dependency-ordered surface contains 45 model tasks:

- 18 exact scaled-Ridge tasks comparing a shared readout with four 24-hour
  blocks;
- 18 RHS VB tasks comparing the frozen tau0 with tau0/4 under the selected
  Ridge readout;
- 9 final outer-validation fits with 500 predictive paths each.

The controller reserves at most 30 distinct physical cores and pins one
single-thread process to each selected core. Because phases depend on prior
selection, actual maximum concurrency is 18, then 18, then 9.

Isolated trace checks showed that slowly converging 24-hour RHS blocks remained
stable and monotone and crossed the frozen `1e-5` criterion by iteration 637.
Incomplete RHS tasks therefore receive a 750-iteration ceiling while retaining
the same tolerance and prior target. Twelve candidates that had already
crossed the criterion under the earlier 500 ceiling are reused exactly. Ridge
tasks are closed form and are unaffected.

## RHS target audit

The pinned exdqlm runtime at commit
`5d373c8b69181c37e5993844fc5e70c699c02272` excludes the intercept from the
RHS block and uses `a_tau = (d + 1) / 2`. A focused regression test verifies
the resulting shape and verifies that different initialization scales do not
change the prior hyperparameters. Ridge estimates initialize computation only.

## Artifacts and gates

Runtime adapters, contracts, fits, paths, logs, selections, and closeout files
are written beneath the ignored campaign directory
`application/data_local/pricefm/campaigns/pricefm_stage_r110_direct_driver_20260921`.
Tracked source and tests contain no registry, manuscript, MCMC, joint-model, or
outer-test mutation path.

The closeout requires 9/9 finite 500-path cases, at least 30 percent pooled and
late-horizon AQL improvement over R102B Normal RHS, no more than 25 percent AQL
excess over cached PriceFM, bounded coverage harm, and no region with more than
10 percent harm. Passing authorizes only a separately controlled no-refit
frozen-QDESN target-driver replay.
