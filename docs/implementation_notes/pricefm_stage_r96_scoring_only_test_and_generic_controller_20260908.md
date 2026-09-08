# PriceFM Stage-R96 scoring-only test audit and reusable controller

## Scope

Stage R96 is the one-time test audit of the hash-frozen Stage-R95 `SE_2`
validation surface. It does not refit a model, change the selected likelihood
family, retune a DESN specification, mutate the decision registry, or edit the
article. Stage R95 selected one coherent exAL family across all three folds and
seven paper quantiles before R96 was allowed to expose test windows.

The reusable controller added beside R96 removes the hard-coded `SE_2`, stage,
runner, and artifact-location assumptions from the R95 scheduler. It accepts an
arbitrary region contract and a concrete, content-addressed all-fold task DAG.
It remains launch-blocked behind a separate approval token and is not used to
launch any additional region in this stage.

## Frozen scientific inputs

- R95 closeout: `application/data_local/pricefm/authoritative/pricefm_stage_r95_allfold_validation_closeout_20260907`
- R95 frozen surface SHA-256:
  `4cb26f956ca0c9b728ccdc2d60297758cf8fa519bd8eeb6d9b90c3e5784c72da`
- Target: `SE_2`; folds: 1, 2, 3
- Quantiles: 0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90
- Frozen family: exAL for the whole region
- Frozen DESN: graph-summary-mean, lag 240, depth 2, units `[120, 64]`,
  alpha 0.5, rho 0.95, input scale 0.15, final-layer readout
- Frozen RHS `tau0`: 0.01

The dual test comparators are copied from the current full-surface decision
registry before scoring. R96 requires the unchanged candidate to beat both the
current authoritative Q-DESN and cached PriceFM within the same fold.

## R96 wiring

1. `311_prepare_pricefm_stage_r96_scoring_only_test.py` verifies the complete
   R95 terminal, frozen-surface hash, all 21 selected beta/prediction/terminal
   artifacts, the three training-fitted scalers, and the old validation design
   hashes. It then freezes three scoring tasks and both comparator rows.
2. `313_launch_pricefm_stage_r96_scoring_only_test.py` requires the explicit
   token `RUN_PRICEFM_R96_SCORING_ONLY_TEST`, a clean synchronized task branch,
   sufficient disk and memory, and one process per selected CPU. It recreates
   train/validation/test preprocessing under a fresh R96 artifact root.
3. `312_run_pricefm_stage_r96_scoring_only_fold.py` rebuilds the validation and
   test design for one fold. It requires exact validation-design hashes and
   prediction replay within `1e-10` before applying the frozen posterior-mean
   readouts to test. It deletes temporary design matrices after scoring.
4. `314_closeout_pricefm_stage_r96_scoring_only_test.py` computes original-unit
   seven-quantile AQL, four horizon-block AQL values, median MAE/RMSE, and
   crossing diagnostics. It creates only a promotion-review queue; registry and
   article mutation remain false.

## Promotion gate

A fold enters the review queue only when all conditions hold:

- exact validation replay passed;
- all seven quantile metrics are present and finite;
- all four horizon-block metrics are present and finite;
- the unchanged R95 candidate has lower test AQL than authoritative Q-DESN;
- the unchanged R95 candidate has lower test AQL than cached PriceFM;
- no model refit or post-test selection occurred.

A passing queue is evidence for a separate integration decision. R96 itself
does not promote anything.

## Generic controller contract

`315_launch_pricefm_region_frozen_allfold.py` consumes explicit paths to a
region contract, pipeline contract, launch control, concrete task manifest, and
hash-valid preprocessing terminal. It checks canonical contract hashes,
single-region identity, content-addressed task outputs, source hashes, an
acyclic dependency graph, validation-only selection, test firewalls, clean git
identity, resource floors, and one CPU per model. It resolves runner commands
from each task rather than from a region-specific constant.

The abstract graph produced by `305_prepare_pricefm_region_frozen_allfold.py`
is not by itself launch-grade. A future region materializer must bind that graph
to concrete data, runtime, runner, and output artifacts before this controller
will accept it. This fail-closed boundary prevents accidental launches from a
planning manifest.

## Validation commands

```bash
PRICEFM_PY=/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python
$PRICEFM_PY -m py_compile application/scripts/pricefm/31{1,2,3,4,5}_*.py
$PRICEFM_PY -m pytest -q \
  application/tests/test_pricefm_stage_r96_scoring_only_test.py \
  application/tests/test_pricefm_region_frozen_controller.py \
  application/tests/test_pricefm_stage_r95_region_frozen_allfold.py \
  application/tests/test_pricefm_region_frozen_contract.py
```

## Explicit exclusions

- No additional region launch.
- No model fitting in R96.
- No family or specification reselection after test exposure.
- No registry, article, joint-model, or MCMC action.
- No modification of frozen R95 scripts or evidence.
