# PriceFM Stage-R35 Failure Decomposition

Date: 2026-08-04

## Objective

Stage-R35 is the read-only diagnosis following the complete negative Stage-R34
closeout. It determines whether another expensive PriceFM experiment is
scientifically justified and, if so, what must be implemented before launch.

It does not fit models, write launch YAML, run MCMC, mutate the PriceFM
registry, or modify article/manuscript files.

## Why Another Capacity Grid Is Blocked

Stage-R34 contains 480 complete experiments and 960 AL/exAL method rows across
20 case-specific region/fold targets. No method row beats cached PriceFM. No
validation-selected row beats both current authoritative Q-DESN and PriceFM,
and even diagnostic test-oracle selection produces no PriceFM winner.

Consequently:

- validation transfer is a real secondary problem, but cannot by itself close
  the PriceFM gap;
- wider/deeper/longer versions of the same AL/exAL family are not the supported
  next experiment;
- postfit calibration remains diagnostic because Stage-R27 produced no
  calibrated PriceFM win;
- MCMC remains confirmation for a future winner, not an optimization rescue.

## Implementation

- Script:
  `application/scripts/pricefm/160_audit_pricefm_stage_r35_failure_decomposition.py`
- Tests:
  `application/tests/test_pricefm_stage_r35_failure_decomposition.py`
- Output root:
  `application/data_local/pricefm/authoritative/pricefm_stage_r35_failure_decomposition_20260804`

The script consumes only materialized closeouts, existing prediction/run
artifacts, and source code. It fail-closes unless R34 is complete,
validation-only selection is frozen, no R34 promotion/MCMC queue exists, all
selected prediction and horizon artifacts align exactly, and source capability
evidence is present.

## Diagnostic Layers

1. **Oracle capability:** checks whether any retrospective test-oracle R33 row
   could beat PriceFM. This separates model-family limitations from selector
   limitations.
2. **Validation transfer:** calculates within-case Pearson/Spearman association,
   selected test rank, oracle validation rank, and selection penalty.
3. **Capacity response:** measures case-specific median response to lag window,
   depth, width, tau0, and AL/exAL choice. Fixed R33 axes are explicitly marked
   unidentified rather than inferred.
4. **Horizon response:** reads the selected model's original-unit validation and
   test horizon-block metrics and joins current-Q-DESN-versus-PriceFM block
   diagnostics without pretending that candidate PriceFM block deltas exist.
5. **Prediction calibration:** aligns selected scaled predictions with adapter
   truths and reports pinball loss, signed bias, empirical median coverage,
   dispersion, and horizon-specific residual lag-1 dependence.
6. **Runner capability:** verifies from code whether horizon weighting and block
   interactions are consumed and whether new loss/likelihood, separate
   block-specific fits, nested validation, calibration, or MCMC are supported.
7. **Test adaptation:** hashes the R10-R34 closeout summaries that exposed test
   or promotion evidence and records that the existing test split is no longer
   pristine for new-family specification selection.
8. **Confirmation design:** audits train/validation/test calendar boundaries and
   blocks article promotion until an independent confirmation strategy exists.

## Pre-Registered Thresholds

- near-gap diagnostic: oracle test gap to PriceFM at most `0.75` AQL;
- far-gap diagnostic: oracle test gap at least `1.25` AQL;
- selection instability: Spearman correlation at most `0`, or selected-minus-
  oracle test penalty at least `0.25` AQL;
- flat capacity-axis response: median test effect span below `0.05` AQL;
- material median miscalibration: empirical coverage error above `0.05`, or
  absolute mean bias above `0.20` of MAE.

These thresholds classify diagnostic queues only. They cannot authorize a
launch or promote a candidate.

## Required Next Mechanism Contract

The only currently justified model-development path is a genuinely consumed
new objective/model family, such as a fully separate horizon-specific
regularized readout or a new loss/likelihood implemented in model code. A YAML
label is insufficient.

Before an expensive launch, the implementation must have:

- unit and integration tests proving field propagation and actual model-code
  consumption;
- case-specific, nested temporal validation selection;
- fallback/harm guards for cases where current authoritative Q-DESN is better;
- no access to the existing test split during specification selection;
- a pre-registered independent confirmation strategy, using later data if
  available or transparently disclosed rolling-origin cross-fitting otherwise.

Only a frozen candidate that beats both current Q-DESN and PriceFM may proceed
to full paper quantiles, reproducibility hashes, MCMC confirmation, and finally
registry/article consideration.

## Materialized Findings

The real-data audit completed with 126 hashed source artifacts and no missing or
changed source. It produced no YAML.

- 480 experiments, 960 AL/exAL method rows, and 20 case selections were
  reconciled from R34;
- validation-selected PriceFM wins: 0;
- diagnostic test-oracle PriceFM wins: 0;
- median within-case validation/test Spearman correlation: 0.2342;
- median selected-minus-oracle test penalty: 0.1598 AQL;
- cases classified as validation-transfer unstable: 10/20;
- cases with material median location/coverage miscalibration: 11/20;
- near-gap cases at the 0.75 threshold: 10/20;
- far-gap cases at the 1.25 threshold: 4/20;
- current-Q-DESN harm-guard cases: `NO_4` fold 1 and `HU` fold 2;
- historical summaries exposing test or promotion evidence: 9;
- latest response time evidenced by current selected artifacts:
  `2025-12-31T23:45:00+00:00`.

The case-specific queue contains two priority-0 harm guards, nine priority-1
near-gap qualification cases, three priority-2 nested-validation cases, two
priority-2 stable mid-gap holds, and four priority-3 far-gap holds. Far-gap
status dominates selector instability because retrospective selection cannot
make those cases plausible qualification targets.

Calibration is material in several cases but is not the sole mechanism: R27
already showed that validation-fit calibration of existing predictions creates
no PriceFM winner. Lag-window and AL/exAL effects are usually flat; width,
depth, and tau0 can matter for individual cases, but their validation-preferred
directions frequently disagree with test and no setting crosses PriceFM.
Pre-registered horizon-focus blocks also show large validation-to-test transfer
gaps, so another weighting-only or block-interaction launch is blocked.
