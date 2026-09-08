# JOINT Shared-Backbone Article Confirmation

Date: 2026-09-07

Status: `IMPLEMENTED_LAUNCH_FREE_PREFLIGHT`

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
