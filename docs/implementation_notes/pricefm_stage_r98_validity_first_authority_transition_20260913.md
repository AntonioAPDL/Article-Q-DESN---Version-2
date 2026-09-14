# PriceFM Stage-R98 validity-first authority transition

Date: 2026-09-13

## Purpose

Stage R98 converts the completed Stage-R97 validation-frozen experiment into a
single prospective PriceFM evidence surface. It does not fit, tune, or select a
new model. Its job is to authorize one scoring-only test pass, preserve the
pre-registered R97 performance result, and prepare a complete 114-case authority
package for the integration coordinator.

The authority decision is protocol-based. The full R97 surface replaces the
full R92 surface even if its mean test AQL is worse. R92 remains available as a
clearly labelled historical sensitivity analysis; no R92 row may be restored as
a case-level fallback after seeing R97 test performance.

## Scientific diagnosis

R92 is a coherent historical result and its final selective-promotion closeout
reports validation-only selection. This audit therefore does not claim that the
R92 closeout directly selected models on test. The limitation is broader: R92
was assembled retrospectively from a long adaptive sequence of region-fold
experiments and does not match the intended prospective region-frozen protocol.

R97 is the prospective reset:

1. For each region, ridge and normal-RHS screening use temporal validation
   windows nested inside the original Fold-1 training interval.
2. One DESN specification and one `tau0` are frozen for the region.
3. Complete seven-quantile AL and exAL surfaces are fit for all three folds.
4. One likelihood family is chosen from Fold-1 validation and then shared across
   all three folds; there is no fold-level or quantile-level family mixing.
5. Test remains sealed until all 37 newly fit regions are reconciled.
6. The previously completed SE_2 R95/R96 surface is reused because it follows
   the same region-frozen, validation-only logic and was scored without refit or
   post-test reselection.

This gives 38 regions, three folds per region, seven paper quantiles per case,
and exactly 114 region-fold cases.

## Two decisions that must remain separate

The R97 pre-registration asks whether the complete candidate mean AQL is
strictly lower than the frozen R92 mean AQL. That performance gate is immutable
and must be reported as passed or not passed.

R98 asks a different question: which surface is scientifically authoritative
under the intended protocol? The answer is R97/R98 because it is the prospective
region-frozen surface. Performance is reported, but it does not decide whether
to retain an R92 case. This distinction prevents outcome-dependent authority.

## Implementation

### Authorization audit

`329_prepare_pricefm_stage_r98_validity_first_authority.py` verifies:

- the sealed 37-region distributed reconciliation;
- the original R97 campaign hash and 114-case contract;
- the exact frozen R92 comparator hash;
- all 37 R97 region closeouts, selected atom manifests, and source hashes;
- one family and one DESN/`tau0` specification per region;
- three folds and the exact seven paper quantiles per region;
- the R95/R96 SE_2 compatibility and scoring-only provenance;
- a clean, synchronized dedicated PriceFM task branch;
- hashes of every script used by scoring and closeout.

It emits a sealed authorization that opens test access once while leaving model
refit, selection changes, registry changes, article changes, joint models, and
MCMC blocked.

### Scoring

`326_finalize_pricefm_stage_r97_distributed_campaign.py score` now requires both
the explicit scoring token and the sealed R98 authorization. It verifies the
authorization sources, script hashes, campaign root, and current Git identity.
It rejects a second scoring invocation after a global terminal exists.

`320_score_pricefm_stage_r97_frozen_case.py` first reproduces each frozen
validation prediction to the configured numerical tolerance. It then applies
the already fitted coefficients to test without fitting or reselection. In
addition to the overall case metric, it writes per-horizon and per-quantile
diagnostics while test truth is available. Large design matrices are deleted
after successful scoring; the evidence required to reproduce and audit the
score is retained.

### Authority closeout

`330_closeout_pricefm_stage_r98_validity_first_authority.py` verifies the global
scoring terminal and exact 114-case R97 closeout. It constructs:

- a complete R98 authority registry with all 114 R97 rows;
- frozen region specifications and validation metrics;
- R92 and cached PriceFM comparisons;
- region, fold, and global AQL summaries;
- a 114-row authority-transition ledger;
- a coordinator-ready LaTeX table and region comparison figure;
- source and article-asset hash manifests.

The generated registry is an integration candidate, not a mutation of the
repository's published registry. The coordinator owns publication to main and
the article snapshot.

## Failure policy

A scoring failure may justify only a mechanical scoring or evidence repair.
It may not change a DESN specification, `tau0`, likelihood family, selected
quantile atom, comparison rule, or authority rule. Any scientific change would
require a new named prospective stage and a newly sealed test boundary.

## Outputs

Runtime outputs belong under ignored `application/data_local/pricefm` paths:

- `authoritative/pricefm_stage_r98_validity_first_authority_prep_20260913`
- `campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908/global_scoring`
- `authoritative/pricefm_stage_r98_validity_first_authority_closeout_20260913`

The task branch stores only scripts, focused tests, and this implementation
note. It must not update article files, main, Overleaf refs, non-PriceFM work,
joint models, or MCMC.

## Integration order

1. Merge the coherent PriceFM task branch after scoring and R98 closeout pass.
2. Verify the R98 source and article-asset manifests in the integrated tree.
3. Replace the published R92 authority with all 114 R98 rows together.
4. Label R92 as historical sensitivity, not a current fallback surface.
5. Update PriceFM prose, tables, and figures with the observed R98 result.
6. Compile the manuscript and publish the article-only snapshot through the
   integration coordinator.

No direct merge to main or Overleaf publication is authorized in this lane.

## Materialized result

The one-time scoring pass completed on 2026-09-13 with 111/111 new scoring
terminals and the three frozen SE_2 folds, giving the exact 114-case surface.
No model was refit and no selection changed after test was opened.

| Surface | Mean AQL | Role |
|---|---:|---|
| R98 region-frozen Q-DESN | 7.217007320 | protocol-valid authority candidate |
| Cached PriceFM | 7.038685347 | external comparator |
| R92 Q-DESN | 6.823677420 | deprecated historical sensitivity |

The R97 preregistered performance gate did not pass: R98 is 0.393330 AQL
higher than R92 and 0.178322 higher than cached PriceFM. This outcome does not
change the R98 validity decision and does not authorize any case-level fallback.

The result is heterogeneous rather than uniformly poor:

- R98 beats cached PriceFM in 54/114 region-fold cases and 16/38 region means.
- R98 beats historical R92 in 49/114 cases and 17/38 region means.
- Fold-2 mean AQL is 6.798915 versus PriceFM 6.826320; Fold 1 is close
  (7.353306 versus 7.296932), while Fold 3 is the main aggregate weakness
  (7.498802 versus 6.992804).
- The largest region-mean gains over PriceFM occur in EE, DK_1, IT_NORD, FR,
  PT, and ES. The largest deficits occur in HR, SK, HU, BG, and LV.
- Validation and test AQL remain strongly ordered across cases (Pearson 0.795;
  Spearman 0.847), so validation remains informative even though the complete
  surface does not beat the comparators on mean AQL.

These comparisons are audit-only. They identify future prospective research
questions but must not be used to alter the frozen R98 authority surface.

## Materialized evidence

- Scoring authorization file SHA-256:
  `3b37f89a618ffd3fa7a71b2a5c7293903606dcf28457bd92cd5c55907913f3d0`
- Global scoring terminal canonical seal:
  `a7e0a6b5d20752042666a3752f1d4246870133da2f9d36da8a9324d147957056`
- R98 registry SHA-256:
  `4cf8ff653c6bd7fc64a2992fbfb6e1df48867d1b7d840cd8544fb30a5c538cb6`
- R98 transition ledger SHA-256:
  `35b0f3d55a1e5ac7e489b3cf171c0f9865e07a012e2fbb4a4674302fa5ef53cd`
- R98 global comparison SHA-256:
  `e3831615ceefe497d68f72176c4a68437448634868aed4c2fada5029ec2768b4`
- R98 closeout source manifest SHA-256:
  `98e5abd74b46988c1afa014455e8cf457929a6ecab3def39b3eeb74d89218dfa`

The prep manifest contains 197 hash-valid records, the closeout manifest
contains 308 hash-valid records, and the six article-safe candidate assets are
hash-valid. Runtime evidence remains under ignored `application/data_local`.

## Publication recommendation

The integration coordinator should replace R92 with the complete R98 registry
and report the observed R98 comparison without claiming a predictive
improvement. The central result is that a prospective, leakage-resistant
region-level calibration remains competitive in many cases but is modestly
worse in aggregate than cached PriceFM and the retrospective R92 surface. R92
may be retained only as a labelled historical sensitivity analysis.

The existing R92 horizon comparison covers 72 of 114 cases and therefore must
not be silently relabelled as an R98 full-surface horizon comparison. The R98
scorer retains full horizon summaries for all 111 newly scored cases and R96
retains SE_2 horizon-group summaries; any replacement horizon table must state
its exact matched coverage and derivation.
