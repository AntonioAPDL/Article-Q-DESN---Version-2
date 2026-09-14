# PriceFM Stage-R97 completed-surface closeout recovery

## Decision

All Stage-R97 fitting is complete: Muscat has 540/540 accepted surface tasks and
Jerez has 1,125/1,125. Jerez's 25 validation closeouts failed only because the
original controller reached them before the repaired normal-parent lineage reader
was installed. A subsequent repaired-controller attempt passed 44 focused tests
and rebound all controls, but its generic 300 GiB Jerez start gate rejected the
metadata-only closeout with 281.8 GiB free.

No model refit, relaunch, retuning, cleanup, test access, registry mutation, or
article mutation is scientifically justified. A read-only replay of all 25 Jerez
surfaces confirmed that every AL/exAL family-fold surface is numerically eligible
and that the repaired reader can calculate every regional selection.

## Recovery contract

The host controller receives an explicit
`--closeout-only-completed-surface` mode with a distinct approval token. The mode
may use the existing 250 GiB absolute safety floor only after it proves all of the
following for every host-owned region:

1. the launch-grade preparation summary is present, validation-only, and bound to
   its unchanged pipeline hash;
2. the manifest is the exact 45-task DAG;
3. all 45 terminals pass retained-artifact hashes and test firewalls;
4. an existing closeout is valid, or its incomplete output directory is empty;
5. the task branch is clean, synchronized, and equal to the recovery contract;
6. the original controller lock is free.

The closeout-only path invokes script 318 directly. It cannot invoke the surface
launcher or model runner. Its status and shard terminal explicitly record
`model_fitting_invoked: false` and `model_launcher_invoked: false`. Normal fitting
continues to require the 300 GiB Jerez start floor.

## Execution sequence

1. Compile the repaired scripts and run focused lineage, campaign, distributed,
   runtime-recovery, and controller tests.
2. Commit and push only the dedicated PriceFM branch.
3. Rebind the Jerez descendant contract to the validated commit and execute the
   guarded closeout-only mode.
4. Require 25/25 regional summaries and a sealed `completed_validation_shard`
   terminal with no fitting or blocked actions.
5. Restart the Muscat coordination watcher with retry-tolerant SSH polling.
6. Build the compact Jerez `results` inventory, transfer only selected evidence,
   verify every byte and SHA-256 digest, and reconcile all 37 regions on Muscat.
7. Stop with test scoring sealed. The 114-case global test score remains a later,
   explicit one-time decision.

## Validation-only findings

The read-only replay selects exAL for 19 Jerez regions and AL for six, with no
numerical fallback. Combined with Muscat, exAL is selected for 26 of 37 regions.
The selected family has lower validation AQL in 86 of 111 region-fold cases and
an average AQL advantage of approximately 0.063 over the alternative family.
This supports region-specific family selection but does not establish improvement
over authoritative Q-DESN or PriceFM; those comparisons remain test-sealed.

## Completion definition

Recovery is complete only when both shard terminals are validation-complete, the
compact Jerez transfer verifies with zero failures, the 37-region reconciliation
terminal exists, and every test, registry, article, joint-model, and MCMC gate
remains false. No article or registry action belongs to this recovery stage.

## Implemented outcome

The recovery completed on 2026-09-13. Commit `dc824d0` introduced the guarded
closeout-only path, and `ae02022` corrected its pipeline check to use the same
canonical self-seal definition as the R97 producer and launcher. The four-file
focused R97 suite passed on both Muscat and Jerez (`40 passed`), and the Jerez
preflight verified all 1,125 completed task terminals before closeout began.

Jerez then closed all 25 regions with zero failures and wrote a sealed
`completed_validation_shard` terminal. The closeout recorded both
`model_fitting_invoked: false` and `model_launcher_invoked: false`. Its results
inventory contained 2,005 entries and 2,010,313,260 file bytes. Muscat transferred
only those selected results and verified every entry with zero failures.

The authoritative validation-only reconciliation is:

`application/data_local/pricefm/authoritative/pricefm_stage_r97_global_region_frozen_campaign_20260908_distributed_closeout/pricefm_stage_r97_distributed_reconciliation_terminal.json`

It covers all 37 regions and has status
`completed_37_region_validation_reconciliation_test_still_sealed`. Across the
111 region-fold validation comparisons, the Fold-1-selected family is better
than the alternative in 86 cases, with mean selected AQL 7.07628 versus 7.13972
for the alternative. AL is selected for 11 regions and exAL for 26; no region
uses numerical fallback. These are family-selection diagnostics only. No global
test-scoring terminal exists, so no claim against PriceFM or the authoritative
Q-DESN registry is available yet.

The next action is a separate, explicit decision on whether to open the one-time
114-case global test score. Registry and article promotion remain downstream of
that score and its dual-comparator audit; they are not authorized by this closeout.
