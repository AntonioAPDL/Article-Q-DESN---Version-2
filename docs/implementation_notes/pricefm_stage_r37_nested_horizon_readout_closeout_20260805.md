# PriceFM Stage-R37 Nested Horizon-Readout Closeout

## Purpose

Stage-R37 closes the completed R36 paired readout experiment without opening the
existing test split. It reconstructs the case-specific inner-validation choice,
checks convergence, applies the pre-registered worst-fold harm guard, and audits
the frozen choice on outer validation against both its paired shared-readout
control and the stronger R34 validation-selected anchor.

## Decision Contract

R36 named a worst-fold harm guard but did not pre-register a positive numerical
tolerance. The authoritative R37 interpretation is therefore a zero tolerance:
the separate readout's worst inner-fold scaled AQL cannot exceed the shared
readout's worst inner-fold scaled AQL. Tolerances of 0.00025 and 0.001 are emitted
only as post hoc sensitivity diagnostics and cannot affect eligibility.

A region/fold enters the fresh full-quantile confirmation queue only when all of
the following hold:

1. the separate readout has lower median inner-fold scaled AQL;
2. all three separate inner fits converge;
3. the strict zero worst-fold harm guard passes;
4. the frozen separate choice improves the paired shared readout on outer
   validation;
5. the frozen choice improves the R34 validation-selected anchor.

Selection remains independent by region/fold. Cross-case pooling is forbidden.
Outer validation is qualification evidence, not a selection surface. Test,
registry, article, full-quantile launch, and MCMC actions remain blocked.

## Reproducibility Outputs

The script writes completion, normalized inner-fold, case-closeout,
horizon-diagnostic, convergence-failure, tolerance-sensitivity, confirmation
queue, decision-gate, source-hash, JSON summary, and Markdown report artifacts.
It writes no launch YAML and performs no fitting.

Implementation:

`application/scripts/pricefm/162_closeout_pricefm_stage_r37_nested_horizon_readout.py`

Default output:

`application/data_local/pricefm/authoritative/pricefm_stage_r37_nested_horizon_readout_closeout_20260805`

## Materialized Result

The completed R36 surface contains 11/11 successful experiments and 66/66 inner
metric rows. Eight cases select the separate readout by median inner AQL, but the
strict closeout produces no fresh full-quantile confirmation candidate:

- HU fold 2 improves the paired shared control and R34 anchor, but its separate
  readout loses by 0.000238 scaled AQL in the worst inner fold and therefore
  fails the authoritative zero-tolerance harm guard.
- NO_4 folds 1 and 2 select the separate readout, but one or more inner separate
  fits do not converge. NO_4 fold 3 retains the shared readout.
- IT_CALA folds 2 and 3 and NO_5 fold 3 improve the paired shared control but do
  not improve the stronger R34 validation anchor.
- IT_SARD fold 1 and SE_1 fold 3 fail the strict worst-fold harm guard.
- NO_3 folds 2 and 3 retain the shared readout.

All 40 files in the materialized source manifest reproduce their recorded
SHA-256 hashes. The existing test split was not inspected. The empty confirmation
queue is an evidence result, not a missing launch-preparation step; no R37-driven
full-quantile run is scientifically authorized.
