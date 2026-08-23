# Independent validation canonical-gap v9 integration handoff

Date: 2026-08-23

Status: **READY_FOR_INTEGRATION**

## Ownership and scope

- Lane: independent single-quantile Q-DESN/DQLM validation only
- Codex transcript:
  `/home/jaguir26/.codex/sessions/2026/05/15/rollout-2026-05-15T18-06-50-019e2dad-9160-7421-a3ae-4c5b3b1410ca.jsonl`
- Validation worktree:
  `/data/jaguir26/local/src/exdqlm__wt__qdesn_canonical_gap_mcmc_v2_1p0p0`
- Validation branch: `validation/qdesn-canonical-gap-mcmc-v2-1.0.0`
- Validation branch HEAD: `c4f68b86877538ecbb9b090b7dd4edeb45efe257`
- Validation integration target: `validation/shared-fitforecast-v2-1.0.0`
- Shared target observed before handoff:
  `fba22d605039dcf5d48f59c7760fc01053685451`
- Article worktree:
  `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__independent_v9_integration_ready_20260823`
- Article branch: `work/independent-validation-v9-integration-ready-20260823`
- Article base: `origin/main` at
  `2d9bc8ccd0a55bc47dfb3934a7e477259d0de05e`
- Article payload commit:
  `3d12c9c660ff9c0ba961f7f3df57889d969fd982`
- Handoff commit: the branch tip containing this file

This handoff contains no joint-QDESN, PriceFM, GloFAS, application, package, or
validation-runtime change. It does not authorize this scientific lane to merge
or push either integration target.

## Frozen result

The canonical-gap campaign completed 176 of 176 jobs with no implementation
failure: 2 smoke, 4 calibration, 128 screen, 36 refinement, and 6 canonical
confirmation jobs. No campaign process or tmux session remains active. The
compact promotion packet contains 124 files (2.1 MB) and no `.rds`, `.rda`,
`.RData`, or fitted-model binary.

Four finite, strict, case-specific forecast improvements replace v8:

| Model and case | Criterion | v8 | v9 | Relative gain |
|---|---|---:|---:|---:|
| Q-DESN AL-RHS, Gaussian, p=0.05 | Forecast MAE | 8.410107 | 6.916594 | 17.8% |
| Q-DESN AL-RHS, Gaussian, p=0.05 | Forecast check loss | 1.220900 | 1.200170 | 1.7% |
| Q-DESN exAL-RHS, Gaussian mixture, p=0.50 | Forecast MAE | 2.562274 | 1.419645 | 44.6% |
| Q-DESN exAL-RHS, Gaussian mixture, p=0.50 | Forecast check loss | 5.610103 | 5.486730 | 2.2% |

No fit criterion changes. The promoted values are three-chain means with 5,000
burn-in and 20,000 retained iterations per chain. exAL uses
`M0_v_collapsed_support_logit`; AL uses `sigma_then_gamma`. Five supporting
chains have WARN and one has FAIL diagnostic status. Consistent with the frozen
metric-specific rule, diagnostics are disclosed but do not veto a finite strict
forecast improvement.

## Validation evidence

Primary handoff:

`validation/fitforecast_v2/docs/QDESN_CANONICAL_GAP_MCMC_V2_INTEGRATION_HANDOFF_2026-08-21.md`

Promotion packet:

`validation/fitforecast_v2/promotions/qdesn_dqlm_500obs_trainonly_article_v9_canonical_gap_20260821/`

Pinned hashes:

- Interface: `eb697b6f3e366581d158a41ecd2213761486be769b541439d2d862d840ea4b27`
- Promotion manifest: `b5a87a3b5a69ac36a1a16ee8a2638ca3d374ea1d6a80b6b72ba44901376a3993`
- Source ledger: `aefdd71842fc0ee56fdf34bed3dd739297be6f73c14b31999ee788263f5f52f2`
- Article delta: `37fa5a69d1047286201e444984f70d626da700b916b8e637b74fe1a8db5849b4`
- Chain evidence: `5341fa1df7a09609b5bb276ec9150637a3cd8185803947477b0d5df8f6228fb5`
- Promoted specifications: `bb614471227f04622ba55967c8633f265afdee5d942f913888463cefb4881a91`
- Rollback ledger: `bc094abef458831ed0d9b7e0d5850dd3493e6a121dd79ea3b3fb359399d4786d`

The validation branch is eight commits ahead of the observed shared target and
the shared target has no unique commit relative to it. The coordinator must
fetch again and recheck this ancestry before fast-forwarding.

## Article-safe payload

The payload contains exactly these 18 article-safe files:

```text
application/config/independent_validation_trainonly_v1.yaml
docs/implementation_notes/independent_validation_canonical_gap_v9_article_promotion_20260821.md
figures/independent_simulation/qdesn_mcmc_metric_envelope_heatmap.pdf
main.tex
qdesn-supplement.tex
scripts/build_independent_validation_trainonly_article.R
scripts/check_independent_validation_trainonly_article.R
tables/qdesn_validation_500obs_trainonly_summary.csv
tables/qdesn_validation_mcmc_figure_data.csv
tables/qdesn_validation_mcmc_figure_manifest.txt
tables/qdesn_validation_tt500_final_combined.tex
tables/qdesn_validation_tt500_final_gausmix.tex
tables/qdesn_validation_tt500_final_manifest.txt
tables/qdesn_validation_tt500_final_mcmc_gausmix.tex
tables/qdesn_validation_tt500_final_mcmc_normal.tex
tables/qdesn_validation_tt500_final_normal.tex
tables/qdesn_validation_tt500_final_summary.csv
tables/qdesn_validation_tt500_mcmc_current_best_manifest.txt
```

This branch was rebuilt from the latest article main available at preparation
time. It deliberately does not merge the older v9 article branch, because that
branch predates the manuscript's reader-facing prose cleanup. The new payload
retains the cleaned prose and adds one concise result paragraph to each
manuscript.

## Verification completed

- Standalone v9 verifier: PASS
  - 72 interface rows
  - 4 promoted forecast roles
  - 119 verified source-ledger rows
  - article-consumption and storage gates PASS
- Focused validation tests: 21 expectations passed
- Article builder and strict checker: PASS
  - 72 rows, 36 VB, 36 MCMC, 108 figure cells, 0 ridge rows
- Deterministic second regeneration: no unstaged difference
- `git diff --check`: PASS
- Main article: 40 pages, references and citations converged
- Supplement: 39 pages, references and citations converged
- Visual inspection: tables, boldface, heatmap, and supplement prose passed
- Pre-existing warnings outside changed lines:
  - main article: 4.78-point overfull box
  - supplement: 0.66-point overfull heading

Ignored compilation evidence:

`local_trackers/independent_validation_v9_integration_ready_20260823/compile_20260823_185010/`

## Required coordinator procedure

1. Fetch both repositories and verify that neither integration target moved in
   an incompatible way.
2. Fast-forward `validation/shared-fitforecast-v2-1.0.0` to validation commit
   `c4f68b86877538ecbb9b090b7dd4edeb45efe257`.
3. Run the standalone promotion verifier and the two focused validation tests
   from the updated shared checkout.
4. Merge this article branch into the latest Article-v2 `origin/main` through
   an explicit integration commit.
5. Run the article builder and checker without `--validation-root`; the default
   shared-validation checkout must resolve the same pinned v9 packet.
6. Recompile and visually inspect both manuscripts.
7. Publish the article-only snapshot through command-line Git to GitHub and
   direct Overleaf, then verify all remote hashes.

Do not publish validation runtime reports, local trackers, model binaries, or
files from another scientific lane. If article main has advanced, preserve its
newer prose and resolve only the files listed in the article-safe payload.

**READY_FOR_INTEGRATION**
