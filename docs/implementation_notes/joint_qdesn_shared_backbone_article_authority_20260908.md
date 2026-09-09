# JOINT shared-backbone article authority

Date: 2026-09-08

## Decision

The completed Jerez shared-backbone article-fixture analysis is the current
JOINT article authority. Its complete 32-cell result replaces the Phase181
article presentation. No cell is selected according to whether it improves on
Phase181.

This decision concerns the seven-level article-fixture comparison. It does not
include or supersede the separate Phase182 19-level dense-grid crossing study,
which remains an active scientific lane pending its own frozen handoff.

## Two distinct JOINT calculations

| Calculation | Scope | State on 2026-09-08 | Article treatment |
| --- | --- | --- | --- |
| Phase182 dense-grid crossing analysis | Nineteen-level MCMC crossing evaluation | Finalization remains active; no frozen integration handoff | Not integrated or reported |
| Jerez shared-backbone article confirmation | Seven levels, eight mechanisms, four model classes, 136 VB components, and 160 MCMC chains | Complete, transferred, manifest-verified, and frozen | Current provisional article authority |

The Jerez calculation uses one selected DESN/RHS specification per simulation
mechanism and holds it common across the four competing model classes. The
selection uses separate source realizations; the article fixture is not used
to choose the specification.

## Initialization sequence

For every mechanism, the frozen calculation applies the following sequence:

1. Gaussian ridge initializes Gaussian RHS--VB.
2. Compatible Gaussian RHS estimates initialize the independent AL regression
   at the median.
3. Independent AL fits continue from the median toward each tail, using the
   nearest completed level on the corresponding side.
4. Each independent exAL fit is initialized from the independent AL fit at the
   same probability level.
5. The complete independent AL and exAL grids initialize the corresponding
   joint fits.
6. Each completed VB fit initializes MCMC for the same statistical model, with
   independently seeded and dispersed chain starts.

These operations transfer initial values only. They do not constrain the
destination estimate, impose dependence among independent quantile
regressions, or change a model's likelihood, prior, or posterior target.

## Frozen numerical evidence

Source execution commit:

```text
fd48499308d613341274717b53643bece977fb39
```

Transferred runtime:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_article_confirmation_jerez_review_20260908/application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907
```

Score-contract SHA-256:

```text
473c0754c9a1c9a873c4db3b7e61912b57b18c1cac1e146dfd16079185f70600
```

The complete result contains 32 finite posterior score cells and 16 paired
joint-minus-independent contrasts. Independent exQDESN has the lowest
posterior mean in seven mechanisms; joint exQDESN is lowest for the Laplace
mechanism. Winner and runner-up marginal intervals overlap in every mechanism.
Five joint-minus-independent intervals favor independent estimation and the
other eleven include zero.

Posterior-mean raw forecast crossings, summed over the eight mechanisms, are:

| Model | Raw crossings | After rearrangement |
| --- | ---: | ---: |
| Joint Q--DESN, AL | 1,426 | 0 |
| Independent Q--DESN, AL | 4,705 | 0 |
| Joint exQDESN, exAL | 0 | 0 |
| Independent exQDESN, exAL | 281 | 0 |

Posterior-score diagnostics have 21 pass and 11 review assessments. All 16
exAL scale--asymmetry assessments remain at review level. Precision
stabilization was invoked in eight of the 96 exAL chains for 34 coefficient
updates, with maximum relative diagonal perturbation `1e-12`; all affected
chains passed the numerical gates.

## Article projection

The reproducible builder is:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/build_joint_qdesn_shared_backbone_article_projection.R \
  --runtime-root \
  /data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_article_confirmation_jerez_review_20260908/application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907 \
  --fit-cores 4
```

It verifies the frozen packet, reconstructs draw-wise fit RMSE with the same
chain-balanced coupling used for scoring, writes article-safe summaries and
tables, creates the fit and forecast interval figures, and records hashes in:

```text
tables/joint_qdesn_shared_backbone_article_asset_manifest.csv
```

The checker is:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/check_joint_qdesn_shared_backbone_article_projection.R
```

Runtime draws, fitted objects, designs, logs, and caches remain ignored and are
not part of the article projection.

The combined repository harness exposed a schema mismatch in a legacy
synthetic-artifact writer: newer AL summaries contain optional RHS iteration
diagnostics that the exAL summary does not contain. The writer now binds those
rows by column name and fills unavailable optional fields with missing values.
This changes only the diagnostic CSV schema; it does not change either fit or
any reported article result.

## Deferred RHS confirmation

The frozen Jerez runtime was generated with the then-current RHS global-scale
conditional, whose shape term used `p/2`. The repository later corrected that
term to `(p+1)/2`. Stored results have not been altered. The article therefore
identifies this projection as provisional, and the registered confirmation
rerun remains required before final archival release:

```text
docs/implementation_notes/joint_qvp_rhs_deferred_rerun_register_20260908.md
```

No Phase182 process, worktree, cache, or result is modified by this projection.
