# PriceFM Stage-R97 closeout-lineage recovery

## Purpose

This note freezes the diagnosis and recovery plan for the Stage-R97 distributed
PriceFM campaign. The repair is limited to validation closeout metadata. It does
not change fitted models, DESN specifications, tau0, data, validation selection,
or any test, registry, article, joint-model, or MCMC gate.

## Audited state

At the 2026-09-12 audit, all 8,880 Ridge candidates, all 3,330 coarse normal-RHS
bundles, and all 108 required normal-RHS refinement bundles were complete. All
540 Muscat quantile-surface tasks had valid completed terminals. Jerez had
entered its 1,125-task quantile surface with 50 one-core workers and no recent
errors.

The Muscat surface integrity audit found 540/540 completed terminals, 504/504
quantile prediction files, 504/504 quantile coefficient summaries, and 36/36
normal source configurations. Six finite normal-RHS fits reached the original
100-iteration ceiling and then converged under the preregistered bounded
500-iteration recovery. Their scientific configurations did not change.

## Root cause

The production surface schema stores `normal_full_config` only on each fold's
`normal_full` task. AL and exAL tasks identify that source through
`normal_task_id`, `normal_task_output`, and the shared `adapter_dir`.

The closeout instead attempted to read `normal_full_config` directly from every
AL/exAL atom. Consequently, all twelve Muscat regional closeouts stopped with
`KeyError('normal_full_config')` after fitting was already complete. This is a
closeout-reader defect, not a numerical failure and not missing model output.
The prior unit coverage exercised family selection but did not reproduce the
production task schema.

## Repair contract

For each family and fold, closeout must:

1. find exactly one `normal_full` task;
2. require all seven quantile atoms to reference its task ID and output path;
3. require all atoms to share its validation adapter;
4. verify the normal configuration against its declared SHA-256 digest; and
5. record that verified configuration as the selected atoms' source evidence.

The correction must not copy source fields into existing immutable task files or
change pipeline manifests. Mixed or ambiguous parent lineage must fail closed.

## Recovery sequence

1. Validate the closeout correction with focused lineage, global-campaign,
   distributed-controller, and surface-runtime recovery tests.
2. Commit and push only the dedicated PriceFM task branch.
3. Rebind a descendant Muscat shard contract and launch controls to that clean,
   synchronized commit while preserving all scientific hashes and firewalls.
4. Rerun the Muscat host controller. Existing 540 terminals must be reused, so
   only twelve validation closeouts execute.
5. Leave the active Jerez worktree unchanged until its controller and all model
   workers exit. A guarded watcher may then fast-forward the same task branch,
   rerun focused tests, rebind the Jerez recovery contract and controls, and
   execute closeout only after all 1,125 surface terminals are present.
6. Require both shard terminals to report `completed_validation_shard` and all
   37 regional closeouts to pass hash and firewall validation.
7. Transfer only the Jerez-owned compact evidence to Muscat, verify it against a
   generated inventory, and run the 37-region reconciliation with test sealed.
8. Global scoring remains a separate, explicit one-time action. Registry and
   article mutation remain blocked until the frozen global comparison is
   reviewed.

## Completion gates

- no model refit during closeout recovery;
- 1,665/1,665 surface terminals accepted across both hosts;
- 37/37 regional closeouts, each selecting one whole AL or exAL family using
  Fold-1 validation and retaining the declared numerical fallback;
- clean synchronized task branch and descendant recovery contracts;
- unchanged test, registry, article, joint-model, and MCMC firewalls;
- hash-verified cross-host evidence before reconciliation.

The final Jerez-to-Muscat transfer uses the dedicated `results` inventory scope.
Unlike the pre-launch `host` scope, it includes each regional validation closeout,
the 21 selected atoms' hash-pinned coefficient and validation-replay evidence,
their scaler/configuration lineage, the completed shard terminal, and the
descendant shard contract. Unselected screening and quantile-model outputs are
excluded. This is the exact material required by reconciliation and later frozen
scoring; test data and global-scoring output are not part of this transfer scope.

The optimal immediate action is to repair and validate closeout while Jerez
continues fitting. Stopping or relaunching Jerez would discard useful compute
without addressing the actual defect.

## Validation record

The focused closeout, global-campaign, distributed-controller, and runtime
recovery suite passed 36 tests after the repair. A production-schema closeout of
the complete BG surface then passed in an isolated output directory, produced
six family-fold validation rows, selected 21 AL atoms without numerical
fallback, and retained `test_opened: false`. This confirms the repair against
real manifests and predictions before any official closeout is replaced.
