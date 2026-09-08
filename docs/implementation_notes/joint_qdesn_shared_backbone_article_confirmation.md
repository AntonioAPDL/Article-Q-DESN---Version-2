# JOINT Shared-Backbone Article Confirmation

Date: 2026-09-07

Status: `READY_FOR_MUSCAT_TRANSFER_AND_INTEGRATION_REVIEW`

This lane prepares the fixed article-fixture VB/MCMC workflow for the completed
JOINT QDESN shared-backbone family campaign. It does not select a new DESN
design, run a new `tau0` screen, launch production VB, launch MCMC, modify
article assets, or touch integration and Overleaf branches.

The workflow imports the frozen source packet from:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_shared_backbone_all_families_20260906/application/cache/joint_qdesn_shared_backbone_family_campaign_20260906
```

The imported evidence must verify 7,560 completed source jobs, zero failures,
eight scenario-specific selected backbones, 56 finite VB aggregate rows, 14
finite joint-independent contrasts, and 32 future article scenario-model cells.

The prepared article VB graph has 136 components:

```text
8 Gaussian RHS article-window refits
56 independent AL quantile refits
56 independent structured exAL quantile refits
8 joint AL refits
8 joint structured exAL refits
```

The VB finalizer assembles exactly 32 compact top-level initializers, one per
scenario-model cell. MCMC workers are guarded and fail before launch unless all
136 VB components and all 32 initializer manifests verify.

The provisional future MCMC budget is frozen in configuration as 16 AL cells
with 4 chains and 16 exAL cells with 6 exact-M0 chains. That yields 160
top-level chain workers. The launcher defaults to `--dry-run`; production modes
require both explicit later user authorization and the matching
`JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION` environment value.

The VB launch driver is
`application/scripts/run_joint_qdesn_shared_backbone_article_vb_queue.R`. It
runs dependency-ready VB jobs in batches up to the frozen host ceiling, records
batch receipts, reuses completed workers, stops on the first failed worker, and
finalizes the 32 compact initializer packets after the 136/136 gate.

The MCMC launch driver is
`application/scripts/run_joint_qdesn_shared_backbone_article_mcmc_queue.R`. It
requires `JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION=MCMC`, a clean synced
execution branch, the verified VB final manifest, and a maximum of 40
concurrent chain workers. It resumes completed chains, records batch receipts,
stops on failed or malformed worker manifests, and writes a final MCMC artifact
manifest before producing the score-packet handoff. Article MCMC forces the
existing sparse precision-draw backend to avoid non-pivoted dense Cholesky
failures in high-dimensional joint cells while preserving the same posterior
target.

The first MCMC launch on Jerez localized a second, narrower numerical issue:
joint exQDESN/exAL exact-M0 chains can encounter a Cholesky failure in the
weighted beta precision draw after dynamic gamma/sigma/latent/RHS evolution.
The failed workers had valid compact VB initializers, interior support-logit
gamma starts, positive scale starts, and well-conditioned first-iteration beta
precision matrices. That diagnosis rules out tau-grid changes, tau0
reselection, forecast-window leakage, malformed initializer manifests, and
endpoint gamma starts as efficient first fixes.

The implemented repair is therefore intentionally local. Exact-M0 exAL article
workers enable a scale-aware precision-draw fallback that first tries the
existing sparse Cholesky path and then adds diagonal jitter only after a
factorization failure. The jitter is relative to the precision diagonal scale,
starts at `1e-12`, and fails closed above `1e-8`. Every repaired draw records
iteration, backend, relative/absolute jitter, scale, weights, gamma, and sigma
diagnostics in `precision_repair_diagnostics.csv`; unrepaired successful draws
only contribute zero counts in `posterior_summary.csv`. AL workers do not
enable this repair.

The companion audit script
`application/scripts/audit_joint_qdesn_shared_backbone_article_mcmc_failures.R`
rebuilds a reproducible failure packet from either an active runtime or a
quarantined MCMC attempt. It writes failure inventory, completed-worker
inventory, deterministic exAL start preflight, first-iteration precision audit,
queue receipts, and a verifying manifest under the ignored runtime diagnostics
directory. The audit is evidence generation only; it does not modify selected
backbones, tau grids, tau0 values, worker outputs, or article assets.

Relaunch policy after this repair is to quarantine flawed or partial MCMC
attempts, keep their audit packets, and restart the active `mcmc_workers/`
runtime from a clean synced execution commit. The 160-worker gate remains
unchanged: all workers must complete, all worker manifests must verify, and the
final MCMC manifest must verify before score-packet analysis.

Generated runtime belongs under:

```text
application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907
```

The runtime is ignored by Git and retains compact initializers, projected
posterior summaries, diagnostics, logs, statuses, manifests, and restart
metadata. Broad `.RData`, `.rda`, or full model `.rds` dumps are not part of the
default retained output contract.

The deterministic API parity fixture is `tiny_api_parity_20260907`. Under the
mirrored Jerez R 4.6.0 environment it freezes design fingerprint
`d65bccb0e0f074b4e251505aa55e22958dade61e20e940c455b5701f4bf0a170`, compact
initializer dimensions `14/14/7/7`, AL summary values
`0.152213091439/0.235467134628/0.150980779259`, monotone contract crossings
`0`, and qhat fingerprint prefix `3456dbca657c`.

## Closeout Addendum: 2026-09-08

The Jerez continuation completed the article-fixture confirmation without
modifying manuscript files or tracked article tables/figures. Final health now
verifies 7,560/7,560 imported source jobs, 136/136 article-window VB
components, 32/32 compact initializers, and 160/160 MCMC chain workers, all
with zero failures. The MCMC worker manifest verification covers exactly 160
workers; the final VB and MCMC manifests verify every entry. The exAL article
workers used the exact-M0 method with the local scale-aware precision-draw
repair enabled only for exAL chains.

The deterministic score packet is:

```text
application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907/score_packet
```

The score packet was built from commit
`66bd9c6feff6a03881fcf3c0f0351e00f69022f4` with the frozen contract
`application/config/joint_qdesn_shared_backbone_article_score_contract_v1.csv`.
The packet status is `READY_FOR_MUSCAT_TRANSFER_AND_INTEGRATION_REVIEW`:
32 finite posterior score rows, 16 joint-minus-independent contrasts, eight
scenario winners, 10/10 computation re-audit gates passing, zero contract
crossing pairs, and a fully verified packet artifact manifest. The contract
score is known-DGP expected finite-grid quantile score,
`dgp_integrated_acrps`, using seven-level trapezoidal weights
`0.025,0.100,0.200,0.250,0.200,0.100,0.025` on twice quantile check loss over
`design$score_local`.

The score results are article-safe candidates only. Seven of eight descriptive
numerical minima are independent exQDESN/exAL/RHS; `laplace_bridge` has a small
joint exQDESN/exAL/RHS numerical edge. All winner-versus-runner-up 95 percent
intervals overlap, so the ranking should be described as numerical/descriptive
unless a later integration review adopts stricter language. The 16
joint-minus-independent contrasts have zero contract crossings on both sides;
five intervals directionally favor independent models, and 11 overlap zero.

The frozen planning files were not rewritten. Stale values such as
`PENDING_VB_GATE`, `BLOCKED_UNTIL_VB_136_OF_136`, and
`NOT_LAUNCHED_REQUIRES_SEPARATE_FROZEN_CONFIRMATION` are documented as
superseded by the final health evidence in
`score_packet/plan_status_supersession_audit.csv`.

Precision repair evidence is retained in
`score_packet/precision_repair_summary.csv`: all 32 cells pass the precision
repair audit, 96 exAL workers had repair enabled, eight workers used at least
one repair, 34 total precision repairs were recorded, and the maximum relative
jitter was `1e-12`. Scalar gamma/sigma diagnostics for the 16 exAL cells are
retained as review-level diagnostics, not rejection gates, because the score
and quantile-functionals are stable and all contract crossings are zero.

For transfer, retain the complete ignored runtime. The generated
`score_packet/transfer_inventory.csv` covers 2,867 files and 470,322,631 bytes;
the inventory hash is
`ad9cb207cc504354cd09e5a892c65553d1f5061691b9064f2d451791b78ed069`. Do not
delete Jerez runtime artifacts before Muscat confirms the transferred hashes.
