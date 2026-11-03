# Corrected GloFAS issued-window article closeout

## Scope and scientific authority

This revision replaces the issued-window display as one complete seven-family
comparison. It does not refit, retune, screen or select a model using the issued
window. Historical reference-only, discrepancy-only and combined-reference
results are retained separately; future discrepancy-only scores remain
unavailable. No independent-simulation, multiquantile-simulation or electricity
result is replaced.

The sixteen corrected quantile producers completed successfully at source
`fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6`. Both multiquantile fits achieved
three consecutive complete convergence passes. The separately enrolled Gaussian
baselines are reused, not newly fitted. The two legacy workers have another
future-path target and are neither dependencies nor replacements for this packet.

The corrected specification retains a normalized sequential future-reference
distribution from the same likelihood used for the historical gauge record.
Each of the 51 issued members contributes one ordinary likelihood factor.
Historical and future reference observations share their source parameters;
retrospective and issued GloFAS contributions share their own parameters.
Future USGS observations are opened only after the forecast packet is sealed.
Realized future weather is retained and explicitly identified.

The forecast summaries are marginal response quantiles of the retained Gaussian
VB future-path factors. They are not conditional locations evaluated at a mean
future design. Historical fitted curves are mean conditional quantiles and are
labelled separately. Separate probability-level path factors do not imply a
single coherent response distribution across levels.

## Frozen evidence and post-fit execution

| Evidence | Verified identity |
|---|---|
| Producer source | `fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6` |
| Posterior target SHA-256 | `72ef0550393106009b100636e1b11e8c21d4da31e77ed01a3dc2663439dbef03` |
| Score/extraction execution source | `90309792229f98a6ad372fe6072f850f9b12deed` |
| Certified historical-reader source | `916cdea43239f94a5c4e3606683ba9be78f81820` |
| Complete score-manifest SHA-256 | `5c476aeda6d2164658875de22ab393a6b25e7a0e6c4e8c72e85e9a3d2b6267ce` |
| Quantile producers | 16 accepted; no remaining corrected fits |
| Forecast grid | 1,372 rows: 7 families × 28 dates × 7 levels |
| Authentic historical fits | 1,260 rows: 6 families × 30 dates × 7 levels |
| Historical window | 26 November–25 December 2022 |
| Issued window | 26 December 2022–22 January 2023 |
| Issued members | 1,428 rows: 51 members × 28 dates |
| Scoring observations | 28 dates; post-seal access only |

The ignored execution records retain closed ledger snapshots, purpose contracts,
source pins, before/after hashes, resource limits, logs, native terminal receipts
and manifests. They remain outside Git. Execution worktrees stay pinned to their
recorded commits: the truth validator rechecks that source identity. Do not
remove or repurpose them as part of publication.

Post-fit stages use one numerical thread, separately assigned CPUs, bounded
memory and CPU/wall limits. Large model readers run sequentially. Small numerical,
document and presentation checks run separately where resources permit. No remote
scientific job or evidence transfer is required for this closeout.

Successful extraction, assembly, truth access, scoring and fitted-history stages
took approximately 94, 18, 1, 19 and 171 seconds, respectively. These are measured
successful-stage wall times, not total campaign costs. Earlier failed guard
checks and a bounded historical-date diagnostic are preserved; their extra reads
must not be omitted from the execution accounting.

Three post-fit reader defects were corrected without changing a fitted model:

1. Equal calendar dates with integer/double internal storage are compared by
   numeric date value rather than strict storage identity.
2. A genuinely fresh output path may have `Sys.readlink()` equal to `NA`;
   broken links remain rejected.
3. Multiquantile historical readouts may contain conditional Gaussian inner
   blocks. Such blocks are accepted only with a complete, converged outer RHS
   partition certificate and all seven reference/discrepancy RHS states.
   Ordinary independent fits still require their own RHS identity.

The historical reader also compares named JSON pin maps semantically rather
than relying on object-key order. Failure receipts are retained; no check was
weakened to accept incomplete scientific evidence.

## Reproduced results

The primary score is twice check loss integrated over the seven-level grid by
unnormalized trapezoidal weights, averaged across the 28 issued dates, on the
`log1p(flow)` scale. The weights are
`0.075, 0.150, 0.150, 0.150, 0.150, 0.150, 0.075` and sum to 0.9.
An independent literal implementation reproduces the score, all date-specific
scores, 49 empirical-frequency summaries, crossing rates and signed widths.

| Family | Grid aCRPS | Endpoint inclusion | Adjacent crossings / 168 | Inverted endpoint pairs |
|---|---:|---:|---:|---:|
| Raw GloFAS | 1.435977 | 0/28 | 0 | 0 |
| Normal Ridge | 0.843669 | 2/28 | 0 | 0 |
| Normal RHS | 0.946388 | 2/28 | 0 | 0 |
| Q–DESN, AL | 1.505869 | 10/28 | 39 | 8 |
| Q–DESN, exAL | 1.613451 | 3/28 | 46 | 9 |
| MQ–DESN, AL | 1.582252 | 10/28 | 43 | 8 |
| MQ–DESN, exAL | 1.639220 | 2/28 | 44 | 7 |

Gaussian Ridge and RHS reduce aggregate loss by 41.25% and 34.09%, respectively,
but both have severe upper-tail undercoverage. For Ridge, 25 of 28 observations
exceed its 0.95 quantile. All four AL/exAL regressions have greater loss than raw
GloFAS. Multiquantile regularization does not consistently improve ordering here.

The reported outer-endpoint inclusion counts leave inverted bounds uncovered;
an inverted pair is not a valid central interval. Signed widths, crossing
magnitudes and negative inverse-transformed quantiles are retained. There are
12, 9, 10 and 8 negative flow-scale quantiles for independent AL, independent
exAL, MQ–AL and MQ–exAL. No clipping, sorting, projection, smoothing, extra
response noise or credible ribbon is introduced.

Numerical stopping checks do not establish calibration or global optimality of
the variational solution. These adverse findings replace the historical issued
window interpretation rather than being hidden by selective promotion.

## Reproduction and publication

The small public CSVs, figures and TeX derivatives are authenticated by
`tables/glofas_same_family_20261103_article_asset_manifest.csv`. The separate
`tables/glofas_same_family_current_authority.json` records scientific review of
the complete packet. Candidate-generation metadata is deliberately not itself
a grant of publication authority.

The renderer is `scripts/build_glofas_same_family_article_assets.R`; its checker
is `scripts/check_glofas_same_family_article_assets.R`. They accept explicit
manifest pins for the sealed score packet, authentic historical/member extracts,
historical fitted curves, independent metrics and measured convergence records.
They read only those small post-fit inputs, never model objects.

`scripts/glofas_current_article_authority.py` validates committed blobs, exact
asset hashes, all seven displayed rows and effective aliases in both manuscripts.
The corrected alias file is loaded last. Historical display files and their hash
tests remain intact but are not mistaken for current issued-window authority.
The source-tree variant is for isolated tests only; publication validates one
immutable Git commit.

Focused and combined tests, both isolated manuscript builds, recorder dependency
closure, PDF visual inspection and clean source projection are required before
main promotion. Publication then uses the existing guarded command-line Git
integration and article-only Overleaf publisher. The final execution receipt
records tested commits, merge parents, build results and remote readbacks.
No claim of a remote update is made solely from local build success.

### Joined validation and historical checks

The independent metric fixtures pass 80 checks; the asset fixtures pass 61,
including undersized lettering, clipping and text-overlap rejections. The final
four vector plots have embedded fonts, no raster images and minimum effective
lettering of at least 8.30 pt at the specified insertion sizes. The isolated
preliminary builds contain 39 main and 103 supplementary pages, with clean final
LaTeX logs. The final committed snapshot is built and checked separately.

The current-authority suite passes 36 tests. PDF privacy verification examines
decoded page text and ordinary/XMP metadata and rejects embedded files; arbitrary
compressed bytes are not interpreted as Windows filenames. The GloFAS-scoped
shared-receipt refresher passes 12 tests. It permits exactly the reviewed 21
article-file additions and updates only the main/supplement/allowlist source
digests in the IND reporting receipt. Every scientific source/output pin and
the prior editorial-refresh record remain unchanged. This is shared-document
metadata maintenance, not another independent-study integration.

Both historical and current model-description guard fixtures remain active:
55 exposition and 87 statistical semantic mutations are rejected. Their live
checks also verify 352 protected scientific CSVs and 705 PriceFM files unchanged.
The Sections 5--7 presentation suite passes all 36 tests in the pinned PyMuPDF
1.26.5 environment, without optional skips. Historical common-window, MQ-overlay
and review-figure checks also pass. The old common-window test had conflated the
original renderer hash with the already approved IND-delegating renderer at
the pre-integration main; the revised test pins both identities and retains all
13 historical output and source hashes rather than modifying the old receipt.

The integration, article-snapshot, historical-review-draft and reviewed-direct-
reconciliation publication tests pass against disposable file-only remotes.
No production remote is used as a test. Superseded model/presentation guards
retain historical branches; the corrected branch additionally requires the
complete current authority rather than merely removing pending notices.

The isolated JOINT-v2 article fixture also copies the current GloFAS validator
when its approved authority is present. Its article-safe data are already in
the copied allowlist; the validator is a test dependency, not an Overleaf upload.
This fixture adjustment does not change any JOINT target, result or scientific
source hash. The combined harness requires R4.6.0 on the child-process PATH as
well as for the parent, and Python3.11 with PyYAML6.0.2; the QA environment also
provides pytest8.3.5 and PyMuPDF1.26.5. Environment failure receipts are retained
separately from source regressions.

The reader-focused guard retains both historical and corrected GloFAS text
versions (115 checks, 24 mutation rejections). The MQ nomenclature suite passes
17 tests, retaining all original source hashes while checking the approved
current issued-window aliases. Its selected-PDF inventory now includes four
corrected GloFAS figures and the three unchanged historical component figures,
in addition to the two simulation figures. Missing approval and a stale
issued-window table are rejected. These are test-consumer updates, not changes
to any simulation or application fit.
