# JOINT corrected article comparison: frozen score closeout handoff

## Integration disposition

```text
SCIENTIFIC_LANE:       COMPLETE
CORRECTED_SCORE_PACKET: COMPLETE_AND_HASH_VERIFIED
ARTICLE_MUTATION:      NONE
OVERLEAF_MUTATION:     NONE
INTEGRATION_STATUS:    READY_FOR_INTEGRATION
```

This handoff closes the corrected seven-level JOINT article-fixture comparison.
It is an integration input, not permission for this lane to merge `main` or
publish the article. The integration coordinator must review the scientific
qualifications below before replacing Phase181 article assets.

## Lane identity

```text
Lane:       JOINT corrected article comparison, Muscat 11-core execution
Worktree:   /data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_corrected_article_comparison_muscat_11core_20260909
Branch:     work/joint-qdesn-corrected-article-comparison-muscat-11core-20260909
Upstream:   origin/work/joint-qdesn-corrected-article-comparison-muscat-11core-20260909
Run tag:    joint_qdesn_corrected_article_comparison_muscat_11core_20260909
Runtime:    application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909
Rscript:    /data/jaguir26/local/opt/R/4.6.0/bin/Rscript
Transcript: /home/jaguir26/.codex/thread_history_1.sqlite
Thread ID:  019f191a-77c2-7393-9f42-60593f12e994
```

The score packet was generated from execution code commit
`b9af9ef4a7da8b507827dce9cd0d6d0b2a53ab24`. The final handoff commit is the
tip of the branch named above; the coordinator must require it to equal its
upstream before integration.

## Git relationship at closeout preparation

After `git fetch origin` on 2026-09-12:

```text
origin/main: 41e3243c14a0d2aa9c200c798c77fd35d6685f3d
merge base:  edf751e663977a13ba4e5eebc42219723efcae68
lane HEAD:   b9af9ef4a7da8b507827dce9cd0d6d0b2a53ab24
main-only commits: 24
lane-only commits before this closeout handoff: 9
lane/upstream divergence before this closeout handoff: 0 ahead, 0 behind
```

Unique scientific and execution commits, oldest first:

1. `f2c5303f5683c2606330997c744d836210bfead4` - Prepare corrected JOINT article comparison.
2. `b71ec3e5f3eb6124893682b2cba257247f375c2c` - Prepare corrected JOINT Muscat execution lane.
3. `4b1d8f51a3d888ceecb529d075e5ba4c27f4d6d6` - Add shared-capacity JOINT Muscat execution lane.
4. `c27e4416c8f9f6a3de051e82386d64e382b5530d` - Fix JOINT MCMC queue preflight lineage.
5. `aedb3f0226151a98c859b3f81384a5acdd3bb587` - Repair JOINT AL precision recovery.
6. `d69aa7e2975371fbec8087e62a9e7c4502bde9c2` - Add corrected JOINT MCMC sentinel launch.
7. `223f4e21098b1f5d0c4533e95a4d2650a3a74e09` - Repair JOINT Gaussian precision mean solves.
8. `ab3137bae9ebca2525a77bf86649369f37cf47d6` - Clarify JOINT resume equivalence evidence.
9. `b9af9ef4a7da8b507827dce9cd0d6d0b2a53ab24` - Fix independent AL failure audit initialization.

Because `origin/main` advanced after the lane fork, the coordinator should
integrate these commits in a fresh worktree based on current `origin/main`.
This lane must not merge or rebase itself.

## Scientific contract

- Eight scenario-specific shared backbones are retained; there is no universal
  DESN or `tau0` specification.
- Models are Joint/Independent QDESN under AL and Joint/Independent exQDESN
  under exAL, all with the RHS prior.
- Each of 32 model cells has five chains sharing one immutable posterior-target
  hash. Chain dispersion changes starts only, never prior centers.
- The primary score is `dgp_integrated_acrps`: twice expected check loss under
  the known DGP, integrated over quantiles
  `0.05,0.10,0.25,0.50,0.75,0.90,0.95` with trapezoidal weights
  `0.025,0.100,0.200,0.250,0.200,0.100,0.025` and no renormalization.
- The canonical action is the chain-balanced posterior-mean quantile path
  followed by the frozen rowwise isotonic reporting contract.
- Joint posterior draws preserve cross-level identity. Independent product
  posteriors use seeded within-chain per-level permutations and three coupling
  sensitivity seeds.
- A lower posterior score mean defines only a descriptive numerical winner.
  Mean, median, equal-tailed 95 percent interval, and canonical-action score
  remain visible together.

The corrected target is necessary because the historical JOINT confirmation
allowed dispersed chain-specific intercept starts to become proper-prior
centers. Those chains did not share one posterior target. The corrected packet
must therefore replace the historical comparison based on scientific validity,
not only in cells where the corrected mean is numerically smaller.

## Completion and integrity

| Gate | Expected | Observed | Failed | Status |
|---|---:|---:|---:|---|
| Frozen source jobs | 7,560 | 7,560 | 0 | pass |
| VB components | 136 | 136 | 0 | pass |
| Compact initializers | 32 | 32 | 0 | pass |
| MCMC workers | 160 | 160 | 0 | pass |
| MCMC model cells | 32 | 32 | 0 | pass |
| Retained MCMC draws | 180,000 | 180,000 | 0 | pass |
| Worker artifact checks | 960 | 960 | 0 | pass |
| Final MCMC manifest checks | 173 | 173 | 0 | pass |
| Posterior-target hash checks | 32 | 32 | 0 | pass |
| Score rows | 32 | 32 | 0 | pass |
| Joint/independent contrasts | 16 | 16 | 0 | pass |
| Scenario winners | 8 | 8 | 0 | pass |
| Formula/quadrature checks | 102 | 102 | 0 | pass |
| qhat reconstruction checks | 160 | 160 | 0 | pass |
| Score-packet manifest checks | 26 | 26 | 0 | pass |
| Contract crossings | 0 | 0 | 0 | pass |

The authoritative MCMC health has zero failures. Across all historical batch
receipts, 28 failed attempts remain preserved and superseded; they document
the repaired queue self-detection and precision-system failures. They are not
final failed model cells and must not be counted against the final 160/160
authority.

## Frozen score result

| Scenario | Posterior-mean winner | Mean | 95% interval | Mean minus runner-up | Qualification |
|---|---|---:|---:|---:|---|
| Asymmetric Laplace tail | Independent exQDESN | 0.332351 | [0.321160, 0.351775] | -0.022953 | intervals overlap |
| Gaussian-mixture bridge | Independent exQDESN | 0.393558 | [0.387131, 0.405470] | -0.003980 | intervals overlap |
| Laplace bridge | Joint exQDESN | 0.333457 | [0.324634, 0.352479] | -0.001401 | intervals overlap; canonical action favors independent exQDESN |
| Nonlinear reservoir friendly | Independent exQDESN | 0.429598 | [0.425301, 0.436212] | -0.002143 | intervals overlap |
| Normal bridge | Independent exQDESN | 0.332264 | [0.314609, 0.364618] | -0.000788 | intervals overlap |
| Persistent heavy tail | Independent exQDESN | 0.370667 | [0.362176, 0.387759] | -0.003672 | intervals overlap |
| Regime shift | Independent exQDESN | 0.431023 | [0.426299, 0.441524] | -0.000086 | intervals overlap |
| Student-t location-scale | Independent exQDESN | 0.352097 | [0.340812, 0.374742] | -0.008229 | intervals overlap |

Posterior-mean ranking gives independent exQDESN seven wins and Joint exQDESN
one. The canonical reported action gives independent exQDESN all eight wins.
The disagreement in `laplace_bridge` is small and scientifically important:
the article must show both quantities and must not call Joint exQDESN a robust
winner there.

Within-likelihood joint-minus-independent contrasts show:

- AL: independent is the numerical winner in 8/8 scenarios; three intervals
  directionally favor independent and five overlap.
- exAL: independent is the numerical winner in 7/8 scenarios; one interval
  directionally favors independent and seven overlap.
- No contrast interval directionally favors a joint model.

The valid article conclusion is not that the joint model dominates predictive
score. The defensible result is a coherence/performance tradeoff with broad
score uncertainty.

## Diagnostics and qualifications

- Canonical raw forecast crossing pairs total 1,197 for Joint AL, 3,522 for
  Independent AL, 0 for Joint exAL, and 269 for Independent exAL. All 269
  Independent exAL crossings occur in `asymmetric_laplace_tail`.
- The reporting contract reduces crossings to zero for all 32 cells.
- Score-functional status is 22 pass and 10 review. Reviews are concentrated
  in joint cells and reflect frozen R-hat/ESS thresholds, not hard failures.
- Coherence status is 8 pass and 24 review because raw crossings or monotone
  adjustments are retained as review-level evidence.
- All 16 exAL gamma/sigma rows are `review_level_retained`. The worst joint
  nonlinear-reservoir diagnostic has gamma rank-Rhat 1.125 and bulk ESS 41.7;
  scalar mixing must remain qualified.
- Chain-allocation score-mean ranges are largest for Gaussian-mixture Joint AL
  (0.02468) and asymmetric-tail Joint AL (0.01935).
- All 16 independent coupling audits pass; maximum relative posterior-mean
  shift is 0.000801.
- Quantile-path reconstruction passes 160/160 workers; maximum validation
  difference is `1.24345e-14` against tolerance `1e-8`.
- Precision repair affected 26 joint workers and 159 operations: 62 Joint AL
  and 97 Joint exAL. Maximum relative jitter was `1e-12`, well below the
  fail-closed `1e-8` ceiling.
- Phase181 reconciliation labels all 32 rows only
  `descriptively_comparable`. The corrected score is lower in three cells and
  higher in 29, but this is not a promotion rule because Phase181 did not have
  the corrected common-posterior target.

## Frozen artifacts and hashes

Primary ignored evidence:

```text
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/score_packet/packet_health_summary.csv
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/score_packet/posterior_dgp_integrated_acrps_summary.csv
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/score_packet/canonical_action_dgp_integrated_acrps.csv
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/score_packet/joint_independent_contrast_summary.csv
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/score_packet/scenario_winner_summary.csv
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/score_packet/score_functional_diagnostics.csv
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/score_packet/crossing_and_adjustment_summary.csv
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/score_packet/phase181_reconciliation.csv
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/score_packet/artifact_manifest.csv
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/score_packet/artifact_manifest_verification.csv
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/score_packet/transfer_inventory.csv
```

```text
score contract SHA-256: d2d118f1b1b1e6feedcd4d552c20ad6d95902d1be833f5af257d7b61f0289ad1
transfer inventory SHA-256: e4b98fe89a8a0c2323f8205c1abef608ff733bc5ec323ea6372198caca02191d
transfer files: 2,970
transfer bytes: 387,506,202
independent transfer verification: 2,970 present, 0 size mismatches, 0 SHA-256 mismatches
```

The inherited score postprocessor still contains several legacy `Jerez`
display strings in diagnostics and deferred staging descriptions. The packet
health status, execution commit, runtime path, and manifests correctly identify
the Muscat authority. These strings are a presentation/provenance caveat only;
changing them after scoring would require regenerating the packet and is not a
scientific reason to do so.

## Tests executed

Pinned R 4.6.0:

```text
application/tests/test_joint_qdesn_posterior_contract.R                         PASS
application/tests/test_joint_qdesn_corrected_article_comparison_contract.R       PASS
application/tests/test_joint_qdesn_corrected_article_comparison_muscat_contract.R PASS
application/tests/test_joint_qdesn_corrected_article_comparison_muscat_shared_contract.R PASS
application/tests/test_joint_qdesn_shared_backbone_article_confirmation.R         PASS
application/tests/test_joint_qdesn_shared_backbone_article_score_packet.R          PASS
bash -n application/scripts/launch_joint_qdesn_corrected_article_comparison_muscat_11core.sh PASS
git diff --check                                                                   PASS
```

The production finalizer also reran the MCMC checker before scoring. Article
compilation was not run because this lane changed no article file and produced
no publication-ready TeX or PDF.

## Exact tracked file surface

Relative to merge base `edf751e663977a13ba4e5eebc42219723efcae68`, this lane
owns the following files:

```text
application/R/joint_qdesn_mcmc_readiness.R
application/R/joint_qdesn_shared_backbone_article_confirmation.R
application/R/joint_qdesn_shared_backbone_article_score_packet.R
application/R/joint_qvp_qdesn.R
application/config/README.md
application/config/joint_qdesn_corrected_article_score_contract_v2.csv
application/config/joint_qdesn_corrected_article_score_contract_v3.csv
application/config/joint_qdesn_corrected_article_score_contract_v4.csv
application/config/joint_qdesn_shared_backbone_article_confirmation_contract_v2.csv
application/config/joint_qdesn_shared_backbone_article_confirmation_contract_v3.csv
application/config/joint_qdesn_shared_backbone_article_confirmation_contract_v4.csv
application/config/joint_qdesn_shared_backbone_article_confirmation_host_profiles_v1.csv
application/scripts/README.md
application/scripts/audit_joint_qdesn_shared_backbone_article_mcmc_resume.R
application/scripts/finalize_joint_qdesn_shared_backbone_article_score_packet.R
application/scripts/launch_joint_qdesn_corrected_article_comparison.sh
application/scripts/launch_joint_qdesn_corrected_article_comparison_muscat.sh
application/scripts/launch_joint_qdesn_corrected_article_comparison_muscat_11core.sh
application/scripts/run_joint_qdesn_shared_backbone_article_vb_worker.R
application/tests/README.md
application/tests/run_tests.R
application/tests/test_joint_qdesn_corrected_article_comparison_contract.R
application/tests/test_joint_qdesn_corrected_article_comparison_muscat_contract.R
application/tests/test_joint_qdesn_corrected_article_comparison_muscat_shared_contract.R
application/tests/test_joint_qdesn_shared_backbone_article_confirmation.R
application/tests/test_joint_qvp_precision_draw_repair.R
docs/implementation_notes/joint_qdesn_corrected_article_comparison_jerez_handoff_20260909.md
docs/implementation_notes/joint_qdesn_corrected_article_comparison_muscat_11core_20260909.md
docs/implementation_notes/joint_qdesn_corrected_article_comparison_muscat_25core_20260909.md
docs/implementation_notes/joint_qdesn_shared_backbone_article_confirmation.md
docs/implementation_notes/joint_qdesn_corrected_article_score_closeout_handoff_20260912.md
```

## Article-safe candidate inputs

The integration coordinator may stage, but must first review, these ignored
CSV files:

```text
score_packet/posterior_dgp_integrated_acrps_summary.csv
score_packet/scenario_winner_summary.csv
score_packet/joint_independent_contrast_summary.csv
score_packet/forecast_metric_summary.csv
score_packet/oracle_recovery_summary.csv
score_packet/crossing_and_adjustment_summary.csv
score_packet/phase181_reconciliation.csv
```

No TeX table, figure, manuscript text, bibliography, `main.pdf`, or supplement
was generated or changed. The article pass must headline DGP-integrated aCRPS,
show the canonical action and 95 percent score interval, retain raw and contract
crossings, and describe fit/forecast MAE or RMSE only as oracle recovery
diagnostics. It must not claim decisive joint superiority.

## Runtime exclusions

Keep all of the following out of Git and article projection:

```text
application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909/
local_trackers/
/tmp/test_joint_qdesn_*_20260912.log
```

Do not mix this packet with historical Phase181/Jerez-v1 results or Phase182
dense-grid outputs. Do not delete the ignored runtime until the coordinator has
copied or retained it and independently verified `transfer_inventory.csv`.

## Recommended coordinator order

1. Fetch the dedicated branch and verify clean upstream equality.
2. Create a fresh integration worktree from current `origin/main`; do not merge
   from this scientific worktree.
3. Review or cherry-pick the 10 lane commits in chronological order, resolving
   against the 24 main-only commits without changing the frozen v4 contract.
4. Run the six focused tests above plus the combined repository test suite.
5. Transfer or retain the ignored runtime and reverify all 2,970 inventory
   entries before using any score CSV.
6. Review the posterior-versus-canonical `laplace_bridge` disagreement, all
   interval overlap, 10 score-functional reviews, and scalar mixing caveats.
7. Build article-safe TeX and figures in the integration lane from the seven
   candidate CSVs; do not copy runtime model objects into Git.
8. Compile `main.tex` and the supplement, verify article manifests and visible
   score labels, then let the coordinator alone merge `main` and publish the
   article-only Overleaf projection.

## Remaining risk

The packet is complete and reproducible, but it does not establish the desired
predictive dominance of joint models. Dense-grid Phase182 may strengthen the
crossing demonstration, but it is a separate estimand and cannot repair or
replace these seven-level predictive comparisons. Any future calibration must
be a separately frozen, case-specific campaign and must not rewrite this
authority.

`READY_FOR_INTEGRATION`
