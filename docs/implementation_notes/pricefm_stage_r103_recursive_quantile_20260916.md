# PriceFM Stage-R103 recursive independent-quantile refits

## Scientific purpose

R103 is the validation-only independent Q-DESN refit after the R102B Normal
driver gate. It reuses the complete `r98_control` Normal-RHS panel selected by
aggregate validation AQL and the 114 frozen region-fold DESN/`tau0` contracts.
It does not search a new reservoir, tune on test data, fit a joint model, run
MCMC, or mutate the registry or article.

Each region-fold case fits seven AL-RHS and seven structured exAL-RHS VB
readouts at paper quantiles `0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`. The
complete campaign therefore contains 114 cases and 1,596 atoms. Training uses
the exact R102 causal teacher-forced design. Validation uses 500 synchronized
recursive Normal-RHS panel paths as the endogenous price-lag driver; observed
validation prices never enter the recursion.

## Initialization and posterior targets

The warm ladder is computational only:

1. Normal RHS initializes AL at 0.50;
2. AL proceeds outward through 0.45, 0.25, 0.10 and 0.55, 0.75, 0.90;
3. each exAL atom is initialized from the matching AL atom.

Every destination retains its fixed RHS prior, region-level `tau0`, no
intercept shrinkage, and fixed likelihood priors. Initial coefficient means,
covariances, and scales do not become prior centers. exAL uses the hash-pinned
R94 coherent latent-first runtime, package version `1.1.1.9005`, with the
structured sigma/gamma update. The runner records both the warm-start source
and `prior_center_from_initializer = false`.

The installed runtime was also inspected directly. Its Normal-Shrinkage RHS
VB and MCMC updates both use `(m_active + 1) / 2` for the global squared-scale
conditional shape, where `m_active` excludes the unshrunk intercept. The R103
source packet hashes the installed package `DESCRIPTION`, lazy-load database
and index, and shared library in addition to the repair manifest. Thus the
prepared campaign is bound to the executed runtime rather than its label alone.

## Recursive validation contract

For every origin, the quantile readout and the selected Normal driver use the
same reservoir, information policy, realized-ex-post exogenous contract, and
causal timing. Horizon one consumes the last observed lag. Later horizons
consume the corresponding Normal-RHS generated regional price panel plus the
admissible exogenous values. Quantile output does not feed its own recursion,
and AL/exAL likelihood noise does not generate the lag path.

The 500 Normal paths are paired one-to-one with 500 beta-posterior draws. This
integrates both sources of uncertainty without constructing a wasteful
500-by-500 Cartesian product. The stored prediction is the posterior mean of
the paired conditional quantile paths.

## Selection and gates

R103 freezes one complete seven-quantile likelihood family per region. The
choice uses Fold-1 validation AQL only and is then applied unchanged to all
three folds. There is no fold-wise or quantile-wise family mixing. If any exAL
atom for a region fails the frozen numerical gate, an exAL Fold-1 win falls
back to the complete AL family. AL itself must be numerically eligible for all
folds and quantiles.

G4 requires 114 hash-valid cases, 1,596 completed atoms, 38 family decisions,
and 798 selected atoms. Outer-test scoring remains blocked. The next allowed
stage after G4 is a path-count stability check; joint models, MCMC, registry
mutation, and manuscript changes remain separate later decisions.

## Implementation

- `application/scripts/pricefm/pricefm_recursive_quantile.py`
- `application/scripts/pricefm/343_prepare_pricefm_stage_r103_recursive_quantile.py`
- `application/scripts/pricefm/344_run_pricefm_stage_r103_quantile_case.R`
- `application/scripts/pricefm/345_run_pricefm_stage_r103_quantile_case.py`
- `application/scripts/pricefm/346_closeout_pricefm_stage_r103_recursive_quantile.py`
- `application/scripts/pricefm/347_orchestrate_pricefm_stage_r103_recursive_quantile.py`
- `application/tests/test_pricefm_stage_r103_recursive_quantile.py`

The campaign is resumable at both the case and atom levels. Atom writes are
atomic and every reusable artifact is checked by SHA-256. The orchestrator
selects only physical cores whose logical siblings are idle and gives each
selected core one sequential task queue, so two PriceFM models cannot share a
physical core accidentally. Source preparation and launch require a clean,
pushed, exactly synchronized dedicated PriceFM branch.
