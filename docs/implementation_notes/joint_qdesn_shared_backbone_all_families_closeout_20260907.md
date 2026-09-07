# JOINT Shared-Backbone All-Families Closeout

Date: 2026-09-07

Status: `VB_FAMILY_CAMPAIGN_COMPLETE_READY_TO_FREEZE_MCMC_PROTOCOL`

## Scope And Decision

This phase implemented and completed the case-specific shared-backbone
selection and quantile-VB warm-start graph for the seven article scenarios not
covered by the retained Regime Shift pilot. It did not use an article fixture
for selection, launch MCMC, or modify article assets.

The phase is complete. A further broad VB screen is not warranted. The next
scientific task is a separately frozen article-fixture VB-initialization and
MCMC-confirmation campaign for eight scenarios and four model classes.

## Completion Audit

| Item | Result |
|---|---:|
| Planned/completed/failed jobs | 7,560 / 7,560 / 0 |
| New scenario packets | 7 / 7 |
| Retained pilot scenarios | 1 |
| Selected case-specific backbones | 8 |
| Aggregate VB score rows | 56 / 56 finite |
| Forecast aggregate rows | 28 |
| Joint-minus-independent contrasts | 14 / 14 finite |
| Nested artifact entries | 98 / 98 verified |
| Campaign final-manifest entries | 7 / 7 verified |
| Future MCMC cells | 32 |
| Article fixtures used for selection | 0 |
| MCMC jobs launched | 0 |
| Article assets modified | 0 |

The background pipeline exited with code zero at
`2026-09-07T03:59:27Z`. No campaign worker or tmux session remains active.

## Selected Backbones

| Scenario | Selected design | Class | RHS `tau0` | Calibration aCRPS gain vs parity |
|---|---|---|---:|---:|
| Asymmetric Laplace Tail | `ridge_076` | reservoir | 0.0001 | 0.000275 |
| Gaussian-Mixture Bridge | `ridge_028` | hybrid | 0.0001 | 0.001305 |
| Laplace Bridge | `ridge_079` | hybrid | 0.1 | 0.001338 |
| Nonlinear Reservoir Friendly | `ridge_089` | hybrid | 0.0001 | 0.000539 |
| Normal Bridge | `ridge_071` | hybrid | 0.001 | 0.001436 |
| Persistent Heavy Tail | `ridge_150` | hybrid | 1 | 0.001623 |
| Regime Shift | retained authority anchor | direct | 1 | 0 |
| Student-t Location-Scale | `ridge_128` | reservoir | 1 | 0.001467 |

Selection used only the frozen 350/150 observational split. Protected VB
scores did not alter these choices.

## Protected VB Findings

Independent exQDESN had the lowest protected-replicate mean DGP-integrated
aCRPS and AQL in all seven new scenarios. Mean results across the seven are:

| Model | DGP-integrated aCRPS | AQL | Raw crossings |
|---|---:|---:|---:|
| Independent exQDESN | 0.3675 | 0.1633 | 535 |
| Independent QDESN | 0.3799 | 0.1786 | 1,980 |
| Joint exQDESN | 0.4473 | 0.2001 | 222 |
| Joint QDESN | 0.4537 | 0.2079 | 2,320 |

All contract-crossing counts are zero. Joint exQDESN has zero raw crossings in
five of seven scenarios and materially lowers average raw crossings relative
to independent exQDESN, but it does not win a protected VB score comparison.
This is evidence about the variational approximation and initialization graph,
not final evidence against the joint model.

## Frozen Evidence

Runtime root:

```text
application/cache/joint_qdesn_shared_backbone_family_campaign_20260906
```

Approximate size: 391 MiB.

| Artifact | SHA-256 |
|---|---|
| `final_artifact_manifest.csv` | `30e2714224b503a19f23f57a8e094378f6475f824358e9568327088d7f0f45a2` |
| `final_decision.csv` | `c97891c4e8af0b6f51e17dd86ed21afacc3411d443152e40d733ca1acc61c1bc` |
| `final_health.csv` | `8ad5c95aa1702525aed9f133b13b124e6eb0e7210efb06d03da05b9b4c43ff2d` |
| `nested_manifest_verification.csv` | `e66705973cf3a87e26e1f639143859531a2ed5e41c4cf8bb0dc4e5ccbad708ef` |
| `selected_family_backbones.csv` | `c7fbc90d34b3ad9600e0ddb9c0462b0015ec6b176c07acd7bb2d6ef84d8de7c3` |
| `seven_family_vb_score_aggregate.csv` | `6a634e6f4bf17b1c84c32ec71bdbeeaac51d34e425d592781ea727d6c0dd5a58` |
| `seven_family_joint_independent_contrasts.csv` | `149d4c3dda5ac72620abe2c05821130cac00a1764b506f0731a4fd576fa0fc3c` |
| `future_article_fixture_mcmc_plan.csv` | `594e5ecdd77ab3784b51ed07d1e07ba03202ffef331dc9859554efc6ceeae167` |

The runtime root is a retained reproducibility source. It remains excluded by
`.gitignore` and must not be cleaned before the MCMC freeze has imported and
verified the selected backbones and required VB provenance.

## MCMC Boundary

The broad VB work is complete, but the final article-fixture initialization is
not. The next branch must:

1. load the 32-row future plan and verify its source hashes;
2. refit the selected Gaussian RHS and quantile-VB warm-start graph on each
   designated article observational window;
3. freeze one matching VB initializer for each scenario-model cell;
4. generate independent, overdispersed chain starts around each initializer;
5. freeze chain, component, and DGP seeds plus MCMC budgets;
6. launch the 32-cell confirmation without selecting on article-fixture scores;
7. report DGP-integrated aCRPS with posterior summaries and 95% intervals,
   AQL, oracle recovery, raw/contract crossings, and functional stability.

The protected-replicate VB objects may validate the graph and inform numerical
defaults, but they are not substitutes for the article-fixture refits.
