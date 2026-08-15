# Shared Validation TT500 MCMC Authoritative Handoff

Date: 2026-07-01

This note records the article-side promotion of the June 30, 2026 Q-DESN
TT500 MCMC confirmation/rescue outputs. The promotion is deliberately narrow:
it replaces only the `qdesn_exal_rhs_ns` MCMC rows in the TT500
fit-and-forecast manuscript tables. It does not replace Q-DESN VB rows,
Q-DESN AL rows, Q-DESN ridge rows, DQLM/exDQLM rows, or any TT5000 rows.

## Validation Source

- Worktree: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Branch: `validation/shared-fitforecast-v2-1.0.0`
- Validation commit containing the promotion artifact:
  `d45abc6e2408a287bd10aff7861f41872e894f8f`
- Promotion materialization HEAD:
  `e99ccdb9ac583e7f494a61879d89a480758638f7`
- Package version: `1.0.0`
- Source registry hash:
  `edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275`
- TT500 training window: `8501:9000`
- Forecast origin: `9000`
- Forecast block: `9001:10000`
- Rolling-origin protocol: maximum lead `30`, origin stride `30`, no refit.

## Promotion Artifact

Promotion directory:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/validation/fitforecast_v2/promotions/qdesn_tt500_mcmc_authoritative_20260701
```

Pinned artifacts:

- Summary CSV:
  `qdesn_tt500_mcmc_authoritative_summary.csv`
- Summary SHA-256:
  `3272c426c4844afc188099f8e63c3d4f442729ee851a0c2347afe7fdff70025d`
- Manifest:
  `qdesn_tt500_mcmc_authoritative_manifest.json`
- Manifest SHA-256:
  `479e4f59b5d6c8eafcadc06a01eaa6951ab44852e40ab6b17f97be8a172cf8a4`
- Source CSV:
  `qdesn_tt500_mcmc_authoritative_sources.csv`
- Source CSV SHA-256:
  `7622a04e02ea3192079bf6d4c1528d26083a22d76a6ca91830c0b2f64a6cae5a`

## Source Runs

Base confirmation:

```text
qdesn-tt500-mcmc-vb-winner-confirmation-full-20260630__git-c051364
```

Campaign stamp:

```text
20260630-101419__git-c051364
```

Rescue run:

```text
qdesn-tt500-mcmc-vbwin-rescue-fail5-full-20260630__git-c051364
```

Campaign stamp:

```text
20260630-112709__git-c051364
```

The promoted set contains 9 successful rows: 5 from the rescue run and 4 from
the base confirmation.

## Diagnostic Qualification

This is an authoritative article-facing MCMC handoff, but it is not a
diagnostic-clean MCMC handoff.

- Selected rows: `9`
- Status: `SUCCESS` for all selected rows
- Diagnostic signoffs: `WARN=7`, `FAIL=2`, `PASS=0`
- Remaining high-autocorrelation rows:
  - `normal`, `tau=0.25`
  - `gausmix`, `tau=0.25`

The article table builder accepts these rows only under the explicit
`diagnostic_qualified_authoritative_mcmc` qualification and records the
remaining signoff reasons in `tables/qdesn_validation_tt500_final_manifest.txt`.

## Article Wiring

Config:

```text
application/config/shared_validation_tt500_final_fitforecast.yaml
```

Builder:

```sh
Rscript application/scripts/31_build_shared_validation_tt500_final_tables.R
```

Audit:

```sh
Rscript application/scripts/32_audit_shared_validation_tt500_vb_competitiveness.R
```

The builder applies the `mcmc_authoritative_handoff` override only after
verifying the promotion summary hash, promotion manifest hash, source registry
hash, package version, validation branch, TT500 windows, rolling-origin grid,
status fields, accepted diagnostic signoffs, and finite display metrics.

## Verification

The table rebuild passed with:

```text
TT500 final manuscript tables: PASS
summary_rows: 108
lead_rows_consumed: 3240
```

The VB competitiveness audit still passed with:

```text
TT500 VB competitiveness audit: PASS
cells: 9
cells_beating_best_dqlm_exdqlm_vb_all_four: 9
```

## Consumption Policy

Use this handoff for the TT500 manuscript comparison only. Do not use it to
claim TT5000 completion, diagnostic-clean MCMC, or exploratory-screening
promotion. Future TT100, TT5000, or strict-clean MCMC handoffs need separate
tracked configs, hashes, diagnostics, and manifests.
