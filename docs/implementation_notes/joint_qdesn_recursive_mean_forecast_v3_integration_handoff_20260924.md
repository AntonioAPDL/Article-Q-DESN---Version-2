# JOINT recursive mean-design forecast v3 integration handoff

Date: 2026-09-24

Status: READY_FOR_INTEGRATION

## Lane identity

- Lane: JOINT recursive posterior-mean state forecast reconstruction.
- Transcript: the JOINT validation Codex chat that produced the
  `work/joint-qdesn-recursive-mean-forecast-jerez-20260924` lane.
- Muscat worktree:
  `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_recursive_mean_forecast_jerez_20260924`
- Jerez execution worktree: the same absolute path on host `jerez`.
- Branch/upstream:
  `work/joint-qdesn-recursive-mean-forecast-jerez-20260924` /
  `origin/work/joint-qdesn-recursive-mean-forecast-jerez-20260924`.
- Pre-closeout HEAD: `5759129c1e25811ee2e091dc2a9ca065b2d05848`.
- Base and current `origin/main` at closeout:
  `757522db0f85815244370ec92a194de132268883`.
- Both worktrees were clean and the branch was `0` ahead / `0` behind its
  upstream before this handoff update.

## Unique commits before this handoff

1. `cc3aefe` Add recursive mean-design JOINT forecast audit.
2. `861d35e` Fix recursive forecast CLI gates.
3. `aa41eb4` Fix recursive JOINT state integration audit.
4. `872ddab` Preserve recursive forecast affinity provenance.
5. `42a629a` Fix recursive MCMC draw cardinality.
6. `5759129` Record recursive forecast v2 closeout.

## Scientific contract

This lane does not refit or retune a model. It reforecasts the frozen
corrected-v4 VB and MCMC fits under the advisor-requested conditional design:

1. Recursively simulate future responses and reservoir states from posterior
   quantile readouts.
2. Average the resulting complete readout design over state paths.
3. Hold that one posterior-mean recursive design fixed.
4. Apply posterior readout/intercept draws to that fixed design.
5. Compute posterior DGP-integrated finite-grid aCRPS summaries and intervals.

Thus score intervals include readout uncertainty but exclude recursive
future-input/state-path uncertainty. VB intervals remain partial because the
retained VB objects do not include intercept covariance. Independent models
use the frozen deterministic product-posterior coupling rule.

## Root corrections

- State integration extends when either the standardized RMS gate or the
  canonical half-score gate fails.
- MCMC half samples alternate within each chain instead of comparing
  chain-major storage blocks.
- Per-tier diagnostics persist outside disposable temporary directories.
- AL and exAL source cardinalities are explicit: 750 and 1,500 retained draws
  per chain, respectively.
- Full state rescue uses all draws available for that likelihood family.
- Final MCMC score summaries always use exactly 750 draws per chain, for 3,750
  total draws in every cell.

## Frozen execution evidence

- Run tag: `joint_qdesn_recursive_mean_forecast_v3_jerez_20260924`.
- Runtime root:
  `application/cache/joint_qdesn_recursive_mean_forecast_v3_jerez_20260924`.
- Host/affinity: Jerez, eight distinct physical cores, logical CPUs `24-31`.
- Frozen contract SHA-256:
  `fda15e5db5684f234506567e7c2578f23ca79ce93ef059fe686bdaafee08719a`.
- Source inventory SHA-256:
  `e4b98fe89a8a0c2323f8205c1abef608ff733bc5ec323ea6372198caca02191d`.
- Completion: 16/16 primary oracle shards, 8/8 banks, 32/32 VB cells,
  32/32 MCMC cells, 64/64 total cells, zero failures.
- Score cardinality: 32 MCMC cells at 3,750 draws and 32 VB cells at 4,000
  draws; all MCMC cells have five equally represented chains.
- Manifests: 64/64 cell manifests verified; 10/10 final-packet artifacts
  verified.
- Scientific gates: 64/64 finite scores, 64/64 RMS passes, 64/64 half-score
  passes, zero posterior or canonical contract crossings.
- State tiers: 63 initial; one extension; zero full-posterior rescues.
- Runtime storage: 654,264,431 bytes; final packet 106,353 bytes.
- Transfer status: the complete v3 runtime was copied from Jerez to the
  Muscat worktree on 2026-09-24. A checksum-mode `rsync` dry run reported no
  differences, and Muscat independently reverified all 10 final-packet files
  against `artifact_manifest.csv`.

Key hashes:

| Artifact | SHA-256 |
|---|---|
| Preflight manifest | `639ee92bb76cf9da9592d837db6c15c799a74659adbc568c6bc8385463e93b19` |
| Source verification | `69bb38b5e112bfbf6299a8d0aecfd76f9b0d1446cc701e908b67e0cc2b192c67` |
| Source cardinality audit | `80623505e898b77b18b48f86d81ae07e2c694ad22e7225ce022fae09e6c37597` |
| Final artifact manifest | `319efab8ec1783bd1ba619a21f15abc627d4591195ffa1b52e218daa5b9ca330` |
| Manifest verification | `dc2409b358b9a9346aed0344f4c5ec2e90166d575a1eb79921f959efbb97f45a` |
| Final health summary | `2edc5693ed5164c2f4d9c399d846484dfc78735a4e04ed515ea204495a4d0f39` |
| Forecast score summary | `4818cf45ba17f0ff949f97b630c1aae23162e04d78dec907742ef82d7f20ed93` |
| Posterior contrasts | `86b443d67cf91b9c9ae4ccb694952099f34a37d0a2cb73c0d23c5efda85a4dd4` |
| Scenario winners | `1aa07ea1c98f6536c817f1236f4a7f08e2bb691b9242749a4acb278cc01ee3cd` |
| Stability tiers | `fb1d06ceaadcce87f90253e1531d1303a38e0da67a42fc30658c69483d2086bb` |

## Tests and checks

The following passed on Muscat and Jerez under pinned R 4.6.0:

- `test_joint_qdesn_recursive_mean_design.R`
- `test_joint_qdesn_recursive_dgp_oracle.R`
- `test_joint_qdesn_recursive_mean_score_packet.R`
- `test_joint_qdesn_corrected_article_comparison_muscat_contract.R`
- `test_joint_qdesn_post_phase178_dgp_integrated_acrps.R`
- launcher `bash -n`
- `git diff --check`

Post-run checks also passed the complete-runtime checker, all eight final
health gates, all 160 source cardinality rows, all 64 cell manifests, all
score-draw cardinalities, and the final manifest verification.

## Scientific result and cautions

The root software defect is fixed. Worker 39 demonstrates the intended
recovery: initial half-score difference `0.007340`, automatic 2,000-path
extension, final difference `0.000611`, and successful completion.

The new recursive-mean packet does not yield uniformly narrower MCMC score
intervals than corrected-v4: 4/32 are narrower and the median width ratio is
`1.207`. This is not a like-for-like state-uncertainty ablation. Corrected-v4
uses the fixed validation design; v3 uses a recursive posterior-mean design.
All v3 score draws condition on one design, so recursive state uncertainty is
not present in the reported interval. Remaining width is attributable to
readout/intercept posterior uncertainty evaluated at the recursive design.

Score-functional mixing is review-level for a few joint cells: maximum MCMC
score rank R-hat is `1.1188`, minimum bulk ESS is `33.6`, and minimum tail ESS
is `140.2`. These do not invalidate the completed reconstruction, but they
block an automatic article replacement or a claim that interval-width concerns
have been resolved.

## Integration surface

The branch changes 25 tracked files after this handoff commit: four R-surface
files (three modules and one README), four configuration files (three
versioned contracts and one README), eight script-surface files (seven scripts
and one README), five test-surface files (three focused tests, the test runner,
and one README), and four planning/closeout documents including this handoff.
Use `git diff --name-status origin/main...HEAD` after the handoff commit for
the authoritative list.

Article-safe files to publish now: none. The final CSV packet is candidate
scientific evidence for review, not an article replacement.

Runtime/generated paths that must remain excluded from Git:

- `application/cache/source/joint_qdesn_corrected_article_comparison_muscat_11core_20260909`
- `application/cache/joint_qdesn_recursive_mean_forecast_jerez_20260924`
- `application/cache/joint_qdesn_recursive_mean_forecast_v2_jerez_20260924`
- `application/cache/joint_qdesn_recursive_mean_forecast_v3_jerez_20260924`

The Jerez source plus v1/v2/v3 runtimes occupy about 2.35 GB. Retain them until
integration verifies transfer hashes. After that review, v1 and v2 are
removable diagnostic runtimes; keep their tracked closeout records and the v3
final packet or a hash-verified transfer.

## Recommended integration order

1. Merge this dedicated lane into the then-current `origin/main`; the branch
   is based directly on the current main recorded above.
2. Retain the hash-verified Muscat copy of the complete ignored v3 runtime
   through integration review; no additional Jerez transfer is required.
3. Re-run the five focused tests and complete-runtime checker in the
   integration worktree.
4. Review the wide joint-cell score intervals and score-functional mixing.
5. Decide article wording and assets in a separate article-safe lane. Do not
   overwrite the existing article authority merely because v3 finalized.
6. Only after integration is accepted, archive or remove v1/v2 heavy runtime
   objects according to the storage note above.

READY_FOR_INTEGRATION
