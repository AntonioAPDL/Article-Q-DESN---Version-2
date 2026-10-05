# JOINT storage cleanup receipt

Date: 2026-09-30
Host: Jerez
Scope: JOINT lane only

## Safety gates

- No removed path was referenced by a live process.
- Current pure-DESN screening, VB, MCMC, score, fixture, design, and initializer
  roots were excluded from deletion.
- Historical authoritative data were removed from Jerez only after a surviving
  Muscat copy passed checksum comparison.
- Failed-preparation payloads were removed only after retaining their SHA-256
  inventories, status tables, and incident metadata.
- The full capacity-wait history remains; four representative, individually
  manifested attempts remain: initial, final blocked, first clean, and ready.

## Removed data

| Bytes | Removed Jerez path or payload | Evidence retained |
|---:|---|---|
| 473,061,449 | `joint_article_confirmation_jerez_20260907/.../joint_qdesn_shared_backbone_article_confirmation_jerez_20260907` | Exact Muscat review copy; 2,867-file transfer inventory, 470,322,631 manifest bytes, zero hash mismatches; checksum `rsync` dry run empty |
| 13,822,830 | first `.superseded.20260907T173849` preparation root | Explicitly superseded, pre-authority runtime |
| 13,822,845 | second `.superseded.20260907T175623` preparation root | Explicitly superseded, pre-authority runtime |
| 339,999,040 | `joint_shared_backbone_all_families_20260906/.../joint_qdesn_shared_backbone_family_campaign_20260906` | Byte-identical Muscat campaign copy; checksum `rsync` dry run empty |
| 389,652,929 | `joint_recursive_mean_forecast_jerez_20260924/application/cache/source` | Byte-identical Muscat corrected-confirmation source; checksum `rsync` dry run empty; Jerez score summaries retained |
| 17,715,390 | standalone `joint_qdesn_pure_recursive_controller_schema_recovery_v3_20260926` | Byte-identical snapshot retained in the recovery archive before payload compaction |
| 35,029,381 | 1,204 redundant `mcmc_capacity_wait/attempt_*` directories | Full `mcmc_capacity_wait_history.csv`; attempts 000001 and 001206-001208 retained |
| 21,942,884 | failed shared-v6 `confirmation_partial` payload | Parent `files.sha256`, archive metadata, process evidence, and source-control evidence retained |
| 17,674,794 | failed schema-recovery preparation payload under `control_root_snapshot/archives` | `files.sha256`, partial inventory, verification, status, launch receipt, and capacity history retained |
| 391,499,700 | Muscat `joint_qdesn_recursive_mean_forecast_v3_jerez_20260924/oracle_banks` | Superseded mean-state experiment; verified final packet, oracle plan, manifest, score summaries, and cell outputs retained |
| 241,110,463 | Muscat `joint_qdesn_recursive_mean_forecast_v3_jerez_20260924/oracle_shards` | Regenerable intermediate shards; verified final packet and compact provenance retained |
| **1,955,331,705** | **Total removed** | **Approximately 1.82 GiB** |

## Preserved authoritative/current data

- `joint_qdesn_pure_recursive_campaign_jerez_15core_20260925`;
- `joint_qdesn_pure_recursive_article_confirmation_jerez_15core_20260925`;
- all 135 MCMC workers completed before recovery, whose ordered manifest-hash
  digest was
  `f18724ee7f222c6e1722e0f05108c840031231e353a12cf844a2eaa3addd576a`;
- the pending score-packet path and corrected expanded-screen scheduler;
- compact recovery metadata and the preliminary fit/forecast atlas;
- compact final outputs from the superseded recursive mean-state experiment,
  without its regenerable 603 MiB oracle-bank/shard payload;
- authoritative historical comparison packets on Muscat.

## Recovery state after cleanup

Capacity attempt 001208 passed after two clean polls. Its artifact manifest has
six verified rows, including the disjoint-process audit. Five PriceFM R122
processes were approved from explicit controller/worker evidence, with zero
declared or worker physical-core overlap with JOINT. Fifteen JOINT workers then
started only on CPUs `1,8,9,12,13,15,19,20,24,25,27,28,29,30,31`.

The cleanup does not change scientific outputs or selection decisions. It only
removes duplicate or failed runtime payloads while retaining the information
needed to explain and reproduce their disposition.
