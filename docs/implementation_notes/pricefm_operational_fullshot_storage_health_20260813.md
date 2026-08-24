# PriceFM operational full-shot storage and health audit (2026-08-13)

## Scope

This audit covers only PriceFM artifacts owned by the historical PriceFM
campaigns and the operational full-shot campaign. It did not modify the
PriceFM decision registry, article files, source windows, predictions, metric
summaries, fitted confirmation evidence, or any non-PriceFM process or file.

## Publication state

- Implementation branch: `work/pricefm-operational-fullshot-20260812`
- Implementation commit before this note: `ae27845acff3fd97e52f579bbefd4cb31209f28a`
- Remote: `https://github.com/AntonioAPDL/Article-Q-DESN---Version-2.git`
- Focused validation: `5 passed` in
  `application/tests/test_pricefm_operational_fullshot.py`
- The branch is intentionally separate from `main`. The local `main` checkout
  contains unrelated work and the remote `main` is moving under other active
  workstreams.

## Cleanup decision

The cleanup removed only deterministic adapter caches from seven inactive
PriceFM stages. A file was eligible only when all of the following held:

1. Its run had no active process.
2. Its cell retained the adapter and feature manifests, cell configuration,
   metric summary, model run manifest, report, and logs.
3. Row and response cache hashes matched the adapter manifest.
4. Feature-map seed and reservoir configuration remained recorded.
5. Every referenced source window and source manifest existed and matched its
   recorded SHA-256 hash.

The audit verified 334 row/response hashes, 58 deterministic feature-map
recipes, and 336 unique source files with zero missing or mismatched sources.

## Cleanup result

| Item | Result |
| --- | ---: |
| Deleted files | 392 |
| Deleted bytes | 1,381,861,952 |
| Inactive stages covered | 7 |
| Planned paths remaining | 0 |
| Pre-delete size/hash failures | 0 |

Local ignored ledgers:

- `application/data_local/pricefm/cleanup_manifests/pricefm_inactive_reconstructable_adapter_cleanup_20260812_plan.tsv`
  (`f31b98f3c4a2a7f31f294f1bd102e2c0f0600fabc12df0af23df5ae2e1e4c774`)
- `application/data_local/pricefm/cleanup_manifests/pricefm_inactive_reconstructable_adapter_cleanup_20260812_deleted.tsv`
  (`b2b7628a75dd7e5fd2f4fe7aaaa14a7a5578e2316ea05eff2b60eb244490a801`)
- `application/data_local/pricefm/cleanup_manifests/pricefm_inactive_reconstructable_adapter_cleanup_20260812_summary.json`
  (`2210517e23fc5f8e98c8f7ad756b39e08b6862d585ff2afa6017d3d36d96ece3`)

Retained evidence includes all predictions and metric summaries, all configs,
manifests, reports, and logs, all authoritative assets, all source windows, all
56 Stage-R50 MCMC confirmation RDS files (65,328,824 bytes), and every active
Stage-R53 artifact. No surviving inactive `.rds`, `.rda`, or `.rdata` file was
discardable: the only such set is the Stage-R50 confirmation evidence.

## Runtime health

At the audit checkpoint, Stage-R53 was healthy and advancing:

- 2,436 planned chains
- 424 completed chains with `status=completed`
- 24 active chains
- 2,012 chains remaining
- 14 of 87 cases fully completed
- zero malformed or failed job summaries

The operational full-shot scheduler was also alive and healthy, but remained
at its resource gate. It reported zero idle physical cores, load 48.57, and
adequate memory and disk. Its contract requires 20 idle physical cores and
load at most 36 before it creates campaign artifacts.

## Recommendation

Do not stop or relaunch either PriceFM process. Stage-R53 is making progress,
and stopping it would not create the 20 idle physical cores required by the
operational campaign while unrelated workloads still occupy the host. Leave
the operational scheduler in place so it starts automatically after a real
capacity release. Recheck Stage-R53 completion, active worker count, failed
summaries, and the scheduler resource gates before launching any additional
PriceFM work.
