# Shared Validation TT500 Provisional Progress Snapshot

Date: 2026-06-13

This note records a non-authoritative progress snapshot for the shared
Q-DESN + exDQLM/DQLM fit+forecast validation study. It is for operational
tracking and explicitly labeled status display only while the Q-DESN TT500
MCMC campaign finishes. It must not be used for scientific result tables or
scientific comparison.

## Validation Source

- Worktree: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Branch: `validation/shared-fitforecast-v2-1.0.0`
- Commit at export: `ec465f93b7b799e675c40f3a6382c7c6e9ae5727`
- Package version: `1.0.0`
- Run tag: `qdesn-dynamic-fitforecast-v2-mcmc-tt500-20260520-035319__git-d075941`
- Campaign id: `20260525-191523__git-d075941`

## Provisional Artifacts

Directory:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/reports/qdesn_mcmc_validation/dynamic_fitforecast_v2_validation/qdesn-dynamic-fitforecast-v2-mcmc-tt500-20260520-035319__git-d075941/20260525-191523__git-d075941/provisional_progress`

Files and hashes at this snapshot:

- `tt500_provisional_atomic_progress.csv`:
  `3aee0709d06ab11fe714252013fd4d3a15de273f40033e80e36d53453a8f32ca`
- `tt500_provisional_root_progress.csv`:
  `49cdd51c52ad4c2a667aa130124e4f46c198ef0d4197324270bfead95abc7a98`
- `tt500_provisional_manifest.json`:
  `83b6ca1155edf308aa9ab15ec91dc7a6cd68bc566bc35e8f1df52896685f8e35`

Snapshot counts:

- atomic specs: 36
- complete atomic specs: 32
- running atomic specs: 2
- pending atomic specs: 2
- root specs: 18
- complete root specs: 16
- running root specs: 2

The two running rows and the two pending rows are placeholders. The table is
expected to be refreshed as the campaign advances.

## Article Wiring

Tracked config:

`application/config/shared_validation_tt500_provisional_progress.yaml`

Audit command:

```sh
Rscript application/scripts/29_audit_shared_validation_tt500_provisional_progress.R
```

Status-table build command:

```sh
Rscript application/scripts/30_build_shared_validation_tt500_provisional_table.R
```

The Article guard enforces:

- `is_final = FALSE`
- `article_consumable = FALSE`
- no active `/home/jaguir26/local/src` validation paths
- no stale 0.5.0 validation worktree, branch, or commit references
- source registry hash fields are present
- forecast-origin/window metadata is present
- rolling-origin `max_lead_configured` and `origin_stride` metadata is present
- configured row counts and hashes match the snapshot

This provisional sync originally updated the active local-source Q-DESN engine
commit pin from `17eb1a4ad25117fde5f336cdf921429f8515ef5b` to the provisional
export commit. The final TT500 article handoff now pins these same tracked
configs to the clean shared-validation HEAD
`437dc73385d0922cd2f79d13262947ff1ba01d77`:

- `application/config/glofas_latent_path_al_vb_dec25_main.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_exact_chunked_smoke.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_fullspec_exact_chunked_pilot.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_fullspec_unchunked_pilot.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_exact_chunked_pilot.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_unchunked_pilot.yaml`

## Refresh Procedure

Refresh the validation-side progress snapshot:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
Rscript scripts/export_qdesn_tt500_provisional_progress_table.R \
  --run-tag qdesn-dynamic-fitforecast-v2-mcmc-tt500-20260520-035319__git-d075941 \
  --campaign-id 20260525-191523__git-d075941
```

Then update `application/config/shared_validation_tt500_provisional_progress.yaml`
with the new hashes and counts, and rerun the Article audit command above.

## Consumption Rule

The generated table
`tables/qdesn_validation_tt500_provisional_progress.tex` may be included only
as an operational status table. Do not point
`scripts/build_qdesn_simulation_tables.R` at these provisional files. Final
article result-table consumption remains blocked for this provisional artifact.
The final TT500 article-facing handoff added on 2026-06-21 is documented in
`docs/implementation_notes/shared_validation_tt500_final_article_handoff_20260621.md`
and uses `application/config/shared_validation_tt500_final_fitforecast.yaml`
instead of this progress snapshot.
