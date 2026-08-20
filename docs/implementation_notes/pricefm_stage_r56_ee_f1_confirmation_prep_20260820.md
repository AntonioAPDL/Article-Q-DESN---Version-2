# PriceFM Stage-R56 EE/fold-1 confirmation prep

## Decision

Stage-R55 does not justify another broad PriceFM MCMC surface. It identifies one
bounded confirmation target, `EE` fold 1, that satisfies the validation-only
selection, validation harm, authority-replay, and dual-reference test-audit
conditions. R56 therefore preserves that one case and all seven paper
quantiles; it does not search or select on test data.

## Why a fresh run is required

R53 retained posterior draws and posterior-mean prediction paths, but not the
latent state or final sampler state required for exact continuation. R56 must
restart from the frozen explicit VB initialization for each quantile. The new
seeds are deterministic and disjoint from R53. This is disclosed in the launch
manifest as `fresh_from_frozen_explicit_vb_init`.

## Budget and surface

- one region/fold case: `EE` fold 1;
- seven quantiles: 0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90;
- four chains per quantile, 28 chain jobs total;
- 5,000 burn-in and 20,000 retained draws per chain;
- collapsed-M0 exAL transition pinned to the frozen R53 engine;
- 20 workers, one process per idle physical core, one numerical thread each.

Linear scaling from R53 gives a deliberately conservative estimate of about
1,373 core-hours, or 69 wall-hours at 20 continuously available workers. The
launcher is resumable and will wait for all host gates rather than competing
with another PriceFM campaign.

## Safety contracts

The prep script verifies the complete R55 target contract, the complete R53
source surface, the frozen case replay, explicit initializations, engine commit,
budget, quantiles, chains, and source hashes. The launcher then re-verifies
those hashes and requires all of the following before fitting:

- explicit launch authorization in both the prep artifacts and CLI;
- the global PriceFM campaign lock;
- 20 idle physical cores at no more than 10% sampled utilization;
- one-minute load no greater than 36;
- at least 128 GiB available memory and 100 GiB free disk.

Registry and article mutation remain blocked. R56 completion alone cannot
promote a model: a later read-only closeout must recompute convergence,
validation harm, authority replay, and dual-reference test audit from the new
draws.

## Files

- `application/scripts/pricefm/188_prepare_pricefm_stage_r56_ee_f1_confirmation.py`
- `application/scripts/pricefm/189_launch_pricefm_stage_r56_ee_f1_confirmation.py`
- `application/tests/test_pricefm_stage_r56_ee_f1_confirmation.py`
