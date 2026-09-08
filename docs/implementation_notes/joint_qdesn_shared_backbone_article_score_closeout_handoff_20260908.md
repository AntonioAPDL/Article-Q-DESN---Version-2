# JOINT Shared-Backbone Article Score Closeout Handoff

Date: 2026-09-08

Status: `READY_FOR_MUSCAT_TRANSFER_AND_INTEGRATION_REVIEW`

Lane:
`work/joint-qdesn-article-confirmation-jerez-20260907`

Worktree:
`/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_article_confirmation_jerez_20260907`

Runtime:
`application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907`

Score packet:
`application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907/score_packet`

Execution commit:
`66bd9c6feff6a03881fcf3c0f0351e00f69022f4`

## Health Check

| Gate | Expected | Observed | Failed | Status | Evidence |
| --- | ---: | ---: | ---: | --- | --- |
| Source jobs | 7,560 | 7,560 | 0 | pass | `source_final_health.csv` |
| VB components | 136 | 136 | 0 | pass | `vb_health_summary.csv` |
| Compact initializers | 32 | 32 | 0 | pass | `vb_initializer_manifest.csv` |
| MCMC workers | 160 | 160 | 0 | pass | `mcmc_health_summary.csv` |
| Worker manifests | 160 | 160 | 0 | pass | `mcmc_worker_manifest_verification.csv` |
| Model cells | 32 | 32 | 0 | pass | `model_cell_plan.csv` |
| Score rows | 32 | 32 | 0 | pass | `score_packet/posterior_dgp_integrated_acrps_summary.csv` |
| Contrasts | 16 | 16 | 0 | pass | `score_packet/joint_independent_contrast_summary.csv` |
| Scenario winners | 8 | 8 | 0 | pass | `score_packet/scenario_winner_summary.csv` |
| Contract crossings | 0 | 0 | 0 | pass | `score_packet/crossing_and_adjustment_summary.csv` |
| Packet manifest | 26 | 26 | 0 | pass | `score_packet/artifact_manifest_verification.csv` |
| Transfer inventory | 2,867 files | 2,867 files | 0 | pass | `score_packet/transfer_inventory.csv` |

Remaining computational runs: 0 VB, 0 MCMC, 0 score cells. The only remaining
work is Muscat transfer and integration review.

## Frozen Score Contract

Contract file:
`application/config/joint_qdesn_shared_backbone_article_score_contract_v1.csv`

Packet copy hash:
`473c0754c9a1c9a873c4db3b7e61912b57b18c1cac1e146dfd16079185f70600`

Primary estimand is known-DGP expected finite-grid quantile score,
`dgp_integrated_acrps`. The seven-level tau grid is
`0.05,0.10,0.25,0.50,0.75,0.90,0.95`; trapezoidal weights are
`0.025,0.100,0.200,0.250,0.200,0.100,0.025`; each ordinate is twice quantile
check loss; weights are not renormalized beyond the observed tau range.
Forecast rows are exactly `design$score_local`. The canonical action is the
pooled posterior-mean parameter path followed by the rowwise monotone contract.
Independent models use deterministic within-chain seeded per-tau permutations;
joint models preserve retained-draw identity across tau.

## Score Winners

| Scenario | Descriptive winner | Mean | Runner-up | Delta |
| --- | --- | ---: | --- | ---: |
| asymmetric_laplace_tail | independent exAL | 0.333854 | independent AL | -0.098834 |
| gaussian_mixture_bridge | independent exAL | 0.394926 | independent AL | -0.006107 |
| laplace_bridge | joint exAL | 0.335035 | independent exAL | -0.001161 |
| nonlinear_reservoir_friendly | independent exAL | 0.430870 | independent AL | -0.002359 |
| normal_bridge | independent exAL | 0.336240 | joint exAL | -0.011212 |
| persistent_heavy_tail | independent exAL | 0.372821 | independent AL | -0.003647 |
| regime_shift | independent exAL | 0.437300 | independent AL | -0.003059 |
| student_t_location_scale | independent exAL | 0.354538 | independent AL | -0.011926 |

All winner-versus-runner-up 95 percent intervals overlap, so these are
descriptive numerical minima, not statistically confirmed wins.

## Joint Minus Independent Contrasts

Negative values favor joint; positive values favor independent.

| Scenario | Variant | Mean | 95% interval | P(joint lower) | Evidence |
| --- | --- | ---: | --- | ---: | --- |
| asymmetric_laplace_tail | AL | 1.028963 | [0.201933, 1.915583] | 0.003000 | favors independent |
| asymmetric_laplace_tail | exAL | 0.444819 | [0.029947, 1.131743] | 0.002000 | favors independent |
| gaussian_mixture_bridge | AL | 0.312756 | [0.078927, 0.624051] | 0.000333 | favors independent |
| gaussian_mixture_bridge | exAL | 0.056824 | [-0.005165, 0.217486] | 0.065778 | overlap |
| laplace_bridge | AL | 0.046961 | [-0.006023, 0.112495] | 0.043333 | overlap |
| laplace_bridge | exAL | -0.001161 | [-0.022487, 0.021982] | 0.566889 | overlap, descriptive joint edge |
| nonlinear_reservoir_friendly | AL | 0.045633 | [0.015163, 0.095766] | 0.000000 | favors independent |
| nonlinear_reservoir_friendly | exAL | 0.021134 | [0.000860, 0.057321] | 0.017778 | favors independent |
| normal_bridge | AL | 0.005953 | [-0.053417, 0.071365] | 0.433000 | overlap |
| normal_bridge | exAL | 0.011212 | [-0.039204, 0.083461] | 0.393333 | overlap |
| persistent_heavy_tail | AL | 0.022792 | [-0.020179, 0.125648] | 0.266667 | overlap |
| persistent_heavy_tail | exAL | 0.016280 | [-0.016246, 0.072991] | 0.189778 | overlap |
| regime_shift | AL | 0.003158 | [-0.030142, 0.042085] | 0.446667 | overlap |
| regime_shift | exAL | 0.007878 | [-0.023373, 0.042342] | 0.290222 | overlap |
| student_t_location_scale | AL | 0.055883 | [-0.034263, 0.323015] | 0.305667 | overlap |
| student_t_location_scale | exAL | 0.019879 | [-0.026716, 0.129678] | 0.344889 | overlap |

Every contrast has zero contract crossings on both sides. Overlapping
intervals mean uncertainty/parity in strength of evidence, not proof of
equality.

## Diagnostics

The qhat reconstruction audit passes for all 160 workers, with maximum fit
path error `8.65974e-15` and maximum validation path error `1.90958e-14`
against tolerance `1e-8`.

Score-functional diagnostics have 21 pass cells and 11 review cells. Coherence
diagnostics have four pass cells and 28 review cells because raw pre-contract
crossings and monotone adjustments remain diagnostic signals. Contract
crossings are zero after the canonical action, so the hard gate passes.

The 16 exAL gamma/sigma diagnostics are all `review_level_retained`.
Precision-repair summaries pass for all 32 cells: 96 workers had repair
enabled, eight workers used at least one repair, 34 precision repairs were
recorded, and maximum relative jitter was `1e-12`.

The Phase181 reconciliation labels all 32 rows `descriptively_comparable`.
The exact reason is that scenario, model family, seven-level tau grid, score
definition, and posterior action align; Jerez uses separately selected
shared-backbone controls and `score_local` rows; tracked Phase181 tables do not
carry article-seed or forecast-row hashes. This lane therefore does not
silently supersede article authority.

## Article Staging

Ignored candidate CSV inputs for later article review are listed in
`score_packet/article_staging_inventory.csv`. They include the 32-cell score
summary, eight-row winner summary, 16-contrast summary, forecast metrics,
oracle recovery diagnostics, crossing diagnostics, and Phase181 reconciliation.

This lane did not modify `main.tex`, `qdesn-supplement.tex`, tracked article
tables, tracked article figures, PriceFM, GloFAS, independent-validation lanes,
or Phase182.

## Transfer

Runtime transfer inventory:
`score_packet/transfer_inventory.csv`

Storage summary:
2,867 files, 470,322,631 bytes, 2,817 required files, 50 optional files.

Inventory hash:
`ad9cb207cc504354cd09e5a892c65553d1f5061691b9064f2d451791b78ed069`

Use `rsync` from a host that can see both endpoints:

```bash
rsync -aH --partial --info=progress2 \
  jerez:/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_article_confirmation_jerez_20260907/application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907/ \
  <MUSCAT_REVIEW_WORKTREE>/application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907/
```

Post-transfer verification command:

```bash
cd <MUSCAT_REVIEW_WORKTREE>/application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907 && \
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'inv <- read.csv("score_packet/transfer_inventory.csv", stringsAsFactors=FALSE, check.names=FALSE); stopifnot(all(file.exists(inv$relative_path))); observed_size <- file.info(inv$relative_path)$size; observed_sha <- unname(tools::sha256sum(inv$relative_path)); bad <- which(observed_size != inv$size_bytes | tolower(observed_sha) != tolower(inv$sha256)); if (length(bad)) { print(inv[bad,]); quit(status=1) }; cat(sprintf("verified %d files, %.0f bytes\n", nrow(inv), sum(inv$size_bytes)))'
```

## Recommended Integration Order

1. Transfer the full ignored Jerez runtime to the Muscat review worktree and
   verify hashes from `score_packet/transfer_inventory.csv`.
2. Merge this dedicated Jerez branch by command-line Git after coordinator
   review; do not merge or rebase it into `main` from this worktree.
3. Keep Phase182 dense-grid crossing evidence separate until Muscat closes that
   lane.
4. In a later integration pass, compare the article-safe candidate CSVs against
   the current Phase181 article authority and decide whether any narrative or
   table promotion is warranted.
5. Publish article assets only through the repository's Git-only article
   snapshot flow after integration review.

## Open Risks

The source VB aggregate remains screening provenance and should not be used for
final model selection. Several scalar score/gamma/sigma diagnostics are
review-level, so article wording should remain cautious. The new packet is
descriptively comparable to Phase181 but not a drop-in article replacement
because the tracked Phase181 tables do not include the hashes required for a
fully matched comparability proof.
