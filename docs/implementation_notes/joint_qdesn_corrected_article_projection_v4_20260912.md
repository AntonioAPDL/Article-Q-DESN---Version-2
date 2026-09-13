# Corrected JOINT article projection v4

## Purpose

This projection replaces the complete Phase181 article comparison with the
corrected seven-level JOINT packet. Replacement is required because all five
chains in each corrected model cell share fixed prior hyperparameters and one
posterior target. The historical chains did not satisfy that condition. No
cell is selected according to whether its corrected numerical result improves.

## Frozen authority

- Source lane: `work/joint-qdesn-corrected-article-comparison-muscat-11core-20260909`
- Source lane HEAD: `ca1cffa155cc5a3491f2492eeef83a31d30044bf`
- Execution-code commit: `b9af9ef4a7da8b507827dce9cd0d6d0b2a53ab24`
- Score-contract SHA-256: `d2d118f1b1b1e6feedcd4d552c20ad6d95902d1be833f5af257d7b61f0289ad1`
- Transfer-inventory SHA-256: `e4b98fe89a8a0c2323f8205c1abef608ff733bc5ec323ea6372198caca02191d`
- Runtime inventory: 2,970 files, 387,506,202 bytes, zero verification failures

The builder verifies the frozen score-packet manifest and stages exact copies
of the seven authorized summary CSVs. It does not read model objects or copy
posterior draws into Git.

## Scientific projection

The main article reports posterior DGP-integrated aCRPS, equal-tailed 95%
intervals, canonical-action scores, and canonical raw/reported crossings. The
supplement contains the complete 32-cell score table, 16 paired
joint-minus-independent contrasts, crossing totals, secondary realized scores,
and fit/forecast oracle quantile-path recovery diagnostics. MAE and RMSE are
identified as oracle recovery diagnostics rather than scores against realized
observations.

The retained interpretation is deliberately limited:

- independent exQDESN has the lowest posterior mean in seven settings;
- joint exQDESN has the lowest posterior mean only for the Laplace setting;
- the canonical action selects independent exQDESN in all eight settings;
- all winner/runner-up marginal intervals overlap;
- four paired intervals favor independent estimation and twelve include zero;
- no paired interval favors joint estimation;
- joint exQDESN has zero canonical raw crossings in every setting, so the
  comparison shows a coherence/performance tradeoff rather than decisive joint
  predictive superiority.

The seven-level packet remains separate from the Phase182 dense-grid analysis.

## Reproduction

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/build_joint_qdesn_corrected_article_projection_v4.R

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/check_joint_qdesn_corrected_article_projection_v4.R
```

The checker verifies staged-input hashes, row counts, winners, contrasts,
diagnostic counts, crossing totals, active manuscript wiring, the article-only
file list, output hashes, one-page PDF structure, vector content, and visible
metric labels.

The independent-simulation v14 manifest hashes for `main.tex`,
`qdesn-supplement.tex`, and `overleaf/article_files.txt` are refreshed after
the JOINT projection is wired. Its numerical inputs, figures, wrappers, and
scientific results are unchanged.
