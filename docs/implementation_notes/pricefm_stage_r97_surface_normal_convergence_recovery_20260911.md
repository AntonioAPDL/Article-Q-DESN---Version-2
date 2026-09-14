# PriceFM Stage-R97 surface normal-convergence recovery

## Decision

Preserve the complete Stage-R97 scientific contract and all valid completed work.
Repair only the runtime boundary that (a) binds preserved surface grids to a clean
descendant task commit and (b) gives a finite normal-RHS fit enough iterations to
satisfy its already registered convergence tolerance. Continue validation-only
AL/exAL surfaces after the repair. Do not open test data, score the global test
surface, mutate the registry or article, fit a joint model, or run MCMC.

## Audited failure modes

| Failure | Direct evidence | Diagnosis | Repair |
|---|---|---|---|
| AT did not launch | `regions/AT/logs/launch_surface.log` reports a Git launch-identity mismatch after the task branch advanced from `b81498d` to `0fbe9bb` | The prepared scientific DAG is intact, but its operational launch identity is stale | Verify every pipeline/task/preprocessing hash, preserve them byte-for-byte, and rebind only `launch_control.json` to a clean synchronized descendant commit |
| ES fold 2 normal task blocked its quantile descendants | `model_method_summary.csv` is finite, reports `converged=FALSE`, and stops at iteration 100 | The strict terminal gate correctly rejected a fit stopped by its iteration ceiling | Retry only this exact recognized state at `max_iter=500`, retaining `tol=1e-5` |
| IT_CSUD folds 1 and 3 blocked descendants | Both method summaries are finite and stop at iteration 100 | Same iteration-ceiling condition, not a process crash or nonfinite model | Apply the same bounded retry and retain the strict convergence requirement |
| One failed region can delay the host shard | `run_surfaces()` previously called `future.result()` without isolating exceptions | An operational exception escapes the admission loop while the executor waits for already active regions | Record the failed region, continue unrelated regions, then end the shard failed-closed if any failures remain |

At the audit boundary, the production values were:

| Case | Iteration | Converged | Final parameter change | Sigma |
|---|---:|---:|---:|---:|
| ES fold 2 | 100 | no | `3.878e-5` | `0.21525784` |
| IT_CSUD fold 1 | 100 | no | `0.04944534` | `0.25128119` |
| IT_CSUD fold 3 | 100 | no | `1.630506` | `0.29066683` |

Controlled, validation-only continuations of the exact IT_CSUD configurations
showed fold 1 satisfying `tol=1e-5` at iteration 141 and fold 3 at iteration 268.
The latter remained unconverged at iteration 200, so 200 is not an adequate common
ceiling. Both trajectories remained finite. A ceiling of 500 is therefore bounded,
empirically sufficient for the observed cases, and inexpensive relative to the
quantile surfaces; early stopping still applies as soon as the unchanged tolerance
is met.

## Scientific contract preserved

The recovery must not alter any of the following:

- region assignment or host ownership;
- train/validation windows, scalers, processed arrays, or test firewall;
- selected region-specific feature policy, lag window, depth, units, `alpha`,
  `rho`, input scale, state output, seed, or `tau0`;
- the 45-task region DAG, task IDs, dependencies, quantiles, AL/exAL methods, or
  coherent exAL runtime;
- Fold-1 validation-only whole-family selection;
- the final 114-case unweighted mean-AQL decision rule.

The generated normal configuration contains `rhs_ns.init_tau: 1.0`, but the normal
runner constructs the package RHS argument from `tau0`, `shrink_intercept`, and the
two freeze fields only. `init_tau` is therefore metadata-only in this campaign.
Changing that behavior now would change the fitted model after screening and is
explicitly out of scope. It should be corrected prospectively in a separately
registered campaign, not silently during R97 recovery.

## Recovery contract

1. New surfaces start normal-RHS with `max_iter=500`, `min_iter=50`, and
   `tol=1e-5`.
2. Preserved 100-iteration surfaces may retry only when all required coefficient,
   covariance, prediction, parameter, and trace values are finite; sigma is
   positive; formal convergence is false; and the method stopped exactly at the
   configured iteration ceiling.
3. Before retry, retain the small first-attempt method, parameter, trace,
   coefficient, covariance, metric, weighting, and provenance files. Do not
   duplicate large prediction artifacts.
4. Derive a per-task recovery configuration from the original cell configuration,
   changing only `normal.vb_control.max_iter` from 100 to 500 and preserving
   `tol=1e-5`.
5. Reuse the hash-valid train/validation adapter and rerun only the normal model and
   summary. Never rebuild the adapter and never load test data.
6. Write a task terminal only after the recovered fit is finite and formally
   converged. A nonfinite state, an unrecognized partial, or failure at iteration
   500 remains failed-closed.
7. Rebind a preserved launch control only after its pipeline self-hash, exact
   45-task manifest, every task/source hash, preprocessing terminal, artifact hash,
   ownership, firewall, and ancestor relationship have passed.
8. Refuse launch-control mutation while that region launcher holds its lock.

## Implementation

- `315_launch_pricefm_region_frozen_allfold.py` implements strict partial-state
  recognition, diagnostic preservation, bounded recovery, post-retry gates, and
  provenance-rich terminals.
- `317_prepare_pricefm_stage_r97_region_quantile_surface.py` sets the prospective
  normal ceiling to 500 and emits the explicit recovery policy.
- `324_orchestrate_pricefm_stage_r97_host_shard.py` isolates region failures while
  allowing unrelated queued regions to finish, then reports a failed-closed shard.
- `327_prepare_pricefm_stage_r97_rhs_transition_recovery.py` adds sealed operational
  authorization for launch-control rebinding and the bounded 500-iteration retry.
- `328_prepare_pricefm_stage_r97_surface_runtime_recovery.py` audits and optionally
  rebinds only preserved surface launch controls; pipeline, manifest, task, and
  preprocessing hashes remain unchanged.

## Validation plan

Run `py_compile`, the focused controller, R93--R97, region-frozen, and new recovery
tests, followed by `git diff --check`. On each host, require a clean synchronized
PriceFM task branch and run the recovery tool in audit mode before `--write`.
Verify the written recovery ledger, rerun preflight, and then resume the same shard
contract with one process per assigned CPU.

The production proof is stronger than a synthetic smoke test: after restart, the
three recognized normal tasks must produce formal convergence terminals; their
descendant quantile tasks must become runnable; AT must pass preflight without any
pipeline/task hash change; and previously completed task terminals must be skipped.

## Two-server continuation

1. Let the currently active Muscat region launchers finish; do not signal their R
   workers. The old host controller is already waiting for those admitted regions
   after AT's exception and will not admit the remaining regions.
2. Commit and push this repair to the dedicated PriceFM task branch.
3. Rebind a new sealed Muscat shard contract to that clean descendant commit.
4. Audit, then write, the surface launch-control recovery after all region launcher
   locks are free. Resume Muscat with the same 20 CPUs. Completed terminals are
   reused; only failed normals and unfinished descendants run; AT, SE_3, and SK are
   admitted normally.
5. Let the resumed Jerez screening establish a new completed compacted RHS bundle.
   At the next controlled boundary, request controller-supported drain, wait for all
   active bundles, fast-forward its task worktree, rebind its sealed contract, audit
   the runtime recovery, and resume with the same 50 one-core workers.
6. Allow both hosts to complete validation surfaces. Do not score test data yet.
7. Transfer Jerez evidence with the hash inventory, reconcile disjoint ownership,
   and only then prepare the separately authorized one-time 114-case test audit.

This is the least wasteful valid continuation: it preserves all completed screening
and quantile atoms, fixes the demonstrated stopping condition, and does not use
test outcomes or alter a selected model specification.
