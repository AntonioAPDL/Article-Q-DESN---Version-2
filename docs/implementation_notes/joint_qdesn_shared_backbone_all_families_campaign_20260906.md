# JOINT Shared-Backbone All-Families Campaign

## Decision

The completed Regime Shift experiment validated the computational graph but did
not produce article-authoritative evidence. The next efficient step is to apply
that graph to the seven remaining article scenarios. The campaign stops after
VB because final score comparisons and article replacement require a separately
frozen MCMC confirmation on each scenario's designated article fixture.

This corrects an earlier emphasis on matching the Regime Shift VB pilot to the
existing article result. Such a matched VB challenge would answer a narrow
algorithmic question, but it would not complete the intended eight-scenario
replacement workflow.

## Frozen Scientific Roles

The authoritative Phase181 packet has 32 rows: eight scenarios by four MCMC
models. Each scenario uses one designated `article_fixture`; that fixture did
not select its specification. The Regime Shift pipeline instead used three
non-article observational-selection replicates and three fresh protected VB
evaluation replicates.

The seed roles remain separate:

- observational-selection seeds choose a scenario-specific DESN and Gaussian
  RHS `tau0` from a 350/150 chronological split of the 500-row fit window;
- protected VB seeds verify the four quantile continuations and never alter the
  selected specification;
- the existing registry article seed is recorded but never loaded by this
  campaign; it is reserved for the future MCMC packet.

No universal DESN or `tau0` is selected. Within a scenario, all four quantile
models share its frozen Gaussian-selected feature design and nominal RHS
control. Across scenarios, those controls may differ.

## Seven-Scenario Campaign

The campaign runs:

1. Asymmetric Laplace Tail;
2. Gaussian-Mixture Bridge;
3. Laplace Bridge;
4. Nonlinear Reservoir Friendly;
5. Normal Bridge;
6. Persistent Heavy Tail; and
7. Student-t Location-Scale.

Regime Shift is retained from the completed pilot. For each new scenario, the
pipeline runs 579 Gaussian ridge jobs, advances 30 designs including the
mandatory authority anchor, runs 450 Gaussian RHS jobs over five `tau0` values,
and then runs 51 full-window continuation jobs. The continuation comprises
three Gaussian RHS refits plus Independent QDESN RHS, Independent exQDESN RHS,
Joint QDESN RHS, and Joint exQDESN RHS over three protected replicates.

Total planned work is 7,560 jobs. Families run sequentially; each stage uses
exactly ten one-thread workers at reduced priority. This bounds the additional
load while the separate Phase182 dense-grid campaign remains active and keeps
the stage graph restartable.

## Evaluation And Promotion Boundary

Protected VB output reports DGP-integrated finite-grid aCRPS, realized aCRPS,
check loss, oracle quantile MAE/RMSE, and raw/contract crossings. These metrics
diagnose readiness and help identify numerical failures. They do not select the
DESN, retune `tau0`, determine the article winner, or replace MCMC values.

After all seven scenarios finish, the finalizer must verify:

- 7,560/7,560 completed jobs and zero failures;
- seven selected new backbones plus the retained Regime Shift backbone;
- 56 finite aggregate VB score rows;
- zero reported contract crossings;
- fourteen joint-minus-independent contrast rows;
- all nested and final manifests; and
- a complete future 32-cell MCMC plan.

The next branch must freeze a fresh MCMC protocol. It will refit VB on only the
observational window of each designated article fixture, use those fits as MCMC
initializers, and run the four model rows on the same fixed dataset within each
scenario. Only audited MCMC posterior score summaries may replace the current
article authority.

## Reproducibility

Tracked inputs include the campaign contract, the eight-scenario registry, a
compact Phase180 authority-design snapshot and manifest, and the retained
Regime Shift selection. Preparation freezes source hashes, Git state, generated
scenario contracts, seeds, job counts, child manifests, and the explicit
selection policy into the ignored runtime root.

Focused tests:

```bash
Rscript application/tests/test_joint_qdesn_shared_backbone_screening.R
Rscript application/tests/test_joint_qdesn_shared_backbone_quantile_fit.R
Rscript application/tests/test_joint_qdesn_shared_backbone_family_campaign.R
```

Launch:

```bash
JOINT_SHARED_FAMILY_WORKERS=10 \
  bash application/scripts/launch_joint_qdesn_shared_backbone_family_campaign.sh \
  application/cache/joint_qdesn_shared_backbone_family_campaign_20260906
```

Health check:

```bash
Rscript application/scripts/check_joint_qdesn_shared_backbone_family_campaign.R \
  --root application/cache/joint_qdesn_shared_backbone_family_campaign_20260906
```

## Implementation Checklist

- [x] Preserve the completed Regime Shift pilot without rerunning it.
- [x] Separate observational, protected VB, and article-fixture seed namespaces.
- [x] Track the current-authority design anchor independently of ignored caches.
- [x] Parameterize screening and continuation contracts by scenario.
- [x] Add a resumable, ten-worker, family-sequential launcher.
- [x] Add campaign health and failure-closed finalization.
- [x] Freeze a future 32-cell MCMC handoff schema without launching MCMC.
- [x] Pass the three focused regression tests.
- [ ] Prepare and verify the real seven-family campaign packet.
- [ ] Run one real worker as an end-to-end launch sentinel.
- [ ] Commit and push the dedicated JOINT branch.
- [ ] Launch in background and confirm live worker progress.
- [ ] After completion, freeze results and prepare the separate MCMC protocol.
