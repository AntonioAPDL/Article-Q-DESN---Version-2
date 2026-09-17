# PriceFM Stage-R102B recursive validation paths

## Purpose

R102B is the validation-only path and panel-selection gate after the completed
R102A Normal refits. It does not fit a new model or search a new DESN. It
generates four complete recursive surfaces, each over all three folds:

- R98 control with exact scaled Ridge;
- R98 control with Normal RHS_NS VB;
- R100 primary with exact scaled Ridge;
- R100 primary with Normal RHS_NS VB.

Each surface uses 500 synchronized posterior-predictive paths, all 38 regions,
96 horizons, and the existing realized-ex-post exogenous contract. Validation
outcomes are absent from the recursion and enter only after forecasting for
original-unit scoring.

## Posterior draws

The exact Ridge fit is sampled from its Normal-inverse-gamma posterior:
`omega2` is drawn first and `beta | omega2` is drawn with the retained
conditional precision inverse. The RHS fit uses its fitted mean-field factors
`q(beta) q(omega2)`. Neither draw rule changes a prior or posterior target.

Random streams are deterministic and paired. Parameter streams are shared by
region, fold, and prior across the two panels. Innovation streams are shared by
region, fold, origin, horizon, and path across every panel and prior. This
reduces Monte Carlo noise without coupling the statistical models themselves.

## Recursive timing

For horizon one, every model advances from the final observed lag row. For
later horizons, every target model consumes the same pre-update vector of 38
generated regional prices plus the admissible exogenous values. All regional
locations and draws are computed before the panel is advanced. The operation
is invariant to regional calculation order, and no observed validation price
is read by the recursive engine.

Full float32 path arrays are retained with SHA-256 manifests; path generation
and scoring use float64 arithmetic. Empirical predictive quantiles are computed
at `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90` and inverse-scaled with each
region-fold training scaler.

## Selection

Ridge surfaces are diagnostic. R102B selects exactly one complete RHS panel by
minimum aggregate original-unit validation AQL over all regions, folds,
origins, horizons, and quantiles. Ties use worst-fold AQL and then the R98
control panel. There is no region-wise or fold-wise mixing and no outer-test
outcome enters selection.

The selected output is a 114-row region-fold Normal-RHS driver manifest for
R103. Quantile fitting, test scoring, joint models, MCMC, registry mutation,
and article mutation remain blocked until their later gates.

## Implementation and validation

- `application/scripts/pricefm/339_prepare_pricefm_stage_r102b_recursive_validation.py`
- `application/scripts/pricefm/340_run_pricefm_stage_r102b_recursive_validation.py`
- `application/scripts/pricefm/341_closeout_pricefm_stage_r102b_recursive_validation.py`
- `application/scripts/pricefm/342_orchestrate_pricefm_stage_r102b_recursive_validation.py`
- `application/tests/test_pricefm_stage_r102b_recursive_validation.py`

Focused tests verify the exact and mean-field posterior draw contracts,
generated-price lag construction, synchronous order invariance, strict
independence from validation truth during recursion, complete-panel selection,
source hashing, and the launch firewall. A real 38-region, 96-horizon smoke
passed. At the production path count, one origin required approximately 22.6
seconds and 462 MB peak RSS on the current host.
