# PriceFM Stage-R97 surface-preprocessing recovery

## Decision

Repair the shared preprocessing seal, reuse every completed Ridge, coarse-RHS,
refinement, and normal-selection artifact, and resume the two frozen host shards.
This is an orchestration-only recovery. It does not change the DESN search space,
selected regional specifications, `tau0`, validation windows, AL/exAL runtime,
family-selection rule, region ownership, or global decision rule.

Test scoring, registry and article mutation, joint models, and MCMC remain blocked.

## Audited state and failure

At 2026-09-11 16:46 America/New_York, 32,033 model fits had produced metrics.
All 8,880 Ridge bundles were complete. Muscat had completed all 1,080 coarse-RHS
bundles, all 36 required refinement bundles, and all 12 validation-only normal
selections. Jerez had 663 of 2,250 coarse-RHS bundles sealed, 49 active, and no
recent model failures.

Muscat prepared AT's valid 45-task surface, then failed closed before launching a
surface task. `Campaign.preprocessing_terminal()` loaded the generated YAML as
the inner `pricefm` mapping and passed that inner mapping to `window_npz_path()`.
The latter calls `pricefm_block()` and therefore requires the original top-level
mapping. The resulting `KeyError('pricefm')` is a configuration-shape defect, not
a statistical, convergence, or numerical failure.

The failed shard terminal confirms zero completed surface regions, no test access,
and no registry or article mutation. AT's surface manifest contains exactly 45
tasks: three normal-RHS, 21 AL, and 21 exAL tasks. It was not launched and can be
reused after its hashes and preprocessing seal pass.

## Scientific state preserved

The 12 frozen Muscat normal contracts are region-specific. They span lag windows
48--240, depths 1--3, widths 40--96, four feature policies, and `tau0` values from
`5e-5` to `1e-2`. Eight select graph-informed inputs and four select target-only
inputs. This supports the pre-registered region-specific strategy; it is not
evidence for a universal DESN specification.

The inner-validation normal AQL values are selection evidence only. No AL/exAL
surface has run, no test AQL has been opened, and no comparison with authoritative
Q-DESN or cached PriceFM is yet scientifically available.

## Repair contract

1. Preserve the full generated YAML mapping when resolving window paths.
2. Recompute and verify the self-hash of the pipeline contract.
3. Verify the generated data-config file record before and after preprocessing.
4. Require exactly folds 1--3 and split records containing only `fold`, `train`,
   and `val` fields.
5. Require unique, nonempty active regions contained in the data contract and an
   exact processed-root match.
6. Seal exactly one scaler per fold and one train and validation window per active
   region and fold.
7. On resume, verify terminal status, pipeline hash, firewall, artifact roles,
   paths, and SHA-256 values rather than trusting terminal existence.
8. Rebind each recovery contract only to a clean synchronized descendant commit;
   completed screening, refinement, selection, and prepared-surface replacement
   remain unauthorized.

## Validation

Run `py_compile` for scripts 317, 319, 324, and 327. Run the focused R97 campaign
and distributed-continuation tests, including a real preprocessing-terminal test
that uses the nested data shape, verifies idempotent reuse, and rejects a tampered
artifact. Run the wider PriceFM R97 focused set and `git diff --check` on Muscat,
then repeat the focused tests on Jerez after fast-forwarding the task branch.

Before launch, use an isolated copy of AT's pipeline contract and generated data
configuration to prove that the helper emits the expected scaler/window inventory
without opening test data. Production AT's existing manifest and pipeline hashes
must remain unchanged.

## Continuation

1. Commit and push the validated repair only to the dedicated PriceFM branch.
2. Rebind a Muscat recovery contract to that commit with unchanged assignment,
   checkpoint, scientific contract, and worker count.
3. Resume Muscat with 20 one-core workers. Its completed screening and refinement
   markers must validate and be skipped. Reuse AT's grid, prepare the other 11
   surfaces, and require a valid preprocessing terminal before any model starts.
4. Place Jerez in controller-supported drain mode after the repair is available.
   Let all active bundles finish and compact; do not signal or kill workers.
5. Fast-forward the drained Jerez worktree, rebind its contract, remove only the
   task-owned drain marker, and resume its remaining coarse-RHS bundles.
6. Confirm one valid Muscat surface result and one post-restart Jerez coarse-RHS
   terminal before leaving both controllers in the background.
7. After both shard terminals report `completed_validation_shard`, transfer Jerez
   outputs through the hash inventory, verify disjoint ownership, and prepare the
   complete 37-region validation reconciliation.
8. Open the frozen 114-case no-refit test audit only at the later authorized global
   scoring stage. Apply the pre-registered overall mean-AQL comparison without a
   per-case veto. Article and registry mutation require a separate promotion gate.

## Expected remaining work

The fixed minimum campaign contains 38,403 metric-producing fits after the 108
Muscat refinement fits are included. At audit time, at least 6,370 fits remained:
4,705 coarse-RHS fits on Jerez and 1,665 quantile-surface tasks. Jerez refinement
can add zero to 225 fits. Its observed median coarse-RHS bundle duration was about
36.6 minutes, implying roughly 18--21 hours for that phase at 49--50 workers.
