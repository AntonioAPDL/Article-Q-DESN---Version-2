# PriceFM Stage-R101 recursive contract and engine

## Purpose

Stage R101 is the read-only implementation gate between the completed R100
normal screening and any recursive refit. It does not fit or score a model.
It freezes the candidate surface and implements the causal forecast operator
needed by R102-R105.

## Frozen evidence

The compiler verifies the R100 terminal, all 17 region closeouts, all 1,530 RHS
ranked experiments, all 1,530 compaction terminals, and all 9,180 retained
audit-file hashes. It also verifies that test access, quantile fitting, registry
mutation, and article mutation remained blocked.

Two complete panels are frozen:

- `r98_control`: the R98 contract in all 38 regions;
- `r100_primary`: the frozen R100 winner in the 17 targeted regions and R98 in
  the other 21 regions.

R100 changes 10 reservoir structures and 11 complete structure-plus-`tau0`
contracts. Austria is a prior-only change (`tau0` 0.01 to 0.04). Therefore the
union contains 48 unique structures and 49 unique full contracts.

## Recursive contract

Training is causal teacher forcing: form the prediction for time `t` from
information available through `t-1` and admissible exogenous information for
`t`, then update with observed price `y_t`.

Forecasting uses synchronous panel recursion. For each path and horizon, all
38 regional inputs, states, and locations are computed from the same `h-1`
panel snapshot. Only after every region is predicted are price draws appended
to the histories. The result is invariant to region calculation order.

Normal Ridge and Normal RHS each self-recurse. Independent AL/exAL models later
consume the common Normal-RHS price paths; their quantile outputs do not feed
the primary endogenous state. Paths and parameter draws are paired by one
index, with 500 paths as the default. A later R104 numerical gate compares 500
against a larger frozen path count before outer-test scoring.

## Provenance rule

The 114 region-fold provenance rows retain selected-atom, feature, scaler,
validation-origin, input-feature, and source-window identities. Some R97
window manifests were deterministically rebuilt after their hashes were frozen.
R101 records both hashes. A manifest-only mismatch is permitted only when the
current window shape, region/fold identity, and binary window-data hash still
match the frozen feature provenance.

## Files

- `application/R/pricefm_recursive_forecast.R`
- `application/scripts/pricefm/pricefm_recursive_adapter.py`
- `application/scripts/pricefm/334_prepare_pricefm_recursive_contract.py`
- `application/tests/test_pricefm_recursive_adapter.py`
- `application/tests/test_pricefm_recursive_forecast.R`
- `application/tests/test_pricefm_stage_r101_recursive_contract.py`

Runtime outputs are materialized only after focused tests pass under:

```text
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/
launch_prep/pricefm_stage_r101_recursive_contract_20260916
```

No YAML, model fit, test score, registry mutation, or article mutation is
authorized by R101. A separate reviewed R102 stage is required to refit the
recursive Normal Ridge and Normal RHS drivers.

The bounded R102 implementation and preparation are documented in
`docs/implementation_notes/pricefm_stage_r102_recursive_normal_prep_20260916.md`.
