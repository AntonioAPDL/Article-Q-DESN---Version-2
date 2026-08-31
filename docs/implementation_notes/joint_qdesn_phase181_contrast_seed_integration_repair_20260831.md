# Joint Q-DESN Phase181 contrast-seed integration repair

## Scope

The integration audit found that the Phase180 score specification recorded
`contrast_pairing_seed = 180901001`, while the joint-minus-independent contrast
function derived its seeds from `primary_pairing_seed + 90000 + comparison
index`. The frozen Phase181 contrast draws therefore used seeds
180990102--180990117 instead of the recorded contrast-seed sequence.

This discrepancy affected only the within-chain permutation used to pair
already-computed scalar posterior score draws. It did not affect MCMC draws,
model specifications, per-model score distributions, source selection,
quantile crossings, or forecast-path recovery diagnostics.

## Repair

The contrast function now uses

```text
(contrast_pairing_seed %||% (primary_pairing_seed + 90000)) + comparison index
```

The fallback preserves compatibility with earlier score specifications that do
not define a separate contrast seed. Phase181 finalization also verifies the
complete sequence of 16 expected seeds.

The retained 256,000 posterior score draws were reused to recompute the scalar
contrasts. No model was refit and no MCMC chain was rerun. The corrected seeds
are 180901002--180901017.

## Scientific invariance

- All 16 corrected equal-tailed 95% contrast intervals include zero.
- Contrast means are invariant to numerical precision because the repair
  changes only the within-chain permutation.
- The 32 marginal posterior score summaries and all eight numerical minima are
  unchanged.
- The 13 selected Phase181 sources are unchanged.
- Posterior-mean crossing totals remain 1, 25, 0, and 0 for joint AL,
  independent AL, joint exAL, and independent exAL, respectively.
- The scientific interpretation remains descriptive.

## Provenance

- Frozen source branch tip:
  `6655408c3f3829075dc166affe802f4d1b6930df`
- Main authority at integration start:
  `394558264d791816ced71742738d6f988a45780f`
- Superseded contrast-summary SHA-256:
  `d84ec89dab227176500ec642ecb6259fa5554809c3f6995e96e0c8a666c8a19c`
- Corrected contrast-summary SHA-256:
  `4dfe83932d90d1a9a62b7f822c0d377c7ef6b18612a252080630311ecaaf63af`
- Superseded packet-manifest SHA-256:
  `e392c717c060636ec8ebadb51842b7abfe3fb531b99de3659cee8875d26d0292`
- Corrected packet-manifest SHA-256:
  `a96200a0dfdb0ad3506f99e737cce75b5f71d68c662a2ee1484376d44ebef624`
- Superseded article-staging-manifest SHA-256:
  `96a54710059002fa1f23aa86b515d6b2f9fc60505888d8f8eb7b79bc7578a69e`
- Corrected article-staging-manifest SHA-256:
  `d17d028c0c06de5b8b6a7382b7945cde87f721074cf82737f7afc642f93f89c6`

The packet and article-staging directories remain ignored runtime evidence.
Only the corrected article-safe sources, deterministic projection code, tests,
and this integration note enter Git.

## Verification

```bash
Rscript application/tests/test_joint_qdesn_phase180_balanced_dgp_score_packet.R
Rscript application/tests/test_joint_qdesn_phase181_score_stability_extension.R
Rscript scripts/check_joint_qdesn_phase181_article_projection.R .
```

The real-packet test verifies the exact 16-seed sequence, and the article
projection check verifies 32 finite scenario--model rows, 16 intervals
containing zero, the reported crossing summaries, and all tracked asset hashes.
