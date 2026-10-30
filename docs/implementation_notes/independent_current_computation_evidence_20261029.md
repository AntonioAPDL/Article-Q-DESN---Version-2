# Current independent-study computation evidence

## Scope and scientific authority

This is a metadata-only audit of the current independent-study publication
inputs. It changes no fit, forecast, score, selection, or uncertainty rule.
The source registry is derived from the active fitting table and the active
300/500-target forecast table, not from all historical campaign candidates.
There are 90 distinct inference/model/level/family/source identities:
54 Q-DESN identities (36 MCMC and 18 VB) and 36 dynamic-baseline identities.
The same source identity may serve fitting and forecast roles, but the
unchanged fitting results and subsequently reconstructed forecasts have
separate execution receipts. They must not be described as an identical
posterior realization merely because their source labels match.

## Reproduce the inventory

From the article repository, with R 4.6.0 and jsonlite:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/audit_independent_computation_evidence_20261029.R \
  --validation-root \
  /data/jaguir26/local/src/Article-Q-DESN/.worktrees/ind_qdesn_forecast_scope_300_500_20261015 \
  --historical-bundle \
  /data/jaguir26/local/artifacts/independent_qdesn_validation/metric_intervals_v10_evidence_bundle_v1_20260824
```

The script reads small contracts, manifests, and status receipts only. It
does not load model objects, call a sampler or optimizer, reconstruct
forecasts, or connect to another host. These retained source locations are
reproducibility inputs, not article-upload files.

Outputs:

- `tables/independent_current_computation_sources_20261029.csv`: all 90 active
  source identities, active fitting/forecast roles, and receipt coverage.
- `tables/independent_current_computation_receipts_20261029.csv`: 276
  source-specific metadata receipts, each with configuration and status hashes.
- `tables/independent_current_computation_inputs_20261029.csv`: hashes of the
  active article inputs, audit script, and source-inventory manifests.

The audit authenticates 144 historical fitting-workflow receipts and 132
forecast-reconstruction receipts. The former cover all 72 active fitting
identities; the latter cover exactly 44 selected MCMC forecast identities,
with three chains each. No selected fitting-source receipt is missing.
The historical exDQLM rolling-state correction is authenticated through its
own promoted job manifest, not substituted with the earlier evidence bundle.
The script rejects changed configuration hashes and incomplete reconstruction
contracts/retention receipts. Status hashes from the old bundle are checked
against their frozen manifest; later status hashes are recorded separately,
without claiming that an earlier manifest had individually pinned them.

## Settings and their interpretation

The selected MCMC contracts request `n_burn=5000`, `n_mcmc=20000`, and
`thin=1`. These are not 20,000 total iterations. In the executed Q-DESN
source `c72e19f3`, `R/exal_mcmc_fit.R` defines `n_keep=n_mcmc` and
`n_total=n_burn+n_keep*thin`. The dynamic sampler likewise defines
`I=n.mcmc+n.burn`; the retained private exdqlm 1.1.1 implementation has
the same budget convention. Thus these requests mean 5,000 burn-in followed
by 20,000 native sampling iterations, 25,000 total when thinning is one.

The published forecast-score calculations use deterministic subsets of
4,000 draws per chain, except the Gaussian 0.05 AL Q-DESN forecasts, which
use 1,000 per chain. Export subsetting is not sampler thinning. Three-chain
pooling gives 12,000 or 3,000 criterion evaluations, respectively. Each
selected VB fitting configuration specifies a 300-iteration maximum; that
limit alone is not a report of its actual stopping iteration or accuracy.

The reconstruction contracts identify Q-DESN/DQLM runtime version 1.0.0 and
the refreshed exDQLM runtime 1.1.1. Historical receipts do not all retain a
runtime version, and the CSV marks that absence rather than filling it with
a contemporary package version. This inventory does not resolve missing
original execution requests or prove that every inherited coefficient-prior
implementation used the same release. It is not a new audit of sampler
correctness or all original prior requests.

## Timing: what is available and what remains open

Elapsed seconds are retained per source receipt. Their scopes differ:

| Evidence group | Receipts | Recorded elapsed-time scope |
|---|---:|---|
| Historical fitting workflows | 144 | Fit, forecasting, and metric workflow |
| Reconstructed forecasting workflows | 121 | Fit, forecasting, and export workflow |
| Cached forecast recovery | 11 | Rescoring/export only; no fit or forecast call |

The rescoring receipts must never be included in a fitting-time summary.
None of these workflow times is labeled fit-only, and no medians or
VB/MCMC speedups are constructed from them. Hardware/affinity records are
not uniformly complete across the historical workflows. Moreover, the
selected DESN specifications can differ by criterion and inference method,
so pairing these times would not give a controlled comparison of posterior
approximations. A matched VB/MCMC fit-only timing comparison remains open.

The current multiquantile score cardinality and five-chain settings are
available in its published protocol/cardinality tables. Its current exact
elapsed fit times were not authenticated by this independent-study audit.
The legacy 144-fit timing table is not substituted for either current study.

## One-step multiquantile scoring boundary

No new one-step scores were computed. On Muscat the inspected current
scientific worktrees retain compact manifests, plans, and aggregate score
packets but not the complete current design/context, posterior-draw, and
oracle-bank inputs for all 32 MCMC comparisons. Aggregate 990-pair scores
cannot recover their 33-first-lead posterior score distributions. The
scientific owner must supply an authentic current evidence inventory before
a complete scoring-only analysis can be frozen. The later Laplace
replacement requires its actual context, draw/coupling convention and oracle
inputs rather than an older campaign's generic filenames or draw counts.

## Historical presentation-checker repair

The inherited v14 checker failed on unmodified article authority because
it compared a historical generator receipt with the current generator.
The frozen pro-review receipt pins builder SHA-256
`86f72a80acf33241ecfc2f043177e7d4c9b2dc1913356502988091b33f1defb9`.
Commit `fe4235d700c007c1255aedddac530ae8539181e8` intentionally changed
that builder to delegate independent reporting to the 300/500-target
authority. Its current SHA-256 is
`98cdbed43661b24a9b4d488efaabcf58b2cfac66bac5bf4202e7de2d2431613f`.
The style digest, all 13 historical derivative digests, and all historical
presentation-source digests remained unchanged. The same checker also
continued to require the retired 1,000-target wrapper in the live main paper.

The bounded repair separates two checks rather than replacing either:

1. Immutable historical presentation source/routing is verified at
   `282206caf176d5e8e13857dd1070f2fac02586fc`. The oracle-v14 manifest is
   verified at `0b747f401e6fbaa7d231adaa8576a9814a7d861d`, whose manuscript
   and publication-list digests exactly match that manifest. Both commits
   must be ancestors of `origin/main` and the checked-out `HEAD`.
2. Actual current reporting is verified independently against the approved
   300/500 authority introduced by `fe4235d700c007c1255aedddac530ae8539181e8`,
   with immutable numerical/policy pins, all current source/output hashes,
   origin/lead counts, effective TeX routing, and article-only publication
   membership. The archived wrappers cannot satisfy this live-routing check.

`scripts/independent_reporting_authority_checks.R` implements that
read-only distinction. Historical lookup is restricted to the three explicit
commits, never a search for any matching Git object. Only the named historical
generator/editorial paths may resolve from their fixed ancestor. Scientific
CSVs and derivative outputs must still match the current file bytes; a
historical copy cannot excuse a changed numerical or figure artifact.
Neither historical manifest nor historical output is updated or regenerated.
The standalone current statistical-language/source-invariance guards remain
unchanged by this repair.

`application/tests/test_independent_reporting_authority_checks.R` rejects
unapproved references, incorrect generator pins, changed historical figure
or numerical pins, stale main forecast routing, and moving forecast MAE back
to the main article. All mutations are in-memory strings or expected hashes.
